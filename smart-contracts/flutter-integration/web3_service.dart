// 🔗 Web3 Service - اتصال Flutter به Smart Contracts

import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart';
import 'contract_addresses.dart';

class Web3Service {
  late Web3Client _client;
  late EthPrivateKey _credentials;
  
  // Contract instances
  late DeployedContract _laxceToken;
  late DeployedContract _swapEngine;
  late DeployedContract _feeManager;
  late DeployedContract _governor;
  
  // Constructor
  Web3Service() {
    _initializeClient();
  }
  
  // 🚀 مقداردهی اولیه
  void _initializeClient() {
    _client = Web3Client(
      ContractAddresses.RPC_URL,
      Client(),
    );
  }
  
  // 🔑 اتصال Wallet
  Future<void> connectWallet(String privateKey) async {
    _credentials = EthPrivateKey.fromHex(privateKey);
    await _loadContracts();
  }
  
  // 📄 بارگذاری Contracts
  Future<void> _loadContracts() async {
    // LAXCE Token Contract
    _laxceToken = DeployedContract(
      ContractAbi.fromJson(await _loadAbi('LAXCE'), 'LAXCE'),
      EthereumAddress.fromHex(ContractAddresses.LAXCE_TOKEN),
    );
    
    // Swap Engine Contract
    _swapEngine = DeployedContract(
      ContractAbi.fromJson(await _loadAbi('SwapEngine'), 'SwapEngine'),
      EthereumAddress.fromHex(ContractAddresses.SWAP_ENGINE),
    );
    
    // Fee Manager Contract
    _feeManager = DeployedContract(
      ContractAbi.fromJson(await _loadAbi('FeeManager'), 'FeeManager'),
      EthereumAddress.fromHex(ContractAddresses.FEE_MANAGER),
    );
    
    // Governor Contract
    _governor = DeployedContract(
      ContractAbi.fromJson(await _loadAbi('Governor'), 'Governor'),
      EthereumAddress.fromHex(ContractAddresses.GOVERNOR),
    );
  }
  
  // 📖 بارگذاری ABI Files
  Future<String> _loadAbi(String contractName) async {
    // در پروژه واقعی، این فایل‌ها از assets لود می‌شوند
    // return await rootBundle.loadString('assets/contracts/$contractName.json');
    
    // فعلاً نمونه ABI برمی‌گردانیم
    return '''[
      {
        "name": "transfer",
        "type": "function",
        "inputs": [
          {"name": "to", "type": "address"},
          {"name": "amount", "type": "uint256"}
        ],
        "outputs": [{"name": "", "type": "bool"}]
      }
    ]''';
  }
  
  // ==================== TOKEN OPERATIONS ====================
  
  // 💰 دریافت Balance
  Future<BigInt> getLaxceBalance(String userAddress) async {
    final function = _laxceToken.function('balanceOf');
    final result = await _client.call(
      contract: _laxceToken,
      function: function,
      params: [EthereumAddress.fromHex(userAddress)],
    );
    return result.first as BigInt;
  }
  
  // 🔒 Lock کردن توکن‌ها
  Future<String> lockTokens(BigInt amount, int duration, bool autoExtend) async {
    final function = _laxceToken.function('lockTokens');
    final transaction = Transaction.callContract(
      contract: _laxceToken,
      function: function,
      parameters: [amount, BigInt.from(duration), autoExtend],
      gasPrice: EtherAmount.inWei(BigInt.from(20000000000)), // 20 gwei
      maxGas: 300000,
    );
    
    final txHash = await _client.sendTransaction(
      _credentials,
      transaction,
      chainId: ContractAddresses.CHAIN_ID,
    );
    
    return txHash;
  }
  
  // 💸 تخفیف Fee دریافت کردن
  Future<BigInt> getFeeDiscount(String userAddress) async {
    final function = _laxceToken.function('getFeeDiscount');
    final result = await _client.call(
      contract: _laxceToken,
      function: function,
      params: [EthereumAddress.fromHex(userAddress)],
    );
    return result.first as BigInt;
  }
  
  // ==================== SWAP OPERATIONS ====================
  
  // 💱 محاسبه Quote
  Future<BigInt> getSwapQuote(
    String tokenIn,
    String tokenOut,
    BigInt amountIn,
  ) async {
    final quoter = DeployedContract(
      ContractAbi.fromJson(await _loadAbi('SwapQuoter'), 'SwapQuoter'),
      EthereumAddress.fromHex(ContractAddresses.SWAP_QUOTER),
    );
    
    final function = quoter.function('quoteExactInputSingle');
    final result = await _client.call(
      contract: quoter,
      function: function,
      params: [
        EthereumAddress.fromHex(tokenIn),
        EthereumAddress.fromHex(tokenOut),
        amountIn,
      ],
    );
    return result.first as BigInt;
  }
  
  // 🔄 انجام Swap
  Future<String> performSwap(
    String tokenIn,
    String tokenOut,
    BigInt amountIn,
    BigInt amountOutMin,
    int deadline,
  ) async {
    final function = _swapEngine.function('exactInputSingle');
    final transaction = Transaction.callContract(
      contract: _swapEngine,
      function: function,
      parameters: [
        EthereumAddress.fromHex(tokenIn),
        EthereumAddress.fromHex(tokenOut),
        amountIn,
        amountOutMin,
        BigInt.from(deadline),
      ],
      gasPrice: EtherAmount.inWei(BigInt.from(20000000000)),
      maxGas: 500000,
    );
    
    final txHash = await _client.sendTransaction(
      _credentials,
      transaction,
      chainId: ContractAddresses.CHAIN_ID,
    );
    
    return txHash;
  }
  
  // ==================== GOVERNANCE OPERATIONS ====================
  
  // 🗳️ ایجاد پیشنهاد
  Future<String> createProposal(
    String title,
    String description,
    String callData,
  ) async {
    final function = _governor.function('propose');
    final transaction = Transaction.callContract(
      contract: _governor,
      function: function,
      parameters: [title, description, callData],
      gasPrice: EtherAmount.inWei(BigInt.from(20000000000)),
      maxGas: 400000,
    );
    
    final txHash = await _client.sendTransaction(
      _credentials,
      transaction,
      chainId: ContractAddresses.CHAIN_ID,
    );
    
    return txHash;
  }
  
  // 📊 رای دادن
  Future<String> voteOnProposal(BigInt proposalId, bool support) async {
    final function = _governor.function('vote');
    final transaction = Transaction.callContract(
      contract: _governor,
      function: function,
      parameters: [proposalId, support],
      gasPrice: EtherAmount.inWei(BigInt.from(20000000000)),
      maxGas: 200000,
    );
    
    final txHash = await _client.sendTransaction(
      _credentials,
      transaction,
      chainId: ContractAddresses.CHAIN_ID,
    );
    
    return txHash;
  }
  
  // ==================== UTILITY FUNCTIONS ====================
  
  // 📡 گوش دادن به Events
  Stream<FilterEvent> listenToSwapEvents() {
    final event = _swapEngine.event('Swap');
    return _client.events(FilterOptions.events(
      contract: _swapEngine,
      event: event,
    ));
  }
  
  // 🔍 بررسی وضعیت تراکنش
  Future<TransactionReceipt?> getTransactionReceipt(String txHash) async {
    return await _client.getTransactionReceipt(txHash);
  }
  
  // ⛽ تخمین Gas
  Future<BigInt> estimateGas(Transaction transaction) async {
    return await _client.estimateGas(
      sender: await _credentials.extractAddress(),
      to: transaction.to,
      data: transaction.data,
      value: transaction.value,
    );
  }
  
  // 📊 دریافت آمار کلی
  Future<Map<String, BigInt>> getSystemStats() async {
    // در پیاده‌سازی واقعی، از چندین contract آمار گرفته می‌شود
    return {
      'totalLiquidity': BigInt.parse('1000000000000000000000000'), // 1M ETH
      'totalVolume24h': BigInt.parse('500000000000000000000000'),  // 500K ETH
      'totalUsers': BigInt.from(15000),
      'totalPools': BigInt.from(250),
    };
  }
  
  // 🚫 قطع اتصال
  void disconnect() {
    _client.dispose();
  }
}