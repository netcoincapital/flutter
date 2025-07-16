# 🧪 راهنمای Security Testing

## 🚀 اجرای تست‌های امنیتی

### استفاده سریع
```dart
import 'package:my_flutter_app/utils/security_test.dart';

// تست کامل امنیت
final results = await SecurityTest.runAllTests();
print(SecurityTest.generateTestReport(results));

// تست سریع
final isSecure = await SecurityTest.quickSecurityCheck();
print('Security Status: ${isSecure ? '✅ Secure' : '❌ Insecure'}');
```

### در کد اصلی اپلیکیشن
```dart
// در main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تست امنیت در حالت debug
  if (kDebugMode) {
    final isSecure = await SecurityTest.quickSecurityCheck();
    print('🔐 Security Check: ${isSecure ? 'PASSED' : 'FAILED'}');
  }
  
  runApp(MyApp());
}
```

### تست Performance
```dart
// Benchmark امنیت
final benchmark = await SecurityTest.runPerformanceBenchmark();
print('AES Performance: ${benchmark['aes_encryption']['operations_per_second']} ops/sec');
```

## 📊 نتایج تست

### Security Score
- **85+**: Excellent ✅
- **70-84**: Good 🟡
- **60-69**: Needs Improvement 🟠
- **<60**: Critical Issues 🔴

### گزارش مثال
```
🛡️ SECURITY TEST REPORT
==================================================
Overall Score: 85%
Tests Passed: 4/5

✅ AES ENCRYPTION - Duration: 45ms
✅ HSM STORAGE - Duration: 120ms  
✅ SECURITY MIGRATION - Duration: 30ms
❌ CERTIFICATE PINNING - Error: Network unavailable
```

## 🔧 Configuration

### تنظیمات تست
```dart
// Test با تنظیمات سفارشی
SecurityTest.configure(
  enableNetworkTests: true,
  enablePerformanceTests: true,
  testIterations: 100,
);
```

### استفاده در CI/CD
```yaml
# در .github/workflows/security.yml
- name: Run Security Tests
  run: |
    flutter test test/security_test.dart
    flutter test --coverage
```

## 📋 Test Categories

### 1. Cryptography Tests
- AES-256-GCM encryption/decryption
- PBKDF2 key derivation
- Secure random generation
- Wrong password handling

### 2. Storage Tests  
- HSM availability
- Device binding
- Fallback mechanisms
- Data integrity

### 3. Communication Tests
- Certificate pinning
- SSL validation
- Network security
- TLS configuration

### 4. Migration Tests
- Legacy data detection
- Automatic upgrade
- Backward compatibility
- Data preservation

## 🎯 Best Practices

### روتین تست
```dart
// تست روزانه
void dailySecurityCheck() async {
  final results = await SecurityTest.runAllTests();
  final report = SecurityTest.generateTestReport(results);
  
  // ارسال گزارش به تیم
  await sendSecurityReport(report);
}
```

### Integration با Monitoring
```dart
// تست مداوم
void monitorSecurity() async {
  Timer.periodic(Duration(hours: 1), (timer) async {
    final isSecure = await SecurityTest.quickSecurityCheck();
    if (!isSecure) {
      await alertSecurityTeam();
    }
  });
}
```

## 🔍 Troubleshooting

### مشکلات رایج
1. **HSM Test Fails**: دستگاه از HSM پشتیبانی نمی‌کند
2. **Network Test Fails**: اتصال اینترنت قطع است
3. **Migration Test Fails**: داده‌های legacy وجود ندارد

### راه‌حل
```dart
// بررسی availability
final hsmAvailable = await SecureStorage.instance.isHSMAvailable();
if (!hsmAvailable) {
  print('⚠️ HSM not available on this device');
}
```

## 📱 Platform-Specific Notes

### Android
- نیاز به API 23+ برای HSM
- Hardware keystore required
- Biometric authentication optional

### iOS  
- Keychain access required
- Touch ID/Face ID optional
- Hardware security available

---

**نکته**: تست‌های امنیتی را به صورت مداوم اجرا کنید تا از امنیت اپلیکیشن اطمینان حاصل شود. 