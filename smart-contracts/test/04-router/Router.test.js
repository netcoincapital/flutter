const { expect } = require("chai");
const { ethers } = require("hardhat");
const { 
  loadFixture, 
  time 
} = require("@nomicfoundation/hardhat-network-helpers");

describe("Router", function () {
  // Test fixture
  async function deployRouterFixture() {
    const [owner, user1, user2, treasury, operator] = await ethers.getSigners();

    // Deploy libraries
    const Constants = await ethers.getContractFactory("Constants");
    const constants = await Constants.deploy();
    await constants.waitForDeployment();

    const ReentrancyGuard = await ethers.getContractFactory("ReentrancyGuard");
    const reentrancyGuard = await ReentrancyGuard.deploy();
    await reentrancyGuard.waitForDeployment();

    const TickMath = await ethers.getContractFactory("TickMath");
    const tickMath = await TickMath.deploy();
    await tickMath.waitForDeployment();

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

    // Deploy mock WETH
    const MockWETH = await ethers.getContractFactory("MockWETH");
    const weth = await MockWETH.deploy();
    await weth.waitForDeployment();

    // Deploy mock PoolManager
    const MockPoolManager = await ethers.getContractFactory("MockPoolManager");
    const poolManager = await MockPoolManager.deploy();
    await poolManager.waitForDeployment();

    // Deploy Router
    const Router = await ethers.getContractFactory("Router", {
      libraries: {
        Constants: await constants.getAddress(),
        ReentrancyGuard: await reentrancyGuard.getAddress()
      }
    });
    const router = await Router.deploy(
      await poolFactory.getAddress(),
      await pathFinder.getAddress(),
      await poolManager.getAddress(),
      await weth.getAddress()
    );
    await router.waitForDeployment();

    // Deploy mock tokens
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const tokenA = await MockERC20.deploy("Token A", "TKNA", 18);
    const tokenB = await MockERC20.deploy("Token B", "TKNB", 18);
    const tokenC = await MockERC20.deploy("Token C", "TKNC", 18);
    await tokenA.waitForDeployment();
    await tokenB.waitForDeployment();
    await tokenC.waitForDeployment();

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
    await poolAB.waitForDeployment();
    await poolBC.waitForDeployment();

    // Setup mock factory to return pools
    await poolFactory.setMockPool(
      await tokenA.getAddress(),
      await tokenB.getAddress(),
      3000,
      await poolAB.getAddress()
    );
    await poolFactory.setMockPool(
      await tokenB.getAddress(),
      await tokenC.getAddress(),
      3000,
      await poolBC.getAddress()
    );

    // Mint tokens to users
    const mintAmount = ethers.parseEther("1000000");
    await tokenA.mint(user1.address, mintAmount);
    await tokenB.mint(user1.address, mintAmount);
    await tokenC.mint(user1.address, mintAmount);
    await tokenA.mint(user2.address, mintAmount);
    await tokenB.mint(user2.address, mintAmount);

    // Grant operator role
    const OPERATOR_ROLE = await router.OPERATOR_ROLE();
    await router.grantRole(OPERATOR_ROLE, operator.address);

    return {
      router,
      pathFinder,
      poolFactory,
      poolManager,
      weth,
      owner,
      user1,
      user2,
      treasury,
      operator,
      tokenA,
      tokenB,
      tokenC,
      poolAB,
      poolBC,
      constants,
      reentrancyGuard,
      tickMath,
      feeManager
    };
  }

  describe("Deployment", function () {
    it("Should deploy with correct addresses", async function () {
      const { router, poolFactory, pathFinder, poolManager, weth } = await loadFixture(deployRouterFixture);
      
      expect(await router.factory()).to.equal(await poolFactory.getAddress());
      expect(await router.pathFinder()).to.equal(await pathFinder.getAddress());
      expect(await router.poolManager()).to.equal(await poolManager.getAddress());
      expect(await router.WETH9()).to.equal(await weth.getAddress());
    });

    it("Should set correct default values", async function () {
      const { router, owner } = await loadFixture(deployRouterFixture);
      
      expect(await router.defaultSlippage()).to.equal(50); // 0.5%
      expect(await router.defaultDeadline()).to.equal(1200); // 20 minutes
      expect(await router.feeRecipient()).to.equal(owner.address);
      expect(await router.routerFee()).to.equal(0);
      expect(await router.tokenWhitelistEnabled()).to.equal(false);
    });

    it("Should grant DEFAULT_ADMIN_ROLE to deployer", async function () {
      const { router, owner } = await loadFixture(deployRouterFixture);
      
      const DEFAULT_ADMIN_ROLE = await router.DEFAULT_ADMIN_ROLE();
      expect(await router.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.be.true;
    });
  });

  describe("Exact Input Single Swap", function () {
    it("Should execute successful exact input single swap", async function () {
      const { router, tokenA, tokenB, user1 } = await loadFixture(deployRouterFixture);
      
      const amountIn = ethers.parseEther("100");
      const amountOutMinimum = ethers.parseEther("95");
      const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
      
      // Approve router to spend tokenA
      await tokenA.connect(user1).approve(await router.getAddress(), amountIn);
      
      const params = {
        tokenIn: await tokenA.getAddress(),
        tokenOut: await tokenB.getAddress(),
        fee: 3000,
        recipient: user1.address,
        deadline: deadline,
        amountIn: amountIn,
        amountOutMinimum: amountOutMinimum,
        sqrtPriceLimitX96: 0
      };
      
      const balanceBefore = await tokenB.balanceOf(user1.address);
      
      await expect(
        router.connect(user1).exactInputSingle(params)
      ).to.emit(router, "SwapExecuted");
      
      const balanceAfter = await tokenB.balanceOf(user1.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should revert with expired deadline", async function () {
      const { router, tokenA, tokenB, user1 } = await loadFixture(deployRouterFixture);
      
      const amountIn = ethers.parseEther("100");
      const expiredDeadline = Math.floor(Date.now() / 1000) - 3600; // 1 hour ago
      
      await tokenA.connect(user1).approve(await router.getAddress(), amountIn);
      
      const params = {
        tokenIn: await tokenA.getAddress(),
        tokenOut: await tokenB.getAddress(),
        fee: 3000,
        recipient: user1.address,
        deadline: expiredDeadline,
        amountIn: amountIn,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      };
      
      await expect(
        router.connect(user1).exactInputSingle(params)
      ).to.be.revertedWithCustomError(router, "Router__DeadlineExpired");
    });

    it("Should revert with zero amount", async function () {
      const { router, tokenA, tokenB, user1 } = await loadFixture(deployRouterFixture);
      
      const deadline = Math.floor(Date.now() / 1000) + 3600;
      
      const params = {
        tokenIn: await tokenA.getAddress(),
        tokenOut: await tokenB.getAddress(),
        fee: 3000,
        recipient: user1.address,
        deadline: deadline,
        amountIn: 0,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      };
      
      await expect(
        router.connect(user1).exactInputSingle(params)
      ).to.be.revertedWithCustomError(router, "Router__ZeroAmount");
    });

    it("Should handle ETH input correctly", async function () {
      const { router, weth, tokenB, user1 } = await loadFixture(deployRouterFixture);
      
      const amountIn = ethers.parseEther("1");
      const deadline = Math.floor(Date.now() / 1000) + 3600;
      
      // Setup mock pool for WETH/TokenB
      const { poolFactory } = await loadFixture(deployRouterFixture);
      const MockPool = await ethers.getContractFactory("MockLaxcePool");
      const wethPool = await MockPool.deploy(
        await weth.getAddress(),
        await tokenB.getAddress(),
        3000,
        ethers.parseEther("1000000"),
        "1461446703485210103287273052203988822378723970341"
      );
      await poolFactory.setMockPool(
        await weth.getAddress(),
        await tokenB.getAddress(),
        3000,
        await wethPool.getAddress()
      );
      
      const params = {
        tokenIn: await weth.getAddress(),
        tokenOut: await tokenB.getAddress(),
        fee: 3000,
        recipient: user1.address,
        deadline: deadline,
        amountIn: amountIn,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      };
      
      await expect(
        router.connect(user1).exactInputSingle(params, { value: amountIn })
      ).to.emit(router, "SwapExecuted");
    });
  });

  describe("Exact Input Multi-hop Swap", function () {
    it("Should execute successful multi-hop swap", async function () {
      const { router, tokenA, tokenB, tokenC, user1 } = await loadFixture(deployRouterFixture);
      
      const amountIn = ethers.parseEther("100");
      const deadline = Math.floor(Date.now() / 1000) + 3600;
      
      // Create path: TokenA -> TokenB -> TokenC
      const path = ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [await tokenA.getAddress(), 3000, await tokenB.getAddress(), 3000, await tokenC.getAddress()]
      );
      
      await tokenA.connect(user1).approve(await router.getAddress(), amountIn);
      
      const params = {
        path: path,
        recipient: user1.address,
        deadline: deadline,
        amountIn: amountIn,
        amountOutMinimum: 0
      };
      
      const balanceBefore = await tokenC.balanceOf(user1.address);
      
      await expect(
        router.connect(user1).exactInput(params)
      ).to.emit(router, "MultiHopSwap");
      
      const balanceAfter = await tokenC.balanceOf(user1.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should revert with invalid path", async function () {
      const { router, tokenA, user1 } = await loadFixture(deployRouterFixture);
      
      const amountIn = ethers.parseEther("100");
      const deadline = Math.floor(Date.now() / 1000) + 3600;
      
      // Invalid path (only one token)
      const invalidPath = ethers.solidityPacked(["address"], [await tokenA.getAddress()]);
      
      const params = {
        path: invalidPath,
        recipient: user1.address,
        deadline: deadline,
        amountIn: amountIn,
        amountOutMinimum: 0
      };
      
      await expect(
        router.connect(user1).exactInput(params)
      ).to.be.revertedWithCustomError(router, "Router__InvalidPath");
    });
  });

  describe("Exact Output Swaps", function () {
    it("Should execute successful exact output single swap", async function () {
      const { router, tokenA, tokenB, user1, pathFinder } = await loadFixture(deployRouterFixture);
      
      const amountOut = ethers.parseEther("95");
      const amountInMaximum = ethers.parseEther("105");
      const deadline = Math.floor(Date.now() / 1000) + 3600;
      
      // Setup PathFinder mock response
      await pathFinder.setMockAmountIn(ethers.parseEther("100"), 100); // 1% price impact
      
      await tokenA.connect(user1).approve(await router.getAddress(), amountInMaximum);
      
      const params = {
        tokenIn: await tokenA.getAddress(),
        tokenOut: await tokenB.getAddress(),
        fee: 3000,
        recipient: user1.address,
        deadline: deadline,
        amountOut: amountOut,
        amountInMaximum: amountInMaximum,
        sqrtPriceLimitX96: 0
      };
      
      const balanceBefore = await tokenB.balanceOf(user1.address);
      
      await expect(
        router.connect(user1).exactOutputSingle(params)
      ).to.emit(router, "SwapExecuted");
      
      const balanceAfter = await tokenB.balanceOf(user1.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should revert if required input exceeds maximum", async function () {
      const { router, tokenA, tokenB, user1, pathFinder } = await loadFixture(deployRouterFixture);
      
      const amountOut = ethers.parseEther("95");
      const amountInMaximum = ethers.parseEther("90"); // Less than required
      const deadline = Math.floor(Date.now() / 1000) + 3600;
      
      // Setup PathFinder to require more input than maximum
      await pathFinder.setMockAmountIn(ethers.parseEther("100"), 100);
      
      await tokenA.connect(user1).approve(await router.getAddress(), amountInMaximum);
      
      const params = {
        tokenIn: await tokenA.getAddress(),
        tokenOut: await tokenB.getAddress(),
        fee: 3000,
        recipient: user1.address,
        deadline: deadline,
        amountOut: amountOut,
        amountInMaximum: amountInMaximum,
        sqrtPriceLimitX96: 0
      };
      
      await expect(
        router.connect(user1).exactOutputSingle(params)
      ).to.be.revertedWithCustomError(router, "Router__ExcessiveAmountIn");
    });
  });

  describe("Quote Functions", function () {
    it("Should provide quote for exact input single", async function () {
      const { router, tokenA, tokenB, pathFinder } = await loadFixture(deployRouterFixture);
      
      const amountIn = ethers.parseEther("100");
      
      // Setup PathFinder mock response
      await pathFinder.setMockAmountOut(ethers.parseEther("95"), 100);
      
      const amountOut = await router.quoteExactInputSingle(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        3000,
        amountIn,
        0
      );
      
      expect(amountOut).to.equal(ethers.parseEther("95"));
    });

    it("Should provide quote for exact input multi-hop", async function () {
      const { router, tokenA, tokenB, tokenC, pathFinder } = await loadFixture(deployRouterFixture);
      
      const amountIn = ethers.parseEther("100");
      const path = ethers.solidityPacked(
        ["address", "uint24", "address", "uint24", "address"],
        [await tokenA.getAddress(), 3000, await tokenB.getAddress(), 3000, await tokenC.getAddress()]
      );
      
      // Setup PathFinder mock response
      await pathFinder.setMockAmountOut(ethers.parseEther("90"), 200);
      
      const amountOut = await router.quoteExactInput(path, amountIn);
      expect(amountOut).to.equal(ethers.parseEther("90"));
    });
  });

  describe("Optimal Path Functions", function () {
    it("Should find optimal path and quote", async function () {
      const { router, tokenA, tokenB, pathFinder } = await loadFixture(deployRouterFixture);
      
      const amountIn = ethers.parseEther("100");
      
      // Setup PathFinder mock response
      const mockPath = {
        tokens: [await tokenA.getAddress(), await tokenB.getAddress()],
        fees: [3000],
        pools: [ethers.ZeroAddress],
        expectedAmountOut: ethers.parseEther("95"),
        priceImpact: 100,
        gasEstimate: 200000,
        isValid: true
      };
      await pathFinder.setMockOptimalPath(mockPath);
      
      const [path, amountOut, priceImpact] = await router.findOptimalPathAndQuote(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        amountIn
      );
      
      expect(path.isValid).to.be.true;
      expect(amountOut).to.equal(ethers.parseEther("95"));
      expect(priceImpact).to.equal(100);
    });

    it("Should find multiple paths", async function () {
      const { router, tokenA, tokenB, pathFinder } = await loadFixture(deployRouterFixture);
      
      const amountIn = ethers.parseEther("100");
      
      // Setup PathFinder mock response
      const mockPaths = [
        {
          tokens: [await tokenA.getAddress(), await tokenB.getAddress()],
          fees: [3000],
          pools: [ethers.ZeroAddress],
          expectedAmountOut: ethers.parseEther("95"),
          priceImpact: 100,
          gasEstimate: 200000,
          isValid: true
        }
      ];
      await pathFinder.setMockMultiplePaths(mockPaths);
      
      const paths = await router.findMultiplePathsAndQuotes(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        amountIn,
        3
      );
      
      expect(paths.length).to.be.gt(0);
      expect(paths[0].isValid).to.be.true;
    });
  });

  describe("Configuration Management", function () {
    it("Should allow admin to set default slippage", async function () {
      const { router, owner } = await loadFixture(deployRouterFixture);
      
      const newSlippage = 100; // 1%
      
      await expect(
        router.setDefaultSlippage(newSlippage)
      ).to.emit(router, "SlippageUpdated")
        .withArgs(50, newSlippage);
      
      expect(await router.defaultSlippage()).to.equal(newSlippage);
    });

    it("Should revert with invalid slippage", async function () {
      const { router } = await loadFixture(deployRouterFixture);
      
      await expect(
        router.setDefaultSlippage(6000) // > 50%
      ).to.be.revertedWithCustomError(router, "Router__InvalidSlippage");
    });

    it("Should allow admin to set fee recipient", async function () {
      const { router, user1 } = await loadFixture(deployRouterFixture);
      
      await expect(
        router.setFeeRecipient(user1.address)
      ).to.emit(router, "FeeRecipientUpdated");
      
      expect(await router.feeRecipient()).to.equal(user1.address);
    });

    it("Should allow admin to set router fee", async function () {
      const { router } = await loadFixture(deployRouterFixture);
      
      const newFee = 50; // 0.5%
      
      await expect(
        router.setRouterFee(newFee)
      ).to.emit(router, "RouterFeeUpdated")
        .withArgs(0, newFee);
      
      expect(await router.routerFee()).to.equal(newFee);
    });

    it("Should revert with excessive router fee", async function () {
      const { router } = await loadFixture(deployRouterFixture);
      
      await expect(
        router.setRouterFee(150) // > 1%
      ).to.be.revertedWithCustomError(router, "Router__InvalidSlippage");
    });
  });

  describe("Token Management", function () {
    it("Should allow admin to approve token", async function () {
      const { router, tokenA } = await loadFixture(deployRouterFixture);
      
      await expect(
        router.setTokenApproval(await tokenA.getAddress(), true)
      ).to.emit(router, "TokenApproved")
        .withArgs(await tokenA.getAddress(), true);
      
      expect(await router.approvedTokens(await tokenA.getAddress())).to.be.true;
    });

    it("Should allow admin to block token", async function () {
      const { router, tokenA } = await loadFixture(deployRouterFixture);
      
      await expect(
        router.setTokenBlocked(await tokenA.getAddress(), true)
      ).to.emit(router, "TokenBlocked")
        .withArgs(await tokenA.getAddress(), true);
      
      expect(await router.blockedTokens(await tokenA.getAddress())).to.be.true;
    });

    it("Should check token usability correctly", async function () {
      const { router, tokenA, tokenB } = await loadFixture(deployRouterFixture);
      
      // Initially all tokens should be usable
      expect(await router.isTokenUsable(await tokenA.getAddress())).to.be.true;
      
      // Block tokenA
      await router.setTokenBlocked(await tokenA.getAddress(), true);
      expect(await router.isTokenUsable(await tokenA.getAddress())).to.be.false;
      
      // Enable whitelist and approve tokenB
      await router.setTokenWhitelistEnabled(true);
      expect(await router.isTokenUsable(await tokenB.getAddress())).to.be.false; // Not approved
      
      await router.setTokenApproval(await tokenB.getAddress(), true);
      expect(await router.isTokenUsable(await tokenB.getAddress())).to.be.true; // Now approved
    });

    it("Should reject swaps with blocked tokens", async function () {
      const { router, tokenA, tokenB, user1 } = await loadFixture(deployRouterFixture);
      
      // Block tokenA
      await router.setTokenBlocked(await tokenA.getAddress(), true);
      
      const amountIn = ethers.parseEther("100");
      const deadline = Math.floor(Date.now() / 1000) + 3600;
      
      const params = {
        tokenIn: await tokenA.getAddress(),
        tokenOut: await tokenB.getAddress(),
        fee: 3000,
        recipient: user1.address,
        deadline: deadline,
        amountIn: amountIn,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      };
      
      await expect(
        router.connect(user1).exactInputSingle(params)
      ).to.be.revertedWithCustomError(router, "Router__TokenBlocked");
    });
  });

  describe("Access Control", function () {
    it("Should only allow admin to modify configuration", async function () {
      const { router, user1 } = await loadFixture(deployRouterFixture);
      
      await expect(
        router.connect(user1).setDefaultSlippage(100)
      ).to.be.reverted;
      
      await expect(
        router.connect(user1).setFeeRecipient(user1.address)
      ).to.be.reverted;
      
      await expect(
        router.connect(user1).setRouterFee(50)
      ).to.be.reverted;
    });

    it("Should only allow pauser to pause", async function () {
      const { router, user1 } = await loadFixture(deployRouterFixture);
      
      await expect(
        router.connect(user1).pause()
      ).to.be.reverted;
    });
  });

  describe("Pause Functionality", function () {
    it("Should prevent swaps when paused", async function () {
      const { router, tokenA, tokenB, user1, owner } = await loadFixture(deployRouterFixture);
      
      // Grant pauser role and pause
      const PAUSER_ROLE = await router.PAUSER_ROLE();
      await router.grantRole(PAUSER_ROLE, owner.address);
      await router.pause();
      
      const amountIn = ethers.parseEther("100");
      const deadline = Math.floor(Date.now() / 1000) + 3600;
      
      await tokenA.connect(user1).approve(await router.getAddress(), amountIn);
      
      const params = {
        tokenIn: await tokenA.getAddress(),
        tokenOut: await tokenB.getAddress(),
        fee: 3000,
        recipient: user1.address,
        deadline: deadline,
        amountIn: amountIn,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      };
      
      await expect(
        router.connect(user1).exactInputSingle(params)
      ).to.be.revertedWith("Pausable: paused");
    });
  });

  describe("Emergency Functions", function () {
    it("Should allow admin to rescue tokens", async function () {
      const { router, tokenA, owner } = await loadFixture(deployRouterFixture);
      
      const amount = ethers.parseEther("100");
      
      // Send tokens to router
      await tokenA.mint(await router.getAddress(), amount);
      
      const balanceBefore = await tokenA.balanceOf(owner.address);
      
      await router.rescueToken(await tokenA.getAddress(), amount);
      
      const balanceAfter = await tokenA.balanceOf(owner.address);
      expect(balanceAfter - balanceBefore).to.equal(amount);
    });

    it("Should allow admin to rescue ETH", async function () {
      const { router, owner } = await loadFixture(deployRouterFixture);
      
      const amount = ethers.parseEther("1");
      
      // Send ETH to router
      await owner.sendTransaction({
        to: await router.getAddress(),
        value: amount
      });
      
      const balanceBefore = await ethers.provider.getBalance(owner.address);
      
      const tx = await router.rescueETH(amount);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      
      const balanceAfter = await ethers.provider.getBalance(owner.address);
      expect(balanceAfter + gasUsed - balanceBefore).to.equal(amount);
    });
  });

  describe("View Functions", function () {
    it("Should return correct configuration", async function () {
      const { router, owner } = await loadFixture(deployRouterFixture);
      
      const [slippage, deadline, feeRecipient, routerFee, whitelistEnabled] = 
        await router.getConfiguration();
      
      expect(slippage).to.equal(50);
      expect(deadline).to.equal(1200);
      expect(feeRecipient).to.equal(owner.address);
      expect(routerFee).to.equal(0);
      expect(whitelistEnabled).to.equal(false);
    });
  });

  describe("ETH Handling", function () {
    it("Should only receive ETH from WETH contract", async function () {
      const { router, user1 } = await loadFixture(deployRouterFixture);
      
      await expect(
        user1.sendTransaction({
          to: await router.getAddress(),
          value: ethers.parseEther("1")
        })
      ).to.be.revertedWithCustomError(router, "Router__TransferFailed");
    });
  });
}); 