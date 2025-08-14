# Router Layer - لایه مسیریاب

## مسئولیت‌ها

این لایه مسئول مسیریابی و بهینه‌سازی مسیرهای swap است:

### 1. Route Finding
- پیدا کردن بهترین مسیر
- Multi-hop routing
- Path optimization

### 2. Route Execution
- اجرای مسیرهای پیچیده
- Atomic multi-step swaps
- Route splitting

### 3. Route Analysis
- تجزیه و تحلیل مسیرها
- Cost analysis
- Liquidity analysis

## فایل‌های این لایه

- `Router.sol` - مسیریاب اصلی
- `PathFinder.sol` - پیدا کننده مسیر
- `RouteOptimizer.sol` - بهینه‌ساز مسیر
- `MultiHopRouter.sol` - multi-hop swaps
- `RouteAnalyzer.sol` - تحلیل مسیرها

## الگوریتم‌ها

- Dijkstra's algorithm for best path
- A* search optimization
- Dynamic programming
- Graph-based routing 