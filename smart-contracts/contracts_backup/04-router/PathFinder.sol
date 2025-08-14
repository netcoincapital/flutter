// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../01-core/AccessControl.sol";
import "../03-pool/PoolFactory.sol";
import "../03-pool/LaxcePool.sol";
import "../libraries/Constants.sol";
import "../libraries/TickMath.sol";
import "../libraries/FeeManager.sol";
import "../libraries/ReentrancyGuard.sol";

/**
 * @title PathFinder
 * @dev Provides optimal path finding for swaps across multiple pools
 * @dev View-only functions for off-chain and on-chain path calculation
 */
contract PathFinder is Pausable, LaxceAccessControl {
    using SafeCast for uint256;
    using ReentrancyGuard for ReentrancyGuard.ReentrancyData;

    // =========== CONSTANTS ===========
    uint256 public constant MAX_HOPS = 3;
    uint256 public constant MAX_POOLS_PER_PAIR = 10;
    uint256 public constant MIN_LIQUIDITY_THRESHOLD = 1000e18;
    uint256 public constant MAX_PRICE_IMPACT = 500; // 5%
    uint256 public constant CACHE_DURATION = 300; // 5 minutes

    // =========== STRUCTS ===========
    struct SwapPath {
        address[] tokens;
        uint24[] fees;
        address[] pools;
        uint256 expectedAmountOut;
        uint256 priceImpact;
        uint256 gasEstimate;
        bool isValid;
    }

    struct PoolInfo {
        address pool;
        address token0;
        address token1;
        uint24 fee;
        uint128 liquidity;
        uint160 sqrtPriceX96;
        int24 tick;
        uint256 lastUpdate;
    }

    struct PathRequest {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 maxHops;
        uint256 maxSlippage;
        bool exactInput;
    }

    struct PathCache {
        SwapPath[] paths;
        uint256 timestamp;
        bool isValid;
    }

    // =========== STATE VARIABLES ===========
    ReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    PoolFactory public immutable factory;
    
    // Pool information cache
    mapping(address => PoolInfo) public poolInfo;
    mapping(bytes32 => PathCache) private pathCache;
    
    // Token pair to pools mapping
    mapping(bytes32 => address[]) public poolsForPair;
    
    // Graph adjacency for tokens
    mapping(address => address[]) public connectedTokens;
    mapping(address => mapping(address => address[])) public tokenPairPools;
    
    // Configuration
    uint256 public cacheTimeout = CACHE_DURATION;
    uint256 public maxSlippageDefault = 50; // 0.5%
    bool public useCache = true;

    // =========== EVENTS ===========
    event PathFound(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 expectedAmountOut,
        uint256 hops
    );
    
    event PoolInfoUpdated(
        address indexed pool,
        uint128 liquidity,
        uint160 sqrtPriceX96
    );
    
    event CacheUpdated(bytes32 indexed key, uint256 pathCount);
    event ConfigurationUpdated(uint256 cacheTimeout, uint256 maxSlippage, bool useCache);

    // =========== ERRORS ===========
    error PathFinder__InvalidTokens();
    error PathFinder__NoPathFound();
    error PathFinder__ExcessiveHops();
    error PathFinder__InsufficientLiquidity();
    error PathFinder__ExcessivePriceImpact();
    error PathFinder__InvalidPool();
    error PathFinder__StaleCache();

    // =========== MODIFIERS ===========
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }

    modifier validTokens(address tokenA, address tokenB) {
        if (tokenA == address(0) || tokenB == address(0) || tokenA == tokenB) {
            revert PathFinder__InvalidTokens();
        }
        _;
    }

    // =========== CONSTRUCTOR ===========
    constructor(address _factory) {
        if (_factory == address(0)) revert PathFinder__InvalidTokens();
        
        factory = PoolFactory(_factory);
        _reentrancyGuard.initialize();
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    // =========== MAIN PATH FINDING FUNCTIONS ===========

    /**
     * @dev Find optimal swap path for exact input
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @param maxSlippage Maximum allowed slippage (basis points)
     * @return path Optimal swap path
     */
    function findOptimalPath(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 maxSlippage
    ) external view returns (SwapPath memory path) {
        return _findOptimalPath(
            PathRequest({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                maxHops: MAX_HOPS,
                maxSlippage: maxSlippage,
                exactInput: true
            })
        );
    }

    /**
     * @dev Find multiple swap paths and return best options
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @param pathCount Number of paths to return
     * @return paths Array of swap paths sorted by efficiency
     */
    function findMultiplePaths(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 pathCount
    ) external view returns (SwapPath[] memory paths) {
        PathRequest memory request = PathRequest({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            maxHops: MAX_HOPS,
            maxSlippage: maxSlippageDefault,
            exactInput: true
        });

        return _findMultiplePaths(request, pathCount);
    }

    /**
     * @dev Get quote for exact input swap
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @return amountOut Expected output amount
     * @return priceImpact Price impact in basis points
     * @return path Optimal path used
     */
    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view validTokens(tokenIn, tokenOut) returns (
        uint256 amountOut,
        uint256 priceImpact,
        SwapPath memory path
    ) {
        path = _findOptimalPath(
            PathRequest({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                maxHops: MAX_HOPS,
                maxSlippage: maxSlippageDefault,
                exactInput: true
            })
        );

        if (!path.isValid) {
            revert PathFinder__NoPathFound();
        }

        return (path.expectedAmountOut, path.priceImpact, path);
    }

    /**
     * @dev Get quote for exact output swap
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountOut Desired output amount
     * @return amountIn Required input amount
     * @return priceImpact Price impact in basis points
     * @return path Optimal path used
     */
    function getAmountIn(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view validTokens(tokenIn, tokenOut) returns (
        uint256 amountIn,
        uint256 priceImpact,
        SwapPath memory path
    ) {
        path = _findOptimalPath(
            PathRequest({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountOut,
                maxHops: MAX_HOPS,
                maxSlippage: maxSlippageDefault,
                exactInput: false
            })
        );

        if (!path.isValid) {
            revert PathFinder__NoPathFound();
        }

        return (path.expectedAmountOut, path.priceImpact, path);
    }

    // =========== INTERNAL PATH FINDING ===========

    /**
     * @dev Internal function to find optimal path
     */
    function _findOptimalPath(PathRequest memory request) 
        internal 
        view 
        returns (SwapPath memory) 
    {
        // Check cache first
        if (useCache) {
            bytes32 cacheKey = _getCacheKey(request);
            PathCache memory cached = pathCache[cacheKey];
            
            if (cached.isValid && block.timestamp <= cached.timestamp + cacheTimeout) {
                if (cached.paths.length > 0) {
                    return cached.paths[0];
                }
            }
        }

        // Direct path (single hop)
        SwapPath memory directPath = _getDirectPath(request);
        
        // Multi-hop paths
        SwapPath[] memory multiHopPaths = _getMultiHopPaths(request);
        
        // Find best path
        SwapPath memory bestPath = directPath;
        
        for (uint256 i = 0; i < multiHopPaths.length; i++) {
            if (_isPathBetter(multiHopPaths[i], bestPath)) {
                bestPath = multiHopPaths[i];
            }
        }

        return bestPath;
    }

    /**
     * @dev Find multiple paths for comparison
     */
    function _findMultiplePaths(PathRequest memory request, uint256 pathCount) 
        internal 
        view 
        returns (SwapPath[] memory) 
    {
        SwapPath[] memory allPaths = new SwapPath[](pathCount);
        uint256 foundPaths = 0;

        // Direct path
        SwapPath memory directPath = _getDirectPath(request);
        if (directPath.isValid && foundPaths < pathCount) {
            allPaths[foundPaths] = directPath;
            foundPaths++;
        }

        // Multi-hop paths
        SwapPath[] memory multiHopPaths = _getMultiHopPaths(request);
        
        for (uint256 i = 0; i < multiHopPaths.length && foundPaths < pathCount; i++) {
            if (multiHopPaths[i].isValid) {
                allPaths[foundPaths] = multiHopPaths[i];
                foundPaths++;
            }
        }

        // Sort paths by efficiency
        _sortPathsByEfficiency(allPaths, foundPaths);

        // Resize array to actual found paths
        SwapPath[] memory result = new SwapPath[](foundPaths);
        for (uint256 i = 0; i < foundPaths; i++) {
            result[i] = allPaths[i];
        }

        return result;
    }

    /**
     * @dev Get direct swap path (single pool)
     */
    function _getDirectPath(PathRequest memory request) 
        internal 
        view 
        returns (SwapPath memory path) 
    {
        bytes32 pairKey = _getPairKey(request.tokenIn, request.tokenOut);
        address[] memory pools = poolsForPair[pairKey];

        SwapPath memory bestPath;
        uint256 bestAmountOut = 0;

        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i] == address(0)) continue;

            PoolInfo memory info = poolInfo[pools[i]];
            if (info.liquidity < MIN_LIQUIDITY_THRESHOLD) continue;

            (uint256 amountOut, uint256 priceImpact) = _calculateSwapAmount(
                pools[i],
                request.tokenIn,
                request.tokenOut,
                request.amountIn,
                request.exactInput
            );

            if (amountOut > bestAmountOut && priceImpact <= request.maxSlippage) {
                bestAmountOut = amountOut;
                
                address[] memory tokens = new address[](2);
                tokens[0] = request.tokenIn;
                tokens[1] = request.tokenOut;
                
                uint24[] memory fees = new uint24[](1);
                fees[0] = info.fee;
                
                address[] memory pathPools = new address[](1);
                pathPools[0] = pools[i];

                bestPath = SwapPath({
                    tokens: tokens,
                    fees: fees,
                    pools: pathPools,
                    expectedAmountOut: amountOut,
                    priceImpact: priceImpact,
                    gasEstimate: _estimateGasForPath(1),
                    isValid: true
                });
            }
        }

        return bestPath;
    }

    /**
     * @dev Get multi-hop swap paths
     */
    function _getMultiHopPaths(PathRequest memory request) 
        internal 
        view 
        returns (SwapPath[] memory) 
    {
        SwapPath[] memory paths = new SwapPath[](10); // Max 10 multi-hop paths
        uint256 pathCount = 0;

        address[] memory intermediates = connectedTokens[request.tokenIn];
        
        for (uint256 i = 0; i < intermediates.length && pathCount < 10; i++) {
            address intermediate = intermediates[i];
            if (intermediate == request.tokenOut) continue;

            // Check if intermediate connects to output token
            address[] memory finalPools = tokenPairPools[intermediate][request.tokenOut];
            if (finalPools.length == 0) continue;

            // Try 2-hop path
            SwapPath memory twoHopPath = _getTwoHopPath(request, intermediate);
            if (twoHopPath.isValid) {
                paths[pathCount] = twoHopPath;
                pathCount++;
            }

            // Try 3-hop paths if allowed
            if (request.maxHops >= 3) {
                SwapPath[] memory threeHopPaths = _getThreeHopPaths(request, intermediate);
                for (uint256 j = 0; j < threeHopPaths.length && pathCount < 10; j++) {
                    if (threeHopPaths[j].isValid) {
                        paths[pathCount] = threeHopPaths[j];
                        pathCount++;
                    }
                }
            }
        }

        // Resize array
        SwapPath[] memory result = new SwapPath[](pathCount);
        for (uint256 i = 0; i < pathCount; i++) {
            result[i] = paths[i];
        }

        return result;
    }

    /**
     * @dev Get 2-hop swap path
     */
    function _getTwoHopPath(PathRequest memory request, address intermediate) 
        internal 
        view 
        returns (SwapPath memory) 
    {
        // Find best pool for first hop
        address[] memory firstHopPools = tokenPairPools[request.tokenIn][intermediate];
        if (firstHopPools.length == 0) {
            return SwapPath({
                tokens: new address[](0),
                fees: new uint24[](0),
                pools: new address[](0),
                expectedAmountOut: 0,
                priceImpact: 0,
                gasEstimate: 0,
                isValid: false
            });
        }

        // Find best pool for second hop  
        address[] memory secondHopPools = tokenPairPools[intermediate][request.tokenOut];
        if (secondHopPools.length == 0) {
            return SwapPath({
                tokens: new address[](0),
                fees: new uint24[](0),
                pools: new address[](0),
                expectedAmountOut: 0,
                priceImpact: 0,
                gasEstimate: 0,
                isValid: false
            });
        }

        address bestFirstPool = _getBestPoolForPair(firstHopPools);
        address bestSecondPool = _getBestPoolForPair(secondHopPools);

        if (bestFirstPool == address(0) || bestSecondPool == address(0)) {
            return SwapPath({
                tokens: new address[](0),
                fees: new uint24[](0),
                pools: new address[](0),
                expectedAmountOut: 0,
                priceImpact: 0,
                gasEstimate: 0,
                isValid: false
            });
        }

        // Calculate amounts
        (uint256 intermediateAmount, uint256 firstPriceImpact) = _calculateSwapAmount(
            bestFirstPool,
            request.tokenIn,
            intermediate,
            request.amountIn,
            true
        );

        (uint256 finalAmount, uint256 secondPriceImpact) = _calculateSwapAmount(
            bestSecondPool,
            intermediate,
            request.tokenOut,
            intermediateAmount,
            true
        );

        uint256 totalPriceImpact = firstPriceImpact + secondPriceImpact;

        if (totalPriceImpact > request.maxSlippage) {
            return SwapPath({
                tokens: new address[](0),
                fees: new uint24[](0),
                pools: new address[](0),
                expectedAmountOut: 0,
                priceImpact: 0,
                gasEstimate: 0,
                isValid: false
            });
        }

        // Build path
        address[] memory tokens = new address[](3);
        tokens[0] = request.tokenIn;
        tokens[1] = intermediate;
        tokens[2] = request.tokenOut;

        uint24[] memory fees = new uint24[](2);
        fees[0] = poolInfo[bestFirstPool].fee;
        fees[1] = poolInfo[bestSecondPool].fee;

        address[] memory pools = new address[](2);
        pools[0] = bestFirstPool;
        pools[1] = bestSecondPool;

        return SwapPath({
            tokens: tokens,
            fees: fees,
            pools: pools,
            expectedAmountOut: finalAmount,
            priceImpact: totalPriceImpact,
            gasEstimate: _estimateGasForPath(2),
            isValid: true
        });
    }

    /**
     * @dev Get 3-hop swap paths
     */
    function _getThreeHopPaths(PathRequest memory request, address firstIntermediate) 
        internal 
        view 
        returns (SwapPath[] memory) 
    {
        SwapPath[] memory paths = new SwapPath[](5); // Max 5 three-hop paths
        uint256 pathCount = 0;

        address[] memory secondIntermediates = connectedTokens[firstIntermediate];
        
        for (uint256 i = 0; i < secondIntermediates.length && pathCount < 5; i++) {
            address secondIntermediate = secondIntermediates[i];
            if (secondIntermediate == request.tokenIn || 
                secondIntermediate == request.tokenOut || 
                secondIntermediate == firstIntermediate) {
                continue;
            }

            // Check if path exists
            address[] memory finalPools = tokenPairPools[secondIntermediate][request.tokenOut];
            if (finalPools.length == 0) continue;

            SwapPath memory threeHopPath = _getThreeHopPath(request, firstIntermediate, secondIntermediate);
            if (threeHopPath.isValid) {
                paths[pathCount] = threeHopPath;
                pathCount++;
            }
        }

        // Resize array
        SwapPath[] memory result = new SwapPath[](pathCount);
        for (uint256 i = 0; i < pathCount; i++) {
            result[i] = paths[i];
        }

        return result;
    }

    /**
     * @dev Get specific 3-hop path
     */
    function _getThreeHopPath(
        PathRequest memory request, 
        address firstIntermediate, 
        address secondIntermediate
    ) internal view returns (SwapPath memory) {
        // Get best pools for each hop
        address[] memory firstPools = tokenPairPools[request.tokenIn][firstIntermediate];
        address[] memory secondPools = tokenPairPools[firstIntermediate][secondIntermediate];
        address[] memory thirdPools = tokenPairPools[secondIntermediate][request.tokenOut];

        if (firstPools.length == 0 || secondPools.length == 0 || thirdPools.length == 0) {
            return SwapPath({
                tokens: new address[](0),
                fees: new uint24[](0),
                pools: new address[](0),
                expectedAmountOut: 0,
                priceImpact: 0,
                gasEstimate: 0,
                isValid: false
            });
        }

        address bestFirstPool = _getBestPoolForPair(firstPools);
        address bestSecondPool = _getBestPoolForPair(secondPools);
        address bestThirdPool = _getBestPoolForPair(thirdPools);

        if (bestFirstPool == address(0) || bestSecondPool == address(0) || bestThirdPool == address(0)) {
            return SwapPath({
                tokens: new address[](0),
                fees: new uint24[](0),
                pools: new address[](0),
                expectedAmountOut: 0,
                priceImpact: 0,
                gasEstimate: 0,
                isValid: false
            });
        }

        // Calculate amounts through the path
        (uint256 firstIntermediateAmount, uint256 firstPriceImpact) = _calculateSwapAmount(
            bestFirstPool,
            request.tokenIn,
            firstIntermediate,
            request.amountIn,
            true
        );

        (uint256 secondIntermediateAmount, uint256 secondPriceImpact) = _calculateSwapAmount(
            bestSecondPool,
            firstIntermediate,
            secondIntermediate,
            firstIntermediateAmount,
            true
        );

        (uint256 finalAmount, uint256 thirdPriceImpact) = _calculateSwapAmount(
            bestThirdPool,
            secondIntermediate,
            request.tokenOut,
            secondIntermediateAmount,
            true
        );

        uint256 totalPriceImpact = firstPriceImpact + secondPriceImpact + thirdPriceImpact;

        if (totalPriceImpact > request.maxSlippage) {
            return SwapPath({
                tokens: new address[](0),
                fees: new uint24[](0),
                pools: new address[](0),
                expectedAmountOut: 0,
                priceImpact: 0,
                gasEstimate: 0,
                isValid: false
            });
        }

        // Build path
        address[] memory tokens = new address[](4);
        tokens[0] = request.tokenIn;
        tokens[1] = firstIntermediate;
        tokens[2] = secondIntermediate;
        tokens[3] = request.tokenOut;

        uint24[] memory fees = new uint24[](3);
        fees[0] = poolInfo[bestFirstPool].fee;
        fees[1] = poolInfo[bestSecondPool].fee;
        fees[2] = poolInfo[bestThirdPool].fee;

        address[] memory pools = new address[](3);
        pools[0] = bestFirstPool;
        pools[1] = bestSecondPool;
        pools[2] = bestThirdPool;

        return SwapPath({
            tokens: tokens,
            fees: fees,
            pools: pools,
            expectedAmountOut: finalAmount,
            priceImpact: totalPriceImpact,
            gasEstimate: _estimateGasForPath(3),
            isValid: true
        });
    }

    // =========== HELPER FUNCTIONS ===========

    /**
     * @dev Calculate swap amount for a specific pool
     */
    function _calculateSwapAmount(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bool exactInput
    ) internal view returns (uint256 amountOut, uint256 priceImpact) {
        if (pool == address(0)) return (0, 0);

        try LaxcePool(pool).slot0() returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        ) {
            // Simple calculation - in real implementation this would be more complex
            // Using basic AMM formula for estimation
            uint128 liquidity = LaxcePool(pool).liquidity();
            
            if (liquidity == 0) return (0, 0);

            // Calculate price impact
            uint256 liquidityValue = uint256(liquidity);
            priceImpact = (amountIn * 10000) / liquidityValue;
            
            if (priceImpact > MAX_PRICE_IMPACT) {
                return (0, priceImpact);
            }

            // Simple output calculation (should use actual Uniswap V3 math)
            PoolInfo memory info = poolInfo[pool];
            uint256 feeAmount = (amountIn * info.fee) / 1000000;
            amountOut = amountIn - feeAmount;

            // Apply some liquidity-based calculation
            amountOut = (amountOut * 995) / 1000; // 0.5% additional slippage simulation

        } catch {
            return (0, 0);
        }
    }

    /**
     * @dev Get best pool from array based on liquidity
     */
    function _getBestPoolForPair(address[] memory pools) 
        internal 
        view 
        returns (address bestPool) 
    {
        uint128 bestLiquidity = 0;
        
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i] == address(0)) continue;
            
            PoolInfo memory info = poolInfo[pools[i]];
            if (info.liquidity > bestLiquidity) {
                bestLiquidity = info.liquidity;
                bestPool = pools[i];
            }
        }
    }

    /**
     * @dev Check if path A is better than path B
     */
    function _isPathBetter(SwapPath memory pathA, SwapPath memory pathB) 
        internal 
        pure 
        returns (bool) 
    {
        if (!pathA.isValid) return false;
        if (!pathB.isValid) return true;

        // Primary: Higher output amount
        if (pathA.expectedAmountOut != pathB.expectedAmountOut) {
            return pathA.expectedAmountOut > pathB.expectedAmountOut;
        }

        // Secondary: Lower price impact
        if (pathA.priceImpact != pathB.priceImpact) {
            return pathA.priceImpact < pathB.priceImpact;
        }

        // Tertiary: Lower gas cost
        return pathA.gasEstimate < pathB.gasEstimate;
    }

    /**
     * @dev Sort paths by efficiency
     */
    function _sortPathsByEfficiency(SwapPath[] memory paths, uint256 length) 
        internal 
        pure 
    {
        for (uint256 i = 0; i < length - 1; i++) {
            for (uint256 j = 0; j < length - i - 1; j++) {
                if (_isPathBetter(paths[j + 1], paths[j])) {
                    SwapPath memory temp = paths[j];
                    paths[j] = paths[j + 1];
                    paths[j + 1] = temp;
                }
            }
        }
    }

    /**
     * @dev Estimate gas cost for path
     */
    function _estimateGasForPath(uint256 hops) internal pure returns (uint256) {
        return 150000 + (hops * 50000); // Base gas + per hop
    }

    /**
     * @dev Get cache key for path request
     */
    function _getCacheKey(PathRequest memory request) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            request.tokenIn,
            request.tokenOut,
            request.amountIn,
            request.maxHops,
            request.exactInput
        ));
    }

    /**
     * @dev Get pair key for token pair
     */
    function _getPairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(token0, token1));
    }

    // =========== ADMIN FUNCTIONS ===========

    /**
     * @dev Update pool information
     */
    function updatePoolInfo(address pool) external nonReentrant {
        if (pool == address(0)) revert PathFinder__InvalidPool();

        try LaxcePool(pool).slot0() returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16,
            uint16,
            uint16,
            uint8,
            bool
        ) {
            address token0 = LaxcePool(pool).token0();
            address token1 = LaxcePool(pool).token1();
            uint24 fee = LaxcePool(pool).fee();
            uint128 liquidity = LaxcePool(pool).liquidity();

            poolInfo[pool] = PoolInfo({
                pool: pool,
                token0: token0,
                token1: token1,
                fee: fee,
                liquidity: liquidity,
                sqrtPriceX96: sqrtPriceX96,
                tick: tick,
                lastUpdate: block.timestamp
            });

            // Update token connections
            _updateTokenConnections(token0, token1, pool);

            emit PoolInfoUpdated(pool, liquidity, sqrtPriceX96);

        } catch {
            revert PathFinder__InvalidPool();
        }
    }

    /**
     * @dev Update token connections for pathfinding
     */
    function _updateTokenConnections(address token0, address token1, address pool) internal {
        // Add to connected tokens
        bool token0HasToken1 = false;
        bool token1HasToken0 = false;

        for (uint256 i = 0; i < connectedTokens[token0].length; i++) {
            if (connectedTokens[token0][i] == token1) {
                token0HasToken1 = true;
                break;
            }
        }

        for (uint256 i = 0; i < connectedTokens[token1].length; i++) {
            if (connectedTokens[token1][i] == token0) {
                token1HasToken0 = true;
                break;
            }
        }

        if (!token0HasToken1) {
            connectedTokens[token0].push(token1);
        }
        if (!token1HasToken0) {
            connectedTokens[token1].push(token0);
        }

        // Add to token pair pools
        tokenPairPools[token0][token1].push(pool);
        tokenPairPools[token1][token0].push(pool);

        // Add to pools for pair
        bytes32 pairKey = _getPairKey(token0, token1);
        poolsForPair[pairKey].push(pool);
    }

    /**
     * @dev Batch update multiple pools
     */
    function batchUpdatePoolInfo(address[] calldata pools) 
        external 
        nonReentrant 
        onlyRole(OPERATOR_ROLE) 
    {
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i] != address(0)) {
                try this.updatePoolInfo(pools[i]) {
                    // Success
                } catch {
                    // Skip failed pools
                    continue;
                }
            }
        }
    }

    /**
     * @dev Set configuration parameters
     */
    function setConfiguration(
        uint256 _cacheTimeout,
        uint256 _maxSlippage,
        bool _useCache
    ) external onlyRole(ADMIN_ROLE) {
        if (_cacheTimeout > 3600) revert PathFinder__InvalidTokens(); // Max 1 hour
        if (_maxSlippage > 1000) revert PathFinder__InvalidTokens(); // Max 10%

        cacheTimeout = _cacheTimeout;
        maxSlippageDefault = _maxSlippage;
        useCache = _useCache;

        emit ConfigurationUpdated(_cacheTimeout, _maxSlippage, _useCache);
    }

    /**
     * @dev Clear path cache
     */
    function clearCache() external onlyRole(OPERATOR_ROLE) {
        // Note: In practice, you'd need to implement cache clearing
        // For now, we'll just emit an event
        emit CacheUpdated(bytes32(0), 0);
    }

    /**
     * @dev Emergency pause
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // =========== VIEW FUNCTIONS ===========

    /**
     * @dev Get all pools for a token pair
     */
    function getPoolsForPair(address tokenA, address tokenB) 
        external 
        view 
        returns (address[] memory) 
    {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        return poolsForPair[pairKey];
    }

    /**
     * @dev Get connected tokens for a token
     */
    function getConnectedTokens(address token) 
        external 
        view 
        returns (address[] memory) 
    {
        return connectedTokens[token];
    }

    /**
     * @dev Check if path exists between tokens
     */
    function hasPath(address tokenIn, address tokenOut, uint256 maxHops) 
        external 
        view 
        returns (bool) 
    {
        if (tokenIn == tokenOut) return true;

        // Check direct path
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        if (poolsForPair[pairKey].length > 0) return true;

        // Check multi-hop paths
        if (maxHops >= 2) {
            address[] memory intermediates = connectedTokens[tokenIn];
            for (uint256 i = 0; i < intermediates.length; i++) {
                if (intermediates[i] == tokenOut) continue;
                
                bytes32 intermediatePairKey = _getPairKey(intermediates[i], tokenOut);
                if (poolsForPair[intermediatePairKey].length > 0) {
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * @dev Get pool statistics
     */
    function getPoolStats(address pool) 
        external 
        view 
        returns (
            uint128 liquidity,
            uint160 sqrtPriceX96,
            int24 tick,
            uint256 lastUpdate
        ) 
    {
        PoolInfo memory info = poolInfo[pool];
        return (info.liquidity, info.sqrtPriceX96, info.tick, info.lastUpdate);
    }
} 