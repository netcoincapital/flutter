package com.laxce.adl.ui.theme.screen

import android.content.Context
import android.content.SharedPreferences
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Divider
import androidx.compose.material.Icon
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.R
import com.laxce.adl.api.Wallet
import androidx.compose.material.*
import androidx.compose.runtime.*
import com.laxce.adl.ui.theme.layout.MainLayout
import com.laxce.adl.utility.loadSelectedWallet
import kotlinx.coroutines.launch
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import com.google.gson.Gson
import java.net.URLEncoder


@Composable
fun WalletsScreen(navController: NavController, wallets: MutableList<Wallet>) {
    var walletsState by remember { mutableStateOf(wallets) }

    // مشاهده تغییرات SharedPreferences
    val context = LocalContext.current
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)

    DisposableEffect(Unit) {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == "user_wallets") {
                val updatedWalletsJson = sharedPreferences.getString("user_wallets", "[]") ?: "[]"
                walletsState = Gson().fromJson(updatedWalletsJson, Array<Wallet>::class.java).toMutableList()
            }
        }
        sharedPreferences.registerOnSharedPreferenceChangeListener(listener)
        onDispose { sharedPreferences.unregisterOnSharedPreferenceChangeListener(listener) }
    }

    MainLayout(navController = navController) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.White)
        ) {
            val context = LocalContext.current
            var selectedWalletName by remember {
                mutableStateOf(loadSelectedWallet(context).ifEmpty {
                    wallets.firstOrNull()?.WalletName.orEmpty()
                })
            }
            var showModal by remember { mutableStateOf(false) }
            val coroutineScope = rememberCoroutineScope()
            val bottomSheetState = rememberModalBottomSheetState(initialValue = ModalBottomSheetValue.Hidden)
            var showDeleteDialog by remember { mutableStateOf(false) }
            var walletToDelete by remember { mutableStateOf("") }

            LaunchedEffect(wallets) {
                if (selectedWalletName.isEmpty() && wallets.isNotEmpty()) {
                    val firstWallet = wallets.first()
                    selectedWalletName = firstWallet.WalletName
                    saveSelectedWallet(context, firstWallet.WalletName, firstWallet.UserID)
                }
            }

            BackHandler {
                try {
                    navController.navigate("settings") {
                        popUpTo("settings") { inclusive = true }
                    }
                } catch (e: Exception) {
                }
            }

            ModalBottomSheetLayout(
                sheetState = bottomSheetState,
                sheetContent = {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .fillMaxHeight(0.9f)
                    ) {
                        AddWalletBottomSheet(
                            onCreateNewWalletClick = {
                                coroutineScope.launch { bottomSheetState.hide() }
                                navController.navigate("insidenewwallet")
                            },
                            onAddExistingWalletClick = {
                                coroutineScope.launch { bottomSheetState.hide() }
                                navController.navigate("insideimportwallet")
                            }
                        )
                    }
                },
                sheetShape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(16.dp)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            text = "Wallets",
                            fontSize = 20.sp,
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
                                    coroutineScope.launch { bottomSheetState.show() }
                                },
                            tint = Color(0x99757575)
                        )
                    }

                    LazyColumn(
                        modifier = Modifier.fillMaxSize()
                    ) {
                        items(wallets) { wallet ->
                            WalletItem(
                                icon = R.drawable.wallet,
                                title = wallet.WalletName,
                                userId = wallet.UserID,
                                backupText = "Back up now",
                                isDefault = wallet.WalletName == selectedWalletName,
                                onWalletClick = { selectedTitle, selectedUserId ->
                                    saveSelectedWallet(context, selectedTitle, selectedUserId)
                                    navController.navigate("home")
                                },
                                onMoreOptionsClick = { walletName ->
                                    if (walletName.isNotEmpty()) {
                                        val encodedWalletName = URLEncoder.encode(walletName, "UTF-8").replace("+", "%20")
                                        navController.navigate("wallet?walletName=$encodedWalletName")
                                    } else {
                                    }
                                },
                                onBackupClick = { walletName ->
                                    val encodedWalletName = URLEncoder.encode(walletName, "UTF-8").replace("+", "%20")
                                    navController.navigate("phrasekeypasscode/$encodedWalletName?showCopy=false")
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
fun WalletItem(
    icon: Int,
    title: String,
    userId: String,
    backupText: String,
    isDefault: Boolean,
    onWalletClick: (String, String) -> Unit,
    onMoreOptionsClick: (String) -> Unit,
    onBackupClick: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp)
            .background(Color(0xFFF7F7F7), shape = RoundedCornerShape(12.dp))
            .clickable { onWalletClick(title, userId) }
            .padding(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                painter = painterResource(id = icon),
                contentDescription = "Wallet Icon",
                modifier = Modifier.size(32.dp),
                tint = Color.Unspecified
            )
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.Black
                )
            }
            if (isDefault) {
                Icon(
                    painter = painterResource(id = R.drawable.badge),
                    contentDescription = "Default Wallet",
                    modifier = Modifier.size(28.dp),
                    tint = Color(0xFF17D27C)
                )
            }
            Icon(
                painter = painterResource(id = R.drawable.more),
                contentDescription = "More Options",
                modifier = Modifier
                    .size(24.dp)
                    .clickable { onMoreOptionsClick(title) },
                tint = Color.Gray
            )
        }

        Text(
            text = backupText,
            fontSize = 14.sp,
            color = Color(0xFF007AFF),
            modifier = Modifier
                .padding(top = 8.dp)
                .clickable { onBackupClick(title) }
        )
    }
}




fun saveSelectedWallet(context: Context, walletName: String, userId: String) {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    sharedPreferences.edit()
        .putString("selected_wallet", walletName)
        .putString("selected_user_id", userId)
        .apply()
}

@Composable
fun AddWalletBottomSheet(
    onCreateNewWalletClick: () -> Unit,
    onAddExistingWalletClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White)
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(150.dp)
                .padding(bottom = 16.dp),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                painter = painterResource(id = R.drawable.cryptowallet),
                contentDescription = "Wallet Icon",
                tint = Color.Unspecified,
                modifier = Modifier.size(300.dp)
            )
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color(0x1463D5B5), shape = RoundedCornerShape(12.dp))
                .padding(16.dp)
                .clickable(
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() }
                ) { onCreateNewWalletClick() },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    painter = painterResource(id = R.drawable.star),
                    contentDescription = "Create New Wallet",
                    tint = Color(0xFF4C70D0),
                    modifier = Modifier.size(32.dp)
                )
                Spacer(modifier = Modifier.width(16.dp))
                Column {
                    Text(
                        text = "Create new wallet",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.Black
                    )
                    Text(
                        text = "Secret phrase or FaceID / fingerprint",
                        fontSize = 12.sp,
                        color = Color.Gray
                    )
                }
            }
            Icon(
                painter = painterResource(id = R.drawable.rightarrow),
                contentDescription = "Arrow Right",
                tint = Color.Gray,
                modifier = Modifier.size(24.dp)
            )
        }

        Spacer(modifier = Modifier.height(8.dp))

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color(0x1463D5B5), shape = RoundedCornerShape(12.dp))
                .padding(16.dp)
                .clickable(
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() }
                ) { onAddExistingWalletClick() },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    painter = painterResource(id = R.drawable.importwallet),
                    contentDescription = "Add Existing Wallet",
                    tint = Color(0xFF4C70D0),
                    modifier = Modifier.size(32.dp)
                )
                Spacer(modifier = Modifier.width(16.dp))
                Column {
                    Text(
                        text = "Add existing wallet",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.Black
                    )
                    Text(
                        text = "Secret phrase, Google Drive or view-only",
                        fontSize = 12.sp,
                        color = Color.Gray
                    )
                }
            }
            Icon(
                painter = painterResource(id = R.drawable.rightarrow),
                contentDescription = "Arrow Right",
                tint = Color.Gray,
                modifier = Modifier.size(24.dp)
            )
        }
    }
}

