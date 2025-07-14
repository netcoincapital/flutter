package com.laxce.adl.api

import com.google.gson.annotations.SerializedName


data class GenerateWalletResponse(
    val success: Boolean,
    val UserID: String?,
    val WalletID: String?,
    val Mnemonic: String?,
    val message: String?
)

data class ImportWalletResponse(
    val status: String?,
    val message: String?,
    val data: WalletData?
)

data class WalletData(
    val UserID: String?,
    val WalletID: String?,
    val Mnemonic: String?,
    val Addresses: List<Address>?
)

data class Address(
    val BlockchainName: String?,
    val PublicAddress: String?
)

data class PriceData(
    val change_24h: String,
    val price: String
)

data class PricesResponse(
    val success: Boolean,
    val prices: Map<String, Map<String, PriceData>>?
)

data class ApiCurrency(
    val BlockchainName: String,
    val CurrencyName: String,
    val Symbol: String,
    val Icon: String?,
    val SmartContractAddress: String?,
    val IsToken: Boolean,
    val DecimalPlaces: Int
)

data class ApiResponse(
    val currencies: List<ApiCurrency>,
    val success: Boolean
)

data class ReceiveResponse(
    val success: Boolean,
    val PublicAddress: String?,
    val message: String? // این فیلد باید تعریف شده باشد
)

data class Wallet(
    val WalletName: String,
    val UserID: String, // اضافه کردن userId
    val backupText: String? = null
)

data class BalanceItem(
    @SerializedName("Balance")
    val balance: String,
    @SerializedName("Blockchain")
    val blockchain: String,
    @SerializedName("IsToken")
    val isToken: Boolean,
    @SerializedName("Symbol")
    val symbol: String,
    @SerializedName("CurrencyName")
    val currency_name: String? = null
)

data class BalanceResponse(
    val success: Boolean,
    @SerializedName("Balances")
    val balances: List<BalanceItem>?,
    @SerializedName("UserID")
    val UserID: String?,
    val message: String? = null
)



data class GasFeeResponse(
    val Arbitrum: GasFeeItem?,
    val Avalanche: GasFeeItem?,
    val Binance: GasFeeItem?,
    val Bitcoin: GasFeeItem?,
    val Cardano: GasFeeItem?,
    val Cosmos: GasFeeItem?,
    val Ethereum: GasFeeItem?,
    val Fantom: GasFeeItem?,
    val Optimism: GasFeeItem?,
    val Polkadot: GasFeeItem?,
    val Polygon: GasFeeItem?,
    val Solana: GasFeeItem?,
    val Tron: GasFeeItem?,
    val XRP: GasFeeItem?
)

data class GasFeeItem(
    val gas_fee: String?
)

data class SendResponse(
    val details: String,
    val transaction_id: String,
    val blockchain_name: String,
    val expires_at: String,
    val success: Boolean
)

data class TransactionsResponse(
    val count: Int,
    val page: Int,
    val per_page: Int,
    val status: String,
    val transactions: List<Transaction>
)

data class Transaction(
    val amount: String,
    val assetType: String,
    val blockchainName: String,
    val direction: String,
    val explorerUrl: String?,
    val fee: String,
    val from: String,
    val price: String,
    val timestamp: String,
    val to: String,
    val tokenContract: String,
    val tokenSymbol: String,
    val txHash: String,
    val status: String = "pending",
    var temporaryId: String? = null
)

data class TransactionDetails(
    val amount: String,
    val blockchain: String,
    val estimated_fee: String,
    val explorer_url: String,
    val recipient: String,
    val sender: String,
    val sender_balance_after: String,
    val sender_balance_before: String
)

data class PrepareTransactionResponse(
    val details: TransactionDetails,
    val expires_at: String,
    val message: String,
    val success: Boolean,
    val transaction_id: String
)

data class PriorityOption(
    val fee: Long,
    val fee_eth: Double
)

data class PriorityOptions(
    val average: PriorityOption,
    val fast: PriorityOption,
    val slow: PriorityOption
)

data class EstimateFeeResponse(
    val fee: Long,
    val fee_currency: String,
    val gas_price: Long,
    val gas_used: Int,
    val priority_options: PriorityOptions,
    val timestamp: Long,
    val unit: String,
    val usd_price: Double
)

data class RegisterDeviceResponse(
    val success: Boolean,
    val message: String?,
    val deviceId: String?
)

data class ConfirmTransactionResponse(
    val success: Boolean,
    val message: String,
    val transaction_hash: String,
    val status: String,
    val description: String
)

data class AIRegisterResponse(
    @SerializedName("interaction_id")
    val interactionId: String,
    
    val message: String,
    
    val status: String,
    
    @SerializedName("user_id")
    val userId: String
)

