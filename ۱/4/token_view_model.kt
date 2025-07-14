package com.laxce.adl.viewmodel

import android.content.Context
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.laxce.adl.api.Api
import com.laxce.adl.api.BalanceRequest
import com.laxce.adl.classes.CryptoToken
import com.google.gson.Gson
import kotlinx.coroutines.launch
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.laxce.adl.api.PriceData
import com.laxce.adl.api.PricesRequest
import com.laxce.adl.api.RetrofitClient
import com.laxce.adl.utility.TokenPreferences
import com.laxce.adl.utility.getSelectedCurrency
import kotlinx.coroutines.delay


class token_view_model(val context: Context?, private var userId: String) : ViewModel() {

    var currencies by mutableStateOf<List<CryptoToken>>(emptyList())
    var isLoading by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set
    private val _activeTokens = MutableStateFlow<List<CryptoToken>>(emptyList())
    val activeTokens = _activeTokens.asStateFlow()
    private var tokenPreferences = context?.let { TokenPreferences(it, userId) }
    private val _tokenStates = mutableStateMapOf<String, Boolean>()
    private var _walletName = mutableStateOf("")
    val walletName: String get() = _walletName.value
    val userTokensMap = mutableStateMapOf<String, List<CryptoToken>>()

    // قیمت‌های توکن‌ها
    private val _tokenPrices = MutableStateFlow<Map<String, Map<String, PriceData>>>(emptyMap())
    val tokenPrices: StateFlow<Map<String, Map<String, PriceData>>> = _tokenPrices.asStateFlow()

    // زمان انقضای کش (میلی‌ثانیه)
    private val CACHE_EXPIRY_TIME = 24 * 60 * 60 * 1000L // 24 ساعت
    private val PRICE_CACHE_EXPIRY_TIME = 5 * 60 * 1000L // 5 minutes in milliseconds

    // اضافه کردن StateFlow برای gas fees
    private val _gasFees = MutableStateFlow<Map<String, String>>(emptyMap())
    val gasFees: StateFlow<Map<String, String>> = _gasFees.asStateFlow()

    // اضافه کردن StateFlow برای نگهداری توکن‌های هر کاربر
    private val _userTokens = MutableStateFlow<Map<String, List<CryptoToken>>>(emptyMap())
    val userTokens: StateFlow<Map<String, List<CryptoToken>>> = _userTokens.asStateFlow()

    // اضافه کردن StateFlow برای نگهداری موجودی‌های هر کاربر
    private val _userBalances = MutableStateFlow<Map<String, Map<String, String>>>(emptyMap())
    val userBalances: StateFlow<Map<String, Map<String, String>>> = _userBalances.asStateFlow()

    private val api: Api = RetrofitClient.getInstance(context ?: throw IllegalStateException("Context is null")).create(Api::class.java)


    suspend fun fetchBalancesForActiveTokens(): Map<String, String> {
        Log.d("BalanceAPI", "🔄 === fetchBalancesForActiveTokens CALLED ===")
        Log.d("BalanceAPI", "🔄 UserId: '$userId'")
        
        if (context == null || userId.isEmpty()) {
            Log.e("BalanceAPI", "❌ Context is null or userId is empty - returning empty map")
            return emptyMap()
        }

        val activeSymbols = activeTokens.value.map { it.symbol }
        if (activeSymbols.isEmpty()) {
            Log.e("BalanceAPI", "❌ No active symbols - returning empty map")
            return emptyMap()
        }

        val request = BalanceRequest(
            userId = userId,
            currencyNames = emptyList(),
            blockchain = emptyMap()
        )

        return try {
            val response = api.getBalance(request)
            
            if (response.success && response.balances != null) {
                val balancesMap = response.balances.associate { it.symbol to it.balance }
                
                // ذخیره موجودی‌های کاربر در StateFlow مربوطه
                val currentBalances = _userBalances.value.toMutableMap()
                currentBalances[userId] = balancesMap
                _userBalances.value = currentBalances

                // به‌روزرسانی موجودی‌ها در لیست توکن‌های فعال
                val updatedTokens = _activeTokens.value.map { token ->
                    val balance = balancesMap[token.symbol] ?: "0.0"
                    val balanceDouble = balance.toDoubleOrNull() ?: 0.0
                    token.copy(amount = balanceDouble)
                }

                // به‌روزرسانی currencies
                currencies = currencies.map { token ->
                    if (token.isEnabled && balancesMap.containsKey(token.symbol)) {
                        val balance = balancesMap[token.symbol] ?: "0.0"
                        val balanceDouble = balance.toDoubleOrNull() ?: 0.0
                        token.copy(amount = balanceDouble)
                    } else if (token.isEnabled) {
                        token.copy(amount = 0.0)
                    } else {
                        token
                    }
                }

                // مرتب‌سازی توکن‌ها بر اساس ارزش
                val sortedTokens = sortTokensByDollarValue(updatedTokens)
                setActiveTokensForUser(sortedTokens)

                balancesMap
            } else {
                Log.e("BalanceAPI", "❌ Failed to fetch balances")
                emptyMap()
            }
        } catch (e: Exception) {
            Log.e("BalanceAPI", "❌ Error fetching balances: ${e.message}")
            emptyMap()
        }
    }

    fun fetchTokensWithBalance(forceRefresh: Boolean = false) {
        viewModelScope.launch {
            isLoading = true
            try {
                smartLoadTokens(forceRefresh) // حالا بسته به وضعیت کش بارگیری می‌کنه
                val balances = fetchBalancesForActiveTokens()

                val updated = _activeTokens.value.map { token ->
                    val newAmount = balances[token.symbol]?.toDoubleOrNull() ?: 0.0
                    token.copy(amount = newAmount)
                }

                // Sort tokens with positive balance by dollar value from highest to lowest
                val tokensWithBalance = updated.filter { it.amount!! > 0 }
                val sortedTokens = sortTokensByDollarValue(tokensWithBalance)
                setActiveTokensForUser(sortedTokens)

            } catch (e: Exception) {
                Log.e("SendScreen", "❌ Error loading tokens with balance: ${e.message}")
            } finally {
                isLoading = false
            }
        }
    }



    init {
        viewModelScope.launch {
            // اضافه کردن توکن‌های پیش‌فرض در اولین اجرا
            initializeDefaultTokens()
            fetchGasFees()
            smartLoadTokens(true)  // Force refresh on initial load
        }
    }

    private suspend fun initializeDefaultTokens() {
        val defaultTokens = mapOf(
            "Bitcoin" to true,
            "Ethereum" to true,
            "Netcoincapital" to true  // فقط یک نسخه با حروف صحیح
        )

        // بررسی اولین اجرا
        val sharedPreferences = context?.getSharedPreferences("token_prefs_$userId", Context.MODE_PRIVATE)
        val isFirstRun = sharedPreferences?.getBoolean("is_first_run", true) ?: true

        Log.d("TokenViewModel", "🔄 === Initialize Default Tokens ===")
        Log.d("TokenViewModel", "🔄 Is first run: $isFirstRun")
        Log.d("TokenViewModel", "🔄 User ID: $userId")

        if (isFirstRun) {
            Log.d("TokenViewModel", "🔄 Initializing default tokens for first run")
            sharedPreferences?.edit()?.apply {
                defaultTokens.forEach { (tokenName, defaultState) ->
                    // ذخیره با نام ساده برای سازگاری با کد قبلی
                    putBoolean(tokenName, defaultState)
                    Log.d("TokenViewModel", "✅ Saved simple key: $tokenName = $defaultState")
                    
                    // ذخیره با کلید ترکیبی جدید برای توکن‌های پیش‌فرض
                    when (tokenName) {
                        "Bitcoin" -> {
                            putBoolean("BTC_Bitcoin_", defaultState)
                            tokenPreferences?.saveTokenState("BTC", "Bitcoin", null, defaultState)
                            val compositeKey = "BTC_Bitcoin_"
                            Log.d("TokenViewModel", "✅ Bitcoin saved with key: $compositeKey = $defaultState")
                            Log.d("TokenViewModel", "✅ Bitcoin TokenPreferences key: BTC_Bitcoin_null")
                        }
                        "Ethereum" -> {
                            putBoolean("ETH_Ethereum_", defaultState)
                            tokenPreferences?.saveTokenState("ETH", "Ethereum", null, defaultState)
                            val compositeKey = "ETH_Ethereum_"
                            Log.d("TokenViewModel", "✅ Ethereum saved with key: $compositeKey = $defaultState")
                            Log.d("TokenViewModel", "✅ Ethereum TokenPreferences key: ETH_Ethereum_null")
                        }
                        "Netcoincapital" -> {
                            putBoolean("NCC_Netcoincapital_", defaultState)
                            tokenPreferences?.saveTokenState("NCC", "Netcoincapital", null, defaultState)
                            val compositeKey = "NCC_Netcoincapital_"
                            Log.d("TokenViewModel", "✅ Netcoincapital saved with key: $compositeKey = $defaultState")
                            Log.d("TokenViewModel", "✅ Netcoincapital TokenPreferences key: NCC_Netcoincapital_null")
                        }
                    }
                }
                putBoolean("is_first_run", false)
                apply()
            }
            Log.d("TokenViewModel", "✅ Default tokens initialized with composite keys")
        } else {
            Log.d("TokenViewModel", "ℹ️ Not first run, checking existing token states...")
            
            // بررسی وضعیت موجود توکن‌های پیش‌فرض
            defaultTokens.forEach { (tokenName, _) ->
                when (tokenName) {
                    "Bitcoin" -> {
                        val simpleState = sharedPreferences?.getBoolean("Bitcoin", false) ?: false
                        val compositeState = tokenPreferences?.getTokenState("BTC", "Bitcoin", null) ?: false
                        Log.d("TokenViewModel", "🔍 Bitcoin - Simple: $simpleState, Composite: $compositeState")
                    }
                    "Ethereum" -> {
                        val simpleState = sharedPreferences?.getBoolean("Ethereum", false) ?: false
                        val compositeState = tokenPreferences?.getTokenState("ETH", "Ethereum", null) ?: false
                        Log.d("TokenViewModel", "🔍 Ethereum - Simple: $simpleState, Composite: $compositeState")
                    }
                    "Netcoincapital" -> {
                        val simpleState = sharedPreferences?.getBoolean("Netcoincapital", false) ?: false
                        val compositeState = tokenPreferences?.getTokenState("NCC", "Netcoincapital", null) ?: false
                        Log.d("TokenViewModel", "🔍 Netcoincapital - Simple: $simpleState, Composite: $compositeState")
                    }
                }
            }
        }
        
        // اطمینان از فعال بودن توکن‌های پیش‌فرض در currencies
        val defaultCryptoTokens = listOf(
            CryptoToken(
                name = "Bitcoin",
                symbol = "BTC",
                BlockchainName = "Bitcoin",
                iconUrl = "https://coinceeper.com/defualtIcons/bitcoin.png",
                isEnabled = true,
                isToken = false,
                SmartContractAddress = null
            ),
            CryptoToken(
                name = "Ethereum", 
                symbol = "ETH",
                BlockchainName = "Ethereum",
                iconUrl = "https://coinceeper.com/defualtIcons/ethereum.png",
                isEnabled = true,
                isToken = false,
                SmartContractAddress = null
            ),
            CryptoToken(
                name = "Netcoincapital",
                symbol = "NCC", 
                BlockchainName = "Netcoincapital",
                iconUrl = "https://coinceeper.com/defualtIcons/netcoincapital.png",
                isEnabled = true,
                isToken = true,
                SmartContractAddress = null
            )
        )
        
        // اگر currencies خالی است، توکن‌های پیش‌فرض را اضافه کن
        if (currencies.isEmpty()) {
            withContext(Dispatchers.Main) {
                currencies = defaultCryptoTokens
                setActiveTokensForUser(defaultCryptoTokens)
                Log.d("TokenViewModel", "✅ Set default tokens as active: ${defaultCryptoTokens.size} tokens")
                Log.d("TokenViewModel", "✅ Active tokens: ${defaultCryptoTokens.map { it.name }}")
            }
        }
        
        // همیشه اطمینان از فعال بودن توکن‌های پیش‌فرض
        val enabledDefaultTokens = defaultCryptoTokens.filter { token ->
            val isEnabled = tokenPreferences?.getTokenState(token.symbol, token.BlockchainName, token.SmartContractAddress) ?: true
            Log.d("TokenViewModel", "🔍 Default token ${token.name} (${token.symbol}) enabled state: $isEnabled")
            isEnabled
        }
        
        Log.d("TokenViewModel", "📊 Enabled default tokens count: ${enabledDefaultTokens.size}")
        
        if (enabledDefaultTokens.isNotEmpty()) {
            withContext(Dispatchers.Main) {
                val currentActive = _activeTokens.value.toMutableList()
                enabledDefaultTokens.forEach { defaultToken ->
                    if (!currentActive.any { it.symbol == defaultToken.symbol }) {
                        currentActive.add(defaultToken)
                        Log.d("TokenViewModel", "➕ Added default token to active list: ${defaultToken.name}")
                    }
                }
                setActiveTokensForUser(currentActive)
                Log.d("TokenViewModel", "✅ Ensured default tokens are active: ${currentActive.size} total active tokens")
            }
        }
    }

    fun smartLoadTokens(forceRefresh: Boolean = false) {
        viewModelScope.launch {
            try {
                isLoading = true
                errorMessage = null

                Log.d("TokenViewModel", "🔄 Starting smartLoadTokens for user: $userId")

                // اگر forceRefresh فعال باشد یا کش معتبر نباشد، از API بارگیری می‌کنیم
                if (forceRefresh || !isCacheValid()) {
                    loadFromApi()
                } else {
                    // سعی در بارگیری از کش
                    val cachedLoaded = loadFromCache()
                    if (!cachedLoaded) {
                        loadFromApi()
                    }
                }

                // ذخیره توکن‌های کاربر در StateFlow مربوطه
                saveUserTokens(userId, currencies)

            } catch (e: Exception) {
                errorMessage = "Error: ${e.message}"
                Log.e("TokenViewModel", "❌ Error in smartLoadTokens: ${e.message}")
            } finally {
                isLoading = false
            }
        }
    }

    private suspend fun loadFromApi() {
        Log.d("TokenViewModel", "🌐 Loading from API for user: $userId")
        val response = api.getAllCurrencies()
        val existingBalances = _activeTokens.value.associateBy { it.symbol }

        if (response.success) {
            val tokens = response.currencies.map { token ->
                // Get user-specific token state
                val savedState = getTokenStateForUser(
                    CryptoToken(
                        name = token.CurrencyName,
                        symbol = token.Symbol,
                        BlockchainName = token.BlockchainName,
                        iconUrl = token.Icon ?: "https://coinceeper.com/defualtIcons/coin.png",
                        isEnabled = false, // Default to false, will be updated based on saved state
                        isToken = token.IsToken,
                        SmartContractAddress = token.SmartContractAddress
                    )
                )
                
                val previousAmount = existingBalances[token.Symbol]?.amount ?: 0.0

                CryptoToken(
                    name = token.CurrencyName,
                    symbol = token.Symbol,
                    BlockchainName = token.BlockchainName,
                    iconUrl = token.Icon ?: "https://coinceeper.com/defualtIcons/coin.png",
                    isEnabled = savedState,
                    isToken = token.IsToken,
                    amount = previousAmount,
                    SmartContractAddress = token.SmartContractAddress
                )
            }

            val orderedTokens = maintainTokenOrder(tokens)
            saveToCache(orderedTokens)

            withContext(Dispatchers.Main) {
                currencies = orderedTokens
                // Update active tokens based on user-specific states
                val enabledTokens = orderedTokens.filter { getTokenStateForUser(it) }
                setActiveTokensForUser(enabledTokens)
                
                // Save user tokens in StateFlow
                saveUserTokens(userId, orderedTokens)
            }

            val activeTokens = _activeTokens.value
            if (activeTokens.isNotEmpty()) {
                val selectedCurrency = context?.let { getSelectedCurrency(it) } ?: "USD"
                fetchPrices(
                    activeSymbols = activeTokens.map { it.symbol },
                    fiatCurrencies = listOf(selectedCurrency)
                )
            }

            Log.d("TokenViewModel", "✅ API load successful with prices for user: $userId")
        } else {
            errorMessage = "Failed to load tokens"
            Log.e("TokenViewModel", "❌ API call failed for user: $userId")
        }
    }

    private suspend fun loadFromCache(): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val sharedPreferences = context?.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
                val cachedTokensJson = sharedPreferences?.getString("cachedUserTokens_$userId", null)

                if (cachedTokensJson.isNullOrEmpty()) {
                    Log.d("TokenViewModel", "📁 Cache is empty for user: $userId")
                    return@withContext false
                }

                val gson = Gson()
                val storedTokens: List<CryptoToken> = gson.fromJson(
                    cachedTokensJson,
                    object : TypeToken<List<CryptoToken>>() {}.type
                )

                val updatedTokens = storedTokens.map { token ->
                    // Get user-specific token state
                    val isEnabled = getTokenStateForUser(token)
                    token.copy(isEnabled = isEnabled)
                }

                withContext(Dispatchers.Main) {
                    currencies = updatedTokens
                    setActiveTokensForUser(updatedTokens.filter { getTokenStateForUser(it) })
                    saveUserTokens(userId, updatedTokens)
                }

                Log.d("TokenViewModel", "✅ Cache load successful for user: $userId")
                true
            } catch (e: Exception) {
                Log.e("TokenViewModel", "❌ Error loading from cache for user: $userId")
                false
            }
        }
    }

    // بهبود تابع بررسی اعتبار کش
    private fun isCacheValid(): Boolean {
        val sharedPreferences = context?.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        val lastCacheTime = sharedPreferences?.getLong("cache_timestamp_$userId", 0) ?: 0
        val currentTime = System.currentTimeMillis()
        val isValid = (currentTime - lastCacheTime) < CACHE_EXPIRY_TIME
        Log.d("TokenViewModel", "📁 Cache validity check: $isValid (age: ${(currentTime - lastCacheTime) / 1000} seconds)")
        return isValid
    }

    // بررسی اعتبار کش قیمت‌ها
    private fun isPriceCacheValid(): Boolean {
        val sharedPreferences = context?.getSharedPreferences("token_prices", Context.MODE_PRIVATE)
        val lastCacheTime = sharedPreferences?.getLong("price_cache_timestamp", 0) ?: 0
        val currentTime = System.currentTimeMillis()
        val isValid = (currentTime - lastCacheTime) < PRICE_CACHE_EXPIRY_TIME
        Log.d("TokenViewModel", "📁 Price cache validity check: $isValid (age: ${(currentTime - lastCacheTime) / 1000} seconds)")
        return isValid
    }

    // بارگذاری قیمت‌ها از کش
    suspend fun loadPricesFromCache(): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val sharedPreferences = context?.getSharedPreferences("token_prices", Context.MODE_PRIVATE)
                val cachedPricesJson = sharedPreferences?.getString("cached_prices", null)

                if (!cachedPricesJson.isNullOrEmpty()) {
                    val gson = Gson()
                    val storedPrices: Map<String, Map<String, PriceData>> = gson.fromJson(
                        cachedPricesJson,
                        object : TypeToken<Map<String, Map<String, PriceData>>>() {}.type
                    )

                    // نمایش سریع قیمت‌های کش شده
                    withContext(Dispatchers.Main) {
                        _tokenPrices.value = storedPrices
                    }

                    val lastCacheTime = sharedPreferences.getLong("price_cache_timestamp", 0)
                    val cacheAge = (System.currentTimeMillis() - lastCacheTime) / 1000
                    Log.d("TokenViewModel", "📊 Showing cached prices (age: ${cacheAge}s)")
                    true
                } else {
                    Log.d("TokenViewModel", "📊 No cached prices available")
                    false
                }
            } catch (e: Exception) {
                Log.e("TokenViewModel", "❌ Error loading prices from cache: ${e.message}")
                false
            }
        }
    }

    // ذخیره داده‌ها در کش با تاریخ و زمان
    private suspend fun saveToCache(tokens: List<CryptoToken>) {
        withContext(Dispatchers.IO) {
            try {
                val sharedPreferences = context?.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
                val gson = Gson()
                val tokensJson = gson.toJson(tokens)
                sharedPreferences?.edit()
                    ?.putString("cachedUserTokens_$userId", tokensJson)
                    ?.putLong("cache_timestamp_$userId", System.currentTimeMillis())
                    ?.apply()
                Log.d("TokenViewModel", "💾 Tokens saved to cache. Count: ${tokens.size}")
            } catch (e: Exception) {
                Log.e("TokenViewModel", "❌ Error saving to cache: ${e.message}")
            }
        }
    }

    // ذخیره قیمت‌ها در کش
    private suspend fun savePricesToCache(prices: Map<String, Map<String, PriceData>>) {
        withContext(Dispatchers.IO) {
            try {
                val sharedPreferences = context?.getSharedPreferences("token_prices", Context.MODE_PRIVATE)
                val gson = Gson()
                val pricesJson = gson.toJson(prices)
                sharedPreferences?.edit()
                    ?.putString("cached_prices", pricesJson)
                    ?.putLong("price_cache_timestamp", System.currentTimeMillis())
                    ?.apply()
                Log.d("TokenViewModel", "💰 Prices saved to cache. Count: ${prices.size} tokens")
            } catch (e: Exception) {
                Log.e("TokenViewModel", "❌ Error saving prices to cache: ${e.message}")
            }
        }
    }



    // دریافت قیمت‌ها از API با در نظر گرفتن کش
    private suspend fun fetchPrices(
        activeSymbols: List<String>,
        fiatCurrencies: List<String> = listOf("USD", "EUR", "IRR")
    ) {
        if (activeSymbols.isEmpty()) {
            Log.d("TokenViewModel", "⚠️ No active symbols to fetch prices for")
            return
        }

        // اگر کش معتبره، اول نشونش بده برای نمایش سریع
        if (isPriceCacheValid()) {
            loadPricesFromCache()
        }

        withContext(Dispatchers.IO) {
            try {
                Log.d("TokenViewModel", "🔄 Fetching fresh prices for symbols: $activeSymbols")

                // Map symbols to match the API request format (lowercase)
                val apiSymbols = activeSymbols.map {
                    when (it) {
                        "BTC" -> "bitcoin"
                        "ETH" -> "ethereum"
                        "TRX" -> "tron"
                        "BNB" -> "BNB"
                        "SHIB" -> "shiba inu"
                        else -> it.lowercase()
                    }
                }

                val pricesRequest = PricesRequest(
                    Symbol = apiSymbols,
                    FiatCurrencies = fiatCurrencies
                )
                val pricesResponse = api.getPrices(pricesRequest)

                val priceDataMap = mutableMapOf<String, Map<String, PriceData>>()

                var allPricesAreZero = true // پرچم بررسی

                // Map returned keys to expected format
                val mappedPrices = mutableMapOf<String, Map<String, PriceData>>()
                pricesResponse.prices?.forEach { (key, value) ->
                    val mappedKey = when (key) {
                        "BTC" -> "BTC"
                        "ETH" -> "ETH"
                        "TRX" -> "TRX"
                        "BNB" -> "BNB"
                        "bitcoin" -> "BTC"
                        "ethereum" -> "ETH"
                        "tron" -> "TRX"
                        "BNB" -> "BNB"
                        "shiba inu" -> "SHIB"
                        else -> key
                    }
                    mappedPrices[mappedKey] = value
                }

                activeSymbols.forEach { symbol ->
                    val currencyMap = mutableMapOf<String, PriceData>()

                    fiatCurrencies.forEach { currency ->
                        val priceInfo = mappedPrices[symbol]?.get(currency)

                        if (priceInfo != null) {
                            val price = priceInfo.price.replace(",", "")
                            val change24h = priceInfo.change_24h ?: "+0.0%"

                            currencyMap[currency] = PriceData(change24h, price)

                            if (price.toDoubleOrNull() != 0.0) {
                                allPricesAreZero = false // حداقل یک قیمت معتبره
                            }
                        }
                    }

                    if (currencyMap.isNotEmpty()) {
                        priceDataMap[symbol] = currencyMap
                    }
                }

                if (allPricesAreZero) {
                    Log.w("TokenViewModel", "⚠️ All prices are 0.0 — skipping cache update.")
                    return@withContext // نه کش آپدیت میشه نه UI
                }

                withContext(Dispatchers.Main) {
                    // ✅ آپدیت UI
                    val currentPrices = _tokenPrices.value.toMutableMap()
                    priceDataMap.forEach { (symbol, newPrices) ->
                        val existing = currentPrices[symbol]?.toMutableMap() ?: mutableMapOf()
                        existing.putAll(newPrices)
                        currentPrices[symbol] = existing
                    }
                    _tokenPrices.value = currentPrices
                }

                // ✅ ذخیره در کش فقط اگر قیمت معتبره
                savePricesToCache(_tokenPrices.value)

                Log.d("TokenViewModel", "✅ Fresh prices fetched and cached successfully")

            } catch (e: Exception) {
                Log.e("TokenViewModel", "❌ Error fetching prices: ${e.message}")
            }
        }
    }




    // دریافت gas fees
    suspend fun fetchGasFees() {
        withContext(Dispatchers.IO) {
            try {
                val gasFeeResponse = api.getGasFee()

                Log.d("GasFees", "Raw response: $gasFeeResponse")

                // ایجاد نقشه از همه گس‌فی‌های دریافتی
                val fees = mapOf(
                    "Arbitrum" to (gasFeeResponse.Arbitrum?.gas_fee ?: "0.0"),
                    "Avalanche" to (gasFeeResponse.Avalanche?.gas_fee ?: "0.0"),
                    "Binance" to (gasFeeResponse.Binance?.gas_fee ?: "0.0"),
                    "Bitcoin" to (gasFeeResponse.Bitcoin?.gas_fee ?: "0.0"),
                    "Cardano" to (gasFeeResponse.Cardano?.gas_fee ?: "0.0"),
                    "Cosmos" to (gasFeeResponse.Cosmos?.gas_fee ?: "0.0"),
                    "Ethereum" to (gasFeeResponse.Ethereum?.gas_fee ?: "0.0"),
                    "Fantom" to (gasFeeResponse.Fantom?.gas_fee ?: "0.0"),
                    "Optimism" to (gasFeeResponse.Optimism?.gas_fee ?: "0.0"),
                    "Polkadot" to (gasFeeResponse.Polkadot?.gas_fee ?: "0.0"),
                    "Polygon" to (gasFeeResponse.Polygon?.gas_fee ?: "0.0"),
                    "Solana" to (gasFeeResponse.Solana?.gas_fee ?: "0.0"),
                    "Tron" to (gasFeeResponse.Tron?.gas_fee ?: "0.0"),
                    "XRP" to (gasFeeResponse.XRP?.gas_fee ?: "0.0")
                )

                Log.d("GasFees", "Raw Ethereum gas fee: ${gasFeeResponse.Ethereum?.gas_fee}")

                // تبدیل هر مقدار به فرمت صحیح عددی
                val formattedFees = fees.mapValues { (_, value) ->
                    try {
                        // تبدیل نمایش علمی به عدد معمولی
                        val parsedValue = if (value.contains("E") || value.contains("e")) {
                            val doubleValue = value.toDouble()
                            Log.d("GasFees", "Converting scientific notation: $value to $doubleValue")
                            doubleValue.toString()
                        } else {
                            value
                        }
                        parsedValue
                    } catch (e: Exception) {
                        Log.e("GasFees", "Error formatting gas fee: $value", e)
                        "0.0"
                    }
                }

                Log.d("GasFees", "Processed fees: $formattedFees")
                Log.d("GasFees", "Processed Ethereum fee: ${formattedFees["Ethereum"]}")

                withContext(Dispatchers.Main) {
                    _gasFees.value = formattedFees
                    Log.d("GasFees", "Updated _gasFees value: ${_gasFees.value}")
                    Log.d("GasFees", "Final Ethereum gas fee in _gasFees: ${_gasFees.value["Ethereum"]}")
                }
            } catch (e: Exception) {
                Log.e("GasFees", "Error fetching gas fees", e)
                withContext(Dispatchers.Main) {
                    _gasFees.value = mapOf(
                        "Bitcoin" to "0.0",
                        "Ethereum" to "0.0"
                    )
                }
            }
        }
    }

    // متدهای زیر برای حفظ سازگاری با کد موجود حفظ شده‌اند
    // اما تغییر یافته‌اند تا از تابع بهینه‌شده smartLoadTokens استفاده کنند

    fun loadTokensFromApi(api: Api) {
        smartLoadTokens(false)
    }

    fun isTokenEnabled(token: CryptoToken): Boolean {
        return tokenPreferences?.getTokenState(
            token.symbol, 
            token.BlockchainName, 
            token.SmartContractAddress
        ) ?: false
    }

    fun getEnabledTokenNames(): List<String> {
        return tokenPreferences?.getAllEnabledTokenNames() ?: emptyList()
    }

    fun getEnabledTokenKeys(): List<String> {
        val keys = tokenPreferences?.getAllEnabledTokenKeys() ?: emptyList()
        Log.d("TokenViewModel", "🔑 === getEnabledTokenKeys ===")
        Log.d("TokenViewModel", "🔑 Total enabled keys count: ${keys.size}")
        keys.forEachIndexed { index, key ->
            Log.d("TokenViewModel", "🔑 [$index] Key: '$key'")
        }
        
        // اضافه کردن بررسی manual برای توکن‌های پیش‌فرض
        val manualChecks = listOf(
            "BTC_Bitcoin_" to (tokenPreferences?.getTokenState("BTC", "Bitcoin", null) ?: false),
            "ETH_Ethereum_" to (tokenPreferences?.getTokenState("ETH", "Ethereum", null) ?: false),
            "NCC_Netcoincapital_" to (tokenPreferences?.getTokenState("NCC", "Netcoincapital", null) ?: false)
        )
        
        Log.d("TokenViewModel", "🔑 Manual checks for default tokens:")
        manualChecks.forEach { (key, state) ->
            Log.d("TokenViewModel", "🔑 Manual check - $key: $state")
        }
        
        return keys
    }

    fun loadTokensForUser(userId: String, api: Api) {
        // این متد دیگر مستقیماً فراخوانی نمی‌شود، اما برای حفظ سازگاری نگه داشته است
        smartLoadTokens(false)
    }

    fun updateActiveTokens(tokens: List<CryptoToken>) {
        viewModelScope.launch {
            setActiveTokensForUser(tokens)
            currencies = currencies.map { currentToken ->
                val updatedToken = tokens.find { it.name == currentToken.name }
                currentToken.copy(isEnabled = updatedToken?.isEnabled ?: currentToken.isEnabled)
            }

            val selectedCurrency = context?.let { getSelectedCurrency(it) } ?: "USD"
            fetchPrices(
                activeSymbols = tokens.filter { it.isEnabled }.map { it.symbol },
                fiatCurrencies = listOf(selectedCurrency)
            )
        }
    }


    fun updateActiveTokensFromPreferences() {
        viewModelScope.launch {
            try {
                // به‌روزرسانی وضعیت همه توکن‌ها از Preferences
                currencies = currencies.map { token ->
                    val isEnabled = tokenPreferences?.getTokenState(
                        token.symbol, 
                        token.BlockchainName, 
                        token.SmartContractAddress
                    ) ?: false
                    token.copy(isEnabled = isEnabled)
                }
                
                // به‌روزرسانی لیست توکن‌های فعال
                val updatedActiveTokens = currencies.filter { it.isEnabled }
                setActiveTokensForUser(updatedActiveTokens)
                
                Log.d("TokenViewModel", "✅ Updated active tokens from preferences: ${updatedActiveTokens.size} tokens")
                Log.d("TokenViewModel", "✅ Active tokens: ${updatedActiveTokens.map { it.name }}")
                
            } catch (e: Exception) {
                Log.e("TokenViewModel", "❌ Error updating active tokens from preferences: ${e.message}")
            }
        }
    }

    // متد جدید برای همگام‌سازی فوری بعد از تغییر تاگل
    fun refreshActiveTokens() {
        val enabledTokens = currencies.filter { it.isEnabled }
        setActiveTokensForUser(enabledTokens)
        Log.d("TokenViewModel", "🔄 Refreshed active tokens: ${enabledTokens.size} tokens")
    }

    // متد جدید برای همگام‌سازی کامل وضعیت توکن‌ها
    fun forceUpdateTokenStates() {
        viewModelScope.launch {
            try {
                Log.d("TokenViewModel", "🔄 Force updating all token states...")
                
                // به‌روزرسانی کامل وضعیت همه توکن‌ها
                currencies = currencies.map { token ->
                    val isEnabled = tokenPreferences?.getTokenState(
                        token.symbol, 
                        token.BlockchainName, 
                        token.SmartContractAddress
                    ) ?: false
                    token.copy(isEnabled = isEnabled)
                }
                
                // فوری به‌روزرسانی لیست فعال
                val enabledTokens = currencies.filter { it.isEnabled }
                setActiveTokensForUser(enabledTokens)
                
                Log.d("TokenViewModel", "✅ Force update completed")
                Log.d("TokenViewModel", "✅ Total tokens: ${currencies.size}")
                Log.d("TokenViewModel", "✅ Active tokens: ${activeTokens.value.size}")
                Log.d("TokenViewModel", "✅ Active tokens list: ${activeTokens.value.map { "${it.name} (${it.symbol})" }}")
                
                // اگر توکن‌های فعال وجود دارند، قیمت‌ها را بارگذاری کن
                if (enabledTokens.isNotEmpty()) {
                    val selectedCurrency = context?.let { getSelectedCurrency(it) } ?: "USD"
                    fetchPrices(
                        activeSymbols = enabledTokens.map { it.symbol },
                        fiatCurrencies = listOf(selectedCurrency)
                    )
                }
                
            } catch (e: Exception) {
                Log.e("TokenViewModel", "❌ Error in force update: ${e.message}")
            }
        }
    }

    suspend fun loadAllUserTokens(api: Api) {
        // این متد برای حفظ سازگاری نگه داشته شده است
        smartLoadTokens(false)
    }

    fun resetAllTokenStates() {
        viewModelScope.launch {
            context?.let { ctx ->
                val sharedPreferences = ctx.getSharedPreferences("token_prefs_$userId", Context.MODE_PRIVATE)
                sharedPreferences.edit().clear().apply()

                // بازگرداندن توکن‌های پیش‌فرض به حالت فعال
                val defaultTokens = listOf("Bitcoin", "Ethereum", "Netcoincapital")
                val editor = sharedPreferences.edit()
                defaultTokens.forEach { token ->
                    editor.putBoolean(token, true)
                }
                editor.apply()

                // به‌روزرسانی لیست توکن‌ها
                currencies = currencies.map { token ->
                    val isDefaultToken = defaultTokens.contains(token.name)
                    token.copy(isEnabled = isDefaultToken)
                }

                setActiveTokensForUser(currencies.filter { it.isEnabled })

                // به‌روزرسانی قیمت‌ها برای توکن‌های فعال
                val activeTokens = _activeTokens.value
                if (activeTokens.isNotEmpty()) {
                    fetchPrices(activeTokens.map { it.symbol })
                }

                Log.d("TokenViewModel", "🔄 Reset all token states to default")
            }
        }
    }

    // به‌روزرسانی تابع forceRefresh
    fun forceRefresh() {
        viewModelScope.launch {
            try {
                isLoading = true
                Log.d("TokenViewModel", "🔄 Force refreshing data - starting with gas fees and token list")

                // 1. دریافت gas fees
                fetchGasFees()

                // 2. به‌روزرسانی لیست توکن‌ها و قیمت‌ها
                smartLoadTokens(true) // Force refresh token list and prices

                // 3. به‌روزرسانی موجودی‌ها
                val balances = fetchBalancesForActiveTokens()

                // 4. به‌روزرسانی قیمت‌ها برای همه توکن‌های فعال
                val activeTokens = _activeTokens.value
                if (activeTokens.isNotEmpty()) {
                    val selectedCurrency = context?.let { getSelectedCurrency(it) } ?: "USD"
                    fetchPrices(
                        activeSymbols = activeTokens.map { it.symbol },
                        fiatCurrencies = listOf(selectedCurrency)
                    )
                }

                // 5. مرتب‌سازی توکن‌ها بر اساس ارزش
                val updatedTokens = activeTokens.map { token ->
                    val balance = balances[token.symbol]?.toDoubleOrNull() ?: 0.0
                    token.copy(amount = balance)
                }
                val sortedTokens = sortTokensByDollarValue(updatedTokens)
                setActiveTokensForUser(sortedTokens)

                Log.d("TokenViewModel", "✅ Force refresh completed successfully")
            } catch (e: Exception) {
                Log.e("TokenViewModel", "❌ Error during force refresh: ${e.message}", e)
                errorMessage = "Failed to refresh data: ${e.message}"
            } finally {
                isLoading = false
            }
        }
    }

    // اضافه کردن متد برای به‌روزرسانی لیست توکن‌های فعال
    fun setActiveTokens(newTokens: List<CryptoToken>) {
        viewModelScope.launch {
            setActiveTokensForUser(newTokens)
        }
    }

    // Helper method to sort tokens by dollar value (amount * price) from highest to lowest
    private fun sortTokensByDollarValue(tokens: List<CryptoToken>): List<CryptoToken> {
        val selectedCurrency = context?.let { getSelectedCurrency(it) } ?: "USD"
        return tokens.sortedByDescending { token ->
            val price = getTokenPrice(token.symbol, selectedCurrency)
            (token.amount ?: 0.0) * price
        }
    }

    // Helper method to get token price in selected currency
    private fun getTokenPrice(symbol: String, currency: String): Double {
        return _tokenPrices.value[symbol]?.get(currency)?.price?.replace(",", "")?.toDoubleOrNull() ?: 0.0
    }

    // اضافه کردن متد جدید برای به‌روزرسانی ترتیب توکن‌ها
    fun updateTokenOrder(newOrder: List<CryptoToken>) {
        viewModelScope.launch {
            // Sort by descending dollar value to ensure highest value at the top
            val sortedByValue = sortTokensByDollarValue(newOrder)
            setActiveTokensForUser(sortedByValue)
            // ذخیره ترتیب جدید در TokenPreferences
            tokenPreferences?.saveTokenOrder(sortedByValue.map { it.symbol })
        }
    }

    private fun loadSavedTokenOrder(tokens: List<CryptoToken>): List<CryptoToken> {
        val savedOrder = tokenPreferences?.getTokenOrder() ?: return tokens
        if (savedOrder.isEmpty()) return tokens

        val tokenMap = tokens.associateBy { "${it.symbol}_${it.name}" }
        val orderedTokens = savedOrder.mapNotNull { symbol -> tokenMap[symbol] }.toMutableList()

        tokens.forEach { token ->
            if (!orderedTokens.contains(token)) {
                orderedTokens.add(token)
            }
        }

        return orderedTokens
    }

    // جایگزینی getTokens با متد موجود
    private suspend fun getTokens(): List<CryptoToken> {
        return try {
            val response = api.getAllCurrencies()
            if (response.success) {
                response.currencies.map { token ->
                    // استفاده از کلید ترکیبی منحصر به فرد
                    val isEnabled = tokenPreferences?.getTokenState(
                        token.Symbol, 
                        token.BlockchainName, 
                        token.SmartContractAddress
                    ) ?: false
                    
                    CryptoToken(
                        name = token.CurrencyName,
                        symbol = token.Symbol,
                        BlockchainName = token.BlockchainName,
                        iconUrl = token.Icon ?: "https://coinceeper.com/defualtIcons/coin.png",
                        isEnabled = isEnabled,
                        isToken = token.IsToken,
                        SmartContractAddress = token.SmartContractAddress
                    )
                }
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            Log.e("TokenViewModel", "Error getting tokens: ${e.message}")
            emptyList()
        }
    }

    fun loadTokens() {
        viewModelScope.launch {
            try {
                val tokens = getTokens()
                val orderedTokens = loadSavedTokenOrder(tokens)
                setActiveTokensForUser(orderedTokens)
            } catch (e: Exception) {
                Log.e("TokenViewModel", "Error loading tokens: ${e.message}")
            }
        }
    }

    fun toggleToken(token: CryptoToken, newState: Boolean) {
        viewModelScope.launch {
            try {
                Log.d("TokenViewModel", "🔄 Toggling token ${token.name} to $newState for user: $userId")
                
                // Save user-specific token state
                saveTokenStateForUser(token, newState)

                // Update currencies list
                currencies = currencies.map { currentToken ->
                    if (currentToken.symbol == token.symbol && 
                        currentToken.BlockchainName == token.BlockchainName &&
                        currentToken.SmartContractAddress == token.SmartContractAddress) {
                        currentToken.copy(isEnabled = newState)
                    } else {
                        currentToken
                    }
                }

                // Update active tokens list
                val updatedActiveTokens = if (newState) {
                    val currentActive = _activeTokens.value.toMutableList()
                    if (!currentActive.any { it.symbol == token.symbol && it.BlockchainName == token.BlockchainName }) {
                        currentActive.add(token.copy(isEnabled = true))
                    }
                    currentActive
                } else {
                    _activeTokens.value.filter { 
                        !(it.symbol == token.symbol && 
                          it.BlockchainName == token.BlockchainName &&
                          it.SmartContractAddress == token.SmartContractAddress)
                    }
                }
                
                setActiveTokensForUser(updatedActiveTokens)

                // Update prices and balances if token is enabled
                if (newState) {
                    val selectedCurrency = context?.let { getSelectedCurrency(it) } ?: "USD"
                    fetchPrices(
                        activeSymbols = updatedActiveTokens.map { it.symbol },
                        fiatCurrencies = listOf(selectedCurrency)
                    )
                    fetchBalancesForActiveTokens()
                }

                Log.d("TokenViewModel", "✅ Token ${token.name} toggled to $newState for user: $userId")
                Log.d("TokenViewModel", "✅ Active tokens count: ${_activeTokens.value.size}")
            } catch (e: Exception) {
                Log.e("TokenViewModel", "❌ Error toggling token: ${e.message}")
                errorMessage = "Failed to update token state"
            }
        }
    }

    // تابع کمکی برای بررسی توکن‌های پیش‌فرض
    private fun isDefaultToken(name: String): Boolean {
        return name.equals("Netcoincapital", ignoreCase = true) ||
                name.equals("Bitcoin", ignoreCase = true) ||
                name.equals("Ethereum", ignoreCase = true)
    }

    // اضافه کردن متد جدید برای مدیریت ترتیب توکن‌ها
    private fun maintainTokenOrder(tokens: List<CryptoToken>): List<CryptoToken> {
        val savedOrder = tokenPreferences?.getTokenOrder() ?: return tokens
        if (savedOrder.isEmpty()) return tokens

        val tokenMap = tokens.associateBy { "${it.symbol}_${it.name}" }
        val orderedTokens = mutableListOf<CryptoToken>()
        val processedSymbols = mutableSetOf<String>()

        // اول توکن‌های موجود در ترتیب ذخیره شده را اضافه می‌کنیم
        savedOrder.forEach { symbol ->
            if (!processedSymbols.contains(symbol)) {
                tokenMap[symbol]?.let { token ->
                    orderedTokens.add(token)
                    processedSymbols.add(symbol)
                }
            }
        }

        // سپس توکن‌های باقیمانده را اضافه می‌کنیم
        tokens.forEach { token ->
            if (!processedSymbols.contains(token.symbol)) {
                orderedTokens.add(token)
                processedSymbols.add(token.symbol)
            }
        }

        return orderedTokens
    }

    /**
     * Calculates the average 24-hour price change percentage across all active tokens.
     * @return A formatted string representing the average change percentage (e.g., "+2.45%" or "-1.20%")
     */
    fun getAverageChange24h(): String? {
        val activeTokens = _activeTokens.value
        if (activeTokens.isEmpty()) return null

        var totalChangePercent = 0.0
        var validTokenCount = 0

        // Iterate through active tokens and calculate average change
        for (token in activeTokens) {
            val tokenPricesMap = _tokenPrices.value[token.symbol]
            val usdPriceData = tokenPricesMap?.get("USD")

            // Extract change percentage if available
            val changeStr = usdPriceData?.change_24h
            if (!changeStr.isNullOrEmpty()) {
                try {
                    // Remove % sign and convert to double
                    val change = changeStr.removeSuffix("%").toDoubleOrNull()
                    if (change != null) {
                        totalChangePercent += change
                        validTokenCount++
                    }
                } catch (e: Exception) {
                    Log.e("TokenViewModel", "Error parsing change percentage: ${e.message}")
                }
            }
        }

        // Calculate average if we have valid tokens
        return if (validTokenCount > 0) {
            val averageChange = totalChangePercent / validTokenCount
            // Format with + or - sign and 2 decimal places
            val sign = if (averageChange >= 0) "+" else ""
            "${sign}${String.format("%.2f", averageChange)}%"
        } else {
            null
        }
    }

    // Add a method to ensure non-zero gas fees are loaded for a blockchain
    suspend fun ensureGasFee(blockchainName: String): String {
        return withContext(Dispatchers.IO) {
            try {
                // Check if we already have a valid gas fee
                val currentFee = _gasFees.value[blockchainName]

                // If null, empty, or "0.0", try to fetch it again
                if (currentFee.isNullOrEmpty() || currentFee == "0.0") {
                    Log.d("GasFees", "Gas fee for $blockchainName is $currentFee - trying to fetch fresh data")
                    fetchGasFees()

                    // Get the updated fee
                    val updatedFee = _gasFees.value[blockchainName]

                    if (updatedFee.isNullOrEmpty() || updatedFee == "0.0") {
                        // If still no valid fee, use default fallback values
                        val fallbackFee = when(blockchainName) {
                            "Ethereum" -> "0.0012"
                            "Bitcoin" -> "0.0001"
                            "Tron" -> "0.00001"
                            "Binance" -> "0.0005"
                            else -> "0.001"
                        }
                        Log.d("GasFees", "Using fallback fee for $blockchainName: $fallbackFee")
                        return@withContext fallbackFee
                    }

                    Log.d("GasFees", "Successfully fetched fee for $blockchainName: $updatedFee")
                    return@withContext updatedFee
                }

                Log.d("GasFees", "Using existing fee for $blockchainName: $currentFee")
                return@withContext currentFee
            } catch (e: Exception) {
                Log.e("GasFees", "Error ensuring gas fee for $blockchainName", e)

                // Fallback values for different blockchains
                val fallbackFee = when(blockchainName) {
                    "Ethereum" -> "0.0012"
                    "Bitcoin" -> "0.0001"
                    "Tron" -> "0.00001"
                    "Binance" -> "0.0005"
                    else -> "0.001"
                }

                return@withContext fallbackFee
            }
        }
    }

    // متد نهایی برای اطمینان از همگام‌سازی کامل
    fun ensureTokensSynchronized() {
        viewModelScope.launch {
            try {
                Log.d("TokenViewModel", "🔄 Ensuring tokens are fully synchronized...")
                
                // اگر currencies خالی است، ابتدا از cache بارگذاری کن
                if (currencies.isEmpty()) {
                    Log.d("TokenViewModel", "📁 Currencies is empty, trying to load from cache or API")
                    val cacheLoaded = loadFromCache()
                    if (!cacheLoaded) {
                        Log.d("TokenViewModel", "📁 No cache available, loading from API")
                        loadFromApi()
                        return@launch
                    }
                }
                
                // همگام‌سازی کامل وضعیت توکن‌ها با preferences
                val updatedCurrencies = currencies.map { token ->
                    val isEnabled = tokenPreferences?.getTokenState(
                        token.symbol, 
                        token.BlockchainName, 
                        token.SmartContractAddress
                    ) ?: false
                    token.copy(isEnabled = isEnabled)
                }
                
                currencies = updatedCurrencies
                
                // فوری به‌روزرسانی لیست فعال بر اساس preferences
                val enabledTokens = updatedCurrencies.filter { it.isEnabled }
                
                // اطمینان از وجود توکن‌های پیش‌فرض اگر هیچ توکنی فعال نیست
                if (enabledTokens.isEmpty()) {
                    Log.w("TokenViewModel", "⚠️ No enabled tokens found, initializing defaults...")
                    initializeDefaultTokens()
                    
                    // بررسی مجدد پس از اولیه‌سازی
                    val reloadedCurrencies = currencies.map { token ->
                        val isEnabled = tokenPreferences?.getTokenState(
                            token.symbol, 
                            token.BlockchainName, 
                            token.SmartContractAddress
                        ) ?: (token.name in listOf("Bitcoin", "Ethereum", "Netcoincapital"))
                        token.copy(isEnabled = isEnabled)
                    }
                    
                    currencies = reloadedCurrencies
                    val finalEnabledTokens = reloadedCurrencies.filter { it.isEnabled }
                    setActiveTokensForUser(finalEnabledTokens)
                    
                    Log.d("TokenViewModel", "✅ Default tokens reinitialized: ${finalEnabledTokens.size} enabled")
                } else {
                    setActiveTokensForUser(enabledTokens)
                }
                
                Log.d("TokenViewModel", "✅ Synchronization completed")
                Log.d("TokenViewModel", "✅ Total currencies: ${currencies.size}")
                Log.d("TokenViewModel", "✅ Active tokens: ${_activeTokens.value.size}")
                Log.d("TokenViewModel", "✅ Active list: ${_activeTokens.value.map { "${it.name}(${it.symbol})" }}")
                
                // بارگذاری قیمت‌ها برای توکن‌های فعال
                val currentActiveTokens = _activeTokens.value
                if (currentActiveTokens.isNotEmpty()) {
                    val selectedCurrency = context?.let { getSelectedCurrency(it) } ?: "USD"
                    fetchPrices(
                        activeSymbols = currentActiveTokens.map { it.symbol },
                        fiatCurrencies = listOf(selectedCurrency)
                    )
                }
                
            } catch (e: Exception) {
                Log.e("TokenViewModel", "❌ Error in synchronization: ${e.message}")
            }
        }
    }

    // Debug method to test balance fetching
    fun debugBalanceState() {
        Log.d("TokenViewModel", "🧪 === DEBUG BALANCE STATE ===")
        Log.d("TokenViewModel", "🧪 User ID: '$userId'")
        Log.d("TokenViewModel", "🧪 Context null: ${context == null}")
        Log.d("TokenViewModel", "🧪 Active tokens count: ${activeTokens.value.size}")
        Log.d("TokenViewModel", "🧪 Active tokens: ${activeTokens.value.map { "${it.symbol}(${it.amount})" }}")
        
        // Show current token amounts before API call
        Log.d("TokenViewModel", "🧪 === BEFORE API CALL ===")
        debugTokenAmounts()
        
        // Always test the direct API call regardless of conditions
        Log.d("TokenViewModel", "🧪 Testing direct API call...")
        testBalanceAPIDirectly()
        
        if (userId.isEmpty()) {
            Log.e("TokenViewModel", "🧪 ERROR: User ID is empty!")
            return
        }
        
        if (context == null) {
            Log.e("TokenViewModel", "🧪 ERROR: Context is null!")
            return
        }
        
        if (activeTokens.value.isEmpty()) {
            Log.w("TokenViewModel", "🧪 WARNING: No active tokens!")
        }
        
        Log.d("TokenViewModel", "🧪 Forcing regular balance fetch...")
        viewModelScope.launch {
            try {
                val balances = fetchBalancesForActiveTokens()
                Log.d("TokenViewModel", "🧪 Regular balance fetch result: $balances")
                
                // Show token amounts after API call
                Log.d("TokenViewModel", "🧪 === AFTER API CALL ===")
                debugTokenAmounts()
            } catch (e: Exception) {
                Log.e("TokenViewModel", "🧪 Regular balance fetch error: ${e.message}", e)
            }
        }
    }

    // Simple test method to bypass all conditions and test API directly
    fun testBalanceAPIDirectly() {
        viewModelScope.launch {
            try {
                Log.d("BalanceAPI", "🧪 === DIRECT API TEST ===")
                Log.d("BalanceAPI", "🧪 Testing balance API with hard-coded UserID")
                
                val request = BalanceRequest(
                    userId = "0d32dfd0-f7ba-4d5a-a408-75e6c2961e23", // Hard-coded working UserID
                    currencyNames = emptyList(),
                    blockchain = emptyMap()
                )
                
                Log.d("BalanceAPI", "🧪 Making direct API call...")
                val response = api.getBalance(request)
                
                Log.d("BalanceAPI", "🧪 === DIRECT API RESPONSE ===")
                Log.d("BalanceAPI", "🧪 Success: ${response.success}")
                Log.d("BalanceAPI", "🧪 UserID: ${response.UserID}")
                Log.d("BalanceAPI", "🧪 Balances count: ${response.balances?.size ?: 0}")
                Log.d("BalanceAPI", "🧪 Message: ${response.message}")
                
                response.balances?.forEach { balance ->
                    Log.d("BalanceAPI", "🧪 Balance: ${balance.symbol} = ${balance.balance} (${balance.blockchain})")
                }
                
                if (response.success && response.balances?.isNotEmpty() == true) {
                    Log.d("BalanceAPI", "🧪 ✅ DIRECT API TEST SUCCESSFUL!")
                    
                    // Now try to update tokens with the received balances
                    val balancesMap = response.balances?.associate { it.symbol to it.balance } ?: emptyMap()
                    Log.d("BalanceAPI", "🧪 Balances map: $balancesMap")
                    
                    // Try to update active tokens if any exist
                    if (activeTokens.value.isNotEmpty()) {
                        val updatedTokens = _activeTokens.value.map { token ->
                            val balance = balancesMap[token.symbol] ?: "0.0"
                            val balanceDouble = balance.toDoubleOrNull() ?: 0.0
                            Log.d("BalanceAPI", "🧪 Updating token ${token.symbol}: ${token.amount} -> $balanceDouble")
                            token.copy(amount = balanceDouble)
                        }
                        setActiveTokensForUser(updatedTokens)
                        Log.d("BalanceAPI", "🧪 ✅ Tokens updated with balances!")
                    } else {
                        Log.w("BalanceAPI", "🧪 ⚠️ No active tokens to update")
                    }
                } else {
                    Log.e("BalanceAPI", "🧪 ❌ DIRECT API TEST FAILED!")
                }
                
            } catch (e: Exception) {
                Log.e("BalanceAPI", "🧪 ❌ DIRECT API TEST EXCEPTION: ${e.message}", e)
            }
        }
    }

    // Function to debug current token amounts
    fun debugTokenAmounts() {
        Log.d("TokenViewModel", "🔍 === CURRENT TOKEN AMOUNTS DEBUG ===")
        
        Log.d("TokenViewModel", "🔍 Active Tokens (${activeTokens.value.size}):")
        activeTokens.value.forEachIndexed { index, token ->
            Log.d("TokenViewModel", "🔍   [$index] ${token.symbol} (${token.name}): amount=${token.amount}")
        }
        
        Log.d("TokenViewModel", "🔍 Currencies List (${currencies.size}):")
        currencies.take(10).forEachIndexed { index, token ->
            Log.d("TokenViewModel", "🔍   [$index] ${token.symbol} (${token.name}): amount=${token.amount}, enabled=${token.isEnabled}")
        }
        
        Log.d("TokenViewModel", "🔍 Active tokens state flow value:")
        Log.d("TokenViewModel", "🔍   _activeTokens.value.size = ${_activeTokens.value.size}")
        _activeTokens.value.forEach { token ->
            Log.d("TokenViewModel", "🔍   StateFlow: ${token.symbol} = ${token.amount}")
        }
    }

    // اضافه کردن تابع برای به‌روزرسانی UserId
    fun updateUserId(newUserId: String) {
        if (this.userId != newUserId) {
            Log.d("TokenViewModel", "🔄 Updating UserId from '${this.userId}' to '$newUserId'")
            this.userId = newUserId
            tokenPreferences = context?.let { TokenPreferences(it, newUserId) }
            // Reload tokens and balances for the new user
            viewModelScope.launch {
                try {
                    // Load user-specific tokens
                    val userSpecificTokens = _userTokens.value[newUserId]
                    if (userSpecificTokens != null) {
                        currencies = userSpecificTokens
                        setActiveTokensForUser(userSpecificTokens.filter { getTokenStateForUser(it) })
                    } else {
                        smartLoadTokens(true)
                    }

                    // Load user-specific balances
                    val userBalances = _userBalances.value[newUserId]
                    if (userBalances != null) {
                        currencies = currencies.map { token ->
                            val balance = userBalances[token.symbol] ?: "0.0"
                            val balanceDouble = balance.toDoubleOrNull() ?: 0.0
                            token.copy(amount = balanceDouble)
                        }
                        setActiveTokensForUser(_activeTokens.value.map { token ->
                            val balance = userBalances[token.symbol] ?: "0.0"
                            val balanceDouble = balance.toDoubleOrNull() ?: 0.0
                            token.copy(amount = balanceDouble)
                        })
                    } else {
                        fetchBalancesForActiveTokens()
                    }
                } catch (e: Exception) {
                    Log.e("TokenViewModel", "❌ Error updating user data: ${e.message}")
                }
            }
        }
    }

    // اضافه کردن متد برای ذخیره توکن‌های کاربر
    private fun saveUserTokens(userId: String, tokens: List<CryptoToken>) {
        val currentTokens = _userTokens.value.toMutableMap()
        currentTokens[userId] = tokens
        _userTokens.value = currentTokens
    }

    // اضافه کردن متد برای ذخیره موجودی‌های کاربر
    private fun saveUserBalances(userId: String, balances: Map<String, String>) {
        val currentBalances = _userBalances.value.toMutableMap()
        currentBalances[userId] = balances
        _userBalances.value = currentBalances
    }

    // اضافه کردن تابع برای دریافت UserId فعلی
    fun getCurrentUserId(): String = userId

    // Update token state management to be user-specific
    private fun getTokenStateForUser(token: CryptoToken): Boolean {
        return tokenPreferences?.getTokenState(
            token.symbol,
            token.BlockchainName,
            token.SmartContractAddress
        ) ?: false
    }

    private fun saveTokenStateForUser(token: CryptoToken, isEnabled: Boolean) {
        tokenPreferences?.saveTokenState(
            token.symbol,
            token.BlockchainName,
            token.SmartContractAddress,
            isEnabled
        )
    }

    // Helper to update active tokens and save for user
    private fun setActiveTokensForUser(tokens: List<CryptoToken>) {
        _activeTokens.value = tokens
        // Save in userTokens map for this user
        val currentTokens = _userTokens.value.toMutableMap()
        currentTokens[userId] = tokens
        _userTokens.value = currentTokens
    }
}
