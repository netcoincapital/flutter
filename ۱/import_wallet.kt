package com.laxce.adl.ui.theme.screen

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.activity.result.ActivityResultLauncher
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.MainViewModel
import com.laxce.adl.classes.CustomCaptureActivity
import com.google.zxing.integration.android.IntentIntegrator
import com.laxce.adl.R
import com.google.gson.Gson
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.Image
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.material.Text as MaterialText
import androidx.compose.material.Button as MaterialButton
import androidx.compose.material.CircularProgressIndicator as MaterialCircularProgressIndicator
import androidx.compose.material.ButtonDefaults as MaterialButtonDefaults

fun openCustomTab(context: Context, url: String) {
    val customTabsIntent = CustomTabsIntent.Builder().build()
    customTabsIntent.launchUrl(context, Uri.parse(url))
}

@Composable
fun AlwaysVisibleTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { MaterialText(label) },
        visualTransformation = VisualTransformation.None, // نمایش دائم متن
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text), // کیبورد متنی معمولی
        modifier = modifier
            .fillMaxWidth()
            .background(Color.Transparent, RoundedCornerShape(8.dp)), // تنظیم رنگ Transparent
        singleLine = true, // جلوگیری از چندخطی شدن
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.Transparent, // پس‌زمینه در حالت فوکوس
            unfocusedContainerColor = Color.Transparent, // پس‌زمینه در حالت غیرفعال
            focusedIndicatorColor = MaterialTheme.colorScheme.primary, // رنگ خط فوکوس
            unfocusedIndicatorColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f), // رنگ خط غیرفعال
            cursorColor = MaterialTheme.colorScheme.primary // رنگ نشانگر متن
        )
    )
}




@Composable
fun ImportWalletScreen(navController: NavController, qrScanLauncher: ActivityResultLauncher<Intent>, viewModel: MainViewModel) {
    var seedPhrase by remember { mutableStateOf(viewModel.scanResult ?: "") }
    var isLoading by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val activity = context as? Activity ?: return
    
    // State for error modal
    var showErrorModal by remember { mutableStateOf(false) }

    // Log initial state
    LaunchedEffect(viewModel.scanResult) {
        viewModel.scanResult?.let {
            seedPhrase = it
            viewModel.scanResult = null
        }
    }

    fun getNextWalletName(context: Context): String {
        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        val walletsJson = sharedPreferences.getString("user_wallets", "[]") ?: "[]"
        val wallets = Gson().fromJson(walletsJson, ArrayList::class.java) as ArrayList<Map<String, String>>

        // استخراج تمام نام‌های والت
        val existingNames = wallets.mapNotNull { it["walletName"] }
        var count = 1

        // پیدا کردن نام مناسب
        while (existingNames.contains("Import $count")) {
            count++
        }
        return "Import $count"
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(top = 16.dp, start = 24.dp, end = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Top
        ) {
            MaterialText(
                text = context.getString(R.string.import_wallet),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Seed phrase field
            PasswordField(
                label = context.getString(R.string.Seed_phrase_or_private_key),
                value = seedPhrase,
                onValueChange = {
                    seedPhrase = it
                },
                onQrScanClick = {
                    val integrator = IntentIntegrator(context)
                    integrator.setDesiredBarcodeFormats(IntentIntegrator.QR_CODE)
                    integrator.setPrompt("Scan a QR code")
                    integrator.setCameraId(0)
                    integrator.setBeepEnabled(false)
                    integrator.setBarcodeImageEnabled(true)
                    integrator.captureActivity = CustomCaptureActivity::class.java
                    qrScanLauncher.launch(integrator.createScanIntent())
                },
            )

            MaterialText(
                text = when {
                    seedPhrase.isEmpty() -> context.getString(R.string.enter_recovery_phrase)
                    else -> context.getString(R.string.valid_phrase_key_detected)
                },
                color = when {
                    seedPhrase.isEmpty() -> Color.Gray
                    else -> Color(0xFF4CAF50)
                },
                fontSize = 14.sp,
                modifier = Modifier.align(Alignment.Start)
            )
        }

        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(24.dp))

            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                MaterialText(
                    text = context.getString(R.string.agree_terms_conditions),
                    color = Color.Gray,
                    fontSize = 12.sp
                )
                MaterialText(
                    text = context.getString(R.string.terms_and_conditions),
                    color = MaterialTheme.colorScheme.primary,
                    fontSize = 12.sp,
                    textDecoration = TextDecoration.Underline,
                    modifier = Modifier.clickable {
                        openCustomTab(context, "https://coinceeper.com/terms-of-service")
                    }
                        .padding(start = 3.dp)
                )

            }

            Spacer(modifier = Modifier.height(24.dp))

            MaterialButton(
                onClick = {
                    if (seedPhrase.isBlank()) return@MaterialButton
                    isLoading = true

                    val walletName = getNextWalletName(context)

                    viewModel.importWallet(
                        context = activity,
                        mnemonic = seedPhrase,
                        walletName = walletName,
                        onSuccess = { walletResponse ->
                            navController.navigate("choose-passcode") {
                                popUpTo("importWallet") { inclusive = true }
                            }
                        },
                        onError = { error ->
                            isLoading = false
                            showErrorModal = true
                        }
                    )
                },
                enabled = seedPhrase.isNotBlank() && !isLoading,
                colors = MaterialButtonDefaults.buttonColors(
                    backgroundColor = if (seedPhrase.isNotBlank()) Color(0xFF4C70D0) else Color(0xFF858585),
                    contentColor = Color.White
                ),
                shape = RoundedCornerShape(100), // 🔹 گوشه‌های کاملاً گرد
                modifier = Modifier
                    .fillMaxWidth()
                    .height(100.dp)
                    .padding(bottom = 50.dp)
            ) {
                if (isLoading) {
                    MaterialCircularProgressIndicator(
                        color = Color.White,
                        modifier = Modifier.size(24.dp)
                    )
                } else {
                    MaterialText(
                        text = context.getString(R.string.import_btn),
                        color = Color.White,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }


        }
    }
    
    // Show error modal if needed
    if (showErrorModal) {
        ImportErrorModal(
            show = true,
            onDismiss = { showErrorModal = false },
            message = "Unable to connect to the server at this time."
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ImportErrorModal(
    show: Boolean,
    onDismiss: () -> Unit,
    message: String,
    title: String = "Error"
) {
    if (show) {
        ModalBottomSheet(
            onDismissRequest = onDismiss,
            sheetState = rememberModalBottomSheetState(
                skipPartiallyExpanded = true,
                confirmValueChange = { true }
            ),
            shape = RoundedCornerShape(topStart = 25.dp, topEnd = 25.dp),
            containerColor = Color.White,
            scrimColor = Color.Black.copy(alpha = 0.6f),
            dragHandle = null
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Image(
                    painter = painterResource(id = R.drawable.error),
                    contentDescription = "Error",
                    modifier = Modifier
                        .size(48.dp)
                        .padding(bottom = 16.dp)
                )

                MaterialText(
                    text = title,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.Black,
                    modifier = Modifier.padding(bottom = 8.dp)
                )

                MaterialText(
                    text = message,
                    fontSize = 16.sp,
                    color = Color.Gray,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(bottom = 24.dp)
                )

                MaterialButton(
                    onClick = onDismiss,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp),
                    colors = MaterialButtonDefaults.buttonColors(
                        backgroundColor = Color(0xFFFF1961),
                        contentColor = Color.White
                    ),
                    shape = RoundedCornerShape(25.dp)
                ) {
                    MaterialText("OK", fontSize = 16.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
fun PasswordField(label: String, value: String, onValueChange: (String) -> Unit, onQrScanClick: (() -> Unit)? = null) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { MaterialText(label) },
        trailingIcon = {
            if (onQrScanClick != null) {
                IconButton(onClick = onQrScanClick) {
                    Icon(imageVector = Icons.Default.QrCode, contentDescription = "QR Code Scanner")
                }
            }
        },
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White, RoundedCornerShape(25.dp))
    )
}
