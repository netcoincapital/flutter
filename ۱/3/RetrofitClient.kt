package com.laxce.adl.api

import android.content.Context
import com.laxce.adl.api.Api
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStreamWriter
import java.util.concurrent.TimeUnit
import java.util.logging.FileHandler
import java.util.logging.Level
import java.util.logging.Logger
import java.util.logging.SimpleFormatter

object RetrofitClient {

    const val BASE_URL = "https://coinceeper.com/api/" // آدرس سرور
    private const val TAG = "RetrofitClient"
    private const val LOG_FILE_NAME = "api_logs.txt" // نام فایل لاگ
    private const val HOST_HEADER_VALUE = "165.232.149.249" // مقدار Host Header
    private val logger: Logger = Logger.getLogger("ApiLogger")
    private var retrofitInstance: Retrofit? = null

    init {
        setupLogger()
    }

    private fun setupLogger() {
        try {
            // مسیر فایل لاگ در دسکتاپ کامپیوتر
            val userHome = System.getProperty("user.home")
            val desktopPath = "$userHome/Desktop/$LOG_FILE_NAME"
            val logFile = File(desktopPath)

            // پیکربندی لاگر
            val fileHandler = FileHandler(logFile.absolutePath, true) // فایل لاگ برای پیوست
            fileHandler.formatter = SimpleFormatter()
            logger.addHandler(fileHandler)
            logger.level = Level.ALL
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun getInstance(context: Context): Retrofit {
        if (retrofitInstance == null) {
            retrofitInstance = Retrofit.Builder()
                .baseUrl(BASE_URL)
                .client(getCustomOkHttpClient(context))
                .addConverterFactory(GsonConverterFactory.create())
                .build()
        }
        return retrofitInstance!!
    }

    private fun getCustomOkHttpClient(context: Context): OkHttpClient {
        return OkHttpClient.Builder()
            .addInterceptor(HeaderInterceptor(context))
            .addInterceptor(ResponseLoggingInterceptor())
            .addInterceptor(ErrorInterceptor(context))
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build()
    }

    private class HeaderInterceptor(private val context: Context) : Interceptor {
        override fun intercept(chain: Interceptor.Chain): okhttp3.Response {
            val originalRequest = chain.request()
            val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
            val userId = sharedPreferences.getString("UserID", null)

            val modifiedRequest = originalRequest.newBuilder().apply {
                // Absolute minimum headers for urgent fix
                header("User-Agent", "Android-App/1.0")
                header("Accept", "application/json")
                header("Content-Type", "application/json")
                
                // Only essential custom headers
                userId?.let { header("UserID", it) }
                
            }.build()

            return chain.proceed(modifiedRequest)
        }
    }

    private class ResponseLoggingInterceptor : Interceptor {
        override fun intercept(chain: Interceptor.Chain): okhttp3.Response {
            val request = chain.request()
            val response = chain.proceed(request)
            
            // Log the raw response only for getAllCurrencies endpoint
            if (request.url.encodedPath.contains("all-currencies")) {
                try {
                    val responseBody = response.body
                    val source = responseBody?.source()
                    source?.request(Long.MAX_VALUE) // Buffer the entire body
                    val buffer = source?.buffer()
                    val responseString = buffer?.clone()?.readUtf8()
                    
                    android.util.Log.d("APIResponse", "🔍 Raw Response for all-currencies:")
                    android.util.Log.d("APIResponse", "📊 Response Code: ${response.code}")
                    android.util.Log.d("APIResponse", "📄 Response Body (first 500 chars): ${responseString?.take(500)}")
                    android.util.Log.d("APIResponse", "📋 Content-Type: ${response.header("Content-Type")}")
                    android.util.Log.d("APIResponse", "🌐 Server: ${response.header("Server")}")
                    
                } catch (e: Exception) {
                    android.util.Log.e("APIResponse", "❌ Error logging response: ${e.message}")
                }
            }
            
            return response
        }
    }

    private class ErrorInterceptor(private val context: Context) : Interceptor {
        override fun intercept(chain: Interceptor.Chain): okhttp3.Response {
            return try {
                val response = chain.proceed(chain.request())
                if (!response.isSuccessful) {
                    val errorMessage = "API call failed: ${response.code} - ${response.message}"
                    RetrofitClient.logToFile(context, errorMessage)
                }
                response
            } catch (e: Exception) {
                val errorMessage = "Network error: ${e.message}"
                RetrofitClient.logToFile(context, errorMessage)
                throw e
            }
        }
    }

    val retryInterceptor = Interceptor { chain ->
        var request = chain.request()
        var response = chain.proceed(request)
        var tryCount = 0
        val maxRetry = 3

        while (!response.isSuccessful && tryCount < maxRetry) {
            tryCount++
            response = chain.proceed(request)
        }
        response
    }

    private fun logToFile(context: Context, message: String) {
        try {
            val logFile = File(context.filesDir, LOG_FILE_NAME)
            FileOutputStream(logFile, true).use { fos ->
                OutputStreamWriter(fos).use { writer ->
                    writer.appendLine(message)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
