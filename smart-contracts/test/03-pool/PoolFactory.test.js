const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("PoolFactory", function () {
    let owner, addr1, addr2, addr3;
    let poolFactory, tokenRegistry, accessControl;
    let token0, token1, token2, token3;

    const FEE_LOW = 500;     // 0.05%
    const FEE_MEDIUM = 3000; // 0.3%
    const FEE_HIGH = 10000;  // 1%
    const TICK_SPACING_LOW = 10;
    const TICK_SPACING_MEDIUM = 60;
    const TICK_SPACING_HIGH = 200;

    async function deployFactoryFixture() {
        [owner, addr1, addr2, addr3] = await ethers.getSigners();

        // Deploy AccessControl
        const AccessControl = await ethers.getContractFactory("LaxceAccessControl");
        accessControl = await AccessControl.deploy(
            owner.address, // treasury
            owner.address, // teamWallet
            owner.address  // marketingWallet
        );

        // Deploy TokenRegistry
        const TokenRegistry = await ethers.getContractFactory("TokenRegistry");
        tokenRegistry = await TokenRegistry.deploy(accessControl.address);

        // Deploy PoolFactory
        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        poolFactory = await PoolFactory.deploy(tokenRegistry.address);

        // Deploy Mock ERC20 tokens
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        
        // Create 4 tokens and sort them
        const tokens = [];
        for (let i = 0; i < 4; i++) {
            const token = await MockERC20.deploy(`Token ${i}`, `TKN${i}`, 18);
            tokens.push(token);
        }

        // Sort tokens by address for consistent ordering
        tokens.sort((a, b) => {
            return a.address.toLowerCase() < b.address.toLowerCase() ? -1 : 1;
        });

        [token0, token1, token2, token3] = tokens;

        return {
            poolFactory,
            tokenRegistry,
            accessControl,
            token0,
            token1,
            token2,
            token3,
            owner,
            addr1,
            addr2,
            addr3
        };
    }

    beforeEach(async function () {
        const fixture = await loadFixture(deployFactoryFixture);
        Object.assign(this, fixture);
        ({
            poolFactory,
            tokenRegistry,
            accessControl,
            token0,
            token1,
            token2,
            token3,
            owner,
            addr1,
            addr2,
            addr3
        } = fixture);
    });

    describe("Deployment & Initialization", function () {
        it("Should deploy with correct parameters", async function () {
            expect(await poolFactory.tokenRegistry()).to.equal(tokenRegistry.address);
            expect(await poolFactory.owner()).to.equal(owner.address);
            expect(await poolFactory.whitelistMode()).to.be.false;
        });

        it("Should have default fee tiers enabled", async function () {
            const lowTier = await poolFactory.feeAmountTickSpacing(FEE_LOW);
            expect(lowTier).to.equal(TICK_SPACING_LOW);

            const mediumTier = await poolFactory.feeAmountTickSpacing(FEE_MEDIUM);
            expect(mediumTier).to.equal(TICK_SPACING_MEDIUM);

            const highTier = await poolFactory.feeAmountTickSpacing(FEE_HIGH);
            expect(highTier).to.equal(TICK_SPACING_HIGH);
        });

        it("Should have correct initial state", async function () {
            expect(await poolFactory.allPoolsLength()).to.equal(0);
            
            const stats = await poolFactory.getFactoryStats();
            expect(stats.totalPools).to.equal(0);
            expect(stats.activePools).to.equal(0);
            expect(stats.totalVolume24h).to.equal(0);
            expect(stats.totalFees24h).to.equal(0);
        });
    });

    describe("Pool Creation", function () {
        it("Should create pool with valid parameters", async function () {
            const createTx = await poolFactory.createPool(
                token0.address,
                token1.address,
                FEE_MEDIUM
            );

            await expect(createTx)
                .to.emit(poolFactory, "PoolCreated")
                .withArgs(
                    token0.address,
                    token1.address,
                    FEE_MEDIUM,
                    TICK_SPACING_MEDIUM,
                    // Pool address will be determined by CREATE2
                    await poolFactory.getPool(token0.address, token1.address, FEE_MEDIUM)
                );

            const poolAddress = await poolFactory.getPool(token0.address, token1.address, FEE_MEDIUM);
            expect(poolAddress).to.not.equal(ethers.constants.AddressZero);

            expect(await poolFactory.allPoolsLength()).to.equal(1);
        });

        it("Should create multiple pools for same token pair with different fees", async function () {
            await poolFactory.createPool(token0.address, token1.address, FEE_LOW);
            await poolFactory.createPool(token0.address, token1.address, FEE_MEDIUM);
            await poolFactory.createPool(token0.address, token1.address, FEE_HIGH);

            const poolLow = await poolFactory.getPool(token0.address, token1.address, FEE_LOW);
            const poolMedium = await poolFactory.getPool(token0.address, token1.address, FEE_MEDIUM);
            const poolHigh = await poolFactory.getPool(token0.address, token1.address, FEE_HIGH);

            expect(poolLow).to.not.equal(poolMedium);
            expect(poolMedium).to.not.equal(poolHigh);
            expect(poolLow).to.not.equal(poolHigh);

            expect(await poolFactory.allPoolsLength()).to.equal(3);
        });

        it("Should reject pool creation with identical tokens", async function () {
            await expect(
                poolFactory.createPool(token0.address, token0.address, FEE_MEDIUM)
            ).to.be.revertedWith("Factory__IdenticalAddresses");
        });

        it("Should reject pool creation with zero address", async function () {
            await expect(
                poolFactory.createPool(ethers.constants.AddressZero, token1.address, FEE_MEDIUM)
            ).to.be.revertedWith("Factory__ZeroAddress");

            await expect(
                poolFactory.createPool(token0.address, ethers.constants.AddressZero, FEE_MEDIUM)
            ).to.be.revertedWith("Factory__ZeroAddress");
        });

        it("Should reject pool creation with unsupported fee", async function () {
            const unsupportedFee = 1500; // Not enabled by default
            
            await expect(
                poolFactory.createPool(token0.address, token1.address, unsupportedFee)
            ).to.be.revertedWith("Factory__FeeNotSupported");
        });

        it("Should reject duplicate pool creation", async function () {
            await poolFactory.createPool(token0.address, token1.address, FEE_MEDIUM);
            
            await expect(
                poolFactory.createPool(token0.address, token1.address, FEE_MEDIUM)
            ).to.be.revertedWith("Factory__PoolExists");
        });

        it("Should handle token ordering correctly", async function () {
            // Create pool with tokens in different order
            await poolFactory.createPool(token1.address, token0.address, FEE_MEDIUM);
            
            // Should return same pool regardless of order
            const pool1 = await poolFactory.getPool(token0.address, token1.address, FEE_MEDIUM);
            const pool2 = await poolFactory.getPool(token1.address, token0.address, FEE_MEDIUM);
            
            expect(pool1).to.equal(pool2);
            expect(pool1).to.not.equal(ethers.constants.AddressZero);
        });
    });

    describe("Fee Tier Management", function () {
        it("Should enable new fee tier", async function () {
            const newFee = 1500;
            const newTickSpacing = 30;

            const enableTx = await poolFactory.enableFeeAmount(newFee, newTickSpacing);
            
            await expect(enableTx)
                .to.emit(poolFactory, "FeeAmountEnabled")
                .withArgs(newFee, newTickSpacing);

            expect(await poolFactory.feeAmountTickSpacing(newFee)).to.equal(newTickSpacing);
        });

        it("Should disable existing fee tier", async function () {
            const disableTx = await poolFactory.disableFeeAmount(FEE_HIGH);
            
            await expect(disableTx)
                .to.emit(poolFactory, "FeeAmountDisabled")
                .withArgs(FEE_HIGH);

            expect(await poolFactory.feeAmountTickSpacing(FEE_HIGH)).to.equal(0);
        });

        it("Should not allow enabling fee tier with zero tick spacing", async function () {
            await expect(
                poolFactory.enableFeeAmount(1500, 0)
            ).to.be.revertedWith("Factory__InvalidTickSpacing");
        });

        it("Should not allow enabling fee tier with too large tick spacing", async function () {
            const maxTickSpacing = 16384;
            
            await expect(
                poolFactory.enableFeeAmount(1500, maxTickSpacing + 1)
            ).to.be.revertedWith("Factory__InvalidTickSpacing");
        });

        it("Should not allow non-owner to manage fee tiers", async function () {
            await expect(
                poolFactory.connect(addr1).enableFeeAmount(1500, 30)
            ).to.be.revertedWith("Factory__NotOwner");

            await expect(
                poolFactory.connect(addr1).disableFeeAmount(FEE_HIGH)
            ).to.be.revertedWith("Factory__NotOwner");
        });

        it("Should get all enabled fee tiers", async function () {
            const enabledTiers = await poolFactory.getEnabledFeeTiers();
            
            expect(enabledTiers.length).to.be.gte(3); // At least default tiers
            expect(enabledTiers).to.include(FEE_LOW);
            expect(enabledTiers).to.include(FEE_MEDIUM);
            expect(enabledTiers).to.include(FEE_HIGH);
        });
    });

    describe("Token Whitelisting", function () {
        it("Should enable whitelist mode", async function () {
            const toggleTx = await poolFactory.setWhitelistMode(true);
            
            await expect(toggleTx)
                .to.emit(poolFactory, "WhitelistModeToggled")
                .withArgs(true);

            expect(await poolFactory.whitelistMode()).to.be.true;
        });

        it("Should whitelist token", async function () {
            await poolFactory.setWhitelistMode(true);
            
            const whitelistTx = await poolFactory.setTokenWhitelist(token0.address, true);
            
            await expect(whitelistTx)
                .to.emit(poolFactory, "TokenWhitelisted")
                .withArgs(token0.address, true);

            expect(await poolFactory.whitelistedTokens(token0.address)).to.be.true;
        });

        it("Should whitelist multiple tokens in batch", async function () {
            await poolFactory.setWhitelistMode(true);
            
            const tokens = [token0.address, token1.address, token2.address];
            const statuses = [true, true, false];
            
            const batchTx = await poolFactory.setTokenWhitelistBatch(tokens, statuses);
            
            expect(await poolFactory.whitelistedTokens(token0.address)).to.be.true;
            expect(await poolFactory.whitelistedTokens(token1.address)).to.be.true;
            expect(await poolFactory.whitelistedTokens(token2.address)).to.be.false;
        });

        it("Should reject pool creation with non-whitelisted tokens", async function () {
            await poolFactory.setWhitelistMode(true);
            await poolFactory.setTokenWhitelist(token0.address, true);
            // token1 is not whitelisted
            
            await expect(
                poolFactory.createPool(token0.address, token1.address, FEE_MEDIUM)
            ).to.be.revertedWith("Factory__TokenNotWhitelisted");
        });

        it("Should allow pool creation with whitelisted tokens", async function () {
            await poolFactory.setWhitelistMode(true);
            await poolFactory.setTokenWhitelist(token0.address, true);
            await poolFactory.setTokenWhitelist(token1.address, true);
            
            await expect(
                poolFactory.createPool(token0.address, token1.address, FEE_MEDIUM)
            ).to.not.be.reverted;
        });

        it("Should not affect pool creation when whitelist mode is disabled", async function () {
            expect(await poolFactory.whitelistMode()).to.be.false;
            
            await expect(
                poolFactory.createPool(token0.address, token1.address, FEE_MEDIUM)
            ).to.not.be.reverted;
        });
    });

    describe("Pool Management", function () {
        beforeEach(async function () {
            // Create some pools for testing
            await poolFactory.createPool(token0.address, token1.address, FEE_LOW);
            await poolFactory.createPool(token0.address, token1.address, FEE_MEDIUM);
            await poolFactory.createPool(token0.address, token2.address, FEE_MEDIUM);
        });

        it("Should set pool status", async function () {
            const poolAddress = await poolFactory.getPool(token0.address, token1.address, FEE_MEDIUM);
            
            const statusTx = await poolFactory.setPoolStatus(poolAddress, false);
            
            await expect(statusTx)
                .to.emit(poolFactory, "PoolStatusUpdated")
                .withArgs(poolAddress, false);
        });

        it("Should update pool statistics", async function () {
            const poolAddress = await poolFactory.getPool(token0.address, token1.address, FEE_MEDIUM);
            const newLiquidity = ethers.utils.parseEther("1000");
            const newVolume = ethers.utils.parseEther("5000");
            const newFees = ethers.utils.parseEther("15");
            
            await poolFactory.updatePoolStats(
                poolAddress,
                newLiquidity,
                newVolume,
                newFees
            );
            
            const poolInfo = await poolFactory.poolInfo(poolAddress);
            expect(poolInfo.liquidity).to.equal(newLiquidity);
            expect(poolInfo.volume24h).to.equal(newVolume);
            expect(poolInfo.fees24h).to.equal(newFees);
        });

        it("Should get pools for token pair", async function () {
            const pools = await poolFactory.getPoolsForPair(token0.address, token1.address);
            
            expect(pools.length).to.equal(2); // LOW and MEDIUM fee tiers
            expect(pools[0]).to.not.equal(ethers.constants.AddressZero);
            expect(pools[1]).to.not.equal(ethers.constants.AddressZero);
        });

        it("Should get active pools", async function () {
            const activePools = await poolFactory.getActivePools();
            
            expect(activePools.length).to.equal(3); // All pools are active by default
        });

        it("Should get factory statistics", async function () {
            const stats = await poolFactory.getFactoryStats();
            
            expect(stats.totalPools).to.equal(3);
            expect(stats.activePools).to.equal(3);
            expect(stats.enabledFeeTiers).to.be.gte(3);
        });
    });

    describe("Access Control & Security", function () {
        it("Should allow only owner to change owner", async function () {
            const newOwner = addr1.address;
            
            const changeTx = await poolFactory.setOwner(newOwner);
            
            await expect(changeTx)
                .to.emit(poolFactory, "OwnerChanged")
                .withArgs(owner.address, newOwner);

            expect(await poolFactory.owner()).to.equal(newOwner);
        });

        it("Should reject unauthorized owner changes", async function () {
            await expect(
                poolFactory.connect(addr1).setOwner(addr2.address)
            ).to.be.revertedWith("Factory__NotOwner");
        });

        it("Should allow only owner to update token registry", async function () {
            // Deploy new token registry
            const NewTokenRegistry = await ethers.getContractFactory("TokenRegistry");
            const newTokenRegistry = await NewTokenRegistry.deploy(accessControl.address);
            
            const updateTx = await poolFactory.setTokenRegistry(newTokenRegistry.address);
            
            await expect(updateTx)
                .to.emit(poolFactory, "TokenRegistryUpdated")
                .withArgs(tokenRegistry.address, newTokenRegistry.address);

            expect(await poolFactory.tokenRegistry()).to.equal(newTokenRegistry.address);
        });

        it("Should pause and unpause correctly", async function () {
            await poolFactory.pause();
            expect(await poolFactory.paused()).to.be.true;

            // Should reject pool creation when paused
            await expect(
                poolFactory.createPool(token2.address, token3.address, FEE_MEDIUM)
            ).to.be.revertedWith("Pausable: paused");

            await poolFactory.unpause();
            expect(await poolFactory.paused()).to.be.false;

            // Should allow pool creation when unpaused
            await expect(
                poolFactory.createPool(token2.address, token3.address, FEE_MEDIUM)
            ).to.not.be.reverted;
        });

        it("Should reject operations from non-authorized users", async function () {
            await expect(
                poolFactory.connect(addr1).pause()
            ).to.be.revertedWith("AccessControl:");

            await expect(
                poolFactory.connect(addr1).setTokenRegistry(tokenRegistry.address)
            ).to.be.revertedWith("Factory__NotOwner");
        });
    });

    describe("Edge Cases & Error Handling", function () {
        it("Should handle maximum number of pools", async function () {
            // This test might be expensive, so we'll just check the logic
            const maxPools = await poolFactory.MAX_POOLS();
            expect(maxPools).to.equal(100000);
        });

        it("Should reject invalid tick spacing values", async function () {
            await expect(
                poolFactory.enableFeeAmount(1500, 0)
            ).to.be.revertedWith("Factory__InvalidTickSpacing");

            await expect(
                poolFactory.enableFeeAmount(1500, 16385) // MAX + 1
            ).to.be.revertedWith("Factory__InvalidTickSpacing");
        });

        it("Should handle token registry updates", async function () {
            const NewTokenRegistry = await ethers.getContractFactory("TokenRegistry");
            const newRegistry = await NewTokenRegistry.deploy(accessControl.address);
            
            await poolFactory.setTokenRegistry(newRegistry.address);
            
            // Should still be able to create pools with new registry
            await expect(
                poolFactory.createPool(token2.address, token3.address, FEE_MEDIUM)
            ).to.not.be.reverted;
        });

        it("Should revert with proper error messages", async function () {
            // Test various error conditions
            await expect(
                poolFactory.getPool(ethers.constants.AddressZero, token1.address, FEE_MEDIUM)
            ).to.be.revertedWith("Factory__ZeroAddress");

            await expect(
                poolFactory.createPool(token0.address, token1.address, 99999) // Invalid fee
            ).to.be.revertedWith("Factory__FeeNotSupported");
        });
    });

    describe("View Functions", function () {
        beforeEach(async function () {
            await poolFactory.createPool(token0.address, token1.address, FEE_MEDIUM);
            await poolFactory.createPool(token1.address, token2.address, FEE_HIGH);
        });

        it("Should return correct pool count", async function () {
            expect(await poolFactory.allPoolsLength()).to.equal(2);
        });

        it("Should return pool address by index", async function () {
            const pool0 = await poolFactory.allPools(0);
            const pool1 = await poolFactory.allPools(1);
            
            expect(pool0).to.not.equal(ethers.constants.AddressZero);
            expect(pool1).to.not.equal(ethers.constants.AddressZero);
            expect(pool0).to.not.equal(pool1);
        });

        it("Should return correct pool info", async function () {
            const poolAddress = await poolFactory.getPool(token0.address, token1.address, FEE_MEDIUM);
            const poolInfo = await poolFactory.poolInfo(poolAddress);
            
            expect(poolInfo.token0).to.equal(token0.address);
            expect(poolInfo.token1).to.equal(token1.address);
            expect(poolInfo.fee).to.equal(FEE_MEDIUM);
            expect(poolInfo.active).to.be.true;
            expect(poolInfo.pool).to.equal(poolAddress);
        });

        it("Should return enabled fee tiers", async function () {
            const enabledTiers = await poolFactory.getEnabledFeeTiers();
            
            expect(enabledTiers).to.include(FEE_LOW);
            expect(enabledTiers).to.include(FEE_MEDIUM);
            expect(enabledTiers).to.include(FEE_HIGH);
        });
    });
});

// Additional helper function for testing
async function createPoolsForTesting(poolFactory, tokens, fees) {
    const pools = [];
    
    for (let i = 0; i < tokens.length - 1; i++) {
        for (let j = i + 1; j < tokens.length; j++) {
            for (const fee of fees) {
                await poolFactory.createPool(tokens[i].address, tokens[j].address, fee);
                const poolAddress = await poolFactory.getPool(tokens[i].address, tokens[j].address, fee);
                pools.push(poolAddress);
            }
        }
    }
    
    return pools;
} 