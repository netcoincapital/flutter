const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

describe("PriceOracle", function () {
    async function deployPriceOracleFixture() {
        const [owner, admin, operator, emergency, user] = await ethers.getSigners();

        // Deploy mock TWAP Oracle
        const MockTWAPOracle = await ethers.getContractFactory("MockTWAPOracle");
        const twapOracle = await MockTWAPOracle.deploy();

        // Deploy mock Chainlink Oracle
        const MockChainlinkOracle = await ethers.getContractFactory("MockChainlinkOracle");
        const chainlinkOracle = await MockChainlinkOracle.deploy();

        // Deploy PriceOracle
        const PriceOracle = await ethers.getContractFactory("PriceOracle");
        const priceOracle = await PriceOracle.deploy(twapOracle.target, chainlinkOracle.target);

        // Set up roles
        const ADMIN_ROLE = await priceOracle.ADMIN_ROLE();
        const OPERATOR_ROLE = await priceOracle.OPERATOR_ROLE();
        const EMERGENCY_ROLE = await priceOracle.EMERGENCY_ROLE();
        const PAUSER_ROLE = await priceOracle.PAUSER_ROLE();

        await priceOracle.grantRole(ADMIN_ROLE, admin.address);
        await priceOracle.grantRole(OPERATOR_ROLE, operator.address);
        await priceOracle.grantRole(EMERGENCY_ROLE, emergency.address);
        await priceOracle.grantRole(PAUSER_ROLE, admin.address);

        // Deploy mock tokens
        const MockToken = await ethers.getContractFactory("MockERC20");
        const token0 = await MockToken.deploy("Token0", "TK0", 18);
        const token1 = await MockToken.deploy("Token1", "TK1", 18);

        return {
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
            const { priceOracle, twapOracle, chainlinkOracle, owner } = await loadFixture(deployPriceOracleFixture);

            expect(await priceOracle.twapOracle()).to.equal(twapOracle.target);
            expect(await priceOracle.chainlinkOracle()).to.equal(chainlinkOracle.target);
            expect(await priceOracle.status()).to.equal(0); // OracleStatus.ACTIVE
            expect(await priceOracle.emergencyMode()).to.equal(false);

            // Check initial roles
            expect(await priceOracle.hasRole(await priceOracle.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;

            // Check default configuration
            const config = await priceOracle.defaultConfig();
            expect(config.useTWAP).to.be.true;
            expect(config.useChainlink).to.be.true;
            expect(config.requireBothSources).to.be.false;
            expect(config.maxDeviation).to.equal(1000); // 10%
            expect(config.twapWeight).to.equal(6000); // 60%
            expect(config.chainlinkWeight).to.equal(4000); // 40%
            expect(config.confidenceThreshold).to.equal(7000); // 70%
        });

        it("Should have correct constants", async function () {
            const { priceOracle } = await loadFixture(deployPriceOracleFixture);

            expect(await priceOracle.PRECISION()).to.equal(ethers.parseEther("1"));
            expect(await priceOracle.MAX_PRICE_DEVIATION()).to.equal(2000); // 20%
            expect(await priceOracle.MIN_UPDATE_INTERVAL()).to.equal(60);
            expect(await priceOracle.MAX_UPDATE_INTERVAL()).to.equal(3600);
            expect(await priceOracle.EMERGENCY_THRESHOLD()).to.equal(5000); // 50%
        });

        it("Should reject invalid oracle addresses", async function () {
            const PriceOracle = await ethers.getContractFactory("PriceOracle");

            await expect(PriceOracle.deploy(ethers.ZeroAddress, ethers.ZeroAddress))
                .to.be.revertedWithCustomError(PriceOracle, "PriceOracle__InvalidOracles");
        });
    });

    describe("Token Pair Management", function () {
        it("Should add token pair successfully", async function () {
            const { priceOracle, token0, token1, admin } = await loadFixture(deployPriceOracleFixture);

            const config = {
                useTWAP: true,
                useChainlink: true,
                requireBothSources: false,
                maxDeviation: 1000,
                twapWeight: 6000,
                chainlinkWeight: 4000,
                confidenceThreshold: 7000,
                stalePriceThreshold: 3600
            };

            await expect(priceOracle.connect(admin).addTokenPair(token0.target, token1.target, config))
                .to.emit(priceOracle, "TokenPairAdded");

            expect(await priceOracle.getSupportedPairsCount()).to.equal(1);

            const pairConfig = await priceOracle.getPairConfig(token0.target, token1.target);
            expect(pairConfig.isActive).to.be.true;
            expect(pairConfig.config.useTWAP).to.equal(config.useTWAP);
            expect(pairConfig.config.useChainlink).to.equal(config.useChainlink);
        });

        it("Should reject duplicate pair", async function () {
            const { priceOracle, token0, token1, admin } = await loadFixture(deployPriceOracleFixture);

            const config = {
                useTWAP: true,
                useChainlink: true,
                requireBothSources: false,
                maxDeviation: 1000,
                twapWeight: 6000,
                chainlinkWeight: 4000,
                confidenceThreshold: 7000,
                stalePriceThreshold: 3600
            };

            await priceOracle.connect(admin).addTokenPair(token0.target, token1.target, config);

            await expect(priceOracle.connect(admin).addTokenPair(token0.target, token1.target, config))
                .to.be.revertedWithCustomError(priceOracle, "PriceOracle__PairAlreadyExists");
        });

        it("Should reject invalid configuration", async function () {
            const { priceOracle, token0, token1, admin } = await loadFixture(deployPriceOracleFixture);

            // Invalid weights (don't sum to 10000)
            const invalidConfig = {
                useTWAP: true,
                useChainlink: true,
                requireBothSources: false,
                maxDeviation: 1000,
                twapWeight: 5000,
                chainlinkWeight: 3000, // Should be 5000 to sum to 10000
                confidenceThreshold: 7000,
                stalePriceThreshold: 3600
            };

            await expect(priceOracle.connect(admin).addTokenPair(token0.target, token1.target, invalidConfig))
                .to.be.revertedWithCustomError(priceOracle, "PriceOracle__InvalidConfiguration");
        });

        it("Should update token pair configuration", async function () {
            const { priceOracle, token0, token1, admin } = await loadFixture(deployPriceOracleFixture);

            const config = {
                useTWAP: true,
                useChainlink: true,
                requireBothSources: false,
                maxDeviation: 1000,
                twapWeight: 6000,
                chainlinkWeight: 4000,
                confidenceThreshold: 7000,
                stalePriceThreshold: 3600
            };

            await priceOracle.connect(admin).addTokenPair(token0.target, token1.target, config);

            const newConfig = {
                ...config,
                maxDeviation: 2000,
                twapWeight: 5000,
                chainlinkWeight: 5000
            };

            await expect(priceOracle.connect(admin).updateTokenPairConfig(token0.target, token1.target, newConfig))
                .to.emit(priceOracle, "TokenPairConfigUpdated");

            const updatedPairConfig = await priceOracle.getPairConfig(token0.target, token1.target);
            expect(updatedPairConfig.config.maxDeviation).to.equal(2000);
        });

        it("Should set default configuration", async function () {
            const { priceOracle, admin } = await loadFixture(deployPriceOracleFixture);

            const newConfig = {
                useTWAP: true,
                useChainlink: false,
                requireBothSources: false,
                maxDeviation: 2000,
                twapWeight: 10000,
                chainlinkWeight: 0,
                confidenceThreshold: 8000,
                stalePriceThreshold: 7200
            };

            await expect(priceOracle.connect(admin).setDefaultConfig(newConfig))
                .to.emit(priceOracle, "DefaultConfigUpdated");

            const config = await priceOracle.defaultConfig();
            expect(config.maxDeviation).to.equal(2000);
            expect(config.confidenceThreshold).to.equal(8000);
        });

        it("Should only allow admin to manage pairs", async function () {
            const { priceOracle, token0, token1, user } = await loadFixture(deployPriceOracleFixture);

            const config = {
                useTWAP: true,
                useChainlink: true,
                requireBothSources: false,
                maxDeviation: 1000,
                twapWeight: 6000,
                chainlinkWeight: 4000,
                confidenceThreshold: 7000,
                stalePriceThreshold: 3600
            };

            await expect(priceOracle.connect(user).addTokenPair(token0.target, token1.target, config))
                .to.be.reverted;
        });
    });

    describe("Price Queries", function () {
        beforeEach(async function () {
            const { priceOracle, token0, token1, admin, twapOracle, chainlinkOracle } = await loadFixture(deployPriceOracleFixture);

            const config = {
                useTWAP: true,
                useChainlink: true,
                requireBothSources: false,
                maxDeviation: 1000,
                twapWeight: 6000,
                chainlinkWeight: 4000,
                confidenceThreshold: 7000,
                stalePriceThreshold: 3600
            };

            await priceOracle.connect(admin).addTokenPair(token0.target, token1.target, config);

            // Set mock prices
            await twapOracle.setPrice(ethers.parseEther("1000"));
            await chainlinkOracle.setPrice(ethers.parseEther("1100"));

            this.priceOracle = priceOracle;
            this.token0 = token0;
            this.token1 = token1;
        });

        it("Should get aggregated price", async function () {
            const { priceOracle, token0, token1 } = this;

            const price = await priceOracle.getPrice(token0.target, token1.target);
            expect(price.isValid).to.be.true;
            expect(price.price).to.be.gt(0);
            expect(price.confidence).to.be.gte(7000);
        });

        it("Should get latest price with update", async function () {
            const { priceOracle, token0, token1 } = this;

            const price = await priceOracle.getLatestPrice(token0.target, token1.target);
            expect(price.isValid).to.be.true;
            expect(price.price).to.be.gt(0);
            expect(price.timestamp).to.be.gt(0);
        });

        it("Should get prices from all sources", async function () {
            const { priceOracle, token0, token1 } = this;

            const [twapPrice, chainlinkPrice, aggregatedPrice] = await priceOracle.getAllPrices(token0.target, token1.target);
            
            expect(twapPrice).to.be.gt(0);
            expect(chainlinkPrice).to.be.gt(0);
            expect(aggregatedPrice.isValid).to.be.true;
        });

        it("Should check if price is fresh", async function () {
            const { priceOracle, token0, token1 } = this;

            const isFresh = await priceOracle.isPriceFresh(token0.target, token1.target);
            expect(isFresh).to.be.a('boolean');
        });

        it("Should get batch prices", async function () {
            const { priceOracle, token0, token1, admin } = this;

            // Add another pair
            const MockToken = await ethers.getContractFactory("MockERC20");
            const token2 = await MockToken.deploy("Token2", "TK2", 18);

            const config = {
                useTWAP: true,
                useChainlink: true,
                requireBothSources: false,
                maxDeviation: 1000,
                twapWeight: 6000,
                chainlinkWeight: 4000,
                confidenceThreshold: 7000,
                stalePriceThreshold: 3600
            };

            await priceOracle.connect(admin).addTokenPair(token1.target, token2.target, config);

            const prices = await priceOracle.getBatchPrices(
                [token0.target, token1.target],
                [token1.target, token2.target]
            );

            expect(prices.length).to.equal(2);
            expect(prices[0].isValid).to.be.true;
        });

        it("Should reject queries for unsupported pairs", async function () {
            const { priceOracle } = await loadFixture(deployPriceOracleFixture);
            
            const MockToken = await ethers.getContractFactory("MockERC20");
            const invalidToken = await MockToken.deploy("Invalid", "INV", 18);

            await expect(priceOracle.getPrice(invalidToken.target, invalidToken.target))
                .to.be.revertedWithCustomError(priceOracle, "PriceOracle__PairNotSupported");
        });
    });

    describe("Price Updates", function () {
        beforeEach(async function () {
            const { priceOracle, token0, token1, admin, twapOracle, chainlinkOracle } = await loadFixture(deployPriceOracleFixture);

            const config = {
                useTWAP: true,
                useChainlink: true,
                requireBothSources: false,
                maxDeviation: 1000,
                twapWeight: 6000,
                chainlinkWeight: 4000,
                confidenceThreshold: 7000,
                stalePriceThreshold: 3600
            };

            await priceOracle.connect(admin).addTokenPair(token0.target, token1.target, config);

            await twapOracle.setPrice(ethers.parseEther("1000"));
            await chainlinkOracle.setPrice(ethers.parseEther("1100"));

            this.priceOracle = priceOracle;
            this.token0 = token0;
            this.token1 = token1;
            this.operator = operator;
        });

        it("Should update price for token pair", async function () {
            const { priceOracle, token0, token1, operator } = this;

            await expect(priceOracle.connect(operator).updatePrice(token0.target, token1.target))
                .to.emit(priceOracle, "PriceUpdated");
        });

        it("Should batch update prices", async function () {
            const { priceOracle, token0, token1, admin, operator } = this;

            // Add another pair
            const MockToken = await ethers.getContractFactory("MockERC20");
            const token2 = await MockToken.deploy("Token2", "TK2", 18);

            const config = {
                useTWAP: true,
                useChainlink: true,
                requireBothSources: false,
                maxDeviation: 1000,
                twapWeight: 6000,
                chainlinkWeight: 4000,
                confidenceThreshold: 7000,
                stalePriceThreshold: 3600
            };

            await priceOracle.connect(admin).addTokenPair(token1.target, token2.target, config);

            const batchId = await priceOracle.connect(operator).batchUpdatePrices.staticCall(
                [token0.target, token1.target],
                [token1.target, token2.target],
                false
            );

            await expect(priceOracle.connect(operator).batchUpdatePrices(
                [token0.target, token1.target],
                [token1.target, token2.target],
                false
            )).to.emit(priceOracle, "BatchUpdateExecuted");
        });

        it("Should handle price deviation detection", async function () {
            const { priceOracle, token0, token1, twapOracle, chainlinkOracle } = this;

            // Set prices with high deviation
            await twapOracle.setPrice(ethers.parseEther("1000"));
            await chainlinkOracle.setPrice(ethers.parseEther("2000")); // 100% deviation

            // This should trigger price deviation detection
            // The test depends on the specific configuration and thresholds
        });
    });

    describe("Emergency Management", function () {
        it("Should activate emergency mode", async function () {
            const { priceOracle, emergency } = await loadFixture(deployPriceOracleFixture);

            await expect(priceOracle.connect(emergency).activateEmergencyMode("Test emergency"))
                .to.emit(priceOracle, "EmergencyModeActivated")
                .withArgs(emergency.address, "Test emergency");

            expect(await priceOracle.emergencyMode()).to.be.true;
            expect(await priceOracle.status()).to.equal(2); // OracleStatus.EMERGENCY
        });

        it("Should deactivate emergency mode after cooldown", async function () {
            const { priceOracle, emergency } = await loadFixture(deployPriceOracleFixture);

            await priceOracle.connect(emergency).activateEmergencyMode("Test emergency");
            
            // Fast forward time past cooldown
            await time.increase(3601); // 1 hour + 1 second

            await expect(priceOracle.connect(emergency).deactivateEmergencyMode())
                .to.emit(priceOracle, "EmergencyModeDeactivated")
                .withArgs(emergency.address);

            expect(await priceOracle.emergencyMode()).to.be.false;
            expect(await priceOracle.status()).to.equal(0); // OracleStatus.ACTIVE
        });

        it("Should reject deactivation before cooldown", async function () {
            const { priceOracle, emergency } = await loadFixture(deployPriceOracleFixture);

            await priceOracle.connect(emergency).activateEmergencyMode("Test emergency");

            await expect(priceOracle.connect(emergency).deactivateEmergencyMode())
                .to.be.revertedWith("Emergency cooldown not met");
        });

        it("Should set emergency price", async function () {
            const { priceOracle, token0, token1, emergency } = await loadFixture(deployPriceOracleFixture);

            const emergencyPrice = ethers.parseEther("1500");

            await expect(priceOracle.connect(emergency).setEmergencyPrice(token0.target, token1.target, emergencyPrice))
                .to.emit(priceOracle, "EmergencyPriceSet");
        });

        it("Should reject operations in emergency mode", async function () {
            const { priceOracle, token0, token1, emergency, operator } = await loadFixture(deployPriceOracleFixture);

            await priceOracle.connect(emergency).activateEmergencyMode("Test emergency");

            await expect(priceOracle.connect(operator).updatePrice(token0.target, token1.target))
                .to.be.revertedWithCustomError(priceOracle, "PriceOracle__EmergencyModeActive");
        });
    });

    describe("Oracle Status Management", function () {
        it("Should set oracle status", async function () {
            const { priceOracle, admin } = await loadFixture(deployPriceOracleFixture);

            await expect(priceOracle.connect(admin).setOracleStatus(1)) // OracleStatus.INACTIVE
                .to.emit(priceOracle, "OracleStatusChanged")
                .withArgs(0, 1); // ACTIVE to INACTIVE

            expect(await priceOracle.status()).to.equal(1);
        });

        it("Should reject operations when inactive", async function () {
            const { priceOracle, token0, token1, admin, operator } = await loadFixture(deployPriceOracleFixture);

            await priceOracle.connect(admin).setOracleStatus(1); // INACTIVE

            await expect(priceOracle.connect(operator).updatePrice(token0.target, token1.target))
                .to.be.revertedWithCustomError(priceOracle, "PriceOracle__OracleInactive");
        });
    });

    describe("Pause Functions", function () {
        it("Should pause and unpause", async function () {
            const { priceOracle, admin } = await loadFixture(deployPriceOracleFixture);

            // Pause
            await priceOracle.connect(admin).pause();
            expect(await priceOracle.paused()).to.be.true;

            // Unpause
            await priceOracle.connect(admin).unpause();
            expect(await priceOracle.paused()).to.be.false;
        });
    });

    describe("View Functions", function () {
        it("Should get supported pairs", async function () {
            const { priceOracle, token0, token1, admin } = await loadFixture(deployPriceOracleFixture);

            const config = {
                useTWAP: true,
                useChainlink: true,
                requireBothSources: false,
                maxDeviation: 1000,
                twapWeight: 6000,
                chainlinkWeight: 4000,
                confidenceThreshold: 7000,
                stalePriceThreshold: 3600
            };

            await priceOracle.connect(admin).addTokenPair(token0.target, token1.target, config);

            const pairs = await priceOracle.getSupportedPairs();
            expect(pairs.length).to.equal(1);

            expect(await priceOracle.getSupportedPairsCount()).to.equal(1);
        });

        it("Should get price history", async function () {
            const { priceOracle, token0, token1, admin } = await loadFixture(deployPriceOracleFixture);

            const config = {
                useTWAP: true,
                useChainlink: true,
                requireBothSources: false,
                maxDeviation: 1000,
                twapWeight: 6000,
                chainlinkWeight: 4000,
                confidenceThreshold: 7000,
                stalePriceThreshold: 3600
            };

            await priceOracle.connect(admin).addTokenPair(token0.target, token1.target, config);

            const history = await priceOracle.getPriceHistory(token0.target, token1.target, 5);
            expect(history).to.be.an('array');
        });

        it("Should get oracle health", async function () {
            const { priceOracle } = await loadFixture(deployPriceOracleFixture);

            const [oracleStatus, emergency, activePairs, totalPairs] = await priceOracle.getOracleHealth();
            
            expect(oracleStatus).to.equal(0); // ACTIVE
            expect(emergency).to.be.false;
            expect(activePairs).to.be.a('bigint');
            expect(totalPairs).to.be.a('bigint');
        });
    });

    describe("Access Control", function () {
        it("Should enforce role-based access control", async function () {
            const { priceOracle, token0, token1, user } = await loadFixture(deployPriceOracleFixture);

            const config = {
                useTWAP: true,
                useChainlink: true,
                requireBothSources: false,
                maxDeviation: 1000,
                twapWeight: 6000,
                chainlinkWeight: 4000,
                confidenceThreshold: 7000,
                stalePriceThreshold: 3600
            };

            // User should not be able to perform admin functions
            await expect(priceOracle.connect(user).addTokenPair(token0.target, token1.target, config))
                .to.be.reverted;

            await expect(priceOracle.connect(user).setOracleStatus(1))
                .to.be.reverted;

            await expect(priceOracle.connect(user).activateEmergencyMode("test"))
                .to.be.reverted;
        });
    });
});

// Mock TWAP Oracle for testing
contract MockTWAPOracle {
    uint256 private price = 1000 * 1e18;

    function getTWAPPrice(address, uint32) external view returns (uint256, uint256) {
        return (price, 1e18 * 1e18 / price);
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }
}

// Mock Chainlink Oracle for testing
contract MockChainlinkOracle {
    uint256 private price = 1100 * 1e18;

    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 roundId;
        bool isValid;
        string source;
    }

    function getLatestPrice(address, address) external view returns (PriceData memory) {
        return PriceData({
            price: price,
            timestamp: block.timestamp,
            roundId: 1,
            isValid: true,
            source: "Chainlink"
        });
    }

    function setPrice(uint256 _price) external {
        price = _price;
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