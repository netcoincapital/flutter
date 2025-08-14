const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Configuration for different networks
const CONFIG = {
    mainnet: {
        confirmations: 6,
        timeout: 300000, // 5 minutes
        verification: true,
        twapConfig: {
            defaultPeriod: 3600, // 1 hour
            defaultCardinality: 200,
            updateInterval: 300, // 5 minutes
            maxPriceDeviation: 1000 // 10%
        },
        chainlinkConfig: {
            maxDeviation: 1000, // 10%
            stalePriceThreshold: 3600, // 1 hour
            enableValidation: true,
            maxHistoryLength: 100
        },
        priceOracleConfig: {
            useTWAP: true,
            useChainlink: true,
            requireBothSources: false,
            maxDeviation: 1000, // 10%
            twapWeight: 6000, // 60%
            chainlinkWeight: 4000, // 40%
            confidenceThreshold: 7000, // 70%
            stalePriceThreshold: 3600 // 1 hour
        },
        managerConfig: {
            maxDeviation: 1000, // 10%
            minConfidence: 7000, // 70%
            requireMultipleSources: false,
            stalePriceThreshold: 3600, // 1 hour
            autoUpdateEnabled: true,
            autoUpdateInterval: 300, // 5 minutes
            healthCheckInterval: 300 // 5 minutes
        }
    },
    testnet: {
        confirmations: 2,
        timeout: 120000, // 2 minutes
        verification: false,
        twapConfig: {
            defaultPeriod: 1800, // 30 minutes
            defaultCardinality: 100,
            updateInterval: 180, // 3 minutes
            maxPriceDeviation: 2000 // 20%
        },
        chainlinkConfig: {
            maxDeviation: 2000, // 20%
            stalePriceThreshold: 1800, // 30 minutes
            enableValidation: false, // Disabled for testing
            maxHistoryLength: 50
        },
        priceOracleConfig: {
            useTWAP: true,
            useChainlink: false, // Disabled if no testnet feeds
            requireBothSources: false,
            maxDeviation: 2000, // 20%
            twapWeight: 10000, // 100% TWAP
            chainlinkWeight: 0, // 0%
            confidenceThreshold: 5000, // 50%
            stalePriceThreshold: 1800 // 30 minutes
        },
        managerConfig: {
            maxDeviation: 2000, // 20%
            minConfidence: 5000, // 50%
            requireMultipleSources: false,
            stalePriceThreshold: 1800, // 30 minutes
            autoUpdateEnabled: true,
            autoUpdateInterval: 180, // 3 minutes
            healthCheckInterval: 180 // 3 minutes
        }
    }
};

class OracleDeployer {
    constructor(network, deployer) {
        this.network = network;
        this.deployer = deployer;
        this.config = CONFIG[network] || CONFIG.testnet;
        this.deployedContracts = {};
        this.gasReport = [];
    }

    async deploy() {
        console.log("🚀 Starting Oracle Layer deployment...");
        console.log(`📡 Network: ${this.network}`);
        console.log(`👤 Deployer: ${this.deployer.address}`);
        
        const balance = await ethers.provider.getBalance(this.deployer.address);
        console.log(`💰 Balance: ${ethers.formatEther(balance)} ETH\n`);

        try {
            // Deploy in order: TWAP -> Chainlink -> PriceOracle -> OracleManager
            await this.deployTWAPOracle();
            await this.deployChainlinkOracle();
            await this.deployPriceOracle();
            await this.deployOracleManager();
            
            // Configure contracts
            await this.configureContracts();
            
            // Save deployment info
            await this.saveDeploymentInfo();
            
            // Verify contracts if enabled
            if (this.config.verification) {
                await this.verifyContracts();
            }
            
            this.printGasReport();
            this.printSummary();
            
        } catch (error) {
            console.error("❌ Deployment failed:", error);
            throw error;
        }
    }

    async deployTWAPOracle() {
        console.log("📊 Deploying TWAPOracle...");
        
        const TWAPOracle = await ethers.getContractFactory("TWAPOracle");
        const txResponse = await TWAPOracle.deploy();
        const twapOracle = await txResponse.waitForDeployment();
        
        await this.waitForConfirmations(txResponse);
        
        this.deployedContracts.twapOracle = twapOracle.target;
        this.gasReport.push({
            contract: "TWAPOracle",
            gasUsed: txResponse.gasLimit?.toString() || "N/A",
            address: twapOracle.target
        });
        
        console.log(`✅ TWAPOracle deployed to: ${twapOracle.target}\n`);
        return twapOracle;
    }

    async deployChainlinkOracle() {
        console.log("🔗 Deploying ChainlinkOracle...");
        
        const ChainlinkOracle = await ethers.getContractFactory("ChainlinkOracle");
        const txResponse = await ChainlinkOracle.deploy();
        const chainlinkOracle = await txResponse.waitForDeployment();
        
        await this.waitForConfirmations(txResponse);
        
        this.deployedContracts.chainlinkOracle = chainlinkOracle.target;
        this.gasReport.push({
            contract: "ChainlinkOracle",
            gasUsed: txResponse.gasLimit?.toString() || "N/A",
            address: chainlinkOracle.target
        });
        
        console.log(`✅ ChainlinkOracle deployed to: ${chainlinkOracle.target}\n`);
        return chainlinkOracle;
    }

    async deployPriceOracle() {
        console.log("💰 Deploying PriceOracle...");
        
        const PriceOracle = await ethers.getContractFactory("PriceOracle");
        const txResponse = await PriceOracle.deploy(
            this.deployedContracts.twapOracle,
            this.deployedContracts.chainlinkOracle
        );
        const priceOracle = await txResponse.waitForDeployment();
        
        await this.waitForConfirmations(txResponse);
        
        this.deployedContracts.priceOracle = priceOracle.target;
        this.gasReport.push({
            contract: "PriceOracle",
            gasUsed: txResponse.gasLimit?.toString() || "N/A",
            address: priceOracle.target
        });
        
        console.log(`✅ PriceOracle deployed to: ${priceOracle.target}\n`);
        return priceOracle;
    }

    async deployOracleManager() {
        console.log("🎛️ Deploying OracleManager...");
        
        const OracleManager = await ethers.getContractFactory("OracleManager");
        const txResponse = await OracleManager.deploy(
            this.deployedContracts.priceOracle,
            this.deployedContracts.twapOracle,
            this.deployedContracts.chainlinkOracle
        );
        const oracleManager = await txResponse.waitForDeployment();
        
        await this.waitForConfirmations(txResponse);
        
        this.deployedContracts.oracleManager = oracleManager.target;
        this.gasReport.push({
            contract: "OracleManager",
            gasUsed: txResponse.gasLimit?.toString() || "N/A",
            address: oracleManager.target
        });
        
        console.log(`✅ OracleManager deployed to: ${oracleManager.target}\n`);
        return oracleManager;
    }

    async configureContracts() {
        console.log("⚙️ Configuring contracts...");
        
        const twapOracle = await ethers.getContractAt("TWAPOracle", this.deployedContracts.twapOracle);
        const chainlinkOracle = await ethers.getContractAt("ChainlinkOracle", this.deployedContracts.chainlinkOracle);
        const priceOracle = await ethers.getContractAt("PriceOracle", this.deployedContracts.priceOracle);
        const oracleManager = await ethers.getContractAt("OracleManager", this.deployedContracts.oracleManager);

        // Configure TWAP Oracle
        console.log("📊 Configuring TWAPOracle...");
        const twapConfig = this.config.twapConfig;
        await twapOracle.setDefaultConfiguration(
            twapConfig.defaultPeriod,
            twapConfig.defaultCardinality,
            twapConfig.updateInterval
        );
        await twapOracle.setMaxPriceDeviation(twapConfig.maxPriceDeviation);
        
        // Configure Chainlink Oracle
        console.log("🔗 Configuring ChainlinkOracle...");
        const chainlinkConfig = this.config.chainlinkConfig;
        await chainlinkOracle.setValidationConfig({
            maxPriceDeviation: chainlinkConfig.maxDeviation,
            stalePriceThreshold: chainlinkConfig.stalePriceThreshold,
            enableValidation: chainlinkConfig.enableValidation,
            requireMinAnswers: false,
            minAnswers: 1
        });
        
        // Configure Price Oracle default config
        console.log("💰 Configuring PriceOracle...");
        const priceConfig = this.config.priceOracleConfig;
        await priceOracle.setDefaultConfig(priceConfig);
        
        // Configure Oracle Manager
        console.log("🎛️ Configuring OracleManager...");
        const managerConfig = this.config.managerConfig;
        await oracleManager.setValidationConfig({
            maxDeviation: managerConfig.maxDeviation,
            minConfidence: managerConfig.minConfidence,
            requireMultipleSources: managerConfig.requireMultipleSources,
            stalePriceThreshold: managerConfig.stalePriceThreshold
        });
        
        await oracleManager.setAutoUpdateConfig(
            managerConfig.autoUpdateEnabled,
            managerConfig.autoUpdateInterval
        );
        
        await oracleManager.setHealthCheckInterval(managerConfig.healthCheckInterval);
        
        console.log("✅ Configuration completed\n");
    }

    async waitForConfirmations(txResponse) {
        if (this.config.confirmations > 0) {
            console.log(`⏳ Waiting for ${this.config.confirmations} confirmations...`);
            await txResponse.wait(this.config.confirmations);
        }
    }

    async saveDeploymentInfo() {
        const deploymentInfo = {
            network: this.network,
            timestamp: new Date().toISOString(),
            deployer: this.deployer.address,
            contracts: this.deployedContracts,
            configuration: this.config,
            gasReport: this.gasReport
        };

        const deploymentDir = path.join(__dirname, "../deployments");
        if (!fs.existsSync(deploymentDir)) {
            fs.mkdirSync(deploymentDir, { recursive: true });
        }

        const filename = `oracle-layer-${this.network}-${Date.now()}.json`;
        const filepath = path.join(deploymentDir, filename);
        
        fs.writeFileSync(filepath, JSON.stringify(deploymentInfo, null, 2));
        console.log(`📄 Deployment info saved to: ${filepath}`);

        // Also save latest deployment info
        const latestFilepath = path.join(deploymentDir, `oracle-layer-${this.network}-latest.json`);
        fs.writeFileSync(latestFilepath, JSON.stringify(deploymentInfo, null, 2));
        console.log(`📄 Latest deployment info saved to: ${latestFilepath}\n`);
    }

    async verifyContracts() {
        console.log("🔍 Verifying contracts...");
        
        // Note: This would require etherscan verification setup
        console.log("⚠️ Contract verification requires etherscan API setup");
        console.log("   Run verification manually with:");
        console.log(`   npx hardhat verify ${this.deployedContracts.twapOracle} --network ${this.network}`);
        console.log(`   npx hardhat verify ${this.deployedContracts.chainlinkOracle} --network ${this.network}`);
        console.log(`   npx hardhat verify ${this.deployedContracts.priceOracle} ${this.deployedContracts.twapOracle} ${this.deployedContracts.chainlinkOracle} --network ${this.network}`);
        console.log(`   npx hardhat verify ${this.deployedContracts.oracleManager} ${this.deployedContracts.priceOracle} ${this.deployedContracts.twapOracle} ${this.deployedContracts.chainlinkOracle} --network ${this.network}\n`);
    }

    printGasReport() {
        console.log("⛽ Gas Usage Report:");
        console.log("┌─────────────────────┬─────────────────────┬───────────────────────────────────────────────┐");
        console.log("│ Contract            │ Gas Used            │ Address                                       │");
        console.log("├─────────────────────┼─────────────────────┼───────────────────────────────────────────────┤");
        
        this.gasReport.forEach(report => {
            console.log(`│ ${report.contract.padEnd(19)} │ ${report.gasUsed.padEnd(19)} │ ${report.address.padEnd(45)} │`);
        });
        
        console.log("└─────────────────────┴─────────────────────┴───────────────────────────────────────────────┘\n");
    }

    printSummary() {
        console.log("🎉 Oracle Layer Deployment Summary:");
        console.log("================================");
        console.log(`Network: ${this.network}`);
        console.log(`Deployer: ${this.deployer.address}`);
        console.log();
        console.log("📊 Deployed Contracts:");
        console.log(`├─ TWAPOracle:      ${this.deployedContracts.twapOracle}`);
        console.log(`├─ ChainlinkOracle: ${this.deployedContracts.chainlinkOracle}`);
        console.log(`├─ PriceOracle:     ${this.deployedContracts.priceOracle}`);
        console.log(`└─ OracleManager:   ${this.deployedContracts.oracleManager}`);
        console.log();
        console.log("🔧 Configuration Applied:");
        console.log(`├─ TWAP Period: ${this.config.twapConfig.defaultPeriod}s`);
        console.log(`├─ Update Interval: ${this.config.managerConfig.autoUpdateInterval}s`);
        console.log(`├─ Max Deviation: ${this.config.managerConfig.maxDeviation/100}%`);
        console.log(`└─ Min Confidence: ${this.config.managerConfig.minConfidence/100}%`);
        console.log();
        console.log("✅ Oracle Layer deployment completed successfully!");
        console.log();
        console.log("📋 Next Steps:");
        console.log("1. Add token pairs to PriceOracle");
        console.log("2. Add pools to TWAPOracle");
        console.log("3. Add price feeds to ChainlinkOracle");
        console.log("4. Grant appropriate roles to operators");
        console.log("5. Set up automated price updates");
        console.log();
    }
}

async function main() {
    const [deployer] = await ethers.getSigners();
    const network = hre.network.name;
    
    console.log("🔗 Oracle Layer Deployment Script");
    console.log("==================================\n");
    
    const oracleDeployer = new OracleDeployer(network, deployer);
    await oracleDeployer.deploy();
}

// Handle script execution
if (require.main === module) {
    main()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error("💥 Deployment script failed:", error);
            process.exit(1);
        });
}

module.exports = { OracleDeployer, CONFIG }; 