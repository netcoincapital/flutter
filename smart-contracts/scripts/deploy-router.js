const { ethers, upgrades } = require("hardhat");
const { verifyContract } = require("./utils/verify");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("🚀 Starting Router Layer deployment...");
  
  const [deployer] = await ethers.getSigners();
  console.log("📍 Deploying with account:", deployer.address);
  
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("💰 Account balance:", ethers.formatEther(balance), "ETH");

  // Load existing deployment addresses
  const networkName = hre.network.name;
  const deploymentPath = path.join(__dirname, "..", "deployments", `${networkName}.json`);
  
  let deployments = {};
  if (fs.existsSync(deploymentPath)) {
    deployments = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
    console.log("📖 Loaded existing deployments");
  } else {
    console.log("⚠️  No existing deployments found");
    return;
  }

  // Check for required previous deployments
  const requiredContracts = ["Constants", "ReentrancyGuard", "TickMath", "FeeManager", "PoolFactory"];
  for (const contract of requiredContracts) {
    if (!deployments[contract]) {
      console.error(`❌ Required contract ${contract} not found in deployments`);
      return;
    }
  }

  try {
    // ==================== DEPLOY PATHFINDER ====================
    console.log("\n📍 1. Deploying PathFinder...");
    
    const PathFinder = await ethers.getContractFactory("PathFinder", {
      libraries: {
        Constants: deployments.Constants,
        TickMath: deployments.TickMath,
        FeeManager: deployments.FeeManager,
        ReentrancyGuard: deployments.ReentrancyGuard
      }
    });

    const pathFinder = await PathFinder.deploy(deployments.PoolFactory);
    await pathFinder.waitForDeployment();
    
    const pathFinderAddress = await pathFinder.getAddress();
    console.log("✅ PathFinder deployed to:", pathFinderAddress);
    
    deployments.PathFinder = pathFinderAddress;

    // ==================== DEPLOY ROUTER ====================
    console.log("\n📍 2. Deploying Router...");
    
    // Get WETH address (network dependent)
    let wethAddress;
    if (networkName === "mainnet") {
      wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"; // Mainnet WETH
    } else if (networkName === "polygon") {
      wethAddress = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"; // Polygon WMATIC
    } else if (networkName === "arbitrum") {
      wethAddress = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"; // Arbitrum WETH
    } else if (networkName === "sepolia") {
      wethAddress = "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"; // Sepolia WETH
    } else {
      // For localhost/hardhat, deploy a mock WETH
      console.log("📍 Deploying Mock WETH for local network...");
      const MockWETH = await ethers.getContractFactory("MockWETH");
      const mockWETH = await MockWETH.deploy();
      await mockWETH.waitForDeployment();
      wethAddress = await mockWETH.getAddress();
      console.log("✅ Mock WETH deployed to:", wethAddress);
      deployments.WETH = wethAddress;
    }

    // Note: PoolManager should be deployed in Pool Layer
    // For now, we'll use a placeholder or deploy a mock
    let poolManagerAddress = deployments.PoolManager;
    if (!poolManagerAddress) {
      console.log("📍 PoolManager not found, deploying Mock PoolManager...");
      const MockPoolManager = await ethers.getContractFactory("MockPoolManager");
      const mockPoolManager = await MockPoolManager.deploy();
      await mockPoolManager.waitForDeployment();
      poolManagerAddress = await mockPoolManager.getAddress();
      console.log("✅ Mock PoolManager deployed to:", poolManagerAddress);
      deployments.MockPoolManager = poolManagerAddress;
    }

    const Router = await ethers.getContractFactory("Router", {
      libraries: {
        Constants: deployments.Constants,
        ReentrancyGuard: deployments.ReentrancyGuard
      }
    });

    const router = await Router.deploy(
      deployments.PoolFactory,
      pathFinderAddress,
      poolManagerAddress,
      wethAddress
    );
    await router.waitForDeployment();
    
    const routerAddress = await router.getAddress();
    console.log("✅ Router deployed to:", routerAddress);
    
    deployments.Router = routerAddress;

    // ==================== INITIAL CONFIGURATION ====================
    console.log("\n⚙️  3. Configuring contracts...");

    // Configure PathFinder
    console.log("📍 Configuring PathFinder...");
    
    // Set reasonable cache timeout and slippage
    const cacheTimeout = 300; // 5 minutes
    const maxSlippage = 50; // 0.5%
    const useCache = true;
    
    await pathFinder.setConfiguration(cacheTimeout, maxSlippage, useCache);
    console.log(`✅ PathFinder configured: cache=${cacheTimeout}s, slippage=${maxSlippage}bp`);

    // Grant operator role to deployer for PathFinder
    const OPERATOR_ROLE = await pathFinder.OPERATOR_ROLE();
    await pathFinder.grantRole(OPERATOR_ROLE, deployer.address);
    console.log("✅ Granted OPERATOR_ROLE to deployer for PathFinder");

    // Configure Router
    console.log("📍 Configuring Router...");
    
    // Set default slippage and deadline
    const defaultSlippage = 50; // 0.5%
    const defaultDeadline = 1200; // 20 minutes
    
    await router.setDefaultSlippage(defaultSlippage);
    await router.setDefaultDeadline(defaultDeadline);
    console.log(`✅ Router configured: slippage=${defaultSlippage}bp, deadline=${defaultDeadline}s`);

    // Set fee recipient to deployer initially
    await router.setFeeRecipient(deployer.address);
    console.log("✅ Set fee recipient to deployer");

    // ==================== ROLE SETUP ====================
    console.log("\n👥 4. Setting up roles...");

    // Grant roles for Router
    const ADMIN_ROLE = await router.ADMIN_ROLE();
    const PAUSER_ROLE = await router.PAUSER_ROLE();
    
    await router.grantRole(ADMIN_ROLE, deployer.address);
    await router.grantRole(PAUSER_ROLE, deployer.address);
    console.log("✅ Granted ADMIN_ROLE and PAUSER_ROLE to deployer for Router");

    // ==================== SAVE DEPLOYMENTS ====================
    console.log("\n💾 5. Saving deployment addresses...");
    
    // Add deployment timestamp and network info
    deployments._meta = {
      ...deployments._meta,
      router_deployed_at: new Date().toISOString(),
      router_deployer: deployer.address,
      router_network: networkName,
      router_block: await ethers.provider.getBlockNumber()
    };

    // Ensure deployments directory exists
    const deploymentsDir = path.dirname(deploymentPath);
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }

    // Save updated deployments
    fs.writeFileSync(deploymentPath, JSON.stringify(deployments, null, 2));
    console.log("✅ Saved deployment addresses to:", deploymentPath);

    // ==================== VERIFICATION ====================
    if (networkName !== "hardhat" && networkName !== "localhost") {
      console.log("\n🔍 6. Verifying contracts...");
      
      try {
        // Verify PathFinder
        await verifyContract(pathFinderAddress, [deployments.PoolFactory]);
        console.log("✅ PathFinder verified");
        
        // Verify Router
        await verifyContract(routerAddress, [
          deployments.PoolFactory,
          pathFinderAddress,
          poolManagerAddress,
          wethAddress
        ]);
        console.log("✅ Router verified");
        
      } catch (error) {
        console.log("⚠️  Verification failed:", error.message);
        console.log("ℹ️  You can verify manually later using the addresses above");
      }
    }

    // ==================== SUMMARY ====================
    console.log("\n📋 ===== ROUTER LAYER DEPLOYMENT SUMMARY =====");
    console.log("🔗 Network:", networkName);
    console.log("👤 Deployer:", deployer.address);
    console.log("📍 PathFinder:", pathFinderAddress);
    console.log("📍 Router:", routerAddress);
    console.log("📍 WETH:", wethAddress);
    console.log("📍 PoolManager:", poolManagerAddress);
    
    console.log("\n⚙️  Configuration:");
    console.log("📍 PathFinder cache timeout:", cacheTimeout, "seconds");
    console.log("📍 PathFinder max slippage:", maxSlippage, "basis points");
    console.log("📍 Router default slippage:", defaultSlippage, "basis points");
    console.log("📍 Router default deadline:", defaultDeadline, "seconds");
    
    console.log("\n🎯 Next Steps:");
    console.log("1. Update pool information in PathFinder");
    console.log("2. Configure token approvals in Router if using whitelist");
    console.log("3. Set up monitoring for swap events");
    console.log("4. Test swap functionality");
    console.log("5. Deploy Oracle Layer (Layer 5)");
    
    console.log("\n✅ Router Layer deployment completed successfully!");

  } catch (error) {
    console.error("❌ Router Layer deployment failed:", error);
    process.exit(1);
  }
}

// Execute deployment
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

module.exports = main; 