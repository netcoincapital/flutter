import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/web3_provider.dart';
import '../services/web3_service.dart';
import '../services/dex_service.dart';
import '../services/wallet_connect_service.dart';

class Web3TestScreen extends StatefulWidget {
  const Web3TestScreen({super.key});

  @override
  State<Web3TestScreen> createState() => _Web3TestScreenState();
}

class _Web3TestScreenState extends State<Web3TestScreen> {
  final TextEditingController _amountController = TextEditingController();
  String _result = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      // مقداردهی اولیه سرویس‌ها
      await Web3Service.instance.initialize();
      DexService.instance.setContractAddresses(
        laxceToken: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
        poolFactory: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
        router: "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9",
        quoter: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
      );
      
      // اتصال به test wallet
      await Web3Service.instance.connectTestWallet();
      
      setState(() {
        _result = '✅ Services initialized successfully';
      });
    } catch (e) {
      setState(() {
        _result = '❌ Error: $e';
      });
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isLoading = true;
      _result = 'Testing connection...';
    });

    try {
      final web3Provider = Provider.of<Web3Provider>(context, listen: false);
      
      // تست اتصال
      if (!Web3Service.instance.isWalletConnected) {
        await Web3Service.instance.connectTestWallet();
      }
      
      // دریافت آدرس
      final address = Web3Service.instance.walletAddress;
      
      // دریافت موجودی ETH
      final ethBalance = await Web3Service.instance.getNativeBalance();
      
      setState(() {
        _result = '''
✅ Connection Test Successful!
📍 Address: $address
💰 ETH Balance: ${ethBalance.toStringAsFixed(4)} ETH
🔗 Network: Hardhat Local (31337)
        ''';
      });
    } catch (e) {
      setState(() {
        _result = '❌ Connection failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testTokenBalance() async {
    setState(() {
      _isLoading = true;
      _result = 'Checking LAXCE balance...';
    });

    try {
      final address = Web3Service.instance.walletAddress;
      if (address == null) {
        throw Exception('Wallet not connected');
      }

      // دریافت موجودی LAXCE
      final balance = await DexService.instance.getLaxceBalance();
      
      setState(() {
        _result = '''
🪙 LAXCE Token Balance
📍 Address: $address
💰 Balance: ${balance.toStringAsFixed(2)} LAXCE
📍 Contract: 0x5FbDB2...0aa3
        ''';
      });
    } catch (e) {
      setState(() {
        _result = '❌ Token balance error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testSwapQuote() async {
    if (_amountController.text.isEmpty) {
      setState(() {
        _result = '❌ Please enter amount';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _result = 'Getting swap quote...';
    });

    try {
      final amount = double.parse(_amountController.text);
      
      // فرض: swap از LAXCE به ETH (mock)
      final tokenIn = "0x5FbDB2315678afecb367f032d93F642f64180aa3"; // LAXCE
      final tokenOut = "0x0000000000000000000000000000000000000000"; // ETH (mock)
      
      final quote = await DexService.instance.getSwapQuote(
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        amountIn: amount,
      );
      
      setState(() {
        _result = '''
💱 Swap Quote
📥 Input: ${amount.toStringAsFixed(2)} LAXCE
📤 Output: ${quote.amountOut.toStringAsFixed(6)} ETH
💹 Price Impact: ${quote.priceImpact.toStringAsFixed(2)}%
        ''';
      });
    } catch (e) {
      setState(() {
        _result = '❌ Quote error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testMintTokens() async {
    if (_amountController.text.isEmpty) {
      setState(() {
        _result = '❌ Please enter amount';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _result = 'Minting LAXCE tokens...';
    });

    try {
      final amount = double.parse(_amountController.text);
      final address = Web3Service.instance.walletAddress;
      
      if (address == null) {
        throw Exception('Wallet not connected');
      }

      // برای تست، از مین کردن token استفاده می‌کنیم
      // در واقع این کار باید توسط owner contract انجام شود
      setState(() {
        _result = '''
🎯 Mock Mint Successful!
📍 Address: $address
🪙 Minted: ${amount.toStringAsFixed(2)} LAXCE
⚠️ Note: This is a simulation for testing
        ''';
      });
    } catch (e) {
      setState(() {
        _result = '❌ Mint error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web3 Integration Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Smart Contract Addresses',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('LAXCE Token: 0x5FbDB2...0aa3'),
                    Text('Router: 0xCf7Ed3...0Fc9'),
                    Text('Quoter: 0x9fE467...6e0'),
                    const SizedBox(height: 8),
                    Text(
                      'Network: Hardhat Local (31337)',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Test Actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testConnection,
                    icon: const Icon(Icons.link),
                    label: const Text('Test Connection'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testTokenBalance,
                    icon: const Icon(Icons.account_balance_wallet),
                    label: const Text('Check Balance'),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Amount Input
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount (LAXCE)',
                border: OutlineInputBorder(),
                hintText: 'Enter amount for testing',
              ),
              keyboardType: TextInputType.number,
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testSwapQuote,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Get Quote'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testMintTokens,
                    icon: const Icon(Icons.add_circle),
                    label: const Text('Mock Mint'),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Results
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Test Results',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          if (_isLoading)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            _result.isEmpty ? 'Tap a button to start testing...' : _result,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              color: _result.startsWith('❌') ? Colors.red : 
                                     _result.startsWith('✅') ? Colors.green : 
                                     null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Status Info
            Consumer<Web3Provider>(
              builder: (context, web3Provider, child) {
                return Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Connection Status:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Wallet: ${web3Provider.isConnected ? "Connected" : "Disconnected"}'),
                        if (web3Provider.isConnected)
                          Text('Address: ${web3Provider.walletAddress?.substring(0, 10)}...'),
                        Text('Loading: ${web3Provider.isLoading ? "Yes" : "No"}'),
                        if (web3Provider.error != null)
                          Text('Error: ${web3Provider.error}', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
} 