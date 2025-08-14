# ✅ چک‌لیست Deployment و Integration

## 🚀 **مرحله 1: آماده‌سازی**

- [ ] **Remix IDE** باز کردن
- [ ] **MetaMask** نصب و تنظیم
- [ ] **Sepolia ETH** گرفتن از faucet
- [ ] **Upload contracts** به Remix
- [ ] **Compiler version** تنظیم (0.8.20+)
- [ ] **Optimization** فعال کردن (200 runs)

---

## 🔨 **مرحله 2: Deployment Contracts**

### **Libraries & Core:**
- [ ] Constants.sol
- [ ] FullMath.sol
- [ ] ReentrancyGuard.sol
- [ ] AccessControl.sol

### **Token System:**
- [ ] LAXCE.sol
  - Treasury Address: `0x...`
  - Team Address: `0x...`
  - Marketing Address: `0x...`
- [ ] TokenRegistry.sol
- [ ] LPToken.sol  
- [ ] PositionNFT.sol

### **Oracle System:**
- [ ] ChainlinkOracle.sol
- [ ] TWAPOracle.sol
- [ ] PriceOracle.sol
- [ ] OracleManager.sol

### **Pool & Trading:**
- [ ] PoolFactory.sol
- [ ] SimplePool.sol
- [ ] SwapLibrary.sol
- [ ] PriceCalculator.sol
- [ ] SlippageProtection.sol
- [ ] SwapValidator.sol
- [ ] SwapEngine.sol
- [ ] SwapQuoter.sol

### **Router & Quoter:**
- [ ] PathFinder.sol
- [ ] Router.sol
- [ ] Quoter.sol
- [ ] SwapRouter.sol

### **Liquidity Mining:**
- [ ] LiquidityMining.sol
- [ ] YieldFarming.sol
- [ ] StakingManager.sol

### **Governance:**
- [ ] VotingToken.sol
- [ ] Treasury.sol
- [ ] Proposal.sol
- [ ] Timelock.sol
- [ ] Governor.sol

### **Fee Management:**
- [ ] FeeCalculator.sol
- [ ] FeeManager.sol
- [ ] FeeDistributor.sol
- [ ] ProtocolFeeCollector.sol
- [ ] FeeOptimizer.sol

### **Security & Advanced Oracle:**
- [ ] SecurityManager.sol
- [ ] UniswapV3Oracle.sol
- [ ] OracleLibrary.sol
- [ ] PriceValidator.sol

---

## 📝 **مرحله 3: ثبت آدرس‌ها**

### **Core Contracts:**
- [ ] AccessControl: `0x...`
- [ ] LAXCE Token: `0x...`
- [ ] TokenRegistry: `0x...`
- [ ] LPToken: `0x...`

### **Trading Contracts:**
- [ ] SwapEngine: `0x...`
- [ ] SwapQuoter: `0x...`
- [ ] Router: `0x...`
- [ ] PoolFactory: `0x...`

### **Oracle Contracts:**
- [ ] OracleManager: `0x...`
- [ ] PriceOracle: `0x...`

### **Governance Contracts:**
- [ ] Governor: `0x...`
- [ ] Treasury: `0x...`
- [ ] Timelock: `0x...`

### **Fee Contracts:**
- [ ] FeeManager: `0x...`
- [ ] FeeCalculator: `0x...`

---

## 🧪 **مرحله 4: تست Contracts**

### **Basic Tests:**
- [ ] LAXCE balance check
- [ ] AccessControl roles check
- [ ] Oracle price feed
- [ ] Pool creation

### **Functionality Tests:**
- [ ] Token transfer
- [ ] Token lock/unlock
- [ ] Simple swap (small amount)
- [ ] Fee calculation
- [ ] LP token mint

### **Integration Tests:**
- [ ] Multi-hop swap
- [ ] Governance proposal
- [ ] Liquidity mining
- [ ] Fee distribution

---

## 📱 **مرحله 5: Flutter Integration**

### **کپی فایل‌ها:**
- [ ] `contract_addresses.dart` به پروژه Flutter
- [ ] `web3_service.dart` به پروژه Flutter
- [ ] ABI files به `assets/contracts/`

### **تنظیم Addresses:**
- [ ] همه آدرس‌ها را از `0x0000...` تغییر دادن
- [ ] Network و RPC URL تنظیم
- [ ] Chain ID درست تنظیم

### **Dependencies:**
- [ ] `web3dart: ^2.7.3` اضافه کردن
- [ ] `http: ^1.1.0` اضافه کردن
- [ ] `provider: ^6.1.1` اضافه کردن

### **Assets:**
- [ ] ABI files در pubspec.yaml اضافه کردن
- [ ] `flutter pub get` اجرا کردن

---

## 🔧 **مرحله 6: UI Implementation**

### **Swap Screen:**
- [ ] Token selector widget
- [ ] Amount input field
- [ ] Quote display
- [ ] Swap button functionality
- [ ] Transaction status

### **Portfolio Screen:**
- [ ] LAXCE balance display
- [ ] Locked tokens info
- [ ] Fee discount tier
- [ ] Rewards claimable

### **Governance Screen:**
- [ ] Proposals list
- [ ] Voting interface
- [ ] Delegation options
- [ ] Treasury info

### **Liquidity Screen:**
- [ ] Pool positions
- [ ] Add/Remove liquidity
- [ ] Mining rewards
- [ ] APY calculations

---

## ✅ **مرحله 7: Testing App**

### **Wallet Connection:**
- [ ] MetaMask connection
- [ ] Account switching
- [ ] Network switching
- [ ] Balance loading

### **Basic Operations:**
- [ ] Token approval
- [ ] Simple swap
- [ ] Balance update
- [ ] Transaction history

### **Advanced Features:**
- [ ] Token locking
- [ ] Governance voting
- [ ] LP mining
- [ ] Fee claiming

---

## 🎯 **مرحله 8: Production Deployment**

### **Mainnet Preparation:**
- [ ] Audit smart contracts
- [ ] Update contract addresses to mainnet
- [ ] Test with small amounts
- [ ] Documentation complete

### **App Store:**
- [ ] App testing on devices
- [ ] Screenshots and descriptions
- [ ] Privacy policy
- [ ] Terms of service

---

## 📊 **نکات مهم:**

### **⚠️ Security:**
- هرگز private keys را در کد قرار ندهید
- همیشه amounts را validate کنید
- Slippage limits تنظیم کنید
- Gas limits مناسب تنظیم کنید

### **💰 Costs (تخمینی):**
- **Testnet**: رایگان
- **Mainnet**: ~1-3 ETH برای deploy همه contracts
- **Verification**: رایگان در Etherscan

### **🔍 Verification:**
- همه contracts را در Etherscan verify کنید
- Source code را public کنید
- README و documentation کامل کنید

---

## 🎉 **تبریک!**

بعد از تکمیل همه این مراحل، شما یک DEX کاملاً عملیاتی خواهید داشت! 🚀

**آیا آماده شروع deployment هستید؟**