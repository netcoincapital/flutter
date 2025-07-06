import 'package:flutter/material.dart';
import 'screens/import_create_screen.dart';
import 'screens/import_wallet_screen.dart';
import 'screens/create_new_wallet_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/add_token_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/qr_scanner_screen.dart';

void main() {
  runApp(const MyApp());
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
    );
  }
}
