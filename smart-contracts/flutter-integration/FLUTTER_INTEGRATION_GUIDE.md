# 📱 راهنمای ادغام Flutter با Smart Contracts

## 🔧 **مرحله 1: نصب Dependencies**

### pubspec.yaml
```yaml
dependencies:
  flutter:
    sdk: flutter
  web3dart: ^2.7.3
  http: ^1.1.0
  provider: ^6.1.1
  shared_preferences: ^2.2.2
  
dev_dependencies:
  build_runner: ^2.4.7
```

## 📁 **مرحله 2: ساختار فایل‌ها**

```
lib/
├── services/
│   ├── web3_service.dart          ← اتصال به blockchain
│   ├── contract_addresses.dart    ← آدرس contracts
│   └── wallet_service.dart        ← مدیریت wallet
├── models/
│   ├── token_model.dart           ← مدل توکن‌ها
│   ├── swap_model.dart            ← مدل معاملات
│   └── governance_model.dart      ← مدل حکمرانی
├── screens/
│   ├── swap_screen.dart           ← صفحه مبادله
│   ├── liquidity_screen.dart      ← صفحه نقدینگی
│   ├── governance_screen.dart     ← صفحه حکمرانی
│   └── portfolio_screen.dart      ← صفحه کیف پول
└── widgets/
    ├── token_selector.dart        ← انتخاب توکن
    ├── swap_button.dart           ← دکمه مبادله
    └── transaction_status.dart    ← وضعیت تراکنش
```

---

## 🚀 **مرحله 3: بعد از Deployment**

### 1. کپی آدرس‌ها از Remix
```javascript
// بعد از deploy هر contract در Remix:
// 1. آدرس را کپی کنید
// 2. در contract_addresses.dart جایگزین کنید

// مثال:
static const String LAXCE_TOKEN = "0x1a2b3c4d5e6f7890..."; // آدرس واقعی
```

### 2. دانلود ABI Files
```javascript
// در Remix:
// 1. Solidity Compiler → Artifacts
// 2. contracts/YourContract.sol/YourContract.json
// 3. کپی ABI section
// 4. ذخیره در assets/contracts/
```

### 3. تنظیم assets در pubspec.yaml
```yaml
flutter:
  assets:
    - assets/contracts/
    - assets/images/
```

---

## 💻 **مرحله 4: پیاده‌سازی UI**

### Swap Screen نمونه:
```dart
class SwapScreen extends StatefulWidget {
  @override
  _SwapScreenState createState() => _SwapScreenState();
}

class _SwapScreenState extends State<SwapScreen> {
  final Web3Service _web3Service = Web3Service();
  
  String? selectedTokenIn;
  String? selectedTokenOut;
  TextEditingController amountController = TextEditingController();
  
  BigInt? swapQuote;
  bool isLoading = false;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('LAXCE Swap')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // Token Input
            _buildTokenSelector(
              label: 'From',
              selectedToken: selectedTokenIn,
              onChanged: (token) {
                setState(() {
                  selectedTokenIn = token;
                });
                _getSwapQuote();
              },
            ),
            
            // Amount Input
            TextField(
              controller: amountController,
              decoration: InputDecoration(
                labelText: 'Amount',
                suffixText: selectedTokenIn ?? '',
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) => _getSwapQuote(),
            ),
            
            // Swap Icon
            IconButton(
              icon: Icon(Icons.swap_vert),
              onPressed: _swapTokens,
            ),
            
            // Token Output
            _buildTokenSelector(
              label: 'To',
              selectedToken: selectedTokenOut,
              onChanged: (token) {
                setState(() {
                  selectedTokenOut = token;
                });
                _getSwapQuote();
              },
            ),
            
            // Quote Display
            if (swapQuote != null)
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'You will receive: ${_formatAmount(swapQuote!)} $selectedTokenOut',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            
            SizedBox(height: 20),
            
            // Swap Button
            ElevatedButton(
              onPressed: isLoading ? null : _performSwap,
              child: isLoading 
                ? CircularProgressIndicator(color: Colors.white)
                : Text('Swap'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // دریافت Quote
  Future<void> _getSwapQuote() async {
    if (selectedTokenIn == null || 
        selectedTokenOut == null || 
        amountController.text.isEmpty) return;
    
    try {
      final amountIn = BigInt.parse(amountController.text);
      final quote = await _web3Service.getSwapQuote(
        _getTokenAddress(selectedTokenIn!),
        _getTokenAddress(selectedTokenOut!),
        amountIn,
      );
      
      setState(() {
        swapQuote = quote;
      });
    } catch (e) {
      _showError('خطا در دریافت قیمت: $e');
    }
  }
  
  // انجام Swap
  Future<void> _performSwap() async {
    if (swapQuote == null) return;
    
    setState(() { isLoading = true; });
    
    try {
      final amountIn = BigInt.parse(amountController.text);
      final amountOutMin = swapQuote! * BigInt.from(995) ~/ BigInt.from(1000); // 0.5% slippage
      final deadline = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1800; // 30 min
      
      final txHash = await _web3Service.performSwap(
        _getTokenAddress(selectedTokenIn!),
        _getTokenAddress(selectedTokenOut!),
        amountIn,
        amountOutMin,
        deadline,
      );
      
      _showSuccess('تراکنش ارسال شد: $txHash');
      
      // گوش دادن به وضعیت تراکنش
      _waitForTransaction(txHash);
      
    } catch (e) {
      _showError('خطا در انجام مبادله: $e');
    }
    
    setState(() { isLoading = false; });
  }
  
  // انتظار برای تایید تراکنش
  Future<void> _waitForTransaction(String txHash) async {
    TransactionReceipt? receipt;
    int attempts = 0;
    
    while (receipt == null && attempts < 60) { // 5 دقیقه انتظار
      await Future.delayed(Duration(seconds: 5));
      receipt = await _web3Service.getTransactionReceipt(txHash);
      attempts++;
    }
    
    if (receipt != null) {
      if (receipt.status!) {
        _showSuccess('مبادله با موفقیت انجام شد!');
      } else {
        _showError('تراکنش شکست خورد');
      }
    } else {
      _showError('تایم‌اوت در انتظار تراکنش');
    }
  }
  
  // Helper Functions
  Widget _buildTokenSelector({
    required String label,
    required String? selectedToken,
    required Function(String) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(labelText: label),
      value: selectedToken,
      items: ['ETH', 'USDC', 'USDT', 'LAXCE'].map((token) {
        return DropdownMenuItem(
          value: token,
          child: Text(token),
        );
      }).toList(),
      onChanged: (value) => onChanged(value!),
    );
  }
  
  String _getTokenAddress(String tokenSymbol) {
    switch (tokenSymbol) {
      case 'ETH': return ContractAddresses.WETH;
      case 'USDC': return ContractAddresses.USDC;
      case 'USDT': return ContractAddresses.USDT;
      case 'LAXCE': return ContractAddresses.LAXCE_TOKEN;
      default: return ContractAddresses.WETH;
    }
  }
  
  String _formatAmount(BigInt amount) {
    return (amount / BigInt.from(10).pow(18)).toString();
  }
  
  void _swapTokens() {
    setState(() {
      final temp = selectedTokenIn;
      selectedTokenIn = selectedTokenOut;
      selectedTokenOut = temp;
    });
    _getSwapQuote();
  }
  
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
```

---

## 🔗 **مرحله 5: Event Listening**

### گوش دادن به رویدادهای Contract:
```dart
class TransactionListener {
  final Web3Service _web3Service = Web3Service();
  
  void startListening() {
    // گوش دادن به Swap events
    _web3Service.listenToSwapEvents().listen((event) {
      print('New swap: ${event.data}');
      // Update UI
      _updateSwapHistory(event);
    });
    
    // گوش دادن به Token Lock events
    _web3Service.listenToLockEvents().listen((event) {
      print('Tokens locked: ${event.data}');
      // Update portfolio
      _updatePortfolio(event);
    });
  }
}
```

---

## ⚡ **مرحله 6: State Management**

### با Provider:
```dart
class DexProvider extends ChangeNotifier {
  final Web3Service _web3Service = Web3Service();
  
  BigInt? _laxceBalance;
  List<SwapTransaction> _swapHistory = [];
  
  BigInt? get laxceBalance => _laxceBalance;
  List<SwapTransaction> get swapHistory => _swapHistory;
  
  Future<void> loadUserData(String userAddress) async {
    _laxceBalance = await _web3Service.getLaxceBalance(userAddress);
    notifyListeners();
  }
  
  Future<void> performSwap(SwapParams params) async {
    // انجام swap
    final txHash = await _web3Service.performSwap(/* params */);
    
    // اضافه کردن به تاریخچه
    _swapHistory.add(SwapTransaction(
      hash: txHash,
      timestamp: DateTime.now(),
      // ...
    ));
    
    notifyListeners();
  }
}
```

---

## 🎯 **خلاصه مراحل:**

1. **Deploy Contracts** در Remix ✅
2. **کپی آدرس‌ها** در `contract_addresses.dart` ⚠️
3. **دانلود ABI files** و ذخیره در assets ⚠️
4. **پیاده‌سازی UI** با استفاده از Web3Service ⚠️
5. **تست** روی testnet ⚠️
6. **Deploy نهایی** روی mainnet ⚠️

### ✅ **بعد از انجام این مراحل:**
- اپ شما به طور کامل به smart contracts متصل می‌شود
- کاربران می‌توانند swap، stake، vote و سایر عملیات را انجام دهند
- تمام قابلیت‌های DEX در دسترس خواهد بود

**آیا مایلید مرحله deployment را در Remix شروع کنیم؟** 🚀