const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    console.log("🚀 شروع deploy کانترکت‌های ساده...");
    
    const [deployer] = await ethers.getSigners();
    console.log("👤 Deploying with account:", deployer.address);
    
    // چک کردن موجودی
    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("💰 Account balance:", ethers.formatEther(balance), "ETH");
    
    const deployedContracts = {};
    
    try {
        // 1. Deploy Simple LAXCE Token
        console.log("\n🪙 Deploying SimpleLAXCE Token...");
        const SimpleLAXCE = await ethers.getContractFactory("SimpleLAXCE");
        
        // 1 billion tokens with 18 decimals
        const totalSupply = ethers.parseEther("1000000000");
        
        const laxce = await SimpleLAXCE.deploy(totalSupply, deployer.address);
        await laxce.waitForDeployment();
        const laxceAddress = await laxce.getAddress();
        deployedContracts.SimpleLAXCE = laxceAddress;
        console.log("✅ SimpleLAXCE deployed to:", laxceAddress);
        
        // 2. Deploy Simple Token Registry
        console.log("\n📝 Deploying SimpleTokenRegistry...");
        const SimpleTokenRegistry = await ethers.getContractFactory("SimpleTokenRegistry");
        const tokenRegistry = await SimpleTokenRegistry.deploy(deployer.address);
        await tokenRegistry.waitForDeployment();
        const tokenRegistryAddress = await tokenRegistry.getAddress();
        deployedContracts.SimpleTokenRegistry = tokenRegistryAddress;
        console.log("✅ SimpleTokenRegistry deployed to:", tokenRegistryAddress);
        
        // 3. Deploy Simple Quoter
        console.log("\n💭 Deploying SimpleQuoter...");
        const SimpleQuoter = await ethers.getContractFactory("SimpleQuoter");
        const quoter = await SimpleQuoter.deploy(
            laxceAddress,
            tokenRegistryAddress,
            deployer.address
        );
        await quoter.waitForDeployment();
        const quoterAddress = await quoter.getAddress();
        deployedContracts.SimpleQuoter = quoterAddress;
        console.log("✅ SimpleQuoter deployed to:", quoterAddress);
        
        // 4. Deploy Simple Router
        console.log("\n🛣️ Deploying SimpleRouter...");
        const SimpleRouter = await ethers.getContractFactory("SimpleRouter");
        const router = await SimpleRouter.deploy(
            laxceAddress,
            tokenRegistryAddress,
            quoterAddress,
            deployer.address
        );
        await router.waitForDeployment();
        const routerAddress = await router.getAddress();
        deployedContracts.SimpleRouter = routerAddress;
        console.log("✅ SimpleRouter deployed to:", routerAddress);
        
        // Save addresses to file
        const addressesPath = path.join(__dirname, "../deployed-addresses.json");
        const network = await ethers.provider.getNetwork();
        const addressesData = {
            network: network.name,
            chainId: network.chainId.toString(),
            deployer: deployer.address,
            timestamp: new Date().toISOString(),
            contracts: deployedContracts
        };
        
        fs.writeFileSync(addressesPath, JSON.stringify(addressesData, null, 2));
        console.log("\n📄 Contract addresses saved to:", addressesPath);
        
        // Setup basic configuration
        console.log("\n⚙️ Setting up basic configuration...");
        
        // Register LAXCE token
        await tokenRegistry.registerToken(laxceAddress, "LAXCE Token", "LAXCE");
        console.log("✅ LAXCE token registered");
        
        // Set LAXCE price (mock price: 1 LAXCE = 0.001 ETH)
        const laxcePrice = ethers.parseEther("0.001");
        await quoter.updatePrice(laxceAddress, laxcePrice);
        console.log("✅ LAXCE price set to:", ethers.formatEther(laxcePrice), "ETH");
        
        // Add some test tokens for different networks
        const network_info = await ethers.provider.getNetwork();
        const chainId = network_info.chainId;
        
        if (chainId === 80001n) { // Polygon Mumbai
            console.log("🔗 Setting up Mumbai testnet tokens...");
            const WMATIC = "0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889";
            const USDC = "0x742d35Cc6634C0532925a3b8D084dF0e29bD62df"; // Mock USDC on Mumbai
            
            await tokenRegistry.registerToken(WMATIC, "Wrapped Matic", "WMATIC");
            await quoter.updatePrice(WMATIC, ethers.parseEther("0.0008")); // 1 MATIC = 0.0008 ETH
            
            await tokenRegistry.registerToken(USDC, "USD Coin", "USDC");
            await quoter.updatePrice(USDC, ethers.parseEther("0.0005")); // 1 USDC = 0.0005 ETH
            
            console.log("✅ Mumbai tokens registered");
        } else if (chainId === 11155111n) { // Sepolia
            console.log("🔗 Setting up Sepolia testnet tokens...");
            // Add common Sepolia test tokens if available
        }
        
        // Add some liquidity to router for testing
        console.log("\n💰 Adding initial liquidity...");
        const liquidityAmount = ethers.parseEther("1000000"); // 1M tokens
        await laxce.approve(routerAddress, liquidityAmount);
        await router.addLiquidity(laxceAddress, liquidityAmount);
        console.log("✅ Added", ethers.formatEther(liquidityAmount), "LAXCE to router");
        
        // Show final summary
        console.log("\n🎉 Deployment Summary:");
        console.log("========================");
        for (const [name, address] of Object.entries(deployedContracts)) {
            console.log(`${name}: ${address}`);
        }
        
        console.log("\n📊 Contract Info:");
        console.log("Network:", network.name);
        console.log("Chain ID:", chainId.toString());
        console.log("Gas used: Check transaction receipts");
        console.log("LAXCE Total Supply:", ethers.formatEther(totalSupply));
        
        console.log("\n🔄 Next Steps:");
        console.log("1. Update Flutter app with new contract addresses");
        console.log("2. Test basic token operations");
        console.log("3. Test swap functionality");
        console.log("4. Add more test tokens as needed");
        
        console.log("\n🚀 Simple contracts deployment completed successfully!");
        
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