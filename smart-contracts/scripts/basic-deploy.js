const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    console.log("🚀 شروع deploy کانترکت‌های اساسی...");
    
    const [deployer] = await ethers.getSigners();
    console.log("👤 Deploying with account:", deployer.address);
    
    // چک کردن موجودی
    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("💰 Account balance:", ethers.formatEther(balance), "ETH");
    
    const deployedContracts = {};
    
    try {
        // 1. Deploy AccessControl
        console.log("\n📋 Deploying LaxceAccessControl...");
        const AccessControl = await ethers.getContractFactory("LaxceAccessControl");
        const accessControl = await AccessControl.deploy();
        await accessControl.waitForDeployment();
        const accessControlAddress = await accessControl.getAddress();
        deployedContracts.LaxceAccessControl = accessControlAddress;
        console.log("✅ LaxceAccessControl deployed to:", accessControlAddress);
        
        // 2. Deploy LAXCE Token
        console.log("\n🪙 Deploying LAXCE Token...");
        const LAXCE = await ethers.getContractFactory("LAXCE");
        
        // پارامترهای LAXCE token
        const initialSupply = ethers.parseEther("1000000000"); // 1 billion tokens
        const treasuryWallet = deployer.address; // در testnet از deployer استفاده می‌کنیم
        const teamWallet = deployer.address;
        const marketingWallet = deployer.address;
        
        const laxce = await LAXCE.deploy(
            accessControlAddress,
            initialSupply,
            treasuryWallet,
            teamWallet,
            marketingWallet
        );
        await laxce.waitForDeployment();
        const laxceAddress = await laxce.getAddress();
        deployedContracts.LAXCE = laxceAddress;
        console.log("✅ LAXCE Token deployed to:", laxceAddress);
        
        // 3. Deploy TokenRegistry
        console.log("\n📝 Deploying TokenRegistry...");
        const TokenRegistry = await ethers.getContractFactory("TokenRegistry");
        const tokenRegistry = await TokenRegistry.deploy(accessControlAddress);
        await tokenRegistry.waitForDeployment();
        const tokenRegistryAddress = await tokenRegistry.getAddress();
        deployedContracts.TokenRegistry = tokenRegistryAddress;
        console.log("✅ TokenRegistry deployed to:", tokenRegistryAddress);
        
        // 4. Deploy PoolFactory (اگر کامپایل شود)
        try {
            console.log("\n🏭 Deploying PoolFactory...");
            const PoolFactory = await ethers.getContractFactory("PoolFactory");
            const poolFactory = await PoolFactory.deploy(accessControlAddress);
            await poolFactory.waitForDeployment();
            const poolFactoryAddress = await poolFactory.getAddress();
            deployedContracts.PoolFactory = poolFactoryAddress;
            console.log("✅ PoolFactory deployed to:", poolFactoryAddress);
        } catch (error) {
            console.log("⚠️ PoolFactory deployment failed:", error.message);
        }
        
        // 5. Deploy Quoter (اگر کامپایل شود)
        try {
            console.log("\n💭 Deploying Quoter...");
            const Quoter = await ethers.getContractFactory("Quoter");
            const quoter = await Quoter.deploy(
                accessControlAddress,
                deployedContracts.PoolFactory || ethers.ZeroAddress
            );
            await quoter.waitForDeployment();
            const quoterAddress = await quoter.getAddress();
            deployedContracts.Quoter = quoterAddress;
            console.log("✅ Quoter deployed to:", quoterAddress);
        } catch (error) {
            console.log("⚠️ Quoter deployment failed:", error.message);
        }
        
        // Save addresses to file
        const addressesPath = path.join(__dirname, "../deployed-addresses.json");
        const addressesData = {
            network: hre.network.name,
            chainId: await ethers.provider.getNetwork().then(n => n.chainId),
            deployer: deployer.address,
            timestamp: new Date().toISOString(),
            contracts: deployedContracts
        };
        
        fs.writeFileSync(addressesPath, JSON.stringify(addressesData, null, 2));
        console.log("\n📄 Contract addresses saved to:", addressesPath);
        
        // Show summary
        console.log("\n🎉 Deployment Summary:");
        console.log("========================");
        for (const [name, address] of Object.entries(deployedContracts)) {
            console.log(`${name}: ${address}`);
        }
        
        // Setup basic configuration
        if (deployedContracts.TokenRegistry && deployedContracts.LAXCE) {
            try {
                console.log("\n⚙️ Setting up basic configuration...");
                const tokenRegistryContract = await ethers.getContractAt("TokenRegistry", deployedContracts.TokenRegistry);
                
                // Register LAXCE token
                await tokenRegistryContract.registerToken(deployedContracts.LAXCE, "LAXCE", "LAXCE");
                console.log("✅ LAXCE token registered in TokenRegistry");
                
                // Add some common testnet tokens (if on testnet)
                const network = await ethers.provider.getNetwork();
                if (network.chainId === 80001n) { // Polygon Mumbai
                    // WMATIC testnet address
                    const WMATIC = "0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889";
                    await tokenRegistryContract.registerToken(WMATIC, "WMATIC", "Wrapped Matic");
                    console.log("✅ WMATIC registered in TokenRegistry");
                }
            } catch (error) {
                console.log("⚠️ Configuration setup failed:", error.message);
            }
        }
        
        console.log("\n🚀 Basic deployment completed successfully!");
        
    } catch (error) {
        console.error("❌ Deployment failed:", error);
        throw error;
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    }); 