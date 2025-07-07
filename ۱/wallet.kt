package com.laxce.adl.ui.theme.screen

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Icon
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.R
import androidx.compose.material.*
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import com.laxce.adl.api.Wallet
import com.laxce.adl.ui.theme.layout.MainLayout
import com.laxce.adl.utility.getUserIdFromKeystore
import com.laxce.adl.utility.getWalletsFromKeystore
import com.laxce.adl.utility.saveSelectedWallet
import com.google.gson.Gson
import java.net.URLEncoder
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys


@Composable
fun WalletScreen(navController: NavController, walletName: String) {
    if (walletName.isEmpty()) {
        return
    }
    val context = LocalContext.current
    val initialWalletName = walletName
    var walletName by remember { mutableStateOf(initialWalletName) }
    var showDeleteDialog by remember { mutableStateOf(false) }
    var wallets = remember { getWalletsFromKeystore(context) }
    val savedWalletName = remember { getWalletNameFromKeystore(context, walletName) }

    MainLayout(navController = navController) {
        Column(modifier = Modifier.fillMaxSize().background(Color.White)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp),
                verticalArrangement = Arrangement.Top,
                horizontalAlignment = Alignment.Start
            ) {
                // نوار بالایی با گزینه ذخیره و حذف
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween // توزیع آیتم‌ها بین چپ و راست
                ) {
                    // متن Wallet در سمت چپ
                    Text(
                        text = "Wallet",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.Black
                    )

                    // آیکون حذف و گزینه Save در سمت راست
                    Row(
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        IconButton(onClick = { showDeleteDialog = true }) { // نمایش مودال هنگام کلیک
                            Icon(
                                painter = painterResource(id = R.drawable.recycle_bin), // آیکون حذف
                                contentDescription = "Delete",
                                tint = Color.Black,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                        TextButton(onClick = {
                            val trimmedWalletName = walletName.trim()
                            val trimmedInitialWalletName = initialWalletName.trim() // مقدار اولیه هم تریم شود
                            if (trimmedWalletName != trimmedInitialWalletName) {
                                val userId = getUserIdFromKeystore(context, trimmedInitialWalletName)
                                // به‌روزرسانی mnemonic با نام جدید کیف پول
                                updateMnemonicForWalletName(context, userId, trimmedInitialWalletName, trimmedWalletName)
                                saveWalletNameToKeystore(
                                    context = context,
                                    userId = userId,
                                    oldWalletName = trimmedInitialWalletName,
                                    newWalletName = trimmedWalletName,
                                    navController = navController
                                )
                            } else {
                            }
                        }) {
                            Text(
                                text = "Save",
                                fontSize = 14.sp,
                                color = Color(0xFF2AC079)
                            )
                        }

                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                Text(text = "Name", fontSize = 14.sp, color = Color.Gray)
                OutlinedTextField(
                    value = walletName,
                    onValueChange = { newValue ->
                        walletName = newValue.trim() // حذف فاصله‌های اضافی
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp),
                    singleLine = true,
                    colors = TextFieldDefaults.outlinedTextFieldColors(
                        cursorColor = Color(0xFF39b6fb),
                        focusedBorderColor = Color(0xFF16B369),
                        unfocusedBorderColor = Color.Gray
                    )
                )



                Spacer(modifier = Modifier.height(16.dp))

                // گزینه‌های Backup
                Text(
                    text = "Secret phrase backups",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.Black,
                    modifier = Modifier.padding(bottom = 8.dp) // فاصله بین عنوان و گزینه‌های بعدی
                )

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            val encodedWalletName = URLEncoder.encode(walletName, "UTF-8").replace("+", "%20")
                            navController.navigate("phrasekeypasscode/$encodedWalletName?showCopy=false")
                        }
                        .padding(vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            painter = painterResource(id = R.drawable.hold),
                            contentDescription = "Manual Backup",
                            tint = Color.Black,
                            modifier = Modifier.size(28.dp)
                        )
                        Spacer(modifier = Modifier.width(16.dp))
                        Text(
                            text = "Manual",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.Black
                        )
                    }
                    Text(
                        text = "Active",
                        fontSize = 14.sp,
                        color = Color.Gray,
                        modifier = Modifier.padding(end = 8.dp)
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp)
                        .background(color = Color(0xFFFFF4E5), shape = RoundedCornerShape(8.dp)) // پس‌زمینه نارنجی با گوشه‌های گرد
                        .padding(16.dp) // فاصله داخلی
                ) {
                    Text(
                        text = "We highly recommend completing both backup options to help prevent the loss of your crypto.",
                        fontSize = 14.sp,
                        color = Color(0xFFE68A00), // رنگ متن قهوه‌ای (هماهنگ با هشدار)
                        textAlign = TextAlign.Start // متن به سمت چپ تنظیم شود
                    )
                }

            }
            // نمایش مودال حذف
            if (showDeleteDialog) {
                AlertDialog(
                    onDismissRequest = { showDeleteDialog = false },
                    title = { Text(text = "Delete Wallet") },
                    text = { Text(text = "Are you sure you want to delete this wallet? This action cannot be undone.") },
                    confirmButton = {
                        TextButton(
                            onClick = {
                                showDeleteDialog = false
                                deleteWallet(context, walletName, navController, wallets.toMutableList()) // تبدیل به MutableList
                            }

                        ) {
                            Text("Delete", color = Color.Red)
                        }
                    },
                    dismissButton = {
                        TextButton(
                            onClick = { showDeleteDialog = false }
                        ) {
                            Text("Cancel", color = Color(0xFFBDBDBD))
                        }
                    }
                )
            }
        }
    }
}

fun saveWalletNameToKeystore(
    context: Context,
    userId: String,
    oldWalletName: String,
    newWalletName: String,
    navController: NavController
) {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    val gson = Gson()

    // خواندن لیست کیف پول‌ها
    val walletsJson = sharedPreferences.getString("user_wallets", "[]") ?: "[]"
    val wallets = gson.fromJson(walletsJson, ArrayList::class.java) as ArrayList<Map<String, String>>

    // به‌روزرسانی نام کیف پول
    val updatedWallets = wallets.map { wallet ->
        if (wallet["userId"] == userId && wallet["walletName"] == oldWalletName) {
            wallet.toMutableMap().apply {
                this["walletName"] = newWalletName
            }
        } else wallet
    }

    // ذخیره تغییرات
    sharedPreferences.edit()
        .putString("user_wallets", gson.toJson(updatedWallets))
        .putString("selected_wallet", newWalletName) // به‌روزرسانی نام کیف پول انتخاب‌شده
        .apply()

    // به‌روزرسانی mnemonic با نام جدید کیف پول
    updateMnemonicForWalletName(context, userId, oldWalletName, newWalletName)

    // بازگشت به صفحه کیف پول‌ها
    navController.navigate("wallets") {
        popUpTo("wallets") { inclusive = true }
    }
}

// تابع جدید برای به‌روزرسانی mnemonic با نام جدید کیف پول
fun updateMnemonicForWalletName(context: Context, userId: String, oldWalletName: String, newWalletName: String) {
    try {
        val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
        val encryptedPrefs = EncryptedSharedPreferences.create(
            "encrypted_mnemonic_prefs",
            masterKeyAlias,
            context,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
        
        val oldKey = "Mnemonic_${userId}_${oldWalletName}"
        val newKey = "Mnemonic_${userId}_${newWalletName}"
        
        // خواندن mnemonic با کلید قدیمی
        val mnemonic = encryptedPrefs.getString(oldKey, null)
        
        if (mnemonic != null) {
            // ذخیره mnemonic با کلید جدید
            encryptedPrefs.edit().putString(newKey, mnemonic).apply()
            
            // حذف کلید قدیمی
            encryptedPrefs.edit().remove(oldKey).apply()
            
            android.util.Log.d("WalletNameUpdate", "Successfully updated mnemonic for wallet: $oldWalletName -> $newWalletName")
        } else {
            android.util.Log.w("WalletNameUpdate", "No mnemonic found for old wallet name: $oldWalletName")
        }
    } catch (e: Exception) {
        android.util.Log.e("WalletNameUpdate", "Error updating mnemonic: ${e.message}")
    }
}





fun getWalletNameFromKeystore(context: Context, walletName: String): String {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    return sharedPreferences.getString("selected_wallet", walletName).orEmpty()
}



fun deleteWallet(context: Context, walletName: String, navController: NavController, wallets: MutableList<Wallet>) {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    val gson = Gson()

    // حذف کیف پول از Keystore
    val dataJson = sharedPreferences.getString("user_wallets", "[]") ?: "[]"
    val currentData = gson.fromJson(dataJson, ArrayList::class.java) as ArrayList<Map<String, String>>
    val updatedData = currentData.filterNot { it["walletName"] == walletName }
    sharedPreferences.edit().putString("user_wallets", gson.toJson(updatedData)).apply()

    // حذف کیف پول انتخاب‌شده
    sharedPreferences.edit().remove("selected_wallet").apply()
    sharedPreferences.edit().remove("selected_user_id").apply()

    // به‌روزرسانی لیست محلی
    wallets.removeAll { it.WalletName == walletName }

    if (updatedData.isNotEmpty()) {
        val newWallet = updatedData.first()
        val newWalletName = newWallet["walletName"] ?: "Unknown Wallet"
        val newUserId = newWallet["userId"] ?: "Unknown UserID"
        saveSelectedWallet(context, newWalletName, newUserId)
        navController.navigate("wallets") {
            popUpTo("wallets") { inclusive = true }
        }
    } else {
        // هیچ کیف پولی باقی نمانده است
        navController.navigate("import-create") {
            popUpTo("wallets") { inclusive = true }
        }
    }
}

