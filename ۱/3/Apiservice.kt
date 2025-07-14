package com.laxce.adl.api

import retrofit2.Call
import retrofit2.http.Body
import retrofit2.http.POST
import retrofit2.http.GET
import retrofit2.http.Headers

// New models for AI interactions
data class CreateInteractionRequest(
    val user_id: String,
    val wallet_id: String
)

data class CreateInteractionResponse(
    val status: String,
    val interaction_id: String
)

interface Api {

    @Headers("Content-Type: application/json")
    @POST("generate-wallet")
    fun generateWallet(@Body request: CreateWalletRequest): Call<GenerateWalletResponse>

    @Headers("Content-Type: application/json")
    @POST("import_wallet")
    fun importWallet(@Body request: ImportWalletRequest): Call<ImportWalletResponse>

    @POST("Recive")
    suspend fun receiveToken(@Body request: ReceiveRequest): ReceiveResponse

    @POST("prices")
    suspend fun getPrices(@Body request: PricesRequest): PricesResponse

    @POST("balance")
    suspend fun getBalance(@Body request: BalanceRequest): BalanceResponse

    @GET("gasfee")
    suspend fun getGasFee(): GasFeeResponse

    // متد برای دریافت تمام ارزها
    @GET("all-currencies")
    suspend fun getAllCurrencies(): ApiResponse

    @POST("transactions")
    suspend fun getTransactions(@Body request: TransactionsRequest): TransactionsResponse

    @Headers("Content-Type: application/json")
    @POST("notifications/register-device")
    suspend fun registerDevice(@Body request: RegisterDeviceRequest): RegisterDeviceResponse

    @Headers("Content-Type: application/json")
    @POST("update-balance")
    fun updateBalance(@Body request: UpdateBalanceRequest): Call<BalanceResponse>

    @Headers("Content-Type: application/json")
    @POST("wallet/add-transaction")
    fun addTransaction(@Body transaction: Transaction): Call<TransactionsResponse>

    @Headers("Content-Type: application/json")
    @POST("send/prepare")
    suspend fun prepareTransaction(@Body request: PrepareTransactionRequest): PrepareTransactionResponse

    @Headers("Content-Type: application/json")
    @POST("estimate-fee")
    suspend fun estimateFee(@Body request: EstimateFeeRequest): EstimateFeeResponse

    @Headers("Content-Type: application/json")
    @POST("send/confirm")
    suspend fun confirmTransaction(@Body request: ConfirmTransactionRequest): ConfirmTransactionResponse

    @POST("ai-api/interactions/new")
    @Headers(
        "Content-Type: application/json",
        "Authorization: Bearer zXpV8dQr7tKfYm2gLjAe5nSbHc3iPw6C0UoT1RyBxN9EsWqFvDuGkJl4MhZ0IaO5P7YbTx8fEdL3GvKcAqRnUm9jW6tXpS2Z1ioH"
    )
    fun createNewInteraction(@Body request: CreateInteractionRequest): Call<CreateInteractionResponse>

    @Headers(
        "Content-Type: application/json",
        "Authorization: Bearer zXpV8dQr7tKfYm2gLjAe5nSbHc3iPw6C0UoT1RyBxN9EsWqFvDuGkJl4MhZ0IaO5P7YbTx8fEdL3GvKcAqRnUm9jW6tXpS2Z1ioH"
    )
    @POST("ai-api/users/register")
    fun registerAIUser(@Body request: AIRegisterRequest): Call<AIRegisterResponse>

}

