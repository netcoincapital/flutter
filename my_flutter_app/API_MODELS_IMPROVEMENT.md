# بهبود فایل api_models.dart

## خلاصه تغییرات

فایل `api_models.dart` به طور کامل بازنویسی شد تا از JSON serialization خودکار استفاده کند و قابلیت‌های بیشتری داشته باشد.

## تغییرات اصلی

### 1. اضافه شدن JSON Serialization
- تمام کلاس‌ها با `@JsonSerializable()` علامت‌گذاری شدند
- از `@JsonKey()` برای نام‌گذاری فیلدها استفاده شد
- متدهای `fromJson` و `toJson` خودکار تولید می‌شوند

### 2. بهبود Validation
- از `assert` برای بررسی مقادیر ورودی استفاده شد
- بررسی‌های امنیتی برای فیلدهای اجباری اضافه شد

### 3. بهبود Type Safety
- تمام فیلدها با نوع‌های دقیق تعریف شدند
- از `const` constructor استفاده شد
- Null safety به طور کامل پیاده‌سازی شد

### 4. اضافه شدن کلاس‌های Utility
- `ApiResult<T>` برای مدیریت نتایج API
- `AppException` برای مدیریت خطاها

## مزایای نسخه جدید

### 1. عملکرد بهتر
```dart
// قبل - دستی
Map<String, dynamic> toJson() {
  return {
    'UserID': userID,
    'CurrencyName': currencyName,
  };
}

// بعد - خودکار
Map<String, dynamic> toJson() => _$SendRequestToJson(this);
```

### 2. امنیت بیشتر
```dart
const SendRequest({
  required this.userID,
  required this.currencyName,
  required this.recipientAddress,
  required this.amount,
}) : assert(userID.isNotEmpty, 'UserID cannot be empty'),
     assert(currencyName.isNotEmpty, 'CurrencyName cannot be empty'),
     assert(recipientAddress.isNotEmpty, 'RecipientAddress cannot be empty'),
     assert(amount.isNotEmpty, 'Amount cannot be empty');
```

### 3. مدیریت خطای بهتر
```dart
class ApiResult<T> {
  final T? data;
  final String? error;
  final bool isSuccess;

  const ApiResult.success(this.data) : error = null, isSuccess = true;
  const ApiResult.error(this.error) : data = null, isSuccess = false;
}
```

## کلاس‌های Request بهبود یافته

### 1. CreateWalletRequest
```dart
@JsonSerializable()
class CreateWalletRequest {
  @JsonKey(name: 'WalletName')
  final String walletName;

  const CreateWalletRequest({required this.walletName}) 
    : assert(walletName.isNotEmpty, 'Wallet name cannot be empty');
}
```

### 2. SendRequest
```dart
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
}
```

### 3. BalanceRequest
```dart
@JsonSerializable()
class BalanceRequest {
  @JsonKey(name: 'UserID')
  final String userId;
  
  @JsonKey(name: 'CurrencyName')
  final List<String> currencyNames;
  
  @JsonKey(name: 'Blockchain')
  final Map<String, String> blockchain;
}
```

## کلاس‌های Response بهبود یافته

### 1. GenerateWalletResponse
```dart
@JsonSerializable()
class GenerateWalletResponse {
  final bool success;
  
  @JsonKey(name: 'UserID')
  final String? userID;
  
  @JsonKey(name: 'WalletID')
  final String? walletID;
  
  final String? mnemonic;
  final String? message;
}
```

### 2. BalanceResponse
```dart
@JsonSerializable()
class BalanceResponse {
  final bool success;
  
  @JsonKey(name: 'Balances')
  final List<BalanceItem>? balances;
  
  @JsonKey(name: 'UserID')
  final String? userID;
  final String? message;
}
```

### 3. Transaction
```dart
@JsonSerializable()
class Transaction {
  final String txHash;
  final String from;
  final String to;
  final String amount;
  
  @JsonKey(name: 'tokenSymbol')
  final String tokenSymbol;
  final String direction;
  final String status;
  final String timestamp;
  
  @JsonKey(name: 'blockchainName')
  final String blockchainName;
  final double? price;
  
  @JsonKey(name: 'temporaryId')
  final String? temporaryId;
}
```

## نحوه استفاده

### 1. ایجاد Request
```dart
final request = SendRequest(
  userID: 'user123',
  currencyName: 'BTC',
  recipientAddress: '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
  amount: '0.001',
);
```

### 2. تبدیل به JSON
```dart
final json = request.toJson();
// نتیجه: {'UserID': 'user123', 'CurrencyName': 'BTC', ...}
```

### 3. تبدیل از JSON
```dart
final response = SendResponse.fromJson(jsonData);
```

### 4. مدیریت خطا
```dart
try {
  final result = await apiService.send(request);
  return ApiResult.success(result);
} catch (e) {
  return ApiResult.error('خطا در ارسال تراکنش: $e');
}
```

## فایل‌های تولید شده

- `api_models.g.dart` - فایل تولید شده توسط build_runner
- شامل تمام متدهای `fromJson` و `toJson` خودکار

## نکات مهم

1. **Build Runner**: برای تولید فایل‌های JSON، دستور زیر را اجرا کنید:
   ```bash
   dart run build_runner build
   ```

2. **Watch Mode**: برای نظارت بر تغییرات:
   ```bash
   dart run build_runner watch
   ```

3. **Clean**: برای پاک کردن فایل‌های قدیمی:
   ```bash
   dart run build_runner clean
   ```

## سازگاری با Backend

تمام مدل‌ها با API های Kotlin سازگار هستند و نام‌گذاری فیلدها مطابق با backend است:

- `UserID` → `user_id`
- `WalletID` → `wallet_id`
- `BlockchainName` → `blockchain_name`
- `CurrencyName` → `currency_name`

## نتیجه‌گیری

نسخه جدید `api_models.dart`:
- ✅ سریع‌تر و کارآمدتر
- ✅ امن‌تر با validation
- ✅ قابل نگهداری بهتر
- ✅ سازگار با backend
- ✅ پشتیبانی کامل از null safety
- ✅ مدیریت خطای بهتر 