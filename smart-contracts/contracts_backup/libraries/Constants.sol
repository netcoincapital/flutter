// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Constants
 * @dev تمام ثابت‌های سیستم LAXCE DEX
 * @notice این کتابخانه تمام مقادیر ثابت مورد نیاز سیستم را تعریف می‌کند
 */
library Constants {
    
    // ==================== GENERAL CONSTANTS ====================
    
    /// @dev نسخه پروتکل
    string internal constant PROTOCOL_VERSION = "1.0.0";
    
    /// @dev نام پروتکل
    string internal constant PROTOCOL_NAME = "LAXCE DEX";
    
    /// @dev نماد اصلی
    string internal constant NATIVE_SYMBOL = "LAXCE";
    
    /// @dev آدرس zero
    address internal constant ZERO_ADDRESS = address(0);
    
    /// @dev حداکثر مقدار uint256
    uint256 internal constant MAX_UINT256 = type(uint256).max;
    
    /// @dev حداکثر مقدار uint128
    uint128 internal constant MAX_UINT128 = type(uint128).max;
    
    /// @dev پایه decimal برای محاسبات
    uint256 internal constant DECIMAL_BASE = 1e18;
    
    // ==================== POOL & AMM CONSTANTS ====================
    
    /// @dev حداقل نقدینگی برای pool جدید
    uint256 internal constant MINIMUM_LIQUIDITY = 1000;
    
    /// @dev حداکثر تعداد pools
    uint256 internal constant MAX_POOLS = 10000;
    
    /// @dev حداقل مقدار token برای swap
    uint256 internal constant MIN_SWAP_AMOUNT = 1000;
    
    /// @dev حداکثر مقدار token برای swap (در یک تراکنش)
    uint256 internal constant MAX_SWAP_AMOUNT = 1000000 * DECIMAL_BASE;
    
    /// @dev فاکتور K برای AMM (x * y = k)
    uint256 internal constant K_FACTOR = 1e12;
    
    // ==================== FEE CONSTANTS ====================
    
    /// @dev کارمزد پیش‌فرض برای swap (0.3%)
    uint256 internal constant DEFAULT_SWAP_FEE = 3000; // 3000 = 0.3% در واحد 10000
    
    /// @dev کارمزد پیش‌فرض برای withdraw (0.1%)
    uint256 internal constant DEFAULT_WITHDRAW_FEE = 1000; // 1000 = 0.1%
    
    /// @dev کارمزد لیست کردن توکن (0.01 ETH)
    uint256 internal constant TOKEN_LISTING_FEE = 0.01 * DECIMAL_BASE;
    
    /// @dev حداکثر کارمزد مجاز (5%)
    uint256 internal constant MAX_FEE_RATE = 5000; // 5000 = 5%
    
    /// @dev حداقل کارمزد مجاز (0.01%)
    uint256 internal constant MIN_FEE_RATE = 10; // 10 = 0.01%
    
    /// @dev پایه محاسبه کارمزد
    uint256 internal constant FEE_BASE = 10000; // 100% = 10000
    
    /// @dev سهم پروتکل از کارمزد (20%)
    uint256 internal constant PROTOCOL_FEE_SHARE = 2000; // 2000 = 20%
    
    /// @dev سهم LP ها از کارمزد (80%)
    uint256 internal constant LP_FEE_SHARE = 8000; // 8000 = 80%
    
    // ==================== CONCENTRATED LIQUIDITY CONSTANTS ====================
    
    /// @dev حداقل فاصله tick
    int24 internal constant MIN_TICK_SPACING = 1;
    
    /// @dev حداکثر فاصله tick
    int24 internal constant MAX_TICK_SPACING = 16384;
    
    /// @dev حداقل tick
    int24 internal constant MIN_TICK = -887272;
    
    /// @dev حداکثر tick
    int24 internal constant MAX_TICK = 887272;
    
    /// @dev پایه محاسبه price ratio
    uint256 internal constant PRICE_RATIO_BASE = 1001; // 1.0001
    
    /// @dev ضریب Q64.96 برای محاسبات دقیق
    uint256 internal constant Q96 = 0x1000000000000000000000000;
    
    /// @dev ضریب Q128
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;
    
    // ==================== GOVERNANCE CONSTANTS ====================
    
    /// @dev حداقل زمان voting (3 روز)
    uint256 internal constant MIN_VOTING_PERIOD = 3 days;
    
    /// @dev حداکثر زمان voting (30 روز)
    uint256 internal constant MAX_VOTING_PERIOD = 30 days;
    
    /// @dev حداقل زمان timelock (1 روز)
    uint256 internal constant MIN_TIMELOCK_DELAY = 1 days;
    
    /// @dev حداکثر زمان timelock (30 روز)
    uint256 internal constant MAX_TIMELOCK_DELAY = 30 days;
    
    /// @dev حداقل quorum برای voting (5%)
    uint256 internal constant MIN_QUORUM = 500; // 5%
    
    /// @dev حداکثر quorum برای voting (20%)
    uint256 internal constant MAX_QUORUM = 2000; // 20%
    
    /// @dev حداقل threshold برای proposal (1%)
    uint256 internal constant MIN_PROPOSAL_THRESHOLD = 100; // 1%
    
    // ==================== SECURITY CONSTANTS ====================
    
    /// @dev حداکثر slippage مجاز (10%)
    uint256 internal constant MAX_SLIPPAGE = 1000; // 10%
    
    /// @dev حداقل slippage (0.1%)
    uint256 internal constant MIN_SLIPPAGE = 10; // 0.1%
    
    /// @dev حداکثر price impact مجاز (20%)
    uint256 internal constant MAX_PRICE_IMPACT = 2000; // 20%
    
    /// @dev زمان cooldown برای withdraw (1 ساعت)
    uint256 internal constant WITHDRAW_COOLDOWN = 1 hours;
    
    /// @dev حداکثر تعداد transactions در هر block
    uint256 internal constant MAX_TXS_PER_BLOCK = 100;
    
    /// @dev حداکثر gas limit برای transaction
    uint256 internal constant MAX_GAS_LIMIT = 15000000;
    
    // ==================== ORACLE CONSTANTS ====================
    
    /// @dev حداقل تعداد observations برای TWAP
    uint256 internal constant MIN_OBSERVATIONS = 2;
    
    /// @dev حداکثر تعداد observations برای TWAP
    uint256 internal constant MAX_OBSERVATIONS = 65535;
    
    /// @dev پیش‌فرض cardinality برای Oracle
    uint256 internal constant DEFAULT_CARDINALITY = 100;
    
    /// @dev حداقل فاصله زمانی بین updates (1 ثانیه)
    uint256 internal constant MIN_UPDATE_INTERVAL = 1;
    
    /// @dev حداکثر فاصله زمانی بین updates (1 ساعت)
    uint256 internal constant MAX_UPDATE_INTERVAL = 3600;
    
    /// @dev حداکثر price deviation مجاز (5%)
    uint256 internal constant MAX_PRICE_DEVIATION = 500; // 5%
    
    // ==================== TOKEN CONSTANTS ====================
    
    /// @dev حداقل supply برای token
    uint256 internal constant MIN_TOKEN_SUPPLY = 1000000 * DECIMAL_BASE;
    
    /// @dev حداکثر supply برای token
    uint256 internal constant MAX_TOKEN_SUPPLY = 1000000000 * DECIMAL_BASE;
    
    /// @dev حداکثر تعداد decimals
    uint8 internal constant MAX_DECIMALS = 18;
    
    /// @dev حداقل تعداد decimals
    uint8 internal constant MIN_DECIMALS = 6;
    
    /// @dev حداکثر طول نام token
    uint256 internal constant MAX_TOKEN_NAME_LENGTH = 50;
    
    /// @dev حداکثر طول symbol token
    uint256 internal constant MAX_TOKEN_SYMBOL_LENGTH = 10;
    
    // ==================== REWARD CONSTANTS ====================
    
    /// @dev مدت زمان lock برای rewards (30 روز)
    uint256 internal constant REWARD_LOCK_PERIOD = 30 days;
    
    /// @dev حداکثر APR برای rewards (1000%)
    uint256 internal constant MAX_REWARD_APR = 100000; // 1000%
    
    /// @dev حداقل APR برای rewards (1%)
    uint256 internal constant MIN_REWARD_APR = 100; // 1%
    
    /// @dev مدت زمان vesting برای team rewards (1 سال)
    uint256 internal constant TEAM_VESTING_PERIOD = 365 days;
    
    // ==================== CIRCUIT BREAKER CONSTANTS ====================
    
    /// @dev threshold برای فعال‌سازی circuit breaker (50% drop در 1 hour)
    uint256 internal constant CIRCUIT_BREAKER_THRESHOLD = 5000; // 50%
    
    /// @dev مدت زمان pause بعد از فعال‌سازی circuit breaker
    uint256 internal constant CIRCUIT_BREAKER_COOLDOWN = 2 hours;
    
    /// @dev حداکثر تعداد فعال‌سازی circuit breaker در روز
    uint256 internal constant MAX_CIRCUIT_BREAKER_TRIGGERS = 3;
    
    // ==================== UTILITY FUNCTIONS ====================
    
    /**
     * @dev تبدیل درصد به مقدار basis points
     * @param percentage درصد (مثلاً 5 برای 5%)
     * @return مقدار basis points (مثلاً 500 برای 5%)
     */
    function percentToBasisPoints(uint256 percentage) internal pure returns (uint256) {
        return percentage * 100;
    }
    
    /**
     * @dev تبدیل basis points به درصد
     * @param basisPoints مقدار basis points
     * @return درصد
     */
    function basisPointsToPercent(uint256 basisPoints) internal pure returns (uint256) {
        return basisPoints / 100;
    }
    
    /**
     * @dev محاسبه کارمزد بر اساس مقدار
     * @param amount مقدار اصلی
     * @param feeRate نرخ کارمزد (در basis points)
     * @return مقدار کارمزد
     */
    function calculateFee(uint256 amount, uint256 feeRate) internal pure returns (uint256) {
        return (amount * feeRate) / FEE_BASE;
    }
    
    /**
     * @dev بررسی valid بودن fee rate
     * @param feeRate نرخ کارمزد
     * @return true اگر valid باشد
     */
    function isValidFeeRate(uint256 feeRate) internal pure returns (bool) {
        return feeRate >= MIN_FEE_RATE && feeRate <= MAX_FEE_RATE;
    }
    
    /**
     * @dev بررسی valid بودن tick
     * @param tick مقدار tick
     * @return true اگر valid باشد
     */
    function isValidTick(int24 tick) internal pure returns (bool) {
        return tick >= MIN_TICK && tick <= MAX_TICK;
    }
    
    /**
     * @dev بررسی valid بودن tick spacing
     * @param tickSpacing فاصله tick
     * @return true اگر valid باشد
     */
    function isValidTickSpacing(int24 tickSpacing) internal pure returns (bool) {
        return tickSpacing >= MIN_TICK_SPACING && tickSpacing <= MAX_TICK_SPACING;
    }
} 