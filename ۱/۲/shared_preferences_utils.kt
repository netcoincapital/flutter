package com.laxce.adl.utility

import android.content.Context
import android.content.SharedPreferences
import android.net.ConnectivityManager
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import com.laxce.adl.api.Api
import com.laxce.adl.api.PriceData
import com.laxce.adl.api.PricesRequest
import com.laxce.adl.api.RetrofitClient
import com.google.gson.Gson
import android.util.Log


private fun isInternetAvailable(context: Context): Boolean {
    val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    val networkInfo = connectivityManager.activeNetworkInfo
    return networkInfo != null && networkInfo.isConnected
}

fun getEncryptedSharedPreferences(context: Context): SharedPreferences {
    return try {
        EncryptedSharedPreferences.create(
            "passcode_prefs",
            MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC),
            context,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    } catch (e: Exception) {
        resetEncryptedPreferences(context)
        context.getSharedPreferences("passcode_prefs", Context.MODE_PRIVATE)
    }
}

fun reloadPrices(context: Context): Map<String, Map<String, String>> {
    val sharedPreferences = context.getSharedPreferences("token_prices", Context.MODE_PRIVATE)
    val allPrices = sharedPreferences.all
    val pricesMap = mutableMapOf<String, Map<String, String>>()

    allPrices.forEach { (key, value) ->
        val parts = key.split("-")
        if (parts.size == 2) {
            val symbol = parts[0]
            val currency = parts[1]
            val price = value.toString()

            pricesMap[symbol] = pricesMap.getOrDefault(symbol, mutableMapOf()).toMutableMap().apply {
                this[currency] = price
            }
        }
    }
    return pricesMap
}

fun loadPriceFromKeystore(context: Context, symbol: String, currency: String): Double {
    val sharedPreferences = context.getSharedPreferences("token_prices", Context.MODE_PRIVATE)
    val key = "$symbol-$currency"

    // مقدار پیش‌فرض 0.0
    return sharedPreferences.getString(key, "0.0")?.toDoubleOrNull() ?: 0.0
}

suspend fun fetchPricesWithCache(
    context: Context,
    gson: Gson,
    selectedCurrency: String,
    activeSymbols: List<String>,
    fiatCurrencies: List<String>
    ): Map<String, Map<String, String>> {

    var sanitizedSymbols = activeSymbols.map { it.uppercase() }

    if (sanitizedSymbols.isEmpty()) {
        val sharedPreferences = context.getSharedPreferences("token_prefs", Context.MODE_PRIVATE)
        sanitizedSymbols = sharedPreferences.all.keys
            .filter { it.startsWith("token_") && it.endsWith("_enabled") && sharedPreferences.getBoolean(it, false) }
            .map { it.replace("token_", "").replace("_enabled", "").uppercase() }
    }

    // دریافت API و UserID
    val api = RetrofitClient.getInstance(context).create(Api::class.java)
    val userId = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        .getString("UserID", "") ?: ""


    if (sanitizedSymbols.isEmpty()) {
        return emptyMap()
    }

    // Map symbols to match the API request format with full names
    val apiSymbols = sanitizedSymbols.map { 
        when (it) {
            "BTC" -> "bitcoin"
            "ETH" -> "ethereum" 
            "TRX" -> "tron"
            "BNB" -> "BNB"
            "SHIB" -> "shiba inu"
            else -> it.lowercase()
        }
    }

    // ساخت درخواست
    val request = PricesRequest(
        Symbol = apiSymbols,
        FiatCurrencies = fiatCurrencies // لیست همه ارزها
    )

    return try {
        val response = api.getPrices(request)

        if (response.success) {
            val prices: Map<String, Map<String, PriceData>> = response.prices ?: emptyMap()

            // Map the returned keys back to the expected format if needed
            val mappedPrices = mutableMapOf<String, Map<String, PriceData>>()
            prices.forEach { (key, value) ->
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

            // بررسی مقدار `null` برای جلوگیری از کرش
            val safePrices: Map<String, Map<String, PriceData>> = mappedPrices.mapValues { (_, currencyMap) ->
                currencyMap.mapValues { (_, priceData) ->
                    priceData ?: PriceData(price = "0.0", change_24h = "+0.0%")
                }
            }

            // ذخیره قیمت‌ها در کش
            context.getSharedPreferences("token_prices", Context.MODE_PRIVATE).edit()
                .putString("cached_prices", gson.toJson(safePrices))
                .putLong("price_cache_timestamp", System.currentTimeMillis())
                .apply()

            // ذخیره قیمت‌های هر توکن به صورت جداگانه برای سازگاری با کد قدیمی
            val sharedPreferences = context.getSharedPreferences("token_prices", Context.MODE_PRIVATE)
            val editor = sharedPreferences.edit()
            
            safePrices.forEach { (symbol, currencyMap) ->
                currencyMap.forEach { (currency, priceData) ->
                    editor.putString("$symbol-$currency-price", priceData.price)
                    editor.putString("$symbol-$currency-change", priceData.change_24h)
                }
            }
            editor.apply()

            // بازگرداندن قیمت‌ها به فرمت قابل استفاده در token_view_model
            return safePrices.mapValues { (_, currencyMap) ->
                currencyMap.mapValues { (_, priceData) ->
                    priceData.price // فقط قیمت را برمی‌گردانیم
                }
            }

        } else {
            return emptyMap()
        }
    } catch (e: Exception) {
        return emptyMap()
    }
}



//fun formatPrice(price: String, selectedCurrency: String): String {
//    val currencySymbol = getCurrencySymbol(selectedCurrency)
//    return try {
//        val sanitizedPrice = price.replace("", "")
//        val value = sanitizedPrice.toBigDecimal()
//        when {
//            value >= "1".toBigDecimal() -> {
//                "$currencySymbol${value.setScale(2, java.math.RoundingMode.DOWN).toPlainString()}"
//            }
//            value >= "0.01".toBigDecimal() -> {
//                "$currencySymbol${value.setScale(4, java.math.RoundingMode.DOWN).toPlainString()}"
//            }
//            else -> {
//                val formatted = value.setScale(10, java.math.RoundingMode.DOWN).toPlainString()
//                val nonZeroIndex = formatted.indexOfFirst { it != '0' && it != '.' }
//                if (nonZeroIndex > 3) {
//                    "$currencySymbol${formatted.substring(0, nonZeroIndex + 4)}"
//                } else {
//                    "$currencySymbol${formatted.trimEnd('0').trimEnd('.')}"
//                }
//            }
//        }
//    } catch (e: Exception) {
//        "$currencySymbol$price" // در صورت خطا مقدار اصلی بازگردانده شود
//    }
//}

fun resetEncryptedPreferences(context: Context) {
    val prefs = context.getSharedPreferences("passcode_prefs", Context.MODE_PRIVATE)
    prefs.edit().clear().apply()
}


fun getUserIdFromKeystore(context: Context, walletName: String): String {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    val walletsJson = sharedPreferences.getString("user_wallets", "[]") ?: "[]"
    val wallets = try {
        Gson().fromJson(walletsJson, ArrayList::class.java) as ArrayList<Map<String, String>>
    } catch (e: Exception) {
        ArrayList()
    }

    val wallet = wallets.find { it["walletName"] == walletName }
    val userId = wallet?.get("userId") ?: ""

    if (userId.isEmpty()) {
        // اگر در فرمت جدید پیدا نشد، سعی کنید از فرمت قدیمی بخوانید
        val legacyUserId = sharedPreferences.getString("UserID", "")
        if (!legacyUserId.isNullOrEmpty()) {
            return legacyUserId
        }
    } else {
    }

    return userId
}

fun getMnemonicFromKeystore(context: Context, userId: String, walletName: String): String? {
    val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
    val encryptedPrefs = EncryptedSharedPreferences.create(
        "encrypted_mnemonic_prefs",
        masterKeyAlias,
        context,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )
    
    // ابتدا سعی می‌کنیم با نام فعلی کیف پول پیدا کنیم
    val currentKey = "Mnemonic_${userId}_${walletName}"
    var mnemonic = encryptedPrefs.getString(currentKey, null)
    
    // اگر پیدا نشد، سعی می‌کنیم با نام‌های مختلف پیدا کنیم
    if (mnemonic == null) {
        val allEntries = encryptedPrefs.all
        val targetUserId = userId
        
        // جستجو در تمام کلیدهای mnemonic برای یافتن کلید مناسب
        for ((key, value) in allEntries) {
            if (key.startsWith("Mnemonic_${targetUserId}_") && value is String && value.isNotEmpty()) {
                // بررسی می‌کنیم که آیا این کلید مربوط به همین کیف پول است یا نه
                // با استفاده از userId و بررسی اینکه آیا این کلید با نام‌های مختلف ذخیره شده
                mnemonic = value
                break
            }
        }
    }
    
    return mnemonic
}

fun saveSelectedCurrency(context: Context, currency: String) {
    val sharedPreferences = context.getSharedPreferences("app_preferences", Context.MODE_PRIVATE)
    sharedPreferences.edit().putString("selected_currency", currency).apply()
}

fun getSelectedCurrency(context: Context): String {
    val sharedPreferences = context.getSharedPreferences("app_preferences", Context.MODE_PRIVATE)
    return sharedPreferences.getString("selected_currency", "USD") ?: "USD"
}


fun getCurrencySymbol(currency: String): String {
    return when (currency) {
        "USD" -> "$"       // دلار آمریکا
        "CAD" -> "CA$"     // دلار کانادا
        "AUD" -> "AU$"     // دلار استرالیا
        "GBP" -> "£"       // پوند بریتانیا
        "EUR" -> "€"       // یورو
        "KWD" -> "KD"      // دینار کویت
        "TRY" -> "₺"       // لیر ترکیه
        "IRR" -> "﷼"       // ریال ایران
        "SAR" -> "﷼"       // ریال عربستان
        "CNY" -> "¥"       // یوآن چین
        "KRW" -> "₩"       // وون کره جنوبی
        "JPY" -> "¥"       // ین ژاپن
        "INR" -> "₹"       // روپیه هند
        "RUB" -> "₽"       // روبل روسیه
        "IQD" -> "ع.د"     // دینار عراق
        "TND" -> "د.ت"     // دینار تونس
        "BHD" -> "ب.د"     // دینار بحرین
        "ZAR" -> "R"       // راند آفریقای جنوبی
        "CHF" -> "CHF"     // فرانک سوئیس
        "NZD" -> "NZ$"     // دلار نیوزیلند
        "SGD" -> "S$"      // دلار سنگاپور
        "HKD" -> "HK$"     // دلار هنگ‌کنگ
        "MXN" -> "MX$"     // پزو مکزیک
        "BRL" -> "R$"      // رئال برزیل
        "SEK" -> "kr"      // کرون سوئد
        "NOK" -> "kr"      // کرون نروژ
        "DKK" -> "kr"      // کرون دانمارک
        "PLN" -> "zł"      // زلوتی لهستان
        "CZK" -> "Kč"      // کرون چک
        "HUF" -> "Ft"      // فورینت مجارستان
        "ILS" -> "₪"       // شِکِل جدید اسرائیل
        "MYR" -> "RM"      // رینگیت مالزی
        "THB" -> "฿"       // بات تایلند
        "PHP" -> "₱"       // پزو فیلیپین
        "IDR" -> "Rp"      // روپیه اندونزی
        "EGP" -> "£"       // پوند مصر
        "PKR" -> "₨"       // روپیه پاکستان
        "NGN" -> "₦"       // نایرا نیجریه
        "VND" -> "₫"       // دونگ ویتنام
        "BDT" -> "৳"       // تاکا بنگلادش
        "LKR" -> "Rs"      // روپیه سریلانکا
        "UAH" -> "₴"       // گریونا اوکراین
        "KZT" -> "₸"       // تنگه قزاقستان
        "XAF" -> "FCFA"    // فرانک آفریقای مرکزی
        "XOF" -> "CFA"     // فرانک آفریقای غربی
        else -> ""         // پیش‌فرض: رشته خالی
    }
}



// Extension function for formatting double values
fun Double.format(digits: Int): String {
    val safeDigits = digits.coerceIn(0, 10) // محدود کردن digits بین 0 و 10
    return "%.${safeDigits}f".format(this)
}

fun formatAmount(amount: Double, price: Double): String {
    if (amount == 0.0) return "0"

    // برای مقادیر خیلی کوچک، تعداد رقم اعشار بیشتری نیاز داریم
    val formatted = when {
        // برای مقادیر کمتر از 0.001 (مثل 0.00012)، حداقل 6 رقم اعشار
        amount < 0.001 -> String.format("%.8f", amount)
        // برای مقادیر کمتر از 0.1، حداقل 4 رقم اعشار  
        amount < 0.1 -> String.format("%.6f", amount)
        // برای مقادیر کمتر از 1، 4 رقم اعشار
        amount < 1.0 -> String.format("%.4f", amount)
        // برای مقادیر کمتر از 10، 3 رقم اعشار
        amount < 10.0 -> String.format("%.3f", amount)
        // برای مقادیر بزرگتر، 2 رقم اعشار
        else -> String.format("%.2f", amount)
    }

    // حذف صفرهای اضافی از انتها
    return formatted.trimEnd('0').trimEnd('.')
}

fun formatPrice(price: Double?, symbol: String): String {
    if (price == null || price.isNaN() || price == 0.0) return "0"

    return when {
        symbol == "BTC" || symbol == "ETH" -> String.format("%,.2f", price)
        price < 0.01 -> String.format("%.8f", price)
        price < 1 -> String.format("%.4f", price)
        else -> String.format("%.2f", price)
    }
}
