import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
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
import 'layout/network_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('fa'), Locale('tr')],
      path: 'assets/locales',
      fallbackLocale: const Locale('en'),
      saveLocale: true,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'laxce',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0BAB9B)),
        useMaterial3: true,
      ),
      home: const ImportCreateScreen(),
      routes: {
        '/import-wallet': (context) => const ImportWalletScreen(),
        '/create-new-wallet': (context) => const CreateNewWalletScreen(),
        '/home': (context) => const HomeScreen(),
        '/add-token': (context) => const AddTokenScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/qr-scanner': (context) => const QrScannerScreen(),
        '/history': (context) => const HistoryScreen(),
        '/preferences': (context) => const PreferencesScreen(),
        '/fiat-currencies': (context) => const FiatCurrenciesScreen(),
        '/languages': (context) => const LanguagesScreen(),
        '/notificationmanagement': (context) => const NotificationManagementScreen(),
        '/receive': (context) => const ReceiveScreen(),
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
        return null;
      },
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) => NetworkOverlay(child: child ?? Container()),
    );
  }
}
