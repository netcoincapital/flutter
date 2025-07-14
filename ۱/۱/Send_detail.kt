package com.laxce.adl.ui.theme.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import com.laxce.adl.classes.CryptoToken
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.ui.res.painterResource
import com.laxce.adl.R
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.activity.compose.rememberLauncherForActivityResult
import com.google.zxing.integration.android.IntentIntegrator
import android.app.Activity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import com.laxce.adl.MainActivity
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import com.laxce.adl.utility.getCurrencySymbol
import com.laxce.adl.utility.getSelectedCurrency
import com.laxce.adl.viewmodel.token_view_model
import androidx.compose.ui.graphics.Brush
import androidx.compose.material3.rememberModalBottomSheetState
import com.laxce.adl.utility.loadWalletsFromKeystore
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import com.laxce.adl.api.RetrofitClient
import com.laxce.adl.utility.getUserIdFromKeystore
import com.laxce.adl.utility.loadSelectedWallet
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.laxce.adl.api.PrepareTransactionRequest
import com.laxce.adl.api.PrepareTransactionResponse
import android.widget.Toast
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import com.laxce.adl.api.ReceiveRequest
import com.laxce.adl.api.EstimateFeeRequest
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.withStyle
import androidx.compose.foundation.text.ClickableText
import androidx.compose.foundation.layout.navigationBarsPadding
import android.content.Context
import androidx.compose.foundation.Image
import androidx.compose.ui.text.style.TextAlign
import com.laxce.adl.api.Api
import com.laxce.adl.api.ConfirmTransactionRequest
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import com.laxce.adl.api.Transaction
import com.laxce.adl.utility.LocalTransactionCache
import com.laxce.adl.api.PriceData
import kotlinx.coroutines.delay


@OptIn(ExperimentalAnimationApi::class, ExperimentalMaterial3Api::class, ExperimentalStdlibApi::class)
@Composable
fun SendDetailScreen(navController: NavController, token: CryptoToken, tokenViewModel: token_view_model) {
    var address by remember { mutableStateOf("") }
    var amount by remember { mutableStateOf("") }
    var addressError by remember { mutableStateOf(false) }
    val isFormValid = address.isNotBlank() && amount.isNotBlank() && !addressError
    val clipboardManager = LocalClipboardManager.current
    val context = LocalContext.current as Activity
    val selectedCurrency = getSelectedCurrency(context)
    
    var isPriceLoading by remember { mutableStateOf(false) }
    
    val tokenPrices = tokenViewModel.tokenPrices.collectAsState().value
    val pricePerToken = getTokenPriceWithFallback(token.symbol, tokenPrices, selectedCurrency)
    
    val amountValue = amount.toDoubleOrNull() ?: 0.0
    val totalValue = amountValue * pricePerToken
    val showAddressBook = remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState()
    val savedWallets = remember {
        mutableStateOf(loadWalletsFromKeystore(context))
    }
    val api = RetrofitClient.getInstance(context).create(Api::class.java)
    val walletName = loadSelectedWallet(context)
    val userId = getUserIdFromKeystore(context, walletName).orEmpty()
    val showConfirmModal = remember { mutableStateOf(false) }
    val txDetails = remember { mutableStateOf<PrepareTransactionResponse?>(null) }

    var isLoading by remember { mutableStateOf(false) }
    var showSelfTransferErrorModal by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()

    val networkFeeOptions = remember {
        val gasPricesGwei = mapOf(
            "slow" to 10L,
            "average" to 20L,
            "fast" to 30L
        )

        gasPricesGwei.mapValues { (priority, gwei) ->
            val gasPriceWei = gwei * 1_000_000_000L
            val feeWei = 21000L * gasPriceWei
            val feeEth = feeWei.toDouble() / 1e18
            val feeUsd = feeEth * 2000.0

            NetworkFeeOption(
                gasPriceGwei = gwei,
                feeEth = feeEth,
                feeUsd = feeUsd
            )
        }
    }

    val selectedFeeOption = networkFeeOptions["average"]!!

    LaunchedEffect(pricePerToken) {
        // Price loaded
    }

    LaunchedEffect(amount) {
        // Amount changed
    }

    LaunchedEffect(token.symbol) {
        if (pricePerToken <= 0.0 && !tokenViewModel.isLoading) {
            isPriceLoading = true
            tokenViewModel.forceRefresh()
            delay(3000)
            isPriceLoading = false
        }
    }

    val qrScanLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val content = IntentIntegrator.parseActivityResult(result.resultCode, result.data).contents
        if (!content.isNullOrBlank()) {
            val parts = content.split("?")
            val addressPart = parts.getOrNull(0)?.substringAfter(":") ?: ""
            val queryParams = parts.getOrNull(1)?.split("&") ?: emptyList()

            val scannedAddress = addressPart
            var scannedAmount: String? = null

            for (param in queryParams) {
                val keyValue = param.split("=")
                if (keyValue.size == 2 && keyValue[0] == "amount") {
                    scannedAmount = keyValue[1]
                    break
                }
            }

            if (isValidWalletAddress(scannedAddress, token.BlockchainName)) {
                address = scannedAddress
                addressError = false
            } else {
                address = scannedAddress
                addressError = true
            }

            if (!scannedAmount.isNullOrBlank()) {
                amount = scannedAmount
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .padding(horizontal = 16.dp)
    ) {
        Spacer(modifier = Modifier.height(20.dp))

        Text(
            text = "Send ${token.symbol}",
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.align(Alignment.CenterHorizontally)
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(text = "Address or Domain Name", color = Color.Gray, fontSize = 14.sp)

        OutlinedTextField(
            value = address,
            onValueChange = {
                address = it
                addressError = it.isNotBlank() && !isValidWalletAddress(it, token.BlockchainName)
            },
            isError = addressError,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
            placeholder = { Text("Search or Enter") },
            colors = TextFieldDefaults.outlinedTextFieldColors(
                cursorColor = Color(0xFF39b6fb),
                focusedBorderColor = if (addressError) Color.Red else Color(0xFF16B369),
                unfocusedBorderColor = if (addressError) Color.Red else Color.Gray
            ),
            trailingIcon = {
                AnimatedContent(
                    targetState = address.isNotBlank(),
                    transitionSpec = {
                        fadeIn(animationSpec = tween(300)) + expandHorizontally() with
                                fadeOut(animationSpec = tween(300)) + shrinkHorizontally()
                    },
                    label = "TrailingIconSwitcher"
                ) { hasText ->
                    if (!hasText) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = "Paste",
                                color = Color(0xFF08C495),
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier
                                    .padding(end = 10.dp)
                                    .clickable {
                                        val clipboardText = clipboardManager.getText()?.text ?: ""

                                        if (isValidWalletAddress(clipboardText, token.BlockchainName)) {
                                            address = clipboardText
                                            addressError = false
                                        } else {
                                            address = clipboardText
                                            addressError = true
                                        }
                                    }
                            )

                            Box(
                                modifier = Modifier
                                    .size(35.dp)
                                    .clickable { showAddressBook.value = true }
                                    .padding(end = 10.dp)
                            ) {
                                Icon(
                                    painter = painterResource(id = R.drawable.address_book),
                                    contentDescription = "Address Book",
                                    tint = Color(0xFF08C495),
                                    modifier = Modifier.fillMaxSize()
                                )
                            }

                            Box(
                                modifier = Modifier
                                    .size(35.dp)
                                    .clickable {
                                        (context as? MainActivity)?.isQRScannerLaunched = true
                                        IntentIntegrator(context).apply {
                                            setOrientationLocked(false)
                                            setBeepEnabled(true)
                                            captureActivity = com.laxce.adl.classes.CustomCaptureActivity::class.java
                                        }.also {
                                            qrScanLauncher.launch(it.createScanIntent())
                                        }
                                    }
                                    .padding(end = 10.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Default.QrCode,
                                    contentDescription = "QR Code",
                                    tint = Color(0xFF08C495),
                                    modifier = Modifier.fillMaxSize()
                                )
                            }
                        }
                    } else {
                        Box(
                            modifier = Modifier
                                .size(35.dp)
                                .clickable {
                                    address = ""
                                    addressError = false
                                }
                        ) {
                            Icon(
                                painter = painterResource(id = R.drawable.delete),
                                contentDescription = "Clear Input",
                                tint = Color.Gray,
                                modifier = Modifier.fillMaxSize().size(24.dp).padding(end = 8.dp)
                            )
                        }
                    }
                }
            },
            singleLine = true
        )
        if (addressError) {
            Text(
                text = "The wallet address entered is not valid.",
                color = Color.Red,
                fontSize = 12.sp,
                modifier = Modifier.padding(top = 4.dp, start = 8.dp)
            )
        }

        Spacer(modifier = Modifier.height(20.dp))

        Text(text = "Amount", color = Color.Gray, fontSize = 14.sp)

        OutlinedTextField(
            value = amount,
            onValueChange = { amount = it },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
            placeholder = { Text("${token.symbol} Amount") },
            trailingIcon = {
                Row {
                    Text(token.symbol, modifier = Modifier.padding(end = 16.dp))
                    Text(
                        "Max",
                        color = Color(0xFF08C495),
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .padding(end = 16.dp)
                            .clickable {
                                amount = String.format("%.8f", token.amount ?: 0.0)
                            }
                    )
                }
            },
            colors = TextFieldDefaults.outlinedTextFieldColors(
                cursorColor = Color(0xFF39b6fb),
                focusedBorderColor = Color(0xFF16B369),
                unfocusedBorderColor = Color.Gray
            ),
            singleLine = true
        )

        Spacer(modifier = Modifier.height(4.dp))
        
        if (isPriceLoading || pricePerToken <= 0.0) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(top = 4.dp)
            ) {
                Text(
                    text = "Fetching latest price...",
                    color = Color.Gray,
                    fontSize = 12.sp
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
                text = "≈ ${getCurrencySymbol(selectedCurrency)} ${"%.2f".format(totalValue)}",
                color = Color.Gray,
                fontSize = 12.sp,
                modifier = Modifier.padding(top = 4.dp)
            )
        }

        Spacer(modifier = Modifier.height(20.dp))

        Spacer(modifier = Modifier.weight(1f))

        Button(
            onClick = {
                if (isFormValid) {
                    isLoading = true

                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val userId = getUserIdFromKeystore(context, walletName).orEmpty()
                            val normalizedBlockchain = normalizeBlockchainNameForServer(token.BlockchainName)

                            val addressResponse = api.receiveToken(
                                ReceiveRequest(
                                    UserID = userId,
                                    BlockchainName = normalizedBlockchain
                                )
                            )

                            if (!addressResponse.success || addressResponse.PublicAddress == null) {
                                withContext(Dispatchers.Main) {
                                    Toast.makeText(
                                        context,
                                        "Error receiving wallet address: ${addressResponse.message ?: "Address not found"}",
                                        Toast.LENGTH_LONG
                                    ).show()
                                    isLoading = false
                                }
                                return@launch
                            }

                            val senderAddress = addressResponse.PublicAddress

                            if (senderAddress.equals(address, ignoreCase = true)) {
                                withContext(Dispatchers.Main) {
                                    showSelfTransferErrorModal = true
                                    isLoading = false
                                }
                                return@launch
                            }

                            val feeResponse = api.estimateFee(
                                EstimateFeeRequest(
                                    blockchain = normalizeBlockchainNameForServer(token.BlockchainName),
                                    from_address = senderAddress,
                                    to_address = address,
                                    amount = amount.toDouble(),
                                    token_contract = token.SmartContractAddress ?: ""
                                )
                            )

                            if (feeResponse.fee < 0L || (feeResponse.fee == 0L && token.BlockchainName.lowercase() != "tron")) {
                                withContext(Dispatchers.Main) {
                                    Toast.makeText(
                                        context,
                                        "Error receiving network fee: Invalid fee",
                                        Toast.LENGTH_LONG
                                    ).show()
                                }
                                return@launch
                            }

                            val actualAmount = amount.toDoubleOrNull()?.let {
                                val diff = Math.abs(it - (token.amount ?: 0.0))

                                if (diff < 0.0000001) {
                                    val blockchainType = getBlockchainType(token.BlockchainName)
                                    val maxAmount = blockchainType.calculateMaxAmount(
                                        tokenAmount = token.amount ?: 0.0,
                                        fee = selectedFeeOption.feeEth
                                    )
                                    maxAmount
                                } else {
                                    it
                                }
                            } ?: 0.0

                            val validationResult = validateTransactionAmount(
                                amount = actualAmount.toString(),
                                fee = (selectedFeeOption.feeEth * 1e18).toLong(),
                                feeCurrency = feeResponse.fee_currency,
                                blockchainName = token.BlockchainName
                            )

                            if (!validationResult.isValid) {
                                withContext(Dispatchers.Main) {
                                    Toast.makeText(
                                        context,
                                        validationResult.message,
                                        Toast.LENGTH_LONG
                                    ).show()
                                }
                                return@launch
                            }

                            val sendAmount = String.format("%.8f", actualAmount)

                            val prepareRequest = PrepareTransactionRequest(
                                blockchain_name = normalizeBlockchainNameForServer(token.BlockchainName).lowercase(),
                                sender_address = senderAddress,
                                recipient_address = address,
                                amount = sendAmount,
                                smart_contract_address = token.SmartContractAddress ?: ""
                            )

                            val response = api.prepareTransaction(prepareRequest)

                            withContext(Dispatchers.Main) {
                                if (response.success) {
                                    txDetails.value = response
                                    showConfirmModal.value = true

                                    val pendingTx = Transaction(
                                        amount = response.details.amount,
                                        assetType = "crypto",
                                        blockchainName = token.symbol,
                                        direction = "outbound",
                                        explorerUrl = response.details.explorer_url ?: "",
                                        fee = response.details.estimated_fee,
                                        from = response.details.sender,
                                        price = "0.0",
                                        timestamp = LocalDateTime.now().format(DateTimeFormatter.ISO_DATE_TIME),
                                        to = response.details.recipient,
                                        tokenSymbol = token.symbol,
                                        txHash = response.transaction_id ?: "pending_${System.currentTimeMillis()}",
                                        status = "pending",
                                        tokenContract = token.SmartContractAddress ?: "",
                                        temporaryId = java.util.UUID.randomUUID().toString()
                                    )
                                    LocalTransactionCache.add(pendingTx)
                                } else {
                                    Toast.makeText(context, "Server error: ${response.message}", Toast.LENGTH_LONG).show()
                                }

                                isLoading = false
                            }
                        } catch (httpError: retrofit2.HttpException) {
                            val code = httpError.code()
                            val errorBody = httpError.response()?.errorBody()?.string() ?: "No error details"

                            withContext(Dispatchers.Main) {
                                Toast.makeText(context, "Server error: $code - $errorBody", Toast.LENGTH_LONG).show()
                                isLoading = false
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                Toast.makeText(context, "Error preparing transaction: ${e.message}", Toast.LENGTH_LONG).show()
                                isLoading = false
                            }
                        }
                    }
                }
            },
            enabled = isFormValid && !isLoading,
            modifier = Modifier
                .fillMaxWidth()
                .height(65.dp)
                .padding(bottom = 15.dp),
            shape = RoundedCornerShape(25.dp),
            colors = ButtonDefaults.buttonColors(
                backgroundColor = Color(0xFF08C495),
                contentColor = Color.White
            ),
            elevation = null
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    color = Color.White,
                    strokeWidth = 2.dp
                )
            } else {
                Text("Next", fontSize = 16.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
    if (showAddressBook.value) {
        ModalBottomSheet(
            onDismissRequest = { showAddressBook.value = false },
            sheetState = sheetState,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp),
            containerColor = Color(0xFFFFFFFF)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(600.dp)
                    .padding(horizontal = 8.dp, vertical = 10.dp)
            ) {
                Text(
                    text = "Address Book",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.Black,
                    modifier = Modifier.align(Alignment.CenterHorizontally)
                )

                Spacer(modifier = Modifier.height(10.dp))

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.White.copy(alpha = 0.6f), RoundedCornerShape(12.dp))
                ) {
                    LazyColumn {
                        items(savedWallets.value) { (name, walletAddress) ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        address = walletAddress
                                        addressError = !isValidWalletAddress(walletAddress, token.BlockchainName)
                                        showAddressBook.value = false
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
                                    .padding(horizontal = 14.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = name,
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color.White
                                    )
                                    Text(
                                        text = walletAddress,
                                        fontSize = 12.sp,
                                        color = Color.White.copy(alpha = 0.9f)
                                    )
                                }

                                Icon(
                                    painter = painterResource(id = R.drawable.rightarrow),
                                    contentDescription = null,
                                    modifier = Modifier.size(18.dp)
                                )
                            }

                            Spacer(modifier = Modifier.height(10.dp))
                        }
                    }
                }
            }
        }
    }

    txDetails.value?.let { tx ->
        if (tx.transaction_id != null) {
            val feeAmount = tx.details.estimated_fee.toDoubleOrNull() ?: 0.0
            val currentPrices = tokenViewModel.tokenPrices.collectAsState().value
            val currentPrice = getTokenPriceWithFallback(token.symbol, currentPrices, selectedCurrency)
            val feeUsd = feeAmount * currentPrice

            TransactionConfirmModal(
                amount = tx.details.amount,
                dollarValue = "≈ $${"%.2f".format(totalValue)}",
                assetName = token.symbol,
                walletName = walletName,
                walletAddress = tx.details.sender,
                recipient = tx.details.recipient,
                networkFee = tx.details.estimated_fee,
                networkFeeFiat = "≈ $${"%.2f".format(feeUsd)}",
                show = showConfirmModal.value,
                onDismiss = {
                    showConfirmModal.value = false
                },
                onConfirm = {
                    coroutineScope.launch {
                        var confirmationSuccess = false
                        try {
                            val blockchainNameForServer = normalizeBlockchainNameForServer(token.BlockchainName).lowercase()
                            val confirmAmount = try { 
                                String.format("%.8f", tx.details.amount.toDouble()) 
                            } catch (e: Exception) { 
                                tx.details.amount 
                            }

                            if (tx.transaction_id.isNullOrBlank()) {
                                withContext(Dispatchers.Main) {
                                    Toast.makeText(context, "Invalid transaction ID", Toast.LENGTH_LONG).show()
                                }
                                return@launch
                            }

                            val confirmRequest = ConfirmTransactionRequest(
                                transaction_id = tx.transaction_id,
                                sender_address = tx.details.sender,
                                recipient_address = tx.details.recipient,
                                amount = confirmAmount,
                                blockchain_name = blockchainNameForServer
                            )

                            val confirmResponse = api.confirmTransaction(confirmRequest)
                            withContext(Dispatchers.Main) {
                                if (confirmResponse.success) {
                                    confirmationSuccess = true
                                    navController.navigate("history") {
                                        popUpTo("home") { inclusive = false }
                                    }
                                } else {
                                    Toast.makeText(
                                        context,
                                        "Transaction confirmation failed: ${confirmResponse.message}",
                                        Toast.LENGTH_LONG
                                    ).show()
                                }
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                Toast.makeText(
                                    context,
                                    "Error: ${e.message}",
                                    Toast.LENGTH_LONG
                                ).show()
                            }
                        } finally {
                            // فقط اگر موفقیت‌آمیز بود، مودال را ببند
                            if (confirmationSuccess) {
                                showConfirmModal.value = false
                            }
                        }
                    }
                },
                transactionId = tx.transaction_id,
                context = context
            )
        }
    }

    // نمایش مودال خطای ارسال به خود
    if (showSelfTransferErrorModal) {
        ErrorModal(
            show = true,
            onDismiss = { showSelfTransferErrorModal = false },
            message = "You cannot send assets to your own address.",
            title = "Transaction Error"
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TransactionConfirmModal(
    amount: String,
    dollarValue: String,
    assetName: String,
    walletName: String,
    walletAddress: String,
    recipient: String,
    networkFee: String = "0.00",
    networkFeeFiat: String = "$0.00",
    show: Boolean,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
    transactionId: String?,
    context: Context
) {
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { true }
    )

    var isSending by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var showErrorModal by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()
    
    // محاسبه مقدار کل با کسر کارمزد
    val dollarValueNumber = dollarValue.replace("≈ $", "").toDoubleOrNull() ?: 0.0
    val feeValueNumber = networkFeeFiat.replace("≈ $", "").toDoubleOrNull() ?: 0.0
    val totalValue = (dollarValueNumber - feeValueNumber).coerceAtLeast(0.0)
    val formattedTotalValue = "≈ $${String.format("%.2f", totalValue)}"

    // لاگ برای اطلاعات مودال
    LaunchedEffect(Unit) {
        if (show) {
            val logMessage = "amount=$amount, asset=$assetName, " +
                "from=$walletAddress, to=$recipient, fee=$networkFee, " +
                "transactionId=$transactionId"
        }
    }

    if (show) {
        val configuration = LocalConfiguration.current
        val screenHeight = configuration.screenHeightDp.dp

        ModalBottomSheet(
            onDismissRequest = onDismiss,
            sheetState = sheetState,
            shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
            containerColor = Color.White,
            scrimColor = Color.Black.copy(alpha = 0.6f),
            dragHandle = null
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(0.9f)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 20.dp, vertical = 24.dp)
                ) {
                    // مقدار منفی در بالا با سایز بزرگ
                    Text(
                        text = "-$amount",
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF000000),
                        modifier = Modifier.align(Alignment.CenterHorizontally)
                    )

                    // معادل دلاری
                    Text(
                        text = dollarValue,
                        fontSize = 14.sp,
                        color = Color.Gray,
                        modifier = Modifier
                            .align(Alignment.CenterHorizontally)
                            .padding(bottom = 24.dp)
                    )

                    // جدول اطلاعات
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Asset", color = Color.Gray, fontSize = 14.sp)
                        Text(assetName, fontWeight = FontWeight.Medium, fontSize = 14.sp)
                    }

                    Divider(color = Color(0xFFEEEEEE), thickness = 1.dp)

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Wallet", color = Color.Gray, fontSize = 14.sp)
                        Column(horizontalAlignment = Alignment.End) {
                            Text(walletName, fontWeight = FontWeight.Medium, fontSize = 14.sp)
                            Text(
                                walletAddress.take(10) + "..." + walletAddress.takeLast(6),
                                color = Color.Gray,
                                fontSize = 12.sp
                            )
                        }
                    }

                    Divider(color = Color(0xFFEEEEEE), thickness = 1.dp)

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("To", color = Color.Gray, fontSize = 14.sp)
                        Text(
                            recipient.take(10) + "..." + recipient.takeLast(6),
                            fontWeight = FontWeight.Medium,
                            fontSize = 14.sp
                        )
                    }

                    Divider(color = Color(0xFFEEEEEE), thickness = 1.dp)
                    
                    // نمایش کارمزد تخمینی
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Estimated Fee", color = Color.Gray, fontSize = 14.sp)
                        Column(horizontalAlignment = Alignment.End) {
                            Text(networkFee, fontWeight = FontWeight.Medium, fontSize = 14.sp)
                            Text(
                                networkFeeFiat,
                                color = Color.Gray,
                                fontSize = 12.sp
                            )
                        }
                    }

                    Divider(color = Color(0xFFEEEEEE), thickness = 1.dp)

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Max Total", color = Color.Gray, fontSize = 14.sp)
                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                formattedTotalValue,
                                fontWeight = FontWeight.Medium, 
                                fontSize = 14.sp
                            )
                            Text(
                                "(Amount - Fee)",
                                color = Color.Gray,
                                fontSize = 10.sp
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // پیام خطا (در صورت نیاز)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(Color(0xFFFFF3E0), RoundedCornerShape(4.dp))
                            .padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            painter = painterResource(id = R.drawable.info),
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        val annotatedText = buildAnnotatedString {
                            append("Insufficient $assetName balance ")
                            pushStringAnnotation(tag = "learn_more", annotation = "learn_more")
                            withStyle(style = SpanStyle(color = Color(0xFF1A73E8))) {
                                append("Learn more")
                            }
                            pop()
                        }
                        ClickableText(
                            text = annotatedText,
                            style = androidx.compose.ui.text.TextStyle(fontSize = 12.sp, color = Color(0xFF333333)),
                            modifier = Modifier.padding(start = 0.dp),
                            onClick = { offset ->
                                // اکشن مربوط به Learn more
                            }
                        )
                    }
                    
                    Spacer(modifier = Modifier.height(15.dp)) // فاصله ۱۵dp از بالای دکمه Send

                    Spacer(modifier = Modifier.height(16.dp))

                    // Show error message if any
                    errorMessage?.let { error ->
                        Text(
                            text = error,
                            color = Color.Red,
                            fontSize = 14.sp,
                            modifier = Modifier.padding(bottom = 16.dp)
                        )
                    }

                    Spacer(modifier = Modifier.height(16.dp))
                }

                // Send button at the bottom
                Button(
                    onClick = {
                        if (!isSending && transactionId != null) {
                            isSending = true
                            errorMessage = null
                            onConfirm()
                        }
                    },
                    enabled = !isSending && transactionId != null,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(65.dp)
                        .align(Alignment.BottomCenter)
                        .padding(horizontal = 20.dp)
                        .navigationBarsPadding()
                        .padding(bottom = 16.dp),
                    colors = ButtonDefaults.buttonColors(
                        backgroundColor = Color(0xFF08C495),
                        contentColor = Color.White
                    ),
                    shape = RoundedCornerShape(25.dp),
                    elevation = null
                ) {
                    if (isSending) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            color = Color.White,
                            strokeWidth = 2.dp
                        )
                    } else {
                        Text(
                            text = "Send $assetName",
                            fontWeight = FontWeight.Bold,
                            fontSize = 16.sp,
                            modifier = Modifier.align(Alignment.CenterVertically)
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ErrorModal(
    show: Boolean,
    onDismiss: () -> Unit,
    message: String,
    title: String = "Error"
) {
    if (show) {
        ModalBottomSheet(
            onDismissRequest = onDismiss,
            sheetState = rememberModalBottomSheetState(
                skipPartiallyExpanded = true,
                confirmValueChange = { true }
            ),
            shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
            containerColor = Color.White,
            scrimColor = Color.Black.copy(alpha = 0.6f),
            dragHandle = null
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Image(
                    painter = painterResource(id = R.drawable.error),
                    contentDescription = "Error",
                    modifier = Modifier
                        .size(48.dp)
                        .padding(bottom = 16.dp)
                )

                Text(
                    text = title,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.Black,
                    modifier = Modifier.padding(bottom = 8.dp)
                )

                Text(
                    text = message,
                    fontSize = 16.sp,
                    color = Color.Gray,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(bottom = 24.dp)
                )

                Button(
                    onClick = onDismiss,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp),
                    colors = ButtonDefaults.buttonColors(
                        backgroundColor = Color(0xFFFF1961),
                        contentColor = Color.White
                    ),
                    shape = RoundedCornerShape(25.dp)
                ) {
                    Text("OK", fontSize = 16.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
fun TransactionDetailRow(label: String, value: String, isDiscount: Boolean = false) {
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Text(text = label, color = Color.Gray, fontSize = 14.sp)
        if (isDiscount) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "100% Discount",
                    color = Color(0xFF08C495),
                    fontWeight = FontWeight.Bold,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(end = 6.dp)
                )
                Text(value.split("\n").last(), fontSize = 14.sp)
            }
        } else {
            Text(text = value, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        }
    }
}



fun isValidWalletAddress(address: String, blockchainName: String): Boolean {
    val blockchainType = getBlockchainType(blockchainName)
    return blockchainType.validateAddress(address)
}

// تابع کمکی برای بررسی مقدار تراکنش و کارمزد
private fun validateTransactionAmount(
    amount: String,
    fee: Long,
    feeCurrency: String,
    blockchainName: String
): TransactionValidationResult {
    return try {
        val amountDouble = amount.toDouble()

        // در همه‌ی شبکه‌ها مقدار رو به Wei محاسبه کن (برای سادگی)
        val amountInWei = (amountDouble * 1e18).toLong()

        return if (amountInWei > fee) {
            val remainingAmount = amountInWei - fee
            val remainingInEth = remainingAmount.toDouble() / 1e18

            TransactionValidationResult(
                isValid = true,
                remainingAmount = remainingAmount,
                remainingInEth = remainingInEth,
                message = "Transaction is valid."
            )
        } else {
            TransactionValidationResult(
                isValid = false,
                remainingAmount = 0,
                remainingInEth = 0.0,
                message = "Transaction amount is less than the network fee."
            )
        }
    } catch (e: Exception) {
        TransactionValidationResult(
            isValid = false,
            remainingAmount = 0,
            remainingInEth = 0.0,
            message = "Error calculating values: ${e.message}"
        )
    }
}

// کلاس برای نگهداری نتیجه بررسی تراکنش
data class TransactionValidationResult(
    val isValid: Boolean,
    val remainingAmount: Long,
    val remainingInEth: Double,
    val message: String
)

// تعریف مدل برای نمایش کارمزد شبکه
data class NetworkFeeOption(
    val gasPriceGwei: Long,
    val feeEth: Double,
    val feeUsd: Double
)

// Helper function to normalize blockchain name for server
fun normalizeBlockchainNameForServer(name: String): String {
    return when (name.trim().lowercase()) {
        "binance smart chain", "bnb smart chain", "binance", "bsc", "bnb chain", "binancecoin" -> "bsc"
        else -> name
    }
}

// Blockchain-specific logic classes
sealed class BlockchainType {
    abstract fun calculateMaxAmount(tokenAmount: Double, fee: Double): Double
    abstract fun validateAddress(address: String): Boolean
    abstract fun calculateNetworkFee(amount: Double, gasPrice: Long, gasUsed: Long): Double
    abstract fun formatAmount(amount: Double): String
}

object EVMBlockchain : BlockchainType() {
    override fun calculateMaxAmount(tokenAmount: Double, fee: Double): Double {
        val amountInWei = (tokenAmount * 1e18).toLong()
        val feeInWei = (fee * 1e18).toLong()
        val remainingWei = amountInWei - feeInWei
        return remainingWei.toDouble() / 1e18
    }

    override fun validateAddress(address: String): Boolean {
        return address.startsWith("0x") && address.length == 42
    }

    override fun calculateNetworkFee(amount: Double, gasPrice: Long, gasUsed: Long): Double {
        return (gasPrice * gasUsed).toDouble() / 1e18
    }

    override fun formatAmount(amount: Double): String {
        return String.format("%.8f", amount)
    }
}

object TRONBlockchain : BlockchainType() {
    override fun calculateMaxAmount(tokenAmount: Double, fee: Double): Double {
        // For TRON, we don't subtract fee as it's handled differently
        return tokenAmount
    }

    override fun validateAddress(address: String): Boolean {
        return address.startsWith("T") && address.length == 34
    }

    override fun calculateNetworkFee(amount: Double, gasPrice: Long, gasUsed: Long): Double {
        // TRON uses bandwidth and energy instead of gas
        return 0.0
    }

    override fun formatAmount(amount: Double): String {
        return String.format("%.6f", amount)
    }
}

object BitcoinBlockchain : BlockchainType() {
    override fun calculateMaxAmount(tokenAmount: Double, fee: Double): Double {
        // Bitcoin uses UTXO model, fee calculation is more complex
        return tokenAmount - fee
    }

    override fun validateAddress(address: String): Boolean {
        return (address.startsWith("bc1") && address.length in 42..62) ||
                ((address.startsWith("1") || address.startsWith("3")) && address.length in 26..35)
    }

    override fun calculateNetworkFee(amount: Double, gasPrice: Long, gasUsed: Long): Double {
        // Bitcoin uses sat/byte instead of gas
        return gasPrice.toDouble() / 1e8
    }

    override fun formatAmount(amount: Double): String {
        return String.format("%.8f", amount)
    }
}

// Helper function to get blockchain type
fun getBlockchainType(blockchainName: String): BlockchainType {
    return when (blockchainName.lowercase()) {
        "tron", "trx" -> TRONBlockchain
        "bitcoin", "btc" -> BitcoinBlockchain
        else -> EVMBlockchain // Default to EVM for other chains
    }
}

// Helper function to safely get token price with fallbacks to ensure a price is always available
@OptIn(ExperimentalStdlibApi::class)
private fun getTokenPriceWithFallback(
    tokenSymbol: String,
    prices: Map<String, Map<String, PriceData>>,
    selectedCurrency: String
): Double {
    // 1. Try direct symbol match first
    val standardPrice = prices[tokenSymbol]?.get(selectedCurrency)?.price?.replace(",", "")?.toDoubleOrNull()
    
    if (standardPrice != null && standardPrice > 0.0) {
        return standardPrice
    }
    
    // 2. Try variations of symbol name (uppercase, lowercase, etc.)
    val variations = listOf(
        tokenSymbol.lowercase(),
        tokenSymbol.uppercase(),
        tokenSymbol.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() },
        // Special mappings for common tokens with inconsistent naming
        if (tokenSymbol.equals("TRX", ignoreCase = true)) "tron" else null,
        if (tokenSymbol.equals("BNB", ignoreCase = true)) "binance" else null,
        if (tokenSymbol.equals("BTC", ignoreCase = true)) "bitcoin" else null,
        if (tokenSymbol.equals("ETH", ignoreCase = true)) "ethereum" else null,
        if (tokenSymbol.equals("SHIB", ignoreCase = true)) "shiba inu" else null
    ).filterNotNull()
    
    // Try all variations
    for (symbol in variations) {
        val price = prices[symbol]?.get(selectedCurrency)?.price?.replace(",", "")?.toDoubleOrNull()
        if (price != null && price > 0.0) {
            return price
        }
    }
    return 0.0
}
