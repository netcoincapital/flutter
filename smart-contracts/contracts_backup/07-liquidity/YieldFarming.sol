// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../01-core/AccessControl.sol";
import "../02-token/LAXCE.sol";
import "../02-token/LPToken.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";
import "./LiquidityMining.sol";

/**
 * @title YieldFarming
 * @dev سیستم پیشرفته yield farming با قابلیت auto-compound و multiple rewards
 * @notice این کانترکت برای حداکثرسازی yield از فعالیت‌های مختلف DeFi استفاده می‌شود
 */
contract YieldFarming is Pausable, LaxceAccessControl {
    using SafeERC20 for IERC20;
    using ReentrancyGuard for ReentrancyGuard.ReentrancyData;
    
    // ==================== CONSTANTS ====================
    
    /// @dev حداکثر تعداد strategies
    uint256 public constant MAX_STRATEGIES = 50;
    
    /// @dev حداکثر تعداد reward tokens per strategy
    uint256 public constant MAX_REWARD_TOKENS = 5;
    
    /// @dev حداکثر performance fee (20%)
    uint256 public constant MAX_PERFORMANCE_FEE = 2000;
    
    /// @dev حداکثر management fee (5%)
    uint256 public constant MAX_MANAGEMENT_FEE = 500;
    
    /// @dev مدت زمان پیش‌فرض lockup (7 روز)
    uint256 public constant DEFAULT_LOCKUP_PERIOD = 7 days;
    
    // ==================== STRUCTS ====================
    
    /// @dev اطلاعات strategy
    struct StrategyInfo {
        string name;                    // نام strategy
        address depositToken;          // توکن مورد نیاز برای deposit
        address[] rewardTokens;        // لیست توکن‌های reward
        uint256 totalDeposited;        // کل مقدار deposit شده
        uint256 totalShares;           // کل shares صادر شده
        uint256 lastHarvestTime;       // زمان آخرین harvest
        uint256 performanceFee;        // کارمزد عملکرد (basis points)
        uint256 managementFee;         // کارمزد مدیریت (basis points)
        uint256 minDeposit;            // حداقل مقدار deposit
        uint256 lockupPeriod;          // مدت زمان قفل
        bool autoCompound;             // آیا auto-compound فعال است
        bool isActive;                 // آیا strategy فعال است
        address strategyContract;      // آدرس کانترکت strategy
    }
    
    /// @dev اطلاعات کاربر در strategy
    struct UserStrategyInfo {
        uint256 shares;                // تعداد shares کاربر
        uint256 depositTime;           // زمان deposit
        uint256 lastClaimTime;         // زمان آخرین claim
        uint256 totalDeposited;        // کل مقدار deposit شده توسط کاربر
        uint256 totalRewarded;         // کل rewards دریافت شده
        uint256 pendingRewards;        // rewards در انتظار
        mapping(address => uint256) rewardDebts; // debt برای هر reward token
        bool autoCompoundEnabled;      // آیا auto-compound فعال است
    }
    
    /// @dev اطلاعات harvest
    struct HarvestInfo {
        uint256 timestamp;             // زمان harvest
        uint256 totalHarvested;        // کل مقدار harvest شده
        uint256 performanceFee;        // کارمزد عملکرد
        address harvester;             // آدرس harvester
        mapping(address => uint256) tokenAmounts; // مقدار هر توکن
    }
    
    /// @dev اطلاعات auto-compound
    struct AutoCompoundInfo {
        bool enabled;                  // آیا فعال است
        uint256 threshold;             // حد آستانه برای compound
        uint256 lastCompoundTime;      // زمان آخرین compound
        uint256 totalCompounded;       // کل مقدار compound شده
        uint256 compoundFee;           // کارمزد compound (basis points)
    }
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev reentrancy guard instance
    ReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    /// @dev آدرس توکن LAXCE
    LAXCE public immutable laxceToken;
    
    /// @dev آدرس LiquidityMining
    LiquidityMining public liquidityMining;
    
    /// @dev اطلاعات همه strategies
    StrategyInfo[] public strategies;
    
    /// @dev mapping strategyId => userId => UserStrategyInfo
    mapping(uint256 => mapping(address => UserStrategyInfo)) public userStrategies;
    
    /// @dev mapping strategyId => harvest history
    mapping(uint256 => HarvestInfo[]) public harvestHistory;
    
    /// @dev mapping strategyId => AutoCompoundInfo
    mapping(uint256 => AutoCompoundInfo) public autoCompoundInfo;
    
    /// @dev treasury address
    address public treasury;
    
    /// @dev default performance fee
    uint256 public defaultPerformanceFee = 1000; // 10%
    
    /// @dev default management fee
    uint256 public defaultManagementFee = 200; // 2%
    
    /// @dev harvest threshold
    uint256 public harvestThreshold = 100 ether;
    
    /// @dev auto compound threshold
    uint256 public autoCompoundThreshold = 10 ether;
    
    /// @dev emergency mode
    bool public emergencyMode;
    
    /// @dev total value locked در همه strategies
    uint256 public totalValueLocked;
    
    /// @dev protocol revenue
    uint256 public protocolRevenue;
    
    // ==================== EVENTS ====================
    
    event StrategyAdded(
        uint256 indexed strategyId,
        string name,
        address depositToken,
        address strategyContract
    );
    
    event StrategyUpdated(uint256 indexed strategyId, bool isActive);
    
    event Deposit(
        address indexed user,
        uint256 indexed strategyId,
        uint256 amount,
        uint256 shares
    );
    
    event Withdraw(
        address indexed user,
        uint256 indexed strategyId,
        uint256 shares,
        uint256 amount
    );
    
    event Harvest(
        uint256 indexed strategyId,
        uint256 totalHarvested,
        uint256 performanceFee,
        address indexed harvester
    );
    
    event RewardsClaimed(
        address indexed user,
        uint256 indexed strategyId,
        address indexed rewardToken,
        uint256 amount
    );
    
    event AutoCompound(
        uint256 indexed strategyId,
        uint256 amount,
        uint256 newShares,
        address indexed user
    );
    
    event PerformanceFeeUpdated(uint256 indexed strategyId, uint256 oldFee, uint256 newFee);
    event ManagementFeeUpdated(uint256 indexed strategyId, uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event EmergencyModeToggled(bool enabled);
    
    // ==================== ERRORS ====================
    
    error YieldFarming__InvalidStrategy();
    error YieldFarming__StrategyNotActive();
    error YieldFarming__InsufficientAmount();
    error YieldFarming__InsufficientShares();
    error YieldFarming__StillLocked();
    error YieldFarming__EmergencyMode();
    error YieldFarming__InvalidFee();
    error YieldFarming__MaxStrategiesReached();
    error YieldFarming__MaxRewardTokensReached();
    error YieldFarming__InvalidToken();
    error YieldFarming__HarvestNotReady();
    error YieldFarming__NoRewardsAvailable();
    
    // ==================== MODIFIERS ====================
    
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }
    
    modifier validStrategy(uint256 _strategyId) {
        if (_strategyId >= strategies.length) revert YieldFarming__InvalidStrategy();
        _;
    }
    
    modifier activeStrategy(uint256 _strategyId) {
        if (!strategies[_strategyId].isActive) revert YieldFarming__StrategyNotActive();
        _;
    }
    
    modifier notEmergency() {
        if (emergencyMode) revert YieldFarming__EmergencyMode();
        _;
    }
    
    modifier validAmount(uint256 _amount) {
        if (_amount == 0) revert YieldFarming__InsufficientAmount();
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(
        address _laxceToken,
        address _liquidityMining,
        address _treasury
    ) {
        laxceToken = LAXCE(_laxceToken);
        liquidityMining = LiquidityMining(_liquidityMining);
        treasury = _treasury;
        
        _reentrancyGuard.initialize();
        
        // گرنت نقش‌های پیش‌فرض
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }
    
    // ==================== STRATEGY MANAGEMENT ====================
    
    /**
     * @notice اضافه کردن strategy جدید
     * @param _name نام strategy
     * @param _depositToken توکن مورد نیاز برای deposit
     * @param _rewardTokens لیست reward tokens
     * @param _strategyContract آدرس کانترکت strategy
     * @param _minDeposit حداقل مقدار deposit
     */
    function addStrategy(
        string calldata _name,
        address _depositToken,
        address[] calldata _rewardTokens,
        address _strategyContract,
        uint256 _minDeposit
    ) external onlyRole(OPERATOR_ROLE) notEmergency {
        if (strategies.length >= MAX_STRATEGIES) revert YieldFarming__MaxStrategiesReached();
        if (_rewardTokens.length > MAX_REWARD_TOKENS) revert YieldFarming__MaxRewardTokensReached();
        
        strategies.push(StrategyInfo({
            name: _name,
            depositToken: _depositToken,
            rewardTokens: _rewardTokens,
            totalDeposited: 0,
            totalShares: 0,
            lastHarvestTime: block.timestamp,
            performanceFee: defaultPerformanceFee,
            managementFee: defaultManagementFee,
            minDeposit: _minDeposit,
            lockupPeriod: DEFAULT_LOCKUP_PERIOD,
            autoCompound: true,
            isActive: true,
            strategyContract: _strategyContract
        }));
        
        uint256 strategyId = strategies.length - 1;
        
        // راه‌اندازی auto-compound
        autoCompoundInfo[strategyId] = AutoCompoundInfo({
            enabled: true,
            threshold: autoCompoundThreshold,
            lastCompoundTime: block.timestamp,
            totalCompounded: 0,
            compoundFee: 100 // 1%
        });
        
        emit StrategyAdded(strategyId, _name, _depositToken, _strategyContract);
    }
    
    /**
     * @notice بروزرسانی تنظیمات strategy
     * @param _strategyId شناسه strategy
     * @param _isActive وضعیت فعال بودن
     * @param _performanceFee کارمزد عملکرد
     * @param _managementFee کارمزد مدیریت
     * @param _minDeposit حداقل مقدار deposit
     */
    function updateStrategy(
        uint256 _strategyId,
        bool _isActive,
        uint256 _performanceFee,
        uint256 _managementFee,
        uint256 _minDeposit
    ) external onlyRole(OPERATOR_ROLE) validStrategy(_strategyId) {
        if (_performanceFee > MAX_PERFORMANCE_FEE) revert YieldFarming__InvalidFee();
        if (_managementFee > MAX_MANAGEMENT_FEE) revert YieldFarming__InvalidFee();
        
        StrategyInfo storage strategy = strategies[_strategyId];
        
        strategy.isActive = _isActive;
        strategy.performanceFee = _performanceFee;
        strategy.managementFee = _managementFee;
        strategy.minDeposit = _minDeposit;
        
        emit StrategyUpdated(_strategyId, _isActive);
    }
    
    // ==================== USER FUNCTIONS ====================
    
    /**
     * @notice deposit به strategy
     * @param _strategyId شناسه strategy
     * @param _amount مقدار برای deposit
     */
    function deposit(uint256 _strategyId, uint256 _amount)
        external
        nonReentrant
        validStrategy(_strategyId)
        activeStrategy(_strategyId)
        validAmount(_amount)
        notEmergency
        whenNotPaused
    {
        StrategyInfo storage strategy = strategies[_strategyId];
        UserStrategyInfo storage user = userStrategies[_strategyId][msg.sender];
        
        if (_amount < strategy.minDeposit && user.shares == 0) {
            revert YieldFarming__InsufficientAmount();
        }
        
        // harvest pending rewards before deposit
        _harvestForStrategy(_strategyId);
        
        // انتقال deposit token
        IERC20(strategy.depositToken).safeTransferFrom(msg.sender, address(this), _amount);
        
        // محاسبه shares
        uint256 shares = _calculateShares(_strategyId, _amount);
        
        // بروزرسانی اطلاعات strategy
        strategy.totalDeposited = strategy.totalDeposited.add(_amount);
        strategy.totalShares = strategy.totalShares.add(shares);
        
        // بروزرسانی اطلاعات کاربر
        user.shares = user.shares.add(shares);
        user.depositTime = block.timestamp;
        user.totalDeposited = user.totalDeposited.add(_amount);
        
        // بروزرسانی reward debts
        _updateRewardDebts(_strategyId, msg.sender);
        
        // بروزرسانی TVL
        totalValueLocked = totalValueLocked.add(_amount);
        
        emit Deposit(msg.sender, _strategyId, _amount, shares);
    }
    
    /**
     * @notice withdraw از strategy
     * @param _strategyId شناسه strategy
     * @param _shares تعداد shares برای withdraw
     */
    function withdraw(uint256 _strategyId, uint256 _shares)
        external
        nonReentrant
        validStrategy(_strategyId)
        validAmount(_shares)
        whenNotPaused
    {
        StrategyInfo storage strategy = strategies[_strategyId];
        UserStrategyInfo storage user = userStrategies[_strategyId][msg.sender];
        
        if (user.shares < _shares) revert YieldFarming__InsufficientShares();
        
        // بررسی lockup period
        if (block.timestamp < user.depositTime.add(strategy.lockupPeriod)) {
            revert YieldFarming__StillLocked();
        }
        
        // harvest pending rewards
        _harvestForStrategy(_strategyId);
        
        // محاسبه مقدار withdraw
        uint256 amount = _calculateWithdrawAmount(_strategyId, _shares);
        
        // محاسبه management fee
        uint256 managementFee = amount.mul(strategy.managementFee).div(10000);
        uint256 withdrawAmount = amount.sub(managementFee);
        
        // بروزرسانی اطلاعات strategy
        strategy.totalShares = strategy.totalShares.sub(_shares);
        strategy.totalDeposited = strategy.totalDeposited.sub(amount);
        
        // بروزرسانی اطلاعات کاربر
        user.shares = user.shares.sub(_shares);
        
        // بروزرسانی reward debts
        _updateRewardDebts(_strategyId, msg.sender);
        
        // انتقال tokens
        if (managementFee > 0) {
            IERC20(strategy.depositToken).safeTransfer(treasury, managementFee);
            protocolRevenue = protocolRevenue.add(managementFee);
        }
        IERC20(strategy.depositToken).safeTransfer(msg.sender, withdrawAmount);
        
        // بروزرسانی TVL
        totalValueLocked = totalValueLocked.sub(amount);
        
        emit Withdraw(msg.sender, _strategyId, _shares, withdrawAmount);
    }
    
    /**
     * @notice claim کردن rewards
     * @param _strategyId شناسه strategy
     */
    function claimRewards(uint256 _strategyId)
        external
        nonReentrant
        validStrategy(_strategyId)
        whenNotPaused
    {
        UserStrategyInfo storage user = userStrategies[_strategyId][msg.sender];
        StrategyInfo storage strategy = strategies[_strategyId];
        
        // harvest strategy rewards
        _harvestForStrategy(_strategyId);
        
        // محاسبه pending rewards برای کاربر
        for (uint256 i = 0; i < strategy.rewardTokens.length; i++) {
            address rewardToken = strategy.rewardTokens[i];
            uint256 pending = _calculatePendingRewards(_strategyId, msg.sender, rewardToken);
            
            if (pending > 0) {
                // انتقال rewards
                IERC20(rewardToken).safeTransfer(msg.sender, pending);
                user.totalRewarded = user.totalRewarded.add(pending);
                user.lastClaimTime = block.timestamp;
                
                emit RewardsClaimed(msg.sender, _strategyId, rewardToken, pending);
            }
        }
        
        // بروزرسانی reward debts
        _updateRewardDebts(_strategyId, msg.sender);
    }
    
    /**
     * @notice تنظیم auto-compound برای کاربر
     * @param _strategyId شناسه strategy
     * @param _enabled آیا فعال باشد
     */
    function setAutoCompound(uint256 _strategyId, bool _enabled)
        external
        validStrategy(_strategyId)
    {
        userStrategies[_strategyId][msg.sender].autoCompoundEnabled = _enabled;
    }
    
    // ==================== HARVEST & AUTO-COMPOUND ====================
    
    /**
     * @notice harvest rewards برای strategy
     * @param _strategyId شناسه strategy
     */
    function harvest(uint256 _strategyId)
        external
        nonReentrant
        validStrategy(_strategyId)
        activeStrategy(_strategyId)
        whenNotPaused
    {
        _harvestForStrategy(_strategyId);
    }
    
    /**
     * @notice auto-compound برای کاربران فعال
     * @param _strategyId شناسه strategy
     * @param _users لیست کاربران برای compound
     */
    function autoCompound(uint256 _strategyId, address[] calldata _users)
        external
        nonReentrant
        validStrategy(_strategyId)
        activeStrategy(_strategyId)
        whenNotPaused
    {
        StrategyInfo storage strategy = strategies[_strategyId];
        AutoCompoundInfo storage compoundInfo = autoCompoundInfo[_strategyId];
        
        if (!compoundInfo.enabled) return;
        
        // harvest اول
        _harvestForStrategy(_strategyId);
        
        for (uint256 i = 0; i < _users.length; i++) {
            address user = _users[i];
            UserStrategyInfo storage userInfo = userStrategies[_strategyId][user];
            
            if (!userInfo.autoCompoundEnabled) continue;
            
            // محاسبه pending rewards
            uint256 totalPendingValue = 0;
            for (uint256 j = 0; j < strategy.rewardTokens.length; j++) {
                uint256 pending = _calculatePendingRewards(_strategyId, user, strategy.rewardTokens[j]);
                totalPendingValue = totalPendingValue.add(pending);
            }
            
            if (totalPendingValue >= compoundInfo.threshold) {
                _executeAutoCompound(_strategyId, user, totalPendingValue);
            }
        }
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    /**
     * @dev harvest rewards برای strategy
     */
    function _harvestForStrategy(uint256 _strategyId) internal {
        StrategyInfo storage strategy = strategies[_strategyId];
        
        // Check if harvest is needed (minimum time passed)
        if (block.timestamp < strategy.lastHarvestTime.add(1 hours)) {
            return;
        }
        
        uint256 totalHarvested = 0;
        
        // فراخوانی harvest از کانترکت strategy
        if (strategy.strategyContract != address(0)) {
            // در implementation واقعی، اینجا باید harvest method از strategy contract فراخوانی شود
            // totalHarvested = IStrategy(strategy.strategyContract).harvest();
        }
        
        if (totalHarvested > 0) {
            // محاسبه performance fee
            uint256 performanceFee = totalHarvested.mul(strategy.performanceFee).div(10000);
            
            if (performanceFee > 0) {
                // انتقال performance fee به treasury
                protocolRevenue = protocolRevenue.add(performanceFee);
            }
            
            strategy.lastHarvestTime = block.timestamp;
            
            emit Harvest(_strategyId, totalHarvested, performanceFee, msg.sender);
        }
    }
    
    /**
     * @dev محاسبه shares برای مقدار deposit
     */
    function _calculateShares(uint256 _strategyId, uint256 _amount) internal view returns (uint256) {
        StrategyInfo storage strategy = strategies[_strategyId];
        
        if (strategy.totalShares == 0 || strategy.totalDeposited == 0) {
            return _amount; // اولین deposit
        }
        
        return _amount.mul(strategy.totalShares).div(strategy.totalDeposited);
    }
    
    /**
     * @dev محاسبه مقدار withdraw برای shares
     */
    function _calculateWithdrawAmount(uint256 _strategyId, uint256 _shares) internal view returns (uint256) {
        StrategyInfo storage strategy = strategies[_strategyId];
        
        if (strategy.totalShares == 0) return 0;
        
        return _shares.mul(strategy.totalDeposited).div(strategy.totalShares);
    }
    
    /**
     * @dev محاسبه pending rewards برای کاربر
     */
    function _calculatePendingRewards(uint256 _strategyId, address _user, address _rewardToken)
        internal
        view
        returns (uint256)
    {
        UserStrategyInfo storage user = userStrategies[_strategyId][_user];
        StrategyInfo storage strategy = strategies[_strategyId];
        
        if (user.shares == 0 || strategy.totalShares == 0) return 0;
        
        // در implementation واقعی، اینجا باید pending rewards محاسبه شود
        // return userShare * accRewardPerShare - rewardDebt
        return 0; // placeholder
    }
    
    /**
     * @dev بروزرسانی reward debts برای کاربر
     */
    function _updateRewardDebts(uint256 _strategyId, address _user) internal {
        UserStrategyInfo storage user = userStrategies[_strategyId][_user];
        StrategyInfo storage strategy = strategies[_strategyId];
        
        for (uint256 i = 0; i < strategy.rewardTokens.length; i++) {
            address rewardToken = strategy.rewardTokens[i];
            // user.rewardDebts[rewardToken] = userShares * accRewardPerShare
            // در implementation واقعی باید دقیق محاسبه شود
        }
    }
    
    /**
     * @dev اجرای auto-compound برای کاربر
     */
    function _executeAutoCompound(uint256 _strategyId, address _user, uint256 _rewardValue) internal {
        AutoCompoundInfo storage compoundInfo = autoCompoundInfo[_strategyId];
        StrategyInfo storage strategy = strategies[_strategyId];
        UserStrategyInfo storage userInfo = userStrategies[_strategyId][_user];
        
        // محاسبه compound fee
        uint256 compoundFee = _rewardValue.mul(compoundInfo.compoundFee).div(10000);
        uint256 compoundAmount = _rewardValue.sub(compoundFee);
        
        // محاسبه shares جدید
        uint256 newShares = _calculateShares(_strategyId, compoundAmount);
        
        // بروزرسانی اطلاعات
        userInfo.shares = userInfo.shares.add(newShares);
        strategy.totalShares = strategy.totalShares.add(newShares);
        strategy.totalDeposited = strategy.totalDeposited.add(compoundAmount);
        
        compoundInfo.totalCompounded = compoundInfo.totalCompounded.add(compoundAmount);
        compoundInfo.lastCompoundTime = block.timestamp;
        
        // انتقال compound fee
        if (compoundFee > 0) {
            protocolRevenue = protocolRevenue.add(compoundFee);
        }
        
        emit AutoCompound(_strategyId, compoundAmount, newShares, _user);
    }
    
    // ==================== EMERGENCY FUNCTIONS ====================
    
    /**
     * @notice emergency withdraw (بدون reward)
     * @param _strategyId شناسه strategy
     */
    function emergencyWithdraw(uint256 _strategyId) external nonReentrant validStrategy(_strategyId) {
        UserStrategyInfo storage user = userStrategies[_strategyId][msg.sender];
        StrategyInfo storage strategy = strategies[_strategyId];
        
        uint256 shares = user.shares;
        if (shares == 0) revert YieldFarming__InsufficientShares();
        
        uint256 amount = _calculateWithdrawAmount(_strategyId, shares);
        
        // بروزرسانی اطلاعات
        user.shares = 0;
        user.pendingRewards = 0;
        strategy.totalShares = strategy.totalShares.sub(shares);
        strategy.totalDeposited = strategy.totalDeposited.sub(amount);
        
        // انتقال tokens
        IERC20(strategy.depositToken).safeTransfer(msg.sender, amount);
        
        totalValueLocked = totalValueLocked.sub(amount);
        
        emit Withdraw(msg.sender, _strategyId, shares, amount);
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @notice تنظیم default fees
     * @param _performanceFee کارمزد عملکرد پیش‌فرض
     * @param _managementFee کارمزد مدیریت پیش‌فرض
     */
    function setDefaultFees(uint256 _performanceFee, uint256 _managementFee)
        external
        onlyRole(OPERATOR_ROLE)
    {
        if (_performanceFee > MAX_PERFORMANCE_FEE) revert YieldFarming__InvalidFee();
        if (_managementFee > MAX_MANAGEMENT_FEE) revert YieldFarming__InvalidFee();
        
        defaultPerformanceFee = _performanceFee;
        defaultManagementFee = _managementFee;
    }
    
    /**
     * @notice تنظیم harvest threshold
     * @param _threshold حد آستانه جدید
     */
    function setHarvestThreshold(uint256 _threshold) external onlyRole(OPERATOR_ROLE) {
        harvestThreshold = _threshold;
    }
    
    /**
     * @notice تنظیم auto-compound برای strategy
     * @param _strategyId شناسه strategy
     * @param _enabled آیا فعال باشد
     * @param _threshold حد آستانه
     * @param _compoundFee کارمزد compound
     */
    function setAutoCompoundConfig(
        uint256 _strategyId,
        bool _enabled,
        uint256 _threshold,
        uint256 _compoundFee
    ) external onlyRole(OPERATOR_ROLE) validStrategy(_strategyId) {
        AutoCompoundInfo storage info = autoCompoundInfo[_strategyId];
        info.enabled = _enabled;
        info.threshold = _threshold;
        info.compoundFee = _compoundFee;
    }
    
    /**
     * @notice تنظیم treasury
     * @param _treasury آدرس treasury جدید
     */
    function setTreasury(address _treasury) external onlyRole(OPERATOR_ROLE) {
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }
    
    /**
     * @notice تغییر وضعیت emergency mode
     * @param _enabled آیا فعال باشد
     */
    function setEmergencyMode(bool _enabled) external onlyRole(EMERGENCY_ROLE) {
        emergencyMode = _enabled;
        emit EmergencyModeToggled(_enabled);
    }
    
    /**
     * @notice withdraw protocol revenue
     * @param _amount مقدار برای withdraw
     */
    function withdrawProtocolRevenue(uint256 _amount) external onlyRole(OPERATOR_ROLE) {
        if (_amount > protocolRevenue) revert YieldFarming__InsufficientAmount();
        
        protocolRevenue = protocolRevenue.sub(_amount);
        laxceToken.transfer(treasury, _amount);
    }
    
    /**
     * @notice توقف اضطراری
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @notice لغو توقف
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @notice دریافت تعداد strategies
     */
    function strategiesLength() external view returns (uint256) {
        return strategies.length;
    }
    
    /**
     * @notice دریافت اطلاعات strategy
     * @param _strategyId شناسه strategy
     */
    function getStrategyInfo(uint256 _strategyId) external view returns (StrategyInfo memory) {
        if (_strategyId >= strategies.length) revert YieldFarming__InvalidStrategy();
        return strategies[_strategyId];
    }
    
    /**
     * @notice دریافت اطلاعات کاربر در strategy
     * @param _strategyId شناسه strategy
     * @param _user آدرس کاربر
     */
    function getUserStrategyInfo(uint256 _strategyId, address _user)
        external
        view
        returns (
            uint256 shares,
            uint256 depositTime,
            uint256 lastClaimTime,
            uint256 totalDeposited,
            uint256 totalRewarded,
            bool autoCompoundEnabled
        )
    {
        UserStrategyInfo storage user = userStrategies[_strategyId][_user];
        return (
            user.shares,
            user.depositTime,
            user.lastClaimTime,
            user.totalDeposited,
            user.totalRewarded,
            user.autoCompoundEnabled
        );
    }
    
    /**
     * @notice محاسبه pending rewards برای کاربر
     * @param _strategyId شناسه strategy
     * @param _user آدرس کاربر
     * @param _rewardToken آدرس reward token
     */
    function pendingRewards(uint256 _strategyId, address _user, address _rewardToken)
        external
        view
        returns (uint256)
    {
        return _calculatePendingRewards(_strategyId, _user, _rewardToken);
    }
    
    /**
     * @notice محاسبه share price برای strategy
     * @param _strategyId شناسه strategy
     */
    function getSharePrice(uint256 _strategyId) external view returns (uint256) {
        if (_strategyId >= strategies.length) return 0;
        
        StrategyInfo storage strategy = strategies[_strategyId];
        if (strategy.totalShares == 0) return 1e18; // price = 1.0
        
        return strategy.totalDeposited.mul(1e18).div(strategy.totalShares);
    }
    
    /**
     * @notice دریافت آمار کلی
     */
    function getGlobalStats() external view returns (
        uint256 totalStrategies,
        uint256 activeStrategies,
        uint256 totalValueLockedAmount,
        uint256 totalProtocolRevenue
    ) {
        totalStrategies = strategies.length;
        totalValueLockedAmount = totalValueLocked;
        totalProtocolRevenue = protocolRevenue;
        
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].isActive) {
                activeStrategies++;
            }
        }
    }
} 