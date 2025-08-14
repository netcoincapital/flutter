# 📊 Layer 6: Quoter/Swap Layer Guide

> **راهنمای کامل لایه 6 - سیستم quote و مبادله پیشرفته**  
> Documentation for LAXCE DEX advanced quoter and swap functionality

## 🎯 Overview

Layer 6 (Quoter/Swap) provides advanced off-chain calculation and on-chain swap execution capabilities for the LAXCE DEX. This layer enables:

- **Off-chain Quote Calculations**: Accurate price and gas estimates without executing transactions
- **Advanced Swap Execution**: Multi-hop routing with MEV protection and slippage control
- **Mathematical Utilities**: Complex swap math for concentrated liquidity

## 📁 Contract Structure

```
contracts/06-quoter/
├── Quoter.sol          # Off-chain quote calculations
├── SwapRouter.sol      # On-chain swap execution
└── SwapMath.sol        # Mathematical library for swaps
```

## 🔧 Core Components

### 1. Quoter.sol
**Purpose**: Off-chain price calculations and gas estimates

**Key Features**:
- ✅ Exact input/output quotes for single and multi-hop swaps
- ✅ Price impact analysis with configurable limits
- ✅ Gas estimation for different swap types
- ✅ Pool information caching for optimization
- ✅ Path validation and route optimization

**Main Functions**:
```solidity
// Single hop quotes
function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
    external view returns (QuoteResult memory result);

function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
    external view returns (QuoteResult memory result);

// Multi-hop quotes
function quoteExactInput(QuoteExactInputParams memory params)
    external view returns (QuoteResult memory result);

function quoteExactOutput(QuoteExactOutputParams memory params)
    external view returns (QuoteResult memory result);
```

### 2. SwapRouter.sol
**Purpose**: On-chain swap execution with advanced features

**Key Features**:
- ✅ Exact input/output swaps (single and multi-hop)
- ✅ MEV protection with configurable parameters
- ✅ Token blacklist/whitelist support
- ✅ Emergency mode for system protection
- ✅ Router fee collection
- ✅ ETH/WETH handling
- ✅ Multicall support for batch operations

**Main Functions**:
```solidity
// Single hop swaps
function exactInputSingle(ExactInputSingleParams calldata params)
    external payable returns (uint256 amountOut);

function exactOutputSingle(ExactOutputSingleParams calldata params)
    external payable returns (uint256 amountIn);

// Multi-hop swaps
function exactInput(ExactInputParams calldata params)
    external payable returns (uint256 amountOut);

function exactOutput(ExactOutputParams calldata params)
    external payable returns (uint256 amountIn);
```

### 3. SwapMath.sol
**Purpose**: Mathematical library for swap calculations

**Key Features**:
- ✅ Complex concentrated liquidity math
- ✅ Price impact calculations
- ✅ Optimal swap amount determination
- ✅ Gas estimation utilities
- ✅ Square root and tick calculations

**Main Functions**:
```solidity
// Core calculations
function calculateSwap(SwapParams memory params)
    internal pure returns (SwapResult memory result);

function getAmountOut(uint256 amountIn, uint256 liquidity, uint160 sqrtPriceX96, bool zeroForOne)
    internal pure returns (uint256 amountOut);

function getAmountIn(uint256 amountOut, uint256 liquidity, uint160 sqrtPriceX96, bool zeroForOne)
    internal pure returns (uint256 amountIn);

// Utility functions
function calculatePriceImpact(uint160 priceBefore, uint160 priceAfter)
    internal pure returns (uint256 impact);

function getLiquidityForAmounts(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint256 amount0, uint256 amount1)
    internal pure returns (uint128 liquidity);
```

## 🚀 Usage Examples

### Basic Quote Calculation

```javascript
const quoter = await ethers.getContractAt("Quoter", quoterAddress);

// Get quote for exact input
const quoteParams = {
    tokenIn: tokenA.address,
    tokenOut: tokenB.address,
    fee: 3000, // 0.3%
    amountIn: ethers.utils.parseEther("100"),
    sqrtPriceLimitX96: 0
};

const result = await quoter.quoteExactInputSingle(quoteParams);
console.log(`Amount Out: ${ethers.utils.formatEther(result.amountOut)}`);
console.log(`Price Impact: ${result.priceImpact / 100}%`);
console.log(`Gas Estimate: ${result.gasEstimate}`);
```

### Multi-hop Quote

```javascript
// Encode path: TokenA -> TokenB -> TokenC
function encodePath(tokens, fees) {
    let path = "0x";
    for (let i = 0; i < tokens.length; i++) {
        path += tokens[i].slice(2);
        if (i < fees.length) {
            path += fees[i].toString(16).padStart(6, '0');
        }
    }
    return path;
}

const path = encodePath(
    [tokenA.address, tokenB.address, tokenC.address],
    [3000, 3000] // 0.3% fee for both hops
);

const multiHopQuote = await quoter.quoteExactInput({
    path: path,
    amountIn: ethers.utils.parseEther("100")
});
```

### Executing Swaps

```javascript
const swapRouter = await ethers.getContractAt("SwapRouter", routerAddress);

// Approve tokens
await tokenA.approve(swapRouter.address, ethers.utils.parseEther("100"));

// Execute exact input swap
const swapParams = {
    tokenIn: tokenA.address,
    tokenOut: tokenB.address,
    fee: 3000,
    recipient: userAddress,
    deadline: Math.floor(Date.now() / 1000) + 3600, // 1 hour
    amountIn: ethers.utils.parseEther("100"),
    amountOutMinimum: ethers.utils.parseEther("95"), // 5% slippage tolerance
    sqrtPriceLimitX96: 0
};

const tx = await swapRouter.exactInputSingle(swapParams);
await tx.wait();
```

### MEV Protection Configuration

```javascript
// Configure MEV protection
const mevConfig = {
    enabled: true,
    maxPriceImpact: 1000, // 10%
    minBlockDelay: 2,
    maxSlippageTolerance: 500 // 5%
};

await swapRouter.setMEVProtection(mevConfig);
```

## ⚙️ Configuration

### Quoter Configuration

```javascript
// Set maximum allowed price impact
await quoter.setMaxPriceImpact(1000); // 10%

// Set minimum liquidity requirement
await quoter.setMinLiquidity(ethers.utils.parseEther("1"));

// Update gas estimates
await quoter.updateGasEstimate("singleSwap", 80000);
await quoter.updateGasEstimate("multiSwapBase", 100000);
```

### SwapRouter Configuration

```javascript
// Set default slippage tolerance
await swapRouter.setDefaultSlippage(500); // 5%

// Set router fee
await swapRouter.setRouterFee(1); // 0.01%

// Configure token whitelist/blacklist
await swapRouter.setTokenBlacklist(maliciousToken, true);
await swapRouter.setTokenWhitelist(trustedToken, true);
await swapRouter.setWhitelistMode(true);
```

## 🔐 Security Features

### MEV Protection
- **Block Delay**: Prevents rapid successive swaps from the same user
- **Price Impact Limits**: Blocks swaps that would cause excessive price movement
- **Slippage Control**: Configurable maximum slippage tolerance

### Access Control
- **Role-based permissions**: Admin, Operator, Pauser roles
- **Emergency controls**: Pause functionality and emergency mode
- **Token filtering**: Blacklist/whitelist support

### Input Validation
- **Amount checks**: Prevents zero or invalid amounts
- **Path validation**: Ensures valid multi-hop routes
- **Deadline enforcement**: Prevents stale transactions

## 📊 Integration with Other Layers

### Dependencies
- **Layer 3 (Pool)**: Uses PoolFactory for pool discovery and LaxcePool for swap execution
- **Layer 5 (Oracle)**: Can integrate with price oracles for additional validation
- **Layer 9 (Security)**: Works with SecurityManager for additional protection

### Integration Points

```javascript
// Integration with Pool Layer
const poolAddress = await poolFactory.getPool(tokenA, tokenB, fee);
const pool = await ethers.getContractAt("LaxcePool", poolAddress);

// Integration with Router Layer (Layer 4)
const pathFinder = await ethers.getContractAt("PathFinder", pathFinderAddress);
const optimalPath = await pathFinder.findOptimalPath(tokenA, tokenB, amountIn);
```

## 🧪 Testing

### Running Tests

```bash
# Test all Quoter Layer contracts
npm run test:quoter

# Test specific contracts
npx hardhat test test/06-quoter/Quoter.test.js
npx hardhat test test/06-quoter/SwapRouter.test.js
npx hardhat test test/06-quoter/SwapMath.test.js
```

### Test Coverage

- ✅ **Quoter**: Single/multi-hop quotes, price impact, gas estimation, caching
- ✅ **SwapRouter**: All swap types, MEV protection, access control, edge cases
- ✅ **SwapMath**: Mathematical accuracy, edge cases, gas optimization

### Example Test

```javascript
describe("Quoter", function () {
    it("Should calculate exact input quote correctly", async function () {
        const params = {
            tokenIn: token0.address,
            tokenOut: token1.address,
            fee: 3000,
            amountIn: ethers.utils.parseEther("100"),
            sqrtPriceLimitX96: 0
        };

        const result = await quoter.quoteExactInputSingle(params);
        
        expect(result.amountOut).to.be.gt(0);
        expect(result.priceImpact).to.be.lt(1000); // Less than 10%
        expect(result.gasEstimate).to.be.gte(80000);
    });
});
```

## 🚀 Deployment

### Environment Setup

```bash
# Set required environment variables
export POOL_FACTORY_ADDRESS="0x..."
export WETH9_ADDRESS="0x..."
export PRIVATE_KEY="your-private-key"
```

### Deploy to Testnet

```bash
# Deploy to testnet
npm run deploy:quoter:testnet

# Or using hardhat directly
npx hardhat run scripts/deploy-quoter.js --network sepolia
```

### Deploy to Mainnet

```bash
# Deploy to mainnet
npm run deploy:quoter

# Or using hardhat directly
npx hardhat run scripts/deploy-quoter.js --network mainnet
```

### Deployment Configuration

The deployment script supports different configurations for mainnet and testnet:

**Mainnet Configuration**:
- Max price impact: 10%
- Router fee: 0.01%
- MEV protection: Enabled

**Testnet Configuration**:
- Max price impact: 20% (more lenient)
- Router fee: 0.05%
- MEV protection: Disabled

## 📈 Gas Optimization

### Best Practices

1. **Use View Functions**: Always use Quoter for price calculations before executing swaps
2. **Path Optimization**: Use shorter paths when possible to reduce gas costs
3. **Batch Operations**: Use multicall for multiple operations
4. **Cache Pool Data**: Quoter caches pool information to reduce gas on repeated calls

### Gas Estimates

| Operation | Estimated Gas |
|-----------|---------------|
| Single hop swap | ~80,000 |
| Multi-hop swap (2 hops) | ~150,000 |
| Multi-hop swap (3 hops) | ~220,000 |
| Quote calculation | ~30,000 |

## 🔧 Advanced Features

### Price Impact Analysis

```javascript
// Check price impact before executing large trades
const quote = await quoter.quoteExactInputSingle(params);
if (quote.priceImpact > 1000) { // > 10%
    console.warn("High price impact detected!");
}
```

### Optimal Amount Calculation

```javascript
// Calculate optimal swap amount using SwapMath
const swapMath = await ethers.getContractAt("SwapMathTest", swapMathAddress);
const optimalAmount = await swapMath.calculateOptimalSwapAmount(
    reserve0,
    reserve1,
    fee
);
```

### Custom Path Encoding

```javascript
function encodeCustomPath(tokens, fees) {
    // Custom path encoding logic
    let encoded = "0x";
    for (let i = 0; i < tokens.length; i++) {
        encoded += tokens[i].slice(2);
        if (i < fees.length) {
            encoded += fees[i].toString(16).padStart(6, '0');
        }
    }
    return encoded;
}
```

## 🔍 Monitoring & Analytics

### Key Metrics

- **Quote Accuracy**: Compare quoted vs actual amounts
- **Price Impact**: Track average price impact across swaps
- **Gas Usage**: Monitor actual vs estimated gas consumption
- **MEV Protection**: Track blocked vs allowed transactions

### Event Monitoring

```javascript
// Monitor swap events
swapRouter.on("SwapExecuted", (sender, recipient, tokenIn, tokenOut, amountIn, amountOut, feeAmount) => {
    console.log(`Swap executed: ${amountIn} ${tokenIn} -> ${amountOut} ${tokenOut}`);
});

// Monitor quote calculations
quoter.on("QuoteCalculated", (tokenIn, tokenOut, amountIn, amountOut, priceImpact) => {
    console.log(`Quote: ${amountIn} -> ${amountOut}, Impact: ${priceImpact / 100}%`);
});
```

## 🐛 Troubleshooting

### Common Issues

1. **"Quoter__PoolNotFound"**
   - Ensure the pool exists for the token pair and fee tier
   - Check that tokens are sorted correctly (token0 < token1)

2. **"SwapRouter__ExcessivePriceImpact"**
   - Reduce swap amount or increase slippage tolerance
   - Check MEV protection settings

3. **"SwapRouter__InsufficientAmountOut"**
   - Increase slippage tolerance
   - Check for sudden price movements

4. **"SwapRouter__DeadlineExpired"**
   - Increase deadline or resubmit transaction faster

### Debugging

```javascript
// Debug quote calculations
try {
    const result = await quoter.quoteExactInputSingle(params);
    console.log("Quote result:", result);
} catch (error) {
    console.error("Quote failed:", error.message);
}

// Check pool state
const poolInfo = await quoter.getPoolInfo(tokenA, tokenB, fee);
console.log("Pool info:", poolInfo);
```

## 📚 Additional Resources

- [Uniswap V3 Math](https://docs.uniswap.org/sdk/v3/guides/swaps/trading)
- [Concentrated Liquidity](https://docs.uniswap.org/concepts/protocol/concentrated-liquidity)
- [MEV Protection Strategies](https://ethereum.org/en/developers/docs/mev/)

---

**تیم توسعه LAXCE DEX**  
Layer 6 provides the core swap infrastructure with advanced features for optimal trading experience. 