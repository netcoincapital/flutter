package com.laxce.adl.ui.theme.screen

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Icon
import androidx.compose.material.IconButton
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.R
import androidx.activity.compose.BackHandler
import androidx.compose.material.Button
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.laxce.adl.ui.theme.layout.MainLayout
import com.laxce.adl.utility.getMnemonicFromKeystore
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import com.laxce.adl.utility.getUserIdFromKeystore
import android.util.Log
import androidx.compose.material.*
import androidx.compose.runtime.*

@Composable
fun PhraseKeyScreen(
    navController: NavController,
    walletName: String,
    showCopy: Boolean
) {
    val context = LocalContext.current
    val decodedWalletName = URLDecoder.decode(walletName, StandardCharsets.UTF_8.toString())

    val userId = remember(decodedWalletName) {
        getUserIdFromKeystore(context, decodedWalletName)
    }

    LaunchedEffect(Unit) {
        val window = (context as? android.app.Activity)?.window
        window?.setFlags(
            android.view.WindowManager.LayoutParams.FLAG_SECURE,
            android.view.WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    DisposableEffect(Unit) {
        onDispose {
            val window = (context as? android.app.Activity)?.window
            window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    BackHandler {
        try {
            navController.navigate("wallets") {
                popUpTo("wallets") { inclusive = true }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    var mnemonic by remember { mutableStateOf("No Mnemonic found") }

    LaunchedEffect(userId, decodedWalletName) {
        try {
            val retrievedMnemonic = getMnemonicFromKeystore(context, userId, decodedWalletName)
            if (retrievedMnemonic != null) {
                mnemonic = retrievedMnemonic
                Log.d("PhraseKey", "Successfully retrieved mnemonic for wallet: $decodedWalletName")
            } else {
                Log.e("PhraseKey", "Failed to retrieve mnemonic for wallet: $decodedWalletName")
            }
        } catch (e: Exception) {
            Log.e("PhraseKey", "Error retrieving mnemonic: ${e.message}")
        }
    }

    val mnemonicWords = mnemonic.split(" ")

    MainLayout(navController = navController) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.White)
                .padding(16.dp)
        ) {
            Text(
                text = "Mnemonic for $decodedWalletName",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.Black,
                modifier = Modifier.padding(bottom = 16.dp)
            )

            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                for (i in mnemonicWords.indices step 2) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        PhraseCard(
                            number = i + 1,
                            word = mnemonicWords[i],
                            modifier = Modifier.weight(1f).padding(end = 4.dp)
                        )
                        if (i + 1 < mnemonicWords.size) {
                            PhraseCard(
                                number = i + 2,
                                word = mnemonicWords[i + 1],
                                modifier = Modifier.weight(1f).padding(start = 4.dp)
                            )
                        }
                    }
                }
            }

            if (showCopy) {
                Button(
                    onClick = {
                        // Copy mnemonic code
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(65.dp)
                        .padding(top = 15.dp),
                    colors = androidx.compose.material.ButtonDefaults.buttonColors(
                        backgroundColor = Color(0xFF08C495),
                        contentColor = Color.White
                    ),
                    shape = RoundedCornerShape(50.dp)
                ) {
                    Text(
                        "Copy Mnemonic",
                        color = Color.White,
                        fontWeight = FontWeight.Black
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFFFFF4E5), shape = RoundedCornerShape(8.dp))
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Icon(
                    painter = painterResource(id = R.drawable.danger),
                    contentDescription = "Warning",
                    tint = Color(0xFFFFAA00),
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Never share your secret phrase with anyone, and store it securely!",
                    fontSize = 12.sp,
                    color = Color.Black,
                    modifier = Modifier.weight(1f).padding(end = 20.dp)
                )
                IconButton(onClick = { /* Next page */ }) {
                    Icon(
                        painter = painterResource(id = R.drawable.rightarrow),
                        contentDescription = "Next",
                        tint = Color.Black,
                        modifier = Modifier.size(20.dp)
                    )
                }
            }
        }
    }
}

@Composable
fun PhraseCard(number: Int, word: String, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(Color(0xFFF0F0F0), shape = RoundedCornerShape(8.dp))
            .padding(18.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = "$number. $word",
            fontSize = 12.sp,
            color = Color.Black,
            textAlign = TextAlign.Center
        )
    }
}
