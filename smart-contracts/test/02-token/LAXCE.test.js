const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

describe("LAXCE Token", function () {
  const INITIAL_SUPPLY = ethers.parseEther("10000000"); // 10M tokens
  const MIN_LOCK_AMOUNT = ethers.parseEther("1000");    // 1000 LAXCE
  const LOCK_DURATION = 365 * 24 * 60 * 60; // 1 year

  async function deployLAXCEFixture() {
    const [owner, user1, user2, admin] = await ethers.getSigners();
    
    const LAXCE = await ethers.getContractFactory("LAXCE");
    const laxce = await LAXCE.deploy(owner.address, INITIAL_SUPPLY);
    
    // Grant admin role
    const ADMIN_ROLE = await laxce.ADMIN_ROLE();
    await laxce.grantRole(ADMIN_ROLE, admin.address);
    
    return { laxce, owner, user1, user2, admin, ADMIN_ROLE };
  }

  describe("Deployment", function () {
    it("Should set correct initial supply", async function () {
      const { laxce, owner } = await loadFixture(deployLAXCEFixture);
      
      expect(await laxce.totalSupply()).to.equal(INITIAL_SUPPLY);
      expect(await laxce.balanceOf(owner.address)).to.equal(INITIAL_SUPPLY);
    });

    it("Should set correct token details", async function () {
      const { laxce } = await loadFixture(deployLAXCEFixture);
      
      expect(await laxce.name()).to.equal("LAXCE DEX Token");
      expect(await laxce.symbol()).to.equal("LAXCE");
      expect(await laxce.decimals()).to.equal(18);
    });
  });

  describe("Token Locking", function () {
    it("Should lock tokens successfully", async function () {
      const { laxce, owner, user1 } = await loadFixture(deployLAXCEFixture);
      
      // Transfer tokens to user1
      await laxce.transfer(user1.address, MIN_LOCK_AMOUNT);
      
      // Lock tokens
      await expect(laxce.connect(user1).lockTokens(MIN_LOCK_AMOUNT, LOCK_DURATION))
        .to.emit(laxce, "TokensLocked")
        .withArgs(user1.address, MIN_LOCK_AMOUNT, LOCK_DURATION, anyValue);
      
      // Check lock info
      const lockInfo = await laxce.lockInfo(user1.address);
      expect(lockInfo.amount).to.equal(MIN_LOCK_AMOUNT);
      expect(lockInfo.isActive).to.be.true;
      
      // Check total locked
      expect(await laxce.totalLocked()).to.equal(MIN_LOCK_AMOUNT);
    });

    it("Should calculate fee discount correctly", async function () {
      const { laxce, owner, user1 } = await loadFixture(deployLAXCEFixture);
      
      // Transfer tokens to user1
      await laxce.transfer(user1.address, MIN_LOCK_AMOUNT);
      
      // Lock tokens
      await laxce.connect(user1).lockTokens(MIN_LOCK_AMOUNT, LOCK_DURATION);
      
      // Check fee discount
      const discount = await laxce.calculateFeeDiscount(user1.address);
      expect(discount).to.be.greaterThan(0);
    });

    it("Should not allow unlocking before time", async function () {
      const { laxce, owner, user1 } = await loadFixture(deployLAXCEFixture);
      
      // Transfer and lock tokens
      await laxce.transfer(user1.address, MIN_LOCK_AMOUNT);
      await laxce.connect(user1).lockTokens(MIN_LOCK_AMOUNT, LOCK_DURATION);
      
      // Try to unlock immediately
      await expect(laxce.connect(user1).unlockTokens())
        .to.be.revertedWith("Tokens still locked");
    });

    it("Should allow unlocking after time", async function () {
      const { laxce, owner, user1 } = await loadFixture(deployLAXCEFixture);
      
      // Transfer and lock tokens
      await laxce.transfer(user1.address, MIN_LOCK_AMOUNT);
      await laxce.connect(user1).lockTokens(MIN_LOCK_AMOUNT, LOCK_DURATION);
      
      // Advance time
      await time.increase(LOCK_DURATION + 1);
      
      // Unlock tokens
      await expect(laxce.connect(user1).unlockTokens())
        .to.emit(laxce, "TokensUnlocked")
        .withArgs(user1.address, MIN_LOCK_AMOUNT);
      
      // Check balance
      expect(await laxce.balanceOf(user1.address)).to.equal(MIN_LOCK_AMOUNT);
    });

    it("Should reject lock amount below minimum", async function () {
      const { laxce, owner, user1 } = await loadFixture(deployLAXCEFixture);
      
      const smallAmount = ethers.parseEther("100"); // Below minimum
      await laxce.transfer(user1.address, smallAmount);
      
      await expect(laxce.connect(user1).lockTokens(smallAmount, LOCK_DURATION))
        .to.be.revertedWith("Amount below minimum lock");
    });
  });

  describe("Revenue Sharing", function () {
    it("Should deposit revenue successfully", async function () {
      const { laxce, admin } = await loadFixture(deployLAXCEFixture);
      
      const revenueAmount = ethers.parseEther("1");
      
      await expect(laxce.connect(admin).depositRevenue({ value: revenueAmount }))
        .to.emit(laxce, "RevenueDeposited")
        .withArgs(revenueAmount, anyValue);
      
      expect(await laxce.revenuePool()).to.equal(revenueAmount);
    });

    it("Should calculate claimable revenue correctly", async function () {
      const { laxce, owner, user1, admin } = await loadFixture(deployLAXCEFixture);
      
      // Setup: Transfer tokens, lock them
      await laxce.transfer(user1.address, MIN_LOCK_AMOUNT);
      await laxce.connect(user1).lockTokens(MIN_LOCK_AMOUNT, LOCK_DURATION);
      
      // Deposit revenue
      const revenueAmount = ethers.parseEther("1");
      await laxce.connect(admin).depositRevenue({ value: revenueAmount });
      
      // Check claimable revenue
      const claimable = await laxce.calculateClaimableRevenue(user1.address);
      expect(claimable).to.equal(revenueAmount); // User has 100% of locked tokens
    });

    it("Should allow claiming revenue", async function () {
      const { laxce, owner, user1, admin } = await loadFixture(deployLAXCEFixture);
      
      // Setup
      await laxce.transfer(user1.address, MIN_LOCK_AMOUNT);
      await laxce.connect(user1).lockTokens(MIN_LOCK_AMOUNT, LOCK_DURATION);
      
      // Deposit revenue
      const revenueAmount = ethers.parseEther("1");
      await laxce.connect(admin).depositRevenue({ value: revenueAmount });
      
      // Claim revenue
      const initialBalance = await ethers.provider.getBalance(user1.address);
      
      await expect(laxce.connect(user1).claimRevenue())
        .to.emit(laxce, "RevenueClaimed");
      
      const finalBalance = await ethers.provider.getBalance(user1.address);
      expect(finalBalance).to.be.greaterThan(initialBalance);
    });

    it("Should not allow claiming when no revenue", async function () {
      const { laxce, owner, user1 } = await loadFixture(deployLAXCEFixture);
      
      await expect(laxce.connect(user1).claimRevenue())
        .to.be.revertedWith("No revenue to claim");
    });
  });

  describe("Voting Power", function () {
    it("Should calculate voting power correctly", async function () {
      const { laxce, owner, user1 } = await loadFixture(deployLAXCEFixture);
      
      // Transfer and lock tokens
      await laxce.transfer(user1.address, MIN_LOCK_AMOUNT);
      await laxce.connect(user1).lockTokens(MIN_LOCK_AMOUNT, LOCK_DURATION);
      
      // Check voting power
      const votingPower = await laxce.getVotingPower(user1.address);
      expect(votingPower).to.be.greaterThan(0);
    });

    it("Should return zero voting power for unlocked tokens", async function () {
      const { laxce, user1 } = await loadFixture(deployLAXCEFixture);
      
      const votingPower = await laxce.getVotingPower(user1.address);
      expect(votingPower).to.equal(0);
    });
  });

  describe("Admin Functions", function () {
    it("Should allow owner to mint tokens", async function () {
      const { laxce, owner, user1 } = await loadFixture(deployLAXCEFixture);
      
      const mintAmount = ethers.parseEther("1000");
      
      await expect(laxce.mint(user1.address, mintAmount))
        .to.emit(laxce, "Transfer")
        .withArgs(ethers.ZeroAddress, user1.address, mintAmount);
      
      expect(await laxce.balanceOf(user1.address)).to.equal(mintAmount);
    });

    it("Should not allow minting beyond max supply", async function () {
      const { laxce, owner, user1 } = await loadFixture(deployLAXCEFixture);
      
      const maxSupply = await laxce.MAX_SUPPLY();
      const currentSupply = await laxce.totalSupply();
      const excessAmount = maxSupply - currentSupply + ethers.parseEther("1");
      
      await expect(laxce.mint(user1.address, excessAmount))
        .to.be.revertedWith("Exceeds max supply");
    });

    it("Should allow owner to toggle revenue sharing", async function () {
      const { laxce, owner } = await loadFixture(deployLAXCEFixture);
      
      await laxce.setRevenueShareEnabled(false);
      expect(await laxce.revenueShareEnabled()).to.be.false;
      
      await laxce.setRevenueShareEnabled(true);
      expect(await laxce.revenueShareEnabled()).to.be.true;
    });
  });

  describe("Gas Optimization", function () {
    it("Should use reasonable gas for locking", async function () {
      const { laxce, owner, user1 } = await loadFixture(deployLAXCEFixture);
      
      await laxce.transfer(user1.address, MIN_LOCK_AMOUNT);
      
      const tx = await laxce.connect(user1).lockTokens(MIN_LOCK_AMOUNT, LOCK_DURATION);
      const receipt = await tx.wait();
      
      // Should use less than 200k gas
      expect(receipt.gasUsed).to.be.lessThan(200000);
    });
  });
}); 