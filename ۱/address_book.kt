package com.laxce.adl.ui.theme.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.compose.ui.text.font.FontWeight
import com.laxce.adl.R
import com.laxce.adl.utility.loadWalletsFromKeystore
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.graphics.Brush

@Composable
fun AddressBook(navController: NavController) {
    val context = navController.context
    val wallets = loadWalletsFromKeystore(context)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .padding(16.dp)
    ) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "Address Book",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
            Icon(
                painter = painterResource(id = R.drawable.plus),
                contentDescription = "Add Wallet",
                modifier = Modifier
                    .padding(end = 18.dp)
                    .size(16.dp)
                    .clickable {
                        navController.navigate("addaddress")
                    },
                tint = Color(0x99757575)
            )
        }

        if (wallets.isEmpty()) {
            // Placeholder Content
            Spacer(modifier = Modifier.weight(0.5f))
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Icon(
                    painter = painterResource(id = R.drawable.addaddress), // Placeholder image
                    contentDescription = "Wallet Placeholder",
                    modifier = Modifier.size(200.dp),
                    tint = Color.Unspecified
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "Your contacts and their wallet address will appear here.",
                    fontSize = 14.sp,
                    color = Color.Gray,
                    textAlign = TextAlign.Center
                )
            }
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(0.5f),
                contentAlignment = Alignment.Center
            ) {
                Button(
                    onClick = {
                        navController.navigate("addaddress")
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .align(Alignment.Center)
                        .height(48.dp),
                    shape = RoundedCornerShape(25.dp),
                    colors = ButtonDefaults.buttonColors(
                        backgroundColor = Color(0xFF16B369),
                        contentColor = Color.White
                    )
                ) {
                    Text(
                        text = "Add wallet address",
                        fontSize = 16.sp
                    )
                }
            }
            Spacer(modifier = Modifier.height(150.dp))
        } else {
            // Wallets List
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(0.dp)


            ) {
                items(wallets) { wallet ->
                    WalletItem(
                        walletName = wallet.first,
                        walletAddress = wallet.second,
                        onWalletClick = { walletName, walletAddress ->
                            navController.navigate(
                                "editWallet/${walletName}/${walletAddress}"
                            )
                        }
                    )
                    Spacer(modifier = Modifier.height(0.dp))
                }
            }
        }
    }
}

@Composable
fun WalletItem(
    walletName: String,
    walletAddress: String,
    onWalletClick: (String, String) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(8.dp)
            .clickable { onWalletClick(walletName, walletAddress) }
            .background(
    brush = Brush.linearGradient(
        colors = listOf(
            Color(0xFF08C495),
            Color(0xFF39b6fb)
        )
        ),
        shape = RoundedCornerShape(12.dp)
    )

            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = walletName,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
            Text(
                text = walletAddress,
                fontSize = 14.sp,
                color = Color.White
            )
        }

        Icon(
            painter = painterResource(id = R.drawable.rightarrow), // جایگزین با آیکون دلخواه
            contentDescription = "More Options",
            modifier = Modifier.size(24.dp),
            tint = Color.White
        )
    }
}

