package com.laxce.adl.ui.theme.screen

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.graphics.drawable.toBitmap
import androidx.navigation.NavController
import androidx.palette.graphics.Palette
import coil.ImageLoader
import coil.compose.AsyncImage
import coil.request.ImageRequest
import coil.request.SuccessResult
import com.laxce.adl.R
import com.laxce.adl.api.ReceiveRequest
import com.laxce.adl.api.RetrofitClient
import com.laxce.adl.classes.CryptoToken
import com.laxce.adl.ui.theme.layout.LoadingOverlay
import com.laxce.adl.ui.theme.layout.MainLayout
import com.laxce.adl.utility.fetchPricesWithCache
import com.laxce.adl.utility.getCurrencySymbol
import com.laxce.adl.utility.getSelectedCurrency
import com.laxce.adl.utility.getUserIdFromKeystore
import com.laxce.adl.utility.loadSelectedWallet
import com.google.gson.Gson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.google.accompanist.swiperefresh.SwipeRefresh
import com.google.accompanist.swiperefresh.rememberSwipeRefreshState
import kotlinx.coroutines.delay
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.Image
import androidx.compose.foundation.shape.RoundedCornerShape
import com.laxce.adl.api.Api
import com.laxce.adl.api.BalanceRequest
import com.laxce.adl.api.Transaction
import com.laxce.adl.api.TransactionsRequest
import com.laxce.adl.utility.formatAmount
import com.laxce.adl.viewmodel.token_view_model
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import com.laxce.adl.utility.LocalTransactionCache
import androidx.compose.ui.layout.ContentScale

@Composable
fun TokenDetailsScreen(
    navController: NavController,
    tokenName: String,
    tokenSymbol: String,
    iconUrl: String,
    token: CryptoToken,
    gasFee: String
) {

    val formattedGasFee = try {
        // Try to parse gas fee - if it's in scientific notation, convert it
        val parsedFee = if (gasFee.contains("E") || gasFee.contains("e")) {
            gasFee.toDouble().toString()
        } else {
            gasFee
        }
        
        // Format to 2 decimal places for display
        "%.2f".format(parsedFee.toDouble())
    } catch (e: Exception) {
        "0.00" // Default value in case of error
    }

    val context = LocalContext.current
    var backgroundColor by remember { mutableStateOf(Color(0x80D7FBE7)) } // Default background color
    val selectedCurrency = getSelectedCurrency(context)
    val currencySymbol = getCurrencySymbol(selectedCurrency)
    var localGasFee by remember { mutableStateOf(formattedGasFee) }
    val coroutineScope = rememberCoroutineScope()
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    var price by remember { mutableStateOf(0.0) }
    var isRefreshing by remember { mutableStateOf(false) }
    val swipeRefreshState = rememberSwipeRefreshState(isRefreshing)
    var isLoading by remember { mutableStateOf(false) } // Main loading state for actions
    var isTransactionLoading by remember { mutableStateOf(false) } // Loading state for transactions
    val walletName = remember { loadSelectedWallet(context) }
    val userId = remember { getUserIdFromKeystore(context, walletName) }
    val tokenViewModel = remember(userId) {
        token_view_model(context, userId)
    }
    var updatedAmount by remember { mutableStateOf(0.0) }

    // When token changes, also fetch the latest gas fee
    LaunchedEffect(tokenSymbol, tokenViewModel) {
        if (tokenSymbol == "ETH" || tokenSymbol == "BTC") {
            try {
                // Fetch fresh gas fees
                tokenViewModel.fetchGasFees()
                
                // Now get the updated fee from the state
                val blockchainName = if (tokenSymbol == "ETH") "Ethereum" else "Bitcoin" 
                val updatedFee = tokenViewModel.gasFees.value[blockchainName] ?: gasFee
                
                if (updatedFee != "0.0") {
                    try {
                        localGasFee = "%.2f".format(updatedFee.toDouble())
                    } catch (e: Exception) {
                        // Error handling
                    }
                } else {
                    // Use default values if still 0.0
                    val defaultFee = if (tokenSymbol == "ETH") "0.0012" else "0.0001"
                    localGasFee = defaultFee
                }
            } catch (e: Exception) {
                // Error handling
            }
        }
    }

    LaunchedEffect(tokenSymbol) {
        val api = RetrofitClient.getInstance(context).create(Api::class.java)
        val gson = Gson()

        try {
            // Get balance
            val balanceResponse = api.getBalance(
                BalanceRequest(
                    userId = userId.orEmpty(),
                    currencyNames = listOf(tokenSymbol),
                    blockchain = emptyMap()
                )
            )

            updatedAmount = balanceResponse.balances
                ?.find { it.symbol.equals(tokenSymbol, ignoreCase = true) }
                ?.balance
                ?.toDoubleOrNull() ?: 0.0

            // Get price
            val prices = fetchPricesWithCache(
                context = context,
                gson = gson,
                selectedCurrency = selectedCurrency,
                activeSymbols = listOf(tokenSymbol),
                fiatCurrencies = listOf(selectedCurrency)
            )
            val tokenPriceMap = prices[tokenSymbol]
            val matchedEntry = tokenPriceMap?.entries?.find {
                it.key.equals(selectedCurrency, ignoreCase = true)
            }
            val rawPrice = matchedEntry?.value?.replace(",", "")
            price = rawPrice?.toDoubleOrNull() ?: 0.0

        } catch (e: Exception) {
            // Error handling
        }
    }

    fun Double.format(digits: Int) = "%.${digits}f".format(this)

    fun refreshData() {
        coroutineScope.launch {
            isRefreshing = true
            val gson = Gson()
            try {
                val activeSymbols = listOf(tokenSymbol)
                val selectedCurrency = getSelectedCurrency(context)
                val fiatCurrencies = listOf(selectedCurrency)

                val prices = fetchPricesWithCache(
                    context = context,
                    gson = gson,
                    selectedCurrency = selectedCurrency,
                    activeSymbols = activeSymbols,
                    fiatCurrencies = fiatCurrencies
                )

                val tokenPriceMap = prices[tokenSymbol]
                val matchedEntry = tokenPriceMap?.entries?.find {
                    it.key.equals(selectedCurrency, ignoreCase = true)
                }
                val rawPrice = matchedEntry?.value?.replace(",", "")
                price = rawPrice?.toDoubleOrNull() ?: 0.0

            } catch (e: Exception) {
                // Error handling
            } finally {
                isRefreshing = false
            }
        }
    }

    // Extract dominant color from the token icon
    LaunchedEffect(iconUrl) {
        val bitmap = loadBitmapFromUrl(context, iconUrl)
        bitmap?.let {
            val palette = Palette.from(it).generate()
            val dominantColor = palette.getDominantColor(0xFFD7FBE7.toInt())
            backgroundColor = Color(dominantColor).copy(alpha = 0.1f) // Set transparency to 50%
        }
    }

    MainLayout(navController = navController) {
        SwipeRefresh(
            state = swipeRefreshState,
            onRefresh = { refreshData() }
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.White)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    // Header Section
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 16.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Icon(Icons.Default.Notifications, contentDescription = "Notifications", tint = Color.Gray)
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(text = tokenName, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                            Text(
                                text = "${if (token.isToken) "Token" else "Coin"}  ||  $tokenSymbol",
                                fontSize = 14.sp,
                                color = Color.Gray
                            )
                        }
                        Icon(Icons.Default.Info, contentDescription = "Info", tint = Color.Gray)
                    }

                    // Token Icon and Info
                    Spacer(modifier = Modifier.height(16.dp))

                    // Token Icon (center)
                    Box(
                        modifier = Modifier
                            .size(72.dp)
                            .background(backgroundColor, shape = CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        AsyncImage(
                            model = iconUrl,
                            contentDescription = "Token Icon",
                            placeholder = painterResource(id = R.drawable.coin),
                            error = painterResource(id = R.drawable.coin),
                            modifier = Modifier
                                .size(52.dp)
                                .clip(CircleShape),
                            contentScale = ContentScale.Crop
                        )
                    }
                    if (tokenSymbol == "ETH" || tokenSymbol == "BTC") {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 10.dp),
                            horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(
                                horizontalArrangement = Arrangement.Center,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    painter = painterResource(id = R.drawable.gas),
                                    contentDescription = "Gas Icon",
                                    tint = Color.Unspecified,
                                    modifier = Modifier.size(24.dp)
                                )

                                Spacer(modifier = Modifier.width(4.dp))
                                Text(
                                    text = "$currencySymbol $localGasFee",
                                    fontSize = 14.sp,
                                    color = Color.Gray,
                                    fontWeight = FontWeight.Normal
                                )
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    Text(
                        text = "${formatAmount(updatedAmount, price)} $tokenSymbol",
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Bold
                    )

                    Text(
                        text = "≈ $currencySymbol ${(updatedAmount * price).format(2)}",
                        fontSize = 18.sp,
                        color = Color.Gray
                    )

                    Spacer(modifier = Modifier.height(16.dp))

                    // Action Buttons
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceAround
                    ) {
                        ActionButton(iconRes = R.drawable.send, label = "Send", color = Color(0x80D7FBE7)) {
                            // Send button action
                        }

                        ActionButton(iconRes = R.drawable.receive, label = "Receive", color = Color(0xFFE0F7FA)) {
                            coroutineScope.launch {
                                isLoading = true

                                val api = RetrofitClient.getInstance(context).create(Api::class.java)

                                val correctedBlockchainName = token.BlockchainName.replace("Blockchain ", "")
                                val request = ReceiveRequest(UserID = userId, BlockchainName = correctedBlockchainName)

                                try {
                                    val response = api.receiveToken(request)

                                    if (response.success && response.PublicAddress != null) {
                                        withContext(Dispatchers.Main) {
                                            navController.navigate(
                                                "receive_wallet/${Uri.encode(token.name)}/${Uri.encode(correctedBlockchainName)}/${Uri.encode(userId)}/${Uri.encode(response.PublicAddress ?: "")}/${Uri.encode(token.symbol)}"
                                            )
                                        }
                                    } else {
                                        isLoading = false
                                    }
                                } catch (e: retrofit2.HttpException) {
                                    isLoading = false
                                } catch (e: Exception) {
                                    isLoading = false
                                } finally {
                                    withContext(Dispatchers.Main) {
                                        delay(500)
                                        isLoading = false
                                    }
                                }
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // Transaction History
                    TokenTransactionsSection(
                        userId = userId.orEmpty(), 
                        tokenSymbol = tokenSymbol,
                        blockchainName = token.BlockchainName,
                        isToken = token.isToken,
                        onLoadingChanged = { isTransactionLoading = it },
                        navController = navController
                    )
                }
            }
            LoadingOverlay(isLoading || isTransactionLoading)
        }
    }
}

@Composable
fun ActionButton(iconRes: Int, label: String, color: Color, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(60.dp)
                .background(color, shape = CircleShape)
                .clickable { onClick() }, // اطمینان از فراخوانی درست
            contentAlignment = Alignment.Center
        ) {
            Icon(
                painter = painterResource(id = iconRes),
                contentDescription = label,
                tint = Color.Unspecified,
                modifier = Modifier.size(24.dp)
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(label, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.Black)
    }
}

@Composable
fun TokenTransactionsSection(
    userId: String,
    tokenSymbol: String,
    blockchainName: String,
    isToken: Boolean,
    onLoadingChanged: (Boolean) -> Unit,
    navController: NavController
) {
    val context = LocalContext.current
    var transactions by remember { mutableStateOf<List<Transaction>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val localPendingTransactions = LocalTransactionCache.pendingTransactions

    // Notify parent about loading state changes
    LaunchedEffect(isLoading) {
        onLoadingChanged(isLoading)
    }

    LaunchedEffect(tokenSymbol) {
        try {
            isLoading = true
            val api = RetrofitClient.getInstance(context).create(Api::class.java)
            
            // Filter by tokenSymbol matching the Transaction's tokenSymbol field
            val response = api.getTransactions(TransactionsRequest(UserID = userId))
            // آپدیت تراکنش لوکال با اطلاعات سرور (در صورت وجود)
            response.transactions?.forEach { serverTx ->
                val matchedPending = LocalTransactionCache.pendingTransactions.find {
                    it.txHash == serverTx.txHash
                }
                if (matchedPending != null) {
                    serverTx.temporaryId = matchedPending.temporaryId
                }
                LocalTransactionCache.updateById(serverTx.txHash, serverTx)
                LocalTransactionCache.matchAndReplacePending(serverTx)
            }
            transactions = response.transactions?.filter {
                it.tokenSymbol.equals(tokenSymbol, ignoreCase = true)
            } ?: emptyList()
            isLoading = false
        } catch (e: Exception) {
            errorMessage = e.message
            isLoading = false
        }
    }

    // ترکیب تراکنش‌های لوکال و سرور
    val allTransactions = (localPendingTransactions + transactions)
        .distinctBy { it.txHash }
        .filter { it.tokenSymbol.equals(tokenSymbol, ignoreCase = true) }
        .sortedByDescending { it.timestamp }

    Column(modifier = Modifier.fillMaxWidth()) {
        // Replace the text header with a divider
        Divider(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 16.dp),
            color = Color(0xFFE0E0E0),
            thickness = 1.dp
        )

        when {
            // Remove the loading case since we're using LoadingOverlay
            !errorMessage.isNullOrEmpty() -> {
                Text(errorMessage!!, color = Color.Red, modifier = Modifier.padding(8.dp))
            }
            allTransactions.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(200.dp)
                        .padding(16.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Image(
                            painter = painterResource(id = R.drawable.notransaction),
                            contentDescription = "No Transactions",
                            modifier = Modifier
                                .size(100.dp)
                                .align(Alignment.CenterHorizontally)
                        )
                        
                        Spacer(modifier = Modifier.height(16.dp))
                        
                        Text(
                            text = "No transactions found",
                            fontSize = 16.sp,
                            color = Color.Gray
                        )
                    }
                }
            }
            else -> {
                // Group transactions by date
                val groupedTransactions = allTransactions.groupBy { transaction ->
                    try {
                        val dateTime = LocalDateTime.parse(transaction.timestamp, DateTimeFormatter.ISO_DATE_TIME)
                        val today = LocalDateTime.now()
                        val yesterday = today.minusDays(1)
                        
                        when {
                            dateTime.toLocalDate().isEqual(today.toLocalDate()) -> "Today"
                            dateTime.toLocalDate().isEqual(yesterday.toLocalDate()) -> "Yesterday"
                            else -> dateTime.format(DateTimeFormatter.ofPattern("MMM d, yyyy"))
                        }
                    } catch (e: Exception) {
                        "Unknown Date"
                    }
                }

                LazyColumn(modifier = Modifier.fillMaxWidth()) {
                    groupedTransactions.forEach { (date, transactionsForDate) ->
                        item { 
                            // Call HistoryDateHeader imported from History.kt
                            com.laxce.adl.ui.theme.screen.HistoryDateHeader(date) 
                        }
                        
                        items(transactionsForDate) { transaction ->
                            val isReceived = transaction.direction == "inbound"
                            val direction = if (isReceived) "From: " else "To: "
                            val address = if (isReceived) transaction.from else transaction.to
                            val shortAddress = if (address.length > 15) {
                                "${address.take(10)}...${address.takeLast(5)}"
                            } else {
                                address
                            }
                            val amountPrefix = if (isReceived) "+" else "-"
                            val formattedAmount = formatAmount(transaction.amount)
                            val amountValue = "$amountPrefix$formattedAmount"

                            // Simple estimation for USD value
                            val fiatValue = try {
                                val price = transaction.price.toDoubleOrNull()
                                if (price != null && price > 0.0) {
                                    "≈ $${String.format("%.2f", price)}"
                                } else {
                                    "≈ $0.00"
                                }
                            } catch (e: Exception) {
                                "≈ $0.00"
                            }

                            // Call HistoryTransactionItem imported from History.kt
                            com.laxce.adl.ui.theme.screen.HistoryTransactionItem(
                                type = if (isReceived) "Receive" else "Send",
                                address = "$direction$shortAddress",
                                amountValue = amountValue,
                                tokenSymbol = transaction.tokenSymbol,
                                fiat = fiatValue,
                                isReceived = isReceived,
                                status = transaction.status,
                                onClick = {
                                    // Navigate to transaction detail screen
                                    val date = try {
                                        val dateTime = LocalDateTime.parse(transaction.timestamp, DateTimeFormatter.ISO_DATE_TIME)
                                        dateTime.format(DateTimeFormatter.ofPattern("MMM d, yyyy, h:mm a"))
                                    } catch (e: Exception) {
                                        "Unknown Date"
                                    }
                                    
                                    val status = "Completed"
                                    val sender = if (isReceived) transaction.from else transaction.to
                                    val networkFee = "0 ${transaction.tokenSymbol}"
                                    
                                    val route = "transaction_detail/" +
                                        "${Uri.encode(amountValue)}/" +
                                        "${Uri.encode(transaction.tokenSymbol)}/" +
                                        "${Uri.encode(fiatValue)}/" +
                                        "${Uri.encode(date)}/" +
                                        "${Uri.encode(status)}/" +
                                        "${Uri.encode(sender)}/" +
                                        "${Uri.encode(networkFee)}/" +
                                        "${Uri.encode(transaction.txHash)}"
                                    
                                    navController.navigate(route)
                                }
                            )
                        }
                    }
                    
                    item {
                        Spacer(modifier = Modifier.height(24.dp))
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(
                                    color = Color(0x0F1BCAA0),
                                    shape = RoundedCornerShape(8.dp)
                                )
                                .padding(12.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Row {
                                Text(
                                    text = "Cannot find your transaction? ",
                                    color = Color.Gray,
                                    fontSize = 14.sp
                                )
                                Text(
                                    text = "Check explorer",
                                    color = Color(0xFF11c699),
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Medium,
                                    modifier = Modifier.clickable {
                                        val explorerUrl = getBlockchainExplorerUrl(blockchainName, tokenSymbol, isToken)
                                        try {
                                            // هدایت به صفحه WebView داخلی به جای استفاده از Custom Tab
                                            navController.navigate("web_view/${Uri.encode(explorerUrl)}")
                                        } catch (e: Exception) {
                                            // Error handling
                                        }
                                    }
                                )
                            }
                        }
                        Spacer(modifier = Modifier.height(32.dp))
                    }
                }
            }
        }
    }
}

// Helper function to format amount by removing trailing zeros
private fun formatAmount(amount: String): String {
    return try {
        val number = amount.toBigDecimal().stripTrailingZeros()
        val plain = number.toPlainString()

        // اگر عدد اعشاری هست، فقط تا 6 رقم بعد از ممیز نگه‌دار
        if (plain.contains(".")) {
            val parts = plain.split(".")
            val integer = parts[0]
            val decimal = parts[1].take(6).trimEnd('0') // حداکثر 6 رقم اعشار

            if (decimal.isNotEmpty()) "$integer.$decimal" else integer
        } else {
            plain // عدد صحیح
        }
    } catch (e: Exception) {
        amount
    }
}

// Helper function to get blockchain explorer URL
fun getBlockchainExplorerUrl(blockchainName: String, symbol: String, isToken: Boolean = true): String {
    val normalizedBlockchain = blockchainName.lowercase().replace("blockchain ", "")
    
    // Handle native coins (not tokens)
    if (!isToken) {
        return when (normalizedBlockchain) {
            "ethereum" -> "https://etherscan.io/"
            "bitcoin" -> "https://www.blockchain.com/explorer/assets/btc"
            "bnb smart chain", "bsc", "binance smart chain" -> "https://bscscan.com/"
            "tron" -> "https://tronscan.org/"
            "polygon" -> "https://polygonscan.com/"
            "solana" -> "https://solscan.io/"
            "avalanche" -> "https://snowtrace.io/"
            "ripple", "xrp" -> "https://xrpscan.com/"
            "arbitrum", "arbitrum one" -> "https://arbiscan.io/"
            "polkadot" -> "https://polkadot.subscan.io/"
            "cardano" -> "https://cardanoscan.io/"
            "cosmos" -> "https://www.mintscan.io/cosmos"
            "algorand" -> "https://algoexplorer.io/"
            "near" -> "https://explorer.near.org/"
            "fantom" -> "https://ftmscan.com/"
            "optimism" -> "https://optimistic.etherscan.io/"
            "cronos" -> "https://cronoscan.com/"
            "hedera" -> "https://hashscan.io/mainnet/dashboard"
            "vechain" -> "https://explore.vechain.org/"
            "aptos" -> "https://explorer.aptoslabs.com/"
            "sui" -> "https://explorer.sui.io/"
            "base" -> "https://basescan.org/"
            "zksync era" -> "https://explorer.zksync.io/"
            "stellar", "xlm" -> "https://stellar.expert/explorer/public"
            else -> "https://coinmarketcap.com/currencies/${symbol.lowercase()}"
        }
    }
    
    // Special cases for native tokens that would normally be treated as coins
    // This section is likely not needed with the isToken check above but kept for safety
    if (normalizedBlockchain == "ethereum" && symbol.equals("eth", ignoreCase = true)) {
        return "https://etherscan.io/"
    } else if (normalizedBlockchain == "bitcoin" && symbol.equals("btc", ignoreCase = true)) {
        return "https://www.blockchain.com/explorer/assets/btc"
    } else if ((normalizedBlockchain == "bnb smart chain" || normalizedBlockchain == "bsc" || 
               normalizedBlockchain == "binance smart chain") && symbol.equals("bnb", ignoreCase = true)) {
        return "https://bscscan.com/"
    } else if (normalizedBlockchain == "tron" && symbol.equals("trx", ignoreCase = true)) {
        return "https://tronscan.org/"
    } else if (normalizedBlockchain == "polygon" && symbol.equals("matic", ignoreCase = true)) {
        return "https://polygonscan.com/"
    } else if (normalizedBlockchain == "solana" && symbol.equals("sol", ignoreCase = true)) {
        return "https://solscan.io/"
    }
    
    // Handle tokens
    return when (normalizedBlockchain) {
        "ethereum" -> "https://etherscan.io/token/${symbol}"
        "bnb smart chain", "bsc", "binance smart chain" -> "https://bscscan.com/token/${symbol}"
        "polygon" -> "https://polygonscan.com/token/${symbol}"
        "solana" -> "https://solscan.io/token/${symbol}"
        "avalanche" -> "https://snowtrace.io/token/${symbol}"
        "bitcoin" -> "https://www.blockchain.com/explorer/assets/btc"
        "ripple", "xrp" -> "https://xrpscan.com/"
        "arbitrum", "arbitrum one" -> "https://arbiscan.io/token/${symbol}"
        "polkadot" -> "https://polkadot.subscan.io/"
        "cardano" -> "https://cardanoscan.io/"
        "cosmos" -> "https://www.mintscan.io/cosmos"
        "algorand" -> "https://algoexplorer.io/"
        "near" -> "https://explorer.near.org/"
        "fantom" -> "https://ftmscan.com/token/${symbol}"
        "optimism" -> "https://optimistic.etherscan.io/token/${symbol}"
        "cronos" -> "https://cronoscan.com/token/${symbol}"
        "hedera" -> "https://hashscan.io/mainnet/dashboard"
        "vechain" -> "https://explore.vechain.org/"
        "aptos" -> "https://explorer.aptoslabs.com/"
        "sui" -> "https://explorer.sui.io/"
        "base" -> "https://basescan.org/token/${symbol}"
        "zksync era" -> "https://explorer.zksync.io/token/${symbol}"
        "stellar", "xlm" -> "https://stellar.expert/explorer/public"
        "tron", "trx" -> "https://tronscan.org/#/token/${symbol}"
        else -> "https://coinmarketcap.com/currencies/${symbol.lowercase()}"
    }
}

suspend fun loadBitmapFromUrl(context: Context, url: String): Bitmap? {
    return withContext(Dispatchers.IO) {
        try {
            val loader = ImageLoader(context)
            val request = ImageRequest.Builder(context)
                .data(url)
                .allowHardware(false)
                .build()
            (loader.execute(request) as? SuccessResult)?.drawable?.toBitmap()
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}
