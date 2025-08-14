const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

describe("SecurityManager", function () {
  
  async function deploySecurityFixture() {
    const [owner, user1, user2, emergencyResponder, attacker] = await ethers.getSigners();
    
    // Deploy SecurityManager
    const SecurityManager = await ethers.getContractFactory("SecurityManager");
    const securityManager = await SecurityManager.deploy(owner.address);
    
    return { 
      securityManager, 
      owner, 
      user1, 
      user2, 
      emergencyResponder, 
      attacker 
    };
  }

  describe("Deployment", function () {
    it("Should initialize correctly", async function () {
      const { securityManager, owner } = await loadFixture(deploySecurityFixture);
      
      // Check initial state
      const stats = await securityManager.getSecurityStats();
      expect(stats.systemPaused).to.be.false;
      
      // Check circuit breaker
      const cbStats = await securityManager.getCircuitBreakerStats();
      expect(cbStats.maxTriggers).to.equal(5);
      expect(cbStats.isActive).to.be.true;
    });
  });

  describe("Emergency Pause", function () {
    it("Should allow emergency responder to pause system", async function () {
      const { securityManager, owner } = await loadFixture(deploySecurityFixture);
      
      await expect(securityManager.emergencyPauseSystem("Security test"))
        .to.emit(securityManager, "SecurityEventDetected")
        .withArgs(owner.address, "EMERGENCY_PAUSE", "Security test", 10);
      
      const pauseInfo = await securityManager.getSystemPauseInfo();
      expect(pauseInfo.isPaused).to.be.true;
      expect(pauseInfo.reason).to.equal("Security test");
    });

    it("Should not allow non-emergency responder to pause", async function () {
      const { securityManager, user1 } = await loadFixture(deploySecurityFixture);
      
      await expect(securityManager.connect(user1).emergencyPauseSystem("Test"))
        .to.be.revertedWith("Not emergency responder");
    });

    it("Should allow timed pause", async function () {
      const { securityManager, owner } = await loadFixture(deploySecurityFixture);
      
      const duration = 1 * 60 * 60; // 1 hour
      await securityManager.timedPauseSystem("Maintenance", duration);
      
      const pauseInfo = await securityManager.getSystemPauseInfo();
      expect(pauseInfo.isPaused).to.be.true;
      expect(pauseInfo.timeUntilUnpause).to.be.greaterThan(0);
    });

    it("Should allow unpause by emergency responder", async function () {
      const { securityManager, owner } = await loadFixture(deploySecurityFixture);
      
      // Pause first
      await securityManager.emergencyPauseSystem("Test pause");
      
      // Unpause
      await expect(securityManager.unpauseSystem())
        .to.emit(securityManager, "SecurityEventDetected")
        .withArgs(owner.address, "SYSTEM_UNPAUSED", "System resumed", 5);
      
      const pauseInfo = await securityManager.getSystemPauseInfo();
      expect(pauseInfo.isPaused).to.be.false;
    });
  });

  describe("Circuit Breaker", function () {
    it("Should trigger circuit breaker on multiple calls", async function () {
      const { securityManager, owner } = await loadFixture(deploySecurityFixture);
      
      // First, authorize this contract to trigger circuit breaker
      await securityManager.authorizeContract(owner.address, true);
      
      // Trigger multiple times (should pause on 5th trigger)
      for (let i = 0; i < 4; i++) {
        const paused = await securityManager.triggerCircuitBreaker(`Test trigger ${i}`);
        expect(paused).to.be.false;
      }
      
      // 5th trigger should pause the system
      const paused = await securityManager.triggerCircuitBreaker("Final trigger");
      expect(paused).to.be.true;
      
      const pauseInfo = await securityManager.getSystemPauseInfo();
      expect(pauseInfo.isPaused).to.be.true;
    });

    it("Should reset circuit breaker after window", async function () {
      const { securityManager, owner } = await loadFixture(deploySecurityFixture);
      
      await securityManager.authorizeContract(owner.address, true);
      
      // Trigger 4 times
      for (let i = 0; i < 4; i++) {
        await securityManager.triggerCircuitBreaker(`Test ${i}`);
      }
      
      // Advance time by more than 1 hour (window duration)
      await time.increase(2 * 60 * 60);
      
      // Should not pause now (window reset)
      const paused = await securityManager.triggerCircuitBreaker("After window");
      expect(paused).to.be.false;
    });
  });

  describe("Slippage Protection", function () {
    it("Should validate correct slippage", async function () {
      const { securityManager } = await loadFixture(deploySecurityFixture);
      
      // This should not revert
      await securityManager.validateSlippage(
        ethers.parseEther("1"),    // amountIn
        ethers.parseEther("0.95"), // amountOutMin
        ethers.parseEther("1.05"), // amountOutMax
        ethers.parseEther("1"),    // actualAmountOut
        500                        // maxSlippageBps (5%)
      );
    });

    it("Should reject high slippage", async function () {
      const { securityManager } = await loadFixture(deploySecurityFixture);
      
      await expect(securityManager.validateSlippage(
        ethers.parseEther("1"),    // amountIn
        ethers.parseEther("0.95"), // amountOutMin
        ethers.parseEther("1.05"), // amountOutMax
        ethers.parseEther("0.8"),  // actualAmountOut (too low)
        500                        // maxSlippageBps (5%)
      )).to.be.revertedWithCustomError(securityManager, "SlippageTooHigh");
    });
  });

  describe("Rate Limiting", function () {
    it("Should enforce rate limits", async function () {
      const { securityManager, user1 } = await loadFixture(deploySecurityFixture);
      
      // First 10 calls should work
      for (let i = 0; i < 10; i++) {
        await securityManager.checkUserRateLimit(user1.address);
      }
      
      // 11th call should fail
      await expect(securityManager.checkUserRateLimit(user1.address))
        .to.be.revertedWithCustomError(securityManager, "RateLimitExceeded");
    });

    it("Should reset rate limit after window", async function () {
      const { securityManager, user1 } = await loadFixture(deploySecurityFixture);
      
      // Exhaust rate limit
      for (let i = 0; i < 10; i++) {
        await securityManager.checkUserRateLimit(user1.address);
      }
      
      // Advance time by 1 minute
      await time.increase(61);
      
      // Should work again
      await securityManager.checkUserRateLimit(user1.address);
    });
  });

  describe("Token Validation", function () {
    it("Should validate legitimate tokens", async function () {
      const { securityManager } = await loadFixture(deploySecurityFixture);
      
      // Deploy a test ERC20 token
      const TestToken = await ethers.getContractFactory("LAXCE");
      const testToken = await TestToken.deploy(
        await securityManager.getAddress(), 
        ethers.parseEther("1000"),
        await securityManager.getAddress() // temporary SecurityManager address
      );
      
      const isValid = await securityManager.validateToken(await testToken.getAddress());
      expect(isValid).to.be.true;
    });

    it("Should reject invalid addresses", async function () {
      const { securityManager } = await loadFixture(deploySecurityFixture);
      
      const isValid = await securityManager.validateToken(ethers.ZeroAddress);
      expect(isValid).to.be.false;
    });
  });

  describe("Admin Functions", function () {
    it("Should allow owner to add emergency responder", async function () {
      const { securityManager, owner, user1 } = await loadFixture(deploySecurityFixture);
      
      await expect(securityManager.addEmergencyResponder(user1.address))
        .to.emit(securityManager, "EmergencyResponderAdded")
        .withArgs(user1.address);
      
      // User1 should now be able to pause
      await securityManager.connect(user1).emergencyPauseSystem("Test by new responder");
      
      const pauseInfo = await securityManager.getSystemPauseInfo();
      expect(pauseInfo.isPaused).to.be.true;
    });

    it("Should allow admin to configure circuit breaker", async function () {
      const { securityManager, owner } = await loadFixture(deploySecurityFixture);
      
      await securityManager.configureCircuitBreaker(10, 30 * 60, true); // 10 triggers, 30 min window
      
      const stats = await securityManager.getCircuitBreakerStats();
      expect(stats.maxTriggers).to.equal(10);
      expect(stats.isActive).to.be.true;
    });

    it("Should not allow non-admin to configure", async function () {
      const { securityManager, user1 } = await loadFixture(deploySecurityFixture);
      
      await expect(securityManager.connect(user1).configureCircuitBreaker(10, 30 * 60, true))
        .to.be.revertedWith("Missing required role");
    });
  });

  describe("Security Events", function () {
    it("Should track security statistics", async function () {
      const { securityManager, owner } = await loadFixture(deploySecurityFixture);
      
      // Trigger some events
      await securityManager.emergencyPauseSystem("Test 1");
      await securityManager.unpauseSystem();
      
      const stats = await securityManager.getSecurityStats();
      expect(stats.totalEvents).to.equal(2); // Pause + Unpause
      expect(stats.totalPauses).to.equal(1);
    });
  });

  describe("Gas Optimization", function () {
    it("Should use reasonable gas for validation", async function () {
      const { securityManager } = await loadFixture(deploySecurityFixture);
      
      const tx = await securityManager.validateSlippage(
        ethers.parseEther("1"),
        ethers.parseEther("0.95"),
        ethers.parseEther("1.05"),
        ethers.parseEther("1"),
        500
      );
      
      const receipt = await tx.wait();
      expect(receipt.gasUsed).to.be.lessThan(50000); // Should be very gas efficient
    });
  });
}); 