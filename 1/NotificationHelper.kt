package com.laxce.adl.utility

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import com.laxce.adl.MainActivity
import com.laxce.adl.R
import android.app.NotificationChannel
import android.app.NotificationManager

class NotificationHelper(private val context: Context) {

    fun cancelAllNotifications() {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancelAll()
    }

    fun deleteNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.deleteNotificationChannel(WELCOME_CHANNEL_ID)
            notificationManager.deleteNotificationChannel(RECEIVE_CHANNEL_ID)
            notificationManager.deleteNotificationChannel(SEND_CHANNEL_ID)
            notificationManager.deleteNotificationChannel(PRICE_ALERT_CHANNEL_ID)
        }
    }


    companion object {
        const val RECEIVE_CHANNEL_ID = "receive_channel"
        const val SEND_CHANNEL_ID = "send_channel"
        const val WELCOME_CHANNEL_ID = "welcome_channel"
        const val PRICE_ALERT_CHANNEL_ID = "price_alert_channel"
        const val CHANNEL_ID = "login_channel_id"
        const val NOTIFICATION_ID = 1
    }


    fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createChannel(RECEIVE_CHANNEL_ID, "Receive Notifications", "receive_sound")
            createChannel(SEND_CHANNEL_ID, "Send Notifications", "send_sound")
            createChannel(WELCOME_CHANNEL_ID, "Welcome Notifications", "welcome_sound")
            createChannel(PRICE_ALERT_CHANNEL_ID, "Price Alert Notifications", "price_alert_sound")
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Login Notifications",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Notifications for user login"
            }

            val notificationManager = context.getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createChannel(channelId: String, channelName: String, soundFileName: String) {
        val soundUri = Uri.parse("android.resource://${context.packageName}/raw/$soundFileName")

        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val channel = NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Channel for $channelName"
            setSound(soundUri, attributes)
        }

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.createNotificationChannel(channel)
    }


    private fun getSoundUri(soundFileName: String): Uri? {
        val resourceId = context.resources.getIdentifier(soundFileName, "raw", context.packageName)
        return if (resourceId != 0) {
            Uri.parse("android.resource://${context.packageName}/raw/$soundFileName")
        } else {
            null
        }
    }

    fun requestNotificationPermission(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {

            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    fun showNotification(channelId: String, title: String, message: String) {
        val sharedPreferences = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        val pushNotificationsEnabled = sharedPreferences.getBoolean("push_notifications", true)

        // اگر اعلان‌ها غیرفعال شده‌اند، هیچ نوتیفیکیشنی ارسال نشود
        if (!pushNotificationsEnabled) {
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent: PendingIntent = PendingIntent.getActivity(
            context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val largeIcon = BitmapFactory.decodeResource(context.resources, R.drawable.logo)

        val notificationId = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.notifsmall)
            .setLargeIcon(largeIcon)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(notificationId, builder.build())
    }

    fun showWelcomeNotification() {
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.notifsmall) // اطمینان حاصل کنید که این آیکون در res/drawable وجود دارد
            .setContentTitle("Welcome")
            .setContentText("Welcome to ADL Wallet")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)

        val notificationManager = NotificationManagerCompat.from(context)
        
        try {
            notificationManager.notify(NOTIFICATION_ID, builder.build())
        } catch (e: SecurityException) {
        }
    }
}





//fun onReceiveTransaction(amount: Double, currency: String) {
//    val notificationHelper = NotificationHelper(context)
//    notificationHelper.showNotification(
//        NotificationHelper.RECEIVE_CHANNEL_ID,
//        "دریافت وجه",
//        "شما $amount $currency دریافت کردید!"
//    )
//}
//
//
//
//fun onSendTransaction(amount: Double, currency: String) {
//    val notificationHelper = NotificationHelper(context)
//    notificationHelper.showNotification(
//        NotificationHelper.SEND_CHANNEL_ID,
//        "ارسال وجه",
//        "شما $amount $currency ارسال کردید!"
//    )
//}
//
//
//
//fun checkPriceAlert(currentPrice: Double, targetPrice: Double) {
//    if (currentPrice >= targetPrice) {
//        val notificationHelper = NotificationHelper(context)
//        notificationHelper.showNotification(
//            NotificationHelper.PRICE_ALERT_CHANNEL_ID,
//            "هشدار قیمت!",
//            "قیمت بیت‌کوین به $currentPrice دلار رسید!"
//        )
//    }
//}
