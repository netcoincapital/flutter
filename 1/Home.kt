package com.laxce.adl.ui.theme.screen

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.R
import com.laxce.adl.viewmodel.token_view_model
import kotlinx.coroutines.launch
import com.google.accompanist.swiperefresh.SwipeRefresh
import com.google.accompanist.swiperefresh.rememberSwipeRefreshState
import coil.compose.AsyncImage
import com.laxce.adl.api.PriceData
import com.laxce.adl.classes.CryptoToken
import com.laxce.adl.ui.theme.layout.MainLayout
import com.laxce.adl.utility.format
import com.laxce.adl.utility.getCurrencySymbol
import com.laxce.adl.utility.getSelectedCurrency
import com.laxce.adl.utility.getUserIdFromKeystore
import com.laxce.adl.utility.getWalletsFromKeystore
import com.laxce.adl.utility.loadSelectedWallet
import com.google.gson.Gson
import com.laxce.adl.utility.TokenPreferences
import kotlin.math.abs
import kotlin.math.roundToInt
import androidx.compose.ui.input.pointer.consumeAllChanges
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.Spring
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.rememberScrollState
import com.laxce.adl.utility.formatAmount
import com.laxce.adl.utility.formatPrice
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.firstOrNull
import androidx.compose.ui.layout.ContentScale
import android.util.Log
import com.laxce.adl.api.Api
import com.laxce.adl.api.BalanceRequest
import com.laxce.adl.api.RetrofitClient

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(navController: NavController, tokenViewModel: token_view_model) {
    val context = LocalContext.current
    var walletName = loadSelectedWallet(context)
    var userId by remember { mutableStateOf("") }
    
    val tokenPreferences = remember(userId) {
        TokenPreferences(context, userId)
    }
    val activeTokens by tokenViewModel.activeTokens.collectAsState()
    val tokenPrices by tokenViewModel.tokenPrices.collectAsState()
    val gson = Gson()
    var isHidden by remember { mutableStateOf(false) }
    var isRefreshing by remember { mutableStateOf(false) }
    val swipeRefreshState = rememberSwipeRefreshState(isRefreshing)
    val coroutineScope = rememberCoroutineScope()
    var selectedTab by remember { mutableStateOf(0) }
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    var isLoading by remember { mutableStateOf(true) }
    val scrollState = rememberScrollState()
    val balanceFetched = remember(userId) { mutableStateOf(false) }
    var isWalletModalVisible by remember { mutableStateOf(false) }
    val walletsList = remember { getWalletsFromKeystore(context) }
    fun loadUserIdForWallet(context: Context, walletName: String): String? {
        val userId = getUserIdFromKeystore(context, walletName)
        return userId
    }
    val hasFetchedBalance = remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        tokenViewModel.loadPricesFromCache()
        isHidden = loadIsHiddenState(context)
    }

    LaunchedEffect(walletName, userId) {
        walletName = loadSelectedWallet(context).ifEmpty {
            getWalletsFromKeystore(context).firstOrNull()?.WalletName.orEmpty()
        }

        userId = loadUserIdForWallet(context, walletName).orEmpty()

        if (userId.isNotEmpty()) {
            Log.d("HomeScreen", "🔄 Updating token view model with new userId: $userId")
            tokenViewModel.updateUserId(userId)
        }

        if (userId.isNotEmpty()) {
            isLoading = true
            try {
                Log.d("HomeScreen", "🔄 Starting Home screen initialization")
                Log.d("HomeScreen", "👤 User ID: $userId")
                Log.d("HomeScreen", "👝 Wallet name: $walletName")
                
                tokenViewModel.loadPricesFromCache()
                tokenViewModel.smartLoadTokens(true)
                
                kotlinx.coroutines.delay(500)
                tokenViewModel.forceUpdateTokenStates()
                tokenViewModel.ensureTokensSynchronized()
                
                Log.d("HomeScreen", "✅ Initial token states synchronized")
                
                // Force fetch balances after tokens are loaded
                Log.d("HomeScreen", "🔄 Fetching balances for user: $userId")
                tokenViewModel.fetchBalancesForActiveTokens()
            } finally {
                isLoading = false
            }
        } else {
            Log.w("HomeScreen", "⚠️ User ID is empty, cannot fetch balances")
            isLoading = false
        }
    }

    // Separate LaunchedEffect to watch for userId changes and fetch balances
    LaunchedEffect(userId) {
        if (userId.isNotEmpty()) {
            Log.d("HomeScreen", "🔄 UserId changed, updating tokenViewModel with: $userId")
            tokenViewModel.updateUserId(userId)
            
            if (activeTokens.isNotEmpty()) {
                Log.d("HomeScreen", "🔄 Active tokens count: ${activeTokens.size}")
                delay(1000) // Wait for tokens to be fully loaded
                tokenViewModel.fetchBalancesForActiveTokens()
            }
        }
    }

    LaunchedEffect(activeTokens.size) {
        if (activeTokens.isNotEmpty()) {
            Log.d("HomeScreen", "✅ Active tokens updated: ${activeTokens.size} tokens")
            Log.d("HomeScreen", "✅ Active tokens list: ${activeTokens.map { it.name }}")
        }
    }

    LaunchedEffect(userId, tokenPrices) {
        if (!hasFetchedBalance.value && userId.isNotEmpty()) {
            snapshotFlow { activeTokens }
                .filter { it.isNotEmpty() }
                .firstOrNull()?.let {
                    tokenViewModel.fetchBalancesForActiveTokens()
                    hasFetchedBalance.value = true
                }
        }
    }

    DisposableEffect(context) {
        val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key?.startsWith("UserID_") == true) {
                val updatedUserId = loadUserIdForWallet(context, walletName).orEmpty()
                userId = updatedUserId
            }
        }
        sharedPreferences.registerOnSharedPreferenceChangeListener(listener)
        onDispose {
            sharedPreferences.unregisterOnSharedPreferenceChangeListener(listener)
        }
    }

    BackHandler {
        (context as? Activity)?.finish()
    }

    Box(modifier = Modifier.fillMaxSize()) {
        MainLayout(navController = navController) {
        SwipeRefresh(
            state = swipeRefreshState,
            onRefresh = {
                coroutineScope.launch {
                    try {
                        isRefreshing = true
                        tokenViewModel.forceRefresh()
                    } catch (e: Exception) {
                        e.printStackTrace()
                    } finally {
                        isRefreshing = false
                    }
                }
            },
            modifier = Modifier.fillMaxSize()
        ) {
            Box(modifier = Modifier.fillMaxSize()) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.White)
                        .padding(horizontal = 20.dp)
                ) {
                    // Top header with wallet name and search icon
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 20.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        // Left section - Two icons
                        Row(
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                painter = painterResource(id = R.drawable.music),
                                contentDescription = "Left Icon 1",
                                modifier = Modifier
                                    .size(18.dp)
                                    .clickable {
                                        navController.navigate("addtoken")
                                     },
                                tint = Color.Black
                            )

                            Spacer(modifier = Modifier.width(12.dp))

//                            Icon(
//                                painter = painterResource(id = R.drawable.rightarrow),
//                                contentDescription = "Left Icon 2",
//                                modifier = Modifier
//                                    .size(18.dp)
//                                    .clickable { isWalletModalVisible = true },
//                                tint = Color.Gray
//                            )
                        }

                        // Center section: Wallet name with dropdown arrow
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center
                        ) {
                            Text(
                                text = walletName,
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Medium,
                                modifier = Modifier.clickable { isWalletModalVisible = true }
                            )

                            Spacer(modifier = Modifier.width(6.dp))

                            Icon(
                                imageVector = if (isHidden) {
                                    Icons.Filled.VisibilityOff
                                } else {
                                    Icons.Filled.Visibility
                                },
                                contentDescription = if (isHidden) "Show Balance" else "Hide Balance",
                                modifier = Modifier
                                    .size(16.dp)
                                    .clickable {
                                        isHidden = !isHidden
                                        saveIsHiddenState(context, isHidden)
                                    },
                                tint = Color.Gray
                            )
                        }

                        // Right section: Search icon
                        Icon(
                            painter = painterResource(id = R.drawable.search),
                            contentDescription = "Search",
                            modifier = Modifier
                                .size(18.dp)
                                .clickable { navController.navigate("addtoken") },
                            tint = Color.Black
                        )
                    }

                    UserProfileSection(
                        walletName = walletName,
                        isHidden = isHidden,
                        totalDollarValue = calculateTotalValue(activeTokens, tokenPrices, getSelectedCurrency(context)).format(2),
                        onToggleHide = {
                            isHidden = !isHidden
                            saveIsHiddenState(context, isHidden)
                        },
                        displayWalletName = false,
                        changePercentage = tokenViewModel.getAverageChange24h() ?: "-0.35%"
                    )

                    Spacer(modifier = Modifier.height(16.dp))
                    ActionButtonsRow(
                        navController = navController,
                        tokenViewModel = tokenViewModel)
                    
                    Spacer(modifier = Modifier.height(8.dp))
                    TokenTabs(selectedTab = selectedTab, onTabSelected = { selectedTab = it })
                    Spacer(modifier = Modifier.height(10.dp))

                    if (selectedTab == 0) {
                        Box(modifier = Modifier.weight(1f)) {
                            TokenList(
                                tokenViewModel = tokenViewModel,
                                tokenPreferences = tokenPreferences,
                                isHidden = isHidden,
                                navController = navController
                            )
                        }
                    } else {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(10.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            NoNftFoundMessage(imageSize = 90.dp, imageTransparency = 0.2f)
                        }
                    }
                }
            }
        }
    }

        // Remove the separate BottomMenuWithSiri since it's now in MainLayout
        // BottomMenuWithSiri(
        //     navController = navController,
        //     currentRoute = "home",
        //     modifier = Modifier.align(Alignment.BottomCenter)
        // )
    }

    if (isWalletModalVisible) {
        ModalBottomSheet(
            onDismissRequest = { isWalletModalVisible = false },
            sheetState = rememberModalBottomSheetState(
                skipPartiallyExpanded = true,
                confirmValueChange = { true }
            ),
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
            containerColor = Color.White
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(0.9f)
                    .padding(20.dp)
            ) {
                Text(
                    text = "Select Wallet",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .padding(vertical = 8.dp)
                        .align(Alignment.CenterHorizontally)
                )

                Spacer(modifier = Modifier.height(16.dp))

                LazyColumn(
                    modifier = Modifier.weight(1f)
                ) {
                    items(walletsList) { wallet ->
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    walletName = wallet.WalletName
                                    saveSelectedWallet(context, wallet.WalletName, wallet.UserID)
                                    isWalletModalVisible = false
                                }
                                .background(
                                    brush = Brush.linearGradient(
                                        colors = listOf(
                                            Color(0xFF08C495),
                                            Color(0xFF39b6fb)
                                        )
                                    ),
                                    shape = RoundedCornerShape(12.dp)
                                )
                                .padding(horizontal = 14.dp, vertical = 12.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = wallet.WalletName,
                                        fontSize = 16.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color.White
                                    )
                                }

                                Icon(
                                    painter = painterResource(id = R.drawable.rightarrow),
                                    contentDescription = null,
                                    tint = Color.White,
                                    modifier = Modifier.size(18.dp)
                                )
                            }
                        }
                        Spacer(modifier = Modifier.height(10.dp))
                    }
                }

                Spacer(modifier = Modifier.height(20.dp))
            }
        }
    }

    // Debug function to test balance API directly
    fun debugBalanceAPI() {
        coroutineScope.launch {
            try {
                Log.d("HomeScreen", "🧪 === DEBUG BALANCE API TEST ===")
                
                val api = RetrofitClient.getInstance(context).create(Api::class.java)
                val request = BalanceRequest(
                    userId = userId,
                    currencyNames = emptyList(),
                    blockchain = emptyMap()
                )
                
                Log.d("HomeScreen", "🧪 Making direct API call with userId: $userId")
                val response = api.getBalance(request)
                
                // Log raw JSON response
                val gson = Gson()
                val jsonResponse = gson.toJson(response)
                Log.d("HomeScreen", "🧪 Raw JSON Response: $jsonResponse")
                
                Log.d("HomeScreen", "🧪 Raw Response Success: ${response.success}")
                Log.d("HomeScreen", "🧪 Raw Response UserID: ${response.UserID}")
                Log.d("HomeScreen", "🧪 Raw Response Message: ${response.message}")
                Log.d("HomeScreen", "🧪 Raw Response Balances Size: ${response.balances?.size}")
                
                response.balances?.forEach { balance ->
                    Log.d("HomeScreen", "🧪 Raw Balance: Symbol=${balance.symbol}, Amount=${balance.balance}, Blockchain=${balance.blockchain}")
                }
                
            } catch (e: Exception) {
                Log.e("HomeScreen", "🧪 Debug API call failed: ${e.message}", e)
            }
        }
    }

    // Test function to manually call balance API with exact Postman request
    fun testBalanceAPIManual() {
        coroutineScope.launch {
            try {
                Log.d("HomeScreen", "🧪 === MANUAL BALANCE API TEST ===")
                Log.d("HomeScreen", "🧪 Testing with exact Postman request")
                Log.d("HomeScreen", "🧪 UserID: $userId")
                
                val api = RetrofitClient.getInstance(context).create(Api::class.java)
                
                // Exact same request as Postman
                val request = BalanceRequest(
                    userId = "0d32dfd0-f7ba-4d5a-a408-75e6c2961e23", // Hard-coded for test
                    currencyNames = emptyList(),
                    blockchain = emptyMap()
                )
                
                Log.d("HomeScreen", "🧪 Making API call...")
                val response = api.getBalance(request)
                
                Log.d("HomeScreen", "🧪 API Response received!")
                Log.d("HomeScreen", "🧪 Success: ${response.success}")
                Log.d("HomeScreen", "🧪 UserID: ${response.UserID}")
                Log.d("HomeScreen", "🧪 Balances count: ${response.balances?.size}")
                
                response.balances?.forEach { balance ->
                    Log.d("HomeScreen", "🧪 Balance found: ${balance.symbol} = ${balance.balance}")
                }
                
                if (response.success && response.balances?.isNotEmpty() == true) {
                    Log.d("HomeScreen", "🧪 ✅ API call successful - balances received!")
                } else {
                    Log.d("HomeScreen", "🧪 ❌ API call failed or no balances")
                }
                
            } catch (e: Exception) {
                Log.e("HomeScreen", "🧪 ❌ API call exception: ${e.message}", e)
            }
        }
    }
}

// تابع کمکی برای محاسبه مجموع ارزش همه توکن‌ها
private fun calculateTotalValue(
    tokens: List<CryptoToken>,
    prices: Map<String, Map<String, PriceData>>,
    selectedCurrency: String
): Double {
    var total = 0.0
    tokens.forEach { token ->
        val price = prices[token.symbol]?.get(selectedCurrency)?.price?.toDoubleOrNull() ?: 0.0
        total += price * (token.amount ?: 0.0)
    }
    return total
}

// ✅ نسخه بهینه‌شده‌ی تابع TokenList با پشتیبانی از انیمیشن حرفه‌ای حذف و جابه‌جایی
// ✅ نسخه نهایی با انیمیشن دقیق جایگزینی آیتم‌ها با animateItemPlacement و translationY فقط روی آیتم درگ‌شده
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TokenList(
    tokenViewModel: token_view_model,
    tokenPreferences: TokenPreferences,
    isHidden: Boolean,
    navController: NavController
) {
    val context = LocalContext.current
    val selectedCurrency = getSelectedCurrency(context)
    val activeTokens by tokenViewModel.activeTokens.collectAsState()
    val prices by tokenViewModel.tokenPrices.collectAsState()
    val gasFees by tokenViewModel.gasFees.collectAsState()

    val pendingRemoval = remember { mutableStateListOf<String>() }
    var draggedItemIndex by remember { mutableStateOf<Int?>(null) }
    var targetItemIndex by remember { mutableStateOf<Int?>(null) }
    val listState = rememberLazyListState()
    val density = LocalDensity.current
    val itemHeightPx = with(density) { 88.dp.toPx() }
    val dragOffset = remember { mutableStateOf(0f) }
    val isDragging = remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    var openedTokenId by remember { mutableStateOf<String?>(null) }

    val sortedTokens = remember(activeTokens, prices) {
        activeTokens.sortedByDescending { token ->
            val tokenPrice = prices[token.symbol]?.get(selectedCurrency)?.price?.replace(",", "")?.toDoubleOrNull() ?: 0.0
            (token.amount ?: 0.0) * tokenPrice
        }
    }

    LaunchedEffect(activeTokens.size) {
        Log.d("TokenList", "🔄 Active tokens updated: ${activeTokens.size} tokens")
        Log.d("TokenList", "🔄 Token names: ${activeTokens.map { it.name }}")
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() }
            ) { openedTokenId = null }
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            itemsIndexed(
                items = sortedTokens,
                key = { index, token -> "${token.symbol}_$index" }
            ) { index, token ->
                val tokenPrices = prices[token.symbol]
                val priceData = tokenPrices?.get(selectedCurrency)
                val price = priceData?.price?.replace(",", "")?.toDoubleOrNull() ?: 0.0
                val change24h = priceData?.change_24h ?: "+0.0%"
                val isVisible = !pendingRemoval.contains(token.symbol)
                val isDraggingThisItem = draggedItemIndex == index
                
                // اصلاح مستقیم برای مقادیر کوچک
                val customFormatAmount = { amount: Double ->
                    when {
                        amount == 0.0 -> "0"
                        amount < 0.001 -> String.format("%.8f", amount).trimEnd('0').trimEnd('.')
                        amount < 0.1 -> String.format("%.6f", amount).trimEnd('0').trimEnd('.')
                        amount < 1.0 -> String.format("%.4f", amount).trimEnd('0').trimEnd('.')
                        amount < 10.0 -> String.format("%.3f", amount).trimEnd('0').trimEnd('.')
                        else -> String.format("%.2f", amount).trimEnd('0').trimEnd('.')
                    }
                }
                
                val amountFormatted = if (isHidden) { 
                    "****" 
                } else { 
                    customFormatAmount(token.amount ?: 0.0)
                }

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            if (isDraggingThisItem) {
                                Modifier.graphicsLayer {
                                    translationY = dragOffset.value
                                }
                            } else {
                                Modifier.animateItemPlacement(
                                    animationSpec = spring(
                                        dampingRatio = Spring.DampingRatioMediumBouncy,
                                        stiffness = Spring.StiffnessLow
                                    )
                                )
                            }
                        )
                ) {
                    AnimatedVisibility(
                        visible = isVisible,
                        exit = shrinkVertically(tween(400)) + scaleOut(tween(400)) + fadeOut(tween(300))
                    ) {
                        TokenRow(
                            tokenName = token.name,
                            tokenPriceUSD = price,
                            iconUrl = token.iconUrl,
                            amount = amountFormatted,
                            selectedCurrency = selectedCurrency,
                            dollarValue = (price * (token.amount ?: 0.0)).format(2),
                            priceInSelectedCurrency = formatPrice(price, token.symbol),
                            totalValueInSelectedCurrency = if (isHidden) "****" else "${getCurrencySymbol(selectedCurrency)}${(price * (token.amount ?: 0.0)).format(2)}",
                            change = change24h,
                            symbol = token.symbol,
                            isDraggable = true,
                            isDragging = isDraggingThisItem,
                            onDragStart = {
                                draggedItemIndex = index
                                isDragging.value = true
                                dragOffset.value = 0f
                                val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    vibrator.vibrate(VibrationEffect.createOneShot(30, VibrationEffect.DEFAULT_AMPLITUDE))
                                }
                            },
                            onDrag = { change ->
                                if (draggedItemIndex == index) {
                                    dragOffset.value += change.y

                                    val visibleItem = listState.layoutInfo.visibleItemsInfo.find { it.index == index }
                                    val currentItemOffset = visibleItem?.offset ?: 0

                                    val totalOffset = dragOffset.value + currentItemOffset
                                    val estimatedIndex = (totalOffset / itemHeightPx).roundToInt()
                                    val targetIndex = estimatedIndex.coerceIn(0, sortedTokens.lastIndex)

                                    if (targetItemIndex != targetIndex) {
                                        targetItemIndex = targetIndex
                                    }
                                }
                            },
                            onDragEnd = {
                                if (
                                    draggedItemIndex != null &&
                                    targetItemIndex != null &&
                                    draggedItemIndex != targetItemIndex &&
                                    targetItemIndex!! in sortedTokens.indices
                                ) {
                                    val reorderedTokens = sortedTokens.toMutableList()
                                    val item = reorderedTokens.removeAt(draggedItemIndex!!)
                                    reorderedTokens.add(targetItemIndex!!, item)
                                    tokenViewModel.updateTokenOrder(reorderedTokens)
                                    tokenPreferences.saveTokenOrder(reorderedTokens.map { it.symbol })
                                }
                                dragOffset.value = 0f
                                draggedItemIndex = null
                                targetItemIndex = null
                                isDragging.value = false
                            },
                            verticalOffset = 0f,
                            onClick = {
                                if (!isDragging.value) {
                                    val encodedIconUrl = Uri.encode(token.iconUrl)
                                    val gasFee = when (token.symbol) {
                                        "BTC" -> gasFees["Bitcoin"] ?: "0.0"
                                        "ETH" -> {
                                            val ethGasFee = gasFees["Ethereum"] ?: "0.0"
                                            
                                            if (ethGasFee == "0.0") {
                                                scope.launch {
                                                    try {
                                                        tokenViewModel.fetchGasFees()
                                                    } catch (e: Exception) {
                                                        e.printStackTrace()
                                                    }
                                                }
                                                "0.0012"
                                            } else {
                                                ethGasFee
                                            }
                                        }
                                        else -> "0.0"
                                    }
                                    navController.navigate("tokendetails/${token.name}/${token.symbol}/$encodedIconUrl/$gasFee/${token.BlockchainName}/${token.isToken}")
                                }
                            },
                            listState = listState,
                            itemHeightPx = itemHeightPx,
                            isSwipedOpen = openedTokenId == "${token.symbol}_$index",
                            onSwipeChange = { isOpen ->
                                openedTokenId = if (isOpen) "${token.symbol}_$index" else null
                            },
                            tokenViewModel = tokenViewModel,
                            token = token,
                            onSwipedToDisable = {
                                pendingRemoval.add(token.symbol)
                                scope.launch {
                                    delay(400)
                                    tokenViewModel.toggleToken(token, false)
                                    pendingRemoval.remove(token.symbol)
                                }
                            }
                        )
                    }
                }
            }
        
            // بلاک بالا تمام شد، حالا آیتم spacer را در سطح اصلی اضافه می‌کنیم
            item {
                Spacer(modifier = Modifier.height(90.dp))
            }
        }
    }
}


@Composable
fun TokenRow(
    tokenName: String,
    tokenPriceUSD: Double,
    iconUrl: String,
    amount: String,
    selectedCurrency: String,
    dollarValue: String,
    priceInSelectedCurrency: String,
    totalValueInSelectedCurrency: String,
    change: String,
    symbol: String,
    modifier: Modifier = Modifier,
    isDraggable: Boolean = false,
    isDragging: Boolean = false,
    onDragStart: () -> Unit = {},
    onDrag: (Offset) -> Unit = {},
    onDragEnd: () -> Unit = {},
    verticalOffset: Float = 0f,
    onClick: () -> Unit,
    listState: LazyListState,
    itemHeightPx: Float,
    isSwipedOpen: Boolean,
    onSwipeChange: (Boolean) -> Unit,
    tokenViewModel: token_view_model,
    token: CryptoToken,
    onSwipedToDisable: () -> Unit // 🆕 پارامتر جدید
) {
    var isLongPressed by remember { mutableStateOf(false) }
    val offsetX = remember { Animatable(0f) }
    val maxSwipe = with(LocalDensity.current) { (-80).dp.toPx() }
    val disableThreshold = maxSwipe * 0.6f
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    LaunchedEffect(isSwipedOpen) {
        if (!isSwipedOpen) {
            offsetX.animateTo(
                targetValue = 0f,
                animationSpec = spring(
                    dampingRatio = 0.8f,
                    stiffness = 300f,
                    visibilityThreshold = 0.1f
                )
            )
        }
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                enabled = isSwipedOpen,
                indication = null,
                interactionSource = remember { MutableInteractionSource() }
            ) {
                scope.launch {
                    onSwipeChange(false)
                    offsetX.animateTo(
                        targetValue = 0f,
                        animationSpec = spring(
                            dampingRatio = 0.8f,
                            stiffness = 300f,
                            visibilityThreshold = 0.1f
                        )
                    )
                }
            }
    ) {
        // 🔴 بکگراند قرمز (Disable)
        Box(
            modifier = Modifier
                .matchParentSize()
                .background(
                    Color(0xFFFF1961).copy(alpha = 0.8f),
                    RoundedCornerShape(12.dp)
                ),
            contentAlignment = Alignment.CenterEnd
        ) {
            Box(
                modifier = Modifier
                    .size(60.dp)
                    .padding(end = 10.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "Disable",
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }

        // 🟢 محتوای اصلی
        Row(
            modifier = modifier
                .fillMaxWidth()
                .offset { IntOffset(offsetX.value.roundToInt(), verticalOffset.roundToInt()) }
                .scale(if (isDragging) 1.03f else 1f)
                .pointerInput(Unit) {
                    detectHorizontalDragGestures(
                        onDragStart = {},
                        onDragEnd = {
                            scope.launch {
                                if (offsetX.value <= disableThreshold) {
                                    onSwipeChange(false)
                                    onSwipedToDisable() // 🆕 اجرای انیمیشن حذف بیرونی
                                } else if (abs(offsetX.value) > abs(maxSwipe) / 2) {
                                    onSwipeChange(true)
                                    offsetX.animateTo(maxSwipe, spring())
                                } else {
                                    onSwipeChange(false)
                                    offsetX.animateTo(0f, spring())
                                }
                            }
                        },
                        onDragCancel = {
                            scope.launch {
                                offsetX.animateTo(0f)
                            }
                        },
                        onHorizontalDrag = { change, dragAmount ->
                            change.consumeAllChanges()
                            scope.launch {
                                val newValue = (offsetX.value + dragAmount).coerceIn(maxSwipe * 1.2f, 0f)
                                offsetX.snapTo(newValue)
                            }
                        }
                    )
                }
                .pointerInput(Unit) {
                    detectDragGesturesAfterLongPress(
                        onDragStart = {
                            isLongPressed = true
                            onDragStart()
                            scope.launch {
                                onSwipeChange(false)
                                offsetX.animateTo(0f)
                            }
                        },
                        onDragEnd = {
                            isLongPressed = false
                            onDragEnd()
                        },
                        onDragCancel = {
                            isLongPressed = false
                            onDragEnd()
                        },
                        onDrag = { change, dragAmount ->
                            if (isLongPressed) {
                                change.consumeAllChanges()
                                onDrag(Offset(0f, dragAmount.y))
                            }
                        }
                    )
                }
                .clickable(
                    enabled = !isDragging && !isLongPressed,
                    onClick = {
                        if (isSwipedOpen) {
                            scope.launch {
                                onSwipeChange(false)
                                offsetX.animateTo(0f)
                            }
                        } else if (offsetX.value == 0f) {
                            onClick()
                        }
                    },
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() }
                )
                .background(
                    brush = Brush.horizontalGradient(
                        colors = listOf(Color(0xFFE7FAEF), Color(0xFFE7F0FB))
                    ),
                    shape = RoundedCornerShape(8.dp)
                )
                .padding(vertical = 3.dp, horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            AsyncImage(
                model = iconUrl.ifEmpty { "https://coinceeper.com/defualtIcons/coin.png" },
                placeholder = painterResource(id = R.drawable.coin),
                error = painterResource(id = R.drawable.coin),
                contentDescription = "$tokenName Logo",
                modifier = Modifier
                    .size(30.dp)
                    .clip(CircleShape),
                contentScale = ContentScale.Crop
            )

            Spacer(modifier = Modifier.width(12.dp))

            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(tokenName, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("($symbol)", fontSize = 12.sp, color = Color(0xff2b2b2b))
                }
                Spacer(modifier = Modifier.height(1.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "${getCurrencySymbol(selectedCurrency)}$priceInSelectedCurrency",
                        fontSize = 14.sp,
                        color = Color.Gray
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    if (change != "+0.0%") {
                        Text(
                            text = "${change}",
                            fontSize = 14.sp,
                            color = if (change.startsWith("-")) Color(0xFFFF1961) else Color(0xFF08C495)
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            Column(horizontalAlignment = Alignment.End) {
                Text(amount, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                Spacer(modifier = Modifier.height(4.dp))
                Text(totalValueInSelectedCurrency, fontSize = 12.sp, color = Color.Gray)
            }
        }
    }
}


@Composable
fun UserProfileSection(
    walletName: String, 
    isHidden: Boolean, 
    totalDollarValue: String, 
    onToggleHide: () -> Unit, 
    displayWalletName: Boolean = true,
    changePercentage: String = "-0.35%"  // Added parameter with default value
) {
    val context = LocalContext.current
    val selectedCurrency = getSelectedCurrency(context)
    val currencySymbol = getCurrencySymbol(selectedCurrency)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 16.dp)
    ) {
        if (displayWalletName) {
            Row(
                modifier = Modifier
                    .fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center
            ) {
                Text(
                    text = walletName,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Medium
                )
                Spacer(modifier = Modifier.width(6.dp))
                Icon(
                    painter = painterResource(id = if (changePercentage.startsWith("-")) R.drawable.receive else R.drawable.send),
                    contentDescription = if (changePercentage.startsWith("-")) "Down Arrow" else "Up Arrow",
                    modifier = Modifier
                        .size(16.dp)
                        .clickable { onToggleHide() },
                    tint = if (changePercentage.startsWith("-")) Color(0xFFFF1961) else Color(0xFF08C495)
                )
            }
            
            Spacer(modifier = Modifier.height(12.dp))
        }
        
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = if (isHidden) "****" else "$currencySymbol$totalDollarValue",
                fontSize = 36.sp,
                fontWeight = FontWeight.Bold
            )


            Spacer(modifier = Modifier.height(4.dp))
            
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    painter = painterResource(id = if (changePercentage.startsWith("-")) R.drawable.receive else R.drawable.send),
                    contentDescription = if (changePercentage.startsWith("-")) "Down Arrow" else "Up Arrow",
                    modifier = Modifier.size(12.dp),
                    tint = if (changePercentage.startsWith("-")) Color(0xFFFF1961) else Color(0xFF08C495)
                )
                
                Text(
                    text = if (isHidden) " **** ${changePercentage}" else " ${totalDollarValue} ${changePercentage}",
                    fontSize = 16.sp,
                    color = if (changePercentage.startsWith("-")) Color(0xFFFF1961) else Color(0xFF08C495)
                )
            }
        }
    }
}

@Composable
fun SearchButton(navController: NavController) {
    var isPressed by remember { mutableStateOf(false) }
    val backgroundColor = if (isPressed) {
        Brush.horizontalGradient(
            colors = listOf(Color(0x99CCFFF3), Color(0x9900D4FF))
        )
    } else {
        Brush.horizontalGradient(
            colors = listOf(Color(0x4DCCFFF3), Color(0x4D00D4FF))
        )
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(60.dp)
            .padding(top = 25.dp)
            .background(
                brush = backgroundColor,
                shape = RoundedCornerShape(50.dp)
            )
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() }
            ) {
                navController.navigate("addtoken")
            }
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.CenterStart
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                painter = painterResource(id = R.drawable.search),
                contentDescription = "Search Icon",
                modifier = Modifier.size(24.dp),
                tint = Color.Unspecified
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "Search tokens",
                color = Color.Gray,
                fontSize = 16.sp
            )
        }
    }
}

@Composable
fun ActionButtonsRow(
    navController: NavController,
    tokenViewModel: token_view_model
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        SendButton(navController = navController, tokenViewModel = tokenViewModel)
        ReceiveButton(navController = navController)
        HistoryButton(navController = navController)
    }
}


@Composable
fun SendButton(navController: NavController, tokenViewModel: token_view_model) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    val walletName = loadSelectedWallet(context)
    val userId = getUserIdFromKeystore(context, walletName)

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .wrapContentWidth()
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() }
            ) {
                navController.navigate("sendscreen")
            }
    ) {
        Box(
            modifier = Modifier
                .size(60.dp)
                .background(Color(0x80D7FBE7), shape = CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                painter = painterResource(id = R.drawable.send),
                contentDescription = "Send",
                tint = Color.Unspecified,
                modifier = Modifier.size(24.dp)
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Send",
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = Color.Black
        )
    }
}



@Composable
fun ReceiveButton(navController: NavController) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .wrapContentWidth()
            .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {
                navController.navigate("receive")
            }
    ) {
        Box(
            modifier = Modifier
                .size(60.dp)
                .background(Color(0x80D7F0F1), shape = CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                painter = painterResource(id = R.drawable.receive),
                contentDescription = "Receive",
                tint = Color.Unspecified,
                modifier = Modifier.size(24.dp)
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text("Receive", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.Black)
    }
}

@Composable
fun HistoryButton(navController: NavController) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .wrapContentWidth()
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() }
            ) {
                navController.navigate("history")
            }
    ) {
        Box(
            modifier = Modifier
                .size(60.dp)
                .background(Color(0x80D6E8FF), shape = CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                painter = painterResource(id = R.drawable.history),
                contentDescription = "History",
                tint = Color.Unspecified,
                modifier = Modifier.size(24.dp)
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text("History", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.Black)
    }
}

@Composable
fun TokenTabs(selectedTab: Int, onTabSelected: (Int) -> Unit, indicatorColor: Color = Color(0xFF005FEE)) {
    TabRow(
        selectedTabIndex = selectedTab,
        containerColor = Color.Transparent,
        contentColor = Color(0xFF11c699),
        indicator = { tabPositions ->
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .wrapContentSize(align = Alignment.BottomStart)
                    .offset {
                        IntOffset(
                            x = tabPositions[selectedTab].left.roundToPx(),
                            y = 0
                        )
                    }
                    .width(tabPositions[selectedTab].width)
                    .height(4.dp)
                    .background(indicatorColor)
            )
        }
    ) {
        Tab(
            selected = selectedTab == 0,
            onClick = { onTabSelected(0) },
            selectedContentColor = Color(0xFF11c699),
            unselectedContentColor = Color.Gray
        ) {
            Text("Cryptos", modifier = Modifier.padding(16.dp), fontWeight = FontWeight.Bold)
        }
        Tab(
            selected = selectedTab == 1,
            onClick = { onTabSelected(1) },
            selectedContentColor = Color(0xFF11c699),
            unselectedContentColor = Color.Gray
        ) {
            Text("NFT's", modifier = Modifier.padding(16.dp), fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
fun NoNftFoundMessage(imageSize: Dp = 20.dp, imageTransparency: Float = 0.2f) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Image(
            painter = painterResource(id = R.drawable.card),
            contentDescription = "No NFT Image",
            modifier = Modifier
                .size(imageSize)
                .graphicsLayer(alpha = imageTransparency)
        )
        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "No NFT Found",
            color = Color(0x7E666666),
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

fun saveIsHiddenState(context: Context, isHidden: Boolean) {
    val sharedPreferences = context.getSharedPreferences("app_settings", Context.MODE_PRIVATE)
    sharedPreferences.edit().putBoolean("isHidden", isHidden).apply()
}

fun loadIsHiddenState(context: Context): Boolean {
    val sharedPreferences = context.getSharedPreferences("app_settings", Context.MODE_PRIVATE)
    return sharedPreferences.getBoolean("isHidden", false)
}


@Composable
fun LoadingOverlay(isLoading: Boolean) {
    if (isLoading) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.5f)),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(40.dp),
                color = Color.White
            )
        }
    }
}
