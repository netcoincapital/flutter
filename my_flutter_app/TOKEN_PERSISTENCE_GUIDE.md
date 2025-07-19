# راهنمای ماندگاری وضعیت توکن‌ها (Token Persistence Guide)

## مقدمه

این راهنما توضیح می‌دهد که چگونه وضعیت توکن‌ها (فعال/غیرفعال) در اپلیکیشن به صورت دائمی ذخیره و بازیابی می‌شود. پیاده‌سازی جدید مشابه کد Kotlin است.

## معماری سیستم (مشابه Kotlin)

### 1. TokenPreferences
کلاس مسئول مدیریت ذخیره‌سازی وضعیت توکن‌ها در `SharedPreferences`:

```dart
class TokenPreferences {
  // کش برای دسترسی سریع - مشابه Kotlin
  static final Map<String, bool> _tokenStateCache = {};
  
  // ذخیره وضعیت توکن برای کاربر خاص
  Future<void> saveTokenState(String symbol, String blockchainName, String? smartContractAddress, bool isEnabled)
  
  // دریافت وضعیت توکن
  Future<bool?> getTokenState(String symbol, String blockchainName, String? smartContractAddress)
  
  // دریافت sync وضعیت توکن
  bool? getTokenStateSync(String symbol, String blockchainName, String? smartContractAddress)
}
```

### 2. TokenProvider (مشابه token_view_model.kt)
کلاس مسئول مدیریت توکن‌ها و ارتباط با TokenPreferences:

```dart
class TokenProvider {
  // Toggle کردن وضعیت توکن - مشابه Kotlin
  Future<void> toggleToken(CryptoToken token, bool newState)
  
  // همگام‌سازی کامل tokens - مشابه ensureTokensSynchronized
  Future<void> ensureTokensSynchronized()
  
  // بررسی فعال بودن توکن برای کاربر خاص
  bool isTokenEnabled(CryptoToken token)
  
  // مدیریت User-specific tokens
  void saveUserTokens(String userId, List<CryptoToken> tokens)
  void setActiveTokensForUser(List<CryptoToken> tokens)
}
```

### 3. AddTokenScreen (مشابه Kotlin UI)
صفحه مدیریت توکن‌ها که مستقیماً با TokenProvider کار می‌کند.

## فرآیند ذخیره‌سازی (مشابه Kotlin)

### 1. هنگام فعال/غیرفعال کردن توکن:

```dart
Future<void> _toggleToken(CryptoToken token) async {
  final newState = !token.isEnabled;
  
  // 1. مستقیماً از TokenProvider برای toggle استفاده کن
  await tokenProvider.toggleToken(token, newState);
  
  // 2. تأیید اینکه state درست ذخیره شده است
  final verifyState = tokenProvider.isTokenEnabled(token);
  if (verifyState != newState) {
    // تلاش مجدد برای ذخیره
    await tokenProvider.saveTokenStateForUser(token, newState);
  }
  
  // 3. به‌روزرسانی UI
  setState(() { ... });
}
```

### 2. کلید منحصر به فرد (مشابه Kotlin):
```dart
String _getTokenKey(String symbol, String blockchainName, String? smartContractAddress) {
  return 'token_state_${symbol}_${blockchainName}_${smartContractAddress ?? ''}';
}
```

## فرآیند بازیابی (مشابه Kotlin)

### 1. هنگام راه‌اندازی اپلیکیشن:

```dart
// AppProvider initialization
void _initializeTokenProviderInBackground() {
  _getOrCreateTokenProvider(_currentUserId!).then((tokenProvider) {
    // اطمینان از synchronization فوری
    tokenProvider.ensureTokensSynchronized();
  });
}
```

### 2. بارگذاری توکن‌ها:

```dart
Future<void> _loadTokens({bool forceRefresh = false}) async {
  // 1. اطمینان از مقداردهی اولیه TokenPreferences
  await tokenProvider.tokenPreferences.initialize();
  
  // 2. همگام‌سازی tokens - مشابه Kotlin
  await tokenProvider.ensureTokensSynchronized();
  
  // 3. دریافت tokens از TokenProvider
  final tokens = tokenProvider.currencies;
}
```

## بهبودهای جدید (مشابه Kotlin)

### 1. User-Specific Token Management:
```dart
// مدیریت توکن‌ها برای هر کاربر جداگانه
void saveUserTokens(String userId, List<CryptoToken> tokens) {
  _userTokens[userId] = tokens;
}

bool getTokenStateForUser(CryptoToken token) {
  return tokenPreferences.getTokenStateSync(...) ?? false;
}
```

### 2. Enhanced Toggle Method:
```dart
Future<void> toggleToken(CryptoToken token, bool newState) async {
  // 1. ذخیره state در preferences
  await tokenPreferences.saveTokenState(...);
  
  // 2. به‌روزرسانی currencies list
  _currencies = _currencies.map((currentToken) => {
    if (matches) return currentToken.copyWith(isEnabled: newState);
    return currentToken;
  }).toList();
  
  // 3. به‌روزرسانی active tokens
  if (newState) {
    _activeTokens.add(token.copyWith(isEnabled: true));
  } else {
    _activeTokens.removeWhere((t) => matches);
  }
  
  // 4. ذخیره در cache و notify
  await _saveToCache(...);
  notifyListeners();
}
```

### 3. Complete Synchronization:
```dart
Future<void> ensureTokensSynchronized() async {
  // 1. بارگذاری از cache یا API
  if (_currencies.isEmpty) {
    await loadFromCacheOrApi();
  }
  
  // 2. همگام‌سازی با preferences
  final updatedCurrencies = _currencies.map((token) {
    final isEnabled = tokenPreferences.getTokenStateSync(...);
    return token.copyWith(isEnabled: isEnabled);
  }).toList();
  
  // 3. به‌روزرسانی active tokens
  _activeTokens = updatedCurrencies.where((t) => t.isEnabled).toList();
  
  // 4. اطمینان از tokens پیش‌فرض
  if (_activeTokens.isEmpty) {
    await _initializeDefaultTokens();
  }
}
```

## مزایای پیاده‌سازی جدید

### 1. سازگاری کامل با Kotlin:
- مدیریت User-specific tokens
- Toggle method مشابه
- Synchronization کامل
- Error handling بهتر

### 2. بهبود Performance:
- Cache دوسطحی (Memory + SharedPreferences)
- Background loading
- Lazy initialization

### 3. Reliability بهتر:
- Verification بعد از toggle
- Retry mechanism
- Fallback برای tokens پیش‌فرض

## نحوه استفاده (مشابه Kotlin)

### 1. برای کاربران:
- وارد صفحه "Token Management" شوید
- توکن مورد نظر را فعال یا غیرفعال کنید
- وضعیت فوراً ذخیره می‌شود
- پس از restart، وضعیت حفظ می‌شود

### 2. برای توسعه‌دهندگان:
```dart
// بررسی وضعیت توکن
bool isEnabled = tokenProvider.isTokenEnabled(token);

// فعال کردن توکن
await tokenProvider.toggleToken(token, true);

// همگام‌سازی کامل
await tokenProvider.ensureTokensSynchronized();
```

## تست کردن

برای تست ماندگاری:
1. توکنی را فعال کنید
2. اپلیکیشن را ببندید
3. اپلیکیشن را دوباره باز کنید
4. بررسی کنید که وضعیت حفظ شده است

## Debug و عیب‌یابی

### 1. اگر وضعیت توکن‌ها حفظ نمی‌شود:
```dart
// بررسی لاگ‌ها
print('🔄 TokenProvider - Active tokens: ${_activeTokens.length}');
print('🔄 TokenProvider - User tokens: ${_userTokens[_userId]?.length ?? 0}');

// همگام‌سازی مجدد
await tokenProvider.ensureTokensSynchronized();
```

### 2. اگر TokenProvider مقداردهی نشده:
```dart
// در AppProvider
await tokenProvider.ensureTokensSynchronized();
```

## نتیجه‌گیری

سیستم ماندگاری توکن‌ها اکنون کاملاً مشابه Kotlin پیاده‌سازی شده و شامل:
- User-specific token management
- Enhanced toggle mechanism
- Complete synchronization
- Robust error handling
- Background initialization

تمام تغییرات توکن‌ها اکنون بین نشست‌های مختلف برنامه حفظ می‌شوند و کاملاً مطابق کد Kotlin عمل می‌کند. 