# 🛠️ راهنمای تنظیم Remix برای LAXCE DEX

## 📤 **مرحله 1: Upload کردن فایل‌ها**

### **گام 1: باز کردن Remix**
- برو به: https://remix.ethereum.org
- منتظر بمان تا کاملاً لود شود

### **گام 2: Upload پوشه contracts**
```
File Explorer (سمت چپ) → Upload Folder → انتخاب پوشه contracts
```

یا 

```
پوشه contracts را از فایندر drag & drop کن به Remix
```

---

## ⚙️ **مرحله 2: تنظیم Compiler**

### **Solidity Compiler Tab:**
```
- Version: 0.8.20 یا بالاتر
- Enable Optimization: ✅ چک کن
- Runs: 200
- EVM Version: London
```

### **Advanced Configuration:**
```json
{
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "evmVersion": "london"
}
```

---

## 🔍 **مرحله 3: بررسی خطاها**

### **ترتیب کامپایل:**
1. `libraries/Constants.sol` ← اول
2. `libraries/FullMath.sol` 
3. `01-core/AccessControl.sol`
4. `02-token/LAXCE.sol`
5. ادامه به ترتیب...

### **خطاهای محتمل:**

#### **خطای Import:**
```solidity
// ❌ اشتباه
import "../01-core/AccessControl.sol";

// ✅ درست (اگر مسیر عوض شده)
import "./01-core/AccessControl.sol";
```

#### **خطای Version:**
```solidity
// بررسی کن همه فایل‌ها دارند:
pragma solidity ^0.8.20;
```

#### **خطای Library:**
```solidity
// اگر Constants.sol خطا داد:
library Constants {
    uint256 public constant BASIS_POINTS = 10000;
    // بقیه constants...
}
```

---

## 🚨 **رفع خطاهای رایج**

### **1. خطای Duplicate Contract:**
```
Error: Duplicate contract name found
```
**راه‌حل:** اسم فایل‌ها یکتا باشد

### **2. خطای Import Path:**
```
Error: Source not found
```
**راه‌حل:** مسیر import ها را بررسی کن

### **3. خطای OpenZeppelin:**
```
Error: @openzeppelin/contracts not found
```
**راه‌حل:** 
- Settings → Package Manager → Add @openzeppelin/contracts@4.9.0

---

## 📋 **چک‌لیست تنظیمات**

### **File Structure در Remix:**
```
📁 contracts/
├── 📁 01-core/
│   ├── AccessControl.sol ✅
│   └── 📁 interfaces/
├── 📁 02-token/
│   ├── LAXCE.sol ✅
│   ├── LPToken.sol ✅
│   └── ...
├── 📁 libraries/
│   ├── Constants.sol ✅
│   ├── FullMath.sol ✅
│   └── ...
└── ...
```

### **Compiler Settings:**
- [ ] Version: 0.8.20+
- [ ] Optimization: Enabled (200 runs)
- [ ] EVM Version: London
- [ ] OpenZeppelin: Installed

### **First Compile Test:**
1. [ ] Constants.sol کامپایل شود
2. [ ] AccessControl.sol کامپایل شود  
3. [ ] LAXCE.sol کامپایل شود

---

## 🎯 **مراحل بعدی**

### **بعد از رفع خطاها:**
1. **تست کامپایل:** همه contracts کامپایل شوند
2. **Deploy تست:** یکی دو contract را تست deploy کن
3. **آدرس‌ها:** آدرس‌های deploy شده را یادداشت کن
4. **ABI:** فایل‌های ABI را دانلود کن

---

## 📞 **درصورت مشکل:**

### **خطاهای رایج:**
- **Import Error:** مسیرها را درست کن
- **Version Error:** همه فایل‌ها 0.8.20+ باشند
- **Library Error:** ترتیب کامپایل را رعایت کن

### **کمک گرفتن:**
- Screenshot از خطا بگیر
- کد خط مشکل‌دار را کپی کن
- نام فایل مشکل‌دار را بگو

**بعد از upload موفق، بهم بگو تا مرحله بعدی (رفع خطاها) را شروع کنیم! 🚀**