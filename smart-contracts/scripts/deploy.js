const { ethers, network } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Import deployment scripts for each layer
const deployCoreLayer = require("./deploy-core");
const deployTokenLayer = require("./deploy-tokens");
const deployPoolLayer = require("./deploy-pools");
const deploySwapLayer = require("./deploy-swap");
const deployLiquidityLayer = require("./deploy-liquidity");
const deployFeeLayer = require("./deploy-fees");
const deployRouterLayer = require("./deploy-router");
const deployGovernanceLayer = require("./deploy-governance");
const deploySecurityLayer = require("./deploy-security");

async function main() {
  console.log("🚀 Starting LAXCE DEX deployment on", network.name);
  console.log("==================================================");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH");

  // Deployment context to pass between layers
  const deploymentContext = {
    deployer,
    network: network.name,
    addresses: {},
    abis: {},
    deployedAt: new Date().toISOString(),
  };

  try {
    // Layer 1: Core Infrastructure
    console.log("\n📋 Deploying Layer 1: Core Infrastructure");
    await deployCoreLayer(deploymentContext);

    // Layer 2: Token Management
    console.log("\n🪙 Deploying Layer 2: Token Management");
    await deployTokenLayer(deploymentContext);

    // Layer 3: Pool Management
    console.log("\n🏊 Deploying Layer 3: Pool Management");
    await deployPoolLayer(deploymentContext);

    // Layer 4: Swap Operations
    console.log("\n🔄 Deploying Layer 4: Swap Operations");
    await deploySwapLayer(deploymentContext);

    // Layer 5: Liquidity Management
    console.log("\n💧 Deploying Layer 5: Liquidity Management");
    await deployLiquidityLayer(deploymentContext);

    // Layer 6: Fee Management
    console.log("\n💰 Deploying Layer 6: Fee Management");
    await deployFeeLayer(deploymentContext);

    // Layer 7: Router & Path Finding
    console.log("\n🗺️ Deploying Layer 7: Router & Path Finding");
    await deployRouterLayer(deploymentContext);

    // Layer 8: Governance
    console.log("\n🏛️ Deploying Layer 8: Governance");
    await deployGovernanceLayer(deploymentContext);

    // Layer 9: Security
    console.log("\n🛡️ Deploying Layer 9: Security");
    await deploySecurityLayer(deploymentContext);

    // Save deployment information
    await saveDeploymentInfo(deploymentContext);

    console.log("\n✅ All layers deployed successfully!");
    console.log("==================================================");
    console.log("📁 Deployment information saved to:", `deploy/addresses/${network.name}.json`);

  } catch (error) {
    console.error("\n❌ Deployment failed:", error);
    process.exit(1);
  }
}

async function saveDeploymentInfo(context) {
  const deployDir = path.join(__dirname, "..", "deploy");
  const addressesDir = path.join(deployDir, "addresses");
  const abisDir = path.join(deployDir, "abis");

  // Create directories if they don't exist
  [deployDir, addressesDir, abisDir].forEach(dir => {
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  });

  // Save addresses
  const addressFile = path.join(addressesDir, `${context.network}.json`);
  const deploymentInfo = {
    network: context.network,
    deployedAt: context.deployedAt,
    deployer: context.deployer.address,
    addresses: context.addresses,
    gasUsed: await calculateTotalGasUsed(context),
  };

  fs.writeFileSync(addressFile, JSON.stringify(deploymentInfo, null, 2));

  // Save ABIs
  for (const [contractName, abi] of Object.entries(context.abis)) {
    const abiFile = path.join(abisDir, `${contractName}.json`);
    fs.writeFileSync(abiFile, JSON.stringify(abi, null, 2));
  }

  console.log(`📄 Saved addresses to: ${addressFile}`);
  console.log(`📄 Saved ABIs to: ${abisDir}/`);
}

async function calculateTotalGasUsed(context) {
  // This would calculate total gas used across all deployments
  // Implementation depends on how we track gas usage
  return {
    total: "0",
    byLayer: {},
  };
}

// Utility function to deploy a contract
async function deployContract(contractName, args = [], deployer) {
  console.log(`  📤 Deploying ${contractName}...`);
  
  const ContractFactory = await ethers.getContractFactory(contractName);
  const contract = await ContractFactory.connect(deployer).deploy(...args);
  await contract.waitForDeployment();
  
  const address = await contract.getAddress();
  console.log(`  ✅ ${contractName} deployed to: ${address}`);
  
  return {
    contract,
    address,
    abi: ContractFactory.interface.format('json'),
  };
}

// Export utility function for use in layer deployment scripts
module.exports = {
  deployContract,
  saveDeploymentInfo,
};

// Run deployment if this script is executed directly
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
} 