const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("AccessControl", function () {
  // Fixture برای راه‌اندازی contracts
  async function deployAccessControlFixture() {
    const [owner, admin, operator, user] = await ethers.getSigners();
    
    const AccessControl = await ethers.getContractFactory("AccessControl");
    const accessControl = await AccessControl.deploy(owner.address);
    
    return { accessControl, owner, admin, operator, user };
  }

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      const { accessControl, owner } = await loadFixture(deployAccessControlFixture);
      
      const OWNER_ROLE = await accessControl.OWNER_ROLE();
      expect(await accessControl.hasRole(OWNER_ROLE, owner.address)).to.equal(true);
    });

    it("Should set default admin role", async function () {
      const { accessControl, owner } = await loadFixture(deployAccessControlFixture);
      
      const DEFAULT_ADMIN_ROLE = await accessControl.DEFAULT_ADMIN_ROLE();
      expect(await accessControl.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.equal(true);
    });

    it("Should revert with zero address", async function () {
      const AccessControl = await ethers.getContractFactory("AccessControl");
      
      await expect(
        AccessControl.deploy(ethers.ZeroAddress)
      ).to.be.revertedWith("Zero address not allowed");
    });
  });

  describe("Role Management", function () {
    it("Should grant admin role", async function () {
      const { accessControl, owner, admin } = await loadFixture(deployAccessControlFixture);
      
      const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
      
      await expect(accessControl.connect(owner).grantRole(ADMIN_ROLE, admin.address))
        .to.emit(accessControl, "RoleGranted")
        .withArgs(ADMIN_ROLE, admin.address, owner.address);
      
      expect(await accessControl.hasRole(ADMIN_ROLE, admin.address)).to.equal(true);
    });

    it("Should revoke role", async function () {
      const { accessControl, owner, admin } = await loadFixture(deployAccessControlFixture);
      
      const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
      
      // ابتدا grant کنیم
      await accessControl.connect(owner).grantRole(ADMIN_ROLE, admin.address);
      
      // سپس revoke کنیم
      await expect(accessControl.connect(owner).revokeRole(ADMIN_ROLE, admin.address))
        .to.emit(accessControl, "RoleRevoked")
        .withArgs(ADMIN_ROLE, admin.address, owner.address);
      
      expect(await accessControl.hasRole(ADMIN_ROLE, admin.address)).to.equal(false);
    });

    it("Should allow role renouncement", async function () {
      const { accessControl, owner, admin } = await loadFixture(deployAccessControlFixture);
      
      const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
      
      // Grant role
      await accessControl.connect(owner).grantRole(ADMIN_ROLE, admin.address);
      
      // Self renounce
      await expect(accessControl.connect(admin).renounceRole(ADMIN_ROLE, admin.address))
        .to.emit(accessControl, "RoleRevoked")
        .withArgs(ADMIN_ROLE, admin.address, admin.address);
      
      expect(await accessControl.hasRole(ADMIN_ROLE, admin.address)).to.equal(false);
    });

    it("Should not allow renouncing others' roles", async function () {
      const { accessControl, owner, admin, user } = await loadFixture(deployAccessControlFixture);
      
      const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
      
      await accessControl.connect(owner).grantRole(ADMIN_ROLE, admin.address);
      
      await expect(
        accessControl.connect(user).renounceRole(ADMIN_ROLE, admin.address)
      ).to.be.revertedWith("AccessControl: can only renounce roles for self");
    });
  });

  describe("Access Control", function () {
    it("Should revert when unauthorized", async function () {
      const { accessControl, user } = await loadFixture(deployAccessControlFixture);
      
      const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
      
      await expect(
        accessControl.connect(user).grantRole(ADMIN_ROLE, user.address)
      ).to.be.revertedWith("AccessControl: account");
    });

    it("Should work with role hierarchy", async function () {
      const { accessControl, owner, admin, operator } = await loadFixture(deployAccessControlFixture);
      
      const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
      const OPERATOR_ROLE = await accessControl.OPERATOR_ROLE();
      
      // Owner grants admin role
      await accessControl.connect(owner).grantRole(ADMIN_ROLE, admin.address);
      
      // Admin grants operator role
      await accessControl.connect(admin).grantRole(OPERATOR_ROLE, operator.address);
      
      expect(await accessControl.hasRole(OPERATOR_ROLE, operator.address)).to.equal(true);
    });
  });

  describe("Role Admin", function () {
    it("Should return correct role admin", async function () {
      const { accessControl } = await loadFixture(deployAccessControlFixture);
      
      const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
      const OWNER_ROLE = await accessControl.OWNER_ROLE();
      
      expect(await accessControl.getRoleAdmin(ADMIN_ROLE)).to.equal(OWNER_ROLE);
    });
  });

  describe("Gas Optimization", function () {
    it("Should not emit event for duplicate role grants", async function () {
      const { accessControl, owner, admin } = await loadFixture(deployAccessControlFixture);
      
      const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
      
      // اولین grant
      await accessControl.connect(owner).grantRole(ADMIN_ROLE, admin.address);
      
      // دومین grant نباید event emit کند
      const tx = await accessControl.connect(owner).grantRole(ADMIN_ROLE, admin.address);
      const receipt = await tx.wait();
      
      // چک کنیم که event جدیدی emit نشده
      const events = receipt.logs.filter(log => log.address === accessControl.target);
      expect(events.length).to.equal(0);
    });
  });
}); 