package com.laxce.adl.ui.theme.screen

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import com.laxce.adl.R
import com.laxce.adl.api.RetrofitClient
import com.laxce.adl.viewmodel.token_view_model
import com.laxce.adl.classes.CryptoToken
import coil.compose.AsyncImage
import com.laxce.adl.ui.theme.layout.LoadingOverlay
import com.laxce.adl.ui.theme.layout.MainLayout
import com.laxce.adl.utility.getUserIdFromKeystore
import com.laxce.adl.utility.loadSelectedWallet
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import com.laxce.adl.api.Api
import androidx.compose.ui.layout.ContentScale
import android.util.Log

// Custom Switch Component
@Composable
fun CustomSwitch(checked: Boolean, onCheckedChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .width(50.dp)
            .height(28.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(if (checked) Color(0xFF27B6AC) else Color.Gray)
            .clickable { onCheckedChange(!checked) },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = if (checked) Arrangement.End else Arrangement.Start
    ) {
        Box(
            modifier = Modifier
                .size(24.dp)
                .clip(CircleShape)
                .background(Color.White)
                .padding(4.dp)
        )
    }
}

@OptIn(ExperimentalMaterialApi::class)
@Composable
fun AddTokenScreen(navController: NavController, tokenViewModel: token_view_model) {

    val context = LocalContext.current
    val api = RetrofitClient.getInstance(context).create(Api::class.java)
    var tokens by remember { mutableStateOf<List<CryptoToken>>(emptyList()) }
    var searchText by remember { mutableStateOf("") }
    var selectedNetwork by remember { mutableStateOf("All Blockchains") }
    var isModalVisible by remember { mutableStateOf(false) }
    var isLoading by remember { mutableStateOf(true) }
    var refreshing by remember { mutableStateOf(false) }

    val walletName = remember { loadSelectedWallet(context) }
    val userId = getUserIdFromKeystore(context, walletName).orEmpty()
    var isNavigating by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()
    val bottomSheetScaffoldState = rememberBottomSheetScaffoldState(
        bottomSheetState = rememberBottomSheetState(initialValue = BottomSheetValue.Collapsed)
    )
    
    Log.d("AddTokenScreen", "🎯 Using tokenViewModel parameter with userId: $userId")
    Log.d("AddTokenScreen", "🎯 TokenViewModel currencies size at start: ${tokenViewModel.currencies.size}")

    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val modalHeight = screenHeight * 0.50f
    val tokensState = remember { mutableStateOf<List<CryptoToken>>(emptyList()) }

    LaunchedEffect(isModalVisible) {
        coroutineScope.launch {
            bottomSheetScaffoldState.bottomSheetState.let { state ->
                if (isModalVisible && state.isCollapsed) {
                    state.expand()
                } else if (!isModalVisible && state.isExpanded) {
                    state.collapse()
                }
            }
        }
    }

    suspend fun loadTokens(forceRefresh: Boolean = false) {
        withContext(Dispatchers.IO) {
            try {
                Log.d("AddTokenScreen", "🔄 Starting loadTokens with forceRefresh=$forceRefresh")
                Log.d("AddTokenScreen", "📋 Current tokensState size before loading: ${tokensState.value.size}")
                
                tokenViewModel.smartLoadTokens(forceRefresh)
                
                Log.d("AddTokenScreen", "📋 TokenViewModel currencies size after smartLoadTokens: ${tokenViewModel.currencies.size}")
                Log.d("AddTokenScreen", "🔍 TokenViewModel error message: ${tokenViewModel.errorMessage}")
                
                val enabledTokenKeys = tokenViewModel.getEnabledTokenKeys()
                Log.d("AddTokenScreen", "🔑 Enabled token keys: $enabledTokenKeys")
                
                val tokenList = tokenViewModel.currencies.map { token ->
                    val compositeKey = "${token.symbol}_${token.BlockchainName}_${token.SmartContractAddress ?: ""}"
                    val isEnabled = enabledTokenKeys.contains(compositeKey)
                    Log.d("AddTokenScreen", "🪙 Token: ${token.symbol} (${token.BlockchainName}) [${token.SmartContractAddress}] - Enabled: $isEnabled")
                    token.copy(isEnabled = isEnabled)
                }
                
                Log.d("AddTokenScreen", "📋 Final tokenList size: ${tokenList.size}")
                tokensState.value = tokenList
                
                Log.d("AddTokenScreen", "✅ loadTokens completed successfully")
            } catch (e: Exception) {
                Log.e("AddTokenScreen", "❌ Error in loadTokens: ${e.message}", e)
                Log.e("AddTokenScreen", "❌ Exception type: ${e.javaClass.simpleName}")
                Log.e("AddTokenScreen", "❌ Stack trace: ${e.stackTrace.joinToString("\n")}")
            }
        }
    }

    fun refreshTokens() {
        Log.d("AddTokenScreen", "🔄 refreshTokens called")
        refreshing = true
        coroutineScope.launch {
            try {
            loadTokens(forceRefresh = true)
                Log.d("AddTokenScreen", "✅ refreshTokens completed")
            } catch (e: Exception) {
                Log.e("AddTokenScreen", "❌ Error in refreshTokens: ${e.message}", e)
            } finally {
            refreshing = false
            }
        }
    }

    LaunchedEffect(Unit) {
        Log.d("AddTokenScreen", "🚀 LaunchedEffect(Unit) triggered")
        isLoading = true
        
        Log.d("AddTokenScreen", "📋 Initial tokenViewModel currencies size: ${tokenViewModel.currencies.size}")
        tokensState.value = tokenViewModel.currencies
        
        try {
            Log.d("AddTokenScreen", "🔄 Starting smartLoadTokens from LaunchedEffect")
            tokenViewModel.smartLoadTokens()
            
            // اطمینان از همگام‌سازی کامل
            kotlinx.coroutines.delay(300)
            tokenViewModel.ensureTokensSynchronized()
            
            Log.d("AddTokenScreen", "✅ smartLoadTokens completed in LaunchedEffect")
        } catch (e: Exception) {
            Log.e("AddTokenScreen", "❌ Error in LaunchedEffect smartLoadTokens: ${e.message}", e)
        } finally {
            isLoading = false
            Log.d("AddTokenScreen", "🏁 LaunchedEffect completed, isLoading = false")
        }
    }

    LaunchedEffect(tokenViewModel.currencies) {
        Log.d("AddTokenScreen", "🔄 LaunchedEffect(tokenViewModel.currencies) triggered")
        Log.d("AddTokenScreen", "📋 TokenViewModel currencies size: ${tokenViewModel.currencies.size}")
        
        if (tokenViewModel.currencies.isEmpty()) {
            Log.w("AddTokenScreen", "⚠️ TokenViewModel currencies is empty!")
        } else {
            Log.d("AddTokenScreen", "📝 First few tokens: ${tokenViewModel.currencies.take(3).map { "${it.symbol} (${it.BlockchainName})" }}")
        }
        
        val enabledTokenKeys = tokenViewModel.getEnabledTokenKeys()
        Log.d("AddTokenScreen", "🔑 Enabled token keys in LaunchedEffect: $enabledTokenKeys")
        
        tokensState.value = tokenViewModel.currencies.map { token ->
            val compositeKey = "${token.symbol}_${token.BlockchainName}_${token.SmartContractAddress ?: ""}"
            val isEnabled = enabledTokenKeys.contains(compositeKey)
            Log.d("AddTokenScreen", "🪙 Processing token: ${token.name} [${compositeKey}] -> enabled: $isEnabled")
            token.copy(isEnabled = isEnabled)
        }
        
        Log.d("AddTokenScreen", "📋 Final tokensState size: ${tokensState.value.size}")
    }

    fun updateTokenState(token: CryptoToken, isEnabled: Boolean) {
        tokensState.value = tokensState.value.map { t ->
            if (t.symbol == token.symbol && 
                t.BlockchainName == token.BlockchainName && 
                t.SmartContractAddress == token.SmartContractAddress) {
                t.copy(isEnabled = isEnabled)
            } else {
                t
            }
        }
    }

    val blockchainIcons = mapOf(
        "All Blockchains" to R.drawable.all,
        "Bitcoin" to R.drawable.btc,
        "Ethereum" to R.drawable.ethereum_logo,
        "Binance Smart Chain" to R.drawable.binance_logo,
        "Polygon" to R.drawable.pol,
        "Tron" to R.drawable.tron,
        "Arbitrum" to R.drawable.arb,
        "XRP" to R.drawable.xrp,
        "Avalanche" to R.drawable.avax,
        "Polkadot" to R.drawable.dot,
        "Solana" to R.drawable.sol
    )

    val filteredTokens by remember(tokensState.value, searchText, selectedNetwork) {
        derivedStateOf {
            tokensState.value?.let { tokens ->
                tokens.filter { token ->
                    (searchText.isEmpty() || token.symbol.contains(searchText, ignoreCase = true)) &&
                            (selectedNetwork == "All Blockchains" || token.BlockchainName == selectedNetwork)
                }
            } ?: emptyList()
        }
    }

    val pullRefreshState = rememberPullRefreshState(refreshing, ::refreshTokens)

    Box(modifier = Modifier.fillMaxSize()) {
        MainLayout(navController = navController) {
            BottomSheetScaffold(
                scaffoldState = bottomSheetScaffoldState,
                sheetPeekHeight = 1.dp,
                sheetShape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp),
                sheetContent = {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(400.dp)
                            .background(Color(0xFFF6F6F6))
                            .padding(14.dp)
                    ) {
                        Text("Select Blockchain", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color.Black)
                        Spacer(modifier = Modifier.height(8.dp))

                        val blockchains = listOf("All Blockchains", "Bitcoin", "Ethereum", "Binance Smart Chain", "Polygon", "Tron", "Arbitrum", "XRP", "Avalanche", "Polkadot", "Solana")
                        LazyColumn {
                            items(blockchains, key = { it }) { blockchain ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable {
                                            selectedNetwork = blockchain
                                            isModalVisible = false
                                            coroutineScope.launch { bottomSheetScaffoldState.bottomSheetState.collapse() }
                                        }
                                        .padding(vertical = 6.dp, horizontal = 16.dp),
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
                }
            ) { innerPadding ->
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.White)
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp)
                    ) {
                        if (tokenViewModel.errorMessage != null) {
                            Box(
                                modifier = Modifier.fillMaxSize(),
                                contentAlignment = Alignment.Center
                            ) {
                                Column(
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    modifier = Modifier.padding(16.dp)
                                ) {
                                    Text(
                                        text = "Error loading tokens:",
                                        color = Color.Red,
                                        fontSize = 16.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                    Spacer(modifier = Modifier.height(8.dp))
                                    Text(
                                        text = tokenViewModel.errorMessage ?: "Unknown error",
                                        color = Color.Red,
                                        fontSize = 14.sp
                                    )
                                    Spacer(modifier = Modifier.height(16.dp))
                                    Text(
                                        text = "Debug Info:",
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color.Gray
                                    )
                                    Text(
                                        text = "ViewModel currencies: ${tokenViewModel.currencies.size}",
                                        fontSize = 10.sp,
                                        color = Color.Gray
                                    )
                                    Text(
                                        text = "TokensState: ${tokensState.value.size}",
                                        fontSize = 10.sp,
                                        color = Color.Gray
                                    )
                                    Text(
                                        text = "IsLoading: ${tokenViewModel.isLoading}",
                                        fontSize = 10.sp,
                                        color = Color.Gray
                                    )
                                    Spacer(modifier = Modifier.height(16.dp))
                                    Button(
                                        onClick = {
                                            Log.d("AddTokenScreen", "🔄 Retry button clicked")
                                            coroutineScope.launch {
                                                tokenViewModel.smartLoadTokens(true)
                                            }
                                        }
                                    ) {
                                        Text("Retry")
                                    }
                                }
                            }
                        } else if (tokensState.value.isEmpty() && !tokenViewModel.isLoading) {
                            // Show when no tokens are loaded and not loading
                            Box(
                                modifier = Modifier.fillMaxSize(),
                                contentAlignment = Alignment.Center
                            ) {
                                Column(
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    modifier = Modifier.padding(16.dp)
                                ) {
                                    Text(
                                        text = "No tokens available",
                                        fontSize = 16.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color.Gray
                                    )
                                    Spacer(modifier = Modifier.height(8.dp))
                                    Text(
                                        text = "Debug Info:",
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color.Gray
                                    )
                                    Text(
                                        text = "ViewModel currencies: ${tokenViewModel.currencies.size}",
                                        fontSize = 10.sp,
                                        color = Color.Gray
                                    )
                                    Text(
                                        text = "TokensState: ${tokensState.value.size}",
                                        fontSize = 10.sp,
                                        color = Color.Gray
                                    )
                                    Text(
                                        text = "IsLoading: ${tokenViewModel.isLoading}",
                                        fontSize = 10.sp,
                                        color = Color.Gray
                                    )
                                    Text(
                                        text = "Error: ${tokenViewModel.errorMessage ?: "None"}",
                                        fontSize = 10.sp,
                                        color = Color.Gray
                                    )
                                    Spacer(modifier = Modifier.height(16.dp))
                                    Button(
                                        onClick = {
                                            Log.d("AddTokenScreen", "🔄 Load tokens button clicked")
                                            coroutineScope.launch {
                                                tokenViewModel.smartLoadTokens(true)
                                            }
                                        }
                                    ) {
                                        Text("Load Tokens")
                                    }
                                }
                            }
                        } else {
                            Text(
                                text = "Manage Tokens",
                                style = MaterialTheme.typography.h5,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(vertical = 8.dp)
                            )

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
                                    .clickable {
                                        coroutineScope.launch {
                                            bottomSheetScaffoldState.bottomSheetState.expand()
                                        }
                                    },
                                contentAlignment = Alignment.CenterStart
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(start = 8.dp, end = 8.dp)
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

                            Spacer(modifier = Modifier.height(14.dp))

                            Text(
                                text = "Cryptos",
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xCB838383),
                                modifier = Modifier.padding(bottom = 8.dp)
                                    .padding(16.dp)
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(10.dp))

                    Box(modifier = Modifier
                        .fillMaxSize()
                        .pullRefresh(pullRefreshState)
                    ) {
                        LazyColumn(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(horizontal = 16.dp)
                        ) {
                            items(filteredTokens) { token ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(12.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    AsyncImage(
                                        model = token.iconUrl,
                                        contentDescription = token.name,
                                        modifier = Modifier
                                            .size(35.dp)
                                            .clip(CircleShape),
                                        placeholder = painterResource(id = R.drawable.coin),
                                        error = painterResource(id = R.drawable.coin),
                                        contentScale = ContentScale.Crop
                                    )

                                    Spacer(modifier = Modifier.width(8.dp))

                                    Column(modifier = Modifier.weight(1f)) {
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Text(
                                                text = token.name,
                                                fontWeight = FontWeight.Bold,
                                                fontSize = 16.sp
                                            )
                                            Spacer(modifier = Modifier.width(8.dp))
                                            Text(
                                                text = token.symbol,
                                                fontSize = 14.sp,
                                                color = Color.Gray
                                            )
                                        }
                                        Text(
                                            text = token.BlockchainName,
                                            fontSize = 14.sp,
                                            color = Color.Gray
                                        )
                                    }

                                    CustomSwitch(
                                        checked = token.isEnabled,
                                        onCheckedChange = { newState ->
                                            // 1. فوری به‌روزرسانی وضعیت محلی
                                            updateTokenState(token, newState)
                                            
                                            // 2. ذخیره در ViewModel و Preferences
                                            tokenViewModel.toggleToken(token, newState)
                                            
                                            // 3. همگام‌سازی کامل
                                            coroutineScope.launch {
                                                kotlinx.coroutines.delay(100) // تاخیر کوتاه برای اطمینان از ذخیره
                                                
                                                // به‌روزرسانی فوری وضعیت توکن‌ها در ViewModel
                                                tokenViewModel.forceUpdateTokenStates()
                                                
                                                // اطمینان از همگام‌سازی کامل
                                                tokenViewModel.ensureTokensSynchronized()
                                                
                                                // به‌روزرسانی لیست محلی با وضعیت جدید
                                                val enabledTokenKeys = tokenViewModel.getEnabledTokenKeys()
                                                tokensState.value = tokenViewModel.currencies.map { currencyToken ->
                                                    val compositeKey = "${currencyToken.symbol}_${currencyToken.BlockchainName}_${currencyToken.SmartContractAddress ?: ""}"
                                                    val isEnabled = enabledTokenKeys.contains(compositeKey)
                                                    currencyToken.copy(isEnabled = isEnabled)
                                                }
                                                
                                                Log.d("AddTokenScreen", "✅ Token ${token.name} toggled to $newState and synchronized")
                                                Log.d("AddTokenScreen", "✅ Active tokens count: ${tokenViewModel.activeTokens.value.size}")
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        
                        PullRefreshIndicator(
                            refreshing = refreshing,
                            state = pullRefreshState,
                            modifier = Modifier.align(Alignment.TopCenter)
                        )
                    }
                }
            }
        }
        
        if (isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.5f)),
                contentAlignment = Alignment.Center
            ) {
                LoadingOverlay(isLoading = true)
            }
        }
    }
}
