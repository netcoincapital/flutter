package com.laxce.adl.ui.theme.screen

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import com.laxce.adl.R
import com.laxce.adl.ui.theme.layout.MainLayout
import androidx.compose.foundation.Image
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.runtime.*
import com.laxce.adl.utility.generateCircleQRCode
import kotlinx.coroutines.delay
import androidx.compose.material3.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.core.content.FileProvider
import com.laxce.adl.utility.fetchPricesWithCache
import com.laxce.adl.utility.getSelectedCurrency
import com.laxce.adl.utility.loadPriceFromKeystore
import com.google.gson.Gson
import java.io.File

@Composable
fun ReceiveWalletScreen(
    navController: NavController,
    cryptoName: String,
    blockchainName: String,
    userId: String,
    publicAddress: String,
    symbol: String
) {
    val price = navController.previousBackStackEntry?.arguments?.getString("price") ?: "0.0"

    MainLayout(navController = navController) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.White)
                .padding(start = 16.dp, top = 40.dp, end = 16.dp, bottom = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFFFFF4E5), RoundedCornerShape(8.dp))
                    .padding(16.dp)
            ) {
                Row {
                    Icon(
                        painter = painterResource(id = R.drawable.danger),
                        contentDescription = "Warning",
                        tint = Color(0xFFE68A00),
                        modifier = Modifier.size(28.dp).padding(end = 8.dp)
                    )
                    Text(
                        text = "Only send ($blockchainName) assets to this address.\nOther assets will be lost forever.",
                        style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                        color = Color(0xFFE68A00),
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            QRCodeScreen(
                publicAddress = publicAddress,
                cryptoName = cryptoName,
                blockchainName = blockchainName,
                iconUrl = "https://coinceeper.com/defualtIcons/coin.png",
                symbol = symbol
            )
        }
    }
}

@Composable
fun ActionButton(iconRes: Int, label: String, context: android.content.Context, onClick: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.clickable(
            indication = null,
            interactionSource = remember { MutableInteractionSource() }
        ) {
            onClick()
        }
    ) {
        Icon(
            painter = painterResource(id = iconRes),
            contentDescription = label,
            modifier = Modifier.size(36.dp),
            tint = Color.Unspecified
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = label,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = Color.Black
        )
    }
}

@Composable
fun QRCodeScreen(publicAddress: String, cryptoName: String, blockchainName: String, iconUrl: String?, symbol: String) {
    val context = LocalContext.current
    val clipboardManager = androidx.compose.ui.platform.LocalClipboardManager.current

    var amount by remember { mutableStateOf("") }
    var isDialogOpen by remember { mutableStateOf(false) }
    var price by remember { mutableStateOf(0.0) }
    val gson = com.google.gson.Gson()

    LaunchedEffect(symbol) {
        val gson = Gson()
        val selectedCurrency = getSelectedCurrency(context)

        price = loadPriceFromKeystore(context, symbol, "USD")

        if (price == 0.0) {
            try {
                val pricesMap = fetchPricesWithCache(
                    context = context,
                    gson = gson,
                    selectedCurrency = selectedCurrency,
                    activeSymbols = listOf(symbol),
                    fiatCurrencies = listOf(selectedCurrency)
                )

                val fetchedPriceString = pricesMap[symbol]?.get(selectedCurrency)?.split(" ")?.firstOrNull()
                val fetchedPrice = fetchedPriceString?.replace(",", "")?.trim()?.toDoubleOrNull() ?: 0.0

                if (fetchedPrice > 0) {
                    price = fetchedPrice
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    val calculatedPrice = amount.toDoubleOrNull()?.times(price) ?: 0.0

    val qrCodeBitmap = generateCircleQRCode(
        context = context,
        text = if (amount.isEmpty()) publicAddress else "$publicAddress?amount=$amount",
        size = 1080,
        logoResId = R.drawable.logo,
        logoWidth = 100f,
        logoHeight = 70f
    )

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .padding(16.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                text = cryptoName,
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = blockchainName,
                color = Color.Gray,
                fontSize = 14.sp
            )
        }

        Box(
            modifier = Modifier
                .size(360.dp)
                .shadow(
                    elevation = 8.dp,
                    shape = RoundedCornerShape(16.dp),
                    clip = false
                )
                .background(Color(0xFFFFFFFF), RoundedCornerShape(16.dp)),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                qrCodeBitmap?.let {
                    Image(
                        bitmap = it.asImageBitmap(),
                        contentDescription = "Circle QR Code",
                        modifier = Modifier.size(300.dp)
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                Text(
                    text = publicAddress,
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                    color = Color.Black,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                        .clickable {
                            clipboardManager.setText(androidx.compose.ui.text.AnnotatedString(publicAddress))
                        }
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        if (amount.isNotEmpty()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(top = 8.dp, bottom = 16.dp)
            ) {
                val formattedPrice = String.format("%.2f", calculatedPrice)

                Text(
                    text = "$amount $cryptoName ≈ $$formattedPrice",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.Black
                )
                Spacer(modifier = Modifier.width(8.dp))
                Icon(
                    painter = painterResource(id = R.drawable.cancel),
                    contentDescription = "Clear Amount",
                    modifier = Modifier
                        .size(20.dp)
                        .clickable {
                            amount = ""
                        },
                    tint = Color.Gray
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            ActionButton(
                iconRes = R.drawable.ic_copy,
                label = "Copy",
                context = context,
                onClick = {
                    clipboardManager.setText(androidx.compose.ui.text.AnnotatedString(publicAddress))
                }
            )

            ActionButton(
                iconRes = R.drawable.ic_set_amount,
                label = "Set Amount",
                context = context,
                onClick = {
                    isDialogOpen = true
                }
            )

            ActionButton(
                iconRes = R.drawable.share,
                label = "Share",
                context = context,
                onClick = {
                    shareQRCodeAndAddress(context, publicAddress, qrCodeBitmap)
                }
            )
        }

        if (isDialogOpen) {
            AlertDialog(
                onDismissRequest = { isDialogOpen = false },
                confirmButton = {
                    Button(
                        onClick = {
                            isDialogOpen = false
                        }
                    ) {
                        Text("OK")
                    }
                },
                dismissButton = {
                    Button(onClick = {
                        isDialogOpen = false
                    }) {
                        Text("Cancel")
                    }
                },
                title = {
                    Text(text = "Enter Amount")
                },
                text = {
                    TextField(
                        value = amount,
                        onValueChange = { amount = it },
                        label = { Text("Amount") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true
                    )
                }
            )
        }
    }
}

fun shareQRCodeAndAddress(context: android.content.Context, publicAddress: String, qrCodeBitmap: Bitmap?) {
    qrCodeBitmap?.let { bitmap ->
        val file = File(context.cacheDir, "qrcode.png")
        file.outputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        }

        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.provider",
            file
        )

        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "image/*"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TEXT, "Public Address: $publicAddress")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        context.startActivity(Intent.createChooser(shareIntent, "Share via"))
    }
}

@Composable
fun DynamicQRCode(publicAddressBase: String, cryptoName: String, blockchainName: String, symbol: String) {
    var dynamicAddress by remember { mutableStateOf(publicAddressBase) }

    LaunchedEffect(Unit) {
        while (true) {
            delay(5000L)
            dynamicAddress = generateNewAddress()
        }
    }

    QRCodeScreen(
        publicAddress = dynamicAddress,
        cryptoName = cryptoName,
        blockchainName = blockchainName,
        iconUrl = "https://coinceeper.com/defualtIcons/coin.png",
        symbol = symbol
    )
}

fun generateNewAddress(): String {
    val randomSuffix = (1000..9999).random()
    return "0xF0F3d4dD1b8A86f4Fe65401524701915F00b4E3B-$randomSuffix"
}

@Preview(showBackground = true)
@Composable
fun PreviewDynamicQRCode() {
    DynamicQRCode(
        publicAddressBase = "0xF0F3d4dD1b8A86f4Fe65401524701915F00b4E3B",
        cryptoName = "ETH",
        blockchainName = "Ethereum",
        symbol = "ETH"
    )
}


