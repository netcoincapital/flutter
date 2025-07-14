package com.laxce.adl.relatedfunctions

import android.util.Log
import com.laxce.adl.classes.CryptoToken
import com.laxce.adl.api.Api

suspend fun getCryptoTokenListFromApi(api: Api): List<CryptoToken> {
    return try {
        val response = api.getAllCurrencies()
        if (response.success) {
            response.currencies.map { currency ->
                CryptoToken(
                    name = currency.CurrencyName,
                    symbol = currency.Symbol,
                    BlockchainName = "${currency.BlockchainName}",
                    iconUrl = currency.Icon ?: "https://coinceeper.com/defualtIcons/coin.png",
                    isEnabled = false,
                    amount = 0.00,
                    isToken = currency.IsToken
                )
            }
        } else {
            emptyList()
        }
    } catch (e: Exception) {
        emptyList()
    }
}



