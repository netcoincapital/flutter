const { ethers } = require("hardhat");

async function main() {
    console.log("🚀 Starting Simple LAXCE DEX Deployment");
    console.log("=====================================");

    const [deployer] = await ethers.getSigners();
    console.log("Deploying with account:", deployer.address);
    
    const balance = await deployer.provider.getBalance(deployer.address);
    console.log("Account balance:", ethers.formatEther(balance), "ETH");

    // Configuration
    const treasury = deployer.address; // For testing, use deployer as treasury
    const teamWallet = deployer.address;
    const marketingWallet = deployer.address;

    try {
        // 1. Deploy AccessControl first
        console.log("\n📋 Deploying AccessControl...");
        const AccessControl = await ethers.getContractFactory("LaxceAccessControl");
        const accessControl = await AccessControl.deploy();
        await accessControl.waitForDeployment();
        const accessControlAddress = await accessControl.getAddress();
        console.log("✅ AccessControl deployed:", accessControlAddress);

        // 2. Deploy LAXCE Token
        console.log("\n🪙 Deploying LAXCE Token...");
        const LAXCE = await ethers.getContractFactory("LAXCE");
        const laxce = await LAXCE.deploy(treasury, teamWallet, marketingWallet);
        await laxce.waitForDeployment();
        const laxceAddress = await laxce.getAddress();
        console.log("✅ LAXCE Token deployed:", laxceAddress);

        // 3. Deploy TokenRegistry
        console.log("\n📚 Deploying TokenRegistry...");
        const TokenRegistry = await ethers.getContractFactory("TokenRegistry");
        const tokenRegistry = await TokenRegistry.deploy();
        await tokenRegistry.waitForDeployment();
        const tokenRegistryAddress = await tokenRegistry.getAddress();
        console.log("✅ TokenRegistry deployed:", tokenRegistryAddress);

        // 4. Deploy basic Pool Factory (if it compiles)
        let poolFactoryAddress = null;
        try {
            console.log("\n🏊 Deploying PoolFactory...");
            const PoolFactory = await ethers.getContractFactory("PoolFactory");
            const poolFactory = await PoolFactory.deploy();
            await poolFactory.waitForDeployment();
            poolFactoryAddress = await poolFactory.getAddress();
            console.log("✅ PoolFactory deployed:", poolFactoryAddress);
        } catch (error) {
            console.log("⚠️ PoolFactory deployment failed:", error.message);
        }

        // Summary
        console.log("\n🎉 Deployment Summary");
        console.log("=====================");
        console.log("AccessControl:", accessControlAddress);
        console.log("LAXCE Token:", laxceAddress);
        console.log("TokenRegistry:", tokenRegistryAddress);
        if (poolFactoryAddress) {
            console.log("PoolFactory:", poolFactoryAddress);
        }

        // Save addresses to file
        const addresses = {
            network: await ethers.provider.getNetwork().then(n => n.name),
            chainId: await ethers.provider.getNetwork().then(n => n.chainId.toString()),
            deployer: deployer.address,
            contracts: {
                AccessControl: accessControlAddress,
                LAXCE: laxceAddress,
                TokenRegistry: tokenRegistryAddress,
                PoolFactory: poolFactoryAddress
            },
            deployedAt: new Date().toISOString()
        };

        const fs = require('fs');
        const deploymentFile = `deployment-${Date.now()}.json`;
        fs.writeFileSync(deploymentFile, JSON.stringify(addresses, null, 2));
        console.log(`\n📝 Deployment info saved to: ${deploymentFile}`);

        return addresses;

    } catch (error) {
        console.error("❌ Deployment failed:", error);
        throw error;
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