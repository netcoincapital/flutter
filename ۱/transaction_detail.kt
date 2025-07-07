package com.laxce.adl.ui.theme.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Divider
import androidx.compose.material.Icon
import androidx.compose.material.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Share
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.api.RetrofitClient
import com.laxce.adl.api.TransactionsRequest
import com.laxce.adl.ui.theme.layout.LoadingOverlay
import com.laxce.adl.ui.theme.layout.MainLayout
import com.laxce.adl.utility.getUserIdFromKeystore
import com.laxce.adl.utility.loadSelectedWallet
import com.laxce.adl.utility.formatAmount
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.math.BigDecimal
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import android.net.Uri
import android.content.Intent
import com.laxce.adl.api.Api

@Composable
fun TransactionDetailScreen(
    navController: NavController,
    amount: String,
    tokenSymbol: String,
    fiatValue: String,
    date: String,
    status: String,
    sender: String,
    networkFee: String,
    transactionId: String = "" // Added transactionId parameter
) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    var isLoading by remember { mutableStateOf(transactionId.isNotEmpty()) }
    
    // State variables for transaction details
    var transactionAmount by remember { mutableStateOf(amount) }
    var transactionSymbol by remember { mutableStateOf(tokenSymbol) }
    var transactionFiatValue by remember { mutableStateOf(fiatValue) }
    var transactionDate by remember { mutableStateOf(date) }
    var transactionStatus by remember { mutableStateOf(status) }
    var transactionSender by remember { 
        val shortSender = if (sender.length > 12) {
            "${sender.take(6)}...${sender.takeLast(6)}"
        } else {
            sender
        }
        mutableStateOf(shortSender) 
    }
    var transactionFee by remember { mutableStateOf(networkFee) }
    var isReceived by remember { mutableStateOf(amount.startsWith("+")) }
    var explorerUrl by remember { mutableStateOf("") } // Added for explorer URL
    
    // If transactionId is provided, fetch the transaction details
    LaunchedEffect(transactionId) {
        if (transactionId.isNotEmpty()) {
            try {
                val walletName = loadSelectedWallet(context)
                val userId = getUserIdFromKeystore(context, walletName).orEmpty()
                val api = RetrofitClient.getInstance(context).create(Api::class.java)
                
                val response = api.getTransactions(TransactionsRequest(UserID = userId))
                val transaction = response.transactions?.find { it.txHash == transactionId }
                
                if (transaction != null) {
                    withContext(Dispatchers.Main) {
                        // Format and update transaction details
                        isReceived = transaction.direction == "inbound"
                        val amountPrefix = if (isReceived) "+" else "-"
                        
                        // Convert amount to Double for utility formatAmount function
                        val amountDouble = transaction.amount.toDoubleOrNull() ?: 0.0
                        
                        // Get the price for formatting (using 0.0 as default if not available)
                        val price = try {
                            transaction.price.toDoubleOrNull() ?: 0.0
                        } catch (e: Exception) {
                            0.0
                        }
                        
                        // Use the utility formatAmount function
                        transactionAmount = "$amountPrefix${formatAmount(amountDouble, price)}"
                        transactionSymbol = transaction.tokenSymbol
                        
                        // Store the explorer URL
                        explorerUrl = transaction.explorerUrl ?: ""
                        
                        // Format fiat value
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
                        transactionFiatValue = fiatValue
                        
                        // Format date
                        transactionDate = try {
                            val dateTime = LocalDateTime.parse(transaction.timestamp, DateTimeFormatter.ISO_DATE_TIME)
                            dateTime.format(DateTimeFormatter.ofPattern("MMM d, yyyy, h:mm a"))
                        } catch (e: Exception) {
                            "Unknown Date"
                        }
                        
                        // چون فیلد confirmations در کلاس Transaction وجود ندارد، همیشه Completed نمایش می‌دهیم
                        transactionStatus = "Completed"
                        
                        // خلاصه کردن آدرس sender
                        val senderAddress = if (isReceived) transaction.from else transaction.to
                        transactionSender = if (senderAddress.length > 12) {
                            "${senderAddress.take(6)}...${senderAddress.takeLast(6)}"
                        } else {
                            senderAddress
                        }
                        
                        // Format the network fee
                        val feeAmount = transaction.fee?.toDoubleOrNull() ?: 0.0
                        
                        // Use the blockchain's native token symbol for the fee
                        val feeSymbol = when(transaction.blockchainName) {
                            "TRON" -> "TRX"
                            "Ethereum" -> "ETH" 
                            "BNB Smart Chain" -> "BNB"
                            "BSC" -> "BNB"
                            "Polygon" -> "MATIC"
                            "Solana" -> "SOL"
                            "Avalanche" -> "AVAX"
                            "Bitcoin" -> "BTC"
                            "Ripple" -> "XRP"
                            "XRP Ledger" -> "XRP"
                            "Arbitrum" -> "ETH"
                            "Arbitrum One" -> "ETH"
                            "Polkadot" -> "DOT"
                            "Cardano" -> "ADA"
                            "Cosmos" -> "ATOM"
                            "Algorand" -> "ALGO"
                            "Near" -> "NEAR"
                            "Fantom" -> "FTM"
                            "Optimism" -> "ETH"
                            "Cronos" -> "CRO"
                            "Hedera" -> "HBAR"
                            "VeChain" -> "VET"
                            "Aptos" -> "APT"
                            "Sui" -> "SUI"
                            "Base" -> "ETH"
                            "zkSync Era" -> "ETH"
                            "Stellar" -> "XLM"
                            "TRON" -> "TRX"
                            else -> "TRX" // Default to TRX if blockchain not identified
                        }
                        
                        // Normalize the fee amount based on specific blockchain requirements
                        val normalizedFee = when(transaction.blockchainName) {
                            // TRON: divide by 1,000,000 (6 decimals)
                            "TRON" -> {
                                val normalizedValue = feeAmount / 1_000_000
                                String.format("%.2f", normalizedValue)
                            }
                            
                            // Ethereum, Arbitrum, Optimism, etc.: divide by 1,000,000,000,000,000,000 (18 decimals)
                            "Ethereum", "Arbitrum", "Arbitrum One", "Optimism", "Base", "zkSync Era" -> {
                                val normalizedValue = feeAmount / 1_000_000_000_000_000_000
                                String.format("%.6f", normalizedValue)
                            }
                            
                            // BNB Smart Chain: divide by 1,000,000,000,000,000,000 (18 decimals)
                            "BNB Smart Chain", "BSC" -> {
                                val normalizedValue = feeAmount / 1_000_000_000_000_000_000
                                String.format("%.6f", normalizedValue)
                            }
                            
                            // Polygon (MATIC): divide by 1,000,000,000,000,000,000 (18 decimals)
                            "Polygon" -> {
                                val normalizedValue = feeAmount / 1_000_000_000_000_000_000
                                String.format("%.6f", normalizedValue)
                            }
                            
                            // Solana: divide by 1,000,000,000 (9 decimals)
                            "Solana" -> {
                                val normalizedValue = feeAmount / 1_000_000_000
                                String.format("%.4f", normalizedValue)
                            }
                            
                            // Bitcoin: divide by 100,000,000 (8 decimals)
                            "Bitcoin" -> {
                                val normalizedValue = feeAmount / 100_000_000
                                String.format("%.8f", normalizedValue)
                            }
                            
                            // XRP: divide by 1,000,000 (6 decimals)
                            "Ripple", "XRP Ledger" -> {
                                val normalizedValue = feeAmount / 1_000_000
                                String.format("%.6f", normalizedValue)
                            }
                            
                            // Cardano: divide by 1,000,000 (6 decimals)
                            "Cardano" -> {
                                val normalizedValue = feeAmount / 1_000_000
                                String.format("%.6f", normalizedValue)
                            }
                            
                            // Polkadot: divide by 10,000,000,000 (10 decimals)
                            "Polkadot" -> {
                                val normalizedValue = feeAmount / 10_000_000_000
                                String.format("%.4f", normalizedValue)
                            }
                            
                            // Algorand: divide by 1,000,000 (6 decimals)
                            "Algorand" -> {
                                val normalizedValue = feeAmount / 1_000_000
                                String.format("%.6f", normalizedValue)
                            }
                            
                            // Cosmos (ATOM): divide by 1,000,000 (6 decimals)
                            "Cosmos" -> {
                                val normalizedValue = feeAmount / 1_000_000
                                String.format("%.6f", normalizedValue)
                            }
                            
                            // Avalanche: divide by 1,000,000,000,000,000,000 (18 decimals)
                            "Avalanche" -> {
                                val normalizedValue = feeAmount / 1_000_000_000_000_000_000
                                String.format("%.6f", normalizedValue)
                            }
                            
                            // Fantom: divide by 1,000,000,000,000,000,000 (18 decimals)
                            "Fantom" -> {
                                val normalizedValue = feeAmount / 1_000_000_000_000_000_000
                                String.format("%.6f", normalizedValue)
                            }
                            
                            // Near: divide by 1,000,000,000,000,000,000,000,000 (24 decimals)
                            "Near" -> {
                                val feeAmountBigDecimal = feeAmount.toBigDecimal()
                                val divisor = BigDecimal("1000000000000000000000000")
                                val normalizedValue = feeAmountBigDecimal.divide(divisor, 6, java.math.RoundingMode.HALF_UP)
                                normalizedValue.toString()
                            }
                            
                            // Stellar: divide by 10,000,000 (7 decimals)
                            "Stellar" -> {
                                val normalizedValue = feeAmount / 10_000_000
                                String.format("%.7f", normalizedValue)
                            }
                            
                            // Default case - use standard formatting
                            else -> formatAmount(feeAmount, price)
                        }
                        
                        transactionFee = "$normalizedFee $feeSymbol"
                    }
                } else {
                }
            } catch (e: Exception) {
            } finally {
                isLoading = false
            }
        }
    }

    MainLayout(navController = navController) {
        Box(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.White)
                    .padding(16.dp)
            ) {
                // Top Header with Back Button, Title, and Share
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.ArrowBack,
                        contentDescription = "Back",
                        modifier = Modifier
                            .clickable { navController.popBackStack() }
                            .size(24.dp),
                        tint = Color.Black
                    )
                    
                    Text(
                        text = "Transfer",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center
                    )
                    
                    Icon(
                        imageVector = Icons.Default.Share,
                        contentDescription = "Share",
                        modifier = Modifier
                            .clickable { 
                                // Share explorer URL if available
                                if (explorerUrl.isNotEmpty()) {
                                    try {
                                        val shareIntent = Intent().apply {
                                            action = Intent.ACTION_SEND
                                            putExtra(Intent.EXTRA_TEXT, explorerUrl)
                                            type = "text/plain"
                                        }
                                        val chooserIntent = Intent.createChooser(shareIntent, "Share Transaction URL")
                                        context.startActivity(chooserIntent)
                                    } catch (e: Exception) {
                                    }
                                }
                            }
                            .size(24.dp),
                        tint = Color.Black
                    )
                }
                
                // Transaction Amount
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    // The "+" sign is included in the amount parameter if it's a received transaction
                    Text(
                        text = "$transactionAmount $transactionSymbol",
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isReceived) Color(0xFF000000) else Color.Black
                    )
                    
                    Text(
                        text = transactionFiatValue,
                        fontSize = 16.sp,
                        color = Color.Gray
                    )
                }
                
                // Transaction Details Card
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFFF7F9FC), RoundedCornerShape(12.dp))
                        .padding(16.dp)
                ) {
                    // Date
                    TransactionDetailRow(label = "Date", value = transactionDate)
                    
                    Divider(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 12.dp),
                        color = Color(0xFFEEEEEE),
                        thickness = 1.dp
                    )
                    
                    // Status
                    TransactionDetailRow(label = "Status", value = transactionStatus)
                    
                    Divider(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 12.dp),
                        color = Color(0xFFEEEEEE),
                        thickness = 1.dp
                    )
                    
                    // Sender or Recipient based on transaction direction
                    TransactionDetailRow(
                        label = if (isReceived) "Sender" else "Recipient", 
                        value = transactionSender
                    )
                    
                    Divider(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 12.dp),
                        color = Color(0xFFEEEEEE),
                        thickness = 1.dp
                    )
                    
                    // Network Fee
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = "Network fee",
                                fontSize = 14.sp,
                                color = Color.Gray
                            )
                            
                            // Info icon for network fee - optional
                            Spacer(modifier = Modifier.width(4.dp))
                            
                            Box(
                                modifier = Modifier
                                    .size(16.dp)
                                    .background(Color(0xFFE0E0E0), shape = RoundedCornerShape(50))
                                    .padding(2.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = "ⓘ",
                                    fontSize = 10.sp,
                                    color = Color.Gray,
                                    textAlign = TextAlign.Center
                                )
                            }
                        }
                        
                        Text(
                            text = transactionFee,
                            fontSize = 14.sp,
                            color = Color.Black
                        )
                    }
                }
                
                Spacer(modifier = Modifier.height(24.dp))
                
                // More Details Button
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            color = Color(0x0F1BCAA0),
                            shape = RoundedCornerShape(8.dp)
                        )
                        .padding(16.dp)
                        .clickable { 
                            // استفاده از WebView داخلی به جای Custom Tabs
                            if (explorerUrl.isNotEmpty()) {
                                try {
                                    navController.navigate("web_view/${Uri.encode(explorerUrl)}")
                                } catch (e: Exception) {
                                }
                            }
                        },
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "More Details",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color(0xFF11c699)
                    )
                    
                    Icon(
                        imageVector = Icons.Default.KeyboardArrowRight,
                        contentDescription = "More Details",
                        tint = Color(0xFF11c699)
                    )
                }
            }
            
            // Show loading overlay if data is being fetched
            if (isLoading) {
                LoadingOverlay(isLoading = true)
            }
        }
    }
}

@Composable
fun TransactionDetailRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = label,
            fontSize = 14.sp,
            color = Color.Gray
        )
        
        Text(
            text = value,
            fontSize = 14.sp,
            color = Color.Black
        )
    }
} 
