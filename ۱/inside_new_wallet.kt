package com.laxce.adl.ui.theme.screen

import android.content.Context
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.MainViewModel
import com.laxce.adl.ui.theme.layout.MainLayout
import com.laxce.adl.utility.getWalletsFromKeystore
import java.net.URLEncoder
import androidx.compose.foundation.Image
import androidx.compose.ui.res.painterResource
import com.laxce.adl.R
import androidx.compose.material3.*
import androidx.compose.material.Text as MaterialText
import androidx.compose.material.Button as MaterialButton
import androidx.compose.material.CircularProgressIndicator as MaterialCircularProgressIndicator
import androidx.compose.material.ButtonDefaults as MaterialButtonDefaults

@Composable
fun CreateWalletScreen(navController: NavController, mainViewModel: MainViewModel) {
    val context = LocalContext.current
    MainLayout(navController = navController) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.White)
                    .padding(16.dp)
            ) {
                // دکمه بازگشت
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 16.dp)
                ) {

                    MaterialText(
                        text = "Generate new wallet",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.Black
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                // گزینه Secret Phrase
                WalletOptionItem(
                    title = "Secret phrase",
                    description = "Generate a new secret phrase.",
                    buttonText = "Generate",
                    mainViewModel = mainViewModel,
                    navController = navController,
                    context = context
                )
            }
    }
}

@Composable
fun WalletOptionItem(
    title: String,
    description: String,
    buttonText: String,
    mainViewModel: MainViewModel,
    navController: NavController,
    context: Context
) {
    var isLoading by remember { mutableStateOf(false) } // مدیریت وضعیت لودینگ
    var errorMessage by remember { mutableStateOf<String?>(null) } // متغیر خطا
    var showErrorModal by remember { mutableStateOf(false) } // متغیر نمایش مودال خطا

    Column(
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color(0x0D16B369), shape = RoundedCornerShape(12.dp))
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(
                modifier = Modifier.weight(1f)
            ) {
                MaterialText(
                    text = title,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.Black
                )
                MaterialText(
                    modifier = Modifier
                        .padding(top = 10.dp),
                    text = description,
                    fontSize = 12.sp,
                    color = Color.Gray

                )
            }
            MaterialButton(
                onClick = {
                    if (isLoading) return@MaterialButton
                    isLoading = true
                    errorMessage = null // پاک کردن پیام خطای قبلی
                    
                    val walletName = findNextAvailableWalletName(context)

                    mainViewModel.generateWallet(
                        context = context,
                        walletName = walletName,
                        onSuccess = { walletResponse ->
                            val encodedWalletName = URLEncoder.encode(walletName, "UTF-8").replace("+", "%20")
                            navController.navigate("backup?walletName=$encodedWalletName") {
                                popUpTo("insidenewwallet") { inclusive = true }
                            }
                        },
                        onError = { throwable ->
                            isLoading = false
                            showErrorModal = true
                            
                            // نمایش پیام خطای مناسب بر اساس نوع خطا
                            errorMessage = when {
                                throwable.message?.contains("به‌روزرسانی موجودی") == true -> 
                                    "به‌روزرسانی موجودی کیف پول با خطا مواجه شد."
                                
                                throwable.message?.contains("ثبت دستگاه") == true -> 
                                    "ثبت دستگاه با خطا مواجه شد."
                                
                                throwable.message?.contains("فرآیند ناقص") == true ->
                                    "فرآیند ایجاد کیف پول با خطا مواجه شد."
                                
                                else -> "خطا در ایجاد کیف پول: ${throwable.message}"
                            }
                        }
                    )
                },
                enabled = !isLoading, // غیرفعال کردن دکمه هنگام لودینگ
                colors = MaterialButtonDefaults.buttonColors(
                    backgroundColor = if (isLoading) Color.Gray else Color.Transparent,
                    contentColor = if (isLoading) Color.LightGray else Color(0xFF16B369)
                ),
                elevation = MaterialButtonDefaults.elevation(
                    defaultElevation = 0.dp, // حذف سایه پیش‌فرض
                    pressedElevation = 0.dp, // حذف سایه هنگام کلیک
                    hoveredElevation = 0.dp, // حذف سایه هنگام هاور
                    focusedElevation = 0.dp // حذف سایه هنگام فوکوس
                ),
                border = BorderStroke(1.dp, Color(0xFF16B369)),
                modifier = Modifier
                    .width(110.dp) // عرض محدود
                    .height(36.dp) // ارتفاع مناسب
            ) {
                if (isLoading) {
                    MaterialCircularProgressIndicator(
                        modifier = Modifier.size(16.dp), // اندازه کوچک‌تر برای هماهنگی با متن
                        color = Color(0xFF16B369),
                        strokeWidth = 2.dp
                    )
                } else {
                    MaterialText(
                        text = buttonText,
                        color = Color(0xFF16B369),
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center
                    )
                }
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
        
        // Error Modal
        if (showErrorModal) {
            InsideCreateWalletErrorModal(
                show = true,
                onDismiss = { showErrorModal = false },
                message = "Device registration failed due to server security restrictions. This may be caused by Cloudflare protection blocking mobile app requests. Please contact support or try again later."
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InsideCreateWalletErrorModal(
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

fun findNextAvailableWalletName(context: Context): String {
    // دریافت لیست کیف پول‌ها از Keystore
    val walletList = getWalletsFromKeystore(context)
    
    // اگر لیست خالی است، همیشه "New 1" برگردان
    if (walletList.isEmpty()) {
        return "New 1"
    }

    // استخراج نام‌های موجود
    val walletNames = walletList.map { it.WalletName }

    // پیدا کردن اولین نام خالی
    var counter = 1
    var nextName: String
    do {
        nextName = "New $counter"
        counter++
    } while (walletNames.contains(nextName))
    return nextName
}
