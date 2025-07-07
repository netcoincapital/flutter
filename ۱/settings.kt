package com.laxce.adl.ui.theme.screen

import android.app.Activity
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.Divider
import androidx.compose.material.Icon
import androidx.compose.material.Text
import androidx.compose.material.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.R
import com.laxce.adl.classes.CustomCaptureActivity
import com.laxce.adl.ui.theme.layout.MainLayout
import com.google.zxing.integration.android.IntentIntegrator
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.Toast
import androidx.compose.material.AlertDialog
import androidx.compose.material.Button
import androidx.compose.material.ButtonDefaults
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.runtime.DisposableEffect
import androidx.compose.material.IconButton
import com.laxce.adl.MainActivity

@Composable
fun SettingScreen(navController: NavController) {

    val context = LocalContext.current
    var walletName by remember { mutableStateOf(loadSelectedWalletName(context)) } // مقدار اولیه از SharedPreferences
    var showDialog by remember { mutableStateOf(false) }
    var qrContent by remember { mutableStateOf("") }


    DisposableEffect(Unit) {
        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == "selected_wallet") {
                walletName = loadSelectedWalletName(context) // به‌روزرسانی نام کیف پول
            }
        }
        sharedPreferences.registerOnSharedPreferenceChangeListener(listener)
        onDispose {
            sharedPreferences.unregisterOnSharedPreferenceChangeListener(listener)
        }
    }


    val qrCodeLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val intentResult = IntentIntegrator.parseActivityResult(
            result.resultCode,
            result.data
        )
        if (intentResult != null && intentResult.contents != null) {
            qrContent = intentResult.contents
            showDialog = true
        }
    }
    Box(modifier = Modifier.fillMaxSize()) {
        MainLayout(navController = navController) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.White)
        ) {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp)
                    .padding(bottom = 5.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Settings",
                    style = MaterialTheme.typography.h6,
                    color = Color.Black
                )
            }

            // سکشن‌ها
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                // سکشن اول
                item {
                    Section(title = "General Settings") {
                        SettingItem(
                            icon = R.drawable.wallet,
                            title = "Wallets",
                            subtitle = walletName, // نمایش نام کیف پول ذخیره‌شده
                            onClick = {
                                navController.navigate("wallets") // ناوبری به صفحه Wallets
                            },
                            paddingVertical = 12.dp
                        )
                    }
                }


                // سکشن دوم
                item {
                    Section(title = "Utilities") {
                        SettingItem(
                            icon = R.drawable.alert,
                            title = "Price Alerts",
                            onClick = { /* Handle click */ },
                            paddingVertical = 20.dp
                        )
                        SettingItem(
                            icon = R.drawable.address_book,
                            title = "Address Book",
                            onClick = { navController.navigate("AddressBook")},
                            paddingVertical = 20.dp
                        )
                        SettingItem(
                            icon = R.drawable.scan,
                            title = "Scan QR Code",
                            onClick = {
                                val activity = context as? MainActivity
                                activity?.isQRScannerLaunched = true  // تنظیم فلگ قبل از لانچ اسکنر
                                (context as? MainActivity)?.isQRScannerLaunched = true
                                val integrator = IntentIntegrator(context as Activity)
                                integrator.setDesiredBarcodeFormats(IntentIntegrator.QR_CODE)
                                integrator.setPrompt("Scan a QR code")
                                integrator.setCameraId(0)
                                integrator.setBeepEnabled(false)
                                integrator.setBarcodeImageEnabled(true)
                                integrator.captureActivity = CustomCaptureActivity::class.java
                                integrator.addExtra("return_screen", "settings")
                                qrCodeLauncher.launch(integrator.createScanIntent())
                            },
                            paddingVertical = 20.dp
                        )
                    }
                }


                // سکشن سوم
                item {
                    Section(title = "Security") {
                        SettingItem(
                            icon = R.drawable.setting,
                            title = "Preferences",
                            onClick = {
                                navController.navigate("preferences")
                            },
                            paddingVertical = 20.dp
                        )

                        SettingItem(
                            icon = R.drawable.shield,
                            title = "Security",
                            onClick = {
                                navController.navigate("security_passcode") // ناوبری به صفحه security_passcode
                            },
                            paddingVertical = 20.dp
                        )

                        SettingItem(
                            icon = R.drawable.bell,
                            title = "Notifications",
                            onClick = { navController.navigate("notificationmanagement") },
                            paddingVertical = 20.dp
                        )
                    }
                }

                // سکشن پنجم
                item {
                    Section(title = "Support") {
                        SettingItem(
                            icon = R.drawable.question,
                            title = "Help Center",
                            onClick = { /* Handle click */ },
                            paddingVertical = 20.dp
                        )
                        SettingItem(
                            icon = R.drawable.support,
                            title = "Support",
                            onClick = { /* Handle click */ },
                            paddingVertical = 20.dp
                        )
                        SettingItem(
                            icon = R.drawable.logo,
                            title = "About",
                            onClick = { /* Handle click */ },
                            paddingVertical = 20.dp
                        )
                    }
                }

                // سکشن ششم
                item {
                    Section(title = "Social media") {
                        SettingItem(
                            icon = R.drawable.x,
                            title = "X platform",
                            onClick = {
                                try {
                                    // تلاش برای باز کردن اپلیکیشن توییتر
                                    val intent = Intent(Intent.ACTION_VIEW).apply {
                                        data = Uri.parse("https://twitter.com/coinceeper") // لینک توییتر
                                        setPackage("com.twitter.android") // مشخص کردن که فقط اپلیکیشن توییتر باز شود
                                    }
                                    context.startActivity(intent)
                                } catch (e: Exception) {
                                    // در صورتی که اپلیکیشن توییتر نصب نباشد، لینک در مرورگر داخلی باز می‌شود
                                    val url = "https://x.com/coinceeper"
                                    val customTabsIntent = CustomTabsIntent.Builder().build()
                                    customTabsIntent.launchUrl(context, Uri.parse(url))
                                }
                            },
                            paddingVertical = 20.dp
                        )
                        SettingItem(
                            icon = R.drawable.instagram,
                            title = "Instagram",
                            onClick = {
                                try {
                                    // تلاش برای باز کردن اپلیکیشن اینستاگرام
                                    val intent = Intent(Intent.ACTION_VIEW).apply {
                                        data = Uri.parse("https://www.instagram.com/coinceeperofficial/")
                                        setPackage("com.instagram.android") // مشخص کردن که اپلیکیشن اینستاگرام باز شود
                                    }
                                    context.startActivity(intent)
                                } catch (e: Exception) {
                                    // در صورتی که اپلیکیشن اینستاگرام نصب نباشد، لینک در مرورگر داخلی باز می‌شود
                                    val url = "https://www.instagram.com/coinceeperofficial/"
                                    val customTabsIntent = CustomTabsIntent.Builder().build()
                                    customTabsIntent.launchUrl(context, Uri.parse(url))
                                }
                            },
                            paddingVertical = 20.dp
                        )

                        SettingItem(
                            icon = R.drawable.telegram,
                            title = "Telegram",
                            onClick = {
                                try {
                                    // تلاش برای باز کردن اپلیکیشن تلگرام
                                    val intent = Intent(Intent.ACTION_VIEW).apply {
                                        data = Uri.parse("tg://resolve?domain=coinceeper") // لینک مستقیم تلگرام
                                        setPackage("org.telegram.messenger") // اطمینان از باز شدن اپلیکیشن تلگرام
                                    }
                                    context.startActivity(intent)
                                } catch (e: Exception) {
                                    // در صورتی که اپلیکیشن تلگرام نصب نباشد، لینک در مرورگر داخلی باز می‌شود
                                    val url = "https://t.me/coinceeper"
                                    val customTabsIntent = CustomTabsIntent.Builder().build()
                                    customTabsIntent.launchUrl(context, Uri.parse(url))
                                }
                            },
                            paddingVertical = 20.dp
                        )

                    }
                }
            }

            // نمایش مودال پیش‌فرض اندروید
            if (showDialog) {
                ShowQRDialog(
                    context = context,
                    qrContent = qrContent,
                    onDismiss = { showDialog = false }
                )
            }
        }
    }
    }
}

@Composable
fun ShowQRDialog(context: Context, qrContent: String, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                text = "Scanned Content",
                style = MaterialTheme.typography.h6,
                modifier = Modifier.fillMaxWidth().padding(0.dp),
                color = Color.Black
            )
        },
        text = {
            Column {
                Text(
                    text = qrContent,
                    style = MaterialTheme.typography.body1,
                    color = Color.Black,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(0.dp)
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val clipboardManager =
                        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip = ClipData.newPlainText("QR Content", qrContent)
                    clipboardManager.setPrimaryClip(clip)
                    Toast.makeText(context, "Copied to clipboard", Toast.LENGTH_SHORT).show()
                },
                colors = ButtonDefaults.buttonColors(
                    backgroundColor = Color.Transparent, // پس‌زمینه شفاف
                    contentColor = Color(0xFF16B369) // رنگ متن مشکی
                ),
                elevation = ButtonDefaults.elevation(0.dp) // حذف سایه
            ) {
                Text(text = "Copy")
            }
        },
        dismissButton = {
            Button(
                onClick = onDismiss,
                colors = ButtonDefaults.buttonColors(
                    backgroundColor = Color.Transparent, // پس‌زمینه شفاف
                    contentColor = Color(0xFFDC0303) // رنگ متن مشکی
                ),
                elevation = ButtonDefaults.elevation(0.dp) // حذف سایه
            ) {
                Text(text = "Cancel")
            }
        }
    )
}


@Composable
fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier = Modifier.fillMaxWidth()) {
        // عنوان سکشن
        Text(
            text = title,
            style = MaterialTheme.typography.subtitle1.copy(fontSize = 16.sp),
            color = Color.Gray,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp)
        )

        // محتوای سکشن
        content()

        // Divider زیر سکشن
        Divider(
            color = Color(0x32626262),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
        )
    }
}


@Composable
fun SettingItem(
    icon: Int,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit,
    paddingVertical: Dp // تغییر نوع به Dp برای سازگاری با Modifier.padding
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(vertical = paddingVertical, horizontal = 16.dp), // اعمال فاصله عمودی
        verticalAlignment = Alignment.CenterVertically // تراز عمودی
    ) {
        // آیکون سمت چپ
        Icon(
            painter = painterResource(id = icon),
            contentDescription = title,
            modifier = Modifier.size(20.dp),
            tint = Color.Gray
        )

        Spacer(modifier = Modifier.width(16.dp))

        // عنوان و زیرنویس
        Column(
            modifier = Modifier.weight(1f)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.body1.copy(
                    fontSize = 18.sp
                ),
                color = Color(0xFF494949)
            )
            subtitle?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.body2.copy(
                        fontSize = 14.sp
                    ),
                    color = Color.Gray,
                    modifier = Modifier.padding(top = 4.dp)
                )
            }
        }

        // فلش سمت راست
        Icon(
            painter = painterResource(id = R.drawable.rightarrow),
            contentDescription = "Arrow",
            modifier = Modifier.size(16.dp),
            tint = Color.Gray
        )
    }
}





fun loadSelectedWalletName(context: Context): String {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    return sharedPreferences.getString("selected_wallet", "No Wallet Selected") ?: "No Wallet Selected"
}



