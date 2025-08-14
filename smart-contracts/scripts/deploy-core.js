const { ethers } = require("hardhat");

/**
 * @title Deploy Core Layer
 * @dev اسکریپت deployment برای لایه Core (Layer 1)
 */
async function deployCoreLayer(deploymentContext) {
  const { deployer, network, addresses, abis } = deploymentContext;
  
  console.log("  🔧 Deploying Core Layer contracts...");
  
  try {
    // ==================== ACCESS CONTROL ====================
    console.log("    📋 Deploying AccessControl...");
    
    const AccessControl = await ethers.getContractFactory("AccessControl");
    const accessControl = await AccessControl.connect(deployer).deploy(deployer.address);
    await accessControl.waitForDeployment();
    
    const accessControlAddress = await accessControl.getAddress();
    console.log(`    ✅ AccessControl deployed to: ${accessControlAddress}`);
    
    // ذخیره آدرس و ABI
    addresses.accessControl = accessControlAddress;
    abis.AccessControl = AccessControl.interface.format('json');
    
    // ==================== VERIFICATION ====================
    
    // بررسی deployment
    const ownerRole = await accessControl.OWNER_ROLE();
    const hasOwnerRole = await accessControl.hasRole(ownerRole, deployer.address);
    
    if (!hasOwnerRole) {
      throw new Error("AccessControl deployment verification failed");
    }
    
    console.log("    ✅ AccessControl verification passed");
    
    // ==================== ROLE SETUP ====================
    
    console.log("    🔑 Setting up additional roles...");
    
    // Admin role برای مدیریت عملیات روزانه
    const adminRole = await accessControl.ADMIN_ROLE();
    // در صورت نیاز می‌توان admin اضافی تعریف کرد
    
    // Emergency role برای شرایط اضطراری
    const emergencyRole = await accessControl.EMERGENCY_ROLE();
    // فعلاً owner خودش emergency access دارد
    
    console.log("    ✅ Core Layer roles configured");
    
    // ==================== SUMMARY ====================
    
    console.log("  🎉 Core Layer deployment completed!");
    console.log(`    📍 AccessControl: ${accessControlAddress}`);
    console.log(`    🔑 Owner: ${deployer.address}`);
    console.log(`    ⛽ Gas used: ${await getGasUsed(accessControl)}`);
    
    return {
      accessControl: {
        contract: accessControl,
        address: accessControlAddress,
      }
    };
    
  } catch (error) {
    console.error("    ❌ Core Layer deployment failed:", error.message);
    throw error;
  }
}

/**
 * @dev محاسبه gas استفاده شده
 */
async function getGasUsed(contract) {
  try {
    const deploymentTx = contract.deploymentTransaction();
    if (deploymentTx) {
      const receipt = await deploymentTx.wait();
      return receipt.gasUsed.toString();
    }
    return "Unknown";
  } catch {
    return "Unknown";
  }
}

/**
 * @dev اجرای deployment اگر این فایل مستقیماً اجرا شود
 */
async function main() {
  const [deployer] = await ethers.getSigners();
  
  const deploymentContext = {
    deployer,
    network: network.name,
    addresses: {},
    abis: {},
    deployedAt: new Date().toISOString(),
  };
  
  console.log("🚀 Deploying Core Layer only...");
  console.log("Deployer:", deployer.address);
  console.log("Network:", network.name);
  
  const result = await deployCoreLayer(deploymentContext);
  
  console.log("\n📄 Deployment Summary:");
  console.log(JSON.stringify(deploymentContext.addresses, null, 2));
}

// Export برای استفاده در deploy.js اصلی
module.exports = deployCoreLayer;

// اجرا اگر مستقیماً فراخوانی شود
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("💥 Deployment failed:", error);
      process.exit(1);
    });
} 