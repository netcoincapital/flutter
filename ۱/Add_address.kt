package com.laxce.adl.ui.theme.screen

import android.content.Context
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

@Composable
fun AddAddressScreen(navController: NavController) {
    val context = navController.context

    // State variables for inputs
    var walletName by remember { mutableStateOf("") }
    var walletAddress by remember { mutableStateOf("") }

    // Regular Expression to allow only alphanumeric characters
    val regex = Regex("^[a-zA-Z0-9 ]*$")

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
                text = "Add Wallet Address",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
            Text(
                text = "Save",
                fontSize = 16.sp,
                color = Color(0xFF16B369),
                modifier = Modifier
                    .padding(end = 16.dp)
                    .clickable {
                        if (walletName.isNotEmpty() && walletAddress.isNotEmpty()) {
                            saveWalletToKeystore(context, walletName, walletAddress)
                            navController.popBackStack() // Return to previous screen
                        }
                    }
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Wallet Name Input
        Text(text = "Wallet Name", fontSize = 14.sp, color = Color.Gray)
        OutlinedTextField(
            value = walletName,
            onValueChange = {
                if (regex.matches(it)) {
                    walletName = it
                }
            },
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

        // Wallet Address Input
        Text(text = "Wallet Address", fontSize = 14.sp, color = Color.Gray)
        OutlinedTextField(
            value = walletAddress,
            onValueChange = {
                if (regex.matches(it)) {
                    walletAddress = it
                }
            },
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
    }
}

// Function to save wallet information to Keystore
fun saveWalletToKeystore(context: Context, walletName: String, walletAddress: String) {
    val sharedPreferences = context.getSharedPreferences("app_keystore", Context.MODE_PRIVATE)
    val editor = sharedPreferences.edit()

    // ذخیره نام و آدرس کیف پول
    editor.putString("wallet_name_$walletName", walletName)
    editor.putString("wallet_address_$walletName", walletAddress)

    editor.apply() // اعمال تغییرات
}
