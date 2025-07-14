package com.laxce.adl.ui.theme.screen

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.MainViewModel
import androidx.compose.foundation.Image
import androidx.compose.material3.*
import com.laxce.adl.R
import androidx.compose.material.Text as MaterialText
import androidx.compose.material.Button as MaterialButton
import androidx.compose.material.CircularProgressIndicator as MaterialCircularProgressIndicator
import androidx.compose.material.ButtonDefaults as MaterialButtonDefaults
import androidx.compose.material.Icon as MaterialIcon

@Composable
fun CreateNewWalletScreen(navController: NavController, mainViewModel: MainViewModel) {
    val context = LocalContext.current
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var walletName by rememberSaveable(key = "wallet_name") { mutableStateOf("") }
    var showErrorModal by remember { mutableStateOf(false) }

    LaunchedEffect(key1 = "init") {
        if (walletName.isEmpty()) {
            walletName = findNextAvailableWalletName(context)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .padding(16.dp),
    ) {
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

            WalletOptionItemNew(
                title = "Secret phrase",
                points = 100,
                buttonText = "Generate",
                onClickCreate = {
                    val currentWalletName = walletName

                    mainViewModel.generateWallet(
                        context = context,
                        walletName = currentWalletName,
                        onSuccess = {
                            errorMessage = null
                            val encodedWalletName = java.net.URLEncoder.encode(currentWalletName, "UTF-8")
                            navController.navigate("choose-passcode?walletName=$encodedWalletName") {
                                popUpTo("create-new-wallet") { inclusive = true }
                                launchSingleTop = true
                            }
                        },
                        onError = { error ->
                            errorMessage = error.message
                            showErrorModal = true
                        }
                    )
                },
            expandedContent = {
                Column(
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    DetailRow(
                        label = "Security",
                        content = "Create and recover wallet with a 12, 18, or 24-word secret phrase. You must manually store this, or back up with Google Drive storage."
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    DetailRow(
                        label = "Transaction",
                        content = "Transactions are available on more networks (chains), but require more steps to complete."
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    DetailRow(
                        label = "Fees",
                        content = "Pay network fee (gas) with native tokens only. For example, if your transaction is on the Ethereum network, you can only pay for this fee with ETH."
                    )
                }
            }
        )

    }
    
    // Show error modal if needed
    if (showErrorModal) {
        CreateWalletErrorModal(
            show = true,
            onDismiss = { showErrorModal = false },
            message = "Device registration failed due to server security restrictions. This may be caused by Cloudflare protection blocking mobile app requests. Please contact support or try again later."
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateWalletErrorModal(
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

@Composable
fun WalletOptionItemNew(
    title: String,
    points: Int? = null,
    buttonText: String,
    onClickCreate: () -> Unit,
    expandedContent: @Composable () -> Unit
) {
    var isExpanded by remember { mutableStateOf(false) } // مدیریت باز و بسته بودن
    var isLoading by remember { mutableStateOf(false) }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0x0D16B369), shape = RoundedCornerShape(12.dp))
            .padding(16.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier = Modifier.fillMaxWidth()
        ) {
            // عنوان و امتیاز
            Column {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    MaterialText(
                        text = title,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.Black
                    )
                    if (points != null) {
                        Spacer(modifier = Modifier.width(8.dp))
                        MaterialText(
                            text = "+$points points",
                            fontSize = 12.sp,
                            color = Color.Gray,
                            fontWeight = FontWeight.Normal
                        )
                    }
                }

                MaterialText(
                    text = if (isExpanded) "Hide details ▲" else "Show details ▼",
                    fontSize = 12.sp,
                    color = Color(0xFF16B369),
                    modifier = Modifier
                        .padding(top = 8.dp)
                        .clickable { isExpanded = !isExpanded } // تغییر وضعیت باز و بسته بودن
                )

            }

            // دکمه Create
            MaterialButton(
                onClick = {
                    if (isLoading) return@MaterialButton // جلوگیری از کلیک دوباره
                    isLoading = true // شروع عملیات لودینگ
                    onClickCreate() // اجرای عملیات
                },
                colors = MaterialButtonDefaults.buttonColors(
                    backgroundColor = Color.Transparent, // حذف رنگ پس‌زمینه
                    contentColor = Color(0xFF16B369) // رنگ متن
                ),
                elevation = MaterialButtonDefaults.elevation(
                    defaultElevation = 0.dp, // حذف سایه پیش‌فرض
                    pressedElevation = 0.dp, // حذف سایه هنگام کلیک
                    hoveredElevation = 0.dp, // حذف سایه هنگام هاور
                    focusedElevation = 0.dp // حذف سایه هنگام فوکوس
                ),
                border = BorderStroke(1.dp, Color(0xFF16B369)), // اضافه کردن بوردر
                modifier = Modifier
                    .width(110.dp)
                    .height(36.dp)
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
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }

        // محتوای اضافی
        if (isExpanded) {
            Spacer(modifier = Modifier.height(16.dp))
            expandedContent()
        }
    }
}

@Composable
fun DetailRow(label: String, content: String) {
    Column {
        // نمایش عنوان
        MaterialText(
            text = label,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            color = Color(0xA6000000)
        )
        // نمایش توضیحات
        MaterialText(
            text = content,
            fontSize = 12.sp,
            color = Color.Gray,
            textAlign = TextAlign.Start,
            modifier = Modifier.padding(top = 4.dp)
        )

        // فقط برای "Transaction" آیکون‌ها و متن نمایش داده شود
        if (label == "Transaction") {
            // لیست آیکون‌های متفاوت
            val icons = listOf(
                com.laxce.adl.R.drawable.btc,
                com.laxce.adl.R.drawable.ethereum_logo,
                com.laxce.adl.R.drawable.binance_logo,
                com.laxce.adl.R.drawable.tron,
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
                horizontalArrangement = Arrangement.Start,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // نمایش آیکون‌ها
                icons.forEachIndexed { index, iconRes ->
                    MaterialIcon(
                        painter = painterResource(id = iconRes), // آیکون از لیست
                        contentDescription = "Icon $index",
                        tint = Color.Unspecified,
                        modifier = Modifier
                            .size(24.dp)
                            .padding(end = 8.dp)
                    )
                }

                // نمایش متن کنار آیکون‌ها
                MaterialText(
                    text = "+ more chains",
                    fontSize = 12.sp,
                    color = Color.Gray
                )
            }
        }
    }
}
