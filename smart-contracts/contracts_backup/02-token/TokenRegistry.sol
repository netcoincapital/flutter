// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../01-core/AccessControl.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";

/**
 * @title TokenRegistry
 * @dev رجیستری توکن‌ها با قابلیت‌های listing fee، token tiers، whitelist/blacklist
 * @notice این کانترکت مدیریت تمام توکن‌های قابل استفاده در DEX را بر عهده دارد
 */
contract TokenRegistry is Pausable, LaxceAccessControl {
    using Strings for uint256;
    using ReentrancyGuard for ReentrancyGuard.ReentrancyData;
    
    // ==================== CONSTANTS ====================
    
    /// @dev حداکثر تعداد توکن‌ها
    uint256 public constant MAX_TOKENS = 10000;
    
    /// @dev حداقل listing fee (0.01 ETH)
    uint256 public constant MIN_LISTING_FEE = 0.01 ether;
    
    /// @dev حداکثر listing fee (10 ETH)
    uint256 public constant MAX_LISTING_FEE = 10 ether;
    
    /// @dev مدت زمان پیش‌فرض evaluation (7 روز)
    uint256 public constant DEFAULT_EVALUATION_PERIOD = 7 days;
    
    /// @dev حداکثر مدت evaluation (30 روز)
    uint256 public constant MAX_EVALUATION_PERIOD = 30 days;
    
    // ==================== ENUMS ====================
    
    /// @dev وضعیت‌های مختلف توکن
    enum TokenStatus {
        PENDING,        // در انتظار بررسی
        APPROVED,       // تایید شده
        REJECTED,       // رد شده
        SUSPENDED,      // تعلیق شده
        DELISTED       // از لیست خارج شده
    }
    
    /// @dev tier های مختلف توکن
    enum TokenTier {
        UNVERIFIED,     // تایید نشده
        VERIFIED,       // تایید شده
        PREMIUM,        // پریمیوم
        BLUE_CHIP,      // آبی رنگ (معتبر)
        GOVERNANCE      // حکومتی
    }
    
    /// @dev نوع‌های مختلف توکن
    enum TokenType {
        STANDARD,       // استاندارد
        DEFLATIONARY,   // کاهشی
        INFLATIONARY,   // افزایشی
        REBASE,         // بازتنظیم
        GOVERNANCE,     // حکومتی
        UTILITY,        // ابزاری
        STABLECOIN,     // ثابت
        WRAPPED,        // بسته‌بندی شده
        SYNTHETIC       // مصنوعی
    }
    
    // ==================== STRUCTS ====================
    
    /// @dev اطلاعات کامل توکن
    struct TokenInfo {
        address tokenAddress;           // آدرس توکن
        string name;                    // نام توکن
        string symbol;                  // نماد توکن
        uint8 decimals;                 // تعداد اعشار
        uint256 totalSupply;            // کل عرضه
        TokenStatus status;             // وضعیت
        TokenTier tier;                 // tier
        TokenType tokenType;            // نوع توکن
        uint256 listingTime;            // زمان لیست
        uint256 listingFee;             // کارمزد لیست
        address lister;                 // لیست‌کننده
        string description;             // توضیحات
        string website;                 // وب‌سایت
        string logoUrl;                 // آدرس لوگو
        bool hasAudit;                  // آیا audit شده
        string auditUrl;                // لینک audit
        uint256 liquidityThreshold;    // حد آستانه نقدینگی
        mapping(string => string) metadata; // متادیتای اضافی
    }
    
    /// @dev اطلاعات listing fee
    struct ListingFeeInfo {
        uint256 baseFee;                // کارمزد پایه
        uint256 tierMultiplier;         // ضریب tier
        uint256 discountRate;           // نرخ تخفیف
        bool dynamicPricing;            // قیمت‌گذاری پویا
    }
    
    /// @dev اطلاعات whitelist/blacklist
    struct ListInfo {
        bool isWhitelisted;             // در whitelist است
        bool isBlacklisted;             // در blacklist است
        uint256 addedTime;              // زمان اضافه شدن
        string reason;                  // دلیل
        address addedBy;                // اضافه‌کننده
    }
    
    /// @dev آمار توکن
    struct TokenStats {
        uint256 totalVolume;            // کل حجم معاملات
        uint256 totalLiquidity;         // کل نقدینگی
        uint256 dailyVolume;            // حجم روزانه
        uint256 weeklyVolume;           // حجم هفتگی
        uint256 monthlyVolume;          // حجم ماهانه
        uint256 lastUpdated;            // آخرین به‌روزرسانی
        uint256 priceUSD;               // قیمت بر حسب دلار
        uint256 marketCap;              // سرمایه بازار
    }
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev محافظت از reentrancy
    ReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    /// @dev mapping از آدرس به اطلاعات توکن
    mapping(address => TokenInfo) public tokenInfo;
    
    /// @dev mapping از آدرس به وضعیت whitelist/blacklist
    mapping(address => ListInfo) public listInfo;
    
    /// @dev mapping از آدرس به آمار توکن
    mapping(address => TokenStats) public tokenStats;
    
    /// @dev لیست تمام توکن‌های ثبت شده
    address[] public allTokens;
    
    /// @dev mapping برای بررسی وجود توکن
    mapping(address => bool) public isTokenRegistered;
    
    /// @dev اطلاعات listing fee
    ListingFeeInfo public listingFeeInfo;
    
    /// @dev آدرس treasury برای دریافت fees
    address public treasury;
    
    /// @dev تعداد کل توکن‌های ثبت شده
    uint256 public totalTokens;
    
    /// @dev آیا نیاز به تایید admin برای listing است
    bool public requiresApproval = true;
    
    /// @dev حداقل نقدینگی برای auto-approval
    uint256 public minLiquidityForAutoApproval = 10000 * Constants.DECIMAL_BASE;
    
    /// @dev مدت زمان evaluation
    uint256 public evaluationPeriod = DEFAULT_EVALUATION_PERIOD;
    
    /// @dev mapping برای metadata keys معتبر
    mapping(string => bool) public validMetadataKeys;
    
    // ==================== EVENTS ====================
    
    event TokenListed(
        address indexed token,
        address indexed lister,
        TokenTier tier,
        uint256 fee,
        uint256 timestamp
    );
    
    event TokenStatusUpdated(
        address indexed token,
        TokenStatus oldStatus,
        TokenStatus newStatus,
        address indexed updatedBy
    );
    
    event TokenTierUpdated(
        address indexed token,
        TokenTier oldTier,
        TokenTier newTier,
        address indexed updatedBy
    );
    
    event TokenWhitelisted(address indexed token, address indexed addedBy, string reason);
    event TokenBlacklisted(address indexed token, address indexed addedBy, string reason);
    event TokenRemovedFromWhitelist(address indexed token, address indexed removedBy);
    event TokenRemovedFromBlacklist(address indexed token, address indexed removedBy);
    
    event ListingFeeUpdated(uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event TokenStatsUpdated(address indexed token, uint256 volume, uint256 liquidity);
    event TokenDelisted(address indexed token, address indexed delistedBy, string reason);
    
    event TokenMetadataUpdated(
        address indexed token,
        string key,
        string oldValue,
        string newValue
    );
    
    // ==================== ERRORS ====================
    
    error TokenRegistry__TokenAlreadyRegistered();
    error TokenRegistry__TokenNotRegistered();
    error TokenRegistry__InvalidTokenAddress();
    error TokenRegistry__InsufficientFee();
    error TokenRegistry__TokenNotApproved();
    error TokenRegistry__TokenBlacklisted();
    error TokenRegistry__InvalidTier();
    error TokenRegistry__InvalidStatus();
    error TokenRegistry__MaxTokensReached();
    error TokenRegistry__ZeroAddress();
    error TokenRegistry__InvalidFeeAmount();
    error TokenRegistry__InvalidMetadataKey();
    error TokenRegistry__TokenSuspended();
    error TokenRegistry__EvaluationPeriodNotExpired();
    
    // ==================== MODIFIERS ====================
    
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }
    
    modifier validToken(address token) {
        if (token == address(0)) revert TokenRegistry__ZeroAddress();
        if (token == address(this)) revert TokenRegistry__InvalidTokenAddress();
        _;
    }
    
    modifier tokenRegistered(address token) {
        if (!isTokenRegistered[token]) revert TokenRegistry__TokenNotRegistered();
        _;
    }
    
    modifier tokenNotBlacklisted(address token) {
        if (listInfo[token].isBlacklisted) revert TokenRegistry__TokenBlacklisted();
        _;
    }
    
    modifier tokenNotSuspended(address token) {
        if (tokenInfo[token].status == TokenStatus.SUSPENDED) {
            revert TokenRegistry__TokenSuspended();
        }
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(address _treasury) validToken(_treasury) {
        treasury = _treasury;
        
        // مقداردهی اولیه reentrancy guard
        _reentrancyGuard.initialize();
        
        // تنظیم listing fee اولیه
        listingFeeInfo = ListingFeeInfo({
            baseFee: Constants.TOKEN_LISTING_FEE,
            tierMultiplier: Constants.FEE_BASE, // 1x برای پایه
            discountRate: 0,
            dynamicPricing: false
        });
        
        // تنظیم metadata keys معتبر
        _setupValidMetadataKeys();
    }
    
    // ==================== TOKEN LISTING FUNCTIONS ====================
    
    /**
     * @dev لیست کردن توکن جدید
     * @param token آدرس توکن
     * @param tier سطح توکن
     * @param tokenType نوع توکن
     * @param description توضیحات
     * @param website وب‌سایت
     * @param logoUrl آدرس لوگو
     */
    function listToken(
        address token,
        TokenTier tier,
        TokenType tokenType,
        string calldata description,
        string calldata website,
        string calldata logoUrl
    ) external payable nonReentrant whenNotPaused validToken(token) {
        if (isTokenRegistered[token]) revert TokenRegistry__TokenAlreadyRegistered();
        if (totalTokens >= MAX_TOKENS) revert TokenRegistry__MaxTokensReached();
        
        // محاسبه listing fee
        uint256 requiredFee = calculateListingFee(tier);
        if (msg.value < requiredFee) revert TokenRegistry__InsufficientFee();
        
        // دریافت اطلاعات توکن از کانترکت
        (string memory name, string memory symbol, uint8 decimals, uint256 totalSupply) = 
            _getTokenMetadata(token);
        
        // ایجاد TokenInfo
        TokenInfo storage info = tokenInfo[token];
        info.tokenAddress = token;
        info.name = name;
        info.symbol = symbol;
        info.decimals = decimals;
        info.totalSupply = totalSupply;
        info.status = requiresApproval ? TokenStatus.PENDING : TokenStatus.APPROVED;
        info.tier = tier;
        info.tokenType = tokenType;
        info.listingTime = block.timestamp;
        info.listingFee = requiredFee;
        info.lister = msg.sender;
        info.description = description;
        info.website = website;
        info.logoUrl = logoUrl;
        info.liquidityThreshold = _calculateLiquidityThreshold(tier);
        
        // اضافه کردن به لیست‌ها
        allTokens.push(token);
        isTokenRegistered[token] = true;
        totalTokens = totalTokens.add(1);
        
        // انتقال fee به treasury
        if (requiredFee > 0) {
            (bool success, ) = payable(treasury).call{value: requiredFee}("");
            require(success, "Fee transfer failed");
        }
        
        // بازگشت مازاد پرداختی
        if (msg.value > requiredFee) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - requiredFee}("");
            require(success, "Refund failed");
        }
        
        emit TokenListed(token, msg.sender, tier, requiredFee, block.timestamp);
    }
    
    /**
     * @dev محاسبه listing fee
     * @param tier سطح توکن
     * @return مقدار fee
     */
    function calculateListingFee(TokenTier tier) public view returns (uint256) {
        uint256 baseFee = listingFeeInfo.baseFee;
        uint256 multiplier = _getTierMultiplier(tier);
        
        uint256 fee = baseFee.mul(multiplier).div(Constants.FEE_BASE);
        
        // اعمال تخفیف
        if (listingFeeInfo.discountRate > 0) {
            uint256 discount = fee.mul(listingFeeInfo.discountRate).div(Constants.FEE_BASE);
            fee = fee.sub(discount);
        }
        
        return fee;
    }
    
    /**
     * @dev به‌روزرسانی وضعیت توکن
     * @param token آدرس توکن
     * @param newStatus وضعیت جدید
     */
    function updateTokenStatus(
        address token,
        TokenStatus newStatus
    ) external onlyValidRole(ADMIN_ROLE) tokenRegistered(token) {
        TokenStatus oldStatus = tokenInfo[token].status;
        tokenInfo[token].status = newStatus;
        
        emit TokenStatusUpdated(token, oldStatus, newStatus, msg.sender);
    }
    
    /**
     * @dev به‌روزرسانی tier توکن
     * @param token آدرس توکن
     * @param newTier tier جدید
     */
    function updateTokenTier(
        address token,
        TokenTier newTier
    ) external onlyValidRole(ADMIN_ROLE) tokenRegistered(token) {
        TokenTier oldTier = tokenInfo[token].tier;
        tokenInfo[token].tier = newTier;
        
        emit TokenTierUpdated(token, oldTier, newTier, msg.sender);
    }
    
    // ==================== WHITELIST/BLACKLIST FUNCTIONS ====================
    
    /**
     * @dev اضافه کردن توکن به whitelist
     * @param token آدرس توکن
     * @param reason دلیل
     */
    function addToWhitelist(
        address token,
        string calldata reason
    ) external onlyValidRole(ADMIN_ROLE) validToken(token) {
        ListInfo storage info = listInfo[token];
        info.isWhitelisted = true;
        info.isBlacklisted = false; // حذف از blacklist
        info.addedTime = block.timestamp;
        info.reason = reason;
        info.addedBy = msg.sender;
        
        emit TokenWhitelisted(token, msg.sender, reason);
    }
    
    /**
     * @dev اضافه کردن توکن به blacklist
     * @param token آدرس توکن
     * @param reason دلیل
     */
    function addToBlacklist(
        address token,
        string calldata reason
    ) external onlyValidRole(ADMIN_ROLE) validToken(token) {
        ListInfo storage info = listInfo[token];
        info.isBlacklisted = true;
        info.isWhitelisted = false; // حذف از whitelist
        info.addedTime = block.timestamp;
        info.reason = reason;
        info.addedBy = msg.sender;
        
        // تعلیق توکن در صورت وجود در رجیستری
        if (isTokenRegistered[token]) {
            tokenInfo[token].status = TokenStatus.SUSPENDED;
        }
        
        emit TokenBlacklisted(token, msg.sender, reason);
    }
    
    /**
     * @dev حذف توکن از whitelist
     * @param token آدرس توکن
     */
    function removeFromWhitelist(
        address token
    ) external onlyValidRole(ADMIN_ROLE) validToken(token) {
        listInfo[token].isWhitelisted = false;
        emit TokenRemovedFromWhitelist(token, msg.sender);
    }
    
    /**
     * @dev حذف توکن از blacklist
     * @param token آدرس توکن
     */
    function removeFromBlacklist(
        address token
    ) external onlyValidRole(ADMIN_ROLE) validToken(token) {
        listInfo[token].isBlacklisted = false;
        
        // بازگشت به وضعیت approved در صورت وجود در رجیستری
        if (isTokenRegistered[token] && tokenInfo[token].status == TokenStatus.SUSPENDED) {
            tokenInfo[token].status = TokenStatus.APPROVED;
        }
        
        emit TokenRemovedFromBlacklist(token, msg.sender);
    }
    
    // ==================== TOKEN STATS FUNCTIONS ====================
    
    /**
     * @dev به‌روزرسانی آمار توکن
     * @param token آدرس توکن
     * @param volume حجم جدید
     * @param liquidity نقدینگی جدید
     * @param priceUSD قیمت USD
     */
    function updateTokenStats(
        address token,
        uint256 volume,
        uint256 liquidity,
        uint256 priceUSD
    ) external onlyValidRole(OPERATOR_ROLE) tokenRegistered(token) {
        TokenStats storage stats = tokenStats[token];
        
        // به‌روزرسانی آمار روزانه/هفتگی/ماهانه
        _updatePeriodVolumes(token, volume);
        
        stats.totalVolume = stats.totalVolume.add(volume);
        stats.totalLiquidity = liquidity;
        stats.priceUSD = priceUSD;
        stats.lastUpdated = block.timestamp;
        
        // محاسبه market cap
        uint256 totalSupply = tokenInfo[token].totalSupply;
        stats.marketCap = totalSupply.mul(priceUSD).div(10**tokenInfo[token].decimals);
        
        emit TokenStatsUpdated(token, volume, liquidity);
    }
    
    /**
     * @dev delist کردن توکن
     * @param token آدرس توکن
     * @param reason دلیل
     */
    function delistToken(
        address token,
        string calldata reason
    ) external onlyValidRole(ADMIN_ROLE) tokenRegistered(token) {
        tokenInfo[token].status = TokenStatus.DELISTED;
        emit TokenDelisted(token, msg.sender, reason);
    }
    
    // ==================== METADATA FUNCTIONS ====================
    
    /**
     * @dev تنظیم metadata توکن
     * @param token آدرس توکن
     * @param key کلید metadata
     * @param value مقدار
     */
    function setTokenMetadata(
        address token,
        string calldata key,
        string calldata value
    ) external tokenRegistered(token) {
        require(
            msg.sender == tokenInfo[token].lister || hasValidRole(msg.sender, ADMIN_ROLE),
            "Not authorized"
        );
        
        if (!validMetadataKeys[key]) revert TokenRegistry__InvalidMetadataKey();
        
        string memory oldValue = tokenInfo[token].metadata[key];
        tokenInfo[token].metadata[key] = value;
        
        emit TokenMetadataUpdated(token, key, oldValue, value);
    }
    
    /**
     * @dev دریافت metadata توکن
     * @param token آدرس توکن
     * @param key کلید metadata
     * @return مقدار metadata
     */
    function getTokenMetadata(
        address token,
        string calldata key
    ) external view tokenRegistered(token) returns (string memory) {
        return tokenInfo[token].metadata[key];
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @dev تنظیم listing fee
     * @param newBaseFee کارمزد پایه جدید
     */
    function setListingFee(uint256 newBaseFee) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        if (newBaseFee < MIN_LISTING_FEE || newBaseFee > MAX_LISTING_FEE) {
            revert TokenRegistry__InvalidFeeAmount();
        }
        
        uint256 oldFee = listingFeeInfo.baseFee;
        listingFeeInfo.baseFee = newBaseFee;
        
        emit ListingFeeUpdated(oldFee, newBaseFee);
    }
    
    /**
     * @dev تنظیم treasury
     * @param newTreasury آدرس treasury جدید
     */
    function setTreasury(address newTreasury) 
        external 
        onlyValidRole(OWNER_ROLE) 
        validToken(newTreasury) 
    {
        address oldTreasury = treasury;
        treasury = newTreasury;
        
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }
    
    /**
     * @dev تنظیم نیاز به تایید
     * @param required آیا نیاز به تایید است
     */
    function setRequiresApproval(bool required) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        requiresApproval = required;
    }
    
    /**
     * @dev تنظیم مدت evaluation
     * @param newPeriod مدت جدید
     */
    function setEvaluationPeriod(uint256 newPeriod) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        require(newPeriod <= MAX_EVALUATION_PERIOD, "Period too long");
        evaluationPeriod = newPeriod;
    }
    
    /**
     * @dev افزودن metadata key معتبر
     * @param key کلید جدید
     */
    function addValidMetadataKey(string calldata key) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        validMetadataKeys[key] = true;
    }
    
    /**
     * @dev pause کردن کانترکت
     */
    function pause() external onlyValidRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @dev unpause کردن کانترکت
     */
    function unpause() external onlyValidRole(ADMIN_ROLE) {
        _unpause();
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @dev بررسی امکان استفاده از توکن در DEX
     * @param token آدرس توکن
     * @return true اگر قابل استفاده باشد
     */
    function isTokenUsable(address token) external view returns (bool) {
        if (!isTokenRegistered[token]) return false;
        if (listInfo[token].isBlacklisted) return false;
        
        TokenStatus status = tokenInfo[token].status;
        return status == TokenStatus.APPROVED;
    }
    
    /**
     * @dev دریافت لیست توکن‌های تایید شده
     * @param offset شروع از
     * @param limit حداکثر تعداد
     * @return لیست آدرس توکن‌ها
     */
    function getApprovedTokens(
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory) {
        require(offset < totalTokens, "Offset out of bounds");
        
        uint256 end = offset.add(limit);
        if (end > totalTokens) {
            end = totalTokens;
        }
        
        uint256 count = 0;
        // شمارش توکن‌های تایید شده
        for (uint256 i = offset; i < end; i++) {
            if (tokenInfo[allTokens[i]].status == TokenStatus.APPROVED) {
                count++;
            }
        }
        
        address[] memory approved = new address[](count);
        uint256 index = 0;
        
        for (uint256 i = offset; i < end; i++) {
            if (tokenInfo[allTokens[i]].status == TokenStatus.APPROVED) {
                approved[index] = allTokens[i];
                index++;
            }
        }
        
        return approved;
    }
    
    /**
     * @dev دریافت توکن‌های یک tier
     * @param tier سطح مورد نظر
     * @return لیست آدرس توکن‌ها
     */
    function getTokensByTier(TokenTier tier) external view returns (address[] memory) {
        uint256 count = 0;
        
        // شمارش
        for (uint256 i = 0; i < totalTokens; i++) {
            if (tokenInfo[allTokens[i]].tier == tier && 
                tokenInfo[allTokens[i]].status == TokenStatus.APPROVED) {
                count++;
            }
        }
        
        address[] memory tierTokens = new address[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < totalTokens; i++) {
            if (tokenInfo[allTokens[i]].tier == tier && 
                tokenInfo[allTokens[i]].status == TokenStatus.APPROVED) {
                tierTokens[index] = allTokens[i];
                index++;
            }
        }
        
        return tierTokens;
    }
    
    /**
     * @dev دریافت آمار کلی
     * @return آمار کامل registry
     */
    function getRegistryStats() external view returns (
        uint256 totalTokens_,
        uint256 approvedTokens,
        uint256 pendingTokens,
        uint256 blacklistedTokens,
        uint256 totalFeeCollected
    ) {
        totalTokens_ = totalTokens;
        
        for (uint256 i = 0; i < totalTokens; i++) {
            TokenStatus status = tokenInfo[allTokens[i]].status;
            if (status == TokenStatus.APPROVED) approvedTokens++;
            else if (status == TokenStatus.PENDING) pendingTokens++;
            
            if (listInfo[allTokens[i]].isBlacklisted) blacklistedTokens++;
        }
        
        totalFeeCollected = address(this).balance;
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    /**
     * @dev دریافت metadata توکن از کانترکت
     * @param token آدرس توکن
     * @return نام، نماد، اعشار، و کل عرضه
     */
    function _getTokenMetadata(address token) 
        internal 
        view 
        returns (string memory, string memory, uint8, uint256) 
    {
        try IERC20Metadata(token).name() returns (string memory name) {
            try IERC20Metadata(token).symbol() returns (string memory symbol) {
                try IERC20Metadata(token).decimals() returns (uint8 decimals) {
                    try IERC20(token).totalSupply() returns (uint256 totalSupply) {
                        return (name, symbol, decimals, totalSupply);
                    } catch {
                        return (name, symbol, decimals, 0);
                    }
                } catch {
                    return (name, symbol, 18, 0);
                }
            } catch {
                return (name, "UNKNOWN", 18, 0);
            }
        } catch {
            return ("UNKNOWN", "UNKNOWN", 18, 0);
        }
    }
    
    /**
     * @dev محاسبه ضریب tier
     * @param tier سطح توکن
     * @return ضریب
     */
    function _getTierMultiplier(TokenTier tier) internal pure returns (uint256) {
        if (tier == TokenTier.UNVERIFIED) return Constants.FEE_BASE; // 1x
        if (tier == TokenTier.VERIFIED) return Constants.FEE_BASE.mul(2); // 2x
        if (tier == TokenTier.PREMIUM) return Constants.FEE_BASE.mul(5); // 5x
        if (tier == TokenTier.BLUE_CHIP) return Constants.FEE_BASE.mul(10); // 10x
        if (tier == TokenTier.GOVERNANCE) return Constants.FEE_BASE.mul(20); // 20x
        return Constants.FEE_BASE;
    }
    
    /**
     * @dev محاسبه حد آستانه نقدینگی
     * @param tier سطح توکن
     * @return حد آستانه
     */
    function _calculateLiquidityThreshold(TokenTier tier) internal pure returns (uint256) {
        if (tier == TokenTier.UNVERIFIED) return 1000 * Constants.DECIMAL_BASE;
        if (tier == TokenTier.VERIFIED) return 5000 * Constants.DECIMAL_BASE;
        if (tier == TokenTier.PREMIUM) return 25000 * Constants.DECIMAL_BASE;
        if (tier == TokenTier.BLUE_CHIP) return 100000 * Constants.DECIMAL_BASE;
        if (tier == TokenTier.GOVERNANCE) return 500000 * Constants.DECIMAL_BASE;
        return 1000 * Constants.DECIMAL_BASE;
    }
    
    /**
     * @dev به‌روزرسانی volumes دوره‌ای
     * @param token آدرس توکن
     * @param volume حجم جدید
     */
    function _updatePeriodVolumes(address token, uint256 volume) internal {
        TokenStats storage stats = tokenStats[token];
        uint256 currentTime = block.timestamp;
        
        // Volume روزانه (reset هر 24 ساعت)
        if (currentTime > stats.lastUpdated + 1 days) {
            stats.dailyVolume = volume;
        } else {
            stats.dailyVolume = stats.dailyVolume.add(volume);
        }
        
        // Volume هفتگی (reset هر 7 روز)
        if (currentTime > stats.lastUpdated + 7 days) {
            stats.weeklyVolume = volume;
        } else {
            stats.weeklyVolume = stats.weeklyVolume.add(volume);
        }
        
        // Volume ماهانه (reset هر 30 روز)
        if (currentTime > stats.lastUpdated + 30 days) {
            stats.monthlyVolume = volume;
        } else {
            stats.monthlyVolume = stats.monthlyVolume.add(volume);
        }
    }
    
    /**
     * @dev تنظیم metadata keys معتبر
     */
    function _setupValidMetadataKeys() internal {
        validMetadataKeys["description"] = true;
        validMetadataKeys["website"] = true;
        validMetadataKeys["telegram"] = true;
        validMetadataKeys["twitter"] = true;
        validMetadataKeys["discord"] = true;
        validMetadataKeys["github"] = true;
        validMetadataKeys["whitepaper"] = true;
        validMetadataKeys["audit"] = true;
        validMetadataKeys["coingecko"] = true;
        validMetadataKeys["coinmarketcap"] = true;
    }
    
    // ==================== RECEIVE FUNCTION ====================
    
    /**
     * @dev دریافت ETH برای listing fees
     */
    receive() external payable {
        // ETH دریافتی برای listing fees
    }
} 