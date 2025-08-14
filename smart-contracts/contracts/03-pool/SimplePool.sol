// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../libraries/Constants.sol";

/**
 * @title SimplePool
 * @dev Pool ساده برای نقدینگی و swap
 */
contract SimplePool is Ownable, Pausable {
    using SafeERC20 for IERC20;
    
    // ==================== STRUCTS ====================
    
    struct PoolState {
        uint256 reserve0;
        uint256 reserve1;
        uint256 totalLiquidity;
        uint32 lastUpdateTime;
    }
    
    struct Position {
        uint256 liquidity;
        uint256 depositTime;
        uint256 token0Deposited;
        uint256 token1Deposited;
    }
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev توکن‌های pool
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    
    /// @dev کارمزد pool (basis points)
    uint24 public immutable fee;
    
    /// @dev وضعیت pool
    PoolState public poolState;
    
    /// @dev موقعیت‌های کاربران
    mapping(address => Position) public positions;
    
    /// @dev لیست ارائه دهندگان نقدینگی
    address[] public liquidityProviders;
    mapping(address => bool) public isLiquidityProvider;
    
    /// @dev حداقل نقدینگی
    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    
    /// @dev ضریب fee برای محاسبه
    uint256 public constant FEE_DENOMINATOR = 1000000;
    
    // ==================== EVENTS ====================
    
    event Mint(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint256 reserve0, uint256 reserve1);
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(
        address _token0,
        address _token1,
        uint24 _fee,
        address _owner
    ) Ownable(_owner) {
        require(_token0 != _token1, "Identical tokens");
        require(_token0 != address(0) && _token1 != address(0), "Zero address");
        
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        fee = _fee;
        
        poolState.lastUpdateTime = uint32(block.timestamp);
    }
    
    // ==================== LIQUIDITY FUNCTIONS ====================
    
    /// @notice اضافه کردن نقدینگی
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external whenNotPaused returns (uint256 liquidity) {
        require(amount0Desired > 0 && amount1Desired > 0, "Insufficient amounts");
        
        (uint256 amount0, uint256 amount1) = _addLiquidity(
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min
        );
        
        // انتقال توکن‌ها
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);
        
        // محاسبه liquidity
        liquidity = _mint(to, amount0, amount1);
        
        // ثبت position
        if (!isLiquidityProvider[to]) {
            liquidityProviders.push(to);
            isLiquidityProvider[to] = true;
        }
        
        positions[to].liquidity += liquidity;
        positions[to].token0Deposited += amount0;
        positions[to].token1Deposited += amount1;
        positions[to].depositTime = block.timestamp;
        
        _updateReserves();
    }
    
    /// @notice حذف نقدینگی
    function removeLiquidity(
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external whenNotPaused returns (uint256 amount0, uint256 amount1) {
        require(liquidity > 0, "Insufficient liquidity");
        require(positions[msg.sender].liquidity >= liquidity, "Insufficient position");
        
        (amount0, amount1) = _burn(liquidity);
        
        require(amount0 >= amount0Min && amount1 >= amount1Min, "Insufficient amounts");
        
        // انتقال توکن‌ها
        token0.safeTransfer(to, amount0);
        token1.safeTransfer(to, amount1);
        
        // بروزرسانی position
        positions[msg.sender].liquidity -= liquidity;
        
        _updateReserves();
    }
    
    function _addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal view returns (uint256 amount0, uint256 amount1) {
        if (poolState.reserve0 == 0 && poolState.reserve1 == 0) {
            (amount0, amount1) = (amount0Desired, amount1Desired);
        } else {
            uint256 amount1Optimal = quote(amount0Desired, poolState.reserve0, poolState.reserve1);
            if (amount1Optimal <= amount1Desired) {
                require(amount1Optimal >= amount1Min, "Insufficient amount1");
                (amount0, amount1) = (amount0Desired, amount1Optimal);
            } else {
                uint256 amount0Optimal = quote(amount1Desired, poolState.reserve1, poolState.reserve0);
                assert(amount0Optimal <= amount0Desired);
                require(amount0Optimal >= amount0Min, "Insufficient amount0");
                (amount0, amount1) = (amount0Optimal, amount1Desired);
            }
        }
    }
    
    function _mint(address to, uint256 amount0, uint256 amount1) internal returns (uint256 liquidity) {
        if (poolState.totalLiquidity == 0) {
            liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            poolState.totalLiquidity = MINIMUM_LIQUIDITY; // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = min(
                (amount0 * poolState.totalLiquidity) / poolState.reserve0,
                (amount1 * poolState.totalLiquidity) / poolState.reserve1
            );
        }
        require(liquidity > 0, "Insufficient liquidity minted");
        poolState.totalLiquidity += liquidity;
        
        emit Mint(msg.sender, amount0, amount1, liquidity);
    }
    
    function _burn(uint256 liquidity) internal returns (uint256 amount0, uint256 amount1) {
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        
        amount0 = (liquidity * balance0) / poolState.totalLiquidity;
        amount1 = (liquidity * balance1) / poolState.totalLiquidity;
        
        require(amount0 > 0 && amount1 > 0, "Insufficient liquidity burned");
        
        poolState.totalLiquidity -= liquidity;
        
        emit Burn(msg.sender, amount0, amount1, liquidity);
    }
    
    // ==================== SWAP FUNCTIONS ====================
    
    /// @notice انجام swap
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) external whenNotPaused {
        require(amount0Out > 0 || amount1Out > 0, "Insufficient output amount");
        require(amount0Out < poolState.reserve0 && amount1Out < poolState.reserve1, "Insufficient liquidity");
        
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        
        // انتقال توکن‌های خروجی
        if (amount0Out > 0) token0.safeTransfer(to, amount0Out);
        if (amount1Out > 0) token1.safeTransfer(to, amount1Out);
        
        // محاسبه ورودی‌ها
        uint256 balance0After = token0.balanceOf(address(this));
        uint256 balance1After = token1.balanceOf(address(this));
        
        uint256 amount0In = balance0After > balance0Before - amount0Out ? balance0After - (balance0Before - amount0Out) : 0;
        uint256 amount1In = balance1After > balance1Before - amount1Out ? balance1After - (balance1Before - amount1Out) : 0;
        
        require(amount0In > 0 || amount1In > 0, "Insufficient input amount");
        
        // بررسی invariant با کارمزد
        {
            uint256 balance0Adjusted = balance0After * 1000 - amount0In * fee / 1000;
            uint256 balance1Adjusted = balance1After * 1000 - amount1In * fee / 1000;
            require(
                balance0Adjusted * balance1Adjusted >= uint256(poolState.reserve0) * poolState.reserve1 * (1000**2),
                "K"
            );
        }
        
        _updateReserves();
        
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
    
    /// @notice محاسبه مقدار خروجی برای swap
    function getAmountOut(uint256 amountIn, bool zeroForOne) external view returns (uint256 amountOut) {
        require(amountIn > 0, "Insufficient input amount");
        
        if (zeroForOne) {
            require(poolState.reserve0 > 0 && poolState.reserve1 > 0, "Insufficient liquidity");
            uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - fee);
            uint256 numerator = amountInWithFee * poolState.reserve1;
            uint256 denominator = poolState.reserve0 * FEE_DENOMINATOR + amountInWithFee;
            amountOut = numerator / denominator;
        } else {
            require(poolState.reserve1 > 0 && poolState.reserve0 > 0, "Insufficient liquidity");
            uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - fee);
            uint256 numerator = amountInWithFee * poolState.reserve0;
            uint256 denominator = poolState.reserve1 * FEE_DENOMINATOR + amountInWithFee;
            amountOut = numerator / denominator;
        }
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /// @notice دریافت reserves
    function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = poolState.reserve0;
        _reserve1 = poolState.reserve1;
        _blockTimestampLast = poolState.lastUpdateTime;
    }
    
    /// @notice محاسبه quote
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256 amountB) {
        require(amountA > 0, "Insufficient amount");
        require(reserveA > 0 && reserveB > 0, "Insufficient liquidity");
        amountB = (amountA * reserveB) / reserveA;
    }
    
    /// @notice تعداد liquidity providers
    function getLiquidityProvidersCount() external view returns (uint256) {
        return liquidityProviders.length;
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    function _updateReserves() internal {
        poolState.reserve0 = token0.balanceOf(address(this));
        poolState.reserve1 = token1.balanceOf(address(this));
        poolState.lastUpdateTime = uint32(block.timestamp);
        
        emit Sync(poolState.reserve0, poolState.reserve1);
    }
    
    // ==================== UTILITY FUNCTIONS ====================
    
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }
    
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
} 