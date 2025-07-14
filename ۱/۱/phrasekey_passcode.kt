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
import kotlinx.coroutines.delay
import androidx.compose.foundation.interaction.MutableInteractionSource
import com.laxce.adl.R
import com.laxce.adl.utility.getUserIdFromKeystore
import java.net.URLEncoder

fun triggerVibration2(context: Context, intensity: Int) {
    val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val vibrationEffect = VibrationEffect.createOneShot(intensity.toLong(), VibrationEffect.DEFAULT_AMPLITUDE)
        vibrator.vibrate(vibrationEffect)
    } else {
        vibrator.vibrate(intensity.toLong())
    }
}

@Composable
fun PhraseKeyPasscodeScreen(navController: NavController, title: String, walletName: String, showCopy: Boolean) {
    var enteredCode by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf("") }
    val context = LocalContext.current as FragmentActivity
    val savedPasscode = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        .getString("Passcode", null)
    val borderColors = listOf(
        Color(0xFF0ab62c), Color(0xFF15b65c), Color(0xFF1bb679),
        Color(0xFF27b6ac), Color(0xFF2db6c7), Color(0xFF39b6fb)
    )

    val onPasscodeConfirmed = {
        val userId = getUserIdFromKeystore(context, walletName)
        val encodedWalletName = URLEncoder.encode(walletName, "UTF-8").replace("+", "%20")
        navController.navigate("phrasekey/$userId/$encodedWalletName?showCopy=$showCopy") {
            popUpTo("phrasekeypasscode") { inclusive = true }
        }
    }

    LaunchedEffect(enteredCode) {
        if (enteredCode.length == 6) {
            if (enteredCode == savedPasscode) {
                onPasscodeConfirmed()
            } else {
                errorMessage = "The passcode entered is not correct"
                delay(500)
                enteredCode = ""
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

        if (errorMessage.isNotEmpty()) {
            Text(
                text = errorMessage,
                color = Color.Red,
                fontSize = 14.sp,
                modifier = Modifier.padding(bottom = 16.dp)
            )
        }

        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            repeat(6) { index ->
                Box(
                    modifier = Modifier
                        .size(55.dp)
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

        NumberPad2(
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
                authenticateBiometric2(context, navController, walletName, showCopy)
            },
            vibrationIntensity = 2
        )
    }
}

@Composable
fun NumberPad2(
    onNumberClick: (String) -> Unit,
    onDeleteClick: () -> Unit,
    onBiometricClick: () -> Unit,
    vibrationIntensity: Int
) {
    val context = LocalContext.current

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
                    NumberButton2(item) {
                        onNumberClick(it)
                        triggerVibration2(context, vibrationIntensity)
                    }
                }
            }
        }

        Row(
            horizontalArrangement = Arrangement.spacedBy(32.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                painter = painterResource(id = R.drawable.fingerprint),
                contentDescription = "Fingerprint Authentication",
                modifier = Modifier
                    .size(60.dp)
                    .clickable {
                        onBiometricClick()
                        triggerVibration2(context, vibrationIntensity)
                    },
                tint = Color.Gray
            )

            NumberButton2("0") {
                onNumberClick("0")
                triggerVibration2(context, vibrationIntensity)
            }

            Text(
                text = "⌫",
                fontSize = 36.sp,
                modifier = Modifier
                    .clickable {
                        onDeleteClick()
                        triggerVibration2(context, vibrationIntensity)
                    }
                    .padding(10.dp),
                color = Color.Gray
            )
        }
    }
}

fun authenticateBiometric2(context: Context, navController: NavController, walletName: String, showCopy: Boolean) {
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
                        val userId = getUserIdFromKeystore(context, walletName)
                        val encodedWalletName = URLEncoder.encode(walletName, "UTF-8").replace("+", "%20")
                        navController.navigate("phrasekey/$userId/$encodedWalletName?showCopy=$showCopy")
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
            val intent = Intent(Settings.ACTION_SECURITY_SETTINGS)
            context.startActivity(intent)
        }
    }
}

@Composable
fun NumberButton2(number: String, onClick: (String) -> Unit) {
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
                triggerVibration2(context, 50) // فعال‌سازی ویبره هنگام کلیک
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
