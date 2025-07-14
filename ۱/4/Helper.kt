package com.laxce.adl.viewmodel

import android.content.Context
import com.laxce.adl.api.ApiCurrency
import com.laxce.adl.classes.CryptoToken

class TokenPreferences(context: Context, private val userId: String) {
    private val PREFS_NAME = "token_prefs_$userId"
    private val sharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // کش داخلی برای کاهش فراخوانی‌های SharedPreferences
    private var enabledTokensCache: MutableMap<String, Boolean>? = null
    private var lastCacheTime: Long = 0
    private val CACHE_VALIDITY_PERIOD = 5 * 60 * 1000 // 5 دقیقه

    init {
        val defaultTokens = listOf("Bitcoin", "Ethereum", "Netcoincapital")
        val editor = sharedPreferences.edit()
        var needsCommit = false

        defaultTokens.forEach { token ->
            if (!sharedPreferences.contains(token)) {
                editor.putBoolean(token, true)
                needsCommit = true
            }
        }

        if (needsCommit) {
            editor.apply()
        }
        
        // بارگذاری کش داخلی در زمان ایجاد کلاس
        loadEnabledTokensCache()
    }

    // بارگذاری کش داخلی از SharedPreferences
    private fun loadEnabledTokensCache() {
        val tokenNames = sharedPreferences.all.keys
        enabledTokensCache = mutableMapOf()
        
        tokenNames.forEach { tokenName: String ->
            enabledTokensCache!![tokenName] = sharedPreferences.getBoolean(tokenName, false)
        }
        
        lastCacheTime = System.currentTimeMillis()
    }
    
    // بررسی اعتبار کش داخلی
    private fun isCacheValid(): Boolean {
        return enabledTokensCache != null && 
               (System.currentTimeMillis() - lastCacheTime) < CACHE_VALIDITY_PERIOD
    }

    fun saveTokenState(token: CryptoToken, isEnabled: Boolean) {
        saveTokenState(token.symbol, token.BlockchainName, token.SmartContractAddress, isEnabled)
    }

    fun getTokenState(token: CryptoToken): Boolean {
        return getTokenState(token.symbol, token.BlockchainName, token.SmartContractAddress)
    }

    fun getTokenState(symbol: String, blockchainName: String, contract: String?): Boolean {
        val key = "${symbol}_${blockchainName}_${contract ?: ""}"
        // استفاده از کش داخلی اگر معتبر است
        if (isCacheValid() && enabledTokensCache?.containsKey(key) == true) {
            return enabledTokensCache!![key] ?: false
        }
        val isEnabled = sharedPreferences.getBoolean(key, false)
        if (enabledTokensCache == null) {
            loadEnabledTokensCache()
        } else {
            enabledTokensCache!![key] = isEnabled
        }
        return isEnabled
    }

    fun saveTokenState(symbol: String, blockchainName: String, contract: String?, isEnabled: Boolean) {
        val key = "${symbol}_${blockchainName}_${contract ?: ""}"
        sharedPreferences.edit().putBoolean(key, isEnabled).apply()
        enabledTokensCache?.put(key, isEnabled)
    }

    fun getAllEnabledTokenNames(): List<String> {
        // اگر کش معتبر نیست، آن را بارگذاری کنیم
        if (!isCacheValid()) {
            loadEnabledTokensCache()
        }
        
        // استفاده از کش داخلی برای بهینه‌سازی
        return enabledTokensCache?.filter { it.value }?.keys?.toList() ?: listOf()
    }

    fun getAllEnabledTokens(availableTokens: List<CryptoToken>): List<CryptoToken> {
        // ابتدا لیست کلیدهای توکن‌های فعال را بگیریم
        val enabledKeys = getAllEnabledTokenNames()
        // فیلتر کردن توکن‌ها بر اساس فعال بودن با کلید ترکیبی
        return availableTokens.map { token ->
            val key = "${token.symbol}_${token.BlockchainName}_${token.SmartContractAddress ?: ""}"
            token.copy(isEnabled = enabledKeys.contains(key))
        }.filter { it.isEnabled }
    }

    // کد تبدیل ApiCurrency به CryptoToken
    fun toCryptoToken(api: ApiCurrency): CryptoToken {
        val isEnabled = getTokenState(api.Symbol, api.BlockchainName, api.SmartContractAddress)
        return CryptoToken(
            name = api.CurrencyName,
            symbol = api.Symbol,
            BlockchainName = api.BlockchainName,
            iconUrl = api.Icon ?: "",
            isEnabled = isEnabled,
            isToken = true,
            SmartContractAddress = api.SmartContractAddress
        )
    }


}

fun ApiCurrency.toCryptoToken(): CryptoToken {
    return CryptoToken(
        name = this.CurrencyName,
        symbol = this.Symbol,
        BlockchainName = this.BlockchainName,
        iconUrl = this.Icon ?: "https://coinceeper.com/defualtIcons/coin.png",
        isEnabled = false,
        amount = 0.0,
        isToken = this.IsToken,
        SmartContractAddress = this.SmartContractAddress
    )
}
