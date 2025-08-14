const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

describe("OracleManager", function () {
    async function deployOracleManagerFixture() {
        const [owner, admin, operator, emergency, user] = await ethers.getSigners();

        // Deploy mock oracles
        const MockPriceOracle = await ethers.getContractFactory("MockPriceOracle");
        const priceOracle = await MockPriceOracle.deploy();

        const MockTWAPOracle = await ethers.getContractFactory("MockTWAPOracle");
        const twapOracle = await MockTWAPOracle.deploy();

        const MockChainlinkOracle = await ethers.getContractFactory("MockChainlinkOracle");
        const chainlinkOracle = await MockChainlinkOracle.deploy();

        // Deploy OracleManager
        const OracleManager = await ethers.getContractFactory("OracleManager");
        const oracleManager = await OracleManager.deploy(
            priceOracle.target,
            twapOracle.target,
            chainlinkOracle.target
        );

        // Set up roles
        const ADMIN_ROLE = await oracleManager.ADMIN_ROLE();
        const OPERATOR_ROLE = await oracleManager.OPERATOR_ROLE();
        const EMERGENCY_ROLE = await oracleManager.EMERGENCY_ROLE();
        const PAUSER_ROLE = await oracleManager.PAUSER_ROLE();

        await oracleManager.grantRole(ADMIN_ROLE, admin.address);
        await oracleManager.grantRole(OPERATOR_ROLE, operator.address);
        await oracleManager.grantRole(EMERGENCY_ROLE, emergency.address);
        await oracleManager.grantRole(PAUSER_ROLE, admin.address);

        // Deploy mock tokens
        const MockToken = await ethers.getContractFactory("MockERC20");
        const token0 = await MockToken.deploy("Token0", "TK0", 18);
        const token1 = await MockToken.deploy("Token1", "TK1", 18);

        return {
            oracleManager,
            priceOracle,
            twapOracle,
            chainlinkOracle,
            token0,
            token1,
            owner,
            admin,
            operator,
            emergency,
            user,
            ADMIN_ROLE,
            OPERATOR_ROLE,
            EMERGENCY_ROLE,
            PAUSER_ROLE
        };
    }

    describe("Deployment", function () {
        it("Should deploy with correct initial state", async function () {
            const { oracleManager, priceOracle, twapOracle, chainlinkOracle, owner } = await loadFixture(deployOracleManagerFixture);

            expect(await oracleManager.priceOracle()).to.equal(priceOracle.target);
            expect(await oracleManager.twapOracle()).to.equal(twapOracle.target);
            expect(await oracleManager.chainlinkOracle()).to.equal(chainlinkOracle.target);
            expect(await oracleManager.status()).to.equal(0); // ManagerStatus.ACTIVE
            expect(await oracleManager.emergencyMode()).to.equal(false);
            expect(await oracleManager.autoUpdateEnabled()).to.equal(true);

            // Check initial roles
            expect(await oracleManager.hasRole(await oracleManager.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;

            // Check validation config
            const config = await oracleManager.validationConfig();
            expect(config.maxDeviation).to.equal(1000); // 10%
            expect(config.minConfidence).to.equal(7000); // 70%
            expect(config.requireMultipleSources).to.be.false;
            expect(config.stalePriceThreshold).to.equal(3600); // 1 hour
        });

        it("Should have correct constants", async function () {
            const { oracleManager } = await loadFixture(deployOracleManagerFixture);

            expect(await oracleManager.MAX_ORACLES()).to.equal(10);
            expect(await oracleManager.UPDATE_BATCH_SIZE()).to.equal(50);
            expect(await oracleManager.HEALTH_CHECK_INTERVAL()).to.equal(300);
            expect(await oracleManager.EMERGENCY_COOLDOWN()).to.equal(3600);
        });

        it("Should reject invalid oracle addresses", async function () {
            const OracleManager = await ethers.getContractFactory("OracleManager");

            await expect(OracleManager.deploy(ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress))
                .to.be.revertedWithCustomError(OracleManager, "OracleManager__InvalidOracle");
        });

        it("Should auto-register core oracles", async function () {
            const { oracleManager } = await loadFixture(deployOracleManagerFixture);

            const oracles = await oracleManager.getRegisteredOracles();
            expect(oracles.length).to.equal(3);

            // Check that core oracles are registered
            expect(oracles[0].name).to.equal("Price Oracle");
            expect(oracles[1].name).to.equal("TWAP Oracle");
            expect(oracles[2].name).to.equal("Chainlink Oracle");
        });
    });

    describe("Oracle Registration", function () {
        it("Should register new oracle successfully", async function () {
            const { oracleManager, admin } = await loadFixture(deployOracleManagerFixture);

            // Deploy another mock oracle
            const MockExternalOracle = await ethers.getContractFactory("MockExternalOracle");
            const externalOracle = await MockExternalOracle.deploy();

            await expect(oracleManager.connect(admin).registerOracle(
                externalOracle.target,
                3, // OracleType.EXTERNAL
                "External Oracle",
                50
            )).to.emit(oracleManager, "OracleRegistered")
              .withArgs(externalOracle.target, 3, "External Oracle", 50);

            const oracles = await oracleManager.getRegisteredOracles();
            expect(oracles.length).to.equal(4); // 3 core + 1 new

            const oracleInfo = await oracleManager.getOracleInfo(externalOracle.target);
            expect(oracleInfo.name).to.equal("External Oracle");
            expect(oracleInfo.isActive).to.be.true;
            expect(oracleInfo.priority).to.equal(50);
        });

        it("Should reject invalid oracle registration", async function () {
            const { oracleManager, admin } = await loadFixture(deployOracleManagerFixture);

            // Invalid address
            await expect(oracleManager.connect(admin).registerOracle(
                ethers.ZeroAddress,
                3,
                "Invalid Oracle",
                50
            )).to.be.revertedWithCustomError(oracleManager, "OracleManager__InvalidOracle");
        });

        it("Should reject duplicate oracle registration", async function () {
            const { oracleManager, priceOracle, admin } = await loadFixture(deployOracleManagerFixture);

            await expect(oracleManager.connect(admin).registerOracle(
                priceOracle.target,
                2, // OracleType.AGGREGATED
                "Duplicate Oracle",
                50
            )).to.be.revertedWithCustomError(oracleManager, "OracleManager__OracleAlreadyRegistered");
        });

        it("Should set oracle status", async function () {
            const { oracleManager, priceOracle, operator } = await loadFixture(deployOracleManagerFixture);

            await expect(oracleManager.connect(operator).setOracleStatus(priceOracle.target, false))
                .to.emit(oracleManager, "OracleStatusUpdated")
                .withArgs(priceOracle.target, false, true);

            const oracleInfo = await oracleManager.getOracleInfo(priceOracle.target);
            expect(oracleInfo.isActive).to.be.false;
        });

        it("Should remove oracle", async function () {
            const { oracleManager, admin } = await loadFixture(deployOracleManagerFixture);

            // Deploy and register external oracle first
            const MockExternalOracle = await ethers.getContractFactory("MockExternalOracle");
            const externalOracle = await MockExternalOracle.deploy();

            await oracleManager.connect(admin).registerOracle(
                externalOracle.target,
                3,
                "External Oracle",
                50
            );

            expect(await oracleManager.isOracleRegistered(externalOracle.target)).to.be.true;

            // Remove oracle
            await oracleManager.connect(admin).removeOracle(externalOracle.target);

            expect(await oracleManager.isOracleRegistered(externalOracle.target)).to.be.false;
        });

        it("Should only allow admin to register/remove oracles", async function () {
            const { oracleManager, user } = await loadFixture(deployOracleManagerFixture);

            const MockExternalOracle = await ethers.getContractFactory("MockExternalOracle");
            const externalOracle = await MockExternalOracle.deploy();

            await expect(oracleManager.connect(user).registerOracle(
                externalOracle.target,
                3,
                "External Oracle",
                50
            )).to.be.reverted;

            await expect(oracleManager.connect(user).removeOracle(externalOracle.target))
                .to.be.reverted;
        });
    });

    describe("Price Management", function () {
        it("Should get price", async function () {
            const { oracleManager, token0, token1 } = await loadFixture(deployOracleManagerFixture);

            const price = await oracleManager.getPrice(token0.target, token1.target);
            expect(price.isValid).to.be.true;
            expect(price.price).to.be.gt(0);
        });

        it("Should get validated price", async function () {
            const { oracleManager, token0, token1 } = await loadFixture(deployOracleManagerFixture);

            const price = await oracleManager.getValidatedPrice(token0.target, token1.target);
            expect(price.isValid).to.be.true;
            expect(price.confidence).to.be.gte(7000); // Should meet confidence threshold
        });

        it("Should update price for token pair", async function () {
            const { oracleManager, token0, token1, operator } = await loadFixture(deployOracleManagerFixture);

            // Note: This test depends on the mock implementation
            // In real implementation, we'd need to set up the price oracle properly
            await expect(oracleManager.connect(operator).updatePrice(token0.target, token1.target))
                .to.not.be.reverted;
        });

        it("Should batch update prices", async function () {
            const { oracleManager, token0, token1, operator } = await loadFixture(deployOracleManagerFixture);

            const MockToken = await ethers.getContractFactory("MockERC20");
            const token2 = await MockToken.deploy("Token2", "TK2", 18);

            const batchId = await oracleManager.connect(operator).batchUpdatePrices.staticCall(
                [token0.target, token1.target],
                [token1.target, token2.target],
                false
            );

            await expect(oracleManager.connect(operator).batchUpdatePrices(
                [token0.target, token1.target],
                [token1.target, token2.target],
                false
            )).to.emit(oracleManager, "BatchUpdateExecuted");

            expect(batchId).to.be.gt(0);
        });

        it("Should reject batch update with too many pairs", async function () {
            const { oracleManager, operator } = await loadFixture(deployOracleManagerFixture);

            // Create arrays larger than UPDATE_BATCH_SIZE (50)
            const token0s = new Array(51).fill(ethers.ZeroAddress);
            const token1s = new Array(51).fill(ethers.ZeroAddress);

            await expect(oracleManager.connect(operator).batchUpdatePrices(token0s, token1s, false))
                .to.be.revertedWithCustomError(oracleManager, "OracleManager__BatchSizeExceeded");
        });

        it("Should reject update too soon", async function () {
            const { oracleManager, token0, token1, operator } = await loadFixture(deployOracleManagerFixture);

            // First update
            await oracleManager.connect(operator).updatePrice(token0.target, token1.target);

            // Try to update again immediately
            await expect(oracleManager.connect(operator).updatePrice(token0.target, token1.target))
                .to.be.revertedWithCustomError(oracleManager, "OracleManager__UpdateTooSoon");
        });
    });

    describe("Health Monitoring", function () {
        it("Should perform global health check", async function () {
            const { oracleManager, operator } = await loadFixture(deployOracleManagerFixture);

            await expect(oracleManager.connect(operator).performGlobalHealthCheck())
                .to.not.be.reverted;

            expect(await oracleManager.lastGlobalHealthCheck()).to.be.gt(0);
        });

        it("Should perform oracle-specific health check", async function () {
            const { oracleManager, priceOracle, operator } = await loadFixture(deployOracleManagerFixture);

            await expect(oracleManager.connect(operator).performOracleHealthCheck(priceOracle.target))
                .to.emit(oracleManager, "HealthCheckCompleted");

            const oracleInfo = await oracleManager.getOracleInfo(priceOracle.target);
            expect(oracleInfo.lastHealthCheck).to.be.gt(0);
        });

        it("Should get health report", async function () {
            const { oracleManager } = await loadFixture(deployOracleManagerFixture);

            const reports = await oracleManager.getHealthReport();
            expect(reports.length).to.equal(3); // 3 core oracles

            expect(reports[0].oracle).to.not.equal(ethers.ZeroAddress);
            expect(reports[0].status).to.be.a('string');
        });

        it("Should check if auto-update is needed", async function () {
            const { oracleManager, token0, token1 } = await loadFixture(deployOracleManagerFixture);

            const needsUpdate = await oracleManager.needsAutoUpdate(token0.target, token1.target);
            expect(needsUpdate).to.be.a('boolean');
        });
    });

    describe("Emergency Management", function () {
        it("Should activate emergency mode", async function () {
            const { oracleManager, emergency } = await loadFixture(deployOracleManagerFixture);

            await expect(oracleManager.connect(emergency).activateEmergencyMode("Test emergency"))
                .to.emit(oracleManager, "EmergencyModeActivated")
                .withArgs(emergency.address, "Test emergency");

            expect(await oracleManager.emergencyMode()).to.be.true;
            expect(await oracleManager.status()).to.equal(2); // ManagerStatus.EMERGENCY
        });

        it("Should deactivate emergency mode after cooldown", async function () {
            const { oracleManager, emergency } = await loadFixture(deployOracleManagerFixture);

            await oracleManager.connect(emergency).activateEmergencyMode("Test emergency");
            
            // Fast forward time past cooldown
            await time.increase(3601); // 1 hour + 1 second

            await expect(oracleManager.connect(emergency).deactivateEmergencyMode())
                .to.emit(oracleManager, "EmergencyModeDeactivated")
                .withArgs(emergency.address);

            expect(await oracleManager.emergencyMode()).to.be.false;
            expect(await oracleManager.status()).to.equal(0); // ManagerStatus.ACTIVE
        });

        it("Should reject deactivation before cooldown", async function () {
            const { oracleManager, emergency } = await loadFixture(deployOracleManagerFixture);

            await oracleManager.connect(emergency).activateEmergencyMode("Test emergency");

            await expect(oracleManager.connect(emergency).deactivateEmergencyMode())
                .to.be.revertedWith("Emergency cooldown not met");
        });

        it("Should set emergency oracle status", async function () {
            const { oracleManager, priceOracle, emergency } = await loadFixture(deployOracleManagerFixture);

            await oracleManager.connect(emergency).setEmergencyOracle(priceOracle.target, true);

            expect(await oracleManager.emergencyOracles(priceOracle.target)).to.be.true;
        });

        it("Should reject operations in emergency mode", async function () {
            const { oracleManager, token0, token1, emergency, operator } = await loadFixture(deployOracleManagerFixture);

            await oracleManager.connect(emergency).activateEmergencyMode("Test emergency");

            await expect(oracleManager.connect(operator).updatePrice(token0.target, token1.target))
                .to.be.revertedWithCustomError(oracleManager, "OracleManager__EmergencyModeActive");
        });
    });

    describe("Configuration", function () {
        it("Should set manager status", async function () {
            const { oracleManager, admin } = await loadFixture(deployOracleManagerFixture);

            await expect(oracleManager.connect(admin).setManagerStatus(1)) // ManagerStatus.MAINTENANCE
                .to.emit(oracleManager, "ManagerStatusChanged")
                .withArgs(0, 1); // ACTIVE to MAINTENANCE

            expect(await oracleManager.status()).to.equal(1);
        });

        it("Should set validation configuration", async function () {
            const { oracleManager, admin } = await loadFixture(deployOracleManagerFixture);

            const newConfig = {
                maxDeviation: 2000, // 20%
                minConfidence: 8000, // 80%
                requireMultipleSources: true,
                stalePriceThreshold: 7200 // 2 hours
            };

            await expect(oracleManager.connect(admin).setValidationConfig(newConfig))
                .to.emit(oracleManager, "ValidationConfigUpdated");

            const config = await oracleManager.validationConfig();
            expect(config.maxDeviation).to.equal(2000);
            expect(config.minConfidence).to.equal(8000);
            expect(config.requireMultipleSources).to.be.true;
        });

        it("Should reject invalid validation configuration", async function () {
            const { oracleManager, admin } = await loadFixture(deployOracleManagerFixture);

            const invalidConfig = {
                maxDeviation: 6000, // 60% - too high
                minConfidence: 11000, // 110% - invalid
                requireMultipleSources: false,
                stalePriceThreshold: 3600
            };

            await expect(oracleManager.connect(admin).setValidationConfig(invalidConfig))
                .to.be.revertedWithCustomError(oracleManager, "OracleManager__InvalidConfiguration");
        });

        it("Should set auto-update configuration", async function () {
            const { oracleManager, admin } = await loadFixture(deployOracleManagerFixture);

            await expect(oracleManager.connect(admin).setAutoUpdateConfig(false, 600))
                .to.emit(oracleManager, "AutoUpdateConfigChanged")
                .withArgs(false, 600);

            expect(await oracleManager.autoUpdateEnabled()).to.be.false;
            expect(await oracleManager.autoUpdateInterval()).to.equal(600);
        });

        it("Should set health check interval", async function () {
            const { oracleManager, admin } = await loadFixture(deployOracleManagerFixture);

            await oracleManager.connect(admin).setHealthCheckInterval(600);

            expect(await oracleManager.healthCheckInterval()).to.equal(600);
        });

        it("Should get manager configuration", async function () {
            const { oracleManager } = await loadFixture(deployOracleManagerFixture);

            const [status, emergency, validation, autoUpdate, autoInterval] = await oracleManager.getManagerConfig();

            expect(status).to.equal(0); // ACTIVE
            expect(emergency).to.be.false;
            expect(validation.maxDeviation).to.equal(1000);
            expect(autoUpdate).to.be.true;
            expect(autoInterval).to.equal(300);
        });
    });

    describe("Pause Functions", function () {
        it("Should pause and unpause", async function () {
            const { oracleManager, admin } = await loadFixture(deployOracleManagerFixture);

            // Pause
            await oracleManager.connect(admin).pause();
            expect(await oracleManager.paused()).to.be.true;

            // Unpause
            await oracleManager.connect(admin).unpause();
            expect(await oracleManager.paused()).to.be.false;
        });
    });

    describe("View Functions", function () {
        it("Should get registered oracles", async function () {
            const { oracleManager } = await loadFixture(deployOracleManagerFixture);

            const oracles = await oracleManager.getRegisteredOracles();
            expect(oracles.length).to.equal(3);
            expect(oracles[0].isActive).to.be.true;
        });

        it("Should get batch request information", async function () {
            const { oracleManager, token0, token1, operator } = await loadFixture(deployOracleManagerFixture);

            // Execute a batch update first
            await oracleManager.connect(operator).batchUpdatePrices(
                [token0.target],
                [token1.target],
                false
            );

            const batchRequest = await oracleManager.getBatchRequest(1);
            expect(batchRequest.batchId).to.equal(1);
            expect(batchRequest.token0s.length).to.equal(1);
            expect(batchRequest.forceUpdate).to.be.false;
        });

        it("Should get system statistics", async function () {
            const { oracleManager } = await loadFixture(deployOracleManagerFixture);

            const [totalOracles, activeOracles, healthyOracles, lastGlobalCheck, totalBatches] = 
                await oracleManager.getSystemStats();

            expect(totalOracles).to.equal(3);
            expect(activeOracles).to.be.lte(totalOracles);
            expect(healthyOracles).to.be.lte(totalOracles);
            expect(lastGlobalCheck).to.be.a('bigint');
            expect(totalBatches).to.be.a('bigint');
        });
    });

    describe("Access Control", function () {
        it("Should enforce role-based access control", async function () {
            const { oracleManager, token0, token1, user } = await loadFixture(deployOracleManagerFixture);

            // User should not be able to perform admin functions
            await expect(oracleManager.connect(user).setManagerStatus(1))
                .to.be.reverted;

            await expect(oracleManager.connect(user).activateEmergencyMode("test"))
                .to.be.reverted;

            // User should not be able to perform operator functions
            await expect(oracleManager.connect(user).performGlobalHealthCheck())
                .to.be.reverted;

            await expect(oracleManager.connect(user).batchUpdatePrices([token0.target], [token1.target], false))
                .to.be.reverted;
        });
    });

    describe("Edge Cases", function () {
        it("Should handle manager not active", async function () {
            const { oracleManager, token0, token1, admin, operator } = await loadFixture(deployOracleManagerFixture);

            // Set manager to maintenance mode
            await oracleManager.connect(admin).setManagerStatus(1); // MAINTENANCE

            await expect(oracleManager.getPrice(token0.target, token1.target))
                .to.be.revertedWith("Manager not active");
        });

        it("Should handle non-existent oracle", async function () {
            const { oracleManager, operator } = await loadFixture(deployOracleManagerFixture);

            const MockToken = await ethers.getContractFactory("MockERC20");
            const fakeOracle = await MockToken.deploy("Fake", "FAKE", 18);

            await expect(oracleManager.connect(operator).performOracleHealthCheck(fakeOracle.target))
                .to.be.revertedWithCustomError(oracleManager, "OracleManager__OracleNotRegistered");
        });
    });
});

// Mock contracts for testing

// Mock Price Oracle
contract MockPriceOracle {
    struct AggregatedPrice {
        uint256 price;
        uint256 twapPrice;
        uint256 chainlinkPrice;
        uint256 timestamp;
        uint256 deviation;
        uint8 primarySource; // PriceSource enum
        bool isValid;
        uint256 confidence;
    }

    enum OracleStatus { ACTIVE, INACTIVE, EMERGENCY, MAINTENANCE }

    function getPrice(address, address) external view returns (AggregatedPrice memory) {
        return AggregatedPrice({
            price: 1000 * 1e18,
            twapPrice: 1000 * 1e18,
            chainlinkPrice: 1100 * 1e18,
            timestamp: block.timestamp,
            deviation: 100, // 1%
            primarySource: 2, // COMBINED
            isValid: true,
            confidence: 9000 // 90%
        });
    }

    function updatePrice(address, address) external {}

    function getSupportedPairsCount() external pure returns (uint256) {
        return 1;
    }

    function getOracleHealth() external pure returns (
        OracleStatus oracleStatus,
        bool emergency,
        uint256 activePairs,
        uint256 totalPairs
    ) {
        return (OracleStatus.ACTIVE, false, 1, 1);
    }
}

// Mock TWAP Oracle  
contract MockTWAPOracle {
    function getSupportedPoolsCount() external pure returns (uint256) {
        return 1;
    }
}

// Mock Chainlink Oracle
contract MockChainlinkOracle {
    function getAllFeedKeys() external pure returns (bytes32[] memory) {
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = keccak256("ETH/USD");
        return keys;
    }
}

// Mock External Oracle
contract MockExternalOracle {
    function isHealthy() external pure returns (bool) {
        return true;
    }
}

// Mock ERC20 for testing
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
} 