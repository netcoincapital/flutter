package com.laxce.adl.ui.theme.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.R
import androidx.compose.ui.platform.LocalContext // اضافه کردن این ایمپورت
import com.laxce.adl.ui.theme.layout.MainLayout
import androidx.compose.runtime.DisposableEffect
import java.net.URLEncoder

@Composable
fun BackupScreen(navController: NavController, walletName: String) {
    val context = LocalContext.current

    LaunchedEffect(Unit) {
    }

    MainLayout(navController = navController) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.White)
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            // دکمه بازگشت و عنوان
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween // تنظیم فاصله بین SKIP و BACKUP
            ) {
                Text(
                    text = "Backup",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.Black
                )
                Text(
                    text = "Skip",
                    modifier = Modifier
                        .padding(end = 16.dp)
                        .clickable { 
                            navController.navigate("home")
                        }
                        .background(Color(0x1A13CE76), shape = RoundedCornerShape(12.dp))
                        .padding(start = 10.dp, end = 10.dp, top = 5.dp, bottom = 5.dp),
                    fontSize = 14.sp,
                    color = Color(0xFF16B369)
                )
            }

            Spacer(modifier = Modifier.height(32.dp))

            // تصویر اصلی
            Icon(
                painter = painterResource(id = R.drawable.backupimage), // تصویر موردنظر
                contentDescription = "Backup Illustration",
                modifier = Modifier.size(300.dp),
                tint = Color.Unspecified
            )

            Spacer(modifier = Modifier.height(32.dp))

            // متن‌های توضیحی
            Text(
                text = "Back up secret phrase",
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = Color.Black,
                textAlign = TextAlign.Center
            )
            Text(
                text = "Protect your assets by backing up your seed phrase now.",
                fontSize = 14.sp,
                color = Color.Gray,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(32.dp))

            // دکمه‌های Backup
            Column(
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Button(
                    onClick = {
                        val encodedWalletName = URLEncoder.encode(walletName, "UTF-8").replace("+", "%20")
                        navController.navigate("phrasekeypasscode/$encodedWalletName?showCopy=true") {
                            popUpTo("backup") { inclusive = true }
                        }
                    },
                    colors = ButtonDefaults.buttonColors(backgroundColor = Color(0x0D1FD092)),
                    shape = RoundedCornerShape(12.dp),
                    elevation = ButtonDefaults.elevation(
                        defaultElevation = 0.dp, // حذف سایه پیش‌فرض
                        pressedElevation = 0.dp, // حذف سایه هنگام کلیک
                        hoveredElevation = 0.dp, // حذف سایه هنگام هاور
                        focusedElevation = 0.dp // حذف سایه هنگام فوکوس
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp)
                ) {
                    Text(
                        text = "Back up manually",
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF16B369)
                    )
                }

            }
        }
    }
    
    // Log when screen is disposed
    DisposableEffect(Unit) {
        onDispose {
        }
    }
}
