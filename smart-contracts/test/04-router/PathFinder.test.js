const { expect } = require("chai");
const { ethers } = require("hardhat");
const { 
  loadFixture, 
  time,
  helpers 
} = require("@nomicfoundation/hardhat-network-helpers");

describe("PathFinder", function () {
  // Test fixture
  async function deployPathFinderFixture() {
    const [owner, user1, user2, treasury, operator] = await ethers.getSigners();

    // Deploy AccessControl
    const LaxceAccessControl = await ethers.getContractFactory("LaxceAccessControl");
    const accessControl = await LaxceAccessControl.deploy();
    await accessControl.waitForDeployment();

    // Deploy Constants library
    const Constants = await ethers.getContractFactory("Constants");
    const constants = await Constants.deploy();
    await constants.waitForDeployment();

    // Deploy ReentrancyGuard library
    const ReentrancyGuard = await ethers.getContractFactory("ReentrancyGuard");
    const reentrancyGuard = await ReentrancyGuard.deploy();
    await reentrancyGuard.waitForDeployment();

    // Deploy TickMath library
    const TickMath = await ethers.getContractFactory("TickMath");
    const tickMath = await TickMath.deploy();
    await tickMath.waitForDeployment();

    // Deploy FeeManager library
    const FeeManager = await ethers.getContractFactory("FeeManager");
    const feeManager = await FeeManager.deploy();
    await feeManager.waitForDeployment();

    // Deploy TokenRegistry
    const TokenRegistry = await ethers.getContractFactory("TokenRegistry", {
      libraries: {
        Constants: await constants.getAddress(),
        ReentrancyGuard: await reentrancyGuard.getAddress()
      }
    });
    const tokenRegistry = await TokenRegistry.deploy();
    await tokenRegistry.waitForDeployment();

    // Deploy PoolFactory
    const PoolFactory = await ethers.getContractFactory("PoolFactory", {
      libraries: {
        Constants: await constants.getAddress(),
        ReentrancyGuard: await reentrancyGuard.getAddress()
      }
    });
    const poolFactory = await PoolFactory.deploy(await tokenRegistry.getAddress());
    await poolFactory.waitForDeployment();

    // Deploy PathFinder
    const PathFinder = await ethers.getContractFactory("PathFinder", {
      libraries: {
        Constants: await constants.getAddress(),
        TickMath: await tickMath.getAddress(),
        FeeManager: await feeManager.getAddress(),
        ReentrancyGuard: await reentrancyGuard.getAddress()
      }
    });
    const pathFinder = await PathFinder.deploy(await poolFactory.getAddress());
    await pathFinder.waitForDeployment();

    // Deploy mock tokens
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const tokenA = await MockERC20.deploy("Token A", "TKNA", 18);
    const tokenB = await MockERC20.deploy("Token B", "TKNB", 18);
    const tokenC = await MockERC20.deploy("Token C", "TKNC", 18);
    const tokenD = await MockERC20.deploy("Token D", "TKND", 18);
    await tokenA.waitForDeployment();
    await tokenB.waitForDeployment();
    await tokenC.waitForDeployment();
    await tokenD.waitForDeployment();

    // Deploy mock pools
    const MockPool = await ethers.getContractFactory("MockLaxcePool");
    const poolAB = await MockPool.deploy(
      await tokenA.getAddress(),
      await tokenB.getAddress(),
      3000, // 0.3% fee
      ethers.parseEther("1000000"), // 1M liquidity
      "1461446703485210103287273052203988822378723970341" // sqrt price
    );
    const poolBC = await MockPool.deploy(
      await tokenB.getAddress(),
      await tokenC.getAddress(),
      3000,
      ethers.parseEther("500000"),
      "1461446703485210103287273052203988822378723970341"
    );
    const poolCD = await MockPool.deploy(
      await tokenC.getAddress(),
      await tokenD.getAddress(),
      3000,
      ethers.parseEther("750000"),
      "1461446703485210103287273052203988822378723970341"
    );
    await poolAB.waitForDeployment();
    await poolBC.waitForDeployment();
    await poolCD.waitForDeployment();

    // Grant operator role
    const OPERATOR_ROLE = await pathFinder.OPERATOR_ROLE();
    await pathFinder.grantRole(OPERATOR_ROLE, operator.address);

    return {
      pathFinder,
      poolFactory,
      tokenRegistry,
      owner,
      user1,
      user2,
      treasury,
      operator,
      tokenA,
      tokenB,
      tokenC,
      tokenD,
      poolAB,
      poolBC,
      poolCD,
      constants,
      reentrancyGuard,
      tickMath,
      feeManager
    };
  }

  describe("Deployment", function () {
    it("Should deploy with correct factory address", async function () {
      const { pathFinder, poolFactory } = await loadFixture(deployPathFinderFixture);
      
      expect(await pathFinder.factory()).to.equal(await poolFactory.getAddress());
    });

    it("Should set correct default values", async function () {
      const { pathFinder } = await loadFixture(deployPathFinderFixture);
      
      expect(await pathFinder.cacheTimeout()).to.equal(300); // 5 minutes
      expect(await pathFinder.maxSlippageDefault()).to.equal(50); // 0.5%
      expect(await pathFinder.useCache()).to.equal(true);
    });

    it("Should grant DEFAULT_ADMIN_ROLE to deployer", async function () {
      const { pathFinder, owner } = await loadFixture(deployPathFinderFixture);
      
      const DEFAULT_ADMIN_ROLE = await pathFinder.DEFAULT_ADMIN_ROLE();
      expect(await pathFinder.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.be.true;
    });
  });

  describe("Pool Information Management", function () {
    it("Should update pool information", async function () {
      const { pathFinder, poolAB, tokenA, tokenB } = await loadFixture(deployPathFinderFixture);
      
      await pathFinder.updatePoolInfo(await poolAB.getAddress());
      
      const poolInfo = await pathFinder.poolInfo(await poolAB.getAddress());
      expect(poolInfo.pool).to.equal(await poolAB.getAddress());
      expect(poolInfo.token0).to.equal(await tokenA.getAddress());
      expect(poolInfo.token1).to.equal(await tokenB.getAddress());
      expect(poolInfo.fee).to.equal(3000);
    });

    it("Should update token connections", async function () {
      const { pathFinder, poolAB, tokenA, tokenB } = await loadFixture(deployPathFinderFixture);
      
      await pathFinder.updatePoolInfo(await poolAB.getAddress());
      
      const connectedTokensA = await pathFinder.getConnectedTokens(await tokenA.getAddress());
      const connectedTokensB = await pathFinder.getConnectedTokens(await tokenB.getAddress());
      
      expect(connectedTokensA).to.include(await tokenB.getAddress());
      expect(connectedTokensB).to.include(await tokenA.getAddress());
    });

    it("Should batch update multiple pools", async function () {
      const { pathFinder, poolAB, poolBC, poolCD, operator } = await loadFixture(deployPathFinderFixture);
      
      const pools = [
        await poolAB.getAddress(),
        await poolBC.getAddress(),
        await poolCD.getAddress()
      ];
      
      await pathFinder.connect(operator).batchUpdatePoolInfo(pools);
      
      // Check that all pools were updated
      for (const pool of pools) {
        const poolInfo = await pathFinder.poolInfo(pool);
        expect(poolInfo.pool).to.equal(pool);
        expect(poolInfo.lastUpdate).to.be.gt(0);
      }
    });

    it("Should revert when updating invalid pool", async function () {
      const { pathFinder } = await loadFixture(deployPathFinderFixture);
      
      await expect(
        pathFinder.updatePoolInfo(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(pathFinder, "PathFinder__InvalidPool");
    });
  });

  describe("Path Finding", function () {
    beforeEach(async function () {
      // Setup pools for each test
      const { pathFinder, poolAB, poolBC, poolCD } = await loadFixture(deployPathFinderFixture);
      
      await pathFinder.updatePoolInfo(await poolAB.getAddress());
      await pathFinder.updatePoolInfo(await poolBC.getAddress());
      await pathFinder.updatePoolInfo(await poolCD.getAddress());
    });

    it("Should find direct path for single hop", async function () {
      const { pathFinder, tokenA, tokenB } = await loadFixture(deployPathFinderFixture);
      
      const amountIn = ethers.parseEther("100");
      const path = await pathFinder.findOptimalPath(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        amountIn,
        100 // 1% slippage
      );
      
      expect(path.isValid).to.be.true;
      expect(path.tokens.length).to.equal(2);
      expect(path.tokens[0]).to.equal(await tokenA.getAddress());
      expect(path.tokens[1]).to.equal(await tokenB.getAddress());
      expect(path.fees.length).to.equal(1);
      expect(path.pools.length).to.equal(1);
    });

    it("Should find multi-hop path when direct path not available", async function () {
      const { pathFinder, tokenA, tokenC } = await loadFixture(deployPathFinderFixture);
      
      const amountIn = ethers.parseEther("100");
      const path = await pathFinder.findOptimalPath(
        await tokenA.getAddress(),
        await tokenC.getAddress(),
        amountIn,
        100 // 1% slippage
      );
      
      expect(path.isValid).to.be.true;
      expect(path.tokens.length).to.equal(3); // A -> B -> C
      expect(path.tokens[0]).to.equal(await tokenA.getAddress());
      expect(path.tokens[2]).to.equal(await tokenC.getAddress());
      expect(path.fees.length).to.equal(2);
      expect(path.pools.length).to.equal(2);
    });

    it("Should find multiple paths", async function () {
      const { pathFinder, tokenA, tokenB } = await loadFixture(deployPathFinderFixture);
      
      const amountIn = ethers.parseEther("100");
      const paths = await pathFinder.findMultiplePaths(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        amountIn,
        3 // Request 3 paths
      );
      
      expect(paths.length).to.be.gt(0);
      expect(paths[0].isValid).to.be.true;
    });

    it("Should check if path exists", async function () {
      const { pathFinder, tokenA, tokenB, tokenC } = await loadFixture(deployPathFinderFixture);
      
      // Direct path should exist
      expect(await pathFinder.hasPath(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        1
      )).to.be.true;
      
      // Multi-hop path should exist
      expect(await pathFinder.hasPath(
        await tokenA.getAddress(),
        await tokenC.getAddress(),
        2
      )).to.be.true;
    });

    it("Should return same token for identical addresses", async function () {
      const { pathFinder, tokenA } = await loadFixture(deployPathFinderFixture);
      
      expect(await pathFinder.hasPath(
        await tokenA.getAddress(),
        await tokenA.getAddress(),
        1
      )).to.be.true;
    });
  });

  describe("Quote Functions", function () {
    beforeEach(async function () {
      const { pathFinder, poolAB } = await loadFixture(deployPathFinderFixture);
      await pathFinder.updatePoolInfo(await poolAB.getAddress());
    });

    it("Should get amount out for exact input", async function () {
      const { pathFinder, tokenA, tokenB } = await loadFixture(deployPathFinderFixture);
      
      const amountIn = ethers.parseEther("100");
      const [amountOut, priceImpact, path] = await pathFinder.getAmountOut(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        amountIn
      );
      
      expect(amountOut).to.be.gt(0);
      expect(priceImpact).to.be.gte(0);
      expect(path.isValid).to.be.true;
    });

    it("Should get amount in for exact output", async function () {
      const { pathFinder, tokenA, tokenB } = await loadFixture(deployPathFinderFixture);
      
      const amountOut = ethers.parseEther("100");
      const [amountIn, priceImpact, path] = await pathFinder.getAmountIn(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        amountOut
      );
      
      expect(amountIn).to.be.gt(0);
      expect(priceImpact).to.be.gte(0);
      expect(path.isValid).to.be.true;
    });

    it("Should revert for invalid token pair", async function () {
      const { pathFinder, tokenA } = await loadFixture(deployPathFinderFixture);
      
      await expect(
        pathFinder.getAmountOut(
          await tokenA.getAddress(),
          ethers.ZeroAddress,
          ethers.parseEther("100")
        )
      ).to.be.revertedWithCustomError(pathFinder, "PathFinder__InvalidTokens");
    });
  });

  describe("Configuration", function () {
    it("Should allow admin to update configuration", async function () {
      const { pathFinder, owner } = await loadFixture(deployPathFinderFixture);
      
      const newCacheTimeout = 600; // 10 minutes
      const newMaxSlippage = 100; // 1%
      const newUseCache = false;
      
      await pathFinder.setConfiguration(newCacheTimeout, newMaxSlippage, newUseCache);
      
      expect(await pathFinder.cacheTimeout()).to.equal(newCacheTimeout);
      expect(await pathFinder.maxSlippageDefault()).to.equal(newMaxSlippage);
      expect(await pathFinder.useCache()).to.equal(newUseCache);
    });

    it("Should emit ConfigurationUpdated event", async function () {
      const { pathFinder } = await loadFixture(deployPathFinderFixture);
      
      const newCacheTimeout = 600;
      const newMaxSlippage = 100;
      const newUseCache = false;
      
      await expect(
        pathFinder.setConfiguration(newCacheTimeout, newMaxSlippage, newUseCache)
      ).to.emit(pathFinder, "ConfigurationUpdated")
        .withArgs(newCacheTimeout, newMaxSlippage, newUseCache);
    });

    it("Should revert with invalid cache timeout", async function () {
      const { pathFinder } = await loadFixture(deployPathFinderFixture);
      
      await expect(
        pathFinder.setConfiguration(3700, 100, true) // > 1 hour
      ).to.be.revertedWithCustomError(pathFinder, "PathFinder__InvalidTokens");
    });

    it("Should revert with invalid max slippage", async function () {
      const { pathFinder } = await loadFixture(deployPathFinderFixture);
      
      await expect(
        pathFinder.setConfiguration(600, 1100, true) // > 10%
      ).to.be.revertedWithCustomError(pathFinder, "PathFinder__InvalidTokens");
    });
  });

  describe("Access Control", function () {
    it("Should allow only admin to set configuration", async function () {
      const { pathFinder, user1 } = await loadFixture(deployPathFinderFixture);
      
      await expect(
        pathFinder.connect(user1).setConfiguration(600, 100, false)
      ).to.be.reverted;
    });

    it("Should allow only operator to batch update pools", async function () {
      const { pathFinder, user1, poolAB } = await loadFixture(deployPathFinderFixture);
      
      await expect(
        pathFinder.connect(user1).batchUpdatePoolInfo([await poolAB.getAddress()])
      ).to.be.reverted;
    });

    it("Should allow only pauser to pause", async function () {
      const { pathFinder, user1 } = await loadFixture(deployPathFinderFixture);
      
      await expect(
        pathFinder.connect(user1).pause()
      ).to.be.reverted;
    });
  });

  describe("Pause Functionality", function () {
    it("Should allow pauser to pause and unpause", async function () {
      const { pathFinder, owner } = await loadFixture(deployPathFinderFixture);
      
      // Grant pauser role to owner
      const PAUSER_ROLE = await pathFinder.PAUSER_ROLE();
      await pathFinder.grantRole(PAUSER_ROLE, owner.address);
      
      await pathFinder.pause();
      expect(await pathFinder.paused()).to.be.true;
      
      await pathFinder.unpause();
      expect(await pathFinder.paused()).to.be.false;
    });
  });

  describe("View Functions", function () {
    beforeEach(async function () {
      const { pathFinder, poolAB } = await loadFixture(deployPathFinderFixture);
      await pathFinder.updatePoolInfo(await poolAB.getAddress());
    });

    it("Should get pool statistics", async function () {
      const { pathFinder, poolAB } = await loadFixture(deployPathFinderFixture);
      
      const [liquidity, sqrtPriceX96, tick, lastUpdate] = await pathFinder.getPoolStats(
        await poolAB.getAddress()
      );
      
      expect(liquidity).to.be.gt(0);
      expect(sqrtPriceX96).to.be.gt(0);
      expect(lastUpdate).to.be.gt(0);
    });

    it("Should get pools for pair", async function () {
      const { pathFinder, tokenA, tokenB, poolAB } = await loadFixture(deployPathFinderFixture);
      
      const pools = await pathFinder.getPoolsForPair(
        await tokenA.getAddress(),
        await tokenB.getAddress()
      );
      
      expect(pools).to.include(await poolAB.getAddress());
    });

    it("Should get connected tokens", async function () {
      const { pathFinder, tokenA, tokenB } = await loadFixture(deployPathFinderFixture);
      
      const connectedTokens = await pathFinder.getConnectedTokens(await tokenA.getAddress());
      expect(connectedTokens).to.include(await tokenB.getAddress());
    });
  });

  describe("Edge Cases", function () {
    it("Should handle zero liquidity pools gracefully", async function () {
      const { pathFinder } = await loadFixture(deployPathFinderFixture);
      
      // Deploy pool with zero liquidity
      const MockPool = await ethers.getContractFactory("MockLaxcePool");
      const zeroLiquidityPool = await MockPool.deploy(
        await (await ethers.getContractFactory("MockERC20")).deploy("TKN1", "TKN1", 18).then(c => c.getAddress()),
        await (await ethers.getContractFactory("MockERC20")).deploy("TKN2", "TKN2", 18).then(c => c.getAddress()),
        3000,
        0, // Zero liquidity
        "1461446703485210103287273052203988822378723970341"
      );
      
      await pathFinder.updatePoolInfo(await zeroLiquidityPool.getAddress());
      
      // Should handle gracefully without reverting
      const poolInfo = await pathFinder.poolInfo(await zeroLiquidityPool.getAddress());
      expect(poolInfo.liquidity).to.equal(0);
    });

    it("Should handle cache clearing", async function () {
      const { pathFinder, operator } = await loadFixture(deployPathFinderFixture);
      
      await expect(
        pathFinder.connect(operator).clearCache()
      ).to.emit(pathFinder, "CacheUpdated");
    });
  });
}); 