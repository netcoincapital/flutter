package com.laxce.adl.ui.theme.screen

import android.content.Context
import androidx.compose.foundation.background
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

@Composable
fun EditWalletScreen(
    navController: NavController,
    walletName: String,
    walletAddress: String
) {
    var updatedWalletName by remember { mutableStateOf(walletName) }
    var updatedWalletAddress by remember { mutableStateOf(walletAddress) }
    var showDeleteDialog by remember { mutableStateOf(false) }

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
                text = "Edit Wallet",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )

            TextButton(
                onClick = {
                    updateWalletInKeystore(
                        context = navController.context,
                        oldWalletName = walletName,
                        newWalletName = updatedWalletName,
                        newWalletAddress = updatedWalletAddress
                    )
                    navController.popBackStack()
                }
            ) {
                Text(text = "Save", fontSize = 16.sp, color = Color(0xFF16B369))
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Wallet Name
        Text(text = "Wallet Name", fontSize = 14.sp, color = Color.Gray)
        OutlinedTextField(
            value = updatedWalletName,
            onValueChange = { updatedWalletName = it },
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            shape = RoundedCornerShape(8.dp),
            singleLine = true,
            colors = TextFieldDefaults.outlinedTextFieldColors(
                cursorColor = Color(0xFF39b6fb),
                focusedBorderColor = Color(0xFF16B369), // سبز برای حالت انتخاب
                unfocusedBorderColor = Color.Gray       // خاکستری برای حالت عادی
            )

        )

        Spacer(modifier = Modifier.height(16.dp))

        // Wallet Address
        Text(text = "Wallet Address", fontSize = 14.sp, color = Color.Gray)
        OutlinedTextField(
            value = updatedWalletAddress,
            onValueChange = { updatedWalletAddress = it },
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            shape = RoundedCornerShape(8.dp),
            singleLine = true,
            colors = TextFieldDefaults.outlinedTextFieldColors(
                cursorColor = Color(0xFF39b6fb),
                focusedBorderColor = Color(0xFF16B369), // سبز برای حالت انتخاب
                unfocusedBorderColor = Color.Gray       // خاکستری برای حالت عادی
            )
        )

        Spacer(modifier = Modifier.weight(1f))

        // Delete Button
        Button(
            onClick = { showDeleteDialog = true },
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp),
            shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.buttonColors(
                backgroundColor = Color(0xFFDC0303),
                contentColor = Color.White
            )
        ) {
            Text(text = "Delete", fontSize = 16.sp)
        }
    }

    // Delete Confirmation Dialog
    if (showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = {
                Text(text = "Delete Wallet")
            },
            text = {
                Text(text = "Are you sure you want to delete this wallet?")
            },
            confirmButton = {
                TextButton(onClick = {
                    deleteWalletFromKeystore(
                        context = navController.context,
                        walletName = walletName
                    )
                    showDeleteDialog = false
                    navController.popBackStack()
                }) {
                    Text("Delete", color = Color(0xFFDC0303))
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}


// Function to delete wallet from Keystore
fun deleteWalletFromKeystore(context: Context, walletName: String) {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    val editor = sharedPreferences.edit()

    editor.remove("wallet_name_$walletName")
    editor.remove("wallet_address_$walletName")
    editor.remove("wallet_description_$walletName")

    editor.apply() // Apply changes
}

// Function to update wallet in Keystore
fun updateWalletInKeystore(
    context: Context,
    oldWalletName: String,
    newWalletName: String,
    newWalletAddress: String
) {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    val editor = sharedPreferences.edit()

    // Remove old wallet data if the name has changed
    if (oldWalletName != newWalletName) {
        editor.remove("wallet_name_$oldWalletName")
        editor.remove("wallet_address_$oldWalletName")
    }

    // Save updated wallet data
    editor.putString("wallet_name_$newWalletName", newWalletName)
    editor.putString("wallet_address_$newWalletName", newWalletAddress)

    editor.apply() // Apply changes
}
