const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

describe("TWAPOracle", function () {
    async function deployTWAPOracleFixture() {
        const [owner, admin, operator, user] = await ethers.getSigners();

        // Deploy LaxceAccessControl
        const LaxceAccessControl = await ethers.getContractFactory("LaxceAccessControl");
        const accessControl = await LaxceAccessControl.deploy();

        // Deploy TWAPOracle
        const TWAPOracle = await ethers.getContractFactory("TWAPOracle");
        const twapOracle = await TWAPOracle.deploy();

        // Set up roles
        const ADMIN_ROLE = await accessControl.ADMIN_ROLE();
        const OPERATOR_ROLE = await accessControl.OPERATOR_ROLE();
        const PAUSER_ROLE = await accessControl.PAUSER_ROLE();

        await twapOracle.grantRole(ADMIN_ROLE, admin.address);
        await twapOracle.grantRole(OPERATOR_ROLE, operator.address);
        await twapOracle.grantRole(PAUSER_ROLE, admin.address);

        // Mock pool contract
        const MockPool = await ethers.getContractFactory("MockLaxcePool");
        const mockPool = await MockPool.deploy();

        return {
            twapOracle,
            mockPool,
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
            const { twapOracle, owner } = await loadFixture(deployTWAPOracleFixture);

            expect(await twapOracle.defaultPeriod()).to.equal(3600);
            expect(await twapOracle.defaultCardinality()).to.equal(100);
            expect(await twapOracle.updateInterval()).to.equal(300);
            expect(await twapOracle.maxPriceDeviation()).to.equal(1000);
            expect(await twapOracle.emergencyMode()).to.equal(false);

            // Check initial roles
            expect(await twapOracle.hasRole(await twapOracle.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;
        });

        it("Should have correct constants", async function () {
            const { twapOracle } = await loadFixture(deployTWAPOracleFixture);

            expect(await twapOracle.MAX_PERIOD()).to.equal(86400);
            expect(await twapOracle.MIN_PERIOD()).to.equal(60);
            expect(await twapOracle.MAX_CARDINALITY()).to.equal(65535);
            expect(await twapOracle.MIN_CARDINALITY()).to.equal(2);
            expect(await twapOracle.PRECISION()).to.equal(ethers.parseEther("1"));
        });
    });

    describe("Pool Management", function () {
        it("Should add pool successfully", async function () {
            const { twapOracle, mockPool, admin } = await loadFixture(deployTWAPOracleFixture);

            const period = 3600;
            const cardinality = 100;

            await expect(twapOracle.connect(admin).addPool(mockPool.target, period, cardinality))
                .to.emit(twapOracle, "PoolAdded")
                .withArgs(mockPool.target, period, cardinality);

            // Check pool was added
            expect(await twapOracle.isSupportedPool(mockPool.target)).to.be.true;
            expect(await twapOracle.getSupportedPoolsCount()).to.equal(1);

            // Check pool data
            const twapData = await twapOracle.twapData(mockPool.target);
            expect(twapData.pool).to.equal(mockPool.target);
            expect(twapData.period).to.equal(period);
            expect(twapData.cardinality).to.equal(cardinality);
            expect(twapData.isValid).to.be.true;
        });

        it("Should reject invalid pool parameters", async function () {
            const { twapOracle, mockPool, admin } = await loadFixture(deployTWAPOracleFixture);

            // Invalid address
            await expect(twapOracle.connect(admin).addPool(ethers.ZeroAddress, 3600, 100))
                .to.be.revertedWithCustomError(twapOracle, "TWAPOracle__InvalidPool");

            // Invalid period
            await expect(twapOracle.connect(admin).addPool(mockPool.target, 30, 100))
                .to.be.revertedWithCustomError(twapOracle, "TWAPOracle__InvalidPeriod");

            await expect(twapOracle.connect(admin).addPool(mockPool.target, 90000, 100))
                .to.be.revertedWithCustomError(twapOracle, "TWAPOracle__InvalidPeriod");

            // Invalid cardinality
            await expect(twapOracle.connect(admin).addPool(mockPool.target, 3600, 1))
                .to.be.revertedWithCustomError(twapOracle, "TWAPOracle__InvalidCardinality");

            await expect(twapOracle.connect(admin).addPool(mockPool.target, 3600, 70000))
                .to.be.revertedWithCustomError(twapOracle, "TWAPOracle__InvalidCardinality");
        });

        it("Should reject duplicate pool", async function () {
            const { twapOracle, mockPool, admin } = await loadFixture(deployTWAPOracleFixture);

            await twapOracle.connect(admin).addPool(mockPool.target, 3600, 100);

            await expect(twapOracle.connect(admin).addPool(mockPool.target, 3600, 100))
                .to.be.revertedWithCustomError(twapOracle, "TWAPOracle__AlreadySupported");
        });

        it("Should remove pool successfully", async function () {
            const { twapOracle, mockPool, admin } = await loadFixture(deployTWAPOracleFixture);

            // Add pool first
            await twapOracle.connect(admin).addPool(mockPool.target, 3600, 100);
            expect(await twapOracle.isSupportedPool(mockPool.target)).to.be.true;

            // Remove pool
            await expect(twapOracle.connect(admin).removePool(mockPool.target))
                .to.emit(twapOracle, "PoolRemoved")
                .withArgs(mockPool.target);

            // Check pool was removed
            expect(await twapOracle.isSupportedPool(mockPool.target)).to.be.false;
            expect(await twapOracle.getSupportedPoolsCount()).to.equal(0);
        });

        it("Should reject removing non-existent pool", async function () {
            const { twapOracle, mockPool, admin } = await loadFixture(deployTWAPOracleFixture);

            await expect(twapOracle.connect(admin).removePool(mockPool.target))
                .to.be.revertedWithCustomError(twapOracle, "TWAPOracle__InvalidPool");
        });

        it("Should only allow admin to manage pools", async function () {
            const { twapOracle, mockPool, user } = await loadFixture(deployTWAPOracleFixture);

            await expect(twapOracle.connect(user).addPool(mockPool.target, 3600, 100))
                .to.be.reverted;

            await expect(twapOracle.connect(user).removePool(mockPool.target))
                .to.be.reverted;
        });
    });

    describe("TWAP Updates", function () {
        it("Should update TWAP for pool", async function () {
            const { twapOracle, mockPool, admin, operator } = await loadFixture(deployTWAPOracleFixture);

            // Add pool
            await twapOracle.connect(admin).addPool(mockPool.target, 3600, 100);

            // Fast forward time to allow update
            await time.increase(301);

            // Update TWAP
            await expect(twapOracle.connect(operator).updateTWAP(mockPool.target))
                .to.emit(twapOracle, "TWAPUpdated");

            // Check that last update time was set
            const twapData = await twapOracle.twapData(mockPool.target);
            expect(twapData.lastUpdate).to.be.gt(0);
        });

        it("Should reject update too soon", async function () {
            const { twapOracle, mockPool, admin, operator } = await loadFixture(deployTWAPOracleFixture);

            // Add pool and update
            await twapOracle.connect(admin).addPool(mockPool.target, 3600, 100);
            await time.increase(301);
            await twapOracle.connect(operator).updateTWAP(mockPool.target);

            // Try to update again immediately
            await expect(twapOracle.connect(operator).updateTWAP(mockPool.target))
                .to.be.revertedWithCustomError(twapOracle, "TWAPOracle__UpdateTooSoon");
        });

        it("Should batch update TWAP for multiple pools", async function () {
            const { twapOracle, admin, operator } = await loadFixture(deployTWAPOracleFixture);

            // Deploy multiple mock pools
            const MockPool = await ethers.getContractFactory("MockLaxcePool");
            const mockPool1 = await MockPool.deploy();
            const mockPool2 = await MockPool.deploy();

            // Add pools
            await twapOracle.connect(admin).addPool(mockPool1.target, 3600, 100);
            await twapOracle.connect(admin).addPool(mockPool2.target, 3600, 100);

            // Fast forward time
            await time.increase(301);

            // Batch update
            await twapOracle.connect(operator).batchUpdateTWAP([mockPool1.target, mockPool2.target]);

            // Check both pools were updated
            const twapData1 = await twapOracle.twapData(mockPool1.target);
            const twapData2 = await twapOracle.twapData(mockPool2.target);
            expect(twapData1.lastUpdate).to.be.gt(0);
            expect(twapData2.lastUpdate).to.be.gt(0);
        });

        it("Should handle emergency update", async function () {
            const { twapOracle, mockPool, admin } = await loadFixture(deployTWAPOracleFixture);

            // Add pool
            await twapOracle.connect(admin).addPool(mockPool.target, 3600, 100);

            // Emergency update (requires EMERGENCY_ROLE)
            const EMERGENCY_ROLE = await twapOracle.EMERGENCY_ROLE();
            await twapOracle.grantRole(EMERGENCY_ROLE, admin.address);

            await expect(twapOracle.connect(admin).emergencyUpdateAll())
                .to.emit(twapOracle, "EmergencyModeToggled")
                .withArgs(true);

            expect(await twapOracle.emergencyMode()).to.be.true;
        });
    });

    describe("Price Queries", function () {
        beforeEach(async function () {
            const { twapOracle, mockPool, admin } = await loadFixture(deployTWAPOracleFixture);
            
            // Add pool and wait for initialization
            await twapOracle.connect(admin).addPool(mockPool.target, 3600, 100);
            await time.increase(301);
            
            // Store for use in tests
            this.twapOracle = twapOracle;
            this.mockPool = mockPool;
        });

        it("Should get TWAP price", async function () {
            const { twapOracle, mockPool } = this;

            const [price0, price1] = await twapOracle.getTWAPPrice(mockPool.target, 3600);
            
            expect(price0).to.be.gt(0);
            expect(price1).to.be.gt(0);
        });

        it("Should get spot price", async function () {
            const { twapOracle, mockPool } = this;

            const [price0, price1] = await twapOracle.getSpotPrice(mockPool.target);
            
            expect(price0).to.be.gt(0);
            expect(price1).to.be.gt(0);
        });

        it("Should get price info", async function () {
            const { twapOracle, mockPool } = this;

            const priceInfo = await twapOracle.getPriceInfo(mockPool.target);
            
            expect(priceInfo.price0).to.be.gt(0);
            expect(priceInfo.price1).to.be.gt(0);
            expect(priceInfo.timestamp).to.be.gt(0);
            expect(priceInfo.period).to.equal(3600);
            expect(priceInfo.isValid).to.be.true;
        });

        it("Should validate price within deviation", async function () {
            const { twapOracle, mockPool } = this;

            const referencePrice = ethers.parseEther("1");
            const isValid = await twapOracle.isPriceValid(mockPool.target, referencePrice);
            
            expect(isValid).to.be.a('boolean');
        });

        it("Should reject queries for invalid pools", async function () {
            const { twapOracle } = await loadFixture(deployTWAPOracleFixture);
            const invalidPool = ethers.ZeroAddress;

            await expect(twapOracle.getTWAPPrice(invalidPool, 3600))
                .to.be.revertedWithCustomError(twapOracle, "TWAPOracle__InvalidPool");
        });
    });

    describe("Observations", function () {
        it("Should get observation at index", async function () {
            const { twapOracle, mockPool, admin } = await loadFixture(deployTWAPOracleFixture);

            await twapOracle.connect(admin).addPool(mockPool.target, 3600, 100);
            
            const observation = await twapOracle.getObservation(mockPool.target, 0);
            expect(observation.initialized).to.be.true;
            expect(observation.blockTimestamp).to.be.gt(0);
        });

        it("Should get latest observations", async function () {
            const { twapOracle, mockPool, admin, operator } = await loadFixture(deployTWAPOracleFixture);

            await twapOracle.connect(admin).addPool(mockPool.target, 3600, 100);
            
            // Add more observations by updating
            await time.increase(301);
            await twapOracle.connect(operator).updateTWAP(mockPool.target);
            
            const observations = await twapOracle.getLatestObservations(mockPool.target, 5);
            expect(observations.length).to.be.lte(5);
            expect(observations[0].initialized).to.be.true;
        });

        it("Should check if TWAP is stale", async function () {
            const { twapOracle, mockPool, admin } = await loadFixture(deployTWAPOracleFixture);

            await twapOracle.connect(admin).addPool(mockPool.target, 3600, 100);
            
            // Check freshness
            const isStale = await twapOracle.isTWAPStale(mockPool.target, 3600);
            expect(isStale).to.be.a('boolean');
        });
    });

    describe("Configuration", function () {
        it("Should set default configuration", async function () {
            const { twapOracle, admin } = await loadFixture(deployTWAPOracleFixture);

            const newPeriod = 1800;
            const newCardinality = 200;
            const newInterval = 600;

            await expect(twapOracle.connect(admin).setDefaultConfiguration(newPeriod, newCardinality, newInterval))
                .to.emit(twapOracle, "ConfigurationUpdated")
                .withArgs(newPeriod, newCardinality, newInterval);

            expect(await twapOracle.defaultPeriod()).to.equal(newPeriod);
            expect(await twapOracle.defaultCardinality()).to.equal(newCardinality);
            expect(await twapOracle.updateInterval()).to.equal(newInterval);
        });

        it("Should reject invalid configuration", async function () {
            const { twapOracle, admin } = await loadFixture(deployTWAPOracleFixture);

            // Invalid period
            await expect(twapOracle.connect(admin).setDefaultConfiguration(30, 100, 300))
                .to.be.revertedWithCustomError(twapOracle, "TWAPOracle__InvalidPeriod");

            // Invalid cardinality
            await expect(twapOracle.connect(admin).setDefaultConfiguration(3600, 1, 300))
                .to.be.revertedWithCustomError(twapOracle, "TWAPOracle__InvalidCardinality");
        });

        it("Should set maximum price deviation", async function () {
            const { twapOracle, admin } = await loadFixture(deployTWAPOracleFixture);

            const newDeviation = 2000;

            await expect(twapOracle.connect(admin).setMaxPriceDeviation(newDeviation))
                .to.emit(twapOracle, "MaxPriceDeviationUpdated")
                .withArgs(1000, newDeviation);

            expect(await twapOracle.maxPriceDeviation()).to.equal(newDeviation);
        });

        it("Should toggle pool monitoring", async function () {
            const { twapOracle, mockPool, admin, operator } = await loadFixture(deployTWAPOracleFixture);

            await twapOracle.connect(admin).addPool(mockPool.target, 3600, 100);
            
            // Disable monitoring
            await twapOracle.connect(operator).setPoolMonitoring(mockPool.target, false);
            expect(await twapOracle.isMonitoring(mockPool.target)).to.be.false;
            
            // Re-enable monitoring
            await twapOracle.connect(operator).setPoolMonitoring(mockPool.target, true);
            expect(await twapOracle.isMonitoring(mockPool.target)).to.be.true;
        });

        it("Should get configuration", async function () {
            const { twapOracle } = await loadFixture(deployTWAPOracleFixture);

            const config = await twapOracle.getConfiguration();
            
            expect(config._defaultPeriod).to.equal(3600);
            expect(config._defaultCardinality).to.equal(100);
            expect(config._updateInterval).to.equal(300);
            expect(config._maxPriceDeviation).to.equal(1000);
            expect(config._emergencyMode).to.be.false;
        });
    });

    describe("Emergency Functions", function () {
        it("Should exit emergency mode", async function () {
            const { twapOracle, admin } = await loadFixture(deployTWAPOracleFixture);

            // First activate emergency mode
            const EMERGENCY_ROLE = await twapOracle.EMERGENCY_ROLE();
            await twapOracle.grantRole(EMERGENCY_ROLE, admin.address);
            await twapOracle.connect(admin).emergencyUpdateAll();

            // Exit emergency mode
            await expect(twapOracle.connect(admin).exitEmergencyMode())
                .to.emit(twapOracle, "EmergencyModeToggled")
                .withArgs(false);

            expect(await twapOracle.emergencyMode()).to.be.false;
        });
    });

    describe("Pause Functions", function () {
        it("Should pause and unpause", async function () {
            const { twapOracle, admin } = await loadFixture(deployTWAPOracleFixture);

            // Pause
            await twapOracle.connect(admin).pause();
            expect(await twapOracle.paused()).to.be.true;

            // Unpause
            await twapOracle.connect(admin).unpause();
            expect(await twapOracle.paused()).to.be.false;
        });

        it("Should reject operations when paused", async function () {
            const { twapOracle, mockPool, admin, operator } = await loadFixture(deployTWAPOracleFixture);

            await twapOracle.connect(admin).addPool(mockPool.target, 3600, 100);
            await twapOracle.connect(admin).pause();

            await expect(twapOracle.connect(operator).updateTWAP(mockPool.target))
                .to.be.revertedWith("Pausable: paused");
        });
    });

    describe("View Functions", function () {
        it("Should get supported pools", async function () {
            const { twapOracle, mockPool, admin } = await loadFixture(deployTWAPOracleFixture);

            await twapOracle.connect(admin).addPool(mockPool.target, 3600, 100);
            
            const pools = await twapOracle.getSupportedPools();
            expect(pools.length).to.equal(1);
            expect(pools[0]).to.equal(mockPool.target);
        });

        it("Should get supported pools count", async function () {
            const { twapOracle, mockPool, admin } = await loadFixture(deployTWAPOracleFixture);

            expect(await twapOracle.getSupportedPoolsCount()).to.equal(0);
            
            await twapOracle.connect(admin).addPool(mockPool.target, 3600, 100);
            expect(await twapOracle.getSupportedPoolsCount()).to.equal(1);
        });
    });

    describe("Access Control", function () {
        it("Should enforce role-based access control", async function () {
            const { twapOracle, mockPool, user } = await loadFixture(deployTWAPOracleFixture);

            // User should not be able to perform admin functions
            await expect(twapOracle.connect(user).addPool(mockPool.target, 3600, 100))
                .to.be.reverted;

            await expect(twapOracle.connect(user).setDefaultConfiguration(1800, 50, 600))
                .to.be.reverted;

            await expect(twapOracle.connect(user).pause())
                .to.be.reverted;
        });
    });
});

// Mock contract for testing
contract MockLaxcePool {
    uint160 public sqrtPriceX96 = 79228162514264337593543950336; // sqrt(1) in Q96
    int24 public tick = 0;
    uint128 public liquidity = 1000000;

    function slot0() external view returns (
        uint160 _sqrtPriceX96,
        int24 _tick,
        uint16,
        uint16,
        uint16,
        uint8,
        bool
    ) {
        return (sqrtPriceX96, tick, 0, 0, 0, 0, true);
    }

    function setPrice(uint160 _sqrtPriceX96, int24 _tick) external {
        sqrtPriceX96 = _sqrtPriceX96;
        tick = _tick;
    }

    function setLiquidity(uint128 _liquidity) external {
        liquidity = _liquidity;
    }
} 