const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("PoolManager", function () {
    let owner, addr1, addr2, addr3;
    let poolManager, poolFactory, positionNFT, laxcePool;
    let token0, token1, weth9, accessControl, tokenRegistry;

    const FEE = 3000; // 0.3%
    const TICK_SPACING = 60;
    const TICK_LOWER = -120;
    const TICK_UPPER = 120;
    const DEADLINE = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

    async function deployPoolManagerFixture() {
        [owner, addr1, addr2, addr3] = await ethers.getSigners();

        // Deploy AccessControl
        const AccessControl = await ethers.getContractFactory("LaxceAccessControl");
        accessControl = await AccessControl.deploy(
            owner.address, // treasury
            owner.address, // teamWallet
            owner.address  // marketingWallet
        );

        // Deploy Mock WETH9
        const MockWETH9 = await ethers.getContractFactory("MockWETH9");
        weth9 = await MockWETH9.deploy();

        // Deploy Mock ERC20 tokens
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        let tokenA = await MockERC20.deploy("Token A", "TKNA", 18);
        let tokenB = await MockERC20.deploy("Token B", "TKNB", 18);

        // Ensure token0 < token1
        if (tokenA.address.toLowerCase() > tokenB.address.toLowerCase()) {
            [token0, token1] = [tokenB, tokenA];
        } else {
            [token0, token1] = [tokenA, tokenB];
        }

        // Deploy TokenRegistry
        const TokenRegistry = await ethers.getContractFactory("TokenRegistry");
        tokenRegistry = await TokenRegistry.deploy(accessControl.address);

        // Deploy PositionNFT
        const PositionNFT = await ethers.getContractFactory("PositionNFT");
        positionNFT = await PositionNFT.deploy(
            "LAXCE Position NFT",
            "LXC-POS",
            accessControl.address
        );

        // Deploy PoolFactory
        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        poolFactory = await PoolFactory.deploy(tokenRegistry.address);

        // Deploy PoolManager
        const PoolManager = await ethers.getContractFactory("PoolManager");
        poolManager = await PoolManager.deploy(
            poolFactory.address,
            positionNFT.address,
            weth9.address
        );

        // Create a pool
        await poolFactory.createPool(token0.address, token1.address, FEE);
        const poolAddress = await poolFactory.getPool(token0.address, token1.address, FEE);
        
        // Get pool contract instance
        const LaxcePool = await ethers.getContractFactory("LaxcePool");
        laxcePool = LaxcePool.attach(poolAddress);

        // Initialize pool
        const initialPrice = "79228162514264337593543950336"; // sqrt(1) in Q96
        await laxcePool.initialize(
            poolFactory.address,
            token0.address,
            token1.address,
            FEE,
            TICK_SPACING,
            owner.address, // lpToken placeholder
            positionNFT.address,
            initialPrice
        );

        // Mint tokens to test accounts
        const mintAmount = ethers.utils.parseEther("1000000");
        await token0.mint(owner.address, mintAmount);
        await token0.mint(addr1.address, mintAmount);
        await token0.mint(addr2.address, mintAmount);
        
        await token1.mint(owner.address, mintAmount);
        await token1.mint(addr1.address, mintAmount);
        await token1.mint(addr2.address, mintAmount);

        // Approve PoolManager for token transfers
        await token0.connect(owner).approve(poolManager.address, mintAmount);
        await token0.connect(addr1).approve(poolManager.address, mintAmount);
        await token0.connect(addr2).approve(poolManager.address, mintAmount);
        
        await token1.connect(owner).approve(poolManager.address, mintAmount);
        await token1.connect(addr1).approve(poolManager.address, mintAmount);
        await token1.connect(addr2).approve(poolManager.address, mintAmount);

        return {
            poolManager,
            poolFactory,
            positionNFT,
            laxcePool,
            token0,
            token1,
            weth9,
            accessControl,
            tokenRegistry,
            owner,
            addr1,
            addr2,
            addr3
        };
    }

    beforeEach(async function () {
        const fixture = await loadFixture(deployPoolManagerFixture);
        Object.assign(this, fixture);
        ({
            poolManager,
            poolFactory,
            positionNFT,
            laxcePool,
            token0,
            token1,
            weth9,
            accessControl,
            tokenRegistry,
            owner,
            addr1,
            addr2,
            addr3
        } = fixture);
    });

    describe("Deployment & Initialization", function () {
        it("Should deploy with correct parameters", async function () {
            expect(await poolManager.factory()).to.equal(poolFactory.address);
            expect(await poolManager.positionNFT()).to.equal(positionNFT.address);
            expect(await poolManager.WETH9()).to.equal(weth9.address);
        });

        it("Should have correct initial state", async function () {
            expect(await poolManager.defaultSlippage()).to.equal(500); // 5%
            expect(await poolManager.autoCompoundEnabled()).to.be.false;
            expect(await poolManager.minLiquidityForAutoCompound()).to.equal(ethers.utils.parseEther("1000"));
        });

        it("Should get pool address correctly", async function () {
            const poolAddress = await poolManager.getPool(token0.address, token1.address, FEE);
            expect(poolAddress).to.equal(laxcePool.address);
        });
    });

    describe("Position Minting", function () {
        const mintParams = {
            token0: "",
            token1: "",
            fee: FEE,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            amount0Desired: ethers.utils.parseEther("100"),
            amount1Desired: ethers.utils.parseEther("100"),
            amount0Min: ethers.utils.parseEther("95"),
            amount1Min: ethers.utils.parseEther("95"),
            recipient: "",
            deadline: DEADLINE
        };

        beforeEach(function () {
            mintParams.token0 = token0.address;
            mintParams.token1 = token1.address;
            mintParams.recipient = addr1.address;
        });

        it("Should mint new position successfully", async function () {
            const mintTx = await poolManager.connect(addr1).mint(mintParams);

            await expect(mintTx)
                .to.emit(poolManager, "IncreaseLiquidity");

            // Check that position NFT was minted
            const balance = await positionNFT.balanceOf(addr1.address);
            expect(balance).to.equal(1);

            const tokenId = await positionNFT.tokenOfOwnerByIndex(addr1.address, 0);
            const position = await positionNFT.getPosition(tokenId);
            expect(position.token0).to.equal(token0.address);
            expect(position.token1).to.equal(token1.address);
            expect(position.fee).to.equal(FEE);
        });

        it("Should reject mint with insufficient amounts", async function () {
            const badParams = {
                ...mintParams,
                amount0Desired: 0,
                amount1Desired: 0
            };

            await expect(
                poolManager.connect(addr1).mint(badParams)
            ).to.be.revertedWith("PoolManager__InsufficientAmount");
        });

        it("Should reject mint with expired deadline", async function () {
            const expiredParams = {
                ...mintParams,
                deadline: Math.floor(Date.now() / 1000) - 3600 // 1 hour ago
            };

            await expect(
                poolManager.connect(addr1).mint(expiredParams)
            ).to.be.revertedWith("PoolManager__DeadlineExpired");
        });

        it("Should reject mint with invalid tick range", async function () {
            const invalidParams = {
                ...mintParams,
                tickLower: TICK_UPPER,
                tickUpper: TICK_LOWER // Reversed
            };

            await expect(
                poolManager.connect(addr1).mint(invalidParams)
            ).to.be.revertedWith("PoolManager__InvalidTickRange");
        });

        it("Should handle slippage protection", async function () {
            const highSlippageParams = {
                ...mintParams,
                amount0Min: ethers.utils.parseEther("150"), // More than desired
                amount1Min: ethers.utils.parseEther("150")
            };

            await expect(
                poolManager.connect(addr1).mint(highSlippageParams)
            ).to.be.revertedWith("PoolManager__TooMuchSlippage");
        });
    });

    describe("Liquidity Management", function () {
        let tokenId;

        beforeEach(async function () {
            // Mint a position first
            const mintParams = {
                token0: token0.address,
                token1: token1.address,
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: ethers.utils.parseEther("100"),
                amount1Desired: ethers.utils.parseEther("100"),
                amount0Min: ethers.utils.parseEther("95"),
                amount1Min: ethers.utils.parseEther("95"),
                recipient: addr1.address,
                deadline: DEADLINE
            };

            await poolManager.connect(addr1).mint(mintParams);
            tokenId = await positionNFT.tokenOfOwnerByIndex(addr1.address, 0);
        });

        it("Should increase liquidity successfully", async function () {
            const increaseParams = {
                tokenId: tokenId,
                amount0Desired: ethers.utils.parseEther("50"),
                amount1Desired: ethers.utils.parseEther("50"),
                amount0Min: ethers.utils.parseEther("45"),
                amount1Min: ethers.utils.parseEther("45"),
                deadline: DEADLINE
            };

            const increaseTx = await poolManager.connect(addr1).increaseLiquidity(increaseParams);

            await expect(increaseTx)
                .to.emit(poolManager, "IncreaseLiquidity")
                .withArgs(tokenId);
        });

        it("Should decrease liquidity successfully", async function () {
            const position = await positionNFT.getPosition(tokenId);
            const liquidityToRemove = position.liquidity.div(2);

            const decreaseParams = {
                tokenId: tokenId,
                liquidity: liquidityToRemove,
                amount0Min: 0,
                amount1Min: 0,
                deadline: DEADLINE
            };

            const decreaseTx = await poolManager.connect(addr1).decreaseLiquidity(decreaseParams);

            await expect(decreaseTx)
                .to.emit(poolManager, "DecreaseLiquidity")
                .withArgs(tokenId, liquidityToRemove);
        });

        it("Should collect fees successfully", async function () {
            // First, perform some swaps to generate fees
            const swapAmount = ethers.utils.parseEther("10");
            await token0.connect(addr2).approve(laxcePool.address, swapAmount);
            await laxcePool.connect(addr2).swap(
                addr2.address,
                true,
                swapAmount,
                "79228162514264337593543950336",
                "0x"
            );

            const collectParams = {
                tokenId: tokenId,
                recipient: addr1.address,
                amount0Max: ethers.constants.MaxUint128,
                amount1Max: ethers.constants.MaxUint128
            };

            const collectTx = await poolManager.connect(addr1).collect(collectParams);

            await expect(collectTx)
                .to.emit(poolManager, "Collect")
                .withArgs(tokenId, addr1.address);
        });

        it("Should burn position successfully", async function () {
            // First decrease all liquidity
            const position = await positionNFT.getPosition(tokenId);
            
            const decreaseParams = {
                tokenId: tokenId,
                liquidity: position.liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: DEADLINE
            };

            await poolManager.connect(addr1).decreaseLiquidity(decreaseParams);

            // Then collect remaining tokens
            const collectParams = {
                tokenId: tokenId,
                recipient: addr1.address,
                amount0Max: ethers.constants.MaxUint128,
                amount1Max: ethers.constants.MaxUint128
            };

            await poolManager.connect(addr1).collect(collectParams);

            // Finally burn the NFT
            await poolManager.connect(addr1).burn(tokenId);

            // Check that NFT was burned
            const balance = await positionNFT.balanceOf(addr1.address);
            expect(balance).to.equal(0);
        });

        it("Should reject operations on non-owned tokens", async function () {
            const increaseParams = {
                tokenId: tokenId,
                amount0Desired: ethers.utils.parseEther("50"),
                amount1Desired: ethers.utils.parseEther("50"),
                amount0Min: ethers.utils.parseEther("45"),
                amount1Min: ethers.utils.parseEther("45"),
                deadline: DEADLINE
            };

            await expect(
                poolManager.connect(addr2).increaseLiquidity(increaseParams)
            ).to.be.revertedWith("PoolManager__NotAuthorized");
        });
    });

    describe("Auto-Compounding", function () {
        let tokenId;

        beforeEach(async function () {
            // Enable auto-compound
            await poolManager.setAutoCompoundEnabled(true);

            // Mint a position
            const mintParams = {
                token0: token0.address,
                token1: token1.address,
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: ethers.utils.parseEther("1000"),
                amount1Desired: ethers.utils.parseEther("1000"),
                amount0Min: ethers.utils.parseEther("950"),
                amount1Min: ethers.utils.parseEther("950"),
                recipient: addr1.address,
                deadline: DEADLINE
            };

            await poolManager.connect(addr1).mint(mintParams);
            tokenId = await positionNFT.tokenOfOwnerByIndex(addr1.address, 0);
        });

        it("Should auto-compound fees successfully", async function () {
            // Generate fees through swaps
            for (let i = 0; i < 5; i++) {
                const swapAmount = ethers.utils.parseEther("50");
                await token0.connect(addr2).approve(laxcePool.address, swapAmount);
                await laxcePool.connect(addr2).swap(
                    addr2.address,
                    true,
                    swapAmount,
                    "79228162514264337593543950336",
                    "0x"
                );
            }

            const positionBefore = await positionNFT.getPosition(tokenId);
            
            const autoCompoundTx = await poolManager.autoCompound(tokenId);

            await expect(autoCompoundTx)
                .to.emit(poolManager, "AutoCompound")
                .withArgs(tokenId);

            const positionAfter = await positionNFT.getPosition(tokenId);
            expect(positionAfter.liquidity).to.be.gt(positionBefore.liquidity);
        });

        it("Should not auto-compound when disabled", async function () {
            await poolManager.setAutoCompoundEnabled(false);

            await expect(
                poolManager.autoCompound(tokenId)
            ).to.be.revertedWith("PoolManager__AutoCompoundDisabled");
        });

        it("Should not auto-compound below minimum liquidity", async function () {
            await poolManager.setMinLiquidityForAutoCompound(ethers.utils.parseEther("10000"));

            await expect(
                poolManager.autoCompound(tokenId)
            ).to.be.revertedWith("PoolManager__InsufficientLiquidityForAutoCompound");
        });
    });

    describe("Configuration Management", function () {
        it("Should set default slippage", async function () {
            const newSlippage = 1000; // 10%

            await poolManager.setDefaultSlippage(newSlippage);

            expect(await poolManager.defaultSlippage()).to.equal(newSlippage);

            await expect(poolManager.setDefaultSlippage(newSlippage))
                .to.emit(poolManager, "SlippageUpdated")
                .withArgs(newSlippage);
        });

        it("Should reject invalid slippage values", async function () {
            await expect(
                poolManager.setDefaultSlippage(0)
            ).to.be.revertedWith("PoolManager__InvalidSlippage");

            await expect(
                poolManager.setDefaultSlippage(5001) // > MAX_SLIPPAGE
            ).to.be.revertedWith("PoolManager__InvalidSlippage");
        });

        it("Should toggle auto-compound", async function () {
            await poolManager.setAutoCompoundEnabled(true);
            expect(await poolManager.autoCompoundEnabled()).to.be.true;

            await expect(poolManager.setAutoCompoundEnabled(true))
                .to.emit(poolManager, "AutoCompoundToggled")
                .withArgs(true);

            await poolManager.setAutoCompoundEnabled(false);
            expect(await poolManager.autoCompoundEnabled()).to.be.false;
        });

        it("Should set minimum liquidity for auto-compound", async function () {
            const newMin = ethers.utils.parseEther("500");

            await poolManager.setMinLiquidityForAutoCompound(newMin);

            expect(await poolManager.minLiquidityForAutoCompound()).to.equal(newMin);
        });

        it("Should set fee collector", async function () {
            const newCollector = addr2.address;

            await poolManager.setFeeCollector(token0.address, newCollector);

            expect(await poolManager.feeCollectors(token0.address)).to.equal(newCollector);

            await expect(poolManager.setFeeCollector(token0.address, newCollector))
                .to.emit(poolManager, "FeeCollectorSet")
                .withArgs(token0.address, newCollector);
        });
    });

    describe("Pool Callbacks", function () {
        it("Should handle mint callback correctly", async function () {
            const amount0 = ethers.utils.parseEther("100");
            const amount1 = ethers.utils.parseEther("100");

            // This would be called by the pool during a mint operation
            await expect(
                poolManager.laxcePoolMintCallback(amount0, amount1, "0x")
            ).to.not.be.reverted;
        });

        it("Should reject callbacks from non-pool addresses", async function () {
            const amount0 = ethers.utils.parseEther("100");
            const amount1 = ethers.utils.parseEther("100");

            await expect(
                poolManager.connect(addr1).laxcePoolMintCallback(amount0, amount1, "0x")
            ).to.be.revertedWith("PoolManager__InvalidCaller");
        });
    });

    describe("Access Control & Security", function () {
        it("Should pause and unpause correctly", async function () {
            await poolManager.pause();
            expect(await poolManager.paused()).to.be.true;

            const mintParams = {
                token0: token0.address,
                token1: token1.address,
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: ethers.utils.parseEther("100"),
                amount1Desired: ethers.utils.parseEther("100"),
                amount0Min: ethers.utils.parseEther("95"),
                amount1Min: ethers.utils.parseEther("95"),
                recipient: addr1.address,
                deadline: DEADLINE
            };

            await expect(
                poolManager.connect(addr1).mint(mintParams)
            ).to.be.revertedWith("Pausable: paused");

            await poolManager.unpause();
            expect(await poolManager.paused()).to.be.false;
        });

        it("Should reject unauthorized configuration changes", async function () {
            await expect(
                poolManager.connect(addr1).setDefaultSlippage(1000)
            ).to.be.revertedWith("AccessControl:");

            await expect(
                poolManager.connect(addr1).setAutoCompoundEnabled(true)
            ).to.be.revertedWith("AccessControl:");

            await expect(
                poolManager.connect(addr1).pause()
            ).to.be.revertedWith("AccessControl:");
        });

        it("Should validate position ownership", async function () {
            const mintParams = {
                token0: token0.address,
                token1: token1.address,
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: ethers.utils.parseEther("100"),
                amount1Desired: ethers.utils.parseEther("100"),
                amount0Min: ethers.utils.parseEther("95"),
                amount1Min: ethers.utils.parseEther("95"),
                recipient: addr1.address,
                deadline: DEADLINE
            };

            await poolManager.connect(addr1).mint(mintParams);
            const tokenId = await positionNFT.tokenOfOwnerByIndex(addr1.address, 0);

            // Should allow owner to operate
            expect(await poolManager.isApprovedOrOwner(addr1.address, tokenId)).to.be.true;

            // Should reject non-owner
            expect(await poolManager.isApprovedOrOwner(addr2.address, tokenId)).to.be.false;
        });
    });

    describe("Edge Cases & Error Handling", function () {
        it("Should handle WETH operations correctly", async function () {
            // Test WETH deposit and withdraw functionality
            const amount = ethers.utils.parseEther("1");
            
            await weth9.connect(addr1).deposit({ value: amount });
            expect(await weth9.balanceOf(addr1.address)).to.equal(amount);
            
            await weth9.connect(addr1).withdraw(amount);
            expect(await weth9.balanceOf(addr1.address)).to.equal(0);
        });

        it("Should handle pool caching correctly", async function () {
            // Get pool multiple times to test caching
            const pool1 = await poolManager.getPool(token0.address, token1.address, FEE);
            const pool2 = await poolManager.getPool(token0.address, token1.address, FEE);
            
            expect(pool1).to.equal(pool2);
            expect(pool1).to.equal(laxcePool.address);
        });

        it("Should revert on non-existent pools", async function () {
            const nonExistentFee = 12345;
            
            await expect(
                poolManager.getPool(token0.address, token1.address, nonExistentFee)
            ).to.be.revertedWith("PoolManager__PoolNotFound");
        });

        it("Should handle large liquidity amounts", async function () {
            const largeAmount = ethers.utils.parseEther("1000000");
            
            // Mint large amounts to test account
            await token0.mint(addr1.address, largeAmount);
            await token1.mint(addr1.address, largeAmount);
            await token0.connect(addr1).approve(poolManager.address, largeAmount);
            await token1.connect(addr1).approve(poolManager.address, largeAmount);

            const mintParams = {
                token0: token0.address,
                token1: token1.address,
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: largeAmount,
                amount1Desired: largeAmount,
                amount0Min: largeAmount.mul(95).div(100),
                amount1Min: largeAmount.mul(95).div(100),
                recipient: addr1.address,
                deadline: DEADLINE
            };

            await expect(
                poolManager.connect(addr1).mint(mintParams)
            ).to.not.be.reverted;
        });
    });

    describe("Integration Tests", function () {
        it("Should handle complete liquidity lifecycle", async function () {
            // 1. Mint position
            const mintParams = {
                token0: token0.address,
                token1: token1.address,
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: ethers.utils.parseEther("100"),
                amount1Desired: ethers.utils.parseEther("100"),
                amount0Min: ethers.utils.parseEther("95"),
                amount1Min: ethers.utils.parseEther("95"),
                recipient: addr1.address,
                deadline: DEADLINE
            };

            await poolManager.connect(addr1).mint(mintParams);
            const tokenId = await positionNFT.tokenOfOwnerByIndex(addr1.address, 0);

            // 2. Increase liquidity
            const increaseParams = {
                tokenId: tokenId,
                amount0Desired: ethers.utils.parseEther("50"),
                amount1Desired: ethers.utils.parseEther("50"),
                amount0Min: ethers.utils.parseEther("45"),
                amount1Min: ethers.utils.parseEther("45"),
                deadline: DEADLINE
            };

            await poolManager.connect(addr1).increaseLiquidity(increaseParams);

            // 3. Generate fees through swaps
            const swapAmount = ethers.utils.parseEther("10");
            await token0.connect(addr2).approve(laxcePool.address, swapAmount);
            await laxcePool.connect(addr2).swap(
                addr2.address,
                true,
                swapAmount,
                "79228162514264337593543950336",
                "0x"
            );

            // 4. Collect fees
            const collectParams = {
                tokenId: tokenId,
                recipient: addr1.address,
                amount0Max: ethers.constants.MaxUint128,
                amount1Max: ethers.constants.MaxUint128
            };

            await poolManager.connect(addr1).collect(collectParams);

            // 5. Decrease liquidity
            const position = await positionNFT.getPosition(tokenId);
            const decreaseParams = {
                tokenId: tokenId,
                liquidity: position.liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: DEADLINE
            };

            await poolManager.connect(addr1).decreaseLiquidity(decreaseParams);

            // 6. Final collect and burn
            await poolManager.connect(addr1).collect(collectParams);
            await poolManager.connect(addr1).burn(tokenId);

            expect(await positionNFT.balanceOf(addr1.address)).to.equal(0);
        });
    });
});

// Mock WETH9 contract for testing
contract MockWETH9 {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf[msg.sender] >= wad, "Insufficient balance");
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
        require(balanceOf[src] >= wad, "Insufficient balance");

        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad, "Insufficient allowance");
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        return true;
    }
} 