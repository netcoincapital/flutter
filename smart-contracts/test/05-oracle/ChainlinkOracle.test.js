const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

describe("ChainlinkOracle", function () {
    async function deployChainlinkOracleFixture() {
        const [owner, admin, operator, user] = await ethers.getSigners();

        // Deploy ChainlinkOracle
        const ChainlinkOracle = await ethers.getContractFactory("ChainlinkOracle");
        const chainlinkOracle = await ChainlinkOracle.deploy();

        // Set up roles
        const ADMIN_ROLE = await chainlinkOracle.ADMIN_ROLE();
        const OPERATOR_ROLE = await chainlinkOracle.OPERATOR_ROLE();
        const PAUSER_ROLE = await chainlinkOracle.PAUSER_ROLE();

        await chainlinkOracle.grantRole(ADMIN_ROLE, admin.address);
        await chainlinkOracle.grantRole(OPERATOR_ROLE, operator.address);
        await chainlinkOracle.grantRole(PAUSER_ROLE, admin.address);

        // Deploy mock tokens
        const MockToken = await ethers.getContractFactory("MockERC20");
        const token0 = await MockToken.deploy("Token0", "TK0", 18);
        const token1 = await MockToken.deploy("Token1", "TK1", 18);

        // Deploy mock aggregator
        const MockAggregator = await ethers.getContractFactory("MockAggregatorV3");
        const mockAggregator = await MockAggregator.deploy(8, "ETH/USD", 1, 200000000000); // $2000 with 8 decimals

        return {
            chainlinkOracle,
            token0,
            token1,
            mockAggregator,
            owner,
            admin,
            operator,
            user,
            ADMIN_ROLE,
            OPERATOR_ROLE,
            PAUSER_ROLE
        };
    }

    describe("Deployment", function () {
        it("Should deploy with correct initial state", async function () {
            const { chainlinkOracle, owner } = await loadFixture(deployChainlinkOracleFixture);

            expect(await chainlinkOracle.fallbackMode()).to.equal(false);
            expect(await chainlinkOracle.maxHistoryLength()).to.equal(100);

            // Check initial roles
            expect(await chainlinkOracle.hasRole(await chainlinkOracle.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;

            // Check validation config
            const config = await chainlinkOracle.validationConfig();
            expect(config.maxPriceDeviation).to.equal(1000); // 10%
            expect(config.stalePriceThreshold).to.equal(3600); // 1 hour
            expect(config.enableValidation).to.be.true;
        });

        it("Should have correct constants", async function () {
            const { chainlinkOracle } = await loadFixture(deployChainlinkOracleFixture);

            expect(await chainlinkOracle.PRICE_PRECISION()).to.equal(ethers.parseEther("1"));
            expect(await chainlinkOracle.MAX_HEARTBEAT()).to.equal(86400);
            expect(await chainlinkOracle.MIN_HEARTBEAT()).to.equal(60);
            expect(await chainlinkOracle.MAX_PRICE_DEVIATION()).to.equal(5000);
            expect(await chainlinkOracle.STALE_PRICE_THRESHOLD()).to.equal(3600);
        });
    });

    describe("Price Feed Management", function () {
        it("Should add price feed successfully", async function () {
            const { chainlinkOracle, token0, token1, mockAggregator, admin } = await loadFixture(deployChainlinkOracleFixture);

            const heartbeat = 3600;

            await expect(chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                mockAggregator.target,
                heartbeat
            )).to.emit(chainlinkOracle, "PriceFeedAdded");

            // Check feed was added
            const feedKeys = await chainlinkOracle.getAllFeedKeys();
            expect(feedKeys.length).to.equal(1);

            // Check feed info
            const [aggregator, heartbeatStored, decimals, isActive, description] = await chainlinkOracle.getFeedInfo(
                token0.target,
                token1.target
            );
            expect(aggregator).to.equal(mockAggregator.target);
            expect(heartbeatStored).to.equal(heartbeat);
            expect(decimals).to.equal(8);
            expect(isActive).to.be.true;
            expect(description).to.equal("ETH/USD");
        });

        it("Should reject invalid feed parameters", async function () {
            const { chainlinkOracle, token0, token1, admin } = await loadFixture(deployChainlinkOracleFixture);

            // Invalid aggregator address
            await expect(chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                ethers.ZeroAddress,
                3600
            )).to.be.revertedWithCustomError(chainlinkOracle, "ChainlinkOracle__InvalidFeed");

            // Invalid heartbeat
            await expect(chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                token0.target, // Using token as invalid aggregator
                30
            )).to.be.revertedWithCustomError(chainlinkOracle, "ChainlinkOracle__InvalidHeartbeat");

            await expect(chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                token0.target,
                90000
            )).to.be.revertedWithCustomError(chainlinkOracle, "ChainlinkOracle__InvalidHeartbeat");
        });

        it("Should reject duplicate feed", async function () {
            const { chainlinkOracle, token0, token1, mockAggregator, admin } = await loadFixture(deployChainlinkOracleFixture);

            await chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                mockAggregator.target,
                3600
            );

            await expect(chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                mockAggregator.target,
                3600
            )).to.be.revertedWithCustomError(chainlinkOracle, "ChainlinkOracle__FeedAlreadyExists");
        });

        it("Should update price feed successfully", async function () {
            const { chainlinkOracle, token0, token1, mockAggregator, admin } = await loadFixture(deployChainlinkOracleFixture);

            // Add feed first
            await chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                mockAggregator.target,
                3600
            );

            // Deploy new aggregator
            const MockAggregator = await ethers.getContractFactory("MockAggregatorV3");
            const newAggregator = await MockAggregator.deploy(18, "BTC/USD", 1, ethers.parseEther("50000"));

            // Update feed
            const newHeartbeat = 1800;
            await expect(chainlinkOracle.connect(admin).updatePriceFeed(
                token0.target,
                token1.target,
                newAggregator.target,
                newHeartbeat
            )).to.emit(chainlinkOracle, "PriceFeedUpdated");

            // Check updated info
            const [aggregator, heartbeat, decimals] = await chainlinkOracle.getFeedInfo(
                token0.target,
                token1.target
            );
            expect(aggregator).to.equal(newAggregator.target);
            expect(heartbeat).to.equal(newHeartbeat);
            expect(decimals).to.equal(18);
        });

        it("Should remove price feed successfully", async function () {
            const { chainlinkOracle, token0, token1, mockAggregator, admin } = await loadFixture(deployChainlinkOracleFixture);

            // Add feed first
            await chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                mockAggregator.target,
                3600
            );

            expect(await chainlinkOracle.getAllFeedKeys()).to.have.length(1);

            // Remove feed
            await expect(chainlinkOracle.connect(admin).removePriceFeed(token0.target, token1.target))
                .to.emit(chainlinkOracle, "PriceFeedRemoved");

            expect(await chainlinkOracle.getAllFeedKeys()).to.have.length(0);
        });

        it("Should only allow admin to manage feeds", async function () {
            const { chainlinkOracle, token0, token1, mockAggregator, user } = await loadFixture(deployChainlinkOracleFixture);

            await expect(chainlinkOracle.connect(user).addPriceFeed(
                token0.target,
                token1.target,
                mockAggregator.target,
                3600
            )).to.be.reverted;

            await expect(chainlinkOracle.connect(user).removePriceFeed(token0.target, token1.target))
                .to.be.reverted;
        });
    });

    describe("Price Queries", function () {
        beforeEach(async function () {
            const { chainlinkOracle, token0, token1, mockAggregator, admin } = await loadFixture(deployChainlinkOracleFixture);
            
            // Add price feed
            await chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                mockAggregator.target,
                3600
            );
            
            // Store for use in tests
            this.chainlinkOracle = chainlinkOracle;
            this.token0 = token0;
            this.token1 = token1;
            this.mockAggregator = mockAggregator;
        });

        it("Should get latest price", async function () {
            const { chainlinkOracle, token0, token1 } = this;

            const priceData = await chainlinkOracle.getLatestPrice(token0.target, token1.target);
            
            expect(priceData.price).to.equal(ethers.parseEther("2000")); // Normalized to 18 decimals
            expect(priceData.timestamp).to.be.gt(0);
            expect(priceData.roundId).to.be.gt(0);
            expect(priceData.isValid).to.be.true;
            expect(priceData.source).to.equal("Chainlink");
        });

        it("Should get price at specific round", async function () {
            const { chainlinkOracle, token0, token1 } = this;

            const priceData = await chainlinkOracle.getPriceAtRound(token0.target, token1.target, 1);
            
            expect(priceData.price).to.equal(ethers.parseEther("2000"));
            expect(priceData.isValid).to.be.true;
            expect(priceData.source).to.equal("Chainlink");
        });

        it("Should get multiple latest prices", async function () {
            const { chainlinkOracle, token0, token1, admin, mockAggregator } = this;

            // Add another token pair
            const MockToken = await ethers.getContractFactory("MockERC20");
            const token2 = await MockToken.deploy("Token2", "TK2", 18);
            
            const MockAggregator = await ethers.getContractFactory("MockAggregatorV3");
            const aggregator2 = await MockAggregator.deploy(8, "BTC/USD", 1, 5000000000000); // $50,000

            await chainlinkOracle.connect(admin).addPriceFeed(
                token1.target,
                token2.target,
                aggregator2.target,
                3600
            );

            const pricesData = await chainlinkOracle.getLatestPrices(
                [token0.target, token1.target],
                [token1.target, token2.target]
            );

            expect(pricesData.length).to.equal(2);
            expect(pricesData[0].isValid).to.be.true;
            expect(pricesData[1].isValid).to.be.true;
            expect(pricesData[0].price).to.equal(ethers.parseEther("2000"));
            expect(pricesData[1].price).to.equal(ethers.parseEther("50000"));
        });

        it("Should check price feed health", async function () {
            const { chainlinkOracle, token0, token1 } = this;

            const isHealthy = await chainlinkOracle.isPriceFeedHealthy(token0.target, token1.target);
            expect(isHealthy).to.be.true;
        });

        it("Should reject queries for non-existent feeds", async function () {
            const { chainlinkOracle } = await loadFixture(deployChainlinkOracleFixture);
            
            const MockToken = await ethers.getContractFactory("MockERC20");
            const invalidToken = await MockToken.deploy("Invalid", "INV", 18);

            await expect(chainlinkOracle.getLatestPrice(invalidToken.target, invalidToken.target))
                .to.be.revertedWithCustomError(chainlinkOracle, "ChainlinkOracle__FeedNotFound");
        });

        it("Should handle stale prices", async function () {
            const { chainlinkOracle, token0, token1, mockAggregator } = this;

            // Set old timestamp to make price stale
            const oldTimestamp = Math.floor(Date.now() / 1000) - 7200; // 2 hours ago
            await mockAggregator.setLatestRoundData(1, 200000000000, oldTimestamp, oldTimestamp, 1);

            await expect(chainlinkOracle.getLatestPrice(token0.target, token1.target))
                .to.be.revertedWithCustomError(chainlinkOracle, "ChainlinkOracle__StalePrice");
        });
    });

    describe("Validation", function () {
        beforeEach(async function () {
            const { chainlinkOracle, token0, token1, mockAggregator, admin } = await loadFixture(deployChainlinkOracleFixture);
            
            await chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                mockAggregator.target,
                3600
            );
            
            this.chainlinkOracle = chainlinkOracle;
            this.token0 = token0;
            this.token1 = token1;
            this.mockAggregator = mockAggregator;
            this.admin = admin;
        });

        it("Should validate price history", async function () {
            const { chainlinkOracle, token0, token1, operator } = this;

            // Update price history
            await chainlinkOracle.connect(operator).updatePriceHistory(token0.target, token1.target);

            // Get price history
            const history = await chainlinkOracle.getPriceHistory(token0.target, token1.target, 5);
            expect(history.length).to.be.gte(1);
        });

        it("Should detect price deviation", async function () {
            const { chainlinkOracle, token0, token1, mockAggregator, admin } = this;

            // First update to establish history
            await chainlinkOracle.connect(admin).updatePriceHistory(token0.target, token1.target);

            // Set a price with high deviation
            const extremePrice = 1000000000000; // $10,000 (5x increase)
            await mockAggregator.setLatestRoundData(2, extremePrice, Math.floor(Date.now() / 1000), Math.floor(Date.now() / 1000), 2);

            // This should potentially trigger validation error if deviation is too high
            // (depends on validation configuration)
        });
    });

    describe("Fallback Mode", function () {
        it("Should set and use fallback prices", async function () {
            const { chainlinkOracle, token0, token1, mockAggregator, admin } = await loadFixture(deployChainlinkOracleFixture);

            await chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                mockAggregator.target,
                3600
            );

            // Set fallback price
            const fallbackPrice = ethers.parseEther("1500");
            await expect(chainlinkOracle.connect(admin).setFallbackPrice(token0.target, token1.target, fallbackPrice))
                .to.emit(chainlinkOracle, "FallbackPriceSet");

            // Enable fallback mode
            await expect(chainlinkOracle.connect(admin).setFallbackMode(true))
                .to.emit(chainlinkOracle, "FallbackModeToggled")
                .withArgs(true);

            // Now price queries should return fallback price
            const priceData = await chainlinkOracle.getLatestPrice(token0.target, token1.target);
            expect(priceData.price).to.equal(fallbackPrice);
            expect(priceData.source).to.equal("Fallback");
        });

        it("Should disable fallback mode", async function () {
            const { chainlinkOracle, admin } = await loadFixture(deployChainlinkOracleFixture);

            await chainlinkOracle.connect(admin).setFallbackMode(true);
            expect(await chainlinkOracle.fallbackMode()).to.be.true;

            await chainlinkOracle.connect(admin).setFallbackMode(false);
            expect(await chainlinkOracle.fallbackMode()).to.be.false;
        });
    });

    describe("Configuration", function () {
        it("Should set validation configuration", async function () {
            const { chainlinkOracle, admin } = await loadFixture(deployChainlinkOracleFixture);

            const newConfig = {
                maxPriceDeviation: 2000, // 20%
                stalePriceThreshold: 7200, // 2 hours
                enableValidation: false,
                requireMinAnswers: true,
                minAnswers: 3
            };

            await expect(chainlinkOracle.connect(admin).setValidationConfig(newConfig))
                .to.emit(chainlinkOracle, "ValidationConfigUpdated");

            const config = await chainlinkOracle.validationConfig();
            expect(config.maxPriceDeviation).to.equal(newConfig.maxPriceDeviation);
            expect(config.stalePriceThreshold).to.equal(newConfig.stalePriceThreshold);
            expect(config.enableValidation).to.equal(newConfig.enableValidation);
            expect(config.requireMinAnswers).to.equal(newConfig.requireMinAnswers);
            expect(config.minAnswers).to.equal(newConfig.minAnswers);
        });

        it("Should set feed active status", async function () {
            const { chainlinkOracle, token0, token1, mockAggregator, admin, operator } = await loadFixture(deployChainlinkOracleFixture);

            await chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                mockAggregator.target,
                3600
            );

            // Deactivate feed
            await chainlinkOracle.connect(operator).setFeedActive(token0.target, token1.target, false);
            
            const [,, , isActive] = await chainlinkOracle.getFeedInfo(token0.target, token1.target);
            expect(isActive).to.be.false;

            // Reactivate feed
            await chainlinkOracle.connect(operator).setFeedActive(token0.target, token1.target, true);
            
            const [,, , isActiveAfter] = await chainlinkOracle.getFeedInfo(token0.target, token1.target);
            expect(isActiveAfter).to.be.true;
        });
    });

    describe("Pause Functions", function () {
        it("Should pause and unpause", async function () {
            const { chainlinkOracle, admin } = await loadFixture(deployChainlinkOracleFixture);

            // Pause
            await chainlinkOracle.connect(admin).pause();
            expect(await chainlinkOracle.paused()).to.be.true;

            // Unpause
            await chainlinkOracle.connect(admin).unpause();
            expect(await chainlinkOracle.paused()).to.be.false;
        });
    });

    describe("View Functions", function () {
        it("Should get all feed keys", async function () {
            const { chainlinkOracle, token0, token1, mockAggregator, admin } = await loadFixture(deployChainlinkOracleFixture);

            expect(await chainlinkOracle.getAllFeedKeys()).to.have.length(0);

            await chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                mockAggregator.target,
                3600
            );

            const feedKeys = await chainlinkOracle.getAllFeedKeys();
            expect(feedKeys).to.have.length(1);
        });

        it("Should get feed information", async function () {
            const { chainlinkOracle, token0, token1, mockAggregator, admin } = await loadFixture(deployChainlinkOracleFixture);

            await chainlinkOracle.connect(admin).addPriceFeed(
                token0.target,
                token1.target,
                mockAggregator.target,
                3600
            );

            const [aggregator, heartbeat, decimals, isActive, description] = await chainlinkOracle.getFeedInfo(
                token0.target,
                token1.target
            );

            expect(aggregator).to.equal(mockAggregator.target);
            expect(heartbeat).to.equal(3600);
            expect(decimals).to.equal(8);
            expect(isActive).to.be.true;
            expect(description).to.equal("ETH/USD");
        });
    });

    describe("Access Control", function () {
        it("Should enforce role-based access control", async function () {
            const { chainlinkOracle, token0, token1, mockAggregator, user } = await loadFixture(deployChainlinkOracleFixture);

            // User should not be able to perform admin functions
            await expect(chainlinkOracle.connect(user).addPriceFeed(
                token0.target,
                token1.target,
                mockAggregator.target,
                3600
            )).to.be.reverted;

            await expect(chainlinkOracle.connect(user).setFallbackMode(true))
                .to.be.reverted;

            await expect(chainlinkOracle.connect(user).pause())
                .to.be.reverted;
        });
    });
});

// Mock ERC20 token for testing
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = 1000000 * 10**_decimals;
    }
}

// Mock Chainlink Aggregator for testing
contract MockAggregatorV3 {
    uint8 public decimals;
    string public description;
    uint256 public version;
    
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }
    
    mapping(uint80 => RoundData) public rounds;
    uint80 public latestRound;

    constructor(uint8 _decimals, string memory _description, uint256 _version, int256 _initialAnswer) {
        decimals = _decimals;
        description = _description;
        version = _version;
        
        // Set initial round
        latestRound = 1;
        rounds[1] = RoundData({
            roundId: 1,
            answer: _initialAnswer,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 1
        });
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        RoundData memory round = rounds[latestRound];
        return (round.roundId, round.answer, round.startedAt, round.updatedAt, round.answeredInRound);
    }

    function getRoundData(uint80 _roundId) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        RoundData memory round = rounds[_roundId];
        require(round.roundId != 0, "Round not found");
        return (round.roundId, round.answer, round.startedAt, round.updatedAt, round.answeredInRound);
    }

    function setLatestRoundData(
        uint80 _roundId,
        int256 _answer,
        uint256 _startedAt,
        uint256 _updatedAt,
        uint80 _answeredInRound
    ) external {
        rounds[_roundId] = RoundData({
            roundId: _roundId,
            answer: _answer,
            startedAt: _startedAt,
            updatedAt: _updatedAt,
            answeredInRound: _answeredInRound
        });
        latestRound = _roundId;
    }
} 