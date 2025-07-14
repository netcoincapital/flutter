package com.laxce.adl.classes
import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class CryptoToken(
    val name: String,
    val symbol: String,
    val BlockchainName: String,
    val iconUrl: String = "https://coinceeper.com/defualtIcons/coin.png",
    var isEnabled: Boolean,
    val amount: Double = 0.0,
    val isToken: Boolean,
    val SmartContractAddress: String? = null
) : Parcelable



data class Asset(
    val icon: Int,
    val name: String,
    val BlockchainName: String,
    val amount: String,
    val value: String
)


data class SettingItemData(
    val icon: Int,
    val title: String,
    val subtitle: String? = null
)


data class WalletResponse(
    val success: Boolean,
    val PhraseKey: String?,
    val message: String? = null
)
