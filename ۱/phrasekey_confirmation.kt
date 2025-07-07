package com.laxce.adl.ui.theme.screen

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.R
import com.laxce.adl.ui.theme.layout.MainLayout
import com.laxce.adl.utility.getMnemonicFromKeystore
import com.laxce.adl.utility.getUserIdFromKeystore

@Composable
fun SecretPhraseScreen(navController: NavController, walletName: String) {
    val context = LocalContext.current
    var checkbox1 by remember { mutableStateOf(false) }
    var checkbox2 by remember { mutableStateOf(false) }
    var checkbox3 by remember { mutableStateOf(false) }
    val allChecked = checkbox1 && checkbox2 && checkbox3

    val userId = getUserIdFromKeystore(context, walletName)
    
    LaunchedEffect(Unit) {
        val sharedPrefs = context.getSharedPreferences("WalletPrefs", Context.MODE_PRIVATE)
        val allEntries = sharedPrefs.all
    }
    
    val mnemonic = if (userId.isNotEmpty()) {
        getMnemonicFromKeystore(context, userId, walletName)
    } else {
        ""
    }

    BackHandler {
        try {
            navController.navigate("wallets") {
                popUpTo("wallet") { inclusive = true }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    MainLayout(navController = navController) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.White)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color(0xFFFDFDFD))
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Spacer(modifier = Modifier.height(20.dp))

                Image(
                    painter = painterResource(id = R.drawable.shild),
                    contentDescription = "Shield Icon",
                    modifier = Modifier
                        .size(250.dp)
                        .padding(16.dp),
                    contentScale = ContentScale.Fit
                )

                Spacer(modifier = Modifier.height(16.dp))

                CheckBoxWithText(
                    isChecked = checkbox1,
                    text = "Coinceeper does not keep a copy of your secret phrase.",
                    onCheckedChange = { checkbox1 = it }
                )
                CheckBoxWithText(
                    isChecked = checkbox2,
                    text = "Saving this digitally in plain text is NOT recommended.",
                    onCheckedChange = { checkbox2 = it }
                )
                CheckBoxWithText(
                    isChecked = checkbox3,
                    text = "Write down your secret phrase and store it in a secure offline location.",
                    onCheckedChange = { checkbox3 = it }
                )

                Spacer(modifier = Modifier.weight(1f))

                Button(
                    onClick = {
                        if (allChecked) {
                            val currentUserId = getUserIdFromKeystore(context, walletName)
                            val encodedWalletName = java.net.URLEncoder.encode(walletName, "UTF-8")
                            val navigationRoute = "phrasekey?userId=$currentUserId&walletName=$encodedWalletName"
                            navController.navigate(navigationRoute)
                        }
                    },
                    enabled = allChecked,
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(
                        backgroundColor = if (allChecked) Color(0xFF005FEE) else Color.Gray,
                        contentColor = Color.White
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp)
                ) {
                    Text(text = "Continue", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                }

                Spacer(modifier = Modifier.height(16.dp))
            }
        }
    }
}

@Composable
fun CheckBoxWithText(isChecked: Boolean, text: String, onCheckedChange: (Boolean) -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 10.dp)
            .background(if (isChecked) Color(0x0D16B369) else Color(0x43CBCBCB), shape = RoundedCornerShape(15.dp))
            .clickable { onCheckedChange(!isChecked) }
    ) {
        Spacer(modifier = Modifier.width(15.dp))

        Box(
            modifier = Modifier
                .size(20.dp)
                .clip(CircleShape)
                .background(if (isChecked) Color(0xFF1CC89F) else Color.LightGray),
            contentAlignment = Alignment.Center
        ) {
            if (isChecked) {
                Icon(
                    imageVector = Icons.Default.Check,
                    contentDescription = "Checked",
                    tint = Color.White,
                    modifier = Modifier.size(16.dp)
                )
            }
        }

        Spacer(modifier = Modifier.width(8.dp))

        Text(
            text = text,
            fontSize = 14.sp,
            color = Color.Black,
            modifier = Modifier
                .weight(1f)
                .padding(start = 10.dp, end = 15.dp, top = 20.dp, bottom = 20.dp)
        )
    }
}

