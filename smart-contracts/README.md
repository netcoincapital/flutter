# LAXCE DEX Smart Contracts

## معماری 10 لایه‌ای DEX + Libraries

این پروژه از 10 لایه قرارداد هوشمند + کتابخانه‌های مشترک تشکیل شده است که هر کدام مسئولیت خاص خود را دارند:

### 1. Core Layer (لایه هسته)
- قراردادهای پایه و اساسی
- مدیریت access control
- پروکسی قراردادها

### 2. Token Layer (لایه توکن)
- مدیریت ERC20 tokens
- پشتیبانی از token standards
- Token metadata

### 3. Pool Layer (لایه استخر)
- مدیریت liquidity pools
- Pool factory
- Pool pairs

### 4. Swap Layer (لایه مبادله)
- منطق swap operations
- Price calculation
- Slippage protection

### 5. Liquidity Layer (لایه نقدینگی)
- Add/Remove liquidity
- LP token management
- Rewards distribution

### 6. Fee Layer (لایه کارمزد)
- Fee calculation
- Fee distribution
- Protocol fees

### 7. Router Layer (لایه مسیریاب)
- Multi-hop swaps
- Best path finding
- Route optimization

### 8. Governance Layer (لایه حکمرانی)
- Voting mechanisms
- Proposal system
- Protocol parameters

### 9. Security Layer (لایه امنیت)
- Security coordination
- Emergency functions
- System-wide pause mechanisms

### 10. Oracle Layer (لایه اوراکل)
- Price oracles و TWAP
- Multi-source price aggregation
- Price manipulation protection

### Libraries (کتابخانه‌های مشترک)
- Math libraries (FullMath, TickMath)
- Transfer helpers (SafeERC20)
- Shared utilities (ReentrancyGuard)

## ساختار پروژه

```
smart-contracts/
├── contracts/
│   ├── libraries/           # کتابخانه‌های مشترک
│   ├── 01-core/            # Access Control & Proxy
│   ├── 02-token/           # ERC20, LP, Position NFT
│   ├── 03-pool/            # Pool Management
│   ├── 04-swap/            # Swap + Quoter
│   ├── 05-liquidity/       # Liquidity + Rewards
│   ├── 06-fee/             # Fee Management
│   ├── 07-router/          # Router + PathFinder
│   ├── 08-governance/      # DAO + Treasury
│   ├── 09-security/        # Emergency Coordinator
│   └── 10-oracle/          # Price Oracle + TWAP
├── scripts/
├── test/
├── deploy/
├── docs/
└── flutter-integration/
```

## تکنولوژی‌های استفاده شده

- **Solidity**: ^0.8.20
- **Hardhat**: Development environment
- **OpenZeppelin**: Security libraries
- **Ethers.js**: Blockchain interaction
- **Chai**: Testing framework

## نصب و راه‌اندازی

```bash
npm install
npx hardhat compile
npx hardhat test
```

## اتصال به Flutter App

این قراردادها به صفحه `dex_screen.dart` در اپلیکیشن فلاتر متصل خواهند شد. 