import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/scheduler.dart';
import 'package:easy_localization/easy_localization.dart';

import 'services/service_provider.dart';
import 'services/device_registration_manager.dart';
import 'services/network_monitor.dart';
import 'services/transaction_notification_receiver.dart';
import 'services/notification_helper.dart';
import 'services/secure_storage.dart';
import 'services/wallet_state_manager.dart';
import 'services/language_manager.dart';
import 'providers/history_provider.dart';
import 'providers/network_provider.dart';
import 'providers/app_provider.dart';
import 'providers/price_provider.dart';
import 'screens/import_create_screen.dart';
import 'screens/import_wallet_screen.dart';
import 'screens/create_new_wallet_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/add_token_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/history_screen.dart';
import 'screens/preferences_screen.dart';
import 'screens/fiat_currencies_screen.dart';
import 'screens/languages_screen.dart';
import 'screens/notification_management_screen.dart';
import 'screens/receive_screen.dart';
import 'screens/send_screen.dart';
import 'screens/send_detail_screen.dart';
import 'screens/transaction_detail_screen.dart';
import 'screens/dex_screen.dart';
import 'screens/passcode_screen.dart';
import 'layout/network_overlay.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/wallets_screen.dart';
import 'services/passcode_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // 🚀 Initialize critical services in parallel for faster startup
  await Future.wait([
    // Initialize ServiceProvider (synchronous - wrapped in Future)
    Future.sync(() => ServiceProvider.instance.initialize()),
    // Initialize NotificationHelper
    NotificationHelper.initialize(),
  ]);
  
  print('🚀 All critical services initialized in parallel');
  
  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en'),
        Locale('fa'),
        Locale('tr'),
        Locale('ar'),
      ],
      path: 'assets/locales',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'), // اضافه کردن startLocale
      child: const MyApp(),
    ),
  );
}

/// Initial device registration (fallback method)
Future<void> _initializeDeviceRegistration() async {
  try {
    // Get user and wallet information from SecureStorage
    final userId = await _getUserId();
    final walletId = await _getWalletId();
    
    if (userId != null && walletId != null) {
      print('📱 Initializing device registration...');
      
      // Check and register device
      final success = await DeviceRegistrationManager.instance.checkAndRegisterDevice(
        userId: userId,
        walletId: walletId,
      );
      
      if (success) {
        print('✅ Device registration initialized successfully');
      } else {
        print('❌ Device registration initialization failed');
      }
    } else {
      print('⚠️ User ID or Wallet ID not available for device registration');
    }
  } catch (e) {
    print('❌ Error initializing device registration: $e');
  }
}

/// Device registration with provided userId (optimized)
Future<void> _initializeDeviceRegistrationWithData(String userId) async {
  try {
    final walletId = await _getWalletId();
    
    if (walletId != null) {
      print('📱 Initializing device registration with user data...');
      
      // Check and register device
      final success = await DeviceRegistrationManager.instance.checkAndRegisterDevice(
        userId: userId,
        walletId: walletId,
      );
      
      if (success) {
        print('✅ Device registration completed with user data');
      } else {
        print('❌ Device registration failed with user data');
      }
    } else {
      print('⚠️ Wallet ID not available for device registration');
    }
  } catch (e) {
    print('❌ Error in device registration with user data: $e');
  }
}

/// Get User ID from SecureStorage
Future<String?> _getUserId() async {
  try {
    return await SecureStorage.getUserId();
  } catch (e) {
    print('❌ Error getting User ID: $e');
    return null;
  }
}

/// Get Wallet ID from SecureStorage
Future<String?> _getWalletId() async {
  try {
    return await SecureStorage.getWalletId();
  } catch (e) {
    print('❌ Error getting Wallet ID: $e');
    return null;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  String? _userId;
  bool _isLoading = true;
  String _initialRoute = '/import-create';
  bool _hasPasscode = false;
  DateTime? _lastBackgroundTime;
  int _autoLockTimeoutMillis = 0; // 0 means Immediate
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 🚀 Run initialization tasks in parallel for faster startup
    Future.wait([
      _initializeApp(),
      _loadAutoLockTimeout(),
    ]).then((_) {
      print('🚀 All initialization tasks completed in parallel');
    }).catchError((e) {
      print('❌ Error in parallel initialization: $e');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Listen to app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) {
      // App goes to background
      final now = DateTime.now();
      _lastBackgroundTime = now;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_background_time', now.millisecondsSinceEpoch);
    } else if (state == AppLifecycleState.resumed) {
      // App comes to foreground
      final prefs = await SharedPreferences.getInstance();
      final lastMillis = prefs.getInt('last_background_time') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = now - lastMillis;
      if (_autoLockTimeoutMillis > 0 && elapsed > _autoLockTimeoutMillis) {
        // Show passcode screen if timeout exceeded
        SchedulerBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/enter-passcode',
            (route) => false,
          );
        });
      } else if (_autoLockTimeoutMillis == 0 && lastMillis > 0) {
        // Immediate lock
        SchedulerBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/enter-passcode',
            (route) => false,
          );
        });
      }
    }
  }

  Future<void> _loadAutoLockTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    // Default: 0 (Immediate), can be set elsewhere in the app
    _autoLockTimeoutMillis = prefs.getInt('auto_lock_timeout_millis') ?? 0;
  }

  Future<void> _clearSecureStorageIfPrefsEmpty() async {
    try {
      const storage = FlutterSecureStorage();
      final secureKeys = await storage.readAll();
      
      // Check if passcode exists in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final passcodeHash = prefs.getString('passcode_hash');
      
      // فقط اگر واقعاً هیچ داده‌ای در SecureStorage نیست AND هیچ پسکدی وجود ندارد، fresh install است
      if (secureKeys.isEmpty && passcodeHash == null) {
        print('🆕 True fresh install detected - no secure data and no passcode found');
        await prefs.clear(); // Clear any leftover SharedPreferences
      } else {
        print('📱 Existing user detected - ${secureKeys.length} secure keys found, passcode exists: ${passcodeHash != null}');
        // Don't clear anything - user has existing data
      }
    } catch (e) {
      print('❌ Error checking install state: $e');
      // Don't clear anything on error to be safe
    }
  }

  /// Initial app setup - optimized for parallel processing
  Future<void> _initializeApp() async {
    try {
      print('🔍 Determining initial screen...');
      
      // 🎯 Step 1: Critical route determination (must be first)
      String initialRoute;
      
      // بررسی وجود کیف پول
      final hasWallet = await WalletStateManager.instance.hasWallet();
      final hasPasscode = await WalletStateManager.instance.hasPasscode();
      
      print('🔍 Wallet check: hasWallet=$hasWallet, hasPasscode=$hasPasscode');
      
      if (hasWallet && hasPasscode) {
        // اگر کیف پول و پسکد وجود دارد، همیشه به enter-passcode برود
        initialRoute = '/enter-passcode';
        print('🎯 User has wallet and passcode -> going to enter-passcode');
      } else {
        // در غیر این صورت از WalletStateManager استفاده کن
        initialRoute = await WalletStateManager.instance.getInitialScreen();
        print('🎯 Using WalletStateManager route: $initialRoute');
      }
      
      print('🎯 Final initial route determined: $initialRoute');
      
      // 🚀 Step 2: Run all non-critical initializations in parallel
      final parallelFutures = await Future.wait([
        // Language initialization
        LanguageManager.initializeLanguage(context),
        // Get UserId from SecureStorage
        _getUserId(),
        // Test server connection
        _testServerConnection(),
        // Show network status
        ServiceProvider.instance.showNetworkStatus(),
        // Debug: Check passcode status
        _checkPasscodeDebug(),
      ]);
      
      // Extract results from parallel operations
      _userId = parallelFutures[1] as String?;
      
      // 🎯 Step 3: Start transaction notification listener (after UI)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        TransactionNotificationReceiver.instance.startListening(context);
      });
      
      // 🎯 Step 4: Start device registration with available data (non-blocking)
      if (_userId != null) {
        _initializeDeviceRegistrationWithData(_userId!).then((_) {
          print('📱 Device registration completed with user data');
        }).catchError((e) {
          print('❌ Device registration failed with user data: $e');
        });
      }
      
      print('🚀 All app initialization completed in parallel');
      
      setState(() {
        _initialRoute = initialRoute;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error during initialization: $e');
      if (mounted) {
        setState(() {
          _initialRoute = '/import-create';
          _isLoading = false;
        });
      }
    }
  }
  
  /// Helper method for server connection testing
  Future<bool> _testServerConnection() async {
    print('🌐 Testing server connection...');
    final isConnected = await ServiceProvider.instance.testServerConnection('coinceeper.com');
    if (isConnected) {
      print('✅ Server connection successful');
    } else {
      print('⚠️ Server connection failed - app will work with limited functionality');
    }
    return isConnected;
  }
  
  /// Helper method for passcode debugging
  Future<void> _checkPasscodeDebug() async {
    try {
      // ✅ Debug: Check passcode status directly
      final passcodeIsSet = await PasscodeManager.isPasscodeSet();
      print('🔑 DEBUG: PasscodeManager.isPasscodeSet() = $passcodeIsSet');
      
      // ✅ Debug: Check SharedPreferences directly
      final prefs = await SharedPreferences.getInstance();
      final passcodeHash = prefs.getString('passcode_hash');
      print('🔑 DEBUG: SharedPreferences passcode_hash = ${passcodeHash != null ? "EXISTS" : "NULL"}');
    } catch (e) {
      print('❌ Error checking passcode debug: $e');
    }
  }



  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MaterialApp(
        // ✅ اضافه کردن localization برای loading screen
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        home: Scaffold(
          body: Container(), // Remove loading spinner and text
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) {
            final appProvider = AppProvider();
            // Initialize AppProvider after the widget tree is built
            WidgetsBinding.instance.addPostFrameCallback((_) {
              appProvider.initialize();
            });
            return appProvider;
          },
        ),
        ChangeNotifierProvider(
          create: (context) => HistoryProvider(),
        ),
        ChangeNotifierProvider(
          create: (context) => NetworkProvider(),
        ),
        ChangeNotifierProvider(
          create: (context) {
            final priceProvider = PriceProvider();
            // Initialize PriceProvider after the widget tree is built
            WidgetsBinding.instance.addPostFrameCallback((_) {
              priceProvider.loadSelectedCurrency();
            });
            return priceProvider;
          },
        ),
        ChangeNotifierProvider.value(
          value: ServiceProvider.instance.networkManager,
        ),
      ],
      child: MaterialApp(
        title: 'laxce',
        // ✅ اضافه کردن تنظیمات localization
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0BAB9B)),
          useMaterial3: true,
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            },
          ),
        ),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
            child: NetworkOverlay(child: child ?? Container()),
          );
        },
        initialRoute: _initialRoute,
        routes: {
          '/import-create': (context) => const ImportCreateScreen(),
          '/import-wallet': (context) {
            final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
            return ImportWalletScreen(qrArguments: args);
          },
          '/create-new-wallet': (context) => const CreateNewWalletScreen(),
          '/passcode-setup': (context) => const PasscodeScreen(
            title: 'Choose Passcode',
          ),
          '/enter-passcode': (context) => PasscodeScreen(
            title: 'Enter Passcode',
            onSuccess: () {
              // Use smoother navigation to prevent black screen
              Navigator.pushReplacementNamed(context, '/home');
            },
          ),
          '/backup': (context) {
            final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
            return BackupScreen(
              walletName: args?['walletName'] ?? 'Unknown Wallet',
              userID: args?['userID'],
              walletID: args?['walletID'],
              mnemonic: args?['mnemonic'],
            );
          },
          '/home': (context) => const HomeScreen(),
          '/wallets': (context) => const WalletsScreen(),
          '/add-token': (context) => const AddTokenScreen(),
          '/settings': (context) => const SettingsScreen(),
          '/qr-scanner': (context) {
            final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
            return QrScannerScreen(
              returnScreen: args?['returnScreen'] ?? 'home',
            );
          },
          '/history': (context) => const HistoryScreen(),
          '/preferences': (context) => const PreferencesScreen(),
          '/fiat-currencies': (context) => const FiatCurrenciesScreen(),
          '/languages': (context) => const LanguagesScreen(),
          '/notificationmanagement': (context) => const NotificationManagementScreen(),
          '/receive': (context) => const ReceiveScreen(),
          '/send': (context) {
            final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
            return SendScreen(qrArguments: args);
          },
          '/dex': (context) => const DexScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name != null && settings.name!.startsWith('/backup')) {
            final uri = Uri.parse(settings.name!);
            final walletName = uri.queryParameters['walletName'] ?? '';
            return MaterialPageRoute(
              builder: (context) => BackupScreen(walletName: walletName),
              settings: settings,
            );
          }
          if (settings.name != null && settings.name!.startsWith('/send_detail/')) {
            final tokenJson = settings.name!.substring('/send_detail/'.length);
            return MaterialPageRoute(
              builder: (context) => SendDetailScreen(tokenJson: tokenJson),
              settings: settings,
            );
          }
          if (settings.name != null && settings.name!.startsWith('/transaction_detail/')) {
            final path = settings.name!.substring('/transaction_detail/'.length);
            final parts = path.split('/');
            if (parts.length >= 8) {
              final amount = Uri.decodeComponent(parts[0]);
              final symbol = Uri.decodeComponent(parts[1]);
              final fiat = Uri.decodeComponent(parts[2]);
              final date = Uri.decodeComponent(parts[3]);
              final status = Uri.decodeComponent(parts[4]);
              final sender = Uri.decodeComponent(parts[5]);
              final networkFee = Uri.decodeComponent(parts[6]);
              final hash = Uri.decodeComponent(parts[7]);
              
              return MaterialPageRoute(
                builder: (context) => TransactionDetailScreen(
                  amount: amount,
                  symbol: symbol,
                  fiat: fiat,
                  date: date,
                  status: status,
                  sender: sender,
                  networkFee: networkFee,
                  hash: hash,
                ),
                settings: settings,
              );
            }
          }
          return null;
        },
      ),
    );
  }
}
