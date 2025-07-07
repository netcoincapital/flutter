package com.laxce.adl.ui.theme.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.R
import com.laxce.adl.api.RetrofitClient
import com.laxce.adl.api.Transaction
import com.laxce.adl.api.TransactionsRequest
import com.laxce.adl.utility.getUserIdFromKeystore
import com.laxce.adl.utility.loadSelectedWallet
import com.google.accompanist.swiperefresh.SwipeRefresh
import com.google.accompanist.swiperefresh.rememberSwipeRefreshState
import kotlinx.coroutines.launch
import com.laxce.adl.ui.theme.layout.MainLayout
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.Image
import com.laxce.adl.api.Api
import com.laxce.adl.utility.LocalTransactionCache

@Composable
fun HistoryScreen(navController: NavController) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    var isRefreshing by remember { mutableStateOf(false) }
    val swipeRefreshState = rememberSwipeRefreshState(isRefreshing)
    var isModalVisible by remember { mutableStateOf(false) }
    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val modalHeight = screenHeight * 0.50f
    val bottomSheetScaffoldState = rememberBottomSheetScaffoldState(
        bottomSheetState = rememberBottomSheetState(initialValue = BottomSheetValue.Collapsed)
    )
    var selectedNetwork by remember { mutableStateOf("All Networks") }
    
    // Transactions state
    var transactions by remember { mutableStateOf<List<Transaction>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val localPendingTransactions = LocalTransactionCache.pendingTransactions

    // Get the selected wallet and userId
    val selectedWallet = loadSelectedWallet(context)
    val userId = getUserIdFromKeystore(context, selectedWallet)

    // Fetch transactions when the screen is created or refreshed
    LaunchedEffect(userId, selectedNetwork) {
        fetchTransactions(context, userId, onSuccess = { 
            // آپدیت تراکنش لوکال با اطلاعات سرور (در صورت وجود)
            it.forEach { serverTx ->
                val matchedPending = LocalTransactionCache.pendingTransactions.find {
                    it.txHash == serverTx.txHash
                }
                if (matchedPending != null) {
                    serverTx.temporaryId = matchedPending.temporaryId
                }
                LocalTransactionCache.updateById(serverTx.txHash, serverTx)
                LocalTransactionCache.matchAndReplacePending(serverTx)
            }
            transactions = it
            isLoading = false
        }, onError = { 
            errorMessage = it.message
            isLoading = false
        })
    }

    LaunchedEffect(isModalVisible) {
        coroutineScope.launch {
            if (isModalVisible) {
                bottomSheetScaffoldState.bottomSheetState.expand()
            } else {
                bottomSheetScaffoldState.bottomSheetState.collapse()
            }
        }
    }


    BottomSheetScaffold(
        scaffoldState = bottomSheetScaffoldState,
        sheetContent = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(modalHeight)
                    .background(Color(0xFFF6F6F6))
                    .padding(16.dp)
            ) {
                Text("Select Blockchain", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color.Black)
                Spacer(modifier = Modifier.height(8.dp))

                val blockchains = listOf(
                    "All Networks", "Ethereum", "BNB Smart Chain",
                    "Bitcoin", "Polygon", "Solana"
                )

                val blockchainIcons = mapOf(
                    "All Networks" to R.drawable.all,
                    "Bitcoin" to R.drawable.btc,
                    "Ethereum" to R.drawable.ethereum_logo,
                    "BNB Smart Chain" to R.drawable.binance_logo,
                    "Polygon" to R.drawable.pol,
                    "Solana" to R.drawable.sol
                )

                LazyColumn {
                    items(blockchains) { blockchain ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    selectedNetwork = blockchain
                                    isModalVisible = false
                                }
                                .padding(vertical = 12.dp, horizontal = 16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                painter = painterResource(id = blockchainIcons[blockchain] ?: R.drawable.ethereum_logo),
                                contentDescription = null,
                                modifier = Modifier.size(24.dp),
                                tint = Color.Unspecified
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Text(text = blockchain, fontSize = 16.sp, color = Color.Black)
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                    }
                }
            }
        },
        sheetPeekHeight = 0.dp,
        sheetShape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp)
    ) {
    MainLayout(navController = navController) {
        SwipeRefresh(
            state = swipeRefreshState,
            onRefresh = {
                coroutineScope.launch {
                    isRefreshing = true
                    fetchTransactions(context, userId, onSuccess = { 
                        transactions = it
                        isRefreshing = false
                    }, onError = { 
                        errorMessage = it.message
                        isRefreshing = false
                    })
                }
            }
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.White)
                    .padding(horizontal = 16.dp)
            ) {
                // Header
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 16.dp, bottom = 12.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "History",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Icon(
                        imageVector = Icons.Default.ArrowBack,
                        contentDescription = "Back",
                        tint = Color.Black,
                        modifier = Modifier
                            .align(Alignment.CenterStart)
                            .size(24.dp)
                            .clickable { navController.popBackStack() }
                    )
                }


                // Filter (All Networks)
                Row(
                    modifier = Modifier
                        .padding(vertical = 8.dp)
                        .background(Color(0xFFF1F3F4), RoundedCornerShape(20.dp))
                        .clickable { isModalVisible = true }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = selectedNetwork,
                        fontSize = 14.sp,
                        color = Color.Black
                    )
                    Icon(
                        imageVector = Icons.Default.ArrowDropDown,
                        contentDescription = "Dropdown",
                        tint = Color.Black,
                        modifier = Modifier.size(20.dp)
                    )
                }


                Spacer(modifier = Modifier.height(8.dp))

                // Transactions List
                if (isLoading) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator(color = Color(0xFF11c699))
                    }
                } else if (errorMessage != null) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "Error: $errorMessage",
                            color = Color.Red,
                            fontSize = 16.sp
                        )
                    }
                } else if (transactions.isEmpty()) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center
                        ) {
                            Image(
                                painter = painterResource(id = R.drawable.notransaction),
                                contentDescription = "No Transactions",
                                modifier = Modifier
                                    .size(180.dp)
                                    .alpha(0.9f)
                            )
                            
                            Spacer(modifier = Modifier.height(16.dp))
                            
                            Text(
                                text = "No transactions found",
                                color = Color.Gray,
                                fontSize = 16.sp
                            )
                        }
                    }
                } else {
                    // Group transactions by date
                    val allTransactions = (localPendingTransactions + transactions)
                        .distinctBy { it.txHash }
                        .filter { selectedNetwork == "All Networks" || it.blockchainName == selectedNetwork }
                        .sortedByDescending { it.timestamp }
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

                    LazyColumn(
                        modifier = Modifier.fillMaxSize()
                    ) {
                        groupedTransactions.forEach { (date, transactionsForDate) ->
                            item { HistoryDateHeader(date) }

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
                                val tokenSymbol = transaction.tokenSymbol

                                // Simple estimation for USD value (for demonstration)
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

                                HistoryTransactionItem(
                                    type = if (isReceived) "Receive" else "Send",
                                    address = "$direction$shortAddress",
                                    amountValue = amountValue,
                                    tokenSymbol = tokenSymbol,
                                    fiat = fiatValue,
                                    isReceived = isReceived,
                                    status = transaction.status,
                                    onClick = {
                                        // Navigate to transaction details
                                        val dateFormatted = try {
                                            val dateTime = LocalDateTime.parse(transaction.timestamp, DateTimeFormatter.ISO_DATE_TIME)
                                            dateTime.format(DateTimeFormatter.ofPattern("MMM d, yyyy, h:mm a"))
                                        } catch (e: Exception) {
                                            "Unknown Date"
                                        }
                                        
                                        val status = "Completed"
                                        val senderAddress = if (isReceived) transaction.from else transaction.to
                                        val networkFee = "0 $tokenSymbol"
                                        
                                        // Encode parameters for URL
                                        val encodedAmount = android.net.Uri.encode(amountValue)
                                        val encodedSymbol = android.net.Uri.encode(tokenSymbol)
                                        val encodedFiat = android.net.Uri.encode(fiatValue)
                                        val encodedDate = android.net.Uri.encode(dateFormatted)
                                        val encodedStatus = android.net.Uri.encode(status)
                                        val encodedSender = android.net.Uri.encode(senderAddress)
                                        val encodedNetworkFee = android.net.Uri.encode(networkFee)
                                        val encodedHash = android.net.Uri.encode(transaction.txHash)
                                        
                                        navController.navigate(
                                            "transaction_detail/$encodedAmount/$encodedSymbol/$encodedFiat/$encodedDate/$encodedStatus/$encodedSender/$encodedNetworkFee/$encodedHash"
                                        )
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
                                            // Open explorer can be implemented here if needed
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
    }
}

// Function to fetch transactions from the API
private suspend fun fetchTransactions(
    context: android.content.Context,
    userId: String,
    onSuccess: (List<Transaction>) -> Unit,
    onError: (Exception) -> Unit
) {
    try {
        val api = RetrofitClient.getInstance(context).create(Api::class.java)
        val request = TransactionsRequest(UserID = userId)
        val response = api.getTransactions(request)
        
        if (response.status == "success") {
            onSuccess(response.transactions)
        } else {
            onError(Exception("Failed to fetch transactions"))
        }
    } catch (e: Exception) {
        onError(e)
    }
}

// Function to format amount by removing trailing zeros
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






@Composable
fun HistoryDateHeader(date: String) {
    Text(
        text = date,
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        color = Color.Gray,
        modifier = Modifier
            .padding(vertical = 8.dp)
    )
}

@Composable
fun HistoryTransactionItem(
    type: String,
    address: String,
    amountValue: String,
    tokenSymbol: String,
    fiat: String,
    isReceived: Boolean,
    status: String = "",
    onClick: () -> Unit = {}
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 10.dp)
            .clickable { onClick() },
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (!isReceived && status?.lowercase() == "pending") {
                Box(
                    modifier = Modifier
                        .size(24.dp)
                        .background(
                            color = Color(0xFFF43672).copy(alpha = 0.1f),
                            shape = CircleShape
                        )
                        .padding(4.dp),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        color = Color(0xFFF43672),
                        strokeWidth = 2.dp
                    )
                }
            } else {
                Icon(
                    imageVector = if (isReceived) Icons.Default.ArrowDownward else Icons.Default.ArrowUpward,
                    contentDescription = if (isReceived) "Received" else "Sent",
                    tint = if (isReceived) Color(0xFF20CDA4) else Color(0xFFF43672),
                    modifier = Modifier
                        .size(24.dp)
                        .background(
                            color = if (isReceived) Color(0xFF20CDA4).copy(alpha = 0.1f)
                            else Color(0xFFF43672).copy(alpha = 0.1f),
                            shape = CircleShape
                        )
                        .padding(4.dp)
                )
            }

            Spacer(modifier = Modifier.width(10.dp))

            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(text = type, fontWeight = FontWeight.Medium, fontSize = 14.sp)
                    if (!isReceived && status?.lowercase() == "pending") {
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "pending",
                            color = Color(0xFFF9A825), // زرد
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
                Text(text = address, color = Color.Gray, fontSize = 12.sp)
            }
        }

        Column(horizontalAlignment = Alignment.End) {
            Row {
                Text(
                    text = amountValue,
                    fontWeight = FontWeight.Medium,
                    fontSize = 12.sp,
                    color = if (amountValue.startsWith("-")) Color(0xFFF43672) else Color(0xFF11c699)
                )
                Spacer(modifier = Modifier.width(2.dp))
                Text(
                    text = tokenSymbol,
                    fontWeight = FontWeight.Medium,
                    fontSize = 12.sp,
                    color = Color.Black
                )
            }
            Text(text = fiat, fontSize = 12.sp, color = Color.Gray)
        }
    }
}
