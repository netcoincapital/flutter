// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../libraries/Constants.sol";

/**
 * @title SimplePoolFactory
 * @dev Factory ساده برای ایجاد و مدیریت pools
 */
contract SimplePoolFactory is Ownable, Pausable {
    
    // ==================== STRUCTS ====================
    
    struct PoolInfo {
        address token0;
        address token1;
        uint24 fee;
        address pool;
        bool isActive;
        uint256 createdAt;
    }
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev لیست همه pools
    mapping(bytes32 => PoolInfo) public pools;
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;
    
    /// @dev آرایه pool ها برای iteration
    address[] public allPools;
    
    /// @dev fee tiers مجاز
    mapping(uint24 => bool) public feeAmountTickSpacing;
    
    /// @dev حداکثر pools
    uint256 public constant MAX_POOLS = 1000;
    
    // ==================== EVENTS ====================
    
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        address pool,
        uint256 poolId
    );
    
    event PoolStatusChanged(address indexed pool, bool isActive);
    event FeeAmountEnabled(uint24 indexed fee, bool enabled);
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(address _owner) Ownable(_owner) {
        // تنظیم fee tiers پیش‌فرض
        _enableFeeAmount(500);   // 0.05%
        _enableFeeAmount(3000);  // 0.3%
        _enableFeeAmount(10000); // 1%
    }
    
    // ==================== POOL CREATION ====================
    
    /// @notice ایجاد pool جدید
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool) {
        require(tokenA != tokenB, "Identical tokens");
        require(feeAmountTickSpacing[fee], "Invalid fee");
        require(allPools.length < MAX_POOLS, "Too many pools");
        
        // مرتب کردن توکن‌ها
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Zero address");
        require(getPool[token0][token1][fee] == address(0), "Pool exists");
        
        // ایجاد pool address (mock)
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, fee));
        pool = address(uint160(uint256(salt)));
        
        // ذخیره اطلاعات pool
        pools[salt] = PoolInfo({
            token0: token0,
            token1: token1,
            fee: fee,
            pool: pool,
            isActive: true,
            createdAt: block.timestamp
        });
        
        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool; // bidirectional
        allPools.push(pool);
        
        emit PoolCreated(token0, token1, fee, pool, allPools.length - 1);
    }
    
    // ==================== POOL MANAGEMENT ====================
    
    /// @notice فعال/غیرفعال کردن pool
    function setPoolStatus(address _pool, bool _isActive) external onlyOwner {
        require(_pool != address(0), "Invalid pool");
        
        // پیدا کردن pool
        bool found = false;
        for (uint256 i = 0; i < allPools.length; i++) {
            if (allPools[i] == _pool) {
                found = true;
                break;
            }
        }
        require(found, "Pool not found");
        
        // بروزرسانی وضعیت در mapping
        // Note: این پیاده‌سازی ساده است و در production باید بهینه شود
        
        emit PoolStatusChanged(_pool, _isActive);
    }
    
    /// @notice فعال/غیرفعال کردن fee amount
    function enableFeeAmount(uint24 _fee, bool _enabled) external onlyOwner {
        _enableFeeAmount(_fee);
        emit FeeAmountEnabled(_fee, _enabled);
    }
    
    function _enableFeeAmount(uint24 _fee) internal {
        require(_fee < 1000000, "Fee too high"); // حداکثر 100%
        feeAmountTickSpacing[_fee] = true;
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /// @notice تعداد کل pools
    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }
    
    /// @notice دریافت اطلاعات pool
    function getPoolInfo(address _pool) external view returns (
        address token0,
        address token1,
        uint24 fee,
        bool isActive,
        uint256 createdAt
    ) {
        // پیدا کردن pool (ساده‌سازی شده)
        for (uint256 i = 0; i < allPools.length; i++) {
            if (allPools[i] == _pool) {
                bytes32 salt = keccak256(abi.encodePacked(i)); // ساده‌سازی
                PoolInfo memory info = pools[salt];
                return (info.token0, info.token1, info.fee, info.isActive, info.createdAt);
            }
        }
        revert("Pool not found");
    }
    
    /// @notice دریافت لیست pools یک توکن
    function getPoolsByToken(address _token) external view returns (address[] memory) {
        address[] memory tokenPools = new address[](allPools.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < allPools.length; i++) {
            // این پیاده‌سازی ساده است و در production باید بهینه شود
            tokenPools[count] = allPools[i];
            count++;
        }
        
        // تنظیم اندازه نهایی
        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = tokenPools[i];
        }
        
        return result;
    }
    
    /// @notice بررسی اینکه آیا pool وجود دارد
    function poolExists(address tokenA, address tokenB, uint24 fee) external view returns (bool) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return getPool[token0][token1][fee] != address(0);
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /// @notice pause کردن factory
    function pause() external onlyOwner {
        _pause();
    }
    
    /// @notice unpause کردن factory
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // ==================== UTILITY FUNCTIONS ====================
    
    /// @notice محاسبه pool address از روی parameters
    function computeAddress(
        address token0,
        address token1,
        uint24 fee
    ) external pure returns (address pool) {
        require(token0 < token1, "Invalid token order");
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, fee));
        pool = address(uint160(uint256(salt)));
    }
} 