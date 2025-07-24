package com.laxce.adl

import android.app.Activity
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.laxce.adl.system.AdlTheme
import androidx.lifecycle.ViewModel
import com.google.zxing.integration.android.IntentIntegrator
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import java.util.concurrent.TimeUnit
import androidx.fragment.app.FragmentActivity
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import androidx.activity.viewModels
import com.laxce.adl.api.RetrofitClient
import retrofit2.Call
import retrofit2.Callback
import retrofit2.Response
import android.util.Log
import com.google.accompanist.systemuicontroller.rememberSystemUiController
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.ViewModelProvider
import androidx.navigation.NavController
import androidx.navigation.NavType
import androidx.navigation.navArgument
import com.laxce.adl.api.ImportWalletRequest
import com.laxce.adl.api.CreateWalletRequest
import com.laxce.adl.factories.TokenViewModelFactory
import com.laxce.adl.ui.theme.screen.AddTokenScreen
import com.laxce.adl.ui.theme.screen.CreateNewWalletScreen
import com.laxce.adl.ui.theme.screen.HomeScreen
import com.laxce.adl.ui.theme.screen.ImportWalletScreen
import com.laxce.adl.ui.theme.screen.NextScreen
import com.laxce.adl.ui.theme.screen.PasscodeScreen
import com.laxce.adl.ui.theme.screen.TokenDetailsScreen
import com.laxce.adl.viewmodel.token_view_model
import com.laxce.adl.ui.theme.screen.ReceiveScreen
import com.laxce.adl.ui.theme.screen.ReceiveWalletScreen
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat
import com.laxce.adl.api.GenerateWalletResponse
import com.laxce.adl.api.ImportWalletResponse
import com.laxce.adl.classes.CryptoToken
import com.laxce.adl.classes.LocaleChangeReceiver
import com.laxce.adl.classes.loadLanguage
import com.laxce.adl.security.KeystoreManager
import com.laxce.adl.ui.theme.screen.AddAddressScreen
import com.laxce.adl.ui.theme.screen.AddressBook
import com.laxce.adl.ui.theme.screen.BackupScreen
import com.laxce.adl.ui.theme.screen.CreateWalletScreen
import com.laxce.adl.ui.theme.screen.EditWalletScreen
import com.laxce.adl.ui.theme.screen.FiatCurrenciesScreen
import com.laxce.adl.ui.theme.screen.HistoryScreen
import com.laxce.adl.ui.theme.screen.InsideImportWalletScreen
import com.laxce.adl.ui.theme.screen.LanguageSettingsScreen
import com.laxce.adl.ui.theme.screen.PhraseKeyPasscodeScreen
import com.laxce.adl.ui.theme.screen.PhraseKeyScreen
import com.laxce.adl.ui.theme.screen.PreferencesScreen
import com.laxce.adl.ui.theme.screen.SecretPhraseScreen
import com.laxce.adl.ui.theme.screen.SecurityPasscodeScreen
import com.laxce.adl.ui.theme.screen.SecurityScreen
import com.laxce.adl.ui.theme.screen.SendDetailScreen
import com.laxce.adl.ui.theme.screen.WalletScreen
import com.laxce.adl.ui.theme.screen.WalletsScreen
import com.laxce.adl.ui.theme.screen.setAppLocale
import com.laxce.adl.utility.getWalletsFromKeystore
import com.laxce.adl.utility.saveUserWallet
import com.laxce.adl.ui.theme.screen.SettingScreen
import com.laxce.adl.ui.theme.screen.NotificationScreen
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.gson.Gson
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.cancelChildren
import com.laxce.adl.ui.theme.screen.SendScreen
import android.net.Uri
import com.laxce.adl.api.Api
import com.laxce.adl.ui.theme.screen.TransactionDetailScreen
import com.laxce.adl.ui.theme.screen.WebViewScreen
import com.laxce.adl.utility.DeviceRegistrationManager
import com.laxce.adl.viewmodel.NetworkViewModel
import com.laxce.adl.ui.theme.screen.NetworkErrorDialog
import com.laxce.adl.api.BalanceResponse
import com.laxce.adl.api.UpdateBalanceRequest
import com.laxce.adl.ui.theme.ai.AIScreen
import com.laxce.adl.ui.theme.ai.AIChatScreen
import com.laxce.adl.utility.NotificationHelper
import com.laxce.adl.utility.getUserIdFromKeystore as getCorrectUserId


class MainViewModel : ViewModel() {

    var scanResult by mutableStateOf<String?>(null)

    private val _walletName = mutableStateOf("")
    val walletName: String get() = _walletName.value

    fun choosePasscode(walletId: String) {
        Log.d("ChoosePasscode", "Navigating with WalletID: $walletId")
    }

    fun saveUserIdToKeystore(context: Context, walletName: String, userId: String) {
        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)

        // خواندن لیست فعلی کیف پول‌ها
        val walletsJson = sharedPreferences.getString("user_wallets", "[]") ?: "[]"
        val wallets = try {
            Gson().fromJson(walletsJson, ArrayList::class.java) as ArrayList<Map<String, String>>
        } catch (e: Exception) {
            ArrayList()
        }

        // حذف کیف پول قبلی با همین نام (اگر وجود داشت)
        wallets.removeIf { it["walletName"] == walletName }

        // اضافه کردن کیف پول جدید
        val newWallet = mapOf(
            "walletName" to walletName,
            "userId" to userId
        )
        wallets.add(newWallet)

        // ذخیره لیست به‌روزشده
        sharedPreferences.edit()
            .putString("user_wallets", Gson().toJson(wallets))
            .putString("selected_wallet", walletName) // برای سازگاری با کد قبلی
            .putString("UserID", userId)              // برای سازگاری با کد قبلی
            .apply()

        Log.d("Keystore", "Wallet saved - Name: $walletName, UserID: $userId")
        Log.d("Keystore", "Updated wallets list: ${Gson().toJson(wallets)}")
    }

    fun saveUserIdForWallet(context: Context, walletName: String, userId: String) {
        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        val key = "UserID_$walletName"
        sharedPreferences.edit().putString(key, userId).apply()

        val storedUserId = sharedPreferences.getString(key, "Not Found")
        Log.d("Keystore", "✅ After Save → UserID: $storedUserId")
    }

    fun saveMnemonicToKeystore(context: Context, mnemonic: String, userId: String, walletName: String) {
        val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
        val encryptedPrefs = EncryptedSharedPreferences.create(
            "encrypted_mnemonic_prefs",
            masterKeyAlias,
            context,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
        val key = "Mnemonic_${userId}_${walletName}"
        encryptedPrefs.edit().putString(key, mnemonic).apply()
        Log.d("saveMnemonicToKeystore", "[ENCRYPTED] Saved Mnemonic for UserId: $userId and WalletName: $walletName")
    }

    fun importWallet(
        context: Context,
        mnemonic: String,
        walletName: String,
        onSuccess: (ImportWalletResponse) -> Unit,
        onError: (Throwable) -> Unit
    ) {
        val TAG = "ImportWallet"
        Log.d(TAG, "Initiating wallet import. Wallet Name: $walletName")

        // برای ذخیره وضعیت APIها
        var updateBalanceSuccess = false
        var registerDeviceSuccess = false
        var importSuccess = false

        val request = ImportWalletRequest(mnemonic = mnemonic.trim())

        RetrofitClient.getInstance(context).create(Api::class.java).importWallet(request)
            .enqueue(object : Callback<ImportWalletResponse> {
                override fun onResponse(
                    call: Call<ImportWalletResponse>,
                    response: Response<ImportWalletResponse>
                ) {
                    Log.d(TAG, "Response received with HTTP status: ${response.code()}")
                    if (response.isSuccessful) {
                        val walletResponse = response.body()
                        Log.d(TAG, "Response body: $walletResponse")

                        if (walletResponse?.status == "success" ||
                            walletResponse?.message?.contains("successfully imported", ignoreCase = true) == true) {

                            val userId = walletResponse.data?.UserID
                            val receivedMnemonic = walletResponse.data?.Mnemonic
                            val walletId = walletResponse.data?.WalletID

                            if (userId != null && receivedMnemonic != null && walletId != null) {
                                saveUserIdToKeystore(context, walletName, userId)
                                saveUserWallet(context, userId, walletName)
                                saveMnemonicToKeystore(context, receivedMnemonic, userId, walletName)

                                importSuccess = true

                                // متغیرهایی برای هماهنگی بین APIها
                                val allApisDone = java.util.concurrent.CountDownLatch(2)

                                // Call update-balance API to send user balance to server
                                updateBalanceWithCheck(context, userId) { success ->
                                    updateBalanceSuccess = success
                                    allApisDone.countDown()
                                }

                                // Register device after delay
                                CoroutineScope(Dispatchers.IO).launch {
                                    delay(3000) // تأخیر 3 ثانیه قبل از ثبت دستگاه
                                    // Register device after successful wallet import
                                    registerDeviceWithCheck(context, userId, walletId) { success ->
                                        registerDeviceSuccess = success
                                        allApisDone.countDown()
                                    }
                                }

                                // منتظر اتمام هر دو API میمانیم
                                CoroutineScope(Dispatchers.IO).launch {
                                    val allApisFinished = allApisDone.await(30, java.util.concurrent.TimeUnit.SECONDS)

                                    withContext(Dispatchers.Main) {
                                        if (allApisFinished && updateBalanceSuccess && registerDeviceSuccess) {
                                            Log.d(TAG, "All APIs completed successfully")
                                            onSuccess(walletResponse)
                                        } else {
                                            var errorMessage = "فرآیند ناقص است. "
                                            if (!updateBalanceSuccess) errorMessage += "خطا در به‌روزرسانی موجودی. "
                                            if (!registerDeviceSuccess) errorMessage += "خطا در ثبت دستگاه. "
                                            if (!allApisFinished) errorMessage += "زمان انتظار برای تکمیل تمام شد. "

                                            Log.e(TAG, errorMessage)
                                            onError(Exception(errorMessage))
                                        }
                                    }
                                }
                            } else {
                                Log.e(TAG, "Incomplete data received: UserID=$userId, WalletID=$walletId, Mnemonic=${receivedMnemonic != null}")
                                onError(Exception("Incomplete data received from server"))
                            }

                        } else {
                            val errorMessage = walletResponse?.message ?: "Unknown error"
                            Log.e(TAG, "Wallet import failed with message: $errorMessage")
                            onError(Exception(errorMessage))
                        }
                    } else {
                        val errorBody = response.errorBody()?.string()
                        Log.e(TAG, "Unsuccessful response: HTTP ${response.code()}, Error: $errorBody")
                        onError(Exception("Response unsuccessful: ${response.code()}, Error: $errorBody"))
                    }
                }

                override fun onFailure(call: Call<ImportWalletResponse>, t: Throwable) {
                    Log.e(TAG, "Network failure during wallet import: ${t.message}", t)
                    onError(t)
                }
            })
    }

    // متد جدید برای چک کردن update balance با callback موفقیت
    private fun updateBalanceWithCheck(context: Context, userId: String, onResult: (Boolean) -> Unit) {
        val TAG = "UpdateBalance"
        Log.d(TAG, "1. Starting balance update process for UserID: $userId")

        val request = UpdateBalanceRequest(UserID = userId)
        Log.d(TAG, "2. Request data: $request")

        // استفاده از maxRetries برای تلاش‌های مجدد
        val maxRetries = 3
        var retryCount = 0

        // Use coroutine to make the API call
        CoroutineScope(Dispatchers.IO).launch {
            // تأخیر بیشتر برای اطمینان از آماده بودن سرور
            Log.d(TAG, "3. Waiting 5 seconds before sending update balance request")
            delay(5000)
            Log.d(TAG, "4. 5-second wait complete, proceeding with balance update")

            var lastError: Throwable? = null
            var success = false

            while (retryCount < maxRetries && !success) {
                try {
                    Log.d(TAG, "5. Attempt ${retryCount + 1} of $maxRetries to update balance")

                    val call = RetrofitClient.getInstance(context).create(Api::class.java)
                        .updateBalance(request)
                    Log.d(TAG, "6. Created API call for balance update")

                    val apiDoneLatch = java.util.concurrent.CountDownLatch(1)
                    Log.d(TAG, "7. Created CountDownLatch for API response")

                    call.enqueue(object : Callback<BalanceResponse> {
                        override fun onResponse(
                            call: Call<BalanceResponse>,
                            response: Response<BalanceResponse>
                        ) {
                            Log.d(TAG, "8. Received balance update response with code: ${response.code()}")
                            if (response.isSuccessful) {
                                val balanceResponse = response.body()
                                Log.d(TAG, "9. Response body: $balanceResponse")
                                if (balanceResponse?.success == true) {
                                    Log.d(TAG, "10. ✅ Balance update successful")
                                    success = true
                                } else {
                                    val msg = balanceResponse?.message ?: "Unknown error"
                                    Log.e(TAG, "11. ❌ Balance update failed: $msg")
                                    lastError = Exception(msg)
                                }
                            } else {
                                val errorMsg = "Failed with status code: ${response.code()}"
                                Log.e(TAG, "12. ❌ Balance update $errorMsg")
                                lastError = Exception(errorMsg)
                            }
                            Log.d(TAG, "13. Counting down API latch")
                            apiDoneLatch.countDown()
                        }

                        override fun onFailure(call: Call<BalanceResponse>, t: Throwable) {
                            Log.e(TAG, "14. Error updating balance: ${t.message}", t)
                            lastError = t
                            apiDoneLatch.countDown()
                        }
                    })

                    // منتظر تکمیل API می‌مانیم (با timeout)
                    Log.d(TAG, "15. Waiting up to 10 seconds for API response")
                    val apiCompleted = apiDoneLatch.await(10, java.util.concurrent.TimeUnit.SECONDS)
                    Log.d(TAG, "16. API wait completed: $apiCompleted, success: $success")

                    if (success) {
                        Log.d(TAG, "17. Balance update succeeded, exiting retry loop")
                        break
                    } else if (!apiCompleted) {
                        Log.e(TAG, "18. Update balance API timed out after 10 seconds")
                        lastError = Exception("API timeout")
                    }

                    // در صورت شکست، تلاش مجدد می‌کنیم
                    retryCount++
                    if (retryCount < maxRetries && !success) {
                        val delayTime = 2000L * retryCount // افزایش تأخیر در هر تلاش
                        Log.d(TAG, "19. Retrying update balance in $delayTime ms... (Attempt ${retryCount + 1}/$maxRetries)")
                        delay(delayTime)
                    }
                } catch (e: Exception) {
                    lastError = e
                    Log.e(TAG, "20. Exception during update balance attempt ${retryCount + 1}: ${e.message}", e)

                    retryCount++
                    if (retryCount < maxRetries && !success) {
                        val delayTime = 2000L * retryCount
                        Log.d(TAG, "21. Retrying update balance in $delayTime ms... (Attempt ${retryCount + 1}/$maxRetries)")
                        delay(delayTime)
                    }
                }
            }

            // پس از اتمام تلاش‌ها، نتیجه را اعلام می‌کنیم
            if (success) {
                Log.d(TAG, "22. Balance update completed successfully after ${retryCount + 1} attempts")
                onResult(true)
            } else {
                Log.e(TAG, "23. All update balance attempts failed (${retryCount + 1}/$maxRetries). Last error: ${lastError?.message}")
                onResult(false)
            }
        }
    }

    // متد جدید برای چک کردن registerDevice با callback موفقیت
    private fun registerDeviceWithCheck(context: Context, userId: String, walletId: String, onResult: (Boolean) -> Unit) {
        val TAG = "DeviceRegistration"
        Log.d(TAG, "1. Starting device registration process for UserID: $userId, WalletID: $walletId with check")

        // ایجاد یک flag برای نتیجه نهایی
        var registrationResult = false

        CoroutineScope(Dispatchers.IO).launch {
            try {
                // منتظر مشخص شدن نتیجه میمانیم
                Log.d(TAG, "2. Creating CountDownLatch for device registration")
                val resultLatch = java.util.concurrent.CountDownLatch(1)

                Log.d(TAG, "3. Initializing DeviceRegistrationManager")
                val deviceRegistrationManager = DeviceRegistrationManager(context)

                Log.d(TAG, "4. Calling registerDeviceWithCallback for UserID: $userId, WalletID: $walletId")
                deviceRegistrationManager.registerDeviceWithCallback(userId, walletId) { success ->
                    Log.d(TAG, "5. Received registration callback result: $success")
                    registrationResult = success
                    Log.d(TAG, "6. Counting down registration latch")
                    resultLatch.countDown()
                }

                // منتظر میمانیم تا عملیات تمام شود (حداکثر 20 ثانیه)
                Log.d(TAG, "7. Waiting up to 20 seconds for device registration to complete")
                val finished = resultLatch.await(20, java.util.concurrent.TimeUnit.SECONDS)
                Log.d(TAG, "8. Registration wait completed. Finished: $finished, Result: $registrationResult")

                // اگر به هر دلیلی تمام نشد، نتیجه منفی برمیگردانیم
                if (!finished) {
                    Log.e(TAG, "9. ERROR: Device registration timed out after 20 seconds")
                    onResult(false)
                } else {
                    Log.d(TAG, "10. Device registration process completed with result: $registrationResult")
                    onResult(registrationResult)
                }
            } catch (e: Exception) {
                Log.e(TAG, "11. ERROR: Exception in registerDeviceWithCheck: ${e.message}", e)
                onResult(false)
            }
        }
    }

    // متد اصلی برای ثبت دستگاه که قبلاً داشته‌ایم
    fun registerDeviceAfterWalletImport(context: Context, userId: String, walletId: String) {
        Log.d("DeviceRegistration", "Starting device registration process for UserID: $userId, WalletID: $walletId")
        val deviceRegistrationManager = DeviceRegistrationManager(context)
        CoroutineScope(Dispatchers.IO).launch {
            deviceRegistrationManager.registerDevice(userId, walletId)
        }
    }

    fun generateWallet(
        context: Context,
        walletName: String,
        onSuccess: (GenerateWalletResponse) -> Unit,
        onError: (Throwable) -> Unit
    ) {
        val TAG = "GenerateWallet"
        Log.d(TAG, "1. Starting wallet generation for walletName: $walletName")

        // برای ذخیره وضعیت APIها
        var updateBalanceSuccess = false
        var registerDeviceSuccess = false
        var generateSuccess = false

        val request = CreateWalletRequest(WalletName = walletName)
        Log.d(TAG, "2. Creating wallet request with data: $request")

        Log.d(TAG, "3. Sending wallet generation request to server...")
        RetrofitClient.getInstance(context).create(Api::class.java).generateWallet(request)
            .enqueue(object : Callback<GenerateWalletResponse> {
                override fun onResponse(
                    call: Call<GenerateWalletResponse>,
                    response: Response<GenerateWalletResponse>
                ) {
                    Log.d(TAG, "4. Received response with HTTP code: ${response.code()}")
                    if (response.isSuccessful) {
                        val walletResponse = response.body()
                        Log.d(TAG, "5. Response body received: $walletResponse")

                        if (walletResponse != null && walletResponse.success) {
                            val userId = walletResponse.UserID
                            val mnemonic = walletResponse.Mnemonic
                            val walletId = walletResponse.WalletID

                            Log.d(TAG, "6. Extracted UserID: $userId, Mnemonic: [REDACTED], WalletID: $walletId")

                            if (userId != null && mnemonic != null && walletId != null) {
                                Log.d(TAG, "7. Saving wallet data to keystore...")
                                saveUserIdToKeystore(context, walletName, userId)
                                saveUserWallet(context, userId, walletName)
                                saveMnemonicToKeystore(context, mnemonic, userId, walletName)
                                Log.d(TAG, "8. Wallet data saved successfully to keystore")

                                generateSuccess = true
                                Log.d(TAG, "9. Wallet generation successful, now proceeding with additional API calls")

                                // متغیرهایی برای هماهنگی بین APIها
                                val allApisDone = java.util.concurrent.CountDownLatch(2)
                                Log.d(TAG, "10. Created CountDownLatch for 2 API operations")

                                // Call update-balance API to send user balance to server
                                Log.d(TAG, "11. Starting balance update for UserID: $userId")
                                updateBalanceWithCheck(context, userId) { success ->
                                    Log.d(TAG, "12. Balance update result: $success")
                                    updateBalanceSuccess = success
                                    allApisDone.countDown()
                                    Log.d(TAG, "13. Balance update API completed, CountDownLatch count: ${allApisDone.count}")
                                }

                                // Register device after delay
                                CoroutineScope(Dispatchers.IO).launch {
                                    Log.d(TAG, "14. Waiting 3 seconds before device registration...")
                                    delay(3000) // تأخیر 3 ثانیه قبل از ثبت دستگاه
                                    Log.d(TAG, "15. Starting device registration for UserID: $userId, WalletID: $walletId")
                                    // Register device after successful wallet generation
                                    registerDeviceWithCheck(context, userId, walletId) { success ->
                                        Log.d(TAG, "16. Device registration result: $success")
                                        registerDeviceSuccess = success
                                        allApisDone.countDown()
                                        Log.d(TAG, "17. Device registration API completed, CountDownLatch count: ${allApisDone.count}")
                                    }
                                }

                                // منتظر اتمام هر دو API میمانیم
                                CoroutineScope(Dispatchers.IO).launch {
                                    Log.d(TAG, "18. Waiting for both APIs to complete (timeout: 30 seconds)")
                                    val allApisFinished = allApisDone.await(30, java.util.concurrent.TimeUnit.SECONDS)
                                    Log.d(TAG, "19. APIs wait completed. allApisFinished: $allApisFinished, updateBalanceSuccess: $updateBalanceSuccess, registerDeviceSuccess: $registerDeviceSuccess")

                                    withContext(Dispatchers.Main) {
                                        if (allApisFinished && updateBalanceSuccess && registerDeviceSuccess) {
                                            Log.d(TAG, "20. All APIs completed successfully - Process COMPLETE")
                                            onSuccess(walletResponse)
                                        } else {
                                            var errorMessage = "فرآیند ناقص است. "
                                            if (!updateBalanceSuccess) {
                                                errorMessage += "خطا در به‌روزرسانی موجودی. "
                                                Log.e(TAG, "21. Balance update failed")
                                            }
                                            if (!registerDeviceSuccess) {
                                                errorMessage += "خطا در ثبت دستگاه. "
                                                Log.e(TAG, "22. Device registration failed")
                                            }
                                            if (!allApisFinished) {
                                                errorMessage += "زمان انتظار برای تکمیل تمام شد. "
                                                Log.e(TAG, "23. APIs timeout - took longer than 30 seconds")
                                            }

                                            Log.e(TAG, "24. ERROR: $errorMessage")
                                            onError(Exception(errorMessage))
                                        }
                                    }
                                }
                            } else {
                                val missingFields = mutableListOf<String>()
                                if (userId == null) missingFields.add("UserID")
                                if (mnemonic == null) missingFields.add("Mnemonic")
                                if (walletId == null) missingFields.add("WalletID")

                                val errorMessage = "Incomplete data received: Missing ${missingFields.joinToString(", ")}"
                                Log.e(TAG, "25. ERROR: $errorMessage")
                                onError(Exception(errorMessage))
                            }
                        } else {
                            val errorMessage = walletResponse?.message ?: "Unknown error"
                            Log.e(TAG, "26. ERROR: Wallet generation failed with message: $errorMessage")
                            onError(Exception(errorMessage))
                        }
                    } else {
                        val errorBody = response.errorBody()?.string()
                        Log.e(TAG, "27. ERROR: Unsuccessful response received: HTTP ${response.code()}, Error body: $errorBody")
                        onError(Exception("Response unsuccessful: ${response.code()}, Error: $errorBody"))
                    }
                }

                override fun onFailure(call: Call<GenerateWalletResponse>, t: Throwable) {
                    Log.e(TAG, "28. ERROR: Network request failed with error: ${t.message}", t)
                    onError(t)
                }
            })
    }

    /**
     * Update user's balance via API call
     */
    private fun updateUserBalance(context: Context, userId: String) {
        val TAG = "UpdateBalance"
        Log.d(TAG, "Sending balance update request for UserID: $userId")

        val request = UpdateBalanceRequest(UserID = userId)

        // استفاده از maxRetries برای تلاش‌های مجدد
        val maxRetries = 3
        var retryCount = 0

        // Use coroutine to make the API call
        CoroutineScope(Dispatchers.IO).launch {
            // تأخیر بیشتر برای اطمینان از آماده بودن سرور
            Log.d(TAG, "Waiting 5 seconds before sending update balance request")
            delay(5000)

            var lastError: Throwable? = null
            while (retryCount < maxRetries) {
                try {
                    Log.d(TAG, "Attempt ${retryCount + 1} of $maxRetries to update balance")

                    val call = RetrofitClient.getInstance(context).create(Api::class.java)
                        .updateBalance(request)

                    var apiCallComplete = false
                    var apiSuccessful = false

                    // با استفاده از CountDownLatch اطمینان حاصل می‌کنیم که API کامل شود
                    val latch = java.util.concurrent.CountDownLatch(1)

                    call.enqueue(object : Callback<BalanceResponse> {
                        override fun onResponse(
                            call: Call<BalanceResponse>,
                            response: Response<BalanceResponse>
                        ) {
                            apiCallComplete = true
                            if (response.isSuccessful) {
                                val balanceResponse = response.body()
                                if (balanceResponse?.success == true) {
                                    apiSuccessful = true
                                    Log.d(TAG, "✅ Balance update successful")
                                } else {
                                    val msg = balanceResponse?.message ?: "Unknown error"
                                    Log.e(TAG, "❌ Balance update failed: $msg")
                                    lastError = Exception(msg)
                                }
                            } else {
                                val errorMsg = "Failed with status code: ${response.code()}"
                                Log.e(TAG, "❌ Balance update $errorMsg")
                                lastError = Exception(errorMsg)
                            }
                            latch.countDown()
                        }

                        override fun onFailure(call: Call<BalanceResponse>, t: Throwable) {
                            apiCallComplete = true
                            Log.e(TAG, "Error updating balance: ${t.message}", t)
                            lastError = t
                            latch.countDown()
                        }
                    })

                    // منتظر تکمیل API می‌مانیم (با timeout)
                    val apiCompleted = latch.await(10, java.util.concurrent.TimeUnit.SECONDS)

                    if (apiSuccessful) {
                        // در صورت موفقیت API، از حلقه خارج می‌شویم
                        Log.d(TAG, "Update balance API completed successfully")
                        break
                    } else if (!apiCallComplete || !apiCompleted) {
                        // اگر API به timeout خورده، خطا لاگ می‌کنیم
                        Log.e(TAG, "Update balance API timed out")
                        lastError = Exception("API timeout")
                    }

                    // در صورت شکست، تلاش مجدد می‌کنیم
                    retryCount++
                    if (retryCount < maxRetries) {
                        val delayTime = 2000L * retryCount // افزایش تأخیر در هر تلاش
                        Log.d(TAG, "Retrying update balance in $delayTime ms... (Attempt ${retryCount + 1}/$maxRetries)")
                        delay(delayTime)
                    }
                } catch (e: Exception) {
                    lastError = e
                    Log.e(TAG, "Exception during update balance attempt ${retryCount + 1}: ${e.message}", e)

                    retryCount++
                    if (retryCount < maxRetries) {
                        val delayTime = 2000L * retryCount
                        Log.d(TAG, "Retrying update balance in $delayTime ms... (Attempt ${retryCount + 1}/$maxRetries)")
                        delay(delayTime)
                    }
                }
            }

            // اگر تمام تلاش‌ها شکست خورد
            if (retryCount == maxRetries && lastError != null) {
                Log.e(TAG, "All update balance attempts failed. Last error: ")
            }
        }
    }

}

class MainActivity : FragmentActivity() {

    companion object {
        private const val REQUEST_CODE_POST_NOTIFICATIONS = 1
    }

    private val mainViewModel: MainViewModel by viewModels()
    private val qrScanLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val scanResult = IntentIntegrator.parseActivityResult(result.resultCode, result.data).contents
            mainViewModel.scanResult = scanResult
        }
    }

    private var isInitialNavigation = true
    private val mainScope = CoroutineScope(Dispatchers.Main + Job())
    private lateinit var tokenViewModel: token_view_model
    private var navController: NavController? = null
    var isQRScannerLaunched = false

    private val networkViewModel: NetworkViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // درخواست دسترسی نوتیفیکیشن برای اندروید 13 و بالاتر
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ActivityCompat.checkSelfPermission(
                    this,
                    android.Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                    1001
                )
            }
        }

        // تنظیم Firebase Messaging
        setupFirebaseMessaging()

        // مقداردهی اولیه tokenViewModel
        initializeTokenViewModel()

        // تعیین مسیر اولیه قبل از setContent
        val startDestination = determineStartDestination()

        setContent {
            val isOnline by networkViewModel.isOnline.collectAsState()
            AdlTheme {
                SystemUiColor()
                val navControllerInstance = rememberNavController()
                navController = navControllerInstance

                if (!isOnline) {
                    NetworkErrorDialog(
                        onDismiss = {
                            navControllerInstance.navigate("passcode") {
                                popUpTo(0)
                            }
                        }
                    )
                }

                NavHost(
                    navController = navControllerInstance,
                    startDestination = startDestination,
                    modifier = Modifier.fillMaxSize()
                ) {
                    // صفحه import-create
                    composable("import-create") {
                        // وقتی کیف پولی import/create شد، در همان صفحه (یا صفحه‌ی بعدی)
                        // mainViewModel.onImportOrCreateWalletComplete() را صدا بزنید.
                        NextScreen(navControllerInstance)
                    }

                    // نمونه‌هایی از سایر مسیرها:
                    composable(
                        route = "backup?walletName={walletName}",
                        arguments = listOf(
                            navArgument("walletName") {
                                type = NavType.StringType
                                defaultValue = ""
                                nullable = true
                            }
                        )
                    ) { entry ->
                        val walletName = entry.arguments?.getString("walletName")?.replace("%20", " ") ?: ""
                        Log.d("NavGraph", "Received walletName in backup: $walletName")
                        BackupScreen(
                            navController = navControllerInstance,
                            walletName = walletName
                        )
                    }

                    composable("security_passcode") { SecurityPasscodeScreen(navControllerInstance) }

                    composable("security") {
                        val initialLabel = when (timeoutInMillisState.value) {
                            0L -> "Immediate"
                            TimeUnit.MINUTES.toMillis(1) -> "1 min"
                            TimeUnit.MINUTES.toMillis(5) -> "5 min"
                            TimeUnit.MINUTES.toMillis(10) -> "10 min"
                            TimeUnit.MINUTES.toMillis(15) -> "15 min"
                            else -> "Immediate"
                        }

                        SecurityScreen(navControllerInstance, initialLabel) { label, timeout ->
                            timeoutInMillisState.value = timeout
                            saveTimeoutInMillis(this@MainActivity, timeout)
                        }
                    }

                    composable("addressbook") { AddressBook(navControllerInstance) }
                    composable("preferences") { PreferencesScreen(navControllerInstance) }
                    composable("fiat-currencies") { FiatCurrenciesScreen(navControllerInstance) }
                    composable("languages") {
                        LanguageSettingsScreen(context = this@MainActivity) { selectedLanguage ->
                            // هر تغییری که لازم است اعمال کنید (مثلاً ست کردن زبان جدید)
                            navControllerInstance.popBackStack()
                        }
                    }

                    composable("addaddress") { AddAddressScreen(navControllerInstance) }
                    composable("insideimportwallet") { InsideImportWalletScreen(navControllerInstance, mainViewModel) }

                    // صفحه ساخت کیف پول جدید
                    composable("create-new-wallet") {
                        CreateNewWalletScreen(navControllerInstance, mainViewModel)
                    }

                    // انتخاب پسکد
                    composable(
                        route = "choose-passcode?walletName={walletName}",
                        arguments = listOf(
                            navArgument("walletName") {
                                type = NavType.StringType
                                defaultValue = "DefaultWallet"
                                nullable = false
                            }
                        )
                    ) { entry ->
                        val walletName = entry.arguments?.getString("walletName")?.replace("%20", " ") ?: "DefaultWallet"
                        Log.d("NavGraph", "Received walletName in choose-passcode: $walletName")
                        PasscodeScreen(
                            navController = navControllerInstance,
                            title = "Choose Passcode",
                            walletName = walletName
                        )
                    }

                    // تایید پسکد
                    composable(
                        route = "confirm-passcode?walletName={walletName}",
                        arguments = listOf(
                            navArgument("walletName") {
                                type = NavType.StringType
                                defaultValue = "DefaultWallet"
                                nullable = false
                            }
                        )
                    ) { entry ->
                        val walletName = entry.arguments?.getString("walletName")?.replace("%20", " ") ?: "DefaultWallet"
                        Log.d("NavGraph", "Received walletName in confirm-passcode: $walletName")
                        PasscodeScreen(
                            navController = navControllerInstance,
                            title = "Confirm Passcode",
                            walletName = walletName
                        )
                    }

                    // صفحه ایمپورت کیف پول
                    composable("importWallet") { ImportWalletScreen(navControllerInstance, qrScanLauncher, mainViewModel) }

                    // صفحه خانه
                    composable("home") { ProvideTokenViewModel(navControllerInstance) }

                    // وقتی اپ لاک باشد و کاربر بخواهد ورود مجدد کند
                    composable("passcode") {
                        PasscodeScreen(navControllerInstance, title = "Enter Passcode")
                    }

                    composable(
                        route = "secret_phrase/{walletName}",
                        arguments = listOf(
                            navArgument("walletName") { type = NavType.StringType }
                        )
                    ) { backStackEntry ->
                        val walletName = backStackEntry.arguments?.getString("walletName") ?: ""
                        SecretPhraseScreen(navController = navControllerInstance, walletName = walletName)
                    }

                    // اضافه کردن توکن جدید
                    composable("addtoken") { AddTokenScreen(navControllerInstance, tokenViewModel) }
                    composable("sendscreen") { SendScreen(navController = navControllerInstance, tokenViewModel = tokenViewModel) }

                    // Add send_detail route to handle navigation from SendScreen
                    composable(
                        route = "send_detail/{tokenJson}",
                        arguments = listOf(
                            navArgument("tokenJson") { type = NavType.StringType }
                        )
                    ) { backStackEntry ->
                        val tokenJson = backStackEntry.arguments?.getString("tokenJson") ?: ""
                        val token = remember(tokenJson) {
                            try {
                                Gson().fromJson(Uri.decode(tokenJson), CryptoToken::class.java)
                            } catch (e: Exception) {
                                Log.e("SendDetail", "Error parsing token: ${e.message}")
                                null
                            }
                        }

                        if (token != null) {
                            SendDetailScreen(
                                navController = navControllerInstance,
                                token = token,
                                tokenViewModel = tokenViewModel
                            )
                        } else {
                            // Show error message if token parsing failed
                            Box(
                                modifier = Modifier.fillMaxSize().background(Color.White),
                                contentAlignment = androidx.compose.ui.Alignment.Center
                            ) {
                                Text(
                                    text = "Error loading token details",
                                    color = Color.Red,
                                    style = MaterialTheme.typography.h6,
                                    modifier = Modifier.padding(16.dp),
                                    textAlign = TextAlign.Center
                                )
                            }
                        }
                    }

                    // خانه‌ی اصلی
                    composable("home") { HomeScreen(navController = navControllerInstance, tokenViewModel = tokenViewModel) }
                    composable("notificationmanagement") { val context = LocalContext.current
                        NotificationScreen(navControllerInstance, context)
                    }
                    // صفحه جزئیات توکن
                    composable(
                        "tokendetails/{tokenName}/{tokenSymbol}/{iconUrl}/{gasFee}/{blockchainName}/{isToken}",
                        arguments = listOf(
                            navArgument("tokenName") { type = NavType.StringType },
                            navArgument("tokenSymbol") { type = NavType.StringType },
                            navArgument("iconUrl") { type = NavType.StringType },
                            navArgument("gasFee") { type = NavType.StringType },
                            navArgument("blockchainName") { type = NavType.StringType },
                            navArgument("isToken") { type = NavType.BoolType }
                        )
                    ) { backStackEntry ->

                        val tokenName = backStackEntry.arguments?.getString("tokenName") ?: "Unknown"
                        val tokenSymbol = backStackEntry.arguments?.getString("tokenSymbol") ?: "Unknown"
                        val iconUrl = backStackEntry.arguments?.getString("iconUrl") ?: "https://coinceeper.com/defualtIcons/coin.png"
                        val gasFee = backStackEntry.arguments?.getString("gasFee") ?: "0.0"
                        val blockchainName = backStackEntry.arguments?.getString("blockchainName") ?: "Unknown"
                        val isToken = backStackEntry.arguments?.getBoolean("isToken") ?: false

                        val token = CryptoToken(
                            name = tokenName,
                            symbol = tokenSymbol,
                            BlockchainName = blockchainName,
                            iconUrl = iconUrl,
                            isEnabled = true,
                            isToken = isToken
                        )


                        TokenDetailsScreen(
                            navController = navControllerInstance,
                            tokenName = tokenName,
                            tokenSymbol = tokenSymbol,
                            iconUrl = iconUrl,
                            gasFee = gasFee,
                            token = token
                        )
                    }

                    // صفحه‌ی دریافت
                    composable("receive") { ReceiveScreen(navControllerInstance) }
                    composable(
                        "receive_wallet/{cryptoName}/{blockchainName}/{userId}/{publicAddress}/{symbol}",
                        arguments = listOf (
                            navArgument("cryptoName") { type = NavType.StringType },
                            navArgument("blockchainName") { type = NavType.StringType },
                            navArgument("userId") { type = NavType.StringType },
                            navArgument("publicAddress") { type = NavType.StringType },
                            navArgument("symbol") { type = NavType.StringType }
                        )
                    ) { backStackEntry ->
                        val cryptoName = backStackEntry.arguments?.getString("cryptoName").orEmpty()
                        val blockchainName = backStackEntry.arguments?.getString("blockchainName").orEmpty()
                        val userId = backStackEntry.arguments?.getString("userId").orEmpty()
                        val publicAddress = backStackEntry.arguments?.getString("publicAddress").orEmpty()
                        val symbol = backStackEntry.arguments?.getString("symbol").orEmpty()

                        if (listOf(cryptoName, blockchainName, userId, publicAddress, symbol).all { it.isNotEmpty() }) {
                            ReceiveWalletScreen(
                                navController = navControllerInstance,
                                cryptoName = cryptoName,
                                blockchainName = blockchainName,
                                userId = userId,
                                publicAddress = publicAddress,
                                symbol = symbol // ارسال سیمبل
                            )
                        } else {
                            Text(
                                text = "Invalid data provided. Please try again.",
                                color = Color.Red,
                                style = MaterialTheme.typography.h6,
                                modifier = Modifier.fillMaxSize().background(Color.White).padding(16.dp),
                                textAlign = TextAlign.Center
                            )
                        }
                    }




                    composable("settings") { SettingScreen(navController = navControllerInstance) }

                    // صفحه لیست کیف پول‌ها
                    composable("wallets") {
                        val wallets = getWalletsFromKeystore(context = navControllerInstance.context).toMutableList()
                        WalletsScreen(navController = navControllerInstance, wallets = wallets)
                    }

                    // صفحه wallet
                    composable(
                        route = "wallet?walletName={walletName}",
                        arguments = listOf(
                            navArgument("walletName") {
                                type = NavType.StringType
                                defaultValue = ""
                                nullable = true
                            }
                        )
                    ) { entry ->
                        val walletName = entry.arguments?.getString("walletName")?.replace("%20", " ") ?: ""
                        Log.d("NavGraph", "Received walletName in wallet screen: $walletName")
                        WalletScreen(navController = navControllerInstance, walletName = walletName)
                    }

                    // صفحه تأیید عبارت بازیابی (Mnemonic)
                    composable(
                        "phrasekeyconfirmation/{walletName}",
                        arguments = listOf(navArgument("walletName") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val walletName = backStackEntry.arguments?.getString("walletName") ?: "Default Wallet"
                        SecretPhraseScreen(navController = navControllerInstance, walletName = walletName)
                    }

                    composable("history") {
                        HistoryScreen(navController = navControllerInstance)
                    }

                    // Transaction Detail Screen
                    composable(
                        route = "transaction_detail/{amount}/{tokenSymbol}/{fiatValue}/{date}/{status}/{sender}/{networkFee}/{transactionId}",
                        arguments = listOf(
                            navArgument("amount") { type = NavType.StringType },
                            navArgument("tokenSymbol") { type = NavType.StringType },
                            navArgument("fiatValue") { type = NavType.StringType },
                            navArgument("date") { type = NavType.StringType },
                            navArgument("status") { type = NavType.StringType },
                            navArgument("sender") { type = NavType.StringType },
                            navArgument("networkFee") { type = NavType.StringType },
                            navArgument("transactionId") {
                                type = NavType.StringType
                                defaultValue = ""
                            }
                        )
                    ) { backStackEntry ->
                        val amount = backStackEntry.arguments?.getString("amount") ?: "0"
                        val tokenSymbol = backStackEntry.arguments?.getString("tokenSymbol") ?: ""
                        val fiatValue = backStackEntry.arguments?.getString("fiatValue") ?: "$0.00"
                        val date = backStackEntry.arguments?.getString("date") ?: "Unknown"
                        val status = backStackEntry.arguments?.getString("status") ?: "Unknown"
                        val sender = backStackEntry.arguments?.getString("sender") ?: "Unknown"
                        val networkFee = backStackEntry.arguments?.getString("networkFee") ?: "0"
                        val transactionId = backStackEntry.arguments?.getString("transactionId") ?: ""

                        TransactionDetailScreen(
                            navController = navControllerInstance,
                            amount = amount,
                            tokenSymbol = tokenSymbol,
                            fiatValue = fiatValue,
                            date = date,
                            status = status,
                            sender = sender,
                            networkFee = networkFee,
                            transactionId = transactionId
                        )
                    }

                    // نمایش عبارت بازیابی
                    composable(
                        route = "phrasekey/{userId}/{walletName}?showCopy={showCopy}",
                        arguments = listOf(
                            navArgument("userId") { type = NavType.StringType },
                            navArgument("walletName") { type = NavType.StringType },
                            navArgument("showCopy") {
                                type = NavType.BoolType
                                defaultValue = false
                            }
                        )
                    ) { backStackEntry ->
                        val userId = backStackEntry.arguments?.getString("userId") ?: ""
                        val walletName = backStackEntry.arguments?.getString("walletName")?.replace("%20", " ") ?: ""
                        val showCopy = backStackEntry.arguments?.getBoolean("showCopy") ?: false

                        Log.d("Navigation", "PhraseKey: userId=$userId, walletName=$walletName, showCopy=$showCopy")
                        PhraseKeyScreen(
                            navController = navControllerInstance,
                            walletName = walletName,
                            showCopy = showCopy
                        )
                    }

                    // صفحه‌ی ساخت کیف پول درونی
                    composable("insidenewwallet") {
                        CreateWalletScreen(navController = navControllerInstance, mainViewModel = mainViewModel)
                    }

                    // صفحه‌ی ویرایش کیف پول
                    composable(
                        route = "editWallet/{walletName}/{walletAddress}",
                        arguments = listOf(
                            navArgument("walletName") { type = NavType.StringType },
                            navArgument("walletAddress") { type = NavType.StringType },
                        )
                    ) { backStackEntry ->
                        val walletName = backStackEntry.arguments?.getString("walletName") ?: ""
                        val walletAddress = backStackEntry.arguments?.getString("walletAddress") ?: ""

                        EditWalletScreen(
                            navController = navControllerInstance,
                            walletName = walletName,
                            walletAddress = walletAddress
                        )
                    }

                    // صفحه phrase key passcode
                    composable(
                        route = "phrasekeypasscode/{walletName}?showCopy={showCopy}",
                        arguments = listOf(
                            navArgument("walletName") {
                                type = NavType.StringType
                                nullable = true
                            },
                            navArgument("showCopy") {
                                type = NavType.BoolType
                                defaultValue = false
                            }
                        )
                    ) { entry ->
                        val walletName = entry.arguments?.getString("walletName")?.replace("%20", " ") ?: ""
                        val showCopy = entry.arguments?.getBoolean("showCopy") ?: false
                        PhraseKeyPasscodeScreen(
                            navController = navControllerInstance,
                            title = "Enter Phrase Key Passcode",
                            walletName = walletName,
                            showCopy = showCopy
                        )
                    }

                    // اضافه کردن صفحه WebView برای باز کردن لینک‌ها در درون برنامه
                    composable(
                        route = "web_view/{url}",
                        arguments = listOf(
                            navArgument("url") { type = NavType.StringType }
                        )
                    ) { backStackEntry ->
                        val encodedUrl = backStackEntry.arguments?.getString("url") ?: ""
                        val decodedUrl = Uri.decode(encodedUrl)
                        WebViewScreen(navController = navControllerInstance, url = decodedUrl)
                    }

                    // صفحه AI
                    composable("ai") { AIScreen(navControllerInstance) }
                    // صفحه AI Chat
                    composable("aichat") { AIChatScreen(navControllerInstance) }
                }

                LaunchedEffect(Unit) {
                    if (isInitialNavigation) {
                        isInitialNavigation = false
                        navControllerInstance.navigate(startDestination) {
                            popUpTo(0) { inclusive = true }
                            launchSingleTop = true
                        }
                    }
                }

                ObserveLifecycle(
                    onEnterBackground = {
                        mainScope.launch(Dispatchers.IO) {
                            if (!isQRScannerLaunched) {
                                lastBackgroundTime = System.currentTimeMillis()
                                saveLastBackgroundTime(this@MainActivity, lastBackgroundTime)
                            }
                        }
                    },
                    onEnterForeground = { skipPasscode ->
                        if (!skipPasscode && !isInitialNavigation && !isQRScannerLaunched) {
                            mainScope.launch(Dispatchers.IO) {
                                withContext(Dispatchers.Main) {
                                    navController?.navigate("passcode") {
                                        popUpTo(navController?.graph?.startDestinationId ?: 0) {
                                            saveState = true
                                        }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                }
                            }
                        }
                        isQRScannerLaunched = false
                    }
                )
            }
        }
    }

    // تغییر به تابع غیر suspend برای اجرای سریع در زمان شروع
    private fun determineStartDestination(): String {
        val hasUserId = checkUserIdStoredSync()
        val hasPasscode = checkPasscodeStoredSync()

        val destination = when {
            !hasUserId && !hasPasscode -> "import-create"
            hasUserId && !hasPasscode -> "choose-passcode"
            hasUserId && hasPasscode -> "passcode"
            else -> "import-create"
        }

        Log.d("Navigation", "Initial destination: $destination")
        return destination
    }

    // توابع sync برای بررسی سریع در شروع برنامه
    private fun checkUserIdStoredSync(): Boolean {
        val sharedPreferences = getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        val userId = sharedPreferences.getString("UserID", null)
        Log.d("Keystore", "Checking UserID: $userId")
        return !userId.isNullOrEmpty()
    }

    private fun checkPasscodeStoredSync(): Boolean {
        val sharedPreferences = getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        val passcode = sharedPreferences.getString("Passcode", null)
        Log.d("Keystore", "Checking Passcode: ${passcode != null}")
        return !passcode.isNullOrEmpty()
    }

    override fun onDestroy() {
        super.onDestroy()
        mainScope.coroutineContext.cancelChildren()
    }

    private fun initializeSettings() {
        // تنظیمات نوتیفیکیشن
        val notificationHelper = NotificationHelper(this)
        notificationHelper.createNotificationChannels()
        handleNotificationPermissions(notificationHelper)

        // تست API
        testApiCall()

        // تنظیمات Keystore
        setupKeystore()

        // تنظیمات زمان‌بندی
        timeoutInMillisState.value = getTimeoutInMillis(this)
        val (initialLabel, initialTimeout) = getAutoLockOption(this)
        timeoutInMillisState.value = initialTimeout

        // تنظیمات زبان
        val savedLanguage = loadLanguage(this)
        setAppLocale(this, savedLanguage)

        // ثبت BroadcastReceiver
        registerLocaleReceiver()

        // مقداردهی TokenViewModel
        initializeTokenViewModel()
    }

    private fun handleNotificationPermissions(notificationHelper: NotificationHelper) {
        if (Build.VERSION.SDK_INT >= 33) {
            val permission = "android.permission.POST_NOTIFICATIONS"
            if (ActivityCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(permission), REQUEST_CODE_POST_NOTIFICATIONS)
            } else {
                notificationHelper.showWelcomeNotification()
            }
        } else {
            notificationHelper.showWelcomeNotification()
        }
    }

    private fun setupKeystore() {
        val keystoreManager = KeystoreManager()
        if (keystoreManager.containsAlias("your_key_alias")) {
            keystoreManager.deleteKey("your_key_alias")
        }
        keystoreManager.generateKey("your_key_alias")
    }

    private fun registerLocaleReceiver() {
        val localeChangeReceiver = LocaleChangeReceiver()
        val filter = IntentFilter("com.wallet.crypto.coinceeper.LOCALE_CHANGED")
        registerReceiver(localeChangeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
    }

    private fun initializeTokenViewModel() {
        val walletName = loadSelectedWallet(this)
        val userId = getCorrectUserId(this, walletName)
        Log.d("MainActivity", "🔧 Initializing TokenViewModel with walletName: '$walletName', userId: '$userId'")
        tokenViewModel = ViewModelProvider(
            this,
            TokenViewModelFactory(applicationContext, userId)
        )[token_view_model::class.java]
        
        // اگر userId موجود است، آن را به tokenViewModel پاس کنیم
        if (userId.isNotEmpty()) {
            Log.d("MainActivity", "🔧 Updating TokenViewModel with correct userId: '$userId'")
            tokenViewModel.updateUserId(userId)
        }
    }

    // تابع جدید برای بروزرسانی userId در tokenViewModel
    fun updateTokenViewModelUserId() {
        val walletName = loadSelectedWallet(this)
        val userId = getCorrectUserId(this, walletName)
        Log.d("MainActivity", "🔄 Refreshing TokenViewModel userId. WalletName: '$walletName', UserId: '$userId'")
        
        if (userId.isNotEmpty() && ::tokenViewModel.isInitialized) {
            tokenViewModel.updateUserId(userId)
        } else {
            Log.w("MainActivity", "⚠️ Cannot update tokenViewModel - userId empty or tokenViewModel not initialized")
        }
    }

    private fun getMasterKey(): String {
        return MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
    }

    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "login_channel_id"
            val channelName = "Login Notifications"
            val channelDescription = "Notifications for user login"

            val importance = NotificationManager.IMPORTANCE_DEFAULT
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = channelDescription
            }

            val notificationManager: NotificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    @Composable
    fun ProvideTokenViewModel(navController: NavController) {
        HomeScreen(navController, tokenViewModel)
    }

    @Composable
    fun SystemUiColor() {
        val systemUiController = rememberSystemUiController()
        val statusBarColor = Color(0xFF1CCAA0) // رنگ سازمانی دلخواه

        LaunchedEffect(Unit) {
            systemUiController.setStatusBarColor(
                color = statusBarColor,
                darkIcons = true // در صورت نیاز به آیکون‌های تیره
            )
        }
    }

    @Composable
    fun ObserveLifecycle(
        onEnterBackground: () -> Unit,
        onEnterForeground: (Boolean) -> Unit
    ) {
        val lifecycleOwner = LocalLifecycleOwner.current
        val context = LocalContext.current
        DisposableEffect(lifecycleOwner) {
            val observer = LifecycleEventObserver { _, event ->
                when (event) {
                    Lifecycle.Event.ON_STOP -> {
                        // ذخیره زمان خروج از اپلیکیشن
                        onEnterBackground()
                    }
                    Lifecycle.Event.ON_START -> {
                        // بازیابی تنظیمات قفل خودکار
                        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
                        val timeoutInMillis = sharedPreferences.getLong("timeout_in_millis", 0L)
                        val lastBackgroundTime = sharedPreferences.getLong("last_background_time", 0L)
                        val currentTime = System.currentTimeMillis()

                        val hasUserId = sharedPreferences.getString("UserID", null) != null
                        if (!hasUserId) {
                            Log.d("ObserveLifecycle", "No UserID found, skipping AutoLock checks")
                            return@LifecycleEventObserver
                        }

                        if (timeoutInMillis == 0L) {
                            onEnterForeground(false)
                        } else if (currentTime - lastBackgroundTime <= timeoutInMillis) {
                            onEnterForeground(true)
                        } else {
                            onEnterForeground(false)
                        }
                    }
                    else -> {}
                }
            }
            lifecycleOwner.lifecycle.addObserver(observer)
            onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
        }
    }

    private fun loadSelectedWallet(context: Context): String {
        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        return sharedPreferences.getString("selected_wallet", "Unknown Wallet") ?: "Unknown Wallet"
    }

    private var lastBackgroundTime = 0L
    private val timeoutInMillisState = mutableStateOf(0L)
    private fun saveTimeoutInMillis(context: Context, timeoutInMillis: Long) {
        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        sharedPreferences.edit().putLong("timeout_in_millis", timeoutInMillis).apply()
    }
    private fun getTimeoutInMillis(context: Context): Long {
        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        return sharedPreferences.getLong("timeout_in_millis", TimeUnit.SECONDS.toMillis(5)) // مقدار پیش‌فرض 5 ثانیه
    }
    private fun saveAutoLockOption(context: Context, label: String, timeoutInMillis: Long) {
        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        sharedPreferences.edit()
            .putString("auto_lock_option", label)
            .putLong("timeout_in_millis", timeoutInMillis)
            .apply()
        Log.d("AutoLock", "Saved AutoLock Option: Label=$label, Timeout=$timeoutInMillis")
    }
    private fun getAutoLockOption(context: Context): Pair<String, Long> {
        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        val label = sharedPreferences.getString("auto_lock_option", "Immediate") ?: "Immediate"
        val timeout = sharedPreferences.getLong("timeout_in_millis", 0L)
        Log.d("AutoLock", "Loaded AutoLock Option: Label=$label, Timeout=$timeout")
        return label to timeout
    }
    private fun saveLastBackgroundTime(context: Context, timestamp: Long) {
        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        sharedPreferences.edit()
            .putLong("last_background_time", timestamp)
            .apply()
    }
    private fun getLastBackgroundTime(context: Context): Long {
        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        return sharedPreferences.getLong("last_background_time", 0L) // مقدار پیش‌فرض 0
    }

    fun testApiCall() {
        val client = OkHttpClient()

        val requestBody = """
        {
            "WalletName": "New 1"
        }
    """.trimIndent().toRequestBody("application/json".toMediaType())

        val request = Request.Builder()
            .url("https://coinceeper.com/api/generate-wallet")
            .post(requestBody)
            .addHeader("Content-Type", "application/json")
            .build()

        Thread {
            try {
                val response = client.newCall(request).execute()
                Log.d("API_CALL", "Response: ${response.code}, Body: ${response.body?.string()}")
            } catch (e: Exception) {
                Log.e("API_CALL", "Error: ${e.message}")
            }
        }.start()
    }

    override fun onResume() {
        super.onResume()

        val sharedPreferences = getSharedPreferences("qr_scan", MODE_PRIVATE)
        val scanResult = sharedPreferences.getString("last_scan_result", null)
        val returnScreen = sharedPreferences.getString("return_screen", null)

        if (scanResult != null && returnScreen != null) {
            sharedPreferences.edit().clear().apply()

            navController?.let { nav ->
                when (returnScreen) {
                    "settings" -> {
                        nav.navigate("settings") {
                            popUpTo("settings") { inclusive = true }
                        }
                    }
                    "import_wallet" -> {
                        nav.navigate("import_wallet") {
                            popUpTo("import_wallet") { inclusive = true }
                        }
                    }
                    "home" -> {
                        // اگر از صفحه home اسکن شده باشد
                        nav.navigate("sendscreen/$scanResult") {
                            popUpTo("home") { inclusive = false }
                        }
                    }
                }
            }
        }
    }

    private fun setupFirebaseMessaging() {
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                val token = task.result
                Log.d("FCM", "Token: $token")

                // ثبت دستگاه در سرور
                val sharedPreferences = getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
                val userId = sharedPreferences.getString("UserID", null)
                val walletId = sharedPreferences.getString("WalletID", null)

                if (userId != null && walletId != null) {
                    val deviceRegistrationManager = DeviceRegistrationManager(this)
                    CoroutineScope(Dispatchers.IO).launch {
                        deviceRegistrationManager.registerDevice(userId, walletId)
                    }
                }
            } else {
                Log.e("FCM", "Fetching FCM registration token failed", task.exception)
            }
        }
    }

    // اضافه کردن متد برای بررسی و ثبت مجدد دستگاه
    fun checkDeviceRegistration() {
        val sharedPreferences = getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        val userId = sharedPreferences.getString("UserID", null)
        val walletId = sharedPreferences.getString("WalletID", null)

        if (userId != null && walletId != null) {
            val deviceRegistrationManager = DeviceRegistrationManager(this)
            CoroutineScope(Dispatchers.IO).launch {
                deviceRegistrationManager.checkAndRegisterDevice(userId, walletId)
            }
        }
    }

}
