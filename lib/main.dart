import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/scheduler.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'firebase_options.dart';

import 'services/service_provider.dart';
import 'services/device_registration_manager.dart';
import 'services/network_monitor.dart';
import 'services/transaction_notification_receiver.dart';
import 'services/notification_helper.dart';
import 'services/secure_storage.dart';
import 'services/wallet_state_manager.dart';
import 'services/language_manager.dart';
import 'services/security_settings_manager.dart';
import 'services/uninstall_data_manager.dart';
import 'services/firebase_messaging_service.dart';
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
import 'screens/security_screen.dart';
import 'layout/network_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/wallets_screen.dart';
import 'screens/debug_wallet_state_screen.dart';
import 'services/passcode_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // Initialize Firebase first - temporarily disabled
  try {
    // TODO: Add real GoogleService-Info.plist and enable Firebase
    // await Firebase.initializeApp(
    //   options: DefaultFirebaseOptions.currentPlatform,
    // );
    print('⚠️ Firebase temporarily disabled - need real GoogleService-Info.plist');
  } catch (e) {
    print('❌ Firebase initialization failed: $e');
  }

  // 🔍 iOS keychain orphaned data check disabled - was causing data loss
  // This was incorrectly clearing wallet data when app was killed from background
  // SharedPreferences being empty != fresh install
  print('📱 iOS: Keychain orphaned data check disabled to prevent data loss');

  // 🚀 Initialize critical services in parallel for faster startup
  await Future.wait([
    // Initialize ServiceProvider (synchronous - wrapped in Future)
    Future.sync(() => ServiceProvider.instance.initialize()),
    // Initialize NotificationHelper
    NotificationHelper.initialize(),
    // Initialize Firebase Messaging Service
    FirebaseMessagingService.instance.initialize(),
  ]);
  
  print('🚀 All critical services initialized in parallel');
  
  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en'),
        Locale('fa'),
        Locale('tr'),
        Locale('ar'),
        Locale('zh'),
        Locale('es'),
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
  bool _isInitialized = false;
  
  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 🚀 Initialize SecuritySettingsManager FIRST, then app
    _initializeSecurityManager().then((_) {
      print('🔒 SecuritySettingsManager initialized, now initializing app');
      return _initializeApp();
    }).then((_) {
      print('🚀 All initialization tasks completed in sequence');
    }).catchError((e) {
      print('❌ Error in initialization sequence: $e');
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
      
      // Save background time using SecuritySettingsManager
      await _securityManager.saveLastBackgroundTime();
      
      print('📱 App went to background at: $now');
    } else if (state == AppLifecycleState.resumed) {
      // App comes to foreground
      print('📱 App resumed from background');
      
      // 🔒 CRITICAL: Check if passcode is enabled and set
      final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
      final hasPasscode = await PasscodeManager.isPasscodeSet();
      
      if (!isPasscodeEnabled) {
        print('⚠️ SECURITY WARNING: Passcode disabled - crypto wallet unprotected!');
        return;
      }
      
      if (!hasPasscode) {
        print('⚠️ SECURITY WARNING: No passcode set - crypto wallet unprotected!');
        return;
      }
      
      // 🔒 PRIORITY 1: Check if app passcode should be shown  
      final shouldShowPasscode = await _securityManager.shouldShowPasscodeNow();
      
      if (shouldShowPasscode) {
        print('🔒 SECURITY: Auto-lock triggered - requiring passcode for crypto wallet access');
        SchedulerBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/enter-passcode',
            (route) => false,
          );
        });
      } else {
        print('🔓 SECURITY: Auto-lock not triggered - within configured time limit or disabled');
        
        // 🔄 IMPORTANT: If no lock required, reset activity timer for foreground event
        await _securityManager.resetActivityTimer();
      }
    }
  }

  Future<void> _initializeSecurityManager() async {
    try {
      // Initialize security settings with defaults
      await _securityManager.initialize();
      
      // Get summary after initialization
      final summary = await _securityManager.getSecuritySettingsSummary();
      print('🔒 Security settings initialized: ${summary['lockMethodText']} - ${summary['autoLockDurationText']}');
    } catch (e) {
      print('❌ Error initializing security manager: $e');
    }
  }

  Future<void> _clearSecureStorageIfPrefsEmpty() async {
    try {
      print('🔍 Starting fresh install check...');
      
      // استفاده از UninstallDataManager برای بررسی و پاکسازی داده‌های باقی‌مانده
      await UninstallDataManager.checkAndCleanupOnFreshInstall();
      
      // بررسی مجدد بعد از پاکسازی
      print('🔍 Verifying cleanup results...');
      final dataStatus = await UninstallDataManager.getDataStatus();
      print('📊 Data status after cleanup: $dataStatus');
      
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
      
      // بررسی وجود کیف پول و فعال بودن passcode
      final hasWallet = await WalletStateManager.instance.hasWallet();
      final hasValidWallet = await WalletStateManager.instance.hasValidWallet();
      final hasPasscode = await WalletStateManager.instance.hasPasscode();
      final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
      final isFreshInstall = await WalletStateManager.instance.isFreshInstall();
      
      // Debug iOS specific issues
      await _debugiOSKeychainAccess();
      
      print('🔍 === ENHANCED ROUTE DETERMINATION DEBUG ===');
      print('🔍 isFreshInstall: $isFreshInstall');
      print('🔍 hasWallet (simple): $hasWallet');
      print('🔍 hasValidWallet (detailed): $hasValidWallet');
      print('🔍 hasPasscode: $hasPasscode');
      print('🔍 isPasscodeEnabled: $isPasscodeEnabled');
      
      // Debug wallet list
      try {
        final wallets = await SecureStorage.instance.getWalletsList();
        print('🔍 Found ${wallets.length} wallets in list:');
        for (int i = 0; i < wallets.length; i++) {
          final wallet = wallets[i];
          final walletName = wallet["walletName"];
          final userId = wallet["userID"];
          print('🔍   Wallet $i: $walletName (userId: $userId)');
          
          // Check if mnemonic exists for this wallet
          if (walletName != null && userId != null) {
            try {
              final mnemonic = await SecureStorage.instance.getMnemonic(walletName, userId);
              print('🔍     Mnemonic: ${mnemonic != null ? "EXISTS" : "MISSING"}');
            } catch (e) {
              print('🔍     Mnemonic check error: $e');
            }
          }
        }
        
        // Debug all keys
        final allKeys = await SecureStorage.instance.getAllKeys();
        print('🔍 Total secure storage keys: ${allKeys.length}');
        print('🔍 Keys: ${allKeys.take(10).join(", ")}${allKeys.length > 10 ? "..." : ""}');
        
      } catch (e) {
        print('🔍 Error getting wallet list: $e');
      }
      
      // 🔒 CRITICAL SECURITY FIX: Enhanced crypto wallet routing logic with activity timer
      if (isFreshInstall) {
        initialRoute = '/import-create';
        print('🎯 🆕 Fresh install -> going to import-create');
      } else {
        // 🔒 PRIORITY 1: App Passcode Check (before any wallet checks)
        final shouldShowPasscode = await _securityManager.shouldShowPasscodeNow();
        
        if (shouldShowPasscode) {
          // 🔒 CRITICAL: Passcode required - don't check wallet until after passcode
          initialRoute = '/enter-passcode';
          print('🎯 🔒 PRIORITY 1: App passcode required -> REQUIRING passcode entry');
        } else if (hasValidWallet && hasPasscode && !isPasscodeEnabled) {
          // ⚠️ INSECURE BUT USER CHOICE: User explicitly disabled passcode
          initialRoute = '/home';
          print('🎯 ⚠️ INSECURE: User disabled passcode -> going to home (USER CHOICE)');
        } else if (hasValidWallet && !hasPasscode) {
          // 🔑 SETUP REQUIRED: Valid wallet but no passcode -> force setup
          initialRoute = '/passcode-setup';
          print('🎯 🔑 SETUP: Valid wallet but no passcode -> FORCING passcode setup');
        } else if (!hasValidWallet && hasPasscode) {
          // 🔄 INCONSISTENT STATE: Passcode exists but no wallet -> import-create
          initialRoute = '/import-create';
          print('🎯 🔄 INCONSISTENT: Passcode exists but no wallet -> going to import-create');
        } else {
          // 🔄 FALLBACK: Use WalletStateManager fallback
          initialRoute = await WalletStateManager.instance.getInitialScreen();
          print('🎯 🔄 FALLBACK: Using WalletStateManager route: $initialRoute');
          
          // اضافه کردن جزئیات بیشتر برای debugging
          if (!hasWallet) {
            print('🔍 → Reason: No wallet found (simple check)');
          }
          if (!hasValidWallet) {
            print('🔍 → Reason: No valid wallet found (detailed check)');
          }
          if (!hasPasscode) {
            print('🔍 → Reason: No passcode set');
          }
          if (hasPasscode && !isPasscodeEnabled) {
            print('🔍 → Reason: Passcode set but disabled');
          }
        }
      }
      
      print('🎯 Final initial route determined: $initialRoute');
      
      // 🚀 Step 2: Run critical initializations first, then non-critical ones
      // Critical operations first
      await LanguageManager.initializeLanguage(context);
      _userId = await _getUserId();
      
      // Non-critical operations in background (don't await)
      _testServerConnection().then((result) {
        print(result ? '✅ Server connection successful' : '⚠️ Server connection failed');
      });
      
      ServiceProvider.instance.showNetworkStatus().then((_) {
        print('✅ Network status shown');
      });
      
      _checkPasscodeDebug().then((_) {
        print('✅ Passcode debug completed');
      });
      
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
  
  /// Debug iOS keychain access issues
  Future<void> _debugiOSKeychainAccess() async {
    if (!Platform.isIOS) return;
    
    try {
      print('🍎 === iOS KEYCHAIN DEBUG ===');
      
      // Test direct keychain access
      const storage = FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock,
          synchronizable: false,
          accountName: 'com.coinceeper.app',
          groupId: null,
        ),
      );
      
      // Test write/read cycle
      final testKey = 'ios_keychain_test_${DateTime.now().millisecondsSinceEpoch}';
      final testValue = 'test_value_${DateTime.now().millisecondsSinceEpoch}';
      
      print('🍎 Testing keychain write...');
      await storage.write(key: testKey, value: testValue);
      
      print('🍎 Testing keychain read...');
      final readValue = await storage.read(key: testKey);
      
      if (readValue == testValue) {
        print('🍎 ✅ Keychain access working correctly');
      } else {
        print('🍎 ❌ Keychain access failed - read: $readValue, expected: $testValue');
      }
      
      // Clean up test key
      await storage.delete(key: testKey);
      
      // Test SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final prefsTestKey = 'ios_prefs_test_${DateTime.now().millisecondsSinceEpoch}';
      final prefsTestValue = 'prefs_test_value_${DateTime.now().millisecondsSinceEpoch}';
      
      print('🍎 Testing SharedPreferences write...');
      await prefs.setString(prefsTestKey, prefsTestValue);
      
      print('🍎 Testing SharedPreferences read...');
      final prefsReadValue = prefs.getString(prefsTestKey);
      
      if (prefsReadValue == prefsTestValue) {
        print('🍎 ✅ SharedPreferences access working correctly');
      } else {
        print('🍎 ❌ SharedPreferences access failed - read: $prefsReadValue, expected: $prefsTestValue');
      }
      
      // Clean up test key
      await prefs.remove(prefsTestKey);
      
      print('🍎 === END iOS KEYCHAIN DEBUG ===');
      
    } catch (e) {
      print('🍎 ❌ iOS keychain debug error: $e');
    }
  }

  /// Helper method for passcode debugging
  Future<void> _checkPasscodeDebug() async {
    try {
      // Debug: Enhanced passcode debugging for iOS issue
      print('🔍 === ENHANCED PASSCODE DEBUGGING ===');
      
      // Check both SharedPreferences and SecureStorage
      final prefs = await SharedPreferences.getInstance();
      final passcodeHash = prefs.getString('passcode_hash');
      final passcodeSalt = prefs.getString('passcode_salt');
      print('🔑 SharedPreferences passcode_hash = ${passcodeHash != null ? "EXISTS" : "NULL"}');
      print('🔑 SharedPreferences passcode_salt = ${passcodeSalt != null ? "EXISTS" : "NULL"}');
      
      // Check SecureStorage backup
      const secureStorage = FlutterSecureStorage();
      final secureHash = await secureStorage.read(key: 'passcode_hash_secure');
      final secureSalt = await secureStorage.read(key: 'passcode_salt_secure');
      print('🔑 SecureStorage passcode_hash_secure = ${secureHash != null ? "EXISTS" : "NULL"}');
      print('🔑 SecureStorage passcode_salt_secure = ${secureSalt != null ? "EXISTS" : "NULL"}');
      
      // Use PasscodeManager to check (this will use the new backup logic)
      final isPasscodeSetResult = await PasscodeManager.isPasscodeSet();
      print('🔑 PasscodeManager.isPasscodeSet() = $isPasscodeSetResult');
      
      print('🔍 === END PASSCODE DEBUGGING ===');
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
        title: 'coinceeper',
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
          '/security': (context) => const SecurityScreen(),
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
          '/debug-wallet-state': (context) => const DebugWalletStateScreen(),
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
          // Route برای دریافت جزئیات تراکنش از API با transactionId (از crypto_details_screen)
          if (settings.name == '/transaction_detail' && settings.arguments != null) {
            final args = settings.arguments as Map<String, dynamic>;
            final transactionId = args['transactionId'] as String?;
            
            return MaterialPageRoute(
              builder: (context) => TransactionDetailScreen(
                transactionId: transactionId, // دریافت جزئیات از API
              ),
              settings: settings,
            );
          }

          return null;
        },
      ),
    );
  }
}
