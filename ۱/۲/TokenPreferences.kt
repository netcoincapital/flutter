package com.laxce.adl.utility

import android.content.Context
import android.content.SharedPreferences
import com.laxce.adl.classes.CryptoToken

class TokenPreferences(context: Context, userId: String) {
    private val sharedPreferences: SharedPreferences = context.getSharedPreferences("token_preferences_$userId", Context.MODE_PRIVATE)

    // Helper to generate unique key for each token (now includes SmartContractAddress)
    fun getTokenKey(token: CryptoToken): String {
        return "${token.symbol}_${token.BlockchainName}_${token.SmartContractAddress ?: ""}"
    }
    fun getTokenKey(symbol: String, blockchainName: String, contract: String?): String {
        return "${symbol}_${blockchainName}_${contract ?: ""}"
    }

    fun saveTokenOrder(tokenOrder: List<String>) {
        val orderString = tokenOrder.joinToString(",")
        sharedPreferences.edit().putString("token_order", orderString).apply()
    }

    fun getTokenOrder(): List<String> {
        val orderString = sharedPreferences.getString("token_order", "") ?: ""
        return if (orderString.isEmpty()) {
            emptyList()
        } else {
            orderString.split(",")
        }
    }

    fun saveTokenState(token: String, isEnabled: Boolean) {
        sharedPreferences.edit().putBoolean(token, isEnabled).apply()
    }
    fun saveTokenState(symbol: String, blockchainName: String, contract: String?, isEnabled: Boolean) {
        val key = getTokenKey(symbol, blockchainName, contract)
        sharedPreferences.edit().putBoolean(key, isEnabled).apply()
    }

    fun getTokenState(token: String): Boolean {
        return sharedPreferences.getBoolean(token, false)
    }
    fun getTokenState(symbol: String, blockchainName: String, contract: String?): Boolean {
        val key = getTokenKey(symbol, blockchainName, contract)
        return sharedPreferences.getBoolean(key, false)
    }

    fun getAllEnabledTokenKeys(): List<String> {
        return sharedPreferences.all
            .filter { it.value is Boolean && it.value as Boolean }
            .map { it.key }
    }

    fun getAllEnabledTokenNames(): List<String> {
        return sharedPreferences.all
            .filter { it.value is Boolean && it.value as Boolean }
            .map { it.key }
    }

    fun getAllEnabledTokens(allTokens: List<CryptoToken>): List<CryptoToken> {
        val enabledKeys = getAllEnabledTokenKeys()
        return allTokens.filter { token -> enabledKeys.contains(getTokenKey(token)) }
    }
} 
