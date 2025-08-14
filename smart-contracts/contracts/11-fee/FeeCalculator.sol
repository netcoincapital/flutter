// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/Constants.sol";
import "../libraries/FullMath.sol";

/**
 * @title FeeCalculator
 * @dev محاسبه کارمزدهای مختلف DEX
 */
contract FeeCalculator is Ownable {
    using FullMath for uint256;

    struct FeeTier {
        uint256 minVolume;      // حداقل volume برای این tier
        uint256 swapFee;        // کارمزد swap (basis points)
        uint256 lpFee;          // کارمزد LP (basis points)
        uint256 protocolFee;    // کارمزد protocol (basis points)
        bool active;            // فعال/غیرفعال
    }

    struct UserFeeInfo {
        uint256 tier;           // tier فعلی کاربر
        uint256 totalVolume;    // کل volume کاربر
        uint256 lastUpdate;     // آخرین به‌روزرسانی
        uint256 discount;       // تخفیف اضافی (basis points)
        bool isVIP;            // کاربر VIP
    }

    struct PoolFeeConfig {
        uint256 baseFee;        // کارمزد پایه
        uint256 dynamicFee;     // کارمزد پویا
        uint256 maxFee;         // حداکثر کارمزد
        uint256 minFee;         // حداقل کارمزد
        bool isDynamic;         // آیا dynamic fee فعال است
    }

    // Events
    event FeeCalculated(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 totalFee,
        uint256 lpFee,
        uint256 protocolFee
    );

    event FeeTierUpdated(uint256 indexed tier, uint256 minVolume, uint256 swapFee);
    event UserTierChanged(address indexed user, uint256 oldTier, uint256 newTier);
    event PoolFeeConfigUpdated(address indexed pool, uint256 baseFee, bool isDynamic);

    // State variables
    mapping(uint256 => FeeTier) public feeTiers;
    mapping(address => UserFeeInfo) public userFeeInfo;
    mapping(address => PoolFeeConfig) public poolFeeConfig;
    mapping(address => mapping(address => uint256)) public pairCustomFee; // tokenA => tokenB => fee
    
    uint256 public totalTiers = 5;
    uint256 public constant MAX_FEE = 1000; // 10% maximum
    uint256 public constant DEFAULT_SWAP_FEE = 30; // 0.3%
    uint256 public constant DEFAULT_LP_SHARE = 8000; // 80% to LPs
    uint256 public constant DEFAULT_PROTOCOL_SHARE = 2000; // 20% to protocol
    
    // VIP benefits
    uint256 public constant VIP_DISCOUNT = 50; // 0.5% additional discount
    uint256 public vipMinVolume = 1000000 * 10**18; // 1M volume for VIP
    
    // Dynamic fee parameters
    uint256 public constant VOLATILITY_MULTIPLIER = 2;
    uint256 public constant LIQUIDITY_MULTIPLIER = 1;

    error InvalidTier();
    error InvalidFee();
    error InvalidVolume();
    error InvalidPool();

    constructor() Ownable(msg.sender) {
        _initializeFeeTiers();
    }

    /**
     * @dev محاسبه کارمزد کامل برای swap
     * @param user آدرس کاربر
     * @param tokenIn توکن ورودی
     * @param tokenOut توکن خروجی
     * @param amountIn مقدار ورودی
     * @param poolAddress آدرس pool
     * @return totalFee کل کارمزد
     * @return lpFee کارمزد LP
     * @return protocolFee کارمزد protocol
     */
    function calculateSwapFee(
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address poolAddress
    ) external view returns (
        uint256 totalFee,
        uint256 lpFee,
        uint256 protocolFee
    ) {
        // دریافت base fee
        uint256 baseFee = _getBaseFee(user, tokenIn, tokenOut, poolAddress);
        
        // اعمال dynamic fee اگر فعال باشد
        if (poolFeeConfig[poolAddress].isDynamic) {
            baseFee = _applyDynamicFee(baseFee, poolAddress, amountIn);
        }
        
        // اعمال تخفیفات کاربر
        baseFee = _applyUserDiscount(user, baseFee);
        
        totalFee = baseFee;
        
        // تقسیم fee بین LP و protocol
        lpFee = (totalFee * DEFAULT_LP_SHARE) / Constants.BASIS_POINTS;
        protocolFee = totalFee - lpFee;
    }

    /**
     * @dev محاسبه کارمزد افزودن نقدینگی
     * @param user آدرس کاربر
     * @param poolAddress آدرس pool
     * @param amountA مقدار توکن A
     * @param amountB مقدار توکن B
     * @return fee کارمزد محاسبه شده
     */
    function calculateLiquidityFee(
        address user,
        address poolAddress,
        uint256 amountA,
        uint256 amountB
    ) external view returns (uint256 fee) {
        UserFeeInfo storage userInfo = userFeeInfo[user];
        FeeTier storage tier = feeTiers[userInfo.tier];
        
        // کارمزد پایه 0.1% برای افزودن نقدینگی
        uint256 baseFee = 10; // 0.1%
        
        // اعمال تخفیف tier
        fee = baseFee - (baseFee * tier.swapFee) / (DEFAULT_SWAP_FEE * 10);
        
        // اعمال تخفیف VIP
        if (userInfo.isVIP) {
            fee = fee > VIP_DISCOUNT ? fee - VIP_DISCOUNT : 0;
        }
        
        // محاسبه بر اساس کل value
        uint256 totalValue = amountA + amountB; // ساده‌سازی
        fee = (totalValue * fee) / Constants.BASIS_POINTS;
    }

    /**
     * @dev محاسبه کارمزد withdrawal نقدینگی
     * @param user آدرس کاربر
     * @param poolAddress آدرس pool
     * @param lpTokenAmount مقدار LP token
     * @param holdingPeriod مدت نگهداری (ثانیه)
     * @return fee کارمزد محاسبه شده
     */
    function calculateWithdrawalFee(
        address user,
        address poolAddress,
        uint256 lpTokenAmount,
        uint256 holdingPeriod
    ) external view returns (uint256 fee) {
        // کارمزد پایه 0.5%
        uint256 baseFee = 50; // 0.5%
        
        // کاهش کارمزد بر اساس مدت نگهداری
        if (holdingPeriod >= 30 days) {
            baseFee = 0; // بدون کارمزد بعد از 30 روز
        } else if (holdingPeriod >= 7 days) {
            baseFee = 10; // 0.1% بعد از 7 روز
        } else if (holdingPeriod >= 1 days) {
            baseFee = 25; // 0.25% بعد از 1 روز
        }
        
        // اعمال تخفیف کاربر
        baseFee = _applyUserDiscount(user, baseFee);
        
        fee = (lpTokenAmount * baseFee) / Constants.BASIS_POINTS;
    }

    /**
     * @dev به‌روزرسانی volume کاربر و tier
     * @param user آدرس کاربر
     * @param volume مقدار volume جدید
     */
    function updateUserVolume(address user, uint256 volume) external {
        // فقط contracts مجاز می‌توانند volume را به‌روزرسانی کنند
        // TODO: اضافه کردن access control
        
        UserFeeInfo storage userInfo = userFeeInfo[user];
        userInfo.totalVolume += volume;
        userInfo.lastUpdate = block.timestamp;
        
        // بررسی تغییر tier
        uint256 newTier = _calculateUserTier(userInfo.totalVolume);
        if (newTier != userInfo.tier) {
            uint256 oldTier = userInfo.tier;
            userInfo.tier = newTier;
            emit UserTierChanged(user, oldTier, newTier);
        }
        
        // بررسی VIP status
        if (userInfo.totalVolume >= vipMinVolume && !userInfo.isVIP) {
            userInfo.isVIP = true;
        }
    }

    /**
     * @dev تنظیم fee tier
     * @param tier شماره tier
     * @param minVolume حداقل volume
     * @param swapFee کارمزد swap
     * @param lpFee کارمزد LP
     * @param protocolFee کارمزد protocol
     */
    function setFeeTier(
        uint256 tier,
        uint256 minVolume,
        uint256 swapFee,
        uint256 lpFee,
        uint256 protocolFee
    ) external onlyOwner {
        if (tier >= totalTiers) revert InvalidTier();
        if (swapFee > MAX_FEE || lpFee > MAX_FEE || protocolFee > MAX_FEE) revert InvalidFee();
        
        feeTiers[tier] = FeeTier({
            minVolume: minVolume,
            swapFee: swapFee,
            lpFee: lpFee,
            protocolFee: protocolFee,
            active: true
        });
        
        emit FeeTierUpdated(tier, minVolume, swapFee);
    }

    /**
     * @dev تنظیم pool fee config
     * @param poolAddress آدرس pool
     * @param baseFee کارمزد پایه
     * @param maxFee حداکثر کارمزد
     * @param minFee حداقل کارمزد
     * @param isDynamic آیا dynamic fee فعال است
     */
    function setPoolFeeConfig(
        address poolAddress,
        uint256 baseFee,
        uint256 maxFee,
        uint256 minFee,
        bool isDynamic
    ) external onlyOwner {
        if (poolAddress == address(0)) revert InvalidPool();
        if (baseFee > MAX_FEE || maxFee > MAX_FEE) revert InvalidFee();
        if (minFee > maxFee) revert InvalidFee();
        
        poolFeeConfig[poolAddress] = PoolFeeConfig({
            baseFee: baseFee,
            dynamicFee: baseFee,
            maxFee: maxFee,
            minFee: minFee,
            isDynamic: isDynamic
        });
        
        emit PoolFeeConfigUpdated(poolAddress, baseFee, isDynamic);
    }

    /**
     * @dev تنظیم custom fee برای pair خاص
     * @param tokenA توکن A
     * @param tokenB توکن B
     * @param fee کارمزد سفارشی
     */
    function setCustomPairFee(
        address tokenA,
        address tokenB,
        uint256 fee
    ) external onlyOwner {
        if (fee > MAX_FEE) revert InvalidFee();
        pairCustomFee[tokenA][tokenB] = fee;
        pairCustomFee[tokenB][tokenA] = fee; // symmetric
    }

    /**
     * @dev تنظیم تخفیف کاربر
     * @param user آدرس کاربر
     * @param discount مقدار تخفیف (basis points)
     */
    function setUserDiscount(address user, uint256 discount) external onlyOwner {
        if (discount > 500) revert InvalidFee(); // حداکثر 5% تخفیف
        userFeeInfo[user].discount = discount;
    }

    /**
     * @dev تنظیم VIP minimum volume
     * @param minVolume حداقل volume برای VIP
     */
    function setVIPMinVolume(uint256 minVolume) external onlyOwner {
        vipMinVolume = minVolume;
    }

    /**
     * @dev دریافت اطلاعات کاربر
     * @param user آدرس کاربر
     */
    function getUserInfo(address user) external view returns (
        uint256 tier,
        uint256 totalVolume,
        uint256 lastUpdate,
        uint256 discount,
        bool isVIP
    ) {
        UserFeeInfo storage info = userFeeInfo[user];
        return (info.tier, info.totalVolume, info.lastUpdate, info.discount, info.isVIP);
    }

    /**
     * @dev دریافت base fee
     */
    function _getBaseFee(
        address user,
        address tokenIn,
        address tokenOut,
        address poolAddress
    ) internal view returns (uint256) {
        // بررسی custom pair fee
        uint256 customFee = pairCustomFee[tokenIn][tokenOut];
        if (customFee > 0) {
            return customFee;
        }
        
        // بررسی pool config
        PoolFeeConfig storage poolConfig = poolFeeConfig[poolAddress];
        if (poolConfig.baseFee > 0) {
            return poolConfig.baseFee;
        }
        
        // استفاده از tier fee
        UserFeeInfo storage userInfo = userFeeInfo[user];
        FeeTier storage tier = feeTiers[userInfo.tier];
        
        return tier.active ? tier.swapFee : DEFAULT_SWAP_FEE;
    }

    /**
     * @dev اعمال dynamic fee
     */
    function _applyDynamicFee(
        uint256 baseFee,
        address poolAddress,
        uint256 amountIn
    ) internal view returns (uint256) {
        PoolFeeConfig storage config = poolFeeConfig[poolAddress];
        
        // ساده‌سازی: اگر معامله بزرگ باشد، fee بیشتر
        uint256 adjustedFee = baseFee;
        
        // TODO: پیاده‌سازی الگوریتم پیچیده‌تر بر اساس volatility و liquidity
        
        // اعمال محدودیت‌ها
        if (adjustedFee > config.maxFee) {
            adjustedFee = config.maxFee;
        } else if (adjustedFee < config.minFee) {
            adjustedFee = config.minFee;
        }
        
        return adjustedFee;
    }

    /**
     * @dev اعمال تخفیف کاربر
     */
    function _applyUserDiscount(address user, uint256 baseFee) internal view returns (uint256) {
        UserFeeInfo storage userInfo = userFeeInfo[user];
        
        uint256 totalDiscount = userInfo.discount;
        
        // تخفیف VIP
        if (userInfo.isVIP) {
            totalDiscount += VIP_DISCOUNT;
        }
        
        // اعمال تخفیف
        if (totalDiscount >= baseFee) {
            return 1; // حداقل 1 basis point
        }
        
        return baseFee - totalDiscount;
    }

    /**
     * @dev محاسبه tier کاربر بر اساس volume
     */
    function _calculateUserTier(uint256 totalVolume) internal view returns (uint256) {
        for (uint256 i = totalTiers - 1; i > 0; i--) {
            if (totalVolume >= feeTiers[i].minVolume && feeTiers[i].active) {
                return i;
            }
        }
        return 0; // tier پایه
    }

    /**
     * @dev مقداردهی اولیه fee tiers
     */
    function _initializeFeeTiers() internal {
        // Tier 0: کاربران جدید
        feeTiers[0] = FeeTier({
            minVolume: 0,
            swapFee: 30,     // 0.3%
            lpFee: 24,       // 0.24%
            protocolFee: 6,  // 0.06%
            active: true
        });
        
        // Tier 1: کاربران فعال
        feeTiers[1] = FeeTier({
            minVolume: 10000 * 10**18,
            swapFee: 25,     // 0.25%
            lpFee: 20,       // 0.20%
            protocolFee: 5,  // 0.05%
            active: true
        });
        
        // Tier 2: کاربران پرحجم
        feeTiers[2] = FeeTier({
            minVolume: 100000 * 10**18,
            swapFee: 20,     // 0.20%
            lpFee: 16,       // 0.16%
            protocolFee: 4,  // 0.04%
            active: true
        });
        
        // Tier 3: کاربران حرفه‌ای
        feeTiers[3] = FeeTier({
            minVolume: 500000 * 10**18,
            swapFee: 15,     // 0.15%
            lpFee: 12,       // 0.12%
            protocolFee: 3,  // 0.03%
            active: true
        });
        
        // Tier 4: کاربران VIP
        feeTiers[4] = FeeTier({
            minVolume: 1000000 * 10**18,
            swapFee: 10,     // 0.10%
            lpFee: 8,        // 0.08%
            protocolFee: 2,  // 0.02%
            active: true
        });
    }
}