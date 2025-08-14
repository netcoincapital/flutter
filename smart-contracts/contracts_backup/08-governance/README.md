# Governance Layer - لایه حکمرانی

## مسئولیت‌ها

این لایه مسئول حکمرانی و تصمیم‌گیری جمعی پروتکل است:

### 1. Voting System
- سیستم رای‌گیری
- Vote delegation
- Quorum management

### 2. Proposal Management
- ایجاد و مدیریت proposals
- Proposal execution
- Timelock mechanisms

### 3. DAO Operations
- Treasury management
- Parameter updates
- Protocol upgrades

## فایل‌های این لایه

- `Governor.sol` - قرارداد حاکمیت اصلی
- `VotingToken.sol` - توکن رای‌گیری
- `Proposal.sol` - مدیریت proposals
- `Timelock.sol` - قفل زمانی
- `Treasury.sol` - خزانه DAO

## ویژگی‌ها

- ERC20Votes compatibility
- Quadratic voting support
- Delegation mechanisms
- Emergency proposals 