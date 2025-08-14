# 🚀 راهنمای Deploy در Remix

## ترتیب صحیح Deployment:

### 1️⃣ **مرحله اول: Foundations**
```
1. libraries/Constants.sol
2. libraries/FullMath.sol  
3. libraries/SafeMath.sol
4. libraries/ReentrancyGuard.sol
5. 01-core/AccessControl.sol
```

### 2️⃣ **مرحله دوم: Core Systems**
```
6. 02-token/LAXCE.sol (constructor params: treasury, teamWallet, marketingWallet)
7. 02-token/TokenRegistry.sol
8. 02-token/LPToken.sol
9. 02-token/PositionNFT.sol
```

### 3️⃣ **مرحله سوم: Oracle & Pool**
```
10. 05-oracle/ChainlinkOracle.sol
11. 05-oracle/TWAPOracle.sol
12. 05-oracle/PriceOracle.sol
13. 05-oracle/OracleManager.sol
14. 03-pool/SimplePool.sol
15. 03-pool/PoolFactory.sol
```

### 4️⃣ **مرحله چهارم: Trading**
```
16. 04-swap/SwapLibrary.sol
17. 04-swap/PriceCalculator.sol  
18. 04-swap/SlippageProtection.sol
19. 04-swap/SwapValidator.sol
20. 04-swap/SwapEngine.sol
21. 04-swap/SwapQuoter.sol
22. 06-quoter/Quoter.sol
23. 06-quoter/SwapRouter.sol
```

### 5️⃣ **مرحله پنجم: Advanced Features**
```
24. 12-router/PathFinder.sol
25. 12-router/Router.sol
26. 07-liquidity/LiquidityMining.sol
27. 07-liquidity/YieldFarming.sol
28. 07-liquidity/StakingManager.sol
29. 09-security/SecurityManager.sol
```

### 6️⃣ **مرحله ششم: Governance**
```
30. 08-governance/VotingToken.sol
31. 08-governance/Treasury.sol
32. 08-governance/Proposal.sol
33. 08-governance/Timelock.sol
34. 08-governance/Governor.sol
```

### 7️⃣ **مرحله هفتم: Fee Management**
```
35. 11-fee/FeeCalculator.sol
36. 11-fee/FeeManager.sol
37. 11-fee/FeeDistributor.sol
38. 11-fee/ProtocolFeeCollector.sol
39. 11-fee/FeeOptimizer.sol
```

### 8️⃣ **مرحله هشتم: Advanced Oracle**
```
40. 10-oracle/UniswapV3Oracle.sol
41. 10-oracle/OracleLibrary.sol
42. 10-oracle/PriceValidator.sol
```

## نکات مهم:
1. هر contract را پس از deploy تست کنید
2. آدرس هر contract را یادداشت کنید
3. Constructor parameters را درست وارد کنید
4. Gas limit را مناسب تنظیم کنید (3M-5M)
5. Network را درست انتخاب کنید (Sepolia testnet توصیه می‌شود)