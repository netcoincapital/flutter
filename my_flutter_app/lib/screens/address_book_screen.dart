import 'package:flutter/material.dart';
import 'add_address_screen.dart';
import 'edit_address_book_screen.dart';
import '../layout/bottom_menu_with_siri.dart';

class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({Key? key}) : super(key: key);

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  List<Map<String, String>> wallets = [];

  void _addWallet(Map<String, String> wallet) {
    setState(() {
      wallets.add(wallet);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Address Book', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: Image.asset('assets/images/plus.png', width: 18, height: 18, color: Color(0x99757575)),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddAddressScreen()),
              );
              if (result != null && result is Map<String, String>) {
                _addWallet(result);
              }
            },
          ),
        ],
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: wallets.isEmpty
            ? _EmptyAddressBook(onAdd: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddAddressScreen()),
                );
                if (result != null && result is Map<String, String>) {
                  _addWallet(result);
                }
              })
            : ListView.separated(
                itemCount: wallets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final wallet = wallets[index];
                  return _WalletItem(
                    walletName: wallet['name'] ?? '',
                    walletAddress: wallet['address'] ?? '',
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditAddressBookScreen(
                            walletName: wallet['name'] ?? '',
                            walletAddress: wallet['address'] ?? '',
                          ),
                        ),
                      );
                      if (result != null && result is Map<String, dynamic>) {
                        if (result['deleted'] == true) {
                          setState(() {
                            wallets.removeAt(index);
                          });
                        } else {
                          setState(() {
                            wallets[index] = {
                              'name': result['name'],
                              'address': result['address'],
                            };
                          });
                        }
                      }
                    },
                  );
                },
              ),
      ),
      bottomNavigationBar: const BottomMenuWithSiri(),
    );
  }
}

class _EmptyAddressBook extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyAddressBook({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 2),
        Image.asset('assets/images/addaddress.png', width: 200, height: 200),
        const SizedBox(height: 16),
        const Text(
          'Your contacts and their wallet address will appear here.',
          style: TextStyle(fontSize: 14, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16B369),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
              elevation: 0,
            ),
            child: const Text('Add wallet address', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 150),
      ],
    );
  }
}

class _WalletItem extends StatelessWidget {
  final String walletName;
  final String walletAddress;
  final VoidCallback onTap;
  const _WalletItem({required this.walletName, required this.walletAddress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF08C495), Color(0xFF39b6fb)]),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(walletName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(walletAddress, style: const TextStyle(fontSize: 14, color: Colors.white)),
                ],
              ),
            ),
            Image.asset('assets/images/rightarrow.png', width: 24, height: 24, color: Colors.white),
          ],
        ),
      ),
    );
  }
} 