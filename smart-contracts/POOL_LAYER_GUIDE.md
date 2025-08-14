# LAXCE DEX - Pool Layer Guide (Layer 3)

## Overview

The Pool Layer (Layer 3) is the heart of the LAXCE DEX, implementing **concentrated liquidity** similar to Uniswap V3. This layer manages all pool operations, liquidity provision, position management, and fee collection through three main contracts.

## Architecture Components

### 1. LaxcePool.sol
The core pool contract implementing concentrated liquidity mechanics.

**Key Features:**
- **Concentrated Liquidity**: Users can provide liquidity within specific price ranges
- **Tick-based System**: Granular price control using tick spacing
- **Multiple Fee Tiers**: Support for 0.05%, 0.3%, 1% and custom fee tiers
- **Flash Loans**: Built-in flash loan functionality
- **Oracle Integration**: Price observations for TWAP calculations
- **Position NFTs**: ERC-721 representation of liquidity positions

**Main Functions:**
```solidity
// Initialize pool with price
function initialize(
    address factory,
    address token0,
    address token1,
    uint24 fee,
    int24 tickSpacing,
    address lpToken,
    address positionNFT,
    uint160 sqrtPriceX96
) external;

// Add liquidity to a position
function mint(
    address recipient,
    int24 tickLower,
    int24 tickUpper,
    uint256 amount0,
    uint256 amount1
) external returns (uint128 liquidity);

// Remove liquidity from a position
function burn(
    int24 tickLower,
    int24 tickUpper,
    uint128 liquidity
) external returns (uint256 amount0, uint256 amount1);

// Swap tokens
function swap(
    address recipient,
    bool zeroForOne,
    int256 amountSpecified,
    uint160 sqrtPriceLimitX96,
    bytes calldata data
) external returns (int256 amount0, int256 amount1);

// Flash loan
function flash(
    address recipient,
    uint256 amount0,
    uint256 amount1,
    bytes calldata data
) external;
```

### 2. PoolFactory.sol
Factory contract for creating and managing pools.

**Key Features:**
- **Pool Creation**: CREATE2 deployment for deterministic addresses
- **Fee Tier Management**: Enable/disable fee tiers dynamically
- **Token Whitelisting**: Optional token whitelisting for pools
- **Pool Registry**: Track all created pools and their statistics
- **Access Control**: Owner-based management system

**Main Functions:**
```solidity
// Create a new pool
function createPool(
    address tokenA,
    address tokenB,
    uint24 fee
) external returns (address pool);

// Enable a new fee tier
function enableFeeAmount(uint24 fee, int24 tickSpacing) external;

// Disable a fee tier
function disableFeeAmount(uint24 fee) external;

// Set token whitelist status
function setTokenWhitelist(address token, bool whitelisted) external;

// Get pool address
function getPool(
    address tokenA,
    address tokenB,
    uint24 fee
) external view returns (address pool);
```

### 3. PoolManager.sol
User-facing contract for position management and liquidity operations.

**Key Features:**
- **Position Management**: Mint, increase, decrease, and burn positions
- **Auto-Compounding**: Automatic reinvestment of fees
- **Slippage Protection**: Configurable slippage tolerance
- **Multi-call Support**: Batch multiple operations
- **WETH Integration**: Seamless ETH/WETH handling

**Main Functions:**
```solidity
// Mint a new position
function mint(MintParams calldata params) external payable returns (
    uint256 tokenId,
    uint128 liquidity,
    uint256 amount0,
    uint256 amount1
);

// Increase liquidity
function increaseLiquidity(IncreaseLiquidityParams calldata params) external payable returns (
    uint128 liquidity,
    uint256 amount0,
    uint256 amount1
);

// Decrease liquidity
function decreaseLiquidity(DecreaseLiquidityParams calldata params) external payable returns (
    uint256 amount0,
    uint256 amount1
);

// Collect fees
function collect(CollectParams calldata params) external payable returns (
    uint256 amount0,
    uint256 amount1
);

// Auto-compound fees
function autoCompound(uint256 tokenId) external returns (
    uint128 liquidityAdded
);
```

## Configuration

### Fee Tiers
```javascript
const DEFAULT_FEE_TIERS = [
    { fee: 500, tickSpacing: 10 },      // 0.05% - Stable pairs
    { fee: 3000, tickSpacing: 60 },     // 0.3% - Standard pairs  
    { fee: 10000, tickSpacing: 200 }    // 1% - Exotic pairs
];
```

### Pool Manager Settings
```javascript
const POOL_MANAGER_CONFIG = {
    defaultSlippage: 500,               // 5%
    autoCompoundEnabled: false,         // Disabled by default
    minLiquidityForAutoCompound: "1000" // 1000 tokens minimum
};
```

## Usage Examples

### 1. Creating a Pool

```javascript
// Deploy tokens first
const tokenA = await TokenA.deploy();
const tokenB = await TokenB.deploy();

// Create pool through factory
const tx = await poolFactory.createPool(
    tokenA.address,
    tokenB.address,
    3000 // 0.3% fee
);

const poolAddress = await poolFactory.getPool(
    tokenA.address,
    tokenB.address,
    3000
);
```

### 2. Adding Liquidity

```javascript
// Approve tokens
await tokenA.approve(poolManager.address, amount0);
await tokenB.approve(poolManager.address, amount1);

// Mint position
const mintParams = {
    token0: tokenA.address,
    token1: tokenB.address,
    fee: 3000,
    tickLower: -60,
    tickUpper: 60,
    amount0Desired: ethers.utils.parseEther("100"),
    amount1Desired: ethers.utils.parseEther("100"),
    amount0Min: ethers.utils.parseEther("95"),
    amount1Min: ethers.utils.parseEther("95"),
    recipient: userAddress,
    deadline: Math.floor(Date.now() / 1000) + 3600
};

const result = await poolManager.mint(mintParams);
```

### 3. Swapping Tokens

```javascript
// Approve token for swap
await tokenA.approve(poolAddress, swapAmount);

// Execute swap
const swapTx = await pool.swap(
    recipient,
    true, // zeroForOne
    swapAmount,
    sqrtPriceLimitX96,
    "0x" // callback data
);
```

### 4. Collecting Fees

```javascript
const collectParams = {
    tokenId: positionTokenId,
    recipient: userAddress,
    amount0Max: ethers.constants.MaxUint128,
    amount1Max: ethers.constants.MaxUint128
};

const fees = await poolManager.collect(collectParams);
```

### 5. Auto-Compounding

```javascript
// Enable auto-compound
await poolManager.setAutoCompoundEnabled(true);

// Auto-compound a position
await poolManager.autoCompound(tokenId);
```

## Integration with Other Layers

### Dependencies
- **Layer 1 (Core)**: Access control and security
- **Layer 2 (Token)**: LP tokens, Position NFTs, Token registry

### Used By
- **Layer 4 (Router)**: Path finding and swap routing
- **Layer 5 (Oracle)**: Price observations and TWAP
- **Layer 6 (Quoter)**: Off-chain price calculations

## Security Considerations

### 1. Access Control
- Pool operations are permissionless
- Administrative functions require proper roles
- Emergency pause capabilities

### 2. Slippage Protection
```solidity
modifier checkDeadline(uint256 deadline) {
    require(block.timestamp <= deadline, "PoolManager__DeadlineExpired");
    _;
}

modifier validateSlippage(uint256 amount, uint256 minAmount) {
    require(amount >= minAmount, "PoolManager__TooMuchSlippage");
    _;
}
```

### 3. Reentrancy Protection
All state-changing functions use `nonReentrant` modifier.

### 4. Input Validation
- Tick ranges are validated
- Token addresses are checked
- Amounts are validated for overflow

## Testing

### Running Pool Layer Tests
```bash
# Test all pool contracts
npm run test:pool

# Test specific contract
npx hardhat test test/03-pool/LaxcePool.test.js
npx hardhat test test/03-pool/PoolFactory.test.js
npx hardhat test test/03-pool/PoolManager.test.js
```

### Test Coverage
- **LaxcePool**: Liquidity management, swapping, flash loans, oracle
- **PoolFactory**: Pool creation, fee management, whitelisting
- **PoolManager**: Position management, auto-compounding, callbacks

## Deployment

### Local Development
```bash
npm run deploy:pool
```

### Testnet Deployment
```bash
npm run deploy:pool:testnet
```

### Environment Variables
```bash
# Required for deployment
WETH9_ADDRESS=0x...
TOKEN_REGISTRY_ADDRESS=0x...
POSITION_NFT_ADDRESS=0x...

# Optional
POOL_FACTORY_ADDRESS=0x...
POOL_MANAGER_ADDRESS=0x...
```

## Gas Optimization

### Pool Operations
- **Pool Creation**: ~2,500,000 gas
- **Mint Position**: ~150,000 gas
- **Swap**: ~80,000 gas
- **Burn Position**: ~100,000 gas

### Optimization Techniques
1. **Packed Structs**: Minimize storage slots
2. **Assembly**: Critical math operations
3. **Caching**: Pool address caching in PoolManager
4. **Batch Operations**: Multicall support

## Advanced Features

### 1. Concentrated Liquidity
Users can provide liquidity within specific price ranges:
```javascript
const tickLower = -60; // Lower price bound
const tickUpper = 60;  // Upper price bound
```

### 2. Flash Loans
Built-in flash loan functionality:
```solidity
function flash(
    address recipient,
    uint256 amount0,
    uint256 amount1,
    bytes calldata data
) external;
```

### 3. Oracle Integration
Automatic price observations for TWAP:
```solidity
function increaseObservationCardinalityNext(
    uint16 observationCardinalityNext
) external;
```

### 4. Position NFTs
Each liquidity position is represented as an NFT with unique metadata.

## Monitoring & Analytics

### Key Metrics
- **TVL**: Total Value Locked in pools
- **Volume**: 24h trading volume
- **Fees**: Fees generated and collected
- **APR**: Annual Percentage Rate for LPs

### Events to Monitor
```solidity
event PoolCreated(address indexed token0, address indexed token1, uint24 indexed fee, int24 tickSpacing, address pool);
event Mint(address sender, address indexed owner, int24 indexed tickLower, int24 indexed tickUpper, uint128 amount, uint256 amount0, uint256 amount1);
event Burn(address indexed owner, int24 indexed tickLower, int24 indexed tickUpper, uint128 amount, uint256 amount0, uint256 amount1);
event Swap(address indexed sender, address indexed recipient, int256 amount0, int256 amount1, uint160 sqrtPriceX96, uint128 liquidity, int24 tick);
```

## Troubleshooting

### Common Issues

1. **Pool Not Found**
   - Ensure pool exists for token pair and fee tier
   - Check token address ordering (token0 < token1)

2. **Insufficient Liquidity**
   - Check minimum liquidity requirements
   - Verify tick range is valid

3. **Slippage Too High**
   - Adjust slippage tolerance
   - Check price impact

4. **Transaction Reverted**
   - Verify token approvals
   - Check deadline hasn't expired
   - Ensure sufficient gas limit

### Debug Commands
```bash
# Check pool state
npx hardhat console --network localhost
const pool = await ethers.getContractAt("LaxcePool", poolAddress);
const slot0 = await pool.slot0();
console.log("Current Price:", slot0.sqrtPriceX96.toString());

# Check position
const position = await positionNFT.getPosition(tokenId);
console.log("Liquidity:", position.liquidity.toString());
```

## Future Enhancements

### Planned Features
1. **Dynamic Fees**: Market-based fee adjustment
2. **Range Orders**: Limit order functionality
3. **LP Farming**: Additional reward mechanisms
4. **Cross-Chain Pools**: Multi-chain liquidity
5. **Advanced Analytics**: Real-time metrics dashboard

### Upgrade Path
The Pool Layer uses upgradeable proxy patterns for future enhancements while maintaining backward compatibility.

---

## Summary

The Pool Layer provides a robust foundation for decentralized trading with:
- ✅ Concentrated liquidity for capital efficiency
- ✅ Multiple fee tiers for different market conditions  
- ✅ Flash loan capabilities
- ✅ Auto-compounding for yield optimization
- ✅ Comprehensive position management
- ✅ Oracle integration for price feeds
- ✅ Security-first design with extensive testing

For technical support or questions, refer to the main [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) or create an issue in the repository. 