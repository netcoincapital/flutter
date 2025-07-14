package com.laxce.adl.ui.theme.screen

import android.app.Activity
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import com.laxce.adl.MainActivity
import com.laxce.adl.MainViewModel
import com.laxce.adl.R
import com.laxce.adl.classes.CustomCaptureActivity
import com.laxce.adl.ui.theme.layout.MainLayout
import com.google.gson.Gson
import com.google.zxing.integration.android.IntentIntegrator
import androidx.compose.foundation.Image
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.material3.*
import androidx.compose.material.Text as MaterialText
import androidx.compose.material.Button as MaterialButton
import androidx.compose.material.CircularProgressIndicator as MaterialCircularProgressIndicator
import androidx.compose.material.ButtonDefaults as MaterialButtonDefaults
import androidx.compose.material.Icon as MaterialIcon
import androidx.compose.material.IconButton as MaterialIconButton
import androidx.compose.material.OutlinedTextField as MaterialOutlinedTextField
import androidx.compose.material.TextFieldDefaults as MaterialTextFieldDefaults


@Composable
fun InsideImportWalletScreen(navController: NavController, viewModel: MainViewModel) {
    val context = LocalContext.current
    val activity = context as? Activity ?: return

    var walletName by remember { mutableStateOf(getNextWalletName(context)) }
    var secretPhrase by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var isLoading by remember { mutableStateOf(false) }
    var showErrorModal by remember { mutableStateOf(false) }

    val clipboardManager = LocalClipboardManager.current
    val regex = Regex("^[a-zA-Z ]*\$")

    fun validateSecretPhrase(input: String): Boolean {
        val words = input.trim().split("\\s+".toRegex())
        return words.size in listOf(12, 18, 24)
    }

    // راه‌اندازی اسکنر QR Code
    val qrScanLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val scanResult = IntentIntegrator.parseActivityResult(result.resultCode, result.data)
        if (scanResult != null && scanResult.contents != null) {
            secretPhrase = scanResult.contents.trim()
            errorMessage = if (validateSecretPhrase(secretPhrase)) null else "Invalid Secret Phrase!"
        }
    }

    val isValidSecretPhrase by remember(secretPhrase) {
        mutableStateOf(validateSecretPhrase(secretPhrase))
    }

    MainLayout(navController = navController) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.White)
                .padding(horizontal = 16.dp)
        ) {
            // هدر با دکمه اسکن QR Code
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 16.dp)
                    .padding(vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                MaterialText(
                    text = "Multi-coin wallet",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.Black
                )

                // دکمه اسکن QR Code (کوچک‌تر و در سمت راست)
                MaterialIconButton(
                    onClick = {
                        (context as? MainActivity)?.isQRScannerLaunched = true
                        val integrator = IntentIntegrator(activity)
                        integrator.setDesiredBarcodeFormats(IntentIntegrator.QR_CODE)
                        integrator.setPrompt("Scan a QR code")
                        integrator.setCameraId(0)
                        integrator.setBeepEnabled(false)
                        integrator.setBarcodeImageEnabled(true)
                        integrator.captureActivity = CustomCaptureActivity::class.java
                        qrScanLauncher.launch(integrator.createScanIntent())
                    },
                    modifier = Modifier.size(24.dp) // کوچک کردن آیکون
                ) {
                    MaterialIcon(
                        painter = painterResource(id = R.drawable.scan),
                        contentDescription = "Scan QR Code",
                        modifier = Modifier.size(24.dp), // کوچک‌تر کردن آیکون
                        tint = Color.Gray // تغییر رنگ به خاکستری
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Secret phrase field
            MaterialText(
                text = "Secret phrase",
                fontSize = 16.sp,
                color = Color.Gray,
                modifier = Modifier.padding(bottom = 8.dp)
            )
            MaterialOutlinedTextField(
                value = secretPhrase,
                onValueChange = { input ->
                    if (regex.matches(input)) {
                        secretPhrase = input
                        errorMessage = if (secretPhrase.isEmpty()) null
                        else if (validateSecretPhrase(secretPhrase)) null
                        else "Secret phrase must contain 12, 18, or 24 words."
                    }
                },
                modifier = Modifier.fillMaxWidth().height(180.dp),
                shape = RoundedCornerShape(8.dp),
                trailingIcon = {
                    MaterialText(
                        text = "Paste",
                        fontSize = 14.sp,
                        color = Color.Blue,
                        modifier = Modifier
                            .clickable {
                                val clipboardText = clipboardManager.getText()?.text ?: ""
                                if (clipboardText.isNotEmpty()) {
                                    secretPhrase = clipboardText.trim()
                                    errorMessage = if (validateSecretPhrase(secretPhrase)) null else "Invalid Secret Phrase!"
                                }
                            }
                            .padding(end = 16.dp)
                            .padding(top = 130.dp)
                    )
                },
                colors = MaterialTextFieldDefaults.outlinedTextFieldColors(
                    focusedBorderColor = if (errorMessage == null) Color.LightGray else Color.Red,
                    unfocusedBorderColor = if (errorMessage == null) Color.LightGray else Color.Red,
                    backgroundColor = Color.White
                ),
                isError = errorMessage != null
            )

            Spacer(modifier = Modifier.weight(1f))

            // Restore Wallet Button
            MaterialButton(
                onClick = {
                    if (isValidSecretPhrase && !isLoading) {
                        isLoading = true // جلوگیری از چندبار کلیک
                        errorMessage = null // پاک کردن پیام خطای قبلی

                        viewModel.importWallet(
                            context = activity,
                            mnemonic = secretPhrase,
                            walletName = walletName,
                            onSuccess = { walletResponse ->
                                navController.navigate("backup?walletName=$walletName") {
                                    popUpTo("InsideImportWalletScreen") { inclusive = true }
                                }
                            },
                            onError = { error ->
                                isLoading = false
                                showErrorModal = true
                                
                                // نمایش پیام خطای مناسب بر اساس نوع خطا
                                errorMessage = when {
                                    error.message?.contains("به‌روزرسانی موجودی") == true -> 
                                        "به‌روزرسانی موجودی کیف پول با خطا مواجه شد. لطفاً دوباره تلاش کنید."
                                    
                                    error.message?.contains("ثبت دستگاه") == true -> 
                                        "ثبت دستگاه با خطا مواجه شد. لطفاً دوباره تلاش کنید."
                                    
                                    error.message?.contains("فرآیند ناقص") == true ->
                                        "فرآیند ایمپورت کیف پول با خطا مواجه شد: ${error.message}"
                                    
                                    else -> "خطا در ایمپورت کیف پول: ${error.message}"
                                }
                            }
                        )
                    }
                },
                enabled = isValidSecretPhrase && !isLoading,
                colors = MaterialButtonDefaults.buttonColors(
                    backgroundColor = if (isValidSecretPhrase) Color(0xCD16B369) else Color.LightGray
                ),
                modifier = Modifier.fillMaxWidth().height(48.dp)
            ) {
                if (isLoading) {
                    MaterialCircularProgressIndicator(
                        color = Color.White,
                        modifier = Modifier.size(24.dp)
                    )
                } else {
                    MaterialText(
                        text = "Restore wallet",
                        fontSize = 14.sp,
                        color = Color.White
                    )
                }
            }

            // نمایش پیام خطا در صورت وجود
            if (errorMessage != null) {
                Spacer(modifier = Modifier.height(8.dp))
                MaterialText(
                    text = errorMessage ?: "",
                    color = Color.Red,
                    fontSize = 14.sp,
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            MaterialText(
                text = "What is a secret phrase?",
                fontSize = 14.sp,
                color = Color.Blue,
                modifier = Modifier.align(Alignment.CenterHorizontally).clickable { /* Help action */ }
            )

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
    
    // Show error modal if needed
    if (showErrorModal) {
        InsideImportErrorModal(
            show = true,
            onDismiss = { showErrorModal = false },
            message = "Unable to connect to the server at this time."
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InsideImportErrorModal(
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
            shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
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


// تابع تولید نام کیف پول جدید
fun getNextWalletName(context: Context): String {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    val walletsJson = sharedPreferences.getString("user_wallets", "[]") ?: "[]"
    val wallets = Gson().fromJson(walletsJson, ArrayList::class.java) as ArrayList<Map<String, String>>

    val existingNames = wallets.mapNotNull { it["walletName"] }
    var count = 1

    while (existingNames.contains("Import $count")) {
        count++
    }
    return "Import $count"
}

