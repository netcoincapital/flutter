# Documentation - مستندات

## ساختار مستندات

این پوشه شامل مستندات کامل پروژه DEX است:

## فایل‌ها

### Architecture Documentation
- `architecture.md` - معماری کلی سیستم
- `layer-interactions.md` - تعامل بین لایه‌ها
- `data-flow.md` - جریان داده‌ها
- `security-model.md` - مدل امنیتی

### API Documentation
- `api/` - مستندات API
- `interfaces/` - توضیح interfaces
- `events/` - مستندات events
- `errors/` - کدهای خطا

### User Guides
- `user-guide.md` - راهنمای کاربر
- `developer-guide.md` - راهنمای توسعه‌دهنده
- `integration-guide.md` - راهنمای integration
- `troubleshooting.md` - عیب‌یابی

### Technical Specifications
- `specifications/` - مشخصات فنی
- `gas-optimization.md` - بهینه‌سازی gas
- `upgrade-mechanism.md` - مکانیزم ارتقاء
- `governance-model.md` - مدل حکمرانی

### Examples
- `examples/` - نمونه کدها
- `tutorials/` - آموزش‌ها
- `use-cases/` - موارد استفاده
- `best-practices.md` - بهترین روش‌ها

## ابزارهای تولید مستندات

- **Docusaurus**: Static site generator
- **Solidity Docgen**: Contract documentation
- **Mermaid**: Diagram generation
- **PlantUML**: UML diagrams

## ساخت مستندات

```bash
# تولید مستندات Solidity
npx solidity-docgen

# ساخت سایت مستندات
npm run docs:build

# مشاهده مستندات
npm run docs:serve
``` 