# Core Layer - لایه هسته

## مسئولیت‌ها

این لایه شامل قراردادهای پایه و اساسی سیستم DEX است:

### 1. Access Control
- مدیریت نقش‌ها و دسترسی‌ها
- Owner و Admin management
- Role-based permissions

### 2. Proxy Contracts
- Upgradeable proxy patterns
- Implementation contracts
- Storage management

### 3. Base Contracts
- قراردادهای والدین مشترک
- Common interfaces
- Basic utilities

## فایل‌های این لایه

- `AccessControl.sol` - مدیریت دسترسی‌ها
- `Proxy.sol` - پروکسی برای upgrade
- `BaseContract.sol` - قرارداد پایه
- `Constants.sol` - ثابت‌های سیستم
- `Interfaces.sol` - رابط‌های اصلی

## Dependencies

```solidity
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../libraries/ReentrancyGuard.sol"; // از Libraries استفاده می‌کند
```

## امنیت

- Access control در همه functions حساس
- Proxy pattern برای upgradability
- تنها Base contracts و Interfaces
- ReentrancyGuard از Libraries layer

## Integration با Governance

- تمام Proxy contracts قابل upgrade توسط Governor
- Role-based access control
- Emergency upgrade mechanism
- Multi-signature requirements 