const { ethers, network } = require("hardhat");

/**
 * Deployment script for Layer 6: Quoter/Swap
 * مسئول deploy کردن کانترکت‌های Quoter, SwapRouter و SwapMath
 */

// Configuration for different networks
const CONFIG = {
    mainnet: {
        quoter: {
            maxPriceImpact: 1000, // 10%
            minLiquidity: 1000,
            gasEstimates: {
                singleSwap: 80000,
                multiSwapBase: 100000,
                multiSwapPerHop: 50000,
                quote: 30000
            }
        },
        swapRouter: {
            defaultSlippage: 500, // 5%
            routerFee: 1, // 0.01%
            mevProtection: {
                enabled: true,
                maxPriceImpact: 1000, // 10%
                minBlockDelay: 2,
                maxSlippageTolerance: 500 // 5%
            },
            whitelistMode: false
        },
        gasLimit: 3000000,
        confirmations: 2
    },
    testnet: {
        quoter: {
            maxPriceImpact: 2000, // 20% (more lenient for testing)
            minLiquidity: 100,
            gasEstimates: {
                singleSwap: 100000,
                multiSwapBase: 120000,
                multiSwapPerHop: 60000,
                quote: 40000
            }
        },
        swapRouter: {
            defaultSlippage: 1000, // 10% (more lenient for testing)
            routerFee: 5, // 0.05%
            mevProtection: {
                enabled: false, // Disabled for testing
                maxPriceImpact: 2000,
                minBlockDelay: 1,
                maxSlippageTolerance: 1000
            },
            whitelistMode: false
        },
        gasLimit: 5000000,
        confirmations: 1
    }
};

class QuoterLayerDeployer {
    constructor() {
        this.contracts = {};
        this.gasUsed = {};
        this.deploymentInfo = {
            network: network.name,
            timestamp: new Date().toISOString(),
            deployer: null,
            contracts: {},
            configuration: {},
            gasReport: {}
        };
    }

    /**
     * اصلی deployment function
     */
    async deploy() {
        console.log("\n🚀 ===== LAYER 6 (QUOTER/SWAP) DEPLOYMENT STARTED =====");
        console.log(`📍 Network: ${network.name}`);
        console.log(`⏰ Time: ${new Date().toISOString()}`);

        const [deployer] = await ethers.getSigners();
        const deployerBalance = await deployer.getBalance();
        this.deploymentInfo.deployer = deployer.address;

        console.log(`👤 Deployer: ${deployer.address}`);
        console.log(`💰 Balance: ${ethers.utils.formatEther(deployerBalance)} ETH\n`);

        const isMainnet = network.name === "mainnet" || network.name === "polygon" || network.name === "bsc";
        const config = isMainnet ? CONFIG.mainnet : CONFIG.testnet;

        try {
            // ✅ Check dependencies
            await this.checkDependencies();

            // 📦 Deploy contracts
            await this.deployQuoter(config);
            await this.deploySwapRouter(config);

            // ⚙️ Configure contracts
            await this.configureContracts(config);

            // 🔍 Verify contracts (if not local)
            if (network.name !== "hardhat" && network.name !== "localhost") {
                await this.verifyContracts();
            }

            // 💾 Save deployment info
            await this.saveDeploymentInfo();

            // 📊 Print summary
            this.printSummary();
            this.printGasReport();

            console.log("\n✅ ===== LAYER 6 DEPLOYMENT COMPLETED SUCCESSFULLY =====\n");

        } catch (error) {
            console.error("\n❌ ===== DEPLOYMENT FAILED =====");
            console.error("Error:", error.message);
            console.error("Stack:", error.stack);
            throw error;
        }
    }

    /**
     * بررسی dependencies لایه‌های قبلی
     */
    async checkDependencies() {
        console.log("🔍 Checking dependencies...");

        // بررسی PoolFactory
        const poolFactoryAddress = process.env.POOL_FACTORY_ADDRESS;
        if (!poolFactoryAddress) {
            throw new Error("❌ POOL_FACTORY_ADDRESS not found. Please deploy Pool Layer first.");
        }

        // بررسی وجود PoolFactory
        const poolFactoryCode = await ethers.provider.getCode(poolFactoryAddress);
        if (poolFactoryCode === "0x") {
            throw new Error(`❌ PoolFactory not found at ${poolFactoryAddress}`);
        }

        // بررسی WETH9
        const weth9Address = process.env.WETH9_ADDRESS;
        if (!weth9Address) {
            throw new Error("❌ WETH9_ADDRESS not found. Please set WETH9_ADDRESS in environment.");
        }

        this.dependencies = {
            poolFactory: poolFactoryAddress,
            weth9: weth9Address
        };

        console.log("✅ Dependencies verified:");
        console.log(`   📦 PoolFactory: ${poolFactoryAddress}`);
        console.log(`   💧 WETH9: ${weth9Address}\n`);
    }

    /**
     * Deploy Quoter contract
     */
    async deployQuoter(config) {
        console.log("📦 Deploying Quoter...");

        const Quoter = await ethers.getContractFactory("Quoter");
        const quoter = await Quoter.deploy(
            this.dependencies.poolFactory,
            {
                gasLimit: config.gasLimit
            }
        );

        await this.waitForConfirmations(quoter, config.confirmations);

        this.contracts.Quoter = quoter;
        this.gasUsed.Quoter = await this.getGasUsed(quoter);

        console.log(`✅ Quoter deployed to: ${quoter.address}`);
        console.log(`⛽ Gas used: ${this.gasUsed.Quoter.toLocaleString()}\n`);

        this.deploymentInfo.contracts.Quoter = {
            address: quoter.address,
            gasUsed: this.gasUsed.Quoter,
            constructor: {
                factory: this.dependencies.poolFactory
            }
        };
    }

    /**
     * Deploy SwapRouter contract
     */
    async deploySwapRouter(config) {
        console.log("📦 Deploying SwapRouter...");

        const SwapRouter = await ethers.getContractFactory("SwapRouter");
        const swapRouter = await SwapRouter.deploy(
            this.dependencies.poolFactory,
            this.dependencies.weth9,
            this.contracts.Quoter.address,
            {
                gasLimit: config.gasLimit
            }
        );

        await this.waitForConfirmations(swapRouter, config.confirmations);

        this.contracts.SwapRouter = swapRouter;
        this.gasUsed.SwapRouter = await this.getGasUsed(swapRouter);

        console.log(`✅ SwapRouter deployed to: ${swapRouter.address}`);
        console.log(`⛽ Gas used: ${this.gasUsed.SwapRouter.toLocaleString()}\n`);

        this.deploymentInfo.contracts.SwapRouter = {
            address: swapRouter.address,
            gasUsed: this.gasUsed.SwapRouter,
            constructor: {
                factory: this.dependencies.poolFactory,
                weth9: this.dependencies.weth9,
                quoter: this.contracts.Quoter.address
            }
        };
    }

    /**
     * Configure deployed contracts
     */
    async configureContracts(config) {
        console.log("⚙️ Configuring contracts...");

        // Configure Quoter
        await this.configureQuoter(config.quoter);

        // Configure SwapRouter
        await this.configureSwapRouter(config.swapRouter);

        this.deploymentInfo.configuration = config;
        console.log("✅ All contracts configured successfully\n");
    }

    /**
     * Configure Quoter
     */
    async configureQuoter(quoterConfig) {
        console.log("   🔧 Configuring Quoter...");

        const quoter = this.contracts.Quoter;

        // Set max price impact
        if (quoterConfig.maxPriceImpact) {
            await quoter.setMaxPriceImpact(quoterConfig.maxPriceImpact);
            console.log(`   ✓ Max price impact set to: ${quoterConfig.maxPriceImpact} basis points`);
        }

        // Set min liquidity
        if (quoterConfig.minLiquidity) {
            await quoter.setMinLiquidity(quoterConfig.minLiquidity);
            console.log(`   ✓ Min liquidity set to: ${quoterConfig.minLiquidity}`);
        }

        // Update gas estimates
        if (quoterConfig.gasEstimates) {
            for (const [operation, gasAmount] of Object.entries(quoterConfig.gasEstimates)) {
                await quoter.updateGasEstimate(operation, gasAmount);
                console.log(`   ✓ Gas estimate for ${operation}: ${gasAmount}`);
            }
        }
    }

    /**
     * Configure SwapRouter
     */
    async configureSwapRouter(routerConfig) {
        console.log("   🔧 Configuring SwapRouter...");

        const swapRouter = this.contracts.SwapRouter;

        // Set default slippage
        if (routerConfig.defaultSlippage) {
            await swapRouter.setDefaultSlippage(routerConfig.defaultSlippage);
            console.log(`   ✓ Default slippage set to: ${routerConfig.defaultSlippage} basis points`);
        }

        // Set router fee
        if (routerConfig.routerFee) {
            await swapRouter.setRouterFee(routerConfig.routerFee);
            console.log(`   ✓ Router fee set to: ${routerConfig.routerFee} basis points`);
        }

        // Configure MEV protection
        if (routerConfig.mevProtection) {
            await swapRouter.setMEVProtection(routerConfig.mevProtection);
            console.log(`   ✓ MEV protection configured: ${routerConfig.mevProtection.enabled ? 'enabled' : 'disabled'}`);
        }

        // Set whitelist mode
        if (typeof routerConfig.whitelistMode === 'boolean') {
            await swapRouter.setWhitelistMode(routerConfig.whitelistMode);
            console.log(`   ✓ Whitelist mode: ${routerConfig.whitelistMode ? 'enabled' : 'disabled'}`);
        }
    }

    /**
     * Wait for transaction confirmations
     */
    async waitForConfirmations(contract, confirmations) {
        if (confirmations > 0) {
            console.log(`   ⏳ Waiting for ${confirmations} confirmations...`);
            await contract.deployTransaction.wait(confirmations);
        }
    }

    /**
     * Get gas used for contract deployment
     */
    async getGasUsed(contract) {
        const receipt = await contract.deployTransaction.wait();
        return receipt.gasUsed;
    }

    /**
     * Verify contracts on block explorer
     */
    async verifyContracts() {
        console.log("🔍 Verifying contracts...");

        try {
            // Verify Quoter
            await this.verifyContract(
                this.contracts.Quoter.address,
                "contracts/06-quoter/Quoter.sol:Quoter",
                [this.dependencies.poolFactory]
            );

            // Verify SwapRouter
            await this.verifyContract(
                this.contracts.SwapRouter.address,
                "contracts/06-quoter/SwapRouter.sol:SwapRouter",
                [
                    this.dependencies.poolFactory,
                    this.dependencies.weth9,
                    this.contracts.Quoter.address
                ]
            );

            console.log("✅ All contracts verified successfully\n");

        } catch (error) {
            console.warn("⚠️ Contract verification failed:", error.message);
            console.warn("   You can verify manually later\n");
        }
    }

    /**
     * Verify single contract
     */
    async verifyContract(address, contractPath, constructorArgs) {
        try {
            await hre.run("verify:verify", {
                address: address,
                contract: contractPath,
                constructorArguments: constructorArgs,
            });
            console.log(`   ✅ Verified: ${address}`);
        } catch (error) {
            if (error.message.includes("Already Verified")) {
                console.log(`   ✓ Already verified: ${address}`);
            } else {
                throw error;
            }
        }
    }

    /**
     * Save deployment information
     */
    async saveDeploymentInfo() {
        const fs = require('fs');
        const path = require('path');

        const deploymentsDir = path.join(__dirname, '../deployments');
        if (!fs.existsSync(deploymentsDir)) {
            fs.mkdirSync(deploymentsDir, { recursive: true });
        }

        const filename = `quoter-layer-${network.name}-${Date.now()}.json`;
        const filepath = path.join(deploymentsDir, filename);

        this.deploymentInfo.gasReport = this.gasUsed;

        fs.writeFileSync(
            filepath,
            JSON.stringify(this.deploymentInfo, null, 2)
        );

        console.log(`💾 Deployment info saved to: ${filepath}\n`);
    }

    /**
     * Print deployment summary
     */
    printSummary() {
        console.log("📋 ===== DEPLOYMENT SUMMARY =====");
        console.log(`🌐 Network: ${network.name}`);
        console.log(`👤 Deployer: ${this.deploymentInfo.deployer}`);
        console.log(`⏰ Time: ${this.deploymentInfo.timestamp}\n`);

        console.log("📦 Deployed Contracts:");
        for (const [name, info] of Object.entries(this.deploymentInfo.contracts)) {
            console.log(`   ${name}: ${info.address}`);
        }

        console.log("\n🔗 Dependencies:");
        console.log(`   PoolFactory: ${this.dependencies.poolFactory}`);
        console.log(`   WETH9: ${this.dependencies.weth9}`);

        console.log("\n⚙️ Configuration Applied:");
        console.log(`   Quoter max price impact: ${this.deploymentInfo.configuration.quoter.maxPriceImpact} basis points`);
        console.log(`   Router default slippage: ${this.deploymentInfo.configuration.swapRouter.defaultSlippage} basis points`);
        console.log(`   MEV protection: ${this.deploymentInfo.configuration.swapRouter.mevProtection.enabled ? 'enabled' : 'disabled'}`);
    }

    /**
     * Print gas usage report
     */
    printGasReport() {
        console.log("\n⛽ ===== GAS USAGE REPORT =====");
        
        let totalGas = 0;
        for (const [contract, gasUsed] of Object.entries(this.gasUsed)) {
            console.log(`   ${contract}: ${gasUsed.toLocaleString()} gas`);
            totalGas += gasUsed.toNumber();
        }
        
        console.log(`   ─────────────────────────────`);
        console.log(`   Total: ${totalGas.toLocaleString()} gas`);
        
        // Estimate cost (assuming 20 gwei gas price)
        const gasPrice = ethers.utils.parseUnits("20", "gwei");
        const totalCost = gasPrice.mul(totalGas);
        console.log(`   Estimated cost: ${ethers.utils.formatEther(totalCost)} ETH\n`);
    }
}

/**
 * Main deployment function
 */
async function main() {
    const deployer = new QuoterLayerDeployer();
    await deployer.deploy();
}

// Handle script execution
if (require.main === module) {
    main()
        .then(() => {
            console.log("🎉 Deployment script completed successfully!");
            process.exit(0);
        })
        .catch((error) => {
            console.error("💥 Deployment script failed:", error);
            process.exit(1);
        });
}

module.exports = { QuoterLayerDeployer, CONFIG }; 