// 📝 Contract Addresses - بعد از deployment این فایل را تکمیل کنید

class ContractAddresses {
  // 🌐 Network Configuration
  static const String NETWORK_NAME = "sepolia"; // یا "mainnet"
  static const String RPC_URL = "https://sepolia.infura.io/v3/YOUR_INFURA_KEY";
  static const int CHAIN_ID = 11155111; // Sepolia: 11155111, Mainnet: 1
  
  // 🏗️ Core Contracts
  static const String ACCESS_CONTROL = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  
  // 🪙 Token Contracts  
  static const String LAXCE_TOKEN = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String LP_TOKEN = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String TOKEN_REGISTRY = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String POSITION_NFT = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  
  // 🏊 Pool Contracts
  static const String POOL_FACTORY = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  
  // 💱 Swap Contracts
  static const String SWAP_ENGINE = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String SWAP_QUOTER = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String PRICE_CALCULATOR = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String SLIPPAGE_PROTECTION = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  
  // 🔮 Oracle Contracts
  static const String ORACLE_MANAGER = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String PRICE_ORACLE = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String CHAINLINK_ORACLE = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String TWAP_ORACLE = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  
  // 🛣️ Router Contracts
  static const String ROUTER = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String PATH_FINDER = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  
  // 💰 Fee Contracts
  static const String FEE_MANAGER = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String FEE_CALCULATOR = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String FEE_DISTRIBUTOR = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  
  // 🏛️ Governance Contracts
  static const String GOVERNOR = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String TREASURY = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String VOTING_TOKEN = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String TIMELOCK = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  
  // 🛡️ Security Contracts
  static const String SECURITY_MANAGER = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  
  // 💧 Liquidity Contracts
  static const String LIQUIDITY_MINING = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String YIELD_FARMING = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String STAKING_MANAGER = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  
  // 📊 Quoter Contracts  
  static const String QUOTER = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String SWAP_ROUTER = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  
  // 🔮 Advanced Oracle
  static const String UNISWAP_V3_ORACLE = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String ORACLE_LIBRARY = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  static const String PRICE_VALIDATOR = "0x0000000000000000000000000000000000000000"; // ⚠️ بعد از deploy پر کنید
  
  // 🏷️ Common Token Addresses (Sepolia Testnet)
  static const String WETH = "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9"; // Sepolia WETH
  static const String USDC = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"; // Sepolia USDC (mock)
  static const String USDT = "0x7169D38820dfd117C3FA1f22a697dBA58d90BA06"; // Sepolia USDT (mock)
  
  // 📋 Helper Methods
  static Map<String, String> getAllAddresses() {
    return {
      'ACCESS_CONTROL': ACCESS_CONTROL,
      'LAXCE_TOKEN': LAXCE_TOKEN,
      'LP_TOKEN': LP_TOKEN,
      'TOKEN_REGISTRY': TOKEN_REGISTRY,
      'POSITION_NFT': POSITION_NFT,
      'POOL_FACTORY': POOL_FACTORY,
      'SWAP_ENGINE': SWAP_ENGINE,
      'SWAP_QUOTER': SWAP_QUOTER,
      'PRICE_CALCULATOR': PRICE_CALCULATOR,
      'ORACLE_MANAGER': ORACLE_MANAGER,
      'PRICE_ORACLE': PRICE_ORACLE,
      'ROUTER': ROUTER,
      'PATH_FINDER': PATH_FINDER,
      'FEE_MANAGER': FEE_MANAGER,
      'GOVERNOR': GOVERNOR,
      'TREASURY': TREASURY,
      'SECURITY_MANAGER': SECURITY_MANAGER,
      'LIQUIDITY_MINING': LIQUIDITY_MINING,
      'YIELD_FARMING': YIELD_FARMING,
      'QUOTER': QUOTER,
      'SWAP_ROUTER': SWAP_ROUTER,
    };
  }
  
  static bool isValidAddress(String address) {
    return address.isNotEmpty && 
           address != "0x0000000000000000000000000000000000000000" &&
           address.length == 42 &&
           address.startsWith('0x');
  }
  
  static bool areAllAddressesSet() {
    final addresses = getAllAddresses();
    return addresses.values.every((address) => isValidAddress(address));
  }
}