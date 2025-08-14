// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./FeeCalculator.sol";
import "./FeeDistributor.sol";
import "./ProtocolFeeCollector.sol";
import "../libraries/Constants.sol";

/**
 * @title FeeManager
 * @dev مدیریت مرکزی تمام کارمزدهای DEX
 */
contract FeeManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct FeeCollection {
        uint256 totalCollected;     // کل fee جمع‌آوری شده
        uint256 lpShare;           // سهم LP ها
        uint256 protocolShare;     // سهم protocol
        uint256 lastCollection;    // آخرین زمان جمع‌آوری
    }

    struct PoolFeeData {
        uint256 totalFees;         // کل fees این pool
        uint256 lpFees;           // fees متعلق به LP ها
        uint256 protocolFees;     // fees متعلق به protocol
        uint256 pendingFees;      // fees در انتظار توزیع
        bool isActive;            // فعال/غیرفعال
    }

    // Events
    event FeeCollected(
        address indexed pool,
        address indexed token,
        uint256 amount,
        uint256 lpShare,
        uint256 protocolShare
    );

    event FeeDistributed(
        address indexed pool,
        address indexed token,
        uint256 lpAmount,
        uint256 protocolAmount
    );

    event PoolRegistered(address indexed pool, bool isActive);
    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed to);

    // State variables
    FeeCalculator public feeCalculator;
    FeeDistributor public feeDistributor;
    ProtocolFeeCollector public protocolFeeCollector;
    
    mapping(address => mapping(address => FeeCollection)) public feeCollections; // pool => token => collection
    mapping(address => PoolFeeData) public poolFeeData;
    mapping(address => bool) public registeredPools;
    mapping(address => bool) public authorizedCollectors; // contracts that can collect fees
    
    // Fee settings
    uint256 public constant DEFAULT_LP_SHARE = 8000;      // 80% to LPs
    uint256 public constant DEFAULT_PROTOCOL_SHARE = 2000; // 20% to protocol
    uint256 public lpSharePercentage = DEFAULT_LP_SHARE;
    uint256 public protocolSharePercentage = DEFAULT_PROTOCOL_SHARE;
    
    // Collection settings
    uint256 public autoCollectionThreshold = 1000 * 10**18; // Auto collect when > 1000 tokens
    uint256 public collectionInterval = 24 hours;           // Minimum interval between collections
    bool public autoCollectionEnabled = true;
    
    // Emergency settings
    bool public emergencyPaused = false;
    address public emergencyWithdrawer;

    error InvalidAddress();
    error InvalidPercentage();
    error PoolNotRegistered();
    error UnauthorizedCollector();
    error EmergencyPaused();
    error InsufficientFees();
    error CollectionTooFrequent();

    modifier onlyAuthorizedCollector() {
        if (!authorizedCollectors[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedCollector();
        }
        _;
    }

    modifier onlyRegisteredPool(address pool) {
        if (!registeredPools[pool]) revert PoolNotRegistered();
        _;
    }

    modifier notPaused() {
        if (emergencyPaused) revert EmergencyPaused();
        _;
    }

    constructor(
        address _feeCalculator,
        address _feeDistributor,
        address _protocolFeeCollector
    ) Ownable(msg.sender) {
        if (_feeCalculator == address(0) || 
            _feeDistributor == address(0) || 
            _protocolFeeCollector == address(0)) {
            revert InvalidAddress();
        }

        feeCalculator = FeeCalculator(_feeCalculator);
        feeDistributor = FeeDistributor(_feeDistributor);
        protocolFeeCollector = ProtocolFeeCollector(_protocolFeeCollector);
        
        emergencyWithdrawer = msg.sender;
        authorizedCollectors[msg.sender] = true;
    }

    /**
     * @dev جمع‌آوری fee از swap
     * @param pool آدرس pool
     * @param token آدرس token
     * @param amount مقدار fee
     * @param user آدرس کاربر (برای محاسبه tier)
     */
    function collectSwapFee(
        address pool,
        address token,
        uint256 amount,
        address user
    ) external onlyAuthorizedCollector onlyRegisteredPool(pool) notPaused nonReentrant {
        if (amount == 0) revert InsufficientFees();

        // محاسبه تقسیم fee
        (uint256 lpShare, uint256 protocolShare) = _calculateFeeShares(amount);

        // به‌روزرسانی داده‌ها
        FeeCollection storage collection = feeCollections[pool][token];
        collection.totalCollected += amount;
        collection.lpShare += lpShare;
        collection.protocolShare += protocolShare;
        collection.lastCollection = block.timestamp;

        PoolFeeData storage poolData = poolFeeData[pool];
        poolData.totalFees += amount;
        poolData.lpFees += lpShare;
        poolData.protocolFees += protocolShare;
        poolData.pendingFees += amount;

        // انتقال token به این contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // به‌روزرسانی volume کاربر در FeeCalculator
        feeCalculator.updateUserVolume(user, amount);

        emit FeeCollected(pool, token, amount, lpShare, protocolShare);

        // بررسی auto collection
        if (autoCollectionEnabled && collection.totalCollected >= autoCollectionThreshold) {
            _autoDistributeFees(pool, token);
        }
    }

    /**
     * @dev توزیع fees جمع‌آوری شده
     * @param pool آدرس pool
     * @param token آدرس token
     */
    function distributeFees(
        address pool,
        address token
    ) external onlyRegisteredPool(pool) notPaused nonReentrant {
        FeeCollection storage collection = feeCollections[pool][token];
        
        if (collection.lastCollection + collectionInterval > block.timestamp) {
            revert CollectionTooFrequent();
        }

        _distributeFees(pool, token);
    }

    /**
     * @dev توزیع fees برای تمام tokens یک pool
     * @param pool آدرس pool
     * @param tokens لیست tokens
     */
    function distributeBatchFees(
        address pool,
        address[] calldata tokens
    ) external onlyRegisteredPool(pool) notPaused nonReentrant {
        for (uint256 i = 0; i < tokens.length; i++) {
            FeeCollection storage collection = feeCollections[pool][tokens[i]];
            if (collection.totalCollected > 0) {
                _distributeFees(pool, tokens[i]);
            }
        }
    }

    /**
     * @dev ثبت pool جدید
     * @param pool آدرس pool
     * @param isActive وضعیت فعال
     */
    function registerPool(address pool, bool isActive) external onlyOwner {
        if (pool == address(0)) revert InvalidAddress();
        
        registeredPools[pool] = true;
        poolFeeData[pool] = PoolFeeData({
            totalFees: 0,
            lpFees: 0,
            protocolFees: 0,
            pendingFees: 0,
            isActive: isActive
        });
        
        emit PoolRegistered(pool, isActive);
    }

    /**
     * @dev فعال/غیرفعال کردن pool
     * @param pool آدرس pool
     * @param isActive وضعیت جدید
     */
    function setPoolActive(address pool, bool isActive) external onlyOwner {
        if (!registeredPools[pool]) revert PoolNotRegistered();
        poolFeeData[pool].isActive = isActive;
        emit PoolRegistered(pool, isActive);
    }

    /**
     * @dev اضافه کردن authorized collector
     * @param collector آدرس collector
     */
    function addAuthorizedCollector(address collector) external onlyOwner {
        if (collector == address(0)) revert InvalidAddress();
        authorizedCollectors[collector] = true;
    }

    /**
     * @dev حذف authorized collector
     * @param collector آدرس collector
     */
    function removeAuthorizedCollector(address collector) external onlyOwner {
        authorizedCollectors[collector] = false;
    }

    /**
     * @dev تنظیم درصد تقسیم fees
     * @param lpShare درصد سهم LP ها
     * @param protocolShare درصد سهم protocol
     */
    function setFeeShares(uint256 lpShare, uint256 protocolShare) external onlyOwner {
        if (lpShare + protocolShare != Constants.BASIS_POINTS) revert InvalidPercentage();
        
        lpSharePercentage = lpShare;
        protocolSharePercentage = protocolShare;
    }

    /**
     * @dev تنظیم threshold برای auto collection
     * @param threshold threshold جدید
     */
    function setAutoCollectionThreshold(uint256 threshold) external onlyOwner {
        autoCollectionThreshold = threshold;
    }

    /**
     * @dev فعال/غیرفعال کردن auto collection
     * @param enabled وضعیت
     */
    function setAutoCollectionEnabled(bool enabled) external onlyOwner {
        autoCollectionEnabled = enabled;
    }

    /**
     * @dev تنظیم collection interval
     * @param interval interval جدید
     */
    function setCollectionInterval(uint256 interval) external onlyOwner {
        require(interval >= 1 hours && interval <= 7 days, "Invalid interval");
        collectionInterval = interval;
    }

    /**
     * @dev فعال/غیرفعال کردن emergency pause
     * @param paused وضعیت
     */
    function setEmergencyPaused(bool paused) external onlyOwner {
        emergencyPaused = paused;
    }

    /**
     * @dev emergency withdrawal
     * @param token آدرس token
     * @param amount مقدار
     * @param to آدرس مقصد
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address to
    ) external {
        require(msg.sender == emergencyWithdrawer || msg.sender == owner(), "Unauthorized");
        require(to != address(0), "Invalid recipient");
        
        IERC20(token).safeTransfer(to, amount);
        emit EmergencyWithdraw(token, amount, to);
    }

    /**
     * @dev دریافت اطلاعات fee collection
     * @param pool آدرس pool
     * @param token آدرس token
     */
    function getFeeCollection(address pool, address token) 
        external 
        view 
        returns (
            uint256 totalCollected,
            uint256 lpShare,
            uint256 protocolShare,
            uint256 lastCollection
        ) 
    {
        FeeCollection storage collection = feeCollections[pool][token];
        return (
            collection.totalCollected,
            collection.lpShare,
            collection.protocolShare,
            collection.lastCollection
        );
    }

    /**
     * @dev دریافت اطلاعات pool
     * @param pool آدرس pool
     */
    function getPoolFeeData(address pool) 
        external 
        view 
        returns (
            uint256 totalFees,
            uint256 lpFees,
            uint256 protocolFees,
            uint256 pendingFees,
            bool isActive
        ) 
    {
        PoolFeeData storage data = poolFeeData[pool];
        return (data.totalFees, data.lpFees, data.protocolFees, data.pendingFees, data.isActive);
    }

    /**
     * @dev محاسبه تقسیم fee
     */
    function _calculateFeeShares(uint256 totalFee) internal view returns (uint256 lpShare, uint256 protocolShare) {
        lpShare = (totalFee * lpSharePercentage) / Constants.BASIS_POINTS;
        protocolShare = totalFee - lpShare;
    }

    /**
     * @dev توزیع fees داخلی
     */
    function _distributeFees(address pool, address token) internal {
        FeeCollection storage collection = feeCollections[pool][token];
        PoolFeeData storage poolData = poolFeeData[pool];
        
        uint256 lpAmount = collection.lpShare;
        uint256 protocolAmount = collection.protocolShare;
        
        if (lpAmount == 0 && protocolAmount == 0) return;

        // توزیع به LP ها
        if (lpAmount > 0) {
            IERC20(token).safeApprove(address(feeDistributor), lpAmount);
            feeDistributor.distributeLPFees(pool, token, lpAmount);
        }

        // توزیع به protocol
        if (protocolAmount > 0) {
            IERC20(token).safeTransfer(address(protocolFeeCollector), protocolAmount);
            protocolFeeCollector.collectFee(token, protocolAmount);
        }

        // reset کردن داده‌ها
        collection.lpShare = 0;
        collection.protocolShare = 0;
        poolData.pendingFees -= (lpAmount + protocolAmount);

        emit FeeDistributed(pool, token, lpAmount, protocolAmount);
    }

    /**
     * @dev auto distribution داخلی
     */
    function _autoDistributeFees(address pool, address token) internal {
        FeeCollection storage collection = feeCollections[pool][token];
        
        // بررسی interval
        if (collection.lastCollection + collectionInterval <= block.timestamp) {
            _distributeFees(pool, token);
        }
    }
}