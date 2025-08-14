// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol" as OZAccessControl;
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/Constants.sol";

/**
 * @title LaxceAccessControl
 * @dev مدیریت کنترل دسترسی برای تمام کانترکت‌های LAXCE DEX
 * @notice این کانترکت اساس سیستم مجوزها و نقش‌ها است
 */
contract LaxceAccessControl is OZAccessControl.AccessControl, Pausable {
    using ReentrancyGuard for ReentrancyGuard.ReentrancyData;
    
    // ==================== ROLE DEFINITIONS ====================
    
    /// @dev نقش مالک اصلی سیستم
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    
    /// @dev نقش ادمین سیستم
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @dev نقش اپراتور
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @dev نقش توقف‌کننده (در شرایط اضطراری)
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    /// @dev نقش ارتقادهنده کانترکت‌ها
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    /// @dev نقش مدیریت treasury
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    
    /// @dev نقش مدیریت Oracle
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    
    /// @dev نقش مدیریت Pool
    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");
    
    /// @dev نقش emergency (اضطراری)
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    /// @dev نقش مدیریت Fee
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev محافظت از reentrancy
    ReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    /// @dev آدرس deployer اولیه
    address public immutable DEPLOYER;
    
    /// @dev تاریخ deployment
    uint256 public immutable DEPLOYMENT_TIME;
    
    /// @dev mapping برای tracking role history
    mapping(bytes32 => mapping(address => uint256)) public roleGrantedAt;
    
    /// @dev mapping برای tracking role expiration
    mapping(bytes32 => mapping(address => uint256)) public roleExpiresAt;
    
    /// @dev حداکثر مدت زمان role (اختیاری)
    mapping(bytes32 => uint256) public maxRoleDuration;
    
    /// @dev آیا role های محدود زمانی فعال است
    bool public timeBasedRolesEnabled;
    
    /// @dev تعداد کل members برای هر role
    mapping(bytes32 => uint256) public roleMemberCount;
    
    /// @dev حداکثر تعداد اعضا برای هر role
    mapping(bytes32 => uint256) public maxRoleMembers;
    
    // ==================== EVENTS ====================
    
    event RoleGrantedWithExpiration(bytes32 indexed role, address indexed account, uint256 expiresAt);
    event RoleExpired(bytes32 indexed role, address indexed account);
    event RoleRenewed(bytes32 indexed role, address indexed account, uint256 newExpiresAt);
    event MaxRoleDurationSet(bytes32 indexed role, uint256 duration);
    event MaxRoleMembersSet(bytes32 indexed role, uint256 maxMembers);
    event TimeBasedRolesToggled(bool enabled);
    event EmergencyActionExecuted(address indexed executor, string action, bytes data);
    
    // ==================== ERRORS ====================
    
    error AccessControl__RoleExpired();
    error AccessControl__RoleMemberLimitExceeded();
    error AccessControl__InvalidDuration();
    error AccessControl__NotAuthorized();
    error AccessControl__ZeroAddress();
    error AccessControl__SelfRevoke();
    error AccessControl__InvalidRole();
    
    // ==================== MODIFIERS ====================
    
    /**
     * @dev بررسی role با در نظر گیری expiration
     */
    modifier onlyValidRole(bytes32 role) {
        if (!hasValidRole(msg.sender, role)) {
            revert AccessControl__NotAuthorized();
        }
        _;
    }
    
    /**
     * @dev محافظت از reentrancy
     */
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor() {
        DEPLOYER = msg.sender;
        DEPLOYMENT_TIME = block.timestamp;
        
        // مقداردهی اولیه reentrancy guard
        _reentrancyGuard.initialize();
        
        // تنظیم role hierarchy
        _setupRoleHierarchy();
        
        // اعطای نقش‌های اولیه به deployer
        _setupInitialRoles(msg.sender);
        
        // تنظیم حداکثر اعضا برای roles
        _setupRoleLimits();
    }
    
    // ==================== MAIN FUNCTIONS ====================
    
    /**
     * @dev اعطای role با expiration
     * @param role نقش مورد نظر
     * @param account آدرس دریافت‌کننده
     * @param duration مدت زمان role (0 = بدون انقضا)
     */
    function grantRoleWithExpiration(
        bytes32 role,
        address account,
        uint256 duration
    ) external onlyValidRole(getRoleAdmin(role)) nonReentrant {
        if (account == address(0)) revert AccessControl__ZeroAddress();
        
        // بررسی محدودیت تعداد اعضا
        if (roleMemberCount[role] >= maxRoleMembers[role] && maxRoleMembers[role] > 0) {
            if (!hasRole(role, account)) {
                revert AccessControl__RoleMemberLimitExceeded();
            }
        }
        
        // بررسی duration
        if (duration > 0 && maxRoleDuration[role] > 0 && duration > maxRoleDuration[role]) {
            revert AccessControl__InvalidDuration();
        }
        
        // اعطای role
        if (!hasRole(role, account)) {
            _grantRole(role, account);
            roleMemberCount[role]++;
        }
        
        // تنظیم زمان‌ها
        roleGrantedAt[role][account] = block.timestamp;
        
        if (timeBasedRolesEnabled && duration > 0) {
            roleExpiresAt[role][account] = block.timestamp + duration;
            emit RoleGrantedWithExpiration(role, account, block.timestamp + duration);
        } else {
            roleExpiresAt[role][account] = 0; // بدون انقضا
        }
    }
    
    /**
     * @dev تمدید role
     * @param role نقش مورد نظر
     * @param account آدرس هدف
     * @param additionalDuration مدت اضافی
     */
    function renewRole(
        bytes32 role,
        address account,
        uint256 additionalDuration
    ) external onlyValidRole(getRoleAdmin(role)) {
        if (!hasRole(role, account)) revert AccessControl__NotAuthorized();
        if (additionalDuration == 0) revert AccessControl__InvalidDuration();
        
        uint256 currentExpiry = roleExpiresAt[role][account];
        uint256 newExpiry;
        
        if (currentExpiry == 0) {
            // Role بدون انقضا - تنظیم از الان
            newExpiry = block.timestamp + additionalDuration;
        } else {
            // اضافه کردن به زمان فعلی
            newExpiry = currentExpiry + additionalDuration;
        }
        
        // بررسی حد مجاز
        if (maxRoleDuration[role] > 0) {
            uint256 totalDuration = newExpiry - roleGrantedAt[role][account];
            if (totalDuration > maxRoleDuration[role]) {
                revert AccessControl__InvalidDuration();
            }
        }
        
        roleExpiresAt[role][account] = newExpiry;
        emit RoleRenewed(role, account, newExpiry);
    }
    
    /**
     * @dev لغو role
     * @param role نقش مورد نظر
     * @param account آدرس هدف
     */
    function revokeRole(bytes32 role, address account) 
        public 
        override 
        onlyValidRole(getRoleAdmin(role)) 
    {
        if (account == msg.sender) revert AccessControl__SelfRevoke();
        
        if (hasRole(role, account)) {
            _revokeRole(role, account);
            roleMemberCount[role]--;
        }
        
        // پاک کردن اطلاعات زمانی
        delete roleGrantedAt[role][account];
        delete roleExpiresAt[role][account];
    }
    
    /**
     * @dev بررسی role با در نظر گیری expiration
     * @param account آدرس هدف
     * @param role نقش مورد نظر
     * @return true اگر role معتبر باشد
     */
    function hasValidRole(address account, bytes32 role) public view returns (bool) {
        if (!hasRole(role, account)) return false;
        
        if (!timeBasedRolesEnabled) return true;
        
        uint256 expiresAt = roleExpiresAt[role][account];
        if (expiresAt == 0) return true; // بدون انقضا
        
        return block.timestamp <= expiresAt;
    }
    
    /**
     * @dev پاک کردن roles منقضی شده
     * @param role نقش مورد نظر
     * @param accounts لیست آدرس‌ها
     */
    function cleanupExpiredRoles(bytes32 role, address[] calldata accounts) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        for (uint i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            
            if (hasRole(role, account) && !hasValidRole(account, role)) {
                _revokeRole(role, account);
                roleMemberCount[role]--;
                
                delete roleGrantedAt[role][account];
                delete roleExpiresAt[role][account];
                
                emit RoleExpired(role, account);
            }
        }
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @dev تنظیم حداکثر مدت role
     * @param role نقش مورد نظر
     * @param duration حداکثر مدت (ثانیه)
     */
    function setMaxRoleDuration(bytes32 role, uint256 duration) 
        external 
        onlyValidRole(OWNER_ROLE) 
    {
        maxRoleDuration[role] = duration;
        emit MaxRoleDurationSet(role, duration);
    }
    
    /**
     * @dev تنظیم حداکثر تعداد اعضای role
     * @param role نقش مورد نظر
     * @param maxMembers حداکثر تعداد اعضا
     */
    function setMaxRoleMembers(bytes32 role, uint256 maxMembers) 
        external 
        onlyValidRole(OWNER_ROLE) 
    {
        maxRoleMembers[role] = maxMembers;
        emit MaxRoleMembersSet(role, maxMembers);
    }
    
    /**
     * @dev فعال/غیرفعال کردن time-based roles
     * @param enabled وضعیت جدید
     */
    function setTimeBasedRolesEnabled(bool enabled) 
        external 
        onlyValidRole(OWNER_ROLE) 
    {
        timeBasedRolesEnabled = enabled;
        emit TimeBasedRolesToggled(enabled);
    }
    
    /**
     * @dev توقف سیستم در شرایط اضطراری
     */
    function emergencyPause() external onlyValidRole(EMERGENCY_ROLE) {
        _pause();
        emit EmergencyActionExecuted(msg.sender, "PAUSE", "");
    }
    
    /**
     * @dev راه‌اندازی مجدد سیستم
     */
    function emergencyUnpause() external onlyValidRole(OWNER_ROLE) {
        _unpause();
        emit EmergencyActionExecuted(msg.sender, "UNPAUSE", "");
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @dev دریافت اطلاعات role
     * @param role نقش مورد نظر
     * @param account آدرس هدف
     */
    function getRoleInfo(bytes32 role, address account) 
        external 
        view 
        returns (
            bool hasRole_,
            bool isValid,
            uint256 grantedAt,
            uint256 expiresAt,
            uint256 remainingTime
        ) 
    {
        hasRole_ = hasRole(role, account);
        isValid = hasValidRole(account, role);
        grantedAt = roleGrantedAt[role][account];
        expiresAt = roleExpiresAt[role][account];
        
        if (expiresAt > 0 && block.timestamp < expiresAt) {
            remainingTime = expiresAt - block.timestamp;
        }
    }
    
    /**
     * @dev دریافت تمام roles یک account
     * @param account آدرس هدف
     * @return لیست roles
     */
    function getAllRoles(address account) external view returns (bytes32[] memory) {
        bytes32[] memory allRoles = new bytes32[](10);
        allRoles[0] = OWNER_ROLE;
        allRoles[1] = ADMIN_ROLE;
        allRoles[2] = OPERATOR_ROLE;
        allRoles[3] = PAUSER_ROLE;
        allRoles[4] = UPGRADER_ROLE;
        allRoles[5] = TREASURY_ROLE;
        allRoles[6] = ORACLE_ROLE;
        allRoles[7] = POOL_MANAGER_ROLE;
        allRoles[8] = EMERGENCY_ROLE;
        allRoles[9] = FEE_MANAGER_ROLE;
        
        uint256 count = 0;
        for (uint i = 0; i < allRoles.length; i++) {
            if (hasValidRole(account, allRoles[i])) {
                allRoles[count] = allRoles[i];
                count++;
            }
        }
        
        // کاهش سایز array
        bytes32[] memory validRoles = new bytes32[](count);
        for (uint i = 0; i < count; i++) {
            validRoles[i] = allRoles[i];
        }
        
        return validRoles;
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    /**
     * @dev تنظیم role hierarchy
     */
    function _setupRoleHierarchy() private {
        // OWNER -> بالاترین سطح
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        
        // ADMIN -> تحت نظر OWNER
        _setRoleAdmin(ADMIN_ROLE, OWNER_ROLE);
        
        // سایر roles تحت نظر ADMIN
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(UPGRADER_ROLE, OWNER_ROLE); // فقط OWNER
        _setRoleAdmin(TREASURY_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ORACLE_ROLE, ADMIN_ROLE);
        _setRoleAdmin(POOL_MANAGER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(EMERGENCY_ROLE, OWNER_ROLE); // فقط OWNER
        _setRoleAdmin(FEE_MANAGER_ROLE, ADMIN_ROLE);
    }
    
    /**
     * @dev تنظیم roles اولیه
     * @param deployer آدرس deployer
     */
    function _setupInitialRoles(address deployer) private {
        // اعطای تمام نقش‌ها به deployer
        _grantRole(DEFAULT_ADMIN_ROLE, deployer);
        _grantRole(OWNER_ROLE, deployer);
        _grantRole(ADMIN_ROLE, deployer);
        _grantRole(EMERGENCY_ROLE, deployer);
        
        // به‌روزرسانی counters
        roleMemberCount[DEFAULT_ADMIN_ROLE] = 1;
        roleMemberCount[OWNER_ROLE] = 1;
        roleMemberCount[ADMIN_ROLE] = 1;
        roleMemberCount[EMERGENCY_ROLE] = 1;
        
        // ثبت زمان
        roleGrantedAt[DEFAULT_ADMIN_ROLE][deployer] = block.timestamp;
        roleGrantedAt[OWNER_ROLE][deployer] = block.timestamp;
        roleGrantedAt[ADMIN_ROLE][deployer] = block.timestamp;
        roleGrantedAt[EMERGENCY_ROLE][deployer] = block.timestamp;
    }
    
    /**
     * @dev تنظیم محدودیت‌های role
     */
    function _setupRoleLimits() private {
        // تنظیم حداکثر اعضا
        maxRoleMembers[OWNER_ROLE] = 3;        // حداکثر 3 owner
        maxRoleMembers[ADMIN_ROLE] = 10;       // حداکثر 10 admin
        maxRoleMembers[EMERGENCY_ROLE] = 5;    // حداکثر 5 emergency
        maxRoleMembers[UPGRADER_ROLE] = 2;     // حداکثر 2 upgrader
        
        // تنظیم حداکثر مدت (برای roles غیر کریتیکال)
        maxRoleDuration[OPERATOR_ROLE] = 365 days;      // 1 سال
        maxRoleDuration[ORACLE_ROLE] = 180 days;        // 6 ماه
        maxRoleDuration[POOL_MANAGER_ROLE] = 365 days;  // 1 سال
        maxRoleDuration[FEE_MANAGER_ROLE] = 90 days;    // 3 ماه
    }
    
    // ==================== OVERRIDES ====================
    
    /**
     * @dev Override برای پشتیبانی از interface detection
     */
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }
} 