package com.laxce.adl.ui.theme.screen

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.ui.theme.layout.MainLayout
import com.laxce.adl.utility.getSelectedCurrency

@Composable
fun PreferencesScreen(navController: NavController) {
    val context = LocalContext.current
    MainLayout(navController = navController) {
        Column(modifier = Modifier.fillMaxSize().background(Color.White)) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp)
            ) {
                // Header
                Text(
                    text = "Preferences",
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(bottom = 16.dp)
                )

                // Currency Setting
                PreferenceItem(
                    title = "Currency",
                    subtitle = getSelectedCurrency(context),
                    onClick = {
                        try {
                            navController.navigate("fiat-currencies")
                        } catch (e: Exception) {
                        }
                    }

                )


                // App Language Setting
                PreferenceItem(
                    title = "App Language",
                    subtitle = getLanguageDisplayName(context, loadLanguage(context)),
                    onClick = {
                        navController.navigate("languages")
                    }
                )
            }
        }
    }
}

@Composable
fun PreferenceItem(
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(vertical = 20.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Title
            Text(
                text = title,
                fontSize = 16.sp,
                color = Color.Black,
                modifier = Modifier.weight(1f)
            )
            // Subtitle (Optional)
            subtitle?.let {
                Text(
                    text = it,
                    fontSize = 14.sp,
                    color = Color.Gray
                )
            }
        }
    }
}


fun getLanguageDisplayName(context: Context, languageCode: String): String {
    val languageDisplayNames = getLanguageDisplayNames()
    return if (languageCode == "default") {
        "System default"
    } else {
        languageDisplayNames[languageCode] ?: "Unknown"
    }
}


