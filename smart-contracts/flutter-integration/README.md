# Flutter Integration - اتصال به اپلیکیشن Flutter

## مقدمه

این بخش نحوه اتصال smart contracts به صفحه `dex_screen.dart` در اپلیکیشن Flutter را شرح می‌دهد.

## فایل‌های مورد نیاز

### 1. Contract Service
- `web3_service.dart` - سرویس اتصال به blockchain
- `dex_contract_service.dart` - سرویس تعامل با DEX contracts
- `wallet_service.dart` - مدیریت wallet

### 2. Models
- `swap_model.dart` - مدل برای swap operations
- `pool_model.dart` - مدل برای pool data
- `token_model.dart` - مدل برای token information

### 3. Providers
- `dex_provider.dart` - Provider برای مدیریت state
- `web3_provider.dart` - Provider برای اتصال Web3

## نصب وابستگی‌ها

```yaml
# pubspec.yaml
dependencies:
  web3dart: ^2.6.1
  http: ^0.13.5
  flutter_dotenv: ^5.0.2
  provider: ^6.0.5
```

## پیکربندی

### 1. تنظیمات محیطی

```env
# .env
ETHEREUM_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
FACTORY_CONTRACT_ADDRESS=0x...
ROUTER_CONTRACT_ADDRESS=0x...
PRIVATE_KEY=your_private_key
```

### 2. کانفیگ شبکه

```dart
// config/network_config.dart
class NetworkConfig {
  static const Map<String, NetworkInfo> networks = {
    'ethereum': NetworkInfo(
      chainId: 1,
      rpcUrl: 'https://mainnet.infura.io/v3/YOUR_KEY',
      name: 'Ethereum Mainnet',
    ),
    'sepolia': NetworkInfo(
      chainId: 11155111,
      rpcUrl: 'https://sepolia.infura.io/v3/YOUR_KEY',
      name: 'Sepolia Testnet',
    ),
  };
}
```

## تعامل با Smart Contracts

### 1. DEX Service

```dart
class DexContractService {
  final Web3Client _client;
  final DeployedContract _factoryContract;
  final DeployedContract _routerContract;

  Future<SwapQuote> getSwapQuote(
    String tokenIn,
    String tokenOut,
    BigInt amountIn,
  ) async {
    // فراخوانی contract برای محاسبه quote
  }

  Future<String> executeSwap(SwapParams params) async {
    // اجرای تراکنش swap
  }

  Future<List<Pool>> getPools() async {
    // دریافت لیست pools
  }
}
```

### 2. اتصال به DexScreen

```dart
// lib/screens/dex_screen.dart
class _DexScreenState extends State<DexScreen> {
  late DexContractService _dexService;
  late DexProvider _dexProvider;

  @override
  void initState() {
    super.initState();
    _dexService = DexContractService();
    _dexProvider = Provider.of<DexProvider>(context, listen: false);
    _loadPoolData();
  }

  Future<void> _loadPoolData() async {
    final pools = await _dexService.getPools();
    _dexProvider.updatePools(pools);
  }

  Future<void> _executeSwap() async {
    try {
      final txHash = await _dexService.executeSwap(SwapParams(
        tokenIn: fromToken,
        tokenOut: toToken,
        amountIn: BigInt.parse(fromAmount),
        slippage: 0.5,
      ));
      
      // نمایش پیام موفقیت
      _showSuccessDialog(txHash);
    } catch (error) {
      // نمایش خطا
      _showErrorDialog(error.toString());
    }
  }
}
```

## Real-time Updates

### 1. WebSocket Connection

```dart
class Web3EventListener {
  late WebSocketChannel _channel;

  void listenToSwapEvents() {
    _channel.stream.listen((event) {
      final swapEvent = SwapEvent.fromJson(event);
      // بروزرسانی UI
    });
  }
}
```

### 2. Event Handling

```dart
class DexProvider extends ChangeNotifier {
  List<SwapEvent> _recentSwaps = [];
  
  void onNewSwap(SwapEvent swap) {
    _recentSwaps.insert(0, swap);
    notifyListeners();
  }
}
```

## Error Handling

```dart
class DexException implements Exception {
  final String message;
  final String? code;
  
  DexException(this.message, [this.code]);
}

// در DexScreen
void _handleError(dynamic error) {
  if (error is DexException) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.message)),
    );
  }
}
```

## Testing

```dart
// test/dex_service_test.dart
void main() {
  group('DexContractService', () {
    test('should get swap quote', () async {
      final service = DexContractService(mockClient);
      final quote = await service.getSwapQuote(
        'USDT', 'ETH', BigInt.from(1000),
      );
      expect(quote.amountOut, greaterThan(BigInt.zero));
    });
  });
}
```

## Production Deployment

### 1. Contract Addresses

```dart
// config/contract_addresses.dart
class ContractAddresses {
  static const Map<String, Map<String, String>> addresses = {
    'mainnet': {
      'factory': '0x...',
      'router': '0x...',
    },
    'sepolia': {
      'factory': '0x...',
      'router': '0x...',
    },
  };
}
```

### 2. Security Considerations

- استفاده از HTTPS برای RPC calls
- Validation ورودی‌های کاربر
- Rate limiting برای API calls
- Secure storage برای private keys 