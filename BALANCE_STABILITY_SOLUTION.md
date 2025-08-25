# حل مشکل پایداری نمایش موجودی‌ها (Balance Display Stability Solution)

## مشکل
موجودی‌ها در صفحه home اول نمایش داده می‌شدند اما بعد از چند دقیقه ناپدید می‌شدند. همچنین وقتی اپلیکیشن kill می‌شد و دوباره باز می‌شد، موجودی‌ها ابتدا درست نمایش داده می‌شدند اما در عرض 2 ثانیه همه صفر می‌شدند.

## علت‌های اصلی مشکل

1. **عدم fetch مداوم موجودی‌ها**: کد فعلی فقط بعد از import wallet موجودی‌ها را fetch می‌کرد
2. **Timer فقط برای قیمت‌ها**: periodic timer فقط قیمت‌ها را به‌روزرسانی می‌کرد، نه موجودی‌ها
3. **Cache پراکنده**: سیستم‌های cache مختلف و غیرهماهنگ وجود داشت
4. **عدم persistence بین navigation**: موجودی‌ها هنگام جابجایی بین صفحات حفظ نمی‌شدند
5. **تداخل در startup**: چندین سیستم همزمان سعی در بارگذاری موجودی‌ها داشتند
6. **عدم محافظت از API خالی**: پاسخ‌های خالی از API موجودی‌های cached را پاک می‌کردند

## راه‌حل پیاده‌سازی شده

### 1. BalanceManager - مدیریت پایدار موجودی‌ها

یک `BalanceManager` singleton ایجاد شد که:
- **Cache مرکزی**: همه موجودی‌ها در یک مکان مرکزی نگهداری می‌شوند
- **Refresh خودکار**: هر 90 ثانیه موجودی‌ها از سرور بازنشانی می‌شوند
- **Persistence**: موجودی‌ها هم در SharedPreferences و هم در SecureStorage ذخیره می‌شوند
- **Per-user/wallet**: موجودی‌ها بر اساس کاربر و کیف پول جداگانه مدیریت می‌شوند
- **Startup Protection**: مدیریت ویژه برای زمان startup app
- **Zero Balance Protection**: جلوگیری از صفر شدن ناگهانی موجودی‌ها
- **Thread Safety**: locks برای جلوگیری از concurrent operations

### 2. StableBalanceDisplay - Widget پایدار نمایش

Widget جدیدی ایجاد شد که:
- از BalanceManager برای دریافت موجودی استفاده می‌کند
- Fallback هوشمند به token amount در صورت عدم دسترسی به BalanceManager
- Priority logic برای انتخاب بهترین مقدار موجودی (جلوگیری از نمایش 0 در transitions)
- Listener دارد برای به‌روزرسانی خودکار UI
- AutomaticKeepAliveClientMixin برای حفظ state

### 3. Integration با HomeScreen

صفحه home به‌روزرسانی شد تا:
- BalanceManager را initialize کند
- Context کاربر و کیف پول را با delay تنظیم کند (جلوگیری از startup conflicts)
- Timer periodic هم قیمت‌ها و هم موجودی‌ها را refresh کند
- Manual refresh از BalanceManager استفاده کند
- Conservative approach در startup (استفاده از cached data)

### 4. Integration با AppProvider

AppProvider به‌روزرسانی شد تا:
- هنگام تغییر کیف پول، BalanceManager را به‌روزرسانی کند
- Context جدید را به BalanceManager اطلاع دهد

## فایل‌های ایجاد/تغییر یافته

### فایل‌های جدید:
- `lib/services/balance_manager.dart` - مدیریت مرکزی موجودی‌ها
- `lib/services/balance_stability_test.dart` - تست پایداری

### فایل‌های به‌روزرسانی شده:
- `lib/widgets/stable_balance_display.dart` - Widget پایدار نمایش
- `lib/screens/home_screen.dart` - Integration با BalanceManager
- `lib/providers/app_provider.dart` - Coordination با BalanceManager

## مزایای راه‌حل

### 1. پایداری کامل
- موجودی‌ها هیچ‌وقت ناپدید نمی‌شوند حتی بعد از app kill
- محافظت از صفر شدن ناگهانی موجودی‌ها
- Refresh خودکار و مداوم از سرور
- Cache چندلایه برای اطمینان از در دسترس بودن

### 2. Performance بهتر
- Cache هوشمند با validity period
- Thread-safe operations با locks
- Non-blocking background refresh
- Startup optimization برای کاهش تداخل

### 3. User Experience بهتر
- نمایش فوری موجودی‌ها از cache
- Smooth updates بدون flickering در startup
- Persistence بین navigation
- Priority logic برای انتخاب بهترین مقدار

### 4. Maintainability
- Architecture تمیز و جداگانه
- Centralized balance management
- Clear separation of concerns

## نحوه استفاده

### برای نمایش موجودی در UI:

```dart
StableBalanceDisplay(
  token: cryptoToken,
  userId: currentUserId,
  isHidden: false,
  showIcon: true,
  showValue: true,
)
```

### برای دسترسی برنامه‌ای به موجودی:

```dart
// Get balance for specific token
final balance = BalanceManager.instance.getTokenBalance(userId, 'BTC');

// Get all user balances
final allBalances = BalanceManager.instance.getUserBalances(userId);

// Force refresh
await BalanceManager.instance.refreshBalancesForUser(userId, force: true);
```

## تنظیمات قابل تغییر

در `BalanceManager`:
- `_balanceCacheValidity`: مدت اعتبار cache (پیش‌فرض: 3 دقیقه)
- `_refreshInterval`: فاصله refresh خودکار (پیش‌فرض: 90 ثانیه)
- `_persistenceInterval`: فاصله ذخیره‌سازی (پیش‌فرض: 30 ثانیه)

## Testing

برای تست پایداری:
```dart
await BalanceStabilityTest.quickValidationTest();
// یا
await BalanceStabilityTest.runStabilityTest(); // 5 دقیقه تست
```

## مشکل خاص App Kill

### علت مشکل:
وقتی اپلیکیشن kill می‌شود و دوباره باز می‌شود، چندین فرآیند همزمان اجرا می‌شوند:
1. TokenProvider موجودی‌های cached را load می‌کند
2. BalanceManager شروع به initialization می‌کند  
3. HomeScreen API call برای refresh می‌زند
4. این فرآیندها با هم تداخل ایجاد می‌کنند و API خالی موجودی‌ها را صفر می‌کند

### راه‌حل:
- **Startup Protection**: BalanceManager در startup محتاط‌تر عمل می‌کند
- **Delayed Initialization**: تنظیم context با 800ms delay
- **Priority Logic**: انتخاب بهترین مقدار بین BalanceManager و TokenProvider
- **Zero Balance Protection**: جلوگیری از پذیرش پاسخ‌های خالی API
- **Thread Safety**: استفاده از locks برای جلوگیری از concurrent operations

## خلاصه

این راه‌حل مشکل پایداری نمایش موجودی‌ها و مشکل app kill را به طور کامل حل می‌کند. موجودی‌ها حالا همیشه به‌روز، پایدار و محافظت شده هستند، حتی در شرایط پیچیده startup.
