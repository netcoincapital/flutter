const { ethers, network } = require("hardhat");

// Configuration for different networks
const CONFIG = {
    mainnet: {
        // Mainnet configurations
        feeTiers: [
            { fee: 500, tickSpacing: 10 },      // 0.05%
            { fee: 3000, tickSpacing: 60 },     // 0.3%
            { fee: 10000, tickSpacing: 200 }    // 1%
        ],
        poolManager: {
            defaultSlippage: 500,               // 5%
            autoCompoundEnabled: false,
            minLiquidityForAutoCompound: ethers.utils.parseEther("1000")
        },
        poolFactory: {
            whitelistMode: false,
            maxPools: 100000
        },
        gasLimit: 8000000,
        confirmations: 5
    },
    testnet: {
        // Testnet configurations (more lenient)
        feeTiers: [
            { fee: 500, tickSpacing: 10 },
            { fee: 3000, tickSpacing: 60 },
            { fee: 10000, tickSpacing: 200 },
            { fee: 1500, tickSpacing: 30 }      // Additional tier for testing
        ],
        poolManager: {
            defaultSlippage: 1000,              // 10% (higher for testing)
            autoCompoundEnabled: true,
            minLiquidityForAutoCompound: ethers.utils.parseEther("100")
        },
        poolFactory: {
            whitelistMode: false,
            maxPools: 10000
        },
        gasLimit: 10000000,
        confirmations: 1
    }
};

class PoolLayerDeployer {
    constructor() {
        this.contracts = {};
        this.gasUsed = {};
        this.deploymentInfo = {
            network: network.name,
            timestamp: new Date().toISOString(),
            deployer: null,
            contracts: {}
        };
    }

    async deploy() {
        console.log("\n🚀 Starting Pool Layer Deployment...");
        console.log(`📡 Network: ${network.name}`);
        
        const [deployer] = await ethers.getSigners();
        this.deploymentInfo.deployer = deployer.address;
        
        console.log(`👤 Deployer: ${deployer.address}`);
        console.log(`💰 Balance: ${ethers.utils.formatEther(await deployer.getBalance())} ETH\n`);

        const config = this.getConfig();

        try {
            // Step 1: Check dependencies
            await this.checkDependencies();

            // Step 2: Deploy Pool Layer contracts
            await this.deployPoolFactory(config);
            await this.deployPoolManager(config);

            // Step 3: Configure contracts
            await this.configureContracts(config);

            // Step 4: Verify contracts (if on mainnet/testnet)
            if (network.name !== "hardhat" && network.name !== "localhost") {
                await this.verifyContracts();
            }

            // Step 5: Save deployment info
            await this.saveDeploymentInfo();

            // Step 6: Print summary
            this.printSummary();

        } catch (error) {
            console.error("\n❌ Deployment failed:", error);
            throw error;
        }
    }

    getConfig() {
        const isMainnet = ["ethereum", "polygon", "bsc", "arbitrum"].includes(network.name);
        return isMainnet ? CONFIG.mainnet : CONFIG.testnet;
    }

    async checkDependencies() {
        console.log("🔍 Checking dependencies...");

        // Check if required contracts exist
        const requiredContracts = [
            "LaxceAccessControl",
            "TokenRegistry",
            "PositionNFT",
            "LAXCE",
            "LPToken"
        ];

        for (const contractName of requiredContracts) {
            try {
                await ethers.getContractFactory(contractName);
                console.log(`✅ ${contractName} contract found`);
            } catch (error) {
                throw new Error(`❌ Required contract ${contractName} not found. Please deploy dependencies first.`);
            }
        }

        // Check if WETH9 address is configured
        const wethAddress = process.env.WETH9_ADDRESS;
        if (!wethAddress) {
            throw new Error("❌ WETH9_ADDRESS environment variable not set");
        }

        console.log(`✅ WETH9 address configured: ${wethAddress}`);
        console.log("✅ All dependencies checked\n");
    }

    async deployPoolFactory(config) {
        console.log("📦 Deploying PoolFactory...");

        // Get TokenRegistry address (should be deployed in Layer 2)
        const tokenRegistryAddress = process.env.TOKEN_REGISTRY_ADDRESS || 
            this.contracts.TokenRegistry?.address;

        if (!tokenRegistryAddress) {
            throw new Error("TokenRegistry address not found. Please deploy Token Layer first.");
        }

        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        const poolFactory = await PoolFactory.deploy(
            tokenRegistryAddress,
            {
                gasLimit: config.gasLimit
            }
        );

        await this.waitForConfirmations(poolFactory, config.confirmations);
        
        this.contracts.PoolFactory = poolFactory;
        this.gasUsed.PoolFactory = await this.getGasUsed(poolFactory);

        console.log(`✅ PoolFactory deployed to: ${poolFactory.address}`);
        console.log(`⛽ Gas used: ${this.gasUsed.PoolFactory.toLocaleString()}\n`);

        // Store in deployment info
        this.deploymentInfo.contracts.PoolFactory = {
            address: poolFactory.address,
            gasUsed: this.gasUsed.PoolFactory,
            constructor: {
                tokenRegistry: tokenRegistryAddress
            }
        };
    }

    async deployPoolManager(config) {
        console.log("📦 Deploying PoolManager...");

        // Get required addresses
        const poolFactoryAddress = this.contracts.PoolFactory.address;
        const positionNFTAddress = process.env.POSITION_NFT_ADDRESS ||
            this.contracts.PositionNFT?.address;
        const weth9Address = process.env.WETH9_ADDRESS;

        if (!positionNFTAddress) {
            throw new Error("PositionNFT address not found. Please deploy Token Layer first.");
        }

        const PoolManager = await ethers.getContractFactory("PoolManager");
        const poolManager = await PoolManager.deploy(
            poolFactoryAddress,
            positionNFTAddress,
            weth9Address,
            {
                gasLimit: config.gasLimit
            }
        );

        await this.waitForConfirmations(poolManager, config.confirmations);
        
        this.contracts.PoolManager = poolManager;
        this.gasUsed.PoolManager = await this.getGasUsed(poolManager);

        console.log(`✅ PoolManager deployed to: ${poolManager.address}`);
        console.log(`⛽ Gas used: ${this.gasUsed.PoolManager.toLocaleString()}\n`);

        // Store in deployment info
        this.deploymentInfo.contracts.PoolManager = {
            address: poolManager.address,
            gasUsed: this.gasUsed.PoolManager,
            constructor: {
                factory: poolFactoryAddress,
                positionNFT: positionNFTAddress,
                weth9: weth9Address
            }
        };
    }

    async configureContracts(config) {
        console.log("⚙️ Configuring Pool Layer contracts...");

        // Configure PoolFactory
        await this.configurePoolFactory(config);

        // Configure PoolManager
        await this.configurePoolManager(config);

        console.log("✅ Configuration completed\n");
    }

    async configurePoolFactory(config) {
        console.log("⚙️ Configuring PoolFactory...");

        const poolFactory = this.contracts.PoolFactory;

        // Set up additional fee tiers (beyond defaults)
        for (const tier of config.feeTiers) {
            try {
                const currentTickSpacing = await poolFactory.feeAmountTickSpacing(tier.fee);
                if (currentTickSpacing.toNumber() === 0) {
                    const tx = await poolFactory.enableFeeAmount(tier.fee, tier.tickSpacing);
                    await tx.wait();
                    console.log(`✅ Enabled fee tier: ${tier.fee} (${tier.fee / 10000}%) with tick spacing ${tier.tickSpacing}`);
                } else {
                    console.log(`⚠️ Fee tier ${tier.fee} already enabled`);
                }
            } catch (error) {
                console.log(`⚠️ Error configuring fee tier ${tier.fee}:`, error.message);
            }
        }

        // Configure whitelist mode
        if (config.poolFactory.whitelistMode) {
            const tx = await poolFactory.setWhitelistMode(true);
            await tx.wait();
            console.log("✅ Whitelist mode enabled");
        }
    }

    async configurePoolManager(config) {
        console.log("⚙️ Configuring PoolManager...");

        const poolManager = this.contracts.PoolManager;

        // Set default slippage
        const tx1 = await poolManager.setDefaultSlippage(config.poolManager.defaultSlippage);
        await tx1.wait();
        console.log(`✅ Default slippage set to: ${config.poolManager.defaultSlippage / 100}%`);

        // Configure auto-compound
        const tx2 = await poolManager.setAutoCompoundEnabled(config.poolManager.autoCompoundEnabled);
        await tx2.wait();
        console.log(`✅ Auto-compound enabled: ${config.poolManager.autoCompoundEnabled}`);

        // Set minimum liquidity for auto-compound
        const tx3 = await poolManager.setMinLiquidityForAutoCompound(
            config.poolManager.minLiquidityForAutoCompound
        );
        await tx3.wait();
        console.log(`✅ Min liquidity for auto-compound: ${ethers.utils.formatEther(
            config.poolManager.minLiquidityForAutoCompound
        )} tokens`);
    }

    async waitForConfirmations(contract, confirmations) {
        if (confirmations > 1) {
            console.log(`⏳ Waiting for ${confirmations} confirmations...`);
            await contract.deployTransaction.wait(confirmations);
        } else {
            await contract.deployed();
        }
    }

    async getGasUsed(contract) {
        const receipt = await contract.deployTransaction.wait();
        return receipt.gasUsed.toNumber();
    }

    async verifyContracts() {
        console.log("🔍 Verifying contracts on Etherscan...");

        for (const [name, contract] of Object.entries(this.contracts)) {
            try {
                await this.verifyContract(name, contract);
            } catch (error) {
                console.log(`⚠️ Verification failed for ${name}:`, error.message);
            }
        }
    }

    async verifyContract(name, contract) {
        try {
            if (name === "PoolFactory") {
                await hre.run("verify:verify", {
                    address: contract.address,
                    constructorArguments: [
                        this.deploymentInfo.contracts.PoolFactory.constructor.tokenRegistry
                    ]
                });
            } else if (name === "PoolManager") {
                await hre.run("verify:verify", {
                    address: contract.address,
                    constructorArguments: [
                        this.deploymentInfo.contracts.PoolManager.constructor.factory,
                        this.deploymentInfo.contracts.PoolManager.constructor.positionNFT,
                        this.deploymentInfo.contracts.PoolManager.constructor.weth9
                    ]
                });
            }
            console.log(`✅ ${name} verified successfully`);
        } catch (error) {
            if (error.message.includes("Already Verified")) {
                console.log(`✅ ${name} already verified`);
            } else {
                throw error;
            }
        }
    }

    async saveDeploymentInfo() {
        const fs = require("fs");
        const path = require("path");

        // Add gas summary
        this.deploymentInfo.gasUsage = {
            total: Object.values(this.gasUsed).reduce((sum, gas) => sum + gas, 0),
            breakdown: this.gasUsed
        };

        // Add configuration used
        this.deploymentInfo.configuration = this.getConfig();

        // Save to file
        const deploymentDir = path.join(__dirname, "../deployments");
        if (!fs.existsSync(deploymentDir)) {
            fs.mkdirSync(deploymentDir, { recursive: true });
        }

        const filename = `pool-layer-${network.name}-${Date.now()}.json`;
        const filepath = path.join(deploymentDir, filename);

        fs.writeFileSync(filepath, JSON.stringify(this.deploymentInfo, null, 2));
        console.log(`📁 Deployment info saved to: ${filepath}`);

        // Also save as latest
        const latestPath = path.join(deploymentDir, `pool-layer-${network.name}-latest.json`);
        fs.writeFileSync(latestPath, JSON.stringify(this.deploymentInfo, null, 2));
        console.log(`📁 Latest deployment info: ${latestPath}`);
    }

    printSummary() {
        console.log("\n🎉 Pool Layer Deployment Summary");
        console.log("=====================================");
        console.log(`📡 Network: ${network.name}`);
        console.log(`👤 Deployer: ${this.deploymentInfo.deployer}`);
        console.log(`📅 Timestamp: ${this.deploymentInfo.timestamp}\n`);

        console.log("📦 Deployed Contracts:");
        Object.entries(this.deploymentInfo.contracts).forEach(([name, info]) => {
            console.log(`  ${name}: ${info.address}`);
            console.log(`    Gas Used: ${info.gasUsed.toLocaleString()}`);
        });

        console.log(`\n⛽ Total Gas Used: ${this.deploymentInfo.gasUsage.total.toLocaleString()}`);

        console.log("\n🔧 Configuration:");
        const config = this.getConfig();
        console.log(`  Fee Tiers: ${config.feeTiers.length} tiers configured`);
        console.log(`  Default Slippage: ${config.poolManager.defaultSlippage / 100}%`);
        console.log(`  Auto-compound: ${config.poolManager.autoCompoundEnabled ? 'Enabled' : 'Disabled'}`);

        console.log("\n✅ Pool Layer deployment completed successfully!");
        
        console.log("\n📝 Next Steps:");
        console.log("  1. Update .env file with new contract addresses");
        console.log("  2. Run tests to verify functionality");
        console.log("  3. Deploy Router Layer (Layer 4) if not already deployed");
        console.log("  4. Create initial liquidity pools");
        console.log("  5. Update frontend configuration");
    }

    printGasReport() {
        console.log("\n⛽ Gas Usage Report");
        console.log("==================");
        
        Object.entries(this.gasUsed).forEach(([contract, gas]) => {
            console.log(`${contract.padEnd(20)}: ${gas.toLocaleString().padStart(10)} gas`);
        });
        
        const total = Object.values(this.gasUsed).reduce((sum, gas) => sum + gas, 0);
        console.log("-".repeat(32));
        console.log(`${"Total".padEnd(20)}: ${total.toLocaleString().padStart(10)} gas`);
    }
}

// Main deployment function
async function main() {
    const deployer = new PoolLayerDeployer();
    await deployer.deploy();
}

// Error handling
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("\n💥 Deployment script failed:");
        console.error(error);
        process.exit(1);
    });

module.exports = { PoolLayerDeployer }; 