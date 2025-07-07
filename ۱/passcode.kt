package com.laxce.adl.ui.theme.screen

import android.content.Context
import android.content.Intent
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.Build
import android.provider.Settings
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.navigation.NavController
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import kotlinx.coroutines.launch
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.runtime.remember
import com.laxce.adl.R
import java.net.URLEncoder


// تابع برای ایجاد ویبره با شدت تنظیم‌شده
fun triggerVibration(context: Context, intensity: Int) {
    val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val vibrationEffect = VibrationEffect.createOneShot(intensity.toLong(), VibrationEffect.DEFAULT_AMPLITUDE)
        vibrator.vibrate(vibrationEffect)
    } else {
        vibrator.vibrate(intensity.toLong())
    }
}

@Composable
fun PasscodeScreen(navController: NavController, title: String, walletName: String = "") {
    val context = LocalContext.current as FragmentActivity
    var enteredCode by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf("") }
    var isConfirmed by remember { mutableStateOf(false) }

    val sharedPrefs = EncryptedSharedPreferences.create(
        "passcode_prefs",
        MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC),
        context,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )
    val coroutineScope = rememberCoroutineScope()

    val firstPasscode = sharedPrefs.getString("first_passcode", null)
    val savedPasscode = sharedPrefs.getString("passcode", null)
    val borderColors = listOf(Color(0xFF0ab62c), Color(0xFF15b65c), Color(0xFF1bb679),
        Color(0xFF27b6ac), Color(0xFF2db6c7), Color(0xFF39b6fb))

    fun FragmentActivity.savePasscodeToKeystore(context: Context, passcode: String) {
        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        sharedPreferences.edit().putString("Passcode", passcode).apply()
    }

    // بررسی ورودی‌های کاربر - بهینه شده
    LaunchedEffect(enteredCode) {
        if (enteredCode.length == 6 && !isConfirmed) {
            when (title) {
                "Choose Passcode" -> {
                    val encodedWalletName = URLEncoder.encode(walletName, "UTF-8")
                    sharedPrefs.edit()
                        .putString("first_passcode", enteredCode)
                        .apply()
                    navController.navigate("confirm-passcode?walletName=$encodedWalletName") {
                        launchSingleTop = true
                        popUpTo("choose-passcode") { inclusive = true }
                    }
                }
                "Confirm Passcode" -> {
                    if (enteredCode == firstPasscode) {
                        sharedPrefs.edit()
                            .putString("passcode", enteredCode)
                            .apply()
                        (context as FragmentActivity).savePasscodeToKeystore(context, enteredCode)
                        val encodedWalletName = URLEncoder.encode(walletName, "UTF-8")
                        navController.navigate("backup?walletName=$encodedWalletName") {
                            launchSingleTop = true
                            popUpTo("confirm-passcode") { inclusive = true }
                        }
                    } else {
                        errorMessage = "The passcode entered is not the same"
                        enteredCode = ""
                    }
                }
                "Enter Passcode" -> {
                    val keystorePasscode = (context as FragmentActivity)
                        .getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
                        .getString("Passcode", null)

                    if (enteredCode == savedPasscode || enteredCode == keystorePasscode) {
                        navController.navigate("home") {
                            launchSingleTop = true
                            popUpTo("passcode") { inclusive = true }
                        }
                    } else {
                        errorMessage = "The passcode entered is not correct"
                        enteredCode = ""
                    }
                }
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = title,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(bottom = 16.dp)
        )

        // نمایش پیام خطا
        if (errorMessage.isNotEmpty()) {
            Text(
                text = errorMessage,
                color = Color.Red,
                fontSize = 14.sp,
                modifier = Modifier.padding(bottom = 16.dp)
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            repeat(6) { index ->
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .aspectRatio(1f)
                        .background(Color.Transparent)
                        .border(
                            width = 2.dp,
                            color = borderColors[index % borderColors.size],
                            shape = RoundedCornerShape(25.dp)
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    if (index < enteredCode.length) {
                        Text(
                            text = "•",
                            fontSize = 30.sp,
                            fontWeight = FontWeight.Bold,
                            color = borderColors[index % borderColors.size]
                        )
                    }
                }
            }
        }

        Text(
            text = "Passcode adds an extra layer of security\nwhen using the app",
            fontSize = 14.sp,
            color = Color.Gray,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 16.dp, bottom = 50.dp)
        )

        NumberPad(
            onNumberClick = { number ->
                if (enteredCode.length < 6) {
                    enteredCode += number
                }
            },
            onDeleteClick = {
                if (enteredCode.isNotEmpty()) {
                    enteredCode = enteredCode.dropLast(1)
                }
            },
            onBiometricClick = {
                coroutineScope.launch {
                    authenticateBiometric(context, navController, walletName)
                }
            },
            vibrationIntensity = 2 // تنظیم شدت ویبره
        )

    }
}

@Composable
fun NumberPad(
    onNumberClick: (String) -> Unit,
    onDeleteClick: () -> Unit,
    onBiometricClick: () -> Unit,
    vibrationIntensity: Int
) {
    val context = LocalContext.current // گرفتن context از LocalContext.current برای استفاده در triggerVibration

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        val buttons = listOf(
            listOf("1", "2", "3"),
            listOf("4", "5", "6"),
            listOf("7", "8", "9")
        )

        for (row in buttons) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(32.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                for (item in row) {
                    NumberButton(item) {
                        onNumberClick(it)
                        triggerVibration(context, vibrationIntensity) // ویبره پس از کلیک روی عدد
                    }
                }
            }
        }

        Row(
            horizontalArrangement = Arrangement.spacedBy(32.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                painter = painterResource(id = R.drawable.fingerprint), // آیکون اثر انگشت
                contentDescription = "Fingerprint Authentication",
                modifier = Modifier
                    .size(60.dp)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null
                    ) {
                        onBiometricClick()
                        triggerVibration(context, vibrationIntensity) // ویبره پس از کلیک روی آیکون اثر انگشت
                    },
                tint = Color.Gray
            )

            NumberButton("0") {
                onNumberClick("0")
                triggerVibration(context, vibrationIntensity) // ویبره پس از کلیک روی دکمه صفر
            }

            Text(
                text = "⌫",
                fontSize = 36.sp,
                modifier = Modifier
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null
                    ) {
                        onDeleteClick()
                        triggerVibration(context, vibrationIntensity) // ویبره پس از کلیک روی دکمه حذف
                    }
                    .padding(10.dp),
                color = Color.Gray
            )
        }
    }
}


suspend fun authenticateBiometric(context: Context, navController: NavController, walletName: String) {
    val executor = ContextCompat.getMainExecutor(context)
    val biometricManager = BiometricManager.from(context)

    when (biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)) {
        BiometricManager.BIOMETRIC_SUCCESS -> {
            val biometricPrompt = BiometricPrompt(
                context as FragmentActivity,
                executor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        super.onAuthenticationSucceeded(result)
                        val encodedWalletName = URLEncoder.encode(walletName, "UTF-8")
                        navController.navigate("backup?walletName=$encodedWalletName") {
                            popUpTo("backup/$walletName") { inclusive = true }
                        }
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        super.onAuthenticationError(errorCode, errString)
                        // پیام خطا نمایش داده شود
                    }

                    override fun onAuthenticationFailed() {
                        super.onAuthenticationFailed()
                        // خطا در صورت عدم تطابق اثر انگشت
                    }
                }
            )

            val promptInfo = BiometricPrompt.PromptInfo.Builder()
                .setTitle("Fingerprint Authentication")
                .setSubtitle("Log in using your fingerprint")
                .setNegativeButtonText("Cancel")
                .build()

            biometricPrompt.authenticate(promptInfo)
        }
        else -> {
            // کاربر اثر انگشت خود را ثبت نکرده است
            val intent = Intent(Settings.ACTION_SECURITY_SETTINGS)
            context.startActivity(intent)
        }
    }
}



@Composable
fun NumberButton(number: String, onClick: (String) -> Unit) {
    val context = LocalContext.current // گرفتن context از LocalContext.current

    Box(
        modifier = Modifier
            .size(70.dp)
            .background(Color.LightGray, shape = CircleShape)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null
            ) {
                onClick(number)
                triggerVibration(context, 50) // فعال‌سازی ویبره هنگام کلیک
            },
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = number,
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = Color.Black
        )
    }
}

