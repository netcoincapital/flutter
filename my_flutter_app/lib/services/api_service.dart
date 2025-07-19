import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_models.dart';
import '../utils/shared_preferences_utils.dart';

/// API service for server communication
/// This class manages all API requests
class ApiService {
  static const String _baseUrl = 'https://coinceeper.com/api/';
  
  late final Dio _dio;
  
  ApiService() {
    _initializeDio();
  }
  
  /// مقداردهی اولیه Dio برای HTTP requests
  void _initializeDio() {
    // تنظیمات اصلی Dio
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Flutter-App/1.0',
      },
    ));
    
    // اضافه کردن interceptors برای logging
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => print('🌐 API Request/Response: $obj'),
    ));
    
    // اضافه کردن interceptor سفارشی برای لاگ کردن جزئیات بیشتر
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        print('🚀 API REQUEST:');
        print('   URL: ${options.uri}');
        print('   Method: ${options.method}');
        print('   Headers: ${options.headers}');
        print('   Data: ${options.data}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        print('📥 API RESPONSE:');
        print('   Status Code: ${response.statusCode}');
        print('   Headers: ${response.headers}');
        print('   Data: ${response.data}');
        handler.next(response);
      },
      onError: (error, handler) {
        print('❌ API ERROR:');
        print('   Error: ${error.message}');
        print('   Type: ${error.type}');
        if (error.response != null) {
          print('   Status Code: ${error.response!.statusCode}');
          print('   Response Data: ${error.response!.data}');
        }
        handler.next(error);
      },
    ));
  }
  
  /// دریافت UserID از SharedPreferences
  Future<String?> _getUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('UserID');
    } catch (e) {
      print('Error getting User ID: $e');
      return null;
    }
  }
  
  /// اضافه کردن UserID به headers اگر موجود باشد
  Future<Map<String, String>> _getHeaders() async {
    final userId = await _getUserId();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'Flutter-App/1.0',
    };
    
    if (userId != null) {
      headers['UserID'] = userId;
    }
    
    return headers;
  }
  
  /// Handle API errors
  void _handleError(DioException e) {
    print('❌ API Error: ${e.message}');
    if (e.response != null) {
      print('📊 Status Code: ${e.response!.statusCode}');
      print('📄 Response Data: ${e.response!.data}');
    }
    throw Exception('Server communication error: ${e.message}');
  }
  
  // ==================== WALLET OPERATIONS ====================
  
  /// Create new wallet
  /// [walletName]: wallet name
  Future<GenerateWalletResponse> generateWallet(String walletName) async {
    try {
      final request = CreateWalletRequest(walletName: walletName);
      // For new wallet creation, don't send UserID in headers
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Flutter-App/1.0',
      };
      
      print('🌐 API Request - URL: ${_baseUrl}generate-wallet');
      print('📤 Request Data: ${request.toJson()}');
      print('📋 Headers: $headers');
      
      final response = await _dio.post(
        'generate-wallet',
        data: request.toJson(),
        options: Options(headers: headers),
      );
      
      print('📥 Response Status: ${response.statusCode}');
      print('📄 Response Data: ${response.data}');
      
      return GenerateWalletResponse.fromJson(response.data);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }
  
  /// Import wallet with mnemonic
  /// [mnemonic]: wallet recovery phrase
  Future<ImportWalletResponse> importWallet(String mnemonic) async {
    try {
      print('🔧 API Service - Starting import wallet request');
      print('📝 Mnemonic length: ${mnemonic.length}');
      
      final request = ImportWalletRequest(mnemonic: mnemonic);
      final headers = await _getHeaders();
      
      print('📤 Request Data: ${request.toJson()}');
      print('📋 Headers: $headers');
      print('🌐 Making POST request to: ${_baseUrl}import_wallet');
      
      final response = await _dio.post(
        'import_wallet',
        data: request.toJson(),
        options: Options(headers: headers),
      );
      
      print('📥 API Service - Response received:');
      print('   Status Code: ${response.statusCode}');
      print('   Response Data: ${response.data}');
      print('   Response Type: ${response.data.runtimeType}');
      print('   Raw Response String: ${response.data.toString()}');
      
      // Log the response as a map if possible
      if (response.data is Map) {
        print('   Response as Map: ${response.data as Map}');
        final map = response.data as Map;
        print('   Map Keys: ${map.keys.toList()}');
        if (map.containsKey('data')) {
          print('   Data field: ${map['data']}');
          if (map['data'] is Map) {
            final dataMap = map['data'] as Map;
            print('   Data Map Keys: ${dataMap.keys.toList()}');
            if (dataMap.containsKey('UserID')) {
              print('   UserID in data: ${dataMap['UserID']}');
            }
            if (dataMap.containsKey('WalletID')) {
              print('   WalletID in data: ${dataMap['WalletID']}');
            }
          }
        }
        if (map.containsKey('status')) {
          print('   Status field: ${map['status']}');
        }
        if (map.containsKey('message')) {
          print('   Message field: ${map['message']}');
        }
      }
      
      print('🔧 API Service - About to parse response...');
      
      try {
        final importResponse = ImportWalletResponse.fromJson(response.data);
        print('🔧 API Service - Parsed response successfully:');
        print('   Status: ${importResponse.status}');
        print('   Message: ${importResponse.message}');
        print('   Has Data: ${importResponse.data != null}');
        
        if (importResponse.data != null) {
          print('   UserID: ${importResponse.data!.userID}');
          print('   WalletID: ${importResponse.data!.walletID}');
          print('   Has Mnemonic: ${importResponse.data!.mnemonic != null}');
          print('   Mnemonic Length: ${importResponse.data!.mnemonic.length}');
          print('   Addresses Count: ${importResponse.data!.addresses.length}');
        }
        
        return importResponse;
      } catch (e, stackTrace) {
        print('💥 API Service - Error parsing response:');
        print('   Error: $e');
        print('   Stack Trace: $stackTrace');
        print('   Response Data Type: ${response.data.runtimeType}');
        print('   Response Data: ${response.data}');
        rethrow;
      }
    } on DioException catch (e) {
      print('💥 API Service - DioException caught:');
      print('   Error: ${e.message}');
      print('   Type: ${e.type}');
      if (e.response != null) {
        print('   Status Code: ${e.response!.statusCode}');
        print('   Response Data: ${e.response!.data}');
      }
      _handleError(e);
      rethrow;
    } catch (e) {
      print('💥 API Service - General exception: $e');
      rethrow;
    }
  }
  
  /// دریافت آدرس برای دریافت ارز
  /// [userID]: شناسه کاربر
  /// [blockchainName]: نام بلاکچین
  Future<ReceiveResponse> receiveToken(String userID, String blockchainName) async {
    try {
      final request = ReceiveRequest(userID: userID, blockchainName: blockchainName);
      final response = await _dio.post(
        'Recive',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      
      return ReceiveResponse.fromJson(response.data);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }
  
  // ==================== PRICE & BALANCE OPERATIONS ====================
  
  /// دریافت قیمت‌های ارزها
  /// [symbols]: لیست نمادهای ارز
  /// [fiatCurrencies]: لیست ارزهای فیات
  Future<PricesResponse> getPrices(List<String> symbols, List<String> fiatCurrencies) async {
    try {
      final request = PricesRequest(symbol: symbols, fiatCurrencies: fiatCurrencies);
      final response = await _dio.post(
        'prices',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      
      return PricesResponse.fromJson(response.data);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }
  
  /// دریافت موجودی کاربر
  /// [userId]: شناسه کاربر
  /// [currencyNames]: لیست نام‌های ارز (اختیاری)
  /// [blockchain]: نقشه بلاکچین‌ها (اختیاری)
  Future<BalanceResponse> getBalance(
    String userId, {
    List<String> currencyNames = const [],
    Map<String, String> blockchain = const {},
  }) async {
    try {
      final request = BalanceRequest(
        userId: userId,
        currencyNames: currencyNames,
        blockchain: blockchain,
      );
      final response = await _dio.post(
        'balance',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      
      return BalanceResponse.fromJson(response.data);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }
  
  /// دریافت موجودی کاربر (فرمت جدید برای ایمپورت کیف پول)
  /// [userId]: شناسه کاربر
  /// [currencyNames]: لیست نام‌های ارز
  Future<GetUserBalanceResponse> getUserBalance(
    String userId, 
    List<String> currencyNames,
  ) async {
    try {
      print('🔄 API Service - Starting getUserBalance request');
      print('📝 UserID: $userId');
      print('📝 CurrencyNames: $currencyNames');
      
      final request = GetUserBalanceRequest(
        userID: userId,
        currencyName: currencyNames,
      );
      
      final headers = await _getHeaders();
      
      print('📤 Request Data: ${request.toJson()}');
      print('📋 Headers: $headers');
      print('🌐 Making POST request to: ${_baseUrl}balance');
      
      final response = await _dio.post(
        'balance',
        data: request.toJson(),
        options: Options(headers: headers),
      );
      
      print('📥 getUserBalance Response received:');
      print('   Status Code: ${response.statusCode}');
      print('   Response Data: ${response.data}');
      
      return GetUserBalanceResponse.fromJson(response.data);
    } on DioException catch (e) {
      print('❌ Error in getUserBalance: ${e.message}');
      _handleError(e);
      rethrow;
    }
  }
  
  /// دریافت کارمزد گاز برای بلاکچین‌های مختلف
  Future<GasFeeResponse> getGasFee() async {
    try {
      final response = await _dio.get(
        'gasfee',
        options: Options(headers: await _getHeaders()),
      );
      
      return GasFeeResponse.fromJson(response.data);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }
  
  /// دریافت تمام ارزهای موجود
  Future<ApiResponse> getAllCurrencies() async {
    try {
      final response = await _dio.get(
        'all-currencies',
        options: Options(headers: await _getHeaders()),
      );
      
      return ApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }
  
  // ==================== TRANSACTION OPERATIONS ====================
  
  /// دریافت تراکنش‌های کاربر (مطابق با کاتلین)
  /// [request]: درخواست شامل UserID و اختیاری TokenSymbol
  Future<TransactionsResponse> getTransactions(TransactionsRequest request) async {
    try {
      final response = await _dio.post(
        'transactions',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      
      return TransactionsResponse.fromJson(response.data);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  /// دریافت همه تراکنش‌های کاربر (بدون فیلتر) - مطابق با History.kt
  /// فقط UserID ارسال می‌شود
  Future<TransactionsResponse> getTransactionsForUser(String userId) async {
    try {
      final request = TransactionsRequest(userID: userId); // فقط UserID
      return await getTransactions(request);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  /// دریافت تراکنش‌های کاربر برای یک توکن خاص - مطابق با crypto_details.kt
  /// UserID + TokenSymbol ارسال می‌شود
  Future<TransactionsResponse> getTransactionsForToken(String userId, String tokenSymbol) async {
    try {
      final request = TransactionsRequest(userID: userId, tokenSymbol: tokenSymbol); // UserID + TokenSymbol
      return await getTransactions(request);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  /// دریافت تراکنش خاص بر اساس txHash - مطابق با transaction_detail.kt
  /// فقط UserID ارسال می‌شود، جستجو txHash در سمت کلاینت
  Future<TransactionsResponse> getTransactionByHash(String userId, String txHash) async {
    try {
      final request = TransactionsRequest(userID: userId); // فقط UserID
      return await getTransactions(request);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }
  
  /// به‌روزرسانی موجودی
  /// [userID]: شناسه کاربر
  Future<BalanceResponse> updateBalance(String userID) async {
    try {
      final request = UpdateBalanceRequest(userID: userID);
      final response = await _dio.post(
        'update-balance',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      
      return BalanceResponse.fromJson(response.data);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }
  
  /// تست API به‌روزرسانی موجودی
  /// [userID]: شناسه کاربر
  Future<void> testUpdateBalance(String userID) async {
    try {
      print('🧪 Testing updateBalance API...');
      print('📝 UserID: $userID');
      
      final response = await updateBalance(userID);
      
      print('✅ API Response received:');
      print('   Success: ${response.success}');
      print('   UserID: ${response.userID}');
      print('   Balances count: ${response.balances?.length ?? 0}');
      
      if (response.balances != null) {
        for (final balance in response.balances!) {
          print('   Token: ${balance.symbol}');
          print('     Balance: ${balance.balance}');
          print('     Blockchain: ${balance.blockchain}');
          print('     Currency: ${balance.currencyName}');
          print('     Is Token: ${balance.isToken}');
        }
      }
      
      if (response.message != null) {
        print('   Message: ${response.message}');
      }
    } catch (e) {
      print('❌ Error testing updateBalance: $e');
    }
  }
  
  /// اضافه کردن تراکنش جدید
  /// [transaction]: اطلاعات تراکنش
  Future<TransactionsResponse> addTransaction(Transaction transaction) async {
    try {
      final response = await _dio.post(
        'wallet/add-transaction',
        data: transaction.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      
      return TransactionsResponse.fromJson(response.data);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }
  
  // ==================== SEND OPERATIONS ====================
  
  /// آماده‌سازی تراکنش برای ارسال
  /// [userID]: شناسه کاربر
  /// [blockchainName]: نام بلاکچین
  /// [senderAddress]: آدرس فرستنده
  /// [recipientAddress]: آدرس گیرنده
  /// [amount]: مقدار ارسالی
  /// [smartContractAddress]: آدرس قرارداد هوشمند (اختیاری)
  Future<PrepareTransactionResponse> prepareTransaction({
    required String userID,
    required String blockchainName,
    required String senderAddress,
    required String recipientAddress,
    required String amount,
    String smartContractAddress = '',
  }) async {
    try {
      final request = PrepareTransactionRequest(
        userID: userID,
        blockchainName: blockchainName,
        senderAddress: senderAddress,
        recipientAddress: recipientAddress,
        amount: amount,
        smartContractAddress: smartContractAddress,
      );
      
      // Debug log for exact request data
      print('🔧 DEBUG: prepareTransaction request data:');
      print('   Full URL: ${_baseUrl}send/prepare');
      print('   Base URL: $_baseUrl');
      print('   Endpoint: send/prepare');
      print('   Request Body: ${request.toJson()}');
      print('   Raw JSON: ${jsonEncode(request.toJson())}');
      
      // Try with minimal headers for debugging
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      
      print('🔧 DEBUG: Using minimal headers: $headers');
      
      final response = await _dio.post(
        'send/prepare',
        data: request.toJson(),
        options: Options(headers: headers),
      );
      
      return PrepareTransactionResponse.fromJson(response.data);
    } on DioException catch (e) {
      print('❌ prepareTransaction ERROR:');
      print('   Status Code: ${e.response?.statusCode}');
      print('   Response Data: ${e.response?.data}');
      print('   Error Message: ${e.message}');
      _handleError(e);
      rethrow;
    }
  }
  
  /// تخمین کارمزد تراکنش
  /// [userID]: شناسه کاربر
  /// [blockchain]: نام بلاکچین
  /// [fromAddress]: آدرس فرستنده
  /// [toAddress]: آدرس گیرنده
  /// [amount]: مقدار
  /// [type]: نوع تراکنش (اختیاری)
  /// [tokenContract]: آدرس توکن (اختیاری)
  Future<EstimateFeeResponse> estimateFee({
    required String userID,
    required String blockchain,
    required String fromAddress,
    required String toAddress,
    required double amount,
    String? type,
    String tokenContract = '',
  }) async {
    try {
      final request = EstimateFeeRequest(
        userID: userID,
        blockchain: blockchain,
        fromAddress: fromAddress,
        toAddress: toAddress,
        amount: amount,
        type: type,
        tokenContract: tokenContract,
      );
      
      print('🔧 DEBUG: EstimateFee Request:');
      print('   UserID: $userID');
      print('   Blockchain: $blockchain');
      print('   From: $fromAddress');
      print('   To: $toAddress');
      print('   Amount: $amount');
      print('   Token Contract: $tokenContract');
      print('   JSON: ${request.toJson()}');
      
      final response = await _dio.post(
        'estimate-fee',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      
      print('✅ EstimateFee Response: ${response.data}');
      
      return EstimateFeeResponse.fromJson(response.data);
    } on DioException catch (e) {
      print('❌ EstimateFee DioException: ${e.response?.statusCode} - ${e.response?.data}');
      _handleError(e);
      rethrow;
    } catch (e) {
      print('❌ EstimateFee Exception: $e');
      throw Exception('Error estimating fee: $e');
    }
  }
  
  /// تایید و ارسال تراکنش
  /// [userID]: شناسه کاربر
  /// [transactionId]: شناسه تراکنش
  /// [blockchain]: نام بلاکچین
  /// [privateKey]: کلید خصوصی
  Future<ConfirmTransactionResponse> confirmTransaction({
    required String userID,
    required String transactionId,
    required String blockchain,
    required String privateKey,
  }) async {
    try {
      final request = ConfirmTransactionRequest(
        userID: userID,
        transactionId: transactionId,
        blockchain: blockchain,
        privateKey: privateKey,
      );
      
      // Debug log for confirm transaction
      print('🔧 DEBUG: confirmTransaction request data:');
      print('   UserID: $userID');
      print('   TransactionId: $transactionId');
      print('   Blockchain: $blockchain');
      print('   PrivateKey: ${privateKey.substring(0, 8)}...');
      print('   Full URL: ${_baseUrl}send/confirm');
      print('   Request Body: ${request.toJson()}');
      
      // Add UserID to headers (same as cURL test)
      final headers = await _getHeaders();
      headers['UserID'] = userID;
      print('   Headers: $headers');
      
      final response = await _dio.post(
        'send/confirm',
        data: request.toJson(),
        options: Options(headers: headers),
      );
      
      print('✅ confirmTransaction Response: ${response.data}');
      
      return ConfirmTransactionResponse.fromJson(response.data);
    } on DioException catch (e) {
      print('❌ confirmTransaction ERROR:');
      print('   Status Code: ${e.response?.statusCode}');
      print('   Response Data: ${e.response?.data}');
      print('   Response Headers: ${e.response?.headers}');
      print('   Request Data: ${e.requestOptions.data}');
      print('   Request Headers: ${e.requestOptions.headers}');
      print('   Request Method: ${e.requestOptions.method}');
      print('   Request URL: ${e.requestOptions.uri}');
      print('   Error Message: ${e.message}');
      print('   Error Type: ${e.type}');
      
      // If it's a 400 error but response has data, try to parse it
      if (e.response?.statusCode == 400 && e.response?.data != null) {
        try {
          print('🔧 Trying to parse 400 response as success...');
          final responseData = e.response!.data;
          print('   Raw response data: $responseData');
          
          // Check if it's actually a success response
          if (responseData is Map<String, dynamic>) {
            final message = responseData['message'];
            final status = responseData['status'];
            final txHash = responseData['tx_hash'] ?? responseData['transaction_hash'];
            
            if (message == "Transaction sent successfully" || 
                status == "sent" || 
                (txHash != null && txHash.toString().isNotEmpty)) {
              print('✅ Found success response in 400 error! Parsing as success...');
              return ConfirmTransactionResponse.fromJson(responseData);
            }
            
            // Handle specific Tatum API errors
            if (message != null && message.contains('Failed to broadcast transaction via Tatum API')) {
              print('❌ Tatum API broadcast failed - this is a server-side issue');
              throw Exception('Network broadcast failed. Please try again later.');
            }
          }
        } catch (parseError) {
          print('❌ Error parsing 400 response: $parseError');
        }
      }
      
      _handleError(e);
      rethrow;
    }
  }
  
  // ==================== NOTIFICATION OPERATIONS ====================
  
  /// ثبت دستگاه برای دریافت اعلان‌ها
  /// [userId]: شناسه کاربر
  /// [walletId]: wallet identifier
  /// [deviceToken]: توکن دستگاه
  /// [deviceName]: نام دستگاه
  /// [deviceType]: نوع دستگاه
  Future<RegisterDeviceResponse> registerDevice({
    required String userId,
    required String walletId,
    required String deviceToken,
    required String deviceName,
    String deviceType = 'android',
  }) async {
    try {
      final request = RegisterDeviceRequest(
        userId: userId,
        walletId: walletId,
        deviceToken: deviceToken,
        deviceName: deviceName,
        deviceType: deviceType,
      );
      final response = await _dio.post(
        'notifications/register-device',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      
      return RegisterDeviceResponse.fromJson(response.data);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }
  

} 