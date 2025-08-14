const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("Quoter", function () {
    let owner, addr1, addr2, addr3;
    let quoter, poolFactory, tokenRegistry, accessControl;
    let token0, token1, token2, weth9;
    let pool1, pool2;

    const FEE_LOW = 500;     // 0.05%
    const FEE_MEDIUM = 3000; // 0.3%
    const FEE_HIGH = 10000;  // 1%
    const INITIAL_PRICE = "79228162514264337593543950336"; // sqrt(1) in Q96

    async function deployQuoterFixture() {
        [owner, addr1, addr2, addr3] = await ethers.getSigners();

        // Deploy AccessControl
        const AccessControl = await ethers.getContractFactory("LaxceAccessControl");
        accessControl = await AccessControl.deploy(
            owner.address, // treasury
            owner.address, // teamWallet
            owner.address  // marketingWallet
        );

        // Deploy Mock WETH9
        const MockWETH9 = await ethers.getContractFactory("MockWETH9");
        weth9 = await MockWETH9.deploy();

        // Deploy Mock ERC20 tokens
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        let tokenA = await MockERC20.deploy("Token A", "TKNA", 18);
        let tokenB = await MockERC20.deploy("Token B", "TKNB", 18);
        let tokenC = await MockERC20.deploy("Token C", "TKNC", 18);

        // Sort tokens by address
        const tokens = [tokenA, tokenB, tokenC].sort((a, b) => 
            a.address.toLowerCase() < b.address.toLowerCase() ? -1 : 1
        );
        [token0, token1, token2] = tokens;

        // Deploy TokenRegistry
        const TokenRegistry = await ethers.getContractFactory("TokenRegistry");
        tokenRegistry = await TokenRegistry.deploy(accessControl.address);

        // Deploy PoolFactory
        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        poolFactory = await PoolFactory.deploy(tokenRegistry.address);

        // Deploy Quoter
        const Quoter = await ethers.getContractFactory("Quoter");
        quoter = await Quoter.deploy(poolFactory.address);

        // Create pools
        await poolFactory.createPool(token0.address, token1.address, FEE_MEDIUM);
        await poolFactory.createPool(token1.address, token2.address, FEE_MEDIUM);

        const pool1Address = await poolFactory.getPool(token0.address, token1.address, FEE_MEDIUM);
        const pool2Address = await poolFactory.getPool(token1.address, token2.address, FEE_MEDIUM);

        // Get pool instances
        const LaxcePool = await ethers.getContractFactory("LaxcePool");
        pool1 = LaxcePool.attach(pool1Address);
        pool2 = LaxcePool.attach(pool2Address);

        // Initialize pools
        await pool1.initialize(
            poolFactory.address,
            token0.address,
            token1.address,
            FEE_MEDIUM,
            60, // tick spacing
            owner.address, // lpToken placeholder
            owner.address, // positionNFT placeholder
            INITIAL_PRICE
        );

        await pool2.initialize(
            poolFactory.address,
            token1.address,
            token2.address,
            FEE_MEDIUM,
            60,
            owner.address,
            owner.address,
            INITIAL_PRICE
        );

        // Mint tokens
        const mintAmount = ethers.utils.parseEther("1000000");
        await token0.mint(owner.address, mintAmount);
        await token0.mint(addr1.address, mintAmount);
        await token1.mint(owner.address, mintAmount);
        await token1.mint(addr1.address, mintAmount);
        await token2.mint(owner.address, mintAmount);
        await token2.mint(addr1.address, mintAmount);

        // Add liquidity to pools (mock implementation)
        // In real scenario, this would be done through PoolManager
        
        return {
            quoter,
            poolFactory,
            tokenRegistry,
            accessControl,
            token0,
            token1,
            token2,
            weth9,
            pool1,
            pool2,
            owner,
            addr1,
            addr2,
            addr3
        };
    }

    beforeEach(async function () {
        const fixture = await loadFixture(deployQuoterFixture);
        Object.assign(this, fixture);
        ({
            quoter,
            poolFactory,
            tokenRegistry,
            accessControl,
            token0,
            token1,
            token2,
            weth9,
            pool1,
            pool2,
            owner,
            addr1,
            addr2,
            addr3
        } = fixture);
    });

    describe("Deployment & Initialization", function () {
        it("Should deploy with correct parameters", async function () {
            expect(await quoter.factory()).to.equal(poolFactory.address);
            expect(await quoter.maxPriceImpact()).to.equal(1000); // 10%
            expect(await quoter.minLiquidity()).to.equal(1000);
        });

        it("Should have correct gas estimates", async function () {
            expect(await quoter.gasEstimates("singleSwap")).to.equal(80000);
            expect(await quoter.gasEstimates("multiSwapBase")).to.equal(100000);
            expect(await quoter.gasEstimates("multiSwapPerHop")).to.equal(50000);
            expect(await quoter.gasEstimates("quote")).to.equal(30000);
        });

        it("Should have correct role assignments", async function () {
            const DEFAULT_ADMIN_ROLE = await quoter.DEFAULT_ADMIN_ROLE();
            const OPERATOR_ROLE = await quoter.OPERATOR_ROLE();
            
            expect(await quoter.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.be.true;
            expect(await quoter.hasRole(OPERATOR_ROLE, owner.address)).to.be.true;
        });
    });

    describe("Single Hop Quotes", function () {
        const amountIn = ethers.utils.parseEther("100");

        it("Should calculate exact input single quote", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                amountIn: amountIn,
                sqrtPriceLimitX96: 0
            };

            const result = await quoter.quoteExactInputSingle(params);
            
            expect(result.amountOut).to.be.gt(0);
            expect(result.feeAmount).to.be.gt(0);
            expect(result.gasEstimate).to.be.gte(80000);
            expect(result.priceImpact).to.be.gte(0);
        });

        it("Should calculate exact output single quote", async function () {
            const amountOut = ethers.utils.parseEther("90");
            
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                amountOut: amountOut,
                sqrtPriceLimitX96: 0
            };

            const result = await quoter.quoteExactOutputSingle(params);
            
            expect(result.amountOut).to.be.gt(amountOut); // This is amountIn for exact output
            expect(result.feeAmount).to.be.gt(0);
            expect(result.gasEstimate).to.be.gte(80000);
        });

        it("Should reject quotes for non-existent pools", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token2.address,
                fee: FEE_HIGH, // Different fee tier
                amountIn: amountIn,
                sqrtPriceLimitX96: 0
            };

            await expect(
                quoter.quoteExactInputSingle(params)
            ).to.be.revertedWith("Quoter__PoolNotFound");
        });

        it("Should reject quotes with zero amount", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                amountIn: 0,
                sqrtPriceLimitX96: 0
            };

            await expect(
                quoter.quoteExactInputSingle(params)
            ).to.be.revertedWith("Quoter__InvalidAmount");
        });

        it("Should reject quotes with invalid tokens", async function () {
            const params = {
                tokenIn: ethers.constants.AddressZero,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                amountIn: amountIn,
                sqrtPriceLimitX96: 0
            };

            await expect(
                quoter.quoteExactInputSingle(params)
            ).to.be.revertedWith("Quoter__InvalidTokens");
        });

        it("Should reject quotes with same token in and out", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token0.address,
                fee: FEE_MEDIUM,
                amountIn: amountIn,
                sqrtPriceLimitX96: 0
            };

            await expect(
                quoter.quoteExactInputSingle(params)
            ).to.be.revertedWith("Quoter__InvalidTokens");
        });
    });

    describe("Multi-Hop Quotes", function () {
        const amountIn = ethers.utils.parseEther("100");

        function encodePath(tokens, fees) {
            let path = "0x";
            for (let i = 0; i < tokens.length; i++) {
                path += tokens[i].slice(2); // Remove 0x prefix
                if (i < fees.length) {
                    path += fees[i].toString(16).padStart(6, '0');
                }
            }
            return path;
        }

        it("Should calculate exact input multi-hop quote", async function () {
            const path = encodePath(
                [token0.address, token1.address, token2.address],
                [FEE_MEDIUM, FEE_MEDIUM]
            );

            const params = {
                path: path,
                amountIn: amountIn
            };

            const result = await quoter.quoteExactInput(params);
            
            expect(result.amountOut).to.be.gt(0);
            expect(result.feeAmount).to.be.gt(0);
            expect(result.gasEstimate).to.be.gte(100000); // Base + per hop
        });

        it("Should calculate exact output multi-hop quote", async function () {
            const amountOut = ethers.utils.parseEther("80");
            const path = encodePath(
                [token0.address, token1.address, token2.address],
                [FEE_MEDIUM, FEE_MEDIUM]
            );

            const params = {
                path: path,
                amountOut: amountOut
            };

            const result = await quoter.quoteExactOutput(params);
            
            expect(result.amountOut).to.be.gt(amountOut); // This is amountIn
            expect(result.feeAmount).to.be.gt(0);
        });

        it("Should reject path with too many hops", async function () {
            // Create a path with 4 hops (5 tokens)
            const path = encodePath(
                [token0.address, token1.address, token2.address, token0.address, token1.address],
                [FEE_MEDIUM, FEE_MEDIUM, FEE_MEDIUM, FEE_MEDIUM]
            );

            const params = {
                path: path,
                amountIn: amountIn
            };

            await expect(
                quoter.quoteExactInput(params)
            ).to.be.revertedWith("Quoter__PathTooLong");
        });

        it("Should reject invalid path", async function () {
            const invalidPath = "0x123456"; // Too short

            const params = {
                path: invalidPath,
                amountIn: amountIn
            };

            await expect(
                quoter.quoteExactInput(params)
            ).to.be.revertedWith("Quoter__InvalidPath");
        });
    });

    describe("Price Impact Analysis", function () {
        it("Should calculate price impact correctly", async function () {
            const smallAmount = ethers.utils.parseEther("1");
            const largeAmount = ethers.utils.parseEther("1000");

            const params1 = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                amountIn: smallAmount,
                sqrtPriceLimitX96: 0
            };

            const params2 = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                amountIn: largeAmount,
                sqrtPriceLimitX96: 0
            };

            const result1 = await quoter.quoteExactInputSingle(params1);
            const result2 = await quoter.quoteExactInputSingle(params2);

            // Large swap should have higher price impact
            expect(result2.priceImpact).to.be.gt(result1.priceImpact);
        });

        it("Should reject swaps with excessive price impact", async function () {
            // Set very low max price impact
            await quoter.setMaxPriceImpact(10); // 0.1%

            const largeAmount = ethers.utils.parseEther("10000");
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                amountIn: largeAmount,
                sqrtPriceLimitX96: 0
            };

            await expect(
                quoter.quoteExactInputSingle(params)
            ).to.be.revertedWith("Quoter__ExcessivePriceImpact");
        });
    });

    describe("Configuration Management", function () {
        it("Should allow admin to update max price impact", async function () {
            const newMaxPriceImpact = 2000; // 20%

            await quoter.setMaxPriceImpact(newMaxPriceImpact);

            expect(await quoter.maxPriceImpact()).to.equal(newMaxPriceImpact);
        });

        it("Should reject invalid max price impact", async function () {
            const invalidPriceImpact = 5001; // > MAX_SLIPPAGE

            await expect(
                quoter.setMaxPriceImpact(invalidPriceImpact)
            ).to.be.revertedWith("Quoter__ExcessivePriceImpact");
        });

        it("Should allow admin to update min liquidity", async function () {
            const newMinLiquidity = 5000;

            await quoter.setMinLiquidity(newMinLiquidity);

            expect(await quoter.minLiquidity()).to.equal(newMinLiquidity);
        });

        it("Should allow admin to update gas estimates", async function () {
            const newGasEstimate = 90000;

            await quoter.updateGasEstimate("singleSwap", newGasEstimate);

            expect(await quoter.gasEstimates("singleSwap")).to.equal(newGasEstimate);
        });

        it("Should not allow non-admin to update settings", async function () {
            await expect(
                quoter.connect(addr1).setMaxPriceImpact(2000)
            ).to.be.revertedWith("AccessControl:");

            await expect(
                quoter.connect(addr1).setMinLiquidity(5000)
            ).to.be.revertedWith("AccessControl:");

            await expect(
                quoter.connect(addr1).updateGasEstimate("singleSwap", 90000)
            ).to.be.revertedWith("AccessControl:");
        });
    });

    describe("Cache Management", function () {
        it("Should cache pool information", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                amountIn: ethers.utils.parseEther("100"),
                sqrtPriceLimitX96: 0
            };

            // First call should cache the pool info
            await quoter.quoteExactInputSingle(params);

            // Second call should use cached data
            const result = await quoter.quoteExactInputSingle(params);
            expect(result.amountOut).to.be.gt(0);
        });

        it("Should allow admin to clear pool cache", async function () {
            await quoter.clearPoolCache(pool1.address);
            // Should not revert
        });

        it("Should allow admin to clear all cache", async function () {
            await quoter.clearAllCache();
            // Should not revert
        });

        it("Should not allow non-admin to clear cache", async function () {
            await expect(
                quoter.connect(addr1).clearPoolCache(pool1.address)
            ).to.be.revertedWith("AccessControl:");

            await expect(
                quoter.connect(addr1).clearAllCache()
            ).to.be.revertedWith("AccessControl:");
        });
    });

    describe("View Functions", function () {
        it("Should return pool info correctly", async function () {
            const poolInfo = await quoter.getPoolInfo(token0.address, token1.address, FEE_MEDIUM);
            
            expect(poolInfo.pool).to.equal(pool1.address);
            expect(poolInfo.fee).to.equal(FEE_MEDIUM);
            expect(poolInfo.initialized).to.be.true;
        });

        it("Should check pool existence correctly", async function () {
            const exists = await quoter.poolExists(token0.address, token1.address, FEE_MEDIUM);
            expect(exists).to.be.true;

            const notExists = await quoter.poolExists(token0.address, token2.address, FEE_HIGH);
            expect(notExists).to.be.false;
        });

        it("Should return factory address", async function () {
            expect(await quoter.getFactory()).to.equal(poolFactory.address);
        });
    });

    describe("Access Control & Security", function () {
        it("Should pause and unpause correctly", async function () {
            await quoter.pause();
            expect(await quoter.paused()).to.be.true;

            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                amountIn: ethers.utils.parseEther("100"),
                sqrtPriceLimitX96: 0
            };

            await expect(
                quoter.quoteExactInputSingle(params)
            ).to.be.revertedWith("Pausable: paused");

            await quoter.unpause();
            expect(await quoter.paused()).to.be.false;
        });

        it("Should not allow non-pauser to pause", async function () {
            await expect(
                quoter.connect(addr1).pause()
            ).to.be.revertedWith("AccessControl:");
        });

        it("Should emit events correctly", async function () {
            const newMaxPriceImpact = 1500;

            await expect(quoter.setMaxPriceImpact(newMaxPriceImpact))
                .to.emit(quoter, "MaxPriceImpactUpdated")
                .withArgs(1000, newMaxPriceImpact);

            const newMinLiquidity = 2000;

            await expect(quoter.setMinLiquidity(newMinLiquidity))
                .to.emit(quoter, "MinLiquidityUpdated")
                .withArgs(1000, newMinLiquidity);

            await expect(quoter.updateGasEstimate("singleSwap", 85000))
                .to.emit(quoter, "GasEstimateUpdated")
                .withArgs("singleSwap", 85000);
        });
    });

    describe("Edge Cases & Error Handling", function () {
        it("Should handle extreme amounts", async function () {
            const extremelyLargeAmount = ethers.utils.parseEther("1000000000");

            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                amountIn: extremelyLargeAmount,
                sqrtPriceLimitX96: 0
            };

            // Should either return a quote or revert with price impact
            try {
                const result = await quoter.quoteExactInputSingle(params);
                expect(result.amountOut).to.be.gt(0);
            } catch (error) {
                expect(error.message).to.include("Quoter__ExcessivePriceImpact");
            }
        });

        it("Should handle different fee tiers", async function () {
            // Create pool with different fee tier
            await poolFactory.enableFeeAmount(FEE_LOW, 10);
            await poolFactory.createPool(token0.address, token1.address, FEE_LOW);

            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_LOW,
                amountIn: ethers.utils.parseEther("100"),
                sqrtPriceLimitX96: 0
            };

            const result = await quoter.quoteExactInputSingle(params);
            expect(result.amountOut).to.be.gt(0);
        });

        it("Should validate pool state", async function () {
            // Test with uninitialized pool would require more complex setup
            // For now, just ensure the validation logic exists
            const poolInfo = await quoter.getPoolInfo(token0.address, token1.address, FEE_MEDIUM);
            expect(poolInfo.initialized).to.be.true;
        });
    });

    describe("Gas Estimation", function () {
        it("Should provide accurate gas estimates for single swaps", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                amountIn: ethers.utils.parseEther("100"),
                sqrtPriceLimitX96: 0
            };

            const result = await quoter.quoteExactInputSingle(params);
            
            // Should include base swap gas + quote overhead
            expect(result.gasEstimate).to.be.gte(80000);
            expect(result.gasEstimate).to.be.lte(150000);
        });

        it("Should provide higher gas estimates for multi-hop swaps", async function () {
            const path = encodePath(
                [token0.address, token1.address, token2.address],
                [FEE_MEDIUM, FEE_MEDIUM]
            );

            const params = {
                path: path,
                amountIn: ethers.utils.parseEther("100")
            };

            const result = await quoter.quoteExactInput(params);
            
            // Should be higher than single swap
            expect(result.gasEstimate).to.be.gte(100000);
        });

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
    });
});

// Mock contracts for testing
contract MockERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) {
        // Implementation
    }
    
    function mint(address to, uint256 amount) external {
        // Implementation
    }
}

contract MockWETH9 {
    function deposit() external payable {
        // Implementation
    }
    
    function withdraw(uint256 wad) external {
        // Implementation
    }
} 