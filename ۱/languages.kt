package com.laxce.adl.ui.theme.screen

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.content.res.XmlResourceParser
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Divider
import androidx.compose.material.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.laxce.adl.R
import java.util.*

@Composable
fun LanguageSettingsScreen(context: Context, onLanguageSelected: (String) -> Unit) {
    // بارگذاری زبان‌های پیشنهادی از strings.xml
    val languageNames = context.resources.getStringArray(R.array.suggested_languages).toList()
    val languageCodes = context.resources.getStringArray(R.array.suggested_language_codes).toList()
    val suggestedLanguages = languageNames.zip(languageCodes)

    // بارگذاری زبان‌های کامل از locales_config.xml
    val allLanguages = loadAllLanguages(context)

    // State برای زبان انتخاب‌شده
    var selectedLanguage by remember { mutableStateOf(loadLanguage(context)) }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        // Header Section: Logo and App Name

        // Header
        Text(
            text = "App languages",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(bottom = 16.dp)
        )

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 16.dp, top = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Logo
            Box(
                modifier = Modifier
                    .size(60.dp) // سایز بک‌گراند (بزرگتر از لوگو)
                    .background(color = Color.White, shape = RoundedCornerShape(40.dp)), // بک‌گراند با گوشه گرد
                contentAlignment = Alignment.Center // لوگو در مرکز قرار می‌گیرد
            ) {
                androidx.compose.foundation.Image(
                    painter = androidx.compose.ui.res.painterResource(id = R.drawable.logo), // آیکون لوگو
                    contentDescription = "App Logo",
                    modifier = Modifier
                        .size(50.dp) // سایز لوگو (کوچکتر از بک‌گراند)
                )
            }


            // App Name
            Text(
                text = "Coinceeper",
                modifier = Modifier.padding(start = 10.dp),
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
        }

        LazyColumn {
            // Suggested Section
            item {
                Text(
                    text = "Suggested",
                    fontSize = 14.sp,
                    color = Color.Gray,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(vertical = 16.dp)
                )
            }
            // اضافه کردن Box برای کل گزینه‌های Suggested
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(color = Color.White, shape = RoundedCornerShape(16.dp))
                        .padding(8.dp)
                ) {
                    Column {
                        suggestedLanguages.forEach { (name, code) ->
                            LanguageRow(
                                name = name,
                                isChecked = selectedLanguage == code,
                                onClick = {
                                    selectedLanguage = code
                                    setAppLocale(context, code)
                                    saveLanguage(context, code)
                                    sendLocaleChangeBroadcast(context, code)
                                    onLanguageSelected(code)
                                }
                            )
                        }
                    }
                }
            }


            // All Languages Section
            item {
                Text(
                    text = "All Languages",
                    fontSize = 14.sp,
                    color = Color.Gray,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(vertical = 16.dp)
                )
            }
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(color = Color.White, shape = RoundedCornerShape(16.dp))
                        .padding(8.dp)
                ) {
                    Column {
                        allLanguages.forEach { (name, code) ->
                            LanguageRow(
                                name = name,
                                isChecked = selectedLanguage == code,
                                onClick = {
                                    selectedLanguage = code
                                    setAppLocale(context, code)
                                    saveLanguage(context, code)
                                    sendLocaleChangeBroadcast(context, code)
                                    onLanguageSelected(code)
                                }
                            )
                            Divider(color = Color.LightGray, thickness = 0.5.dp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun LanguageRow(name: String, isChecked: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp)
            .clickable { onClick() },
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = name,
            fontSize = 16.sp,
            color = Color.Black,
            modifier = Modifier.weight(1f).padding(top = 8.dp)
        )
        if (isChecked) {
            Text(
                text = "✔", // علامت انتخاب
                fontSize = 16.sp,
                color = Color(0xFF16B369),
                modifier = Modifier.padding(end = 8.dp)
            )
        }
    }
}

fun loadLanguage(context: Context): String {
    val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
    return prefs.getString("language_code", "default") ?: "default"
}

fun sendLocaleChangeBroadcast(context: Context, languageCode: String) {
    val intent = Intent("com.wallet.crypto.coinceeper.LOCALE_CHANGED").apply {
        putExtra("locale", languageCode)
    }
    context.sendBroadcast(intent)
}

fun saveLanguage(context: Context, languageCode: String) {
    val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
    prefs.edit().putString("language_code", languageCode).apply()
}

fun setAppLocale(context: Context, languageCode: String) {
    val currentLocale = context.resources.configuration.locale
    val currentLanguage = currentLocale.language
    val selectedLocale = if (languageCode == "default") Locale.getDefault() else Locale(languageCode)

    val isCurrentRtl = isRtl(currentLocale)
    val isSelectedRtl = isRtl(selectedLocale)

    if (currentLanguage == languageCode && isCurrentRtl == isSelectedRtl) {
        return
    }

    val locale = selectedLocale
    Locale.setDefault(locale)

    val config = Configuration(context.resources.configuration)
    config.setLocale(locale)
    context.resources.updateConfiguration(config, context.resources.displayMetrics)

    val restartIntent = Intent(context, com.laxce.adl.MainActivity::class.java)
    restartIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
    context.startActivity(restartIntent)
}

// متد برای تشخیص جهت زبان
fun isRtl(locale: Locale): Boolean {
    val directionality = Character.getDirectionality(locale.displayName[0])
    return directionality == Character.DIRECTIONALITY_RIGHT_TO_LEFT || directionality == Character.DIRECTIONALITY_RIGHT_TO_LEFT_ARABIC
}

fun loadAllLanguages(context: Context): List<Pair<String, String>> {
    val allLanguages = mutableListOf<Pair<String, String>>()
    val languageDisplayNames = getLanguageDisplayNames()
    val parser = context.resources.getXml(R.xml.locales_config)
    try {
        parser.next()
        var eventType = parser.eventType
        while (eventType != XmlResourceParser.END_DOCUMENT) {
            if (eventType == XmlResourceParser.START_TAG && parser.name == "locale") {
                val code = parser.getAttributeValue("http://schemas.android.com/apk/res/android", "name")
                if (code != null) {
                    val displayName = languageDisplayNames[code] ?: "Unknown"
                    allLanguages.add(displayName to code)
                }
            }
            eventType = parser.next()
        }
    } catch (e: Exception) {
        e.printStackTrace()
    } finally {
        parser.close()
    }
    return allLanguages
}

fun getLanguageDisplayNames(): Map<String, String> {
    return mapOf(
        "br" to "Brezhoneg",
        "cs" to "Čeština",
        "da" to "Dansk",
        "de" to "Deutsch",
        "en" to "English",
        "tr" to "Türkçe",
        "es" to "Español",
        "fr" to "Français",
        "fa" to "Persian"
    )
}

