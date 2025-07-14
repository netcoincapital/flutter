package com.laxce.adl.api

import com.google.gson.annotations.SerializedName

// درخواست برای ایجاد کیف پول
data class CreateWalletRequest(
    val WalletName: String
)

// درخواست برای وارد کردن کیف پول
data class ImportWalletRequest(
//    val PrivateKey: String? = null,
    val mnemonic: String? = null
)

data class ReceiveRequest(
    val UserID: String,
    val BlockchainName: String
)

data class PricesRequest(
    val Symbol: List<String>,
    val FiatCurrencies: List<String>
)

data class BalanceRequest(
    @SerializedName("UserID")
    val userId: String,

    @SerializedName("CurrencyName")
    val currencyNames: List<String> = emptyList(),

    @SerializedName("Blockchain")
    val blockchain: Map<String, String> = emptyMap() // اگر مورد خاصی نیست، یک map خالی بفرستید
)


data class SendRequest(
    val UserID: String,
    val CurrencyName: String,
    val RecipientAddress: String,
    val Amount: String
)

data class TransactionsRequest(
    val UserID: String
)

data class UpdateBalanceRequest(
    val UserID: String
)

data class PrepareTransactionRequest(
    @SerializedName("blockchain")
    val blockchain_name: String,
    val sender_address: String,
    val recipient_address: String,
    val amount: String,
    val smart_contract_address: String = ""
)

data class EstimateFeeRequest(
    val blockchain: String,
    val from_address: String,
    val to_address: String,
    val amount: Double,
    val type: String? = null,
    val token_contract: String = ""
)

data class RegisterDeviceRequest(
    @SerializedName("UserID")
    val userId: String,

    @SerializedName("WalletID")
    val walletId: String,

    @SerializedName("DeviceToken")
    val deviceToken: String,

    @SerializedName("DeviceName")
    val deviceName: String,

    @SerializedName("DeviceType")
    val deviceType: String = "android"
)

data class ConfirmTransactionRequest(
    val transaction_id: String,
    // اطلاعات اضافی اختیاری که ممکن است سرور به آن‌ها نیاز داشته باشد
    val sender_address: String? = null,
    val recipient_address: String? = null,
    val amount: String? = null,
    val blockchain_name: String? = null,
)

data class AIRegisterRequest(
    @SerializedName("user_id")
    val userId: String,
    
    @SerializedName("wallet_id")
    val walletId: String
)


