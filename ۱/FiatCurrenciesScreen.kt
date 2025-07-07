package com.laxce.adl.ui.theme.screen

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.laxce.adl.R
import com.laxce.adl.ui.theme.layout.MainLayout
import com.laxce.adl.utility.saveSelectedCurrency

@Composable
fun FiatCurrenciesScreen(navController: NavController) {

    MainLayout(navController = navController) {
        Column(modifier = Modifier.fillMaxSize().background(Color.White)) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp)
            ) {
                // Header
                Text(
                    text = "Fiat Currencies",
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(bottom = 16.dp)
                )

                // Box containing the currencies list
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(8.dp)
                ) {
                    Column {
                        Text(
                            text = "All currency:",
                            fontSize = 16.sp,
                            color = Color(0xCB838383),
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(bottom = 16.dp)
                        )

                        LazyColumn(modifier = Modifier.fillMaxSize()) {
                            val currencies = listOf(
                                Triple("USD", "$" , R.drawable.us),
                                Triple("CAD", "CA", R.drawable.ca),
                                Triple("AUD", "AU", R.drawable.au),
                                Triple("GBP", "£", R.drawable.gb),
                                Triple("EUR", "€", R.drawable.eu),
                                Triple("KWD", "KD", R.drawable.kw),
                                Triple("TRY", "₺", R.drawable.tr),
//                                Triple("IRR", "﷼", R.drawable.ir),
                                Triple("SAR", "﷼", R.drawable.sa),
                                Triple("CNY", "¥", R.drawable.cn),
                                Triple("KRW", "₩", R.drawable.kr),
                                Triple("JPY", "¥", R.drawable.jp),
                                Triple("INR", "₹", R.drawable.`in`),
                                Triple("RUB", "₽", R.drawable.ru),
                                Triple("IQD", "ع.د", R.drawable.iq),
                                Triple("TND", "د.ت", R.drawable.tn),
                                Triple("BHD", "ب.د", R.drawable.bh)
                            )

                            items(currencies.size) { index ->
                                val (currency, symbol, flagRes) = currencies[index]
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable {
                                            saveSelectedCurrency(
                                                context = navController.context,
                                                currency = currency
                                            )
                                            navController.popBackStack()
                                        }
                                        .padding(vertical = 8.dp),
                                    horizontalArrangement = Arrangement.Start
                                ) {
                                    // Flag image
                                    Image(
                                        painter = painterResource(id = flagRes),
                                        contentDescription = "$currency flag",
                                        modifier = Modifier.size(24.dp)
                                    )

                                    Spacer(modifier = Modifier.width(8.dp))

                                    // Currency details
                                    Column {
                                        Text(
                                            text = "$currency ($symbol)",
                                            fontSize = 18.sp,
                                            color = Color.Black
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
