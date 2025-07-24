import 'package:json_annotation/json_annotation.dart';

part 'api_models.g.dart';

// ==================== REQUEST MODELS ====================

/// درخواست برای ایجاد کیف پول جدید
@JsonSerializable()
class CreateWalletRequest {
  @JsonKey(name: 'WalletName')
  final String walletName;

  CreateWalletRequest({required this.walletName}) {
    assert(walletName.isNotEmpty, 'Wallet name cannot be empty');
  }

  factory CreateWalletRequest.fromJson(Map<String, dynamic> json) => _$CreateWalletRequestFromJson(json);
  Map<String, dynamic> toJson() => _$CreateWalletRequestToJson(this);
}

/// درخواست برای وارد کردن کیف پول
@JsonSerializable()
class ImportWalletRequest {
  final String? mnemonic;

  const ImportWalletRequest({this.mnemonic});

  factory ImportWalletRequest.fromJson(Map<String, dynamic> json) => _$ImportWalletRequestFromJson(json);
  Map<String, dynamic> toJson() => _$ImportWalletRequestToJson(this);
}

/// آدرس بلاکچین
@JsonSerializable()
class BlockchainAddress {
  @JsonKey(name: 'BlockchainName')
  final String blockchainName;
  
  @JsonKey(name: 'PublicAddress')
  final String publicAddress;

  BlockchainAddress({required this.blockchainName, required this.publicAddress});

  factory BlockchainAddress.fromJson(Map<String, dynamic> json) => _$BlockchainAddressFromJson(json);
  Map<String, dynamic> toJson() => _$BlockchainAddressToJson(this);
}

/// داده‌های ایمپورت والت
class ImportWalletData {
  @JsonKey(name: 'Addresses')
  final List<BlockchainAddress> addresses;
  @JsonKey(name: 'Mnemonic')
  final String mnemonic;
  @JsonKey(name: 'UserID')
  final String userID;
  @JsonKey(name: 'WalletID')
  final String walletID;

  ImportWalletData({
    required this.addresses,
    required this.mnemonic,
    required this.userID,
    required this.walletID,
  });

  factory ImportWalletData.fromJson(Map<String, dynamic> json) {
    print('🔧 ImportWalletData.fromJson - Parsing JSON:');
    print('   Raw JSON: $json');
    print('   Has Addresses: ${json.containsKey('Addresses')}');
    print('   Has Mnemonic: ${json.containsKey('Mnemonic')}');
    print('   Has UserID: ${json.containsKey('UserID')}');
    print('   Has WalletID: ${json.containsKey('WalletID')}');
    
    final addresses = (json['Addresses'] as List<dynamic>?)
            ?.map((e) => BlockchainAddress.fromJson(e as Map<String, dynamic>))
            .toList() ?? [];
    final mnemonic = json['Mnemonic'] as String? ?? '';
    final userID = json['UserID'] as String? ?? '';
    final walletID = json['WalletID'] as String? ?? '';
    
    print('   Parsed Addresses Count: ${addresses.length}');
    print('   Parsed Mnemonic Length: ${mnemonic.length}');
    print('   Parsed UserID: $userID');
    print('   Parsed WalletID: $walletID');
    
    return ImportWalletData(
      addresses: addresses,
      mnemonic: mnemonic,
      userID: userID,
      walletID: walletID,
    );
  }
  Map<String, dynamic> toJson() => {
    'Addresses': addresses.map((e) => e.toJson()).toList(),
    'Mnemonic': mnemonic,
    'UserID': userID,
    'WalletID': walletID,
  };
}

/// پاسخ ایمپورت والت
@JsonSerializable()
class ImportWalletResponse {
  final ImportWalletData? data;
  final String message;
  final String status;

  ImportWalletResponse({
    this.data,
    required this.message,
    required this.status,
  });

  factory ImportWalletResponse.fromJson(Map<String, dynamic> json) {
    print('🔧 ImportWalletResponse.fromJson - Parsing response:');
    print('   Raw JSON: $json');
    print('   Has Data: ${json.containsKey('data')}');
    print('   Has Message: ${json.containsKey('message')}');
    print('   Has Status: ${json.containsKey('status')}');
    
    final response = _$ImportWalletResponseFromJson(json);
    print('   Parsed Status: ${response.status}');
    print('   Parsed Message: ${response.message}');
    print('   Parsed Data: ${response.data != null}');
    
    return response;
  }
  
  Map<String, dynamic> toJson() => _$ImportWalletResponseToJson(this);
}

/// درخواست برای دریافت آدرس
@JsonSerializable()
class ReceiveRequest {
  @JsonKey(name: 'UserID')
  final String userID;
  
  @JsonKey(name: 'BlockchainName')
  final String blockchainName;

  ReceiveRequest({required this.userID, required this.blockchainName}) {
    assert(userID.isNotEmpty, 'UserID cannot be empty');
    assert(blockchainName.isNotEmpty, 'BlockchainName cannot be empty');
  }

  factory ReceiveRequest.fromJson(Map<String, dynamic> json) => _$ReceiveRequestFromJson(json);
  Map<String, dynamic> toJson() => _$ReceiveRequestToJson(this);
}

/// درخواست برای دریافت قیمت‌ها
@JsonSerializable()
class PricesRequest {
  @JsonKey(name: 'Symbol')
  final List<String> symbol;
  
  @JsonKey(name: 'FiatCurrencies')
  final List<String> fiatCurrencies;

  PricesRequest({required this.symbol, required this.fiatCurrencies}) {
    assert(symbol.isNotEmpty, 'Symbol list cannot be empty');
    assert(fiatCurrencies.isNotEmpty, 'FiatCurrencies list cannot be empty');
  }

  factory PricesRequest.fromJson(Map<String, dynamic> json) => _$PricesRequestFromJson(json);
  Map<String, dynamic> toJson() => _$PricesRequestToJson(this);
}

/// درخواست برای دریافت موجودی
@JsonSerializable()
class BalanceRequest {
  @JsonKey(name: 'UserID')
  final String userId;
  
  @JsonKey(name: 'CurrencyName')
  final List<String> currencyNames;
  
  @JsonKey(name: 'Blockchain')
  final Map<String, String> blockchain;

  BalanceRequest({
    required this.userId,
    this.currencyNames = const [],
    this.blockchain = const {},
  }) {
    assert(userId.isNotEmpty, 'UserID cannot be empty');
  }

  factory BalanceRequest.fromJson(Map<String, dynamic> json) => _$BalanceRequestFromJson(json);
  Map<String, dynamic> toJson() => _$BalanceRequestToJson(this);
}

/// درخواست برای ارسال تراکنش
@JsonSerializable()
class SendRequest {
  @JsonKey(name: 'UserID')
  final String userID;
  
  @JsonKey(name: 'CurrencyName')
  final String currencyName;
  
  @JsonKey(name: 'RecipientAddress')
  final String recipientAddress;
  
  @JsonKey(name: 'Amount')
  final String amount;

  SendRequest({
    required this.userID,
    required this.currencyName,
    required this.recipientAddress,
    required this.amount,
  }) {
    assert(userID.isNotEmpty, 'UserID cannot be empty');
    assert(currencyName.isNotEmpty, 'CurrencyName cannot be empty');
    assert(recipientAddress.isNotEmpty, 'RecipientAddress cannot be empty');
    assert(amount.isNotEmpty, 'Amount cannot be empty');
  }

  factory SendRequest.fromJson(Map<String, dynamic> json) => _$SendRequestFromJson(json);
  Map<String, dynamic> toJson() => _$SendRequestToJson(this);
}

/// درخواست برای دریافت تراکنش‌ها
@JsonSerializable()
class TransactionsRequest {
  @JsonKey(name: 'UserID')
  final String userID;
  
  @JsonKey(name: 'TokenSymbol', includeIfNull: false)
  final String? tokenSymbol;

  TransactionsRequest({required this.userID, this.tokenSymbol}) {
    assert(userID.isNotEmpty, 'UserID cannot be empty');
  }

  factory TransactionsRequest.fromJson(Map<String, dynamic> json) => _$TransactionsRequestFromJson(json);
  Map<String, dynamic> toJson() => _$TransactionsRequestToJson(this);
}

/// درخواست برای به‌روزرسانی موجودی
@JsonSerializable()
class UpdateBalanceRequest {
  @JsonKey(name: 'UserID')
  final String userID;

  UpdateBalanceRequest({required this.userID}) {
    assert(userID.isNotEmpty, 'UserID cannot be empty');
  }

  factory UpdateBalanceRequest.fromJson(Map<String, dynamic> json) => _$UpdateBalanceRequestFromJson(json);
  Map<String, dynamic> toJson() => _$UpdateBalanceRequestToJson(this);
}

/// درخواست برای آماده‌سازی تراکنش
@JsonSerializable()
class PrepareTransactionRequest {
  @JsonKey(name: 'UserID')
  final String userID;
  
  @JsonKey(name: 'blockchain')
  final String blockchainName;
  
  @JsonKey(name: 'sender_address')
  final String senderAddress;
  
  @JsonKey(name: 'recipient_address')
  final String recipientAddress;
  
  final String amount;
  
  @JsonKey(name: 'smart_contract_address')
  final String smartContractAddress;

  PrepareTransactionRequest({
    required this.userID,
    required this.blockchainName,
    required this.senderAddress,
    required this.recipientAddress,
    required this.amount,
    this.smartContractAddress = '',
  }) {
    assert(userID.isNotEmpty, 'UserID cannot be empty');
    assert(blockchainName.isNotEmpty, 'BlockchainName cannot be empty');
    assert(senderAddress.isNotEmpty, 'SenderAddress cannot be empty');
    assert(recipientAddress.isNotEmpty, 'RecipientAddress cannot be empty');
    assert(amount.isNotEmpty, 'Amount cannot be empty');
  }

  factory PrepareTransactionRequest.fromJson(Map<String, dynamic> json) => _$PrepareTransactionRequestFromJson(json);
  Map<String, dynamic> toJson() => _$PrepareTransactionRequestToJson(this);
}

/// درخواست برای تخمین کارمزد
@JsonSerializable()
class EstimateFeeRequest {
  @JsonKey(name: 'UserID')
  final String userID;
  
  final String blockchain;
  
  @JsonKey(name: 'from_address')
  final String fromAddress;
  
  @JsonKey(name: 'to_address')
  final String toAddress;
  
  final double amount;
  
  final String? type;
  
  @JsonKey(name: 'token_contract')
  final String tokenContract;

  EstimateFeeRequest({
    required this.userID,
    required this.blockchain,
    required this.fromAddress,
    required this.toAddress,
    required this.amount,
    this.type,
    this.tokenContract = '',
  }) {
    assert(userID.isNotEmpty, 'UserID cannot be empty');
    assert(blockchain.isNotEmpty, 'Blockchain cannot be empty');
    assert(fromAddress.isNotEmpty, 'FromAddress cannot be empty');
    assert(toAddress.isNotEmpty, 'ToAddress cannot be empty');
    assert(amount > 0, 'Amount must be greater than 0');
  }

  factory EstimateFeeRequest.fromJson(Map<String, dynamic> json) => _$EstimateFeeRequestFromJson(json);
  Map<String, dynamic> toJson() => _$EstimateFeeRequestToJson(this);
}

/// درخواست برای ثبت دستگاه
@JsonSerializable()
class RegisterDeviceRequest {
  @JsonKey(name: 'UserID')
  final String userId;
  
  @JsonKey(name: 'WalletID')
  final String walletId;
  
  @JsonKey(name: 'DeviceToken')
  final String deviceToken;
  
  @JsonKey(name: 'DeviceName')
  final String deviceName;
  
  @JsonKey(name: 'DeviceType')
  final String deviceType;

  RegisterDeviceRequest({
    required this.userId,
    required this.walletId,
    required this.deviceToken,
    required this.deviceName,
    this.deviceType = 'android',
  }) {
    assert(userId.isNotEmpty, 'UserID cannot be empty');
    assert(walletId.isNotEmpty, 'WalletID cannot be empty');
    assert(deviceToken.isNotEmpty, 'DeviceToken cannot be empty');
    assert(deviceName.isNotEmpty, 'DeviceName cannot be empty');
  }

  factory RegisterDeviceRequest.fromJson(Map<String, dynamic> json) => _$RegisterDeviceRequestFromJson(json);
  Map<String, dynamic> toJson() => _$RegisterDeviceRequestToJson(this);
}

/// درخواست برای تایید تراکنش
@JsonSerializable()
class ConfirmTransactionRequest {
  @JsonKey(name: 'UserID')
  final String userID;
  
  @JsonKey(name: 'transaction_id')
  final String transactionId;
  
  final String blockchain;
  
  @JsonKey(name: 'private_key')
  final String privateKey;

  ConfirmTransactionRequest({
    required this.userID,
    required this.transactionId,
    required this.blockchain,
    required this.privateKey,
  }) {
    assert(userID.isNotEmpty, 'UserID cannot be empty');
    assert(transactionId.isNotEmpty, 'TransactionId cannot be empty');
    assert(blockchain.isNotEmpty, 'Blockchain cannot be empty');
    assert(privateKey.isNotEmpty, 'PrivateKey cannot be empty');
  }

  factory ConfirmTransactionRequest.fromJson(Map<String, dynamic> json) => _$ConfirmTransactionRequestFromJson(json);
  Map<String, dynamic> toJson() => _$ConfirmTransactionRequestToJson(this);
}

/// درخواست برای دریافت موجودی کاربر (فرمت جدید)
@JsonSerializable()
class GetUserBalanceRequest {
  @JsonKey(name: 'UserID')
  final String userID;
  
  @JsonKey(name: 'CurrencyName')
  final List<String> currencyName;

  GetUserBalanceRequest({
    required this.userID,
    required this.currencyName,
  }) {
    assert(userID.isNotEmpty, 'UserID cannot be empty');
    assert(currencyName.isNotEmpty, 'CurrencyName cannot be empty');
  }

  factory GetUserBalanceRequest.fromJson(Map<String, dynamic> json) => _$GetUserBalanceRequestFromJson(json);
  Map<String, dynamic> toJson() => _$GetUserBalanceRequestToJson(this);
}


// ==================== RESPONSE MODELS ====================

/// پاسخ ایجاد کیف پول
@JsonSerializable()
class GenerateWalletResponse {
  final bool success;
  
  @JsonKey(name: 'UserID')
  final String? userID;
  
  @JsonKey(name: 'WalletID')
  final String? walletID;
  
  @JsonKey(name: 'Mnemonic')
  final String? mnemonic;
  final String? message;

  const GenerateWalletResponse({
    required this.success,
    this.userID,
    this.walletID,
    this.mnemonic,
    this.message,
  });

  factory GenerateWalletResponse.fromJson(Map<String, dynamic> json) => _$GenerateWalletResponseFromJson(json);
  Map<String, dynamic> toJson() => _$GenerateWalletResponseToJson(this);
}



/// داده‌های کیف پول
@JsonSerializable()
class WalletData {
  @JsonKey(name: 'UserID')
  final String? userID;
  
  @JsonKey(name: 'WalletID')
  final String? walletID;
  
  final String? mnemonic;
  
  @JsonKey(name: 'Addresses')
  final List<Address>? addresses;

  const WalletData({
    this.userID,
    this.walletID,
    this.mnemonic,
    this.addresses,
  });

  factory WalletData.fromJson(Map<String, dynamic> json) => _$WalletDataFromJson(json);
  Map<String, dynamic> toJson() => _$WalletDataToJson(this);
}

/// آدرس کیف پول
@JsonSerializable()
class Address {
  @JsonKey(name: 'BlockchainName')
  final String? blockchainName;
  
  @JsonKey(name: 'PublicAddress')
  final String? publicAddress;

  const Address({
    this.blockchainName,
    this.publicAddress,
  });

  factory Address.fromJson(Map<String, dynamic> json) => _$AddressFromJson(json);
  Map<String, dynamic> toJson() => _$AddressToJson(this);
}

/// داده‌های قیمت
@JsonSerializable()
class PriceData {
  @JsonKey(name: 'change_24h')
  final String change24h;
  final String price;

  const PriceData({
    required this.change24h,
    required this.price,
  });

  factory PriceData.fromJson(Map<String, dynamic> json) => _$PriceDataFromJson(json);
  Map<String, dynamic> toJson() => _$PriceDataToJson(this);
}

/// پاسخ قیمت‌ها
@JsonSerializable()
class PricesResponse {
  final bool success;
  final Map<String, Map<String, PriceData>>? prices;

  const PricesResponse({
    required this.success,
    this.prices,
  });

  factory PricesResponse.fromJson(Map<String, dynamic> json) => _$PricesResponseFromJson(json);
  Map<String, dynamic> toJson() => _$PricesResponseToJson(this);
}

/// ارز API
@JsonSerializable()
class ApiCurrency {
  @JsonKey(name: 'CurrencyID')
  final String? currencyId;
  
  @JsonKey(name: 'BlockchainName')
  final String? blockchainName;
  
  @JsonKey(name: 'CurrencyName')
  final String? currencyName;
  
  @JsonKey(name: 'Symbol')
  final String? symbol;
  
  @JsonKey(name: 'Icon')
  final String? icon;
  
  @JsonKey(name: 'SmartContractAddress')
  final String? smartContractAddress;
  
  @JsonKey(name: 'IsToken')
  final bool? isToken;
  
  @JsonKey(name: 'DecimalPlaces')
  final int? decimalPlaces;

  const ApiCurrency({
    this.currencyId,
    this.blockchainName,
    this.currencyName,
    this.symbol,
    this.icon,
    this.smartContractAddress,
    this.isToken,
    this.decimalPlaces,
  });

  factory ApiCurrency.fromJson(Map<String, dynamic> json) => _$ApiCurrencyFromJson(json);
  Map<String, dynamic> toJson() => _$ApiCurrencyToJson(this);
}

/// پاسخ API عمومی
@JsonSerializable()
class ApiResponse {
  final List<ApiCurrency> currencies;
  final bool success;

  const ApiResponse({
    required this.currencies,
    required this.success,
  });

  factory ApiResponse.fromJson(Map<String, dynamic> json) => _$ApiResponseFromJson(json);
  Map<String, dynamic> toJson() => _$ApiResponseToJson(this);
}

/// پاسخ دریافت آدرس
@JsonSerializable()
class ReceiveResponse {
  final bool success;
  
  @JsonKey(name: 'PublicAddress')
  final String? publicAddress;
  final String? message;

  const ReceiveResponse({
    required this.success,
    this.publicAddress,
    this.message,
  });

  factory ReceiveResponse.fromJson(Map<String, dynamic> json) => _$ReceiveResponseFromJson(json);
  Map<String, dynamic> toJson() => _$ReceiveResponseToJson(this);
}

/// آیتم موجودی
@JsonSerializable()
class BalanceItem {
  @JsonKey(name: 'Balance')
  final String? balance;
  
  @JsonKey(name: 'Blockchain')
  final String? blockchain;
  
  @JsonKey(name: 'IsToken')
  final bool? isToken;
  
  @JsonKey(name: 'Symbol')
  final String? symbol;
  
  @JsonKey(name: 'currency_name')
  final String? currencyName;

  const BalanceItem({
    this.balance,
    this.blockchain,
    this.isToken,
    this.symbol,
    this.currencyName,
  });

  factory BalanceItem.fromJson(Map<String, dynamic> json) => _$BalanceItemFromJson(json);
  Map<String, dynamic> toJson() => _$BalanceItemToJson(this);
}

/// پاسخ موجودی
@JsonSerializable()
class BalanceResponse {
  final bool success;
  
  @JsonKey(name: 'Balances')
  final List<BalanceItem>? balances;
  
  @JsonKey(name: 'UserID')
  final String? userID;
  final String? message;

  const BalanceResponse({
    required this.success,
    this.balances,
    this.userID,
    this.message,
  });

  factory BalanceResponse.fromJson(Map<String, dynamic> json) => _$BalanceResponseFromJson(json);
  Map<String, dynamic> toJson() => _$BalanceResponseToJson(this);
}

/// پاسخ موجودی کاربر (فرمت جدید)
@JsonSerializable()
class GetUserBalanceResponse {
  @JsonKey(name: 'Tokens')
  final Map<String, dynamic> tokens;
  
  @JsonKey(name: 'UserID')
  final String userID;
  
  final bool success;

  const GetUserBalanceResponse({
    required this.tokens,
    required this.userID,
    required this.success,
  });

  factory GetUserBalanceResponse.fromJson(Map<String, dynamic> json) => _$GetUserBalanceResponseFromJson(json);
  Map<String, dynamic> toJson() => _$GetUserBalanceResponseToJson(this);
}

/// آیتم کارمزد گاز
@JsonSerializable()
class GasFeeItem {
  @JsonKey(name: 'gas_fee')
  final String? gasFee;

  const GasFeeItem({this.gasFee});

  factory GasFeeItem.fromJson(Map<String, dynamic> json) => _$GasFeeItemFromJson(json);
  Map<String, dynamic> toJson() => _$GasFeeItemToJson(this);
}

/// پاسخ کارمزد گاز
@JsonSerializable()
class GasFeeResponse {
  final GasFeeItem? arbitrum;
  final GasFeeItem? avalanche;
  final GasFeeItem? binance;
  final GasFeeItem? bitcoin;
  final GasFeeItem? cardano;
  final GasFeeItem? cosmos;
  final GasFeeItem? ethereum;
  final GasFeeItem? fantom;
  final GasFeeItem? optimism;
  final GasFeeItem? polkadot;
  final GasFeeItem? polygon;
  final GasFeeItem? solana;
  final GasFeeItem? tron;
  final GasFeeItem? xrp;

  const GasFeeResponse({
    this.arbitrum,
    this.avalanche,
    this.binance,
    this.bitcoin,
    this.cardano,
    this.cosmos,
    this.ethereum,
    this.fantom,
    this.optimism,
    this.polkadot,
    this.polygon,
    this.solana,
    this.tron,
    this.xrp,
  });

  factory GasFeeResponse.fromJson(Map<String, dynamic> json) => _$GasFeeResponseFromJson(json);
  Map<String, dynamic> toJson() => _$GasFeeResponseToJson(this);
}

/// پاسخ ارسال
@JsonSerializable()
class SendResponse {
  final String details;
  
  @JsonKey(name: 'transaction_id')
  final String transactionId;
  
  @JsonKey(name: 'blockchain_name')
  final String blockchainName;
  
  @JsonKey(name: 'expires_at')
  final String expiresAt;
  final bool success;

  const SendResponse({
    required this.details,
    required this.transactionId,
    required this.blockchainName,
    required this.expiresAt,
    required this.success,
  });

  factory SendResponse.fromJson(Map<String, dynamic> json) => _$SendResponseFromJson(json);
  Map<String, dynamic> toJson() => _$SendResponseToJson(this);
}

/// کلاس تراکنش
@JsonSerializable()
class Transaction {
  final String? txHash;
  final String? from;
  final String? to;
  final String? amount;
  
  @JsonKey(name: 'tokenSymbol')
  final String? tokenSymbol;
  final String? direction;
  final String? status;
  final String? timestamp;
  
  @JsonKey(name: 'blockchainName')
  final String? blockchainName;
  
  @JsonKey(name: 'price', fromJson: _priceFromJson)
  final double? price;
  
  @JsonKey(name: 'temporaryId')
  final String? temporaryId;

  @JsonKey(name: 'explorerUrl')
  final String? explorerUrl;

  final String? fee;
  final String? assetType;
  final String? tokenContract;

  const Transaction({
    this.txHash,
    this.from,
    this.to,
    this.amount,
    this.tokenSymbol,
    this.direction,
    this.status,
    this.timestamp,
    this.blockchainName,
    this.price,
    this.temporaryId,
    this.explorerUrl,
    this.fee,
    this.assetType,
    this.tokenContract,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) => _$TransactionFromJson(json);
  Map<String, dynamic> toJson() => _$TransactionToJson(this);
  
  /// تبدیل امن String به double برای فیلد price
  static double? _priceFromJson(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      try {
        return double.tryParse(value);
      } catch (e) {
        print('⚠️ Warning: Could not parse price value "$value" to double');
        return null;
      }
    }
    print('⚠️ Warning: Unexpected price value type: ${value.runtimeType}');
    return null;
  }
}

/// پاسخ تراکنش‌ها
@JsonSerializable()
class TransactionsResponse {
  final int count;
  final int page;
  
  @JsonKey(name: 'per_page')
  final int perPage;
  final String status;
  final List<Transaction> transactions;

  const TransactionsResponse({
    required this.count,
    required this.page,
    required this.perPage,
    required this.status,
    required this.transactions,
  });

  factory TransactionsResponse.fromJson(Map<String, dynamic> json) => _$TransactionsResponseFromJson(json);
  Map<String, dynamic> toJson() => _$TransactionsResponseToJson(this);
}

/// جزئیات تراکنش
@JsonSerializable()
class TransactionDetails {
  final String amount;
  final String blockchain;
  
  @JsonKey(name: 'estimated_fee')
  final String estimatedFee;
  
  @JsonKey(name: 'explorer_url')
  final String explorerUrl;
  final String recipient;
  final String sender;
  
  @JsonKey(name: 'sender_balance_after')
  final String senderBalanceAfter;
  
  @JsonKey(name: 'sender_balance_before')
  final String senderBalanceBefore;

  const TransactionDetails({
    required this.amount,
    required this.blockchain,
    required this.estimatedFee,
    required this.explorerUrl,
    required this.recipient,
    required this.sender,
    required this.senderBalanceAfter,
    required this.senderBalanceBefore,
  });

  factory TransactionDetails.fromJson(Map<String, dynamic> json) => _$TransactionDetailsFromJson(json);
  Map<String, dynamic> toJson() => _$TransactionDetailsToJson(this);
}

/// پاسخ آماده‌سازی تراکنش
@JsonSerializable()
class PrepareTransactionResponse {
  final TransactionDetails details;
  
  @JsonKey(name: 'expires_at')
  final String expiresAt;
  final String message;
  final bool success;
  
  @JsonKey(name: 'transaction_id')
  final String transactionId;

  const PrepareTransactionResponse({
    required this.details,
    required this.expiresAt,
    required this.message,
    required this.success,
    required this.transactionId,
  });

  factory PrepareTransactionResponse.fromJson(Map<String, dynamic> json) => _$PrepareTransactionResponseFromJson(json);
  Map<String, dynamic> toJson() => _$PrepareTransactionResponseToJson(this);
}

/// گزینه اولویت
@JsonSerializable()
class PriorityOption {
  final int? fee;
  
  @JsonKey(name: 'fee_eth')
  final double? feeEth;

  const PriorityOption({
    this.fee,
    this.feeEth,
  });

  factory PriorityOption.fromJson(Map<String, dynamic> json) => _$PriorityOptionFromJson(json);
  Map<String, dynamic> toJson() => _$PriorityOptionToJson(this);
}

/// گزینه‌های اولویت
@JsonSerializable()
class PriorityOptions {
  final PriorityOption? average;
  final PriorityOption? fast;
  final PriorityOption? slow;

  const PriorityOptions({
    this.average,
    this.fast,
    this.slow,
  });

  factory PriorityOptions.fromJson(Map<String, dynamic> json) => _$PriorityOptionsFromJson(json);
  Map<String, dynamic> toJson() => _$PriorityOptionsToJson(this);
}

/// پاسخ تخمین کارمزد
@JsonSerializable()
class EstimateFeeResponse {
  final int? fee;
  
  @JsonKey(name: 'fee_currency')
  final String? feeCurrency;
  
  @JsonKey(name: 'gas_price')
  final int? gasPrice;
  
  @JsonKey(name: 'gas_used')
  final int? gasUsed;
  
  @JsonKey(name: 'priority_options')
  final PriorityOptions? priorityOptions;
  final int? timestamp;
  final String? unit;
  
  @JsonKey(name: 'usd_price')
  final double? usdPrice;

  const EstimateFeeResponse({
    this.fee,
    this.feeCurrency,
    this.gasPrice,
    this.gasUsed,
    this.priorityOptions,
    this.timestamp,
    this.unit,
    this.usdPrice,
  });

  factory EstimateFeeResponse.fromJson(Map<String, dynamic> json) => _$EstimateFeeResponseFromJson(json);
  Map<String, dynamic> toJson() => _$EstimateFeeResponseToJson(this);
}

/// پاسخ ثبت دستگاه
@JsonSerializable()
class RegisterDeviceResponse {
  final bool success;
  final String? message;
  
  @JsonKey(name: 'deviceId')
  final String? deviceId;

  const RegisterDeviceResponse({
    required this.success,
    this.message,
    this.deviceId,
  });

  factory RegisterDeviceResponse.fromJson(Map<String, dynamic> json) => _$RegisterDeviceResponseFromJson(json);
  Map<String, dynamic> toJson() => _$RegisterDeviceResponseToJson(this);
}

/// پاسخ تایید تراکنش
@JsonSerializable()
class ConfirmTransactionResponse {
  final bool? success;
  final String? message;
  
  @JsonKey(name: 'transaction_hash')
  final String? transactionHash;
  
  @JsonKey(name: 'tx_hash')
  final String? txHash;
  
  final String? status;
  final String? description;

  const ConfirmTransactionResponse({
    this.success,
    this.message,
    this.transactionHash,
    this.txHash,
    this.status,
    this.description,
  });

  factory ConfirmTransactionResponse.fromJson(Map<String, dynamic> json) => _$ConfirmTransactionResponseFromJson(json);
  Map<String, dynamic> toJson() => _$ConfirmTransactionResponseToJson(this);
  
  // Helper method to check if transaction was successful
  bool get isSuccess => success == true || 
                        message == "Transaction sent successfully" || 
                        status == "sent" ||
                        (transactionHash != null && transactionHash!.isNotEmpty) ||
                        (txHash != null && txHash!.isNotEmpty);
  
  // Helper method to get transaction hash
  String? get hash => transactionHash ?? txHash;
}



// ==================== UTILITY CLASSES ====================

/// کلاس برای مدیریت نتایج API
class ApiResult<T> {
  final bool success;
  final T? data;
  final String? error;

  ApiResult.success(this.data) : success = true, error = null;
  ApiResult.error(this.error) : success = false, data = null;
}

// ==================== NOTIFICATION MODELS ====================

/// Firebase notification payload
@JsonSerializable()
class NotificationPayload {
  final String title;
  final String body;

  const NotificationPayload({
    required this.title,
    required this.body,
  });

  factory NotificationPayload.fromJson(Map<String, dynamic> json) => _$NotificationPayloadFromJson(json);
  Map<String, dynamic> toJson() => _$NotificationPayloadToJson(this);
}

/// Transaction notification data
@JsonSerializable()
class NotificationData {
  @JsonKey(name: 'transaction_id')
  final String? transactionId;
  
  final String? type; // "receive", "send", etc.
  final String? direction; // "inbound", "outbound"
  final String? amount;
  final String? currency; // BTC, ETH, etc.
  final String? symbol; // For backward compatibility
  
  @JsonKey(name: 'from_address')
  final String? fromAddress;
  
  @JsonKey(name: 'to_address')
  final String? toAddress;
  
  @JsonKey(name: 'wallet_id')
  final String? walletId;
  
  final String? timestamp;
  final String? status;

  const NotificationData({
    this.transactionId,
    this.type,
    this.direction,
    this.amount,
    this.currency,
    this.symbol,
    this.fromAddress,
    this.toAddress,
    this.walletId,
    this.timestamp,
    this.status,
  });

  factory NotificationData.fromJson(Map<String, dynamic> json) => _$NotificationDataFromJson(json);
  Map<String, dynamic> toJson() => _$NotificationDataToJson(this);
}

/// Android-specific notification configuration
@JsonSerializable()
class AndroidNotificationConfig {
  @JsonKey(name: 'channel_id')
  final String? channelId;
  
  final String? sound;
  final String? icon;
  final int? priority;

  const AndroidNotificationConfig({
    this.channelId,
    this.sound,
    this.icon,
    this.priority,
  });

  factory AndroidNotificationConfig.fromJson(Map<String, dynamic> json) => _$AndroidNotificationConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AndroidNotificationConfigToJson(this);
}

/// Complete FCM notification message
@JsonSerializable()
class FCMNotificationMessage {
  final NotificationPayload notification;
  final NotificationData data;
  
  @JsonKey(name: 'android')
  final Map<String, AndroidNotificationConfig>? androidConfig;

  const FCMNotificationMessage({
    required this.notification,
    required this.data,
    this.androidConfig,
  });

  factory FCMNotificationMessage.fromJson(Map<String, dynamic> json) => _$FCMNotificationMessageFromJson(json);
  Map<String, dynamic> toJson() => _$FCMNotificationMessageToJson(this);
}

// Helper methods for creating notification messages
extension FCMNotificationMessageExtensions on FCMNotificationMessage {
  /// Create a receive notification
  static FCMNotificationMessage createReceiveNotification({
    required String amount,
    required String currency,
    required String fromAddress,
    required String toAddress,
    required String transactionId,
    required String walletId,
  }) {
    return FCMNotificationMessage(
      notification: NotificationPayload(
        title: '💰 Received: $amount $currency',
        body: 'From ${fromAddress.length > 10 ? "${fromAddress.substring(0, 6)}...${fromAddress.substring(fromAddress.length - 4)}" : fromAddress}',
      ),
      data: NotificationData(
        transactionId: transactionId,
        type: 'receive',
        direction: 'inbound',
        amount: amount,
        currency: currency,
        symbol: currency, // For backward compatibility
        fromAddress: fromAddress,
        toAddress: toAddress,
        walletId: walletId,
        timestamp: DateTime.now().toIso8601String(),
        status: 'confirmed',
      ),
      androidConfig: {
        'notification': AndroidNotificationConfig(
          channelId: 'receive_channel',
          sound: 'receive_sound',
          icon: 'ic_notification',
          priority: 2, // High priority
        ),
      },
    );
  }

  /// Create a send notification
  static FCMNotificationMessage createSendNotification({
    required String amount,
    required String currency,
    required String fromAddress,
    required String toAddress,
    required String transactionId,
    required String walletId,
  }) {
    return FCMNotificationMessage(
      notification: NotificationPayload(
        title: '📤 Sent: $amount $currency',
        body: 'To ${toAddress.length > 10 ? "${toAddress.substring(0, 6)}...${toAddress.substring(toAddress.length - 4)}" : toAddress}',
      ),
      data: NotificationData(
        transactionId: transactionId,
        type: 'send',
        direction: 'outbound',
        amount: amount,
        currency: currency,
        symbol: currency, // For backward compatibility
        fromAddress: fromAddress,
        toAddress: toAddress,
        walletId: walletId,
        timestamp: DateTime.now().toIso8601String(),
        status: 'confirmed',
      ),
      androidConfig: {
        'notification': AndroidNotificationConfig(
          channelId: 'send_channel',
          sound: 'send_sound',
          icon: 'ic_notification',
          priority: 2, // High priority
        ),
      },
    );
  }
}

/// کلاس برای مدیریت خطاهای API
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const AppException({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  String toString() => 'AppException: $message (Code: $code)';
} 