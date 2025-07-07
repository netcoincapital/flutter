package com.laxce.adl.ui.theme.screen

import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.lazy.LazyColumn
import androidx.navigation.NavController
import androidx.compose.foundation.clickable
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.background
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import coil.compose.AsyncImage
import com.laxce.adl.viewmodel.token_view_model
import com.laxce.adl.classes.CryptoToken
import com.laxce.adl.ui.theme.layout.MainLayout
import com.laxce.adl.utility.NetworkOption
import com.laxce.adl.ui.theme.layout.networks
import com.laxce.adl.ui.theme.layout.LoadingOverlay
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import com.laxce.adl.utility.format
import com.laxce.adl.utility.getCurrencySymbol
import com.laxce.adl.utility.getSelectedCurrency
import com.laxce.adl.utility.getUserIdFromKeystore
import com.laxce.adl.utility.loadSelectedWallet
import com.laxce.adl.api.BalanceRequest
import com.laxce.adl.api.BalanceItem
import com.laxce.adl.api.RetrofitClient
import com.google.gson.Gson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import com.laxce.adl.utility.formatAmount
import android.widget.Toast
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import kotlinx.coroutines.delay
import androidx.compose.runtime.rememberCoroutineScope
import com.laxce.adl.api.Api
import kotlin.ExperimentalStdlibApi
import androidx.compose.ui.layout.ContentScale


@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SendScreen(navController: NavController, tokenViewModel: token_view_model) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    var isRefreshing by remember { mutableStateOf(false) }
    var balanceItems by remember { mutableStateOf<List<BalanceItem>>(emptyList()) }
    var tokens by remember { mutableStateOf<List<CryptoToken>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    
    // State for search and network filtering
    var searchText by remember { mutableStateOf("") }
    var selectedNetwork by remember { mutableStateOf("All") }
    var isModalVisible by remember { mutableStateOf(false) }
    
    // Function to get balance directly from the API
    val fetchBalanceDirectly = {
        isLoading = true
        coroutineScope.launch(Dispatchers.IO) {
            try {
                val walletName = loadSelectedWallet(context)
                val userId = getUserIdFromKeystore(context, walletName ?: "")
                
                if (userId != null) {
                    // Get all available tokens from view model to know what to request
                    val availableTokens = tokenViewModel.currencies
                    val tokenSymbols = availableTokens.map { it.symbol }
                    

                    val api = RetrofitClient.getInstance(context).create(Api::class.java)
                    
                    // مشابه درخواست Postman، فقط UserID را می‌فرستیم
                    val request = BalanceRequest(
                        userId = userId,
                        // ارسال لیست خالی - سرور همه موجودی‌ها را برمی‌گرداند
                        currencyNames = emptyList(),
                        blockchain = emptyMap()
                    )
                    
                    val response = api.getBalance(request)
                    
                    // لاگ کردن JSON اصلی برای تشخیص مشکل
                    val gson = Gson()
                    val jsonResponse = gson.toJson(response)

                    if (response.success && response.balances != null) {
                        // Filter balances greater than 0
                        val positiveBalances = response.balances.filter { balanceItem -> 
                            if (balanceItem.balance == null) {
                                false
                            } else {
                                val balance = balanceItem.balance.toDoubleOrNull() ?: 0.0
                                balance > 0.0
                            }
                        }

                        // Update our state
                        balanceItems = positiveBalances
                        
                        // Convert balance items to CryptoToken objects
                        tokens = positiveBalances.mapNotNull { balanceItem ->
                            // Find corresponding token in view model currencies
                            val token = availableTokens.find { it.symbol == balanceItem.symbol }
                            if (token != null) {
                                val amount = if (balanceItem.balance == null) {
                                    0.0
                                } else {
                                    balanceItem.balance.toDoubleOrNull() ?: 0.0
                                }
                                token.copy(amount = amount)
                            } else {
                                null
                            }
                        }
                        
                        tokens.forEach { token ->
                        }
                        
                        // Always fetch prices after getting balances
                        val symbolsToFetch = tokens.map { it.symbol }
                        val selectedCurrency = getSelectedCurrency(context)
                        
                        if (symbolsToFetch.isNotEmpty()) {
                            tokenViewModel.forceRefresh()
                        }
                    } else {
                    }
                }
            } catch (e: Exception) {
            } finally {
                isLoading = false
                isRefreshing = false
                coroutineScope.launch(Dispatchers.Main) {
                    if (isRefreshing) {
                        Toast.makeText(context, "Refresh completed", Toast.LENGTH_SHORT).show()
                    }
                }
            }
        }
    }
    
    // Fetch balances on screen launch
    LaunchedEffect(Unit) {
        fetchBalanceDirectly()
    }
    
    // Auto-refresh prices periodically (every 30 seconds)
    LaunchedEffect(Unit) {
        while (true) {
            delay(30000) // 30 seconds
            // Only refresh prices, not balances
            if (!isLoading && !isRefreshing && tokens.isNotEmpty()) {
                val symbolsToFetch = tokens.map { it.symbol }
                val selectedCurrency = getSelectedCurrency(context)
                
                tokenViewModel.forceRefresh()
            }
        }
    }
    
    // Apply filters (search text and network)
    val filteredTokens = tokens.filter { token ->
        (searchText.isEmpty() ||
                token.name.contains(searchText, ignoreCase = true) ||
                token.symbol.contains(searchText, ignoreCase = true)) &&
                (selectedNetwork == "All" || token.BlockchainName == selectedNetwork)
    }

    // Function to refresh token balances
    val refreshTokens = {
        Toast.makeText(context, "Loading...", Toast.LENGTH_SHORT).show()
        isRefreshing = true
        fetchBalanceDirectly()
    }
    
    // For manual pull to refresh
    var dragOffsetY by remember { mutableStateOf(0f) }
    val draggableState = rememberDraggableState { delta ->
        if (!isRefreshing && !isLoading && delta > 0) {
            dragOffsetY += delta
            // Trigger refresh when drag is beyond threshold
            if (dragOffsetY > 150f) {
                dragOffsetY = 0f
                refreshTokens()
            }
        }
    }

    MainLayout(navController = navController) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.White)
                .padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Send Token",
                    style = MaterialTheme.typography.h5,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(8.dp)
                )
            }

            BasicTextField(
                value = searchText,
                onValueChange = { searchText = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0x25757575), RoundedCornerShape(25.dp))
                    .padding(12.dp),
                decorationBox = { innerTextField ->
                    if (searchText.isEmpty()) {
                        Text("Search", color = Color.Gray)
                    }
                    innerTextField()
                }
            )

            Spacer(modifier = Modifier.height(8.dp))

            Box(
                modifier = Modifier
                    .width(200.dp)
                    .height(32.dp)
                    .background(Color(0x25757575), RoundedCornerShape(15.dp))
                    .clickable { isModalVisible = true },
                contentAlignment = Alignment.CenterStart
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp)
                ) {
                    Text(
                        text = if (selectedNetwork == "All") "Select Network" else selectedNetwork,
                        fontSize = 16.sp,
                        color = Color(0xFF2c2c2c),
                        modifier = Modifier.weight(1f)
                    )
                    Icon(
                        imageVector = Icons.Filled.ArrowDropDown,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
            
            // Content area with pull-to-refresh capability
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .draggable(
                        state = draggableState,
                        orientation = Orientation.Vertical,
                        onDragStopped = {
                            if (dragOffsetY > 150f) {
                                dragOffsetY = 0f
                                refreshTokens()
                            } else {
                                dragOffsetY = 0f
                            }
                        }
                    )
            ) {
                // Show loading overlay when loading or refreshing
                LoadingOverlay(isLoading = isLoading || isRefreshing)
                
                if (!isLoading && !isRefreshing) {
                    // Display message if no tokens with balance
                    if (filteredTokens.isEmpty()) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .fillMaxHeight(),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = "No tokens with balance found",
                                color = Color.Gray,
                                fontSize = 16.sp
                            )
                        }
                    } else {
                        // Display tokens with balance
                        LazyColumn(
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            items(filteredTokens) { token ->
                                TokenItem(
                                    token = token,
                                    tokenViewModel = tokenViewModel,
                                    onClick = {
                                        try {
                                            // Serialize token to JSON and navigate to send_detail
                                            val tokenJson = Uri.encode(Gson().toJson(token))
                                            navController.navigate("send_detail/$tokenJson")
                                        } catch (e: Exception) {
                                            Toast.makeText(context, "Error displaying token details", Toast.LENGTH_SHORT).show()
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }

            if (isModalVisible) {
                ModalBottomSheet(
                    onDismissRequest = { isModalVisible = false }
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .fillMaxHeight(0.5f)
                            .background(Color(0xFFE0E0E0))
                            .padding(16.dp)
                    ) {
                        Text(
                            text = "Networks",
                            style = MaterialTheme.typography.h6,
                            modifier = Modifier
                                .padding(bottom = 16.dp)
                                .align(Alignment.CenterHorizontally)
                        )
                        networks.forEach { network ->
                            NetworkOption(
                                networkName = network.networkName,
                                iconResId = network.iconResId,
                                onClick = {
                                    selectedNetwork = network.networkName
                                    isModalVisible = false
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun TokenItem(token: CryptoToken, tokenViewModel: token_view_model, onClick: () -> Unit) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    val selectedCurrency = getSelectedCurrency(context)
    val currencySymbol = getCurrencySymbol(selectedCurrency)
    val prices by rememberUpdatedState(tokenViewModel.tokenPrices.collectAsState().value)

    // Track if we're waiting for price refresh
    var isPriceLoading by remember { mutableStateOf(false) }
    
    // Get price using our safe helper function
    val price = getSafeTokenPrice(token.symbol, tokenViewModel, selectedCurrency)
    
    val dollarValue = (price * (token.amount ?: 0.0)).format(2)
    val formattedAmount = formatAmount(token.amount ?: 0.0, price)

    // Request a price refresh if needed when this item is composed
    LaunchedEffect(token.symbol) {
        // If no price or price is 0, try to refresh
        if (price <= 0.0 && !tokenViewModel.isLoading) {
            isPriceLoading = true
            coroutineScope.launch {
                tokenViewModel.forceRefresh()
                // Wait a bit and then stop showing loading state
                delay(3000)
                isPriceLoading = false
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
            .clickable { onClick() }
            .padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically
        ) {
            AsyncImage(
                model = if (token.iconUrl.isNullOrEmpty()) "https://coinceeper.com/defualtIcons/coin.png" else token.iconUrl,
                contentDescription = null,
                modifier = Modifier.size(30.dp).clip(CircleShape),
                contentScale = ContentScale.Crop
            )
            Spacer(modifier = Modifier.width(16.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = token.name,
                    fontWeight = FontWeight.Bold,
                    fontSize = 16.sp,
                    color = Color.Black
                )
                Text(
                    text = token.BlockchainName,
                    fontSize = 13.sp,
                    color = Color.Gray
                )
            }

            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = formattedAmount,
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    color = Color(0xFF000000)
                )
                
                // Show loading indicator or price
                if (isPriceLoading || price <= 0.0) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = "Fetching price...",
                            fontSize = 12.sp,
                            color = Color.Gray
                        )
                        if (isPriceLoading) {
                            Spacer(modifier = Modifier.width(4.dp))
                            CircularProgressIndicator(
                                modifier = Modifier.size(12.dp),
                                color = Color.Gray,
                                strokeWidth = 1.5.dp
                            )
                        }
                    }
                } else {
                    Text(
                        text = "$currencySymbol$dollarValue",
                        fontSize = 12.sp,
                        color = Color.Gray
                    )
                }
            }
        }
    }
}

/**
 * Helper function to retrieve token price with proper fallbacks for any token
 * This ensures we always display a price even if the API didn't return one
 */
@OptIn(ExperimentalStdlibApi::class)
fun getSafeTokenPrice(
    tokenSymbol: String, 
    tokenViewModel: token_view_model,
    selectedCurrency: String
): Double {
    val prices = tokenViewModel.tokenPrices.value
    
    // Try standard mapping first
    val standardPrice = prices[tokenSymbol]?.get(selectedCurrency)?.price?.replace(",", "")?.toDoubleOrNull()
    
    if (standardPrice != null && standardPrice > 0.0) {
        return standardPrice
    }
    
    // Try lowercase/uppercase variations and alternative token names
    val variations = listOf(
        tokenSymbol.lowercase(),
        tokenSymbol.uppercase(),
        tokenSymbol.capitalize(),
        // Special mapping for common tokens
        if (tokenSymbol.equals("TRX", ignoreCase = true)) "tron" else null,
        if (tokenSymbol.equals("BNB", ignoreCase = true)) "binance" else null,
        if (tokenSymbol.equals("BTC", ignoreCase = true)) "bitcoin" else null,
        if (tokenSymbol.equals("ETH", ignoreCase = true)) "ethereum" else null,
        if (tokenSymbol.equals("SHIB", ignoreCase = true)) "shiba inu" else null
    ).filterNotNull()
    
    // Try all variations
    for (symbol in variations) {
        prices[symbol]?.get(selectedCurrency)?.price?.replace(",", "")?.toDoubleOrNull()?.let { 
            if (it > 0.0) return it
        }
    }
    
    // If still no price, trigger a refresh and return a temporary value
    // This is only used as a temporary display value until the prices are refreshed
    return 0.0 // Return 0.0 which will cause the UI to show as pending/loading
}

// String extension function to capitalize first letter
@OptIn(ExperimentalStdlibApi::class)
fun String.capitalize(): String {
    return if (this.isNotEmpty()) {
        this[0].uppercase() + this.substring(1).lowercase()
    } else {
        this
    }
}
