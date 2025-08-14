const { ethers } = require("hardhat");

/**
 * @title Deploy Token Layer
 * @dev اسکریپت deployment برای لایه Token (Layer 2)
 */
async function deployTokenLayer(deploymentContext) {
  const { deployer, network, addresses, abis } = deploymentContext;
  
  console.log("  🪙 Deploying Token Layer contracts...");
  
  try {
    // بررسی وجود Core Layer و Security Layer
    if (!addresses.accessControl) {
      throw new Error("Core Layer not deployed. Deploy Core Layer first.");
    }
    
    // Deploy a minimal SecurityManager for now (if not exists)
    let securityManagerAddress = addresses.securityManager;
    if (!securityManagerAddress) {
      console.log("    🔐 Deploying minimal SecurityManager for tokens...");
      const SecurityManager = await ethers.getContractFactory("SecurityManager");
      const securityManager = await SecurityManager.connect(deployer).deploy(deployer.address);
      await securityManager.waitForDeployment();
      securityManagerAddress = await securityManager.getAddress();
      addresses.securityManager = securityManagerAddress;
      console.log(`    ✅ SecurityManager deployed: ${securityManagerAddress}`);
    }
    
    // ==================== LAXCE TOKEN ====================
    console.log("    💎 Deploying LAXCE Token...");
    
    const initialSupply = ethers.parseEther("10000000"); // 10M tokens
    
    const LAXCE = await ethers.getContractFactory("LAXCE");
    const laxce = await LAXCE.connect(deployer).deploy(
      deployer.address,
      initialSupply,
      securityManagerAddress
    );
    await laxce.waitForDeployment();
    
    const laxceAddress = await laxce.getAddress();
    console.log(`    ✅ LAXCE Token deployed to: ${laxceAddress}`);
    
    // ذخیره آدرس و ABI
    addresses.laxceToken = laxceAddress;
    abis.LAXCE = LAXCE.interface.format('json');
    
    // ==================== TOKEN REGISTRY ====================
    console.log("    📋 Deploying Token Registry...");
    
    const TokenRegistry = await ethers.getContractFactory("TokenRegistry");
    const tokenRegistry = await TokenRegistry.connect(deployer).deploy(
      laxceAddress,
      deployer.address
    );
    await tokenRegistry.waitForDeployment();
    
    const tokenRegistryAddress = await tokenRegistry.getAddress();
    console.log(`    ✅ Token Registry deployed to: ${tokenRegistryAddress}`);
    
    // ذخیره آدرس و ABI
    addresses.tokenRegistry = tokenRegistryAddress;
    abis.TokenRegistry = TokenRegistry.interface.format('json');
    
    // ==================== SAMPLE LP TOKEN ====================
    console.log("    🏊 Deploying Sample LP Token...");
    
    // برای نمونه یک LP Token ایجاد می‌کنیم
    const LPToken = await ethers.getContractFactory("LPToken");
    const lpToken = await LPToken.connect(deployer).deploy(
      "LAXCE LP Token", // name
      "LAXCE-LP",       // symbol
      laxceAddress,     // laxce token address
      deployer.address, // temporary pool address (will be updated later)
      deployer.address  // owner
    );
    await lpToken.waitForDeployment();
    
    const lpTokenAddress = await lpToken.getAddress();
    console.log(`    ✅ Sample LP Token deployed to: ${lpTokenAddress}`);
    
    // ذخیره آدرس و ABI
    addresses.sampleLPToken = lpTokenAddress;
    abis.LPToken = LPToken.interface.format('json');
    
    // ==================== INITIAL CONFIGURATION ====================
    
    console.log("    ⚙️ Configuring Token Layer...");
    
    // Transfer some LAXCE tokens to contract for rewards
    const rewardAmount = ethers.parseEther("1000000"); // 1M tokens for rewards
    await laxce.transfer(lpTokenAddress, rewardAmount);
    console.log(`    ✅ Transferred ${ethers.formatEther(rewardAmount)} LAXCE for LP rewards`);
    
    // Grant admin role to deployer for TokenRegistry
    const ADMIN_ROLE = await tokenRegistry.ADMIN_ROLE();
    // Deployer already has admin role from constructor
    
    // ==================== VERIFICATION ====================
    
    // Verify LAXCE Token
    const totalSupply = await laxce.totalSupply();
    const maxSupply = await laxce.MAX_SUPPLY();
    
    if (totalSupply > maxSupply) {
      throw new Error("LAXCE Token verification failed: supply exceeds maximum");
    }
    
    // Verify Token Registry
    const laxceTokenInRegistry = await tokenRegistry.laxceToken();
    if (laxceTokenInRegistry !== laxceAddress) {
      throw new Error("Token Registry verification failed: incorrect LAXCE address");
    }
    
    // Verify LP Token
    const laxceTokenInLP = await lpToken.laxceToken();
    if (laxceTokenInLP !== laxceAddress) {
      throw new Error("LP Token verification failed: incorrect LAXCE address");
    }
    
    console.log("    ✅ Token Layer verification passed");
    
    // ==================== SUMMARY ====================
    
    console.log("  🎉 Token Layer deployment completed!");
    console.log(`    💎 LAXCE Token: ${laxceAddress}`);
    console.log(`    📋 Token Registry: ${tokenRegistryAddress}`);
    console.log(`    🏊 Sample LP Token: ${lpTokenAddress}`);
    console.log(`    💰 Initial Supply: ${ethers.formatEther(totalSupply)} LAXCE`);
    console.log(`    🎁 Reward Pool: ${ethers.formatEther(rewardAmount)} LAXCE`);
    console.log(`    ⛽ Total Gas used: ${await getTotalGasUsed([laxce, tokenRegistry, lpToken])}`);
    
    return {
      laxceToken: {
        contract: laxce,
        address: laxceAddress,
      },
      tokenRegistry: {
        contract: tokenRegistry,
        address: tokenRegistryAddress,
      },
      lpToken: {
        contract: lpToken,
        address: lpTokenAddress,
      }
    };
    
  } catch (error) {
    console.error("    ❌ Token Layer deployment failed:", error.message);
    throw error;
  }
}

/**
 * @dev محاسبه کل gas استفاده شده
 */
async function getTotalGasUsed(contracts) {
  let totalGas = 0n;
  
  for (const contract of contracts) {
    try {
      const deploymentTx = contract.deploymentTransaction();
      if (deploymentTx) {
        const receipt = await deploymentTx.wait();
        totalGas += receipt.gasUsed;
      }
    } catch (error) {
      // Ignore errors for gas calculation
    }
  }
  
  return totalGas.toString();
}

/**
 * @dev اجرای deployment اگر این فایل مستقیماً اجرا شود
 */
async function main() {
  const [deployer] = await ethers.getSigners();
  
  const deploymentContext = {
    deployer,
    network: network.name,
    addresses: {
      // Mock core layer address for testing
      accessControl: "0x1234567890123456789012345678901234567890"
    },
    abis: {},
    deployedAt: new Date().toISOString(),
  };
  
  console.log("🚀 Deploying Token Layer only...");
  console.log("Deployer:", deployer.address);
  console.log("Network:", network.name);
  console.log("Balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH");
  
  const result = await deployTokenLayer(deploymentContext);
  
  console.log("\n📄 Token Layer Deployment Summary:");
  console.log(JSON.stringify({
    laxceToken: deploymentContext.addresses.laxceToken,
    tokenRegistry: deploymentContext.addresses.tokenRegistry,
    sampleLPToken: deploymentContext.addresses.sampleLPToken,
  }, null, 2));
  
  console.log("\n🎯 Next Steps:");
  console.log("1. Deploy Pool Layer (Layer 3)");
  console.log("2. Connect LP Tokens to actual pools");
  console.log("3. Set up proper reward distribution");
  console.log("4. Test token locking and fee discounts");
  console.log("5. Set up token listing process");
}

// Export برای استفاده در deploy.js اصلی
module.exports = deployTokenLayer;

// اجرا اگر مستقیماً فراخوانی شود
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("💥 Token Layer deployment failed:", error);
      process.exit(1);
    });
} 