package com.laxce.adl.ui.theme.screen

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.utility.NotificationHelper
import android.app.NotificationManager
import androidx.compose.ui.text.font.FontWeight
import com.laxce.adl.ui.theme.layout.MainLayout

@Composable
fun NotificationScreen(navController: NavController, context: Context) {
    val sharedPreferences = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
    val notificationHelper = remember { NotificationHelper(context) }

    var pushNotifications by remember {
        mutableStateOf(sharedPreferences.getBoolean("push_notifications", true))
    }
    var sendAndReceive by remember {
        mutableStateOf(sharedPreferences.getBoolean("send_and_receive", false))
    }
    var productAnnouncements by remember {
        mutableStateOf(sharedPreferences.getBoolean("product_announcements", true))
    }

    LaunchedEffect(pushNotifications) {
        with(sharedPreferences.edit()) {
            putBoolean("push_notifications", pushNotifications)
            apply()
        }
        if (!pushNotifications) {
            sendAndReceive = false
            productAnnouncements = false
            notificationHelper.cancelAllNotifications()
            notificationHelper.deleteNotificationChannels()
        } else {
            enableNotifications(context)
        }
    }

    LaunchedEffect(sendAndReceive) {
        with(sharedPreferences.edit()) {
            putBoolean("send_and_receive", sendAndReceive)
            apply()
        }
    }

    LaunchedEffect(productAnnouncements) {
        with(sharedPreferences.edit()) {
            putBoolean("product_announcements", productAnnouncements)
            apply()
        }
    }
    MainLayout(navController = navController) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.White)
                .padding(16.dp),
            horizontalAlignment = Alignment.Start
        ) {
            Text(
                text = "Notifications",
                fontSize = 20.sp,
                fontWeight = FontWeight(600),
                color = Color.Black,
                modifier = Modifier.padding(bottom = 16.dp)
            )

            NotificationItem(
                title = "Allow push notifications",
                description = "Activate or deactivate push notifications",
                state = pushNotifications,
                onToggle = {
                    pushNotifications = it
                    with(sharedPreferences.edit()) {
                        putBoolean("push_notifications", pushNotifications)
                        apply()
                    }
                    if (!it) {
                        notificationHelper.cancelAllNotifications()
                        notificationHelper.deleteNotificationChannels()
                    } else {
                        enableNotifications(context)
                    }
                },
                switchColor = Color(0xFF27B6AC)
            )

            NotificationItem(
                title = "Send and receive",
                description = "Get notified when sending or receiving",
                state = sendAndReceive,
                onToggle = {
                    sendAndReceive = it
                    with(sharedPreferences.edit()) {
                        putBoolean("send_and_receive", sendAndReceive)
                        apply()
                    }
                    if (!it) {
                        notificationHelper.cancelAllNotifications()
                    }
                },
                enabled = pushNotifications,
                switchColor = Color(0xFF27B6AC)
            )
        }
    }
}

fun enableNotifications(context: Context) {
    val notificationHelper = NotificationHelper(context)
    notificationHelper.createNotificationChannels()
}

@Composable
fun CustomSwitch(checked: Boolean, onCheckedChange: (Boolean) -> Unit, switchColor: Color) {
    Row(
        modifier = Modifier
            .width(50.dp)
            .height(28.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(if (checked) switchColor else Color.Gray)
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

@Composable
fun NotificationItem(title: String, description: String? = null, state: Boolean, onToggle: (Boolean) -> Unit, enabled: Boolean = true, switchColor: Color) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, fontSize = 16.sp, color = Color.Black)
            description?.let {
                Text(text = it, fontSize = 14.sp, color = Color.Gray)
            }
        }
        CustomSwitch(checked = state, onCheckedChange = onToggle, switchColor = switchColor)
    }
}
