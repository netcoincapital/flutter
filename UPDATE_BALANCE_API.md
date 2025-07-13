# Update Balance API

## وضعیت پیاده‌سازی

✅ **API قبلاً پیاده‌سازی شده و آماده استفاده است**

## مشخصات API

### Endpoint
```
POST /update-balance
```

### Request Body
```json
{
  "UserID": "83d816f7-329a-4bd2-b9fd-5f36970c55a0"
}
```

### Response
```json
{
  "Balances": [
    {
      "balance": "9.206907331361321586",
      "blockchain": "Polygon",
      "currency_name": "POL",
      "is_token": false,
      "symbol": "POL"
    },
    {
      "balance": "2.233161",
      "blockchain": "Tron",
      "currency_name": "Tron",
      "is_token": false,
      "symbol": "TRX"
    }
  ],
  "UserID": "83d816f7-329a-4bd2-b9fd-5f36970c55a0",
  "success": true
}
```

## نحوه استفاده

### 1. استفاده از API Service

```dart
import 'package:my_flutter_app/services/api_service.dart';

// دریافت instance از API service
final apiService = APIService();

// به‌روزرسانی موجودی
try {
  final response = await apiService.updateBalance(userID);
  
  if (response.success) {
    print('Balance updated successfully');
    // استفاده از response.balances
    for (final balance in response.balances ?? []) {
      print('${balance.symbol}: ${balance.balance}');
    }
  } else {
    print('Failed to update balance: ${response.message}');
  }
} catch (e) {
  print('Error updating balance: $e');
}
```

### 2. استفاده از Token Provider

```dart
import 'package:provider/provider.dart';
import 'package:my_flutter_app/providers/token_provider.dart';

// در widget
Consumer<TokenProvider>(
  builder: (context, tokenProvider, child) {
    return ElevatedButton(
      onPressed: () async {
        final success = await tokenProvider.updateBalance();
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Balance updated successfully')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update balance')),
          );
        }
      },
      child: Text('Update Balance'),
    );
  },
);
```

### 3. Test API

```dart
// تست API
await apiService.testUpdateBalance(userID);
```

## پیاده‌سازی فعلی

### Files
- `lib/services/api_service.dart` - متد `updateBalance()`
- `lib/services/api_models.dart` - `UpdateBalanceRequest` و `BalanceResponse`
- `lib/providers/token_provider.dart` - متد `updateBalance()`
- `screens/home_screen.dart` - دکمه Refresh در UI

### Features
- ✅ درخواست POST به endpoint `update-balance`
- ✅ مدل‌های Request و Response
- ✅ Error handling
- ✅ Integration با TokenProvider
- ✅ UI button در صفحه Home
- ✅ Notification برای کاربر
- ✅ Automatic price refresh بعد از update

## استفاده در UI

در صفحه Home، دکمه "Refresh" اضافه شده است که:
1. API update-balance را فراخوانی می‌کند
2. موجودی توکن‌ها را به‌روزرسانی می‌کند
3. قیمت‌ها را مجدداً دریافت می‌کند
4. نتیجه را به کاربر نمایش می‌دهد

## مثال کاربردی

```dart
// در هر جایی از کد که نیاز به به‌روزرسانی موجودی دارید:
final tokenProvider = Provider.of<TokenProvider>(context, listen: false);
final success = await tokenProvider.updateBalance();

if (success) {
  print('✅ Balance updated successfully');
  // موجودی‌های جدید در tokenProvider.enabledTokens موجود است
} else {
  print('❌ Failed to update balance');
}
```

## نکات مهم

1. **UserID**: باید UserID معتبر ارسال شود
2. **Token Mapping**: Response format با مدل‌های Flutter سازگار است
3. **Error Handling**: خطاهای شبکه و API به درستی handle می‌شوند
4. **UI Integration**: دکمه Refresh در Home screen موجود است
5. **Automatic Updates**: بعد از update، قیمت‌ها و UI به‌روزرسانی می‌شوند 