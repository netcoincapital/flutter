// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "../01-core/AccessControl.sol";
import "../02-token/PositionNFT.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/TickMath.sol";
import "../libraries/Interfaces.sol";
import "../libraries/FullMath.sol";
import "../libraries/SqrtPriceMath.sol";
import "../libraries/SwapMath.sol";
import "./LaxcePool.sol";
import "./PoolFactory.sol";

/**
 * @title PoolManager
 * @dev مدیریت positions و liquidity operations
 * @notice این کانترکت واسطه بین کاربران و pools است
 */
contract PoolManager is Pausable, LaxceAccessControl, Multicall {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using ReentrancyGuard for ReentrancyGuard.ReentrancyData;
    
    // ==================== CONSTANTS ====================
    
    /// @dev deadline پیش‌فرض (30 دقیقه)
    uint256 public constant DEFAULT_DEADLINE = 30 minutes;
    
    /// @dev حداکثر slippage (50%)
    uint256 public constant MAX_SLIPPAGE = 5000;
    
    /// @dev حداقل slippage (0.1%)
    uint256 public constant MIN_SLIPPAGE = 10;
    
    // ==================== STRUCTS ====================
    
    /// @dev پارامترهای mint
    struct MintParams {
        address token0;                 // آدرس توکن اول
        address token1;                 // آدرس توکن دوم
        uint24 fee;                     // کارمزد pool
        int24 tickLower;                // tick پایین
        int24 tickUpper;                // tick بالا
        uint256 amount0Desired;         // مقدار مطلوب توکن 0
        uint256 amount1Desired;         // مقدار مطلوب توکن 1
        uint256 amount0Min;             // حداقل توکن 0
        uint256 amount1Min;             // حداقل توکن 1
        address recipient;              // دریافت‌کننده NFT
        uint256 deadline;               // deadline
    }
    
    /// @dev پارامترهای increase liquidity
    struct IncreaseLiquidityParams {
        uint256 tokenId;                // شناسه NFT
        uint256 amount0Desired;         // مقدار مطلوب توکن 0
        uint256 amount1Desired;         // مقدار مطلوب توکن 1
        uint256 amount0Min;             // حداقل توکن 0
        uint256 amount1Min;             // حداقل توکن 1
        uint256 deadline;               // deadline
    }
    
    /// @dev پارامترهای decrease liquidity
    struct DecreaseLiquidityParams {
        uint256 tokenId;                // شناسه NFT
        uint128 liquidity;              // مقدار liquidity برای کاهش
        uint256 amount0Min;             // حداقل توکن 0
        uint256 amount1Min;             // حداقل توکن 1
        uint256 deadline;               // deadline
    }
    
    /// @dev پارامترهای collect
    struct CollectParams {
        uint256 tokenId;                // شناسه NFT
        address recipient;              // دریافت‌کننده
        uint128 amount0Max;             // حداکثر توکن 0
        uint128 amount1Max;             // حداکثر توکن 1
    }
    
    /// @dev اطلاعات position
    struct PositionInfo {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev محافظت از reentrancy
    ReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    /// @dev Pool Factory
    PoolFactory public immutable factory;
    
    /// @dev Position NFT
    PositionNFT public immutable positionNFT;
    
    /// @dev WETH address
    address public immutable WETH9;
    
    /// @dev mapping cached pool addresses
    mapping(bytes32 => address) private _cachedPools;
    
    /// @dev mapping fee collector
    mapping(uint256 => address) public feeCollectors;
    
    /// @dev slippage پیش‌فرض
    uint256 public defaultSlippage = 500; // 5%
    
    /// @dev آیا auto compound فعال است
    bool public autoCompoundEnabled = true;
    
    /// @dev minimum liquidity برای auto compound
    uint256 public minLiquidityForAutoCompound = 1000 * Constants.DECIMAL_BASE;
    
    // ==================== EVENTS ====================
    
    event IncreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    
    event DecreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    
    event Collect(
        uint256 indexed tokenId,
        address recipient,
        uint256 amount0,
        uint256 amount1
    );
    
    event AutoCompound(
        uint256 indexed tokenId,
        uint128 liquidityAdded,
        uint256 amount0Used,
        uint256 amount1Used
    );
    
    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event AutoCompoundToggled(bool enabled);
    event FeeCollectorSet(uint256 indexed tokenId, address collector);
    
    // ==================== ERRORS ====================
    
    error PoolManager__DeadlineExpired();
    error PoolManager__InsufficientAmount();
    error PoolManager__InvalidSlippage();
    error PoolManager__PoolNotExists();
    error PoolManager__NotAuthorized();
    error PoolManager__ZeroLiquidity();
    error PoolManager__InvalidTicks();
    error PoolManager__ZeroAddress();
    error PoolManager__InsufficientFees();
    
    // ==================== MODIFIERS ====================
    
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }
    
    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert PoolManager__DeadlineExpired();
        _;
    }
    
    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(
        address _factory,
        address _positionNFT,
        address _WETH9
    ) {
        if (_factory == address(0)) revert PoolManager__ZeroAddress();
        if (_positionNFT == address(0)) revert PoolManager__ZeroAddress();
        if (_WETH9 == address(0)) revert PoolManager__ZeroAddress();
        
        factory = PoolFactory(_factory);
        positionNFT = PositionNFT(_positionNFT);
        WETH9 = _WETH9;
        
        // مقداردهی اولیه reentrancy guard
        _reentrancyGuard.initialize();
    }
    
    // ==================== POSITION MANAGEMENT ====================
    
    /**
     * @dev mint کردن position جدید
     * @param params پارامترهای mint
     * @return tokenId شناسه NFT
     * @return liquidity مقدار liquidity اضافه شده
     * @return amount0 مقدار واقعی توکن 0
     * @return amount1 مقدار واقعی توکن 1
     */
    function mint(MintParams calldata params)
        external
        payable
        nonReentrant
        checkDeadline(params.deadline)
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        LaxcePool pool = LaxcePool(_getPool(params.token0, params.token1, params.fee));
        
        // محاسبه liquidity
        liquidity = _getLiquidityForAmounts(
            pool,
            params.tickLower,
            params.tickUpper,
            params.amount0Desired,
            params.amount1Desired
        );
        
        if (liquidity == 0) revert PoolManager__ZeroLiquidity();
        
        // mint NFT
        tokenId = positionNFT.mint(
            params.recipient,
            params.token0,
            params.token1,
            params.fee,
            params.tickLower,
            params.tickUpper,
            liquidity,
            0 // default expiry
        );
        
        // add liquidity به pool
        (amount0, amount1) = pool.mint(
            address(this),
            params.tickLower,
            params.tickUpper,
            liquidity,
            abi.encode(
                MintCallbackData({
                    token0: params.token0,
                    token1: params.token1,
                    fee: params.fee,
                    payer: msg.sender
                })
            )
        );
        
        // بررسی slippage
        if (amount0 < params.amount0Min || amount1 < params.amount1Min) {
            revert PoolManager__InsufficientAmount();
        }
        
        emit IncreaseLiquidity(tokenId, liquidity, amount0, amount1);
    }
    
    /**
     * @dev افزایش liquidity position
     * @param params پارامترهای increase liquidity
     * @return liquidity مقدار liquidity اضافه شده
     * @return amount0 مقدار توکن 0
     * @return amount1 مقدار توکن 1
     */
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        nonReentrant
        isAuthorizedForToken(params.tokenId)
        checkDeadline(params.deadline)
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        PositionNFT.Position memory position = positionNFT.getPosition(params.tokenId);
        
        LaxcePool pool = LaxcePool(_getPool(position.token0, position.token1, position.fee));
        
        // محاسبه liquidity
        liquidity = _getLiquidityForAmounts(
            pool,
            position.tickLower,
            position.tickUpper,
            params.amount0Desired,
            params.amount1Desired
        );
        
        if (liquidity == 0) revert PoolManager__ZeroLiquidity();
        
        // add liquidity
        (amount0, amount1) = pool.mint(
            address(this),
            position.tickLower,
            position.tickUpper,
            liquidity,
            abi.encode(
                MintCallbackData({
                    token0: position.token0,
                    token1: position.token1,
                    fee: position.fee,
                    payer: msg.sender
                })
            )
        );
        
        // بررسی slippage
        if (amount0 < params.amount0Min || amount1 < params.amount1Min) {
            revert PoolManager__InsufficientAmount();
        }
        
        // به‌روزرسانی NFT
        positionNFT.updatePosition(
            params.tokenId,
            int128(liquidity),
            0,
            0
        );
        
        emit IncreaseLiquidity(params.tokenId, liquidity, amount0, amount1);
    }
    
    /**
     * @dev کاهش liquidity position
     * @param params پارامترهای decrease liquidity
     * @return amount0 مقدار توکن 0
     * @return amount1 مقدار توکن 1
     */
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        nonReentrant
        isAuthorizedForToken(params.tokenId)
        checkDeadline(params.deadline)
        returns (uint256 amount0, uint256 amount1)
    {
        if (params.liquidity == 0) revert PoolManager__ZeroLiquidity();
        
        PositionNFT.Position memory position = positionNFT.getPosition(params.tokenId);
        
        LaxcePool pool = LaxcePool(_getPool(position.token0, position.token1, position.fee));
        
        // burn liquidity
        (amount0, amount1) = pool.burn(
            position.tickLower,
            position.tickUpper,
            params.liquidity
        );
        
        // بررسی slippage
        if (amount0 < params.amount0Min || amount1 < params.amount1Min) {
            revert PoolManager__InsufficientAmount();
        }
        
        // به‌روزرسانی NFT
        positionNFT.updatePosition(
            params.tokenId,
            -int128(params.liquidity),
            0,
            0
        );
        
        emit DecreaseLiquidity(params.tokenId, params.liquidity, amount0, amount1);
    }
    
    /**
     * @dev collect کردن fees
     * @param params پارامترهای collect
     * @return amount0 مقدار توکن 0
     * @return amount1 مقدار توکن 1
     */
    function collect(CollectParams calldata params)
        external
        nonReentrant
        isAuthorizedForToken(params.tokenId)
        returns (uint256 amount0, uint256 amount1)
    {
        PositionNFT.Position memory position = positionNFT.getPosition(params.tokenId);
        
        LaxcePool pool = LaxcePool(_getPool(position.token0, position.token1, position.fee));
        
        // collect از pool
        (uint128 amount0Collected, uint128 amount1Collected) = pool.collect(
            params.recipient,
            position.tickLower,
            position.tickUpper,
            params.amount0Max,
            params.amount1Max
        );
        
        amount0 = amount0Collected;
        amount1 = amount1Collected;
        
        // collect از NFT
        (uint256 nftAmount0, uint256 nftAmount1) = positionNFT.collectFees(
            params.tokenId,
            params.recipient
        );
        
        amount0 = amount0.add(nftAmount0);
        amount1 = amount1.add(nftAmount1);
        
        emit Collect(params.tokenId, params.recipient, amount0, amount1);
    }
    
    /**
     * @dev burn کردن position
     * @param tokenId شناسه NFT
     */
    function burn(uint256 tokenId)
        external
        nonReentrant
        isAuthorizedForToken(tokenId)
    {
        PositionNFT.Position memory position = positionNFT.getPosition(tokenId);
        
        require(position.liquidity == 0, "Not cleared");
        
        positionNFT.burn(tokenId);
    }
    
    // ==================== AUTO COMPOUND ====================
    
    /**
     * @dev auto compound fees به liquidity
     * @param tokenId شناسه NFT
     * @return liquidityAdded مقدار liquidity اضافه شده
     */
    function autoCompound(uint256 tokenId)
        external
        nonReentrant
        isAuthorizedForToken(tokenId)
        returns (uint128 liquidityAdded)
    {
        if (!autoCompoundEnabled) return 0;
        
        PositionNFT.Position memory position = positionNFT.getPosition(tokenId);
        
        // collect fees
        (uint256 amount0, uint256 amount1) = collect(
            CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        
        // بررسی حد minimum
        if (amount0.add(amount1) < minLiquidityForAutoCompound) {
            return 0;
        }
        
        LaxcePool pool = LaxcePool(_getPool(position.token0, position.token1, position.fee));
        
        // محاسبه liquidity جدید
        liquidityAdded = _getLiquidityForAmounts(
            pool,
            position.tickLower,
            position.tickUpper,
            amount0,
            amount1
        );
        
        if (liquidityAdded > 0) {
            // add liquidity
            pool.mint(
                address(this),
                position.tickLower,
                position.tickUpper,
                liquidityAdded,
                abi.encode(
                    MintCallbackData({
                        token0: position.token0,
                        token1: position.token1,
                        fee: position.fee,
                        payer: address(this)
                    })
                )
            );
            
            // به‌روزرسانی NFT
            positionNFT.updatePosition(
                tokenId,
                int128(liquidityAdded),
                0,
                0
            );
            
            emit AutoCompound(tokenId, liquidityAdded, amount0, amount1);
        }
    }
    
    // ==================== CALLBACK FUNCTIONS ====================
    
    struct MintCallbackData {
        address token0;
        address token1;
        uint24 fee;
        address payer;
    }
    
    /**
     * @dev callback برای mint
     */
    function laxcePoolMintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        
        // بررسی pool
        require(msg.sender == _getPool(decoded.token0, decoded.token1, decoded.fee), "Invalid pool");
        
        // انتقال tokens
        if (amount0Owed > 0) {
            _pay(decoded.token0, decoded.payer, msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            _pay(decoded.token1, decoded.payer, msg.sender, amount1Owed);
        }
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @dev تنظیم default slippage
     * @param newSlippage slippage جدید
     */
    function setDefaultSlippage(uint256 newSlippage) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        if (newSlippage < MIN_SLIPPAGE || newSlippage > MAX_SLIPPAGE) {
            revert PoolManager__InvalidSlippage();
        }
        
        uint256 oldSlippage = defaultSlippage;
        defaultSlippage = newSlippage;
        
        emit SlippageUpdated(oldSlippage, newSlippage);
    }
    
    /**
     * @dev تنظیم auto compound
     * @param enabled فعال یا غیرفعال
     */
    function setAutoCompoundEnabled(bool enabled) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        autoCompoundEnabled = enabled;
        emit AutoCompoundToggled(enabled);
    }
    
    /**
     * @dev تنظیم min liquidity برای auto compound
     * @param minLiquidity حد minimum جدید
     */
    function setMinLiquidityForAutoCompound(uint256 minLiquidity) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        minLiquidityForAutoCompound = minLiquidity;
    }
    
    /**
     * @dev تنظیم fee collector برای position
     * @param tokenId شناسه NFT
     * @param collector آدرس collector
     */
    function setFeeCollector(uint256 tokenId, address collector) 
        external 
        isAuthorizedForToken(tokenId) 
    {
        feeCollectors[tokenId] = collector;
        emit FeeCollectorSet(tokenId, collector);
    }
    
    /**
     * @dev pause کردن
     */
    function pause() external onlyValidRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @dev unpause کردن
     */
    function unpause() external onlyValidRole(ADMIN_ROLE) {
        _unpause();
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @dev دریافت pool
     * @param token0 آدرس توکن اول
     * @param token1 آدرس توکن دوم
     * @param fee کارمزد
     * @return آدرس pool
     */
    function getPool(
        address token0,
        address token1,
        uint24 fee
    ) external view returns (address) {
        return _getPool(token0, token1, fee);
    }
    
    /**
     * @dev بررسی authorization
     * @param spender آدرس spender
     * @param tokenId شناسه NFT
     * @return true اگر مجاز باشد
     */
    function isApprovedOrOwner(address spender, uint256 tokenId) 
        external 
        view 
        returns (bool) 
    {
        return _isApprovedOrOwner(spender, tokenId);
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    /**
     * @dev دریافت pool (cached)
     */
    function _getPool(
        address token0,
        address token1,
        uint24 fee
    ) internal returns (address pool) {
        if (token0 > token1) (token0, token1) = (token1, token0);
        
        bytes32 key = keccak256(abi.encodePacked(token0, token1, fee));
        pool = _cachedPools[key];
        
        if (pool == address(0)) {
            pool = factory.getPool(token0, token1, fee);
            if (pool == address(0)) revert PoolManager__PoolNotExists();
            _cachedPools[key] = pool;
        }
    }
    
    /**
     * @dev محاسبه liquidity برای amounts
     */
    function _getLiquidityForAmounts(
        LaxcePool pool,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (uint128 liquidity) {
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        
        return LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            tickLower.getSqrtRatioAtTick(),
            tickUpper.getSqrtRatioAtTick(),
            amount0,
            amount1
        );
    }
    
    /**
     * @dev بررسی authorization
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) 
        internal 
        view 
        returns (bool) 
    {
        return positionNFT.ownerOf(tokenId) == spender ||
               positionNFT.getApproved(tokenId) == spender ||
               positionNFT.isApprovedForAll(positionNFT.ownerOf(tokenId), spender);
    }
    
    /**
     * @dev پرداخت token
     */
    function _pay(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token == WETH9 && address(this).balance >= value) {
            // پرداخت با ETH
            IWETH9(WETH9).deposit{value: value}();
            IERC20(WETH9).safeTransfer(recipient, value);
        } else if (payer == address(this)) {
            // پرداخت از contract
            IERC20(token).safeTransfer(recipient, value);
        } else {
            // پرداخت از payer
            IERC20(token).safeTransferFrom(payer, recipient, value);
        }
    }
    
    // ==================== RECEIVE FUNCTION ====================
    
    receive() external payable {}
}

// ==================== INTERFACES ====================

// Math libraries...
library LiquidityAmounts {
    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        
        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);
            
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }
    
    function getLiquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, Constants.Q96);
        return uint128(FullMath.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
    }
    
    function getLiquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        return uint128(FullMath.mulDiv(amount1, Constants.Q96, sqrtRatioBX96 - sqrtRatioAX96));
    }
}

 