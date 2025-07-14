package com.laxce.adl.utility

import android.content.Context
import com.laxce.adl.api.Wallet
import com.google.gson.Gson



fun saveUserWallet(context: Context, userId: String, walletName: String) {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    val walletsJson = sharedPreferences.getString("user_wallets", "[]") ?: "[]"
    val wallets = Gson().fromJson(walletsJson, ArrayList::class.java) as ArrayList<Map<String, String>>

    // حذف کیف پول با همان نام در صورت وجود
    wallets.removeAll { it["walletName"] == walletName }

    // افزودن کیف پول جدید
    wallets.add(mapOf("userId" to userId, "walletName" to walletName))

    // ذخیره‌سازی لیست به‌روز شده
    sharedPreferences.edit()
        .putString("user_wallets", Gson().toJson(wallets))
        .apply()
}





fun getWalletsFromKeystore(context: Context): MutableList<Wallet> {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    val gson = Gson()
    val dataJson = sharedPreferences.getString("user_wallets", "[]") ?: "[]"
    val data = gson.fromJson(dataJson, ArrayList::class.java) as ArrayList<Map<String, String>>
    return data.map { entry ->
        Wallet(
            WalletName = entry["walletName"] ?: "Unknown Wallet",
            UserID = entry["userId"] ?: "Unknown UserID"
        )
    }.toMutableList()
}



fun saveSelectedWallet(context: Context, walletName: String, userId: String) {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    sharedPreferences.edit()
        .putString("selected_wallet", walletName)
        .putString("selected_user_id", userId)
        .apply()
}


fun loadSelectedWallet(context: Context): String {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    return sharedPreferences.getString("selected_wallet", "").orEmpty()
}

fun getUserIdForSelectedWallet(context: Context): Pair<String, String?> {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    val selectedWallet = loadSelectedWallet(context)
    val userId = sharedPreferences.getString("selected_user_id", null)
    return Pair(selectedWallet, userId)
}

fun saveToKeystore(context: Context, walletName: String) {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    val existingWallets = sharedPreferences.getStringSet("wallets", mutableSetOf()) ?: mutableSetOf()
    existingWallets.add(walletName)
    sharedPreferences.edit().putStringSet("wallets", existingWallets).apply()

}
