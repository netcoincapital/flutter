package com.laxce.adl.utility

import android.content.Context

fun loadWalletsFromKeystore(context: Context): List<Pair<String, String>> {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    val allEntries = sharedPreferences.all

    return allEntries.filter { it.key.startsWith("wallet_name_") }.map { entry ->
        val walletName = entry.value as String
        val walletAddress = sharedPreferences.getString("wallet_address_$walletName", "") ?: ""
        walletName to walletAddress
    }
}
