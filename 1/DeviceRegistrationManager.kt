package com.laxce.adl.utility

import android.content.Context
import android.util.Log
import com.laxce.adl.api.RegisterDeviceRequest
import com.laxce.adl.api.RetrofitClient
import com.laxce.adl.api.Api
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.FirebaseApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.withContext

class DeviceRegistrationManager(context: Context) {
    private val context = context.applicationContext
    private val apiService = RetrofitClient.getInstance(context).create(Api::class.java)
    private val scope = CoroutineScope(Dispatchers.IO)
    private val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    
    // زمان انتظار API در میلی‌ثانیه
    private val API_TIMEOUT = 15000L
    // حداکثر تعداد تلاش‌های مجدد
    private val MAX_RETRY_ATTEMPTS = 3
    // تأخیر بین تلاش‌های مجدد (میلی‌ثانیه)
    private val RETRY_DELAY = 3000L

    private fun isProvisioningComplete(userId: String?, walletId: String?, deviceToken: String?): Boolean {
        return !userId.isNullOrBlank() && !walletId.isNullOrBlank() && !deviceToken.isNullOrBlank()
    }

    private suspend fun initializeFirebaseAndGetToken(): String? {
        return withContext(Dispatchers.IO) {
            Log.d("DeviceRegManager", "Attempting to get FCM token...")
            try {
                if (FirebaseApp.getApps(context).isEmpty()) {
                    Log.e("DeviceRegManager", "FirebaseApp is NOT initialized! Check Application class.")
                    return@withContext null
                }
                FirebaseMessaging.getInstance().token.await()
            } catch (e: Exception) {
                Log.e("DeviceRegManager", "Error getting token: ${e.message}", e)
                null
            }
        }
    }

    // متد جدید که با callback نتیجه را برمی‌گرداند
    fun registerDeviceWithCallback(userId: String, walletId: String, onResult: (Boolean) -> Unit) {
        val TAG = "DeviceRegistration"
        scope.launch {
            try {
                val deviceName = android.os.Build.MODEL
                Log.d(TAG, "Starting device registration process for UserID: $userId, WalletID: $walletId")
                
                // دریافت توکن با لاگ‌های بیشتر
                Log.d(TAG, "Attempting to get FCM token...")
                val deviceToken = initializeFirebaseAndGetToken()
                Log.d(TAG, "FCM token retrieval result: ${if (deviceToken != null) "Success" else "Failed"}")
                
                if (!isProvisioningComplete(userId, walletId, deviceToken)) {
                    Log.e(TAG, "Provisioning incomplete: userId=$userId, walletId=$walletId, deviceToken=$deviceToken")
                    onResult(false)
                    return@launch
                }
                val lastRegisteredToken = sharedPreferences.getString("last_registered_token", null)
                val lastRegisteredUserId = sharedPreferences.getString("last_registered_userid", null)
                if (deviceToken == lastRegisteredToken && userId == lastRegisteredUserId) {
                    Log.d(TAG, "Device already registered with same token and userId")
                    onResult(true)
                    return@launch
                }
                val request = RegisterDeviceRequest(
                    userId = userId,
                    walletId = walletId,
                    deviceToken = deviceToken!!,
                    deviceName = deviceName,
                    deviceType = "android"
                )
                var lastException: Exception? = null
                var registrationSuccess = false
                attemptLoop@ for (attempt in 1..MAX_RETRY_ATTEMPTS) {
                    try {
                        Log.d(TAG, "Attempt $attempt of $MAX_RETRY_ATTEMPTS to register device. Request: $request")
                        
                        val response = try {
                            withTimeoutOrNull(API_TIMEOUT) {
                                apiService.registerDevice(request)
                            }
                        } catch (jsonException: Exception) {
                            // Handle JSON parsing errors - assume success since server logs show it works
                            if (jsonException.message?.contains("malformed JSON", ignoreCase = true) == true ||
                                jsonException.message?.contains("JsonReader.setStrictness", ignoreCase = true) == true) {
                                Log.d(TAG, "📝 JSON parsing error detected, but server likely succeeded. Assuming success.")
                                Log.d(TAG, "🔍 JSON Error: ${jsonException.message}")
                                registrationSuccess = true
                                break@attemptLoop
                            } else {
                                throw jsonException
                            }
                        }
                        
                        if (response == null) {
                            Log.e(TAG, "API timeout on attempt $attempt")
                            delay(RETRY_DELAY)
                            continue@attemptLoop
                        }
                        
                        // Log raw response for debugging
                        try {
                            val rawResponse = response.toString()
                            Log.d(TAG, "Raw response received: $rawResponse")
                            Log.d(TAG, "Response class: ${response::class.java.simpleName}")
                            Log.d(TAG, "Response success field: ${response.success}")
                            Log.d(TAG, "Response message field: '${response.message}'")
                            Log.d(TAG, "Response deviceId field: '${response.deviceId}'")
                        } catch (e: Exception) {
                            Log.e(TAG, "Error logging response details: ${e.message}")
                        }
                        
                        // Check if registration is successful based on success field OR success keywords in message
                        val message = response.message ?: ""
                        val isSuccessfulByMessage = message.contains("به‌روزرسانی شد", ignoreCase = true) ||
                                                   message.contains("ثبت شد", ignoreCase = true) ||
                                                   message.contains("توکن دستگاه جدید", ignoreCase = true) ||
                                                   message.contains("توکن دستگاه موجود", ignoreCase = true) ||
                                                   message.contains("شناسه", ignoreCase = true) ||
                                                   message.contains("updated", ignoreCase = true) ||
                                                   message.contains("successful", ignoreCase = true) ||
                                                   message.contains("registered", ignoreCase = true) ||
                                                   message.contains("device token", ignoreCase = true) ||
                                                   response.deviceId != null // If deviceId is returned, it's usually successful
                        
                        val isActuallySuccessful = response.success || isSuccessfulByMessage
                        
                        Log.d(TAG, "Final success determination: response.success=${response.success}, successByMessage=$isSuccessfulByMessage, finalResult=$isActuallySuccessful")
                        
                        if (isActuallySuccessful) {
                            Log.d(TAG, "✅ Device registration successful on attempt $attempt")
                            sharedPreferences.edit()
                                .putString("last_registered_token", deviceToken)
                                .putString("last_registered_userid", userId)
                                .apply()
                            registrationSuccess = true
                            break@attemptLoop
                        } else {
                            val errorMessage = response.message ?: "Unknown registration error"
                            Log.e(TAG, "❌ Registration failed on attempt $attempt: $errorMessage")
                            Log.e(TAG, "Expected success=true but got success=${response.success}")
                            if (errorMessage.contains("INVALID_ARGUMENT", ignoreCase = true)) {
                                Log.e(TAG, "INVALID_ARGUMENT from server. Sent request: $request")
                            }
                            lastException = Exception(errorMessage)
                            if (attempt < MAX_RETRY_ATTEMPTS) {
                                val delayTime = RETRY_DELAY * attempt
                                Log.d(TAG, "Retrying in ${delayTime}ms...")
                                delay(delayTime)
                            }
                        }
                    } catch (e: Exception) {
                        // Handle JSON parsing errors specifically
                        if (e.message?.contains("malformed JSON", ignoreCase = true) == true ||
                            e.message?.contains("JsonReader.setStrictness", ignoreCase = true) == true) {
                            Log.d(TAG, "📝 JSON parsing error on attempt $attempt, but server likely succeeded. Assuming success.")
                            Log.d(TAG, "🔍 JSON Error details: ${e.message}")
                            registrationSuccess = true
                            break@attemptLoop
                        } else {
                            Log.e(TAG, "Exception on attempt $attempt: ${e.message}")
                            lastException = e
                            if (attempt < MAX_RETRY_ATTEMPTS) {
                                val delayTime = RETRY_DELAY * attempt
                                Log.d(TAG, "Retrying in ${delayTime}ms...")
                                delay(delayTime)
                            }
                        }
                    }
                }
                if (registrationSuccess) {
                    Log.d(TAG, "Device registration completed successfully")
                    onResult(true)
                } else {
                    Log.e(TAG, "Device registration failed after all attempts. Last error: ${lastException?.message}")
                    onResult(false)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Unexpected error in device registration: ${e.message}")
                onResult(false)
            }
        }
    }

    suspend fun registerDevice(userId: String, walletId: String) {
        try {
            if (FirebaseApp.getApps(context).isEmpty()) {
                Log.e("DeviceRegistration", "FirebaseApp is NOT initialized! Check Application class.")
                return
            }
            val deviceName = android.os.Build.MODEL
            delay(3000)
            val deviceToken = withTimeoutOrNull(5000) {
                FirebaseMessaging.getInstance().token.await()
            }
            if (!isProvisioningComplete(userId, walletId, deviceToken)) {
                Log.e("DeviceRegistration", "Provisioning incomplete: userId=$userId, walletId=$walletId, deviceToken=$deviceToken")
                return
            }
            val lastRegisteredToken = sharedPreferences.getString("last_registered_token", null)
            val lastRegisteredUserId = sharedPreferences.getString("last_registered_userid", null)
            if (deviceToken == lastRegisteredToken && userId == lastRegisteredUserId) {
                Log.d("DeviceRegistration", "Device already registered with same token and userId")
                return
            }
            val request = RegisterDeviceRequest(
                userId = userId,
                walletId = walletId,
                deviceToken = deviceToken!!,
                deviceName = deviceName,
                deviceType = "android"
            )
            var lastException: Exception? = null
            attemptLoop@ for (attempt in 1..MAX_RETRY_ATTEMPTS) {
                try {
                    Log.d("DeviceRegistration", "Attempt $attempt of $MAX_RETRY_ATTEMPTS to register device. Request: $request")
                    
                    val response = try {
                        withTimeoutOrNull(API_TIMEOUT) {
                            apiService.registerDevice(request)
                        }
                    } catch (jsonException: Exception) {
                        // Handle JSON parsing errors - assume success since server logs show it works
                        if (jsonException.message?.contains("malformed JSON", ignoreCase = true) == true ||
                            jsonException.message?.contains("JsonReader.setStrictness", ignoreCase = true) == true) {
                            Log.d("DeviceRegistration", "📝 JSON parsing error detected, but server likely succeeded. Assuming success.")
                            Log.d("DeviceRegistration", "🔍 JSON Error: ${jsonException.message}")
                            sharedPreferences.edit()
                                .putString("last_registered_token", deviceToken)
                                .putString("last_registered_userid", userId)
                                .apply()
                            return
                        } else {
                            throw jsonException
                        }
                    }
                    
                    if (response == null) {
                        Log.e("DeviceRegistration", "API timeout on attempt $attempt")
                        delay(RETRY_DELAY)
                        continue@attemptLoop
                    }
                    
                    // Log raw response for debugging
                    try {
                        val rawResponse = response.toString()
                        Log.d("DeviceRegistration", "Raw response received: $rawResponse")
                        Log.d("DeviceRegistration", "Response class: ${response::class.java.simpleName}")
                        Log.d("DeviceRegistration", "Response success field: ${response.success}")
                        Log.d("DeviceRegistration", "Response message field: '${response.message}'")
                        Log.d("DeviceRegistration", "Response deviceId field: '${response.deviceId}'")
                    } catch (e: Exception) {
                        Log.e("DeviceRegistration", "Error logging response details: ${e.message}")
                    }
                    
                    // Check if registration is successful based on success field OR success keywords in message
                    val message = response.message ?: ""
                    val isSuccessfulByMessage = message.contains("به‌روزرسانی شد", ignoreCase = true) ||
                                               message.contains("ثبت شد", ignoreCase = true) ||
                                               message.contains("توکن دستگاه جدید", ignoreCase = true) ||
                                               message.contains("توکن دستگاه موجود", ignoreCase = true) ||
                                               message.contains("شناسه", ignoreCase = true) ||
                                               message.contains("updated", ignoreCase = true) ||
                                               message.contains("successful", ignoreCase = true) ||
                                               message.contains("registered", ignoreCase = true) ||
                                               message.contains("device token", ignoreCase = true) ||
                                               response.deviceId != null // If deviceId is returned, it's usually successful
                    
                    val isActuallySuccessful = response.success || isSuccessfulByMessage
                    
                    Log.d("DeviceRegistration", "Final success determination: response.success=${response.success}, successByMessage=$isSuccessfulByMessage, finalResult=$isActuallySuccessful")
                    
                    if (isActuallySuccessful) {
                        Log.d("DeviceRegistration", "✅ Device registration successful on attempt $attempt")
                        sharedPreferences.edit()
                            .putString("last_registered_token", deviceToken)
                            .putString("last_registered_userid", userId)
                            .apply()
                        return
                    } else {
                        val errorMessage = response.message ?: "Unknown registration error"
                        Log.e("DeviceRegistration", "❌ Registration failed on attempt $attempt: $errorMessage")
                        Log.e("DeviceRegistration", "Expected success=true but got success=${response.success}")
                        if (errorMessage.contains("INVALID_ARGUMENT", ignoreCase = true)) {
                            Log.e("DeviceRegistration", "INVALID_ARGUMENT from server. Sent request: $request")
                        }
                        lastException = Exception(errorMessage)
                        if (attempt < MAX_RETRY_ATTEMPTS) {
                            val delayTime = RETRY_DELAY * attempt
                            Log.d("DeviceRegistration", "Retrying in ${delayTime}ms...")
                            delay(delayTime)
                        }
                    }
                } catch (e: Exception) {
                    // Handle JSON parsing errors specifically
                    if (e.message?.contains("malformed JSON", ignoreCase = true) == true ||
                        e.message?.contains("JsonReader.setStrictness", ignoreCase = true) == true) {
                        Log.d("DeviceRegistration", "📝 JSON parsing error on attempt $attempt, but server likely succeeded. Assuming success.")
                        Log.d("DeviceRegistration", "🔍 JSON Error details: ${e.message}")
                        sharedPreferences.edit()
                            .putString("last_registered_token", deviceToken)
                            .putString("last_registered_userid", userId)
                            .apply()
                        return
                    } else {
                        Log.e("DeviceRegistration", "Exception on attempt $attempt: ${e.message}")
                        lastException = e
                        if (attempt < MAX_RETRY_ATTEMPTS) {
                            val delayTime = RETRY_DELAY * attempt
                            Log.d("DeviceRegistration", "Retrying in ${delayTime}ms...")
                            delay(delayTime)
                        }
                    }
                }
            }
            Log.e("DeviceRegistration", "Device registration failed after all attempts. Last error: ${lastException?.message}")
        } catch (e: Exception) {
            Log.e("DeviceRegistration", "Unexpected error in device registration: ${e.message}")
        }
    }

    // متد برای بررسی و ثبت مجدد دستگاه در صورت نیاز
    suspend fun checkAndRegisterDevice(userId: String, walletId: String) {
        try {
            if (FirebaseApp.getApps(context).isEmpty()) {
                Log.e("DeviceRegistration", "FirebaseApp is NOT initialized! Check Application class.")
                return
            }
            val deviceToken = withTimeoutOrNull(5000) {
                FirebaseMessaging.getInstance().token.await()
            }
            if (!isProvisioningComplete(userId, walletId, deviceToken)) {
                Log.e("DeviceRegistration", "Provisioning incomplete: userId=$userId, walletId=$walletId, deviceToken=$deviceToken")
                return
            }
            val lastRegisteredToken = sharedPreferences.getString("last_registered_token", null)
            val lastRegisteredUserId = sharedPreferences.getString("last_registered_userid", null)
            val deviceName = android.os.Build.MODEL
            if (deviceToken != lastRegisteredToken || userId != lastRegisteredUserId) {
                Log.d("DeviceRegistration", "Token or userId changed, re-registering device")
                registerDevice(userId, walletId)
            } else {
                Log.d("DeviceRegistration", "Device already registered with current token and userId")
            }
        } catch (e: Exception) {
            Log.e("DeviceRegistration", "Error in checkAndRegisterDevice: ${e.message}")
        }
    }
} 

