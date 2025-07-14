package com.laxce.adl.ui.theme.screen

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.R
import java.util.concurrent.TimeUnit

@Composable
fun SecurityScreen(navController: NavController, initialAutoLockOption: String, onAutoLockSelected: (String, Long) -> Unit
) {
    var showAutoLockDialog by remember { mutableStateOf(false) }
    var selectedAutoLockOption by remember { mutableStateOf(initialAutoLockOption) } // ذخیره گزینه انتخاب‌شده

    BackHandler {
        navController.navigate("settings") {
            popUpTo("security") { inclusive = true }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        Text(
            text = "Security",
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(bottom = 16.dp)
        )

        SettingItemWithSwitch(
            title = "Passcode",
            subtitle = "",
            initialChecked = true,
            onCheckedChange = { /* Handle change */ }
        )

        SettingItem(
            title = "Auto-lock",
            subtitle = selectedAutoLockOption,
            onClick = { showAutoLockDialog = true }
        )

        SettingItem(
            title = "Lock method",
            subtitle = "Passcode / Biometric",
            onClick = { /* Handle click */ }
        )
    }

    if (showAutoLockDialog) {
        AutoLockDialog(
            onDismiss = { showAutoLockDialog = false },
            onOptionSelected = { label, timeout ->
                selectedAutoLockOption = label
                onAutoLockSelected(label, timeout) // ارسال مقدار جدید به MainActivity
                showAutoLockDialog = false
            }
        )
    }
}


@Composable
fun AutoLockDialog(
    onDismiss: () -> Unit,
    onOptionSelected: (String, Long) -> Unit // ارسال نام و زمان انتخاب‌شده
) {
    val options = listOf(
        "Immediate" to 0L,
        "1 min" to TimeUnit.MINUTES.toMillis(1),
        "5 min" to TimeUnit.MINUTES.toMillis(5),
        "10 min" to TimeUnit.MINUTES.toMillis(10),
        "15 min" to TimeUnit.MINUTES.toMillis(15)
    )

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(text = "Select Auto-lock Time")
        },
        text = {
            Column {
                options.forEach { (label, timeout) ->
                    Text(
                        text = label,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onOptionSelected(label, timeout) } // ارسال گزینه انتخاب‌شده
                            .padding(vertical = 8.dp),
                        fontSize = 16.sp
                    )
                }
            }
        },
        confirmButton = {}
    )
}


@Composable
fun SettingItemWithSwitch(
    title: String,
    subtitle: String,
    initialChecked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    var isChecked by remember { mutableStateOf(initialChecked) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                color = Color.Black
            )
            if (subtitle.isNotEmpty()) {
                Text(
                    text = subtitle,
                    fontSize = 12.sp,
                    color = Color.Gray
                )
            }
        }
        Switch(
            checked = isChecked,
            onCheckedChange = {
                isChecked = it
                onCheckedChange(it)
            }
        )
    }
}

@Composable
fun SettingItem(
    title: String,
    subtitle: String,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                color = Color.Black
            )
            if (subtitle.isNotEmpty()) {
                Text(
                    text = subtitle,
                    fontSize = 12.sp,
                    color = Color.Gray
                )
            }
        }
    }
}
