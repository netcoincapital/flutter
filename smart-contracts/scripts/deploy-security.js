const { ethers } = require("hardhat");

/**
 * @title Deploy Security Layer
 * @dev اسکریپت deployment برای Security Layer (Layer 9)
 */
async function deploySecurityLayer(deploymentContext) {
  const { deployer, network, addresses, abis } = deploymentContext;
  
  console.log("  🔐 Deploying Security Layer contracts...");
  
  try {
    // بررسی وجود Core Layer
    if (!addresses.accessControl) {
      throw new Error("Core Layer not deployed. Deploy Core Layer first.");
    }
    
    // ==================== SECURITY MANAGER ====================
    console.log("    🛡️ Deploying Security Manager...");
    
    const SecurityManager = await ethers.getContractFactory("SecurityManager");
    const securityManager = await SecurityManager.connect(deployer).deploy(
      deployer.address
    );
    await securityManager.waitForDeployment();
    
    const securityManagerAddress = await securityManager.getAddress();
    console.log(`    ✅ Security Manager deployed to: ${securityManagerAddress}`);
    
    // ذخیره آدرس و ABI
    addresses.securityManager = securityManagerAddress;
    abis.SecurityManager = SecurityManager.interface.format('json');
    
    // ==================== INITIAL CONFIGURATION ====================
    
    console.log("    ⚙️ Configuring Security Layer...");
    
    // Configure circuit breaker (5 triggers per hour)
    await securityManager.configureCircuitBreaker(
      5,         // maxTriggers
      3600,      // windowDuration (1 hour)
      true       // isActive
    );
    console.log("    ✅ Circuit breaker configured");
    
    // Configure auto-pause conditions
    await securityManager.configureAutoPause(
      "PRICE_DEVIATION",
      2500,      // 25% threshold
      true,      // enabled
      1800       // 30 min cooldown
    );
    
    await securityManager.configureAutoPause(
      "VOLUME_SPIKE",
      "1000000000000000000000000", // 1M USD threshold (1e24)
      true,
      900        // 15 min cooldown
    );
    
    await securityManager.configureAutoPause(
      "LOW_LIQUIDITY",
      "10000000000000000000000", // 10K USD threshold (1e22)
      true,
      300        // 5 min cooldown
    );
    console.log("    ✅ Auto-pause conditions configured");
    
    // Add deployer as emergency responder (already done in constructor)
    console.log("    ✅ Emergency responder configured");
    
    // ==================== AUTHORIZE FUTURE CONTRACTS ====================
    
    // Pre-authorize known contract addresses (will be updated when they're deployed)
    const contractsToAuthorize = [
      deployer.address, // Temporary for testing
    ];
    
    for (const contractAddr of contractsToAuthorize) {
      await securityManager.authorizeContract(contractAddr, true);
      console.log(`    ✅ Authorized contract: ${contractAddr}`);
    }
    
    // ==================== VERIFICATION ====================
    
    // Test basic functionality
    const stats = await securityManager.getSecurityStats();
    if (stats.systemPaused) {
      throw new Error("Security Manager verification failed: system should not be paused initially");
    }
    
    const cbStats = await securityManager.getCircuitBreakerStats();
    if (!cbStats.isActive || cbStats.maxTriggers !== 5n) {
      throw new Error("Security Manager verification failed: circuit breaker not configured correctly");
    }
    
    // Test token validation with a known address
    const isValidToken = await securityManager.validateToken(securityManagerAddress);
    if (isValidToken) { // SecurityManager is not a token, so this should be false
      console.log("    ⚠️ Warning: Token validation might need adjustment");
    }
    
    console.log("    ✅ Security Layer verification passed");
    
    // ==================== SUMMARY ====================
    
    console.log("  🎉 Security Layer deployment completed!");
    console.log(`    🛡️ Security Manager: ${securityManagerAddress}`);
    console.log(`    🔄 Circuit Breaker: 5 triggers/hour`);
    console.log(`    ⏸️ Auto-Pause: 3 conditions configured`);
    console.log(`    🚨 Emergency Responders: 1 (deployer)`);
    console.log(`    ⛽ Gas used: ${await getGasUsed([securityManager])}`);
    
    return {
      securityManager: {
        contract: securityManager,
        address: securityManagerAddress,
      }
    };
    
  } catch (error) {
    console.error("    ❌ Security Layer deployment failed:", error.message);
    throw error;
  }
}

/**
 * @dev محاسبه کل gas استفاده شده
 */
async function getGasUsed(contracts) {
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
  
  console.log("🚀 Deploying Security Layer only...");
  console.log("Deployer:", deployer.address);
  console.log("Network:", network.name);
  console.log("Balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH");
  
  const result = await deploySecurityLayer(deploymentContext);
  
  console.log("\n📄 Security Layer Deployment Summary:");
  console.log(JSON.stringify({
    securityManager: deploymentContext.addresses.securityManager,
  }, null, 2));
  
  console.log("\n🎯 Next Steps:");
  console.log("1. Update existing contracts to use SecurityManager");
  console.log("2. Authorize pool and swap contracts when deployed");
  console.log("3. Add additional emergency responders");
  console.log("4. Test emergency pause functionality");
  console.log("5. Configure monitoring and alerts");
}

// Export برای استفاده در deploy.js اصلی
module.exports = deploySecurityLayer;

// اجرا اگر مستقیماً فراخوانی شود
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("💥 Security Layer deployment failed:", error);
      process.exit(1);
    });
} 