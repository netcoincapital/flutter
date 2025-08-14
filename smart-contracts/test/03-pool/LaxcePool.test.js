const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("LaxcePool", function () {
    let owner, addr1, addr2, addr3;
    let laxcePool, factory, token0, token1, lpToken, positionNFT;
    let accessControl, tokenRegistry;

    const TICK_SPACING = 60;
    const FEE = 3000; // 0.3%
    const MINIMUM_LIQUIDITY = 1000;
    const INITIAL_PRICE = "79228162514264337593543950336"; // sqrt(1) in Q96

    async function deployPoolFixture() {
        [owner, addr1, addr2, addr3] = await ethers.getSigners();

        // Deploy AccessControl
        const AccessControl = await ethers.getContractFactory("LaxceAccessControl");
        accessControl = await AccessControl.deploy(
            owner.address, // treasury
            owner.address, // teamWallet
            owner.address  // marketingWallet
        );

        // Deploy Mock ERC20 tokens
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        let tokenA = await MockERC20.deploy("Token A", "TKNA", 18);
        let tokenB = await MockERC20.deploy("Token B", "TKNB", 18);

        // Ensure token0 < token1 for pool creation
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

        // Deploy LPToken
        const LPToken = await ethers.getContractFactory("LPToken");
        lpToken = await LPToken.deploy(
            token0.address,
            token1.address,
            FEE,
            owner.address, // laxceToken placeholder
            owner.address, // factory placeholder
            owner.address, // router placeholder
            accessControl.address
        );

        // Deploy PoolFactory
        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        factory = await PoolFactory.deploy(tokenRegistry.address);

        // Deploy LaxcePool
        const LaxcePool = await ethers.getContractFactory("LaxcePool");
        laxcePool = await LaxcePool.deploy();

        // Initialize pool
        await laxcePool.initialize(
            factory.address,
            token0.address,
            token1.address,
            FEE,
            TICK_SPACING,
            lpToken.address,
            positionNFT.address,
            INITIAL_PRICE
        );

        // Mint tokens to test accounts
        const mintAmount = ethers.utils.parseEther("1000000");
        await token0.mint(owner.address, mintAmount);
        await token0.mint(addr1.address, mintAmount);
        await token0.mint(addr2.address, mintAmount);
        
        await token1.mint(owner.address, mintAmount);
        await token1.mint(addr1.address, mintAmount);
        await token1.mint(addr2.address, mintAmount);

        // Approve pool for token transfers
        await token0.connect(owner).approve(laxcePool.address, mintAmount);
        await token0.connect(addr1).approve(laxcePool.address, mintAmount);
        await token0.connect(addr2).approve(laxcePool.address, mintAmount);
        
        await token1.connect(owner).approve(laxcePool.address, mintAmount);
        await token1.connect(addr1).approve(laxcePool.address, mintAmount);
        await token1.connect(addr2).approve(laxcePool.address, mintAmount);

        return {
            laxcePool,
            factory,
            token0,
            token1,
            lpToken,
            positionNFT,
            accessControl,
            tokenRegistry,
            owner,
            addr1,
            addr2,
            addr3
        };
    }

    beforeEach(async function () {
        const fixture = await loadFixture(deployPoolFixture);
        Object.assign(this, fixture);
        ({
            laxcePool,
            factory,
            token0,
            token1,
            lpToken,
            positionNFT,
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
            expect(await laxcePool.factory()).to.equal(factory.address);
            expect(await laxcePool.token0()).to.equal(token0.address);
            expect(await laxcePool.token1()).to.equal(token1.address);
            expect(await laxcePool.fee()).to.equal(FEE);
            expect(await laxcePool.tickSpacing()).to.equal(TICK_SPACING);
        });

        it("Should not allow re-initialization", async function () {
            await expect(
                laxcePool.initialize(
                    factory.address,
                    token0.address,
                    token1.address,
                    FEE,
                    TICK_SPACING,
                    lpToken.address,
                    positionNFT.address,
                    INITIAL_PRICE
                )
            ).to.be.revertedWith("Pool__AlreadyInitialized");
        });

        it("Should have correct initial state", async function () {
            const slot0 = await laxcePool.slot0();
            expect(slot0.sqrtPriceX96).to.equal(INITIAL_PRICE);
            expect(slot0.tick).to.equal(0);
            expect(slot0.observationIndex).to.equal(0);
            expect(slot0.observationCardinality).to.equal(1);
            expect(slot0.observationCardinalityNext).to.equal(1);
            expect(slot0.feeProtocol).to.equal(0);
            expect(slot0.unlocked).to.equal(true);
        });
    });

    describe("Liquidity Management", function () {
        const tickLower = -60;
        const tickUpper = 60;
        const amount0 = ethers.utils.parseEther("100");
        const amount1 = ethers.utils.parseEther("100");

        it("Should mint liquidity successfully", async function () {
            const mintTx = await laxcePool.connect(addr1).mint(
                addr1.address,
                tickLower,
                tickUpper,
                amount0,
                amount1
            );

            await expect(mintTx)
                .to.emit(laxcePool, "Mint")
                .withArgs(addr1.address, addr1.address, tickLower, tickUpper);

            const position = await laxcePool.positions(
                ethers.utils.keccak256(
                    ethers.utils.defaultAbiCoder.encode(
                        ["address", "int24", "int24"],
                        [addr1.address, tickLower, tickUpper]
                    )
                )
            );

            expect(position.liquidity).to.be.gt(0);
        });

        it("Should burn liquidity successfully", async function () {
            // First mint liquidity
            await laxcePool.connect(addr1).mint(
                addr1.address,
                tickLower,
                tickUpper,
                amount0,
                amount1
            );

            const positionKey = ethers.utils.keccak256(
                ethers.utils.defaultAbiCoder.encode(
                    ["address", "int24", "int24"],
                    [addr1.address, tickLower, tickUpper]
                )
            );

            const position = await laxcePool.positions(positionKey);
            const liquidityToBurn = position.liquidity.div(2);

            const burnTx = await laxcePool.connect(addr1).burn(
                tickLower,
                tickUpper,
                liquidityToBurn
            );

            await expect(burnTx)
                .to.emit(laxcePool, "Burn")
                .withArgs(addr1.address, tickLower, tickUpper, liquidityToBurn);
        });

        it("Should collect fees successfully", async function () {
            // First mint liquidity
            await laxcePool.connect(addr1).mint(
                addr1.address,
                tickLower,
                tickUpper,
                amount0,
                amount1
            );

            // Perform some swaps to generate fees
            const swapAmount = ethers.utils.parseEther("10");
            await laxcePool.connect(addr2).swap(
                addr2.address,
                true, // zeroForOne
                swapAmount,
                "79228162514264337593543950336", // sqrtPriceLimitX96
                "0x" // data
            );

            // Collect fees
            const collectTx = await laxcePool.connect(addr1).collect(
                addr1.address,
                tickLower,
                tickUpper,
                ethers.constants.MaxUint128,
                ethers.constants.MaxUint128
            );

            await expect(collectTx).to.emit(laxcePool, "Collect");
        });

        it("Should reject invalid tick ranges", async function () {
            const invalidTickLower = -887273; // Below MIN_TICK
            const invalidTickUpper = 887273;  // Above MAX_TICK

            await expect(
                laxcePool.connect(addr1).mint(
                    addr1.address,
                    invalidTickLower,
                    tickUpper,
                    amount0,
                    amount1
                )
            ).to.be.revertedWith("Pool__TickNotSpaced");

            await expect(
                laxcePool.connect(addr1).mint(
                    addr1.address,
                    tickLower,
                    invalidTickUpper,
                    amount0,
                    amount1
                )
            ).to.be.revertedWith("Pool__TickNotSpaced");
        });

        it("Should reject invalid liquidity amounts", async function () {
            await expect(
                laxcePool.connect(addr1).mint(
                    addr1.address,
                    tickLower,
                    tickUpper,
                    0,
                    0
                )
            ).to.be.revertedWith("Pool__InsufficientLiquidity");
        });
    });

    describe("Swapping", function () {
        const tickLower = -120;
        const tickUpper = 120;
        const liquidityAmount0 = ethers.utils.parseEther("1000");
        const liquidityAmount1 = ethers.utils.parseEther("1000");

        beforeEach(async function () {
            // Add liquidity for swapping
            await laxcePool.connect(addr1).mint(
                addr1.address,
                tickLower,
                tickUpper,
                liquidityAmount0,
                liquidityAmount1
            );
        });

        it("Should execute swap token0 for token1", async function () {
            const swapAmount = ethers.utils.parseEther("10");
            const balanceBefore0 = await token0.balanceOf(addr2.address);
            const balanceBefore1 = await token1.balanceOf(addr2.address);

            const swapTx = await laxcePool.connect(addr2).swap(
                addr2.address,
                true, // zeroForOne
                swapAmount,
                "4295128739", // min sqrtPriceX96
                "0x"
            );

            await expect(swapTx).to.emit(laxcePool, "Swap");

            const balanceAfter0 = await token0.balanceOf(addr2.address);
            const balanceAfter1 = await token1.balanceOf(addr2.address);

            expect(balanceBefore0.sub(balanceAfter0)).to.equal(swapAmount);
            expect(balanceAfter1).to.be.gt(balanceBefore1);
        });

        it("Should execute swap token1 for token0", async function () {
            const swapAmount = ethers.utils.parseEther("10");
            const balanceBefore0 = await token0.balanceOf(addr2.address);
            const balanceBefore1 = await token1.balanceOf(addr2.address);

            const swapTx = await laxcePool.connect(addr2).swap(
                addr2.address,
                false, // oneForZero
                swapAmount,
                "1461446703485210103287273052203988822378723970341", // max sqrtPriceX96
                "0x"
            );

            await expect(swapTx).to.emit(laxcePool, "Swap");

            const balanceAfter0 = await token0.balanceOf(addr2.address);
            const balanceAfter1 = await token1.balanceOf(addr2.address);

            expect(balanceAfter0).to.be.gt(balanceBefore0);
            expect(balanceBefore1.sub(balanceAfter1)).to.equal(swapAmount);
        });

        it("Should reject swaps with zero amount", async function () {
            await expect(
                laxcePool.connect(addr2).swap(
                    addr2.address,
                    true,
                    0,
                    "4295128739",
                    "0x"
                )
            ).to.be.revertedWith("Pool__ZeroAmount");
        });

        it("Should reject swaps exceeding price limits", async function () {
            const swapAmount = ethers.utils.parseEther("10");
            
            await expect(
                laxcePool.connect(addr2).swap(
                    addr2.address,
                    true,
                    swapAmount,
                    "1461446703485210103287273052203988822378723970341", // wrong direction limit
                    "0x"
                )
            ).to.be.revertedWith("Pool__InvalidPriceLimit");
        });
    });

    describe("Flash Loans", function () {
        const tickLower = -120;
        const tickUpper = 120;
        const liquidityAmount0 = ethers.utils.parseEther("1000");
        const liquidityAmount1 = ethers.utils.parseEther("1000");

        beforeEach(async function () {
            // Add liquidity for flash loans
            await laxcePool.connect(addr1).mint(
                addr1.address,
                tickLower,
                tickUpper,
                liquidityAmount0,
                liquidityAmount1
            );
        });

        it("Should execute flash loan successfully", async function () {
            const flashAmount0 = ethers.utils.parseEther("100");
            const flashAmount1 = ethers.utils.parseEther("100");

            // Deploy a mock flash loan receiver for testing
            const MockFlashLoanReceiver = await ethers.getContractFactory("MockFlashLoanReceiver");
            const receiver = await MockFlashLoanReceiver.deploy();

            // Fund the receiver with tokens to pay fees
            await token0.transfer(receiver.address, ethers.utils.parseEther("10"));
            await token1.transfer(receiver.address, ethers.utils.parseEther("10"));

            const flashTx = await laxcePool.flash(
                receiver.address,
                flashAmount0,
                flashAmount1,
                "0x"
            );

            await expect(flashTx).to.emit(laxcePool, "Flash");
        });

        it("Should reject flash loans with insufficient callback payment", async function () {
            const flashAmount0 = ethers.utils.parseEther("100");
            const flashAmount1 = ethers.utils.parseEther("100");

            // Deploy a mock flash loan receiver that doesn't pay
            const MockBadFlashLoanReceiver = await ethers.getContractFactory("MockBadFlashLoanReceiver");
            const badReceiver = await MockBadFlashLoanReceiver.deploy();

            await expect(
                laxcePool.flash(
                    badReceiver.address,
                    flashAmount0,
                    flashAmount1,
                    "0x"
                )
            ).to.be.revertedWith("Pool__FlashLoanNotPaid");
        });
    });

    describe("Observations & Oracle", function () {
        it("Should increase observation cardinality", async function () {
            const newCardinality = 10;
            
            await laxcePool.increaseObservationCardinalityNext(newCardinality);
            
            const slot0 = await laxcePool.slot0();
            expect(slot0.observationCardinalityNext).to.equal(newCardinality);
        });

        it("Should not allow non-authorized cardinality increase", async function () {
            const newCardinality = 10;
            
            await expect(
                laxcePool.connect(addr1).increaseObservationCardinalityNext(newCardinality)
            ).to.be.revertedWith("AccessControl:");
        });

        it("Should maintain observation history during swaps", async function () {
            // Add liquidity
            await laxcePool.connect(addr1).mint(
                addr1.address,
                -120,
                120,
                ethers.utils.parseEther("1000"),
                ethers.utils.parseEther("1000")
            );

            // Increase cardinality
            await laxcePool.increaseObservationCardinalityNext(5);

            // Perform swaps to create observations
            for (let i = 0; i < 3; i++) {
                await laxcePool.connect(addr2).swap(
                    addr2.address,
                    i % 2 === 0,
                    ethers.utils.parseEther("10"),
                    i % 2 === 0 ? "4295128739" : "1461446703485210103287273052203988822378723970341",
                    "0x"
                );
                
                // Wait for next block
                await ethers.provider.send("evm_mine");
            }

            const slot0 = await laxcePool.slot0();
            expect(slot0.observationIndex).to.be.gt(0);
        });
    });

    describe("Access Control & Security", function () {
        it("Should allow only authorized users to set fee protocol", async function () {
            await laxcePool.setFeeProtocol(4, 4);
            
            const slot0 = await laxcePool.slot0();
            expect(slot0.feeProtocol).to.equal(68); // 4 << 4 | 4
        });

        it("Should reject unauthorized fee protocol changes", async function () {
            await expect(
                laxcePool.connect(addr1).setFeeProtocol(4, 4)
            ).to.be.revertedWith("AccessControl:");
        });

        it("Should allow protocol fee collection", async function () {
            // Set protocol fee
            await laxcePool.setFeeProtocol(4, 4);
            
            // Add liquidity and perform swaps to generate fees
            await laxcePool.connect(addr1).mint(
                addr1.address,
                -120,
                120,
                ethers.utils.parseEther("1000"),
                ethers.utils.parseEther("1000")
            );

            for (let i = 0; i < 5; i++) {
                await laxcePool.connect(addr2).swap(
                    addr2.address,
                    i % 2 === 0,
                    ethers.utils.parseEther("10"),
                    i % 2 === 0 ? "4295128739" : "1461446703485210103287273052203988822378723970341",
                    "0x"
                );
            }

            // Collect protocol fees
            const collectTx = await laxcePool.collectProtocol(
                owner.address,
                ethers.constants.MaxUint128,
                ethers.constants.MaxUint128
            );

            await expect(collectTx).to.emit(laxcePool, "CollectProtocol");
        });

        it("Should pause and unpause correctly", async function () {
            await laxcePool.pause();
            expect(await laxcePool.paused()).to.be.true;

            // Should reject operations when paused
            await expect(
                laxcePool.connect(addr1).mint(
                    addr1.address,
                    -60,
                    60,
                    ethers.utils.parseEther("100"),
                    ethers.utils.parseEther("100")
                )
            ).to.be.revertedWith("Pausable: paused");

            await laxcePool.unpause();
            expect(await laxcePool.paused()).to.be.false;
        });
    });

    describe("Edge Cases & Error Handling", function () {
        it("Should handle minimum liquidity correctly", async function () {
            const minAmount = MINIMUM_LIQUIDITY.toString();
            
            await expect(
                laxcePool.connect(addr1).mint(
                    addr1.address,
                    -60,
                    60,
                    minAmount,
                    minAmount
                )
            ).to.not.be.reverted;
        });

        it("Should reject operations on uninitialized pool", async function () {
            // Deploy new uninitialized pool
            const LaxcePool = await ethers.getContractFactory("LaxcePool");
            const uninitializedPool = await LaxcePool.deploy();

            await expect(
                uninitializedPool.connect(addr1).mint(
                    addr1.address,
                    -60,
                    60,
                    ethers.utils.parseEther("100"),
                    ethers.utils.parseEther("100")
                )
            ).to.be.revertedWith("Pool__NotInitialized");
        });

        it("Should handle large liquidity amounts", async function () {
            const largeAmount = ethers.utils.parseEther("1000000");
            
            await expect(
                laxcePool.connect(addr1).mint(
                    addr1.address,
                    -120,
                    120,
                    largeAmount,
                    largeAmount
                )
            ).to.not.be.reverted;
        });
    });

    describe("View Functions", function () {
        beforeEach(async function () {
            // Add some liquidity for testing view functions
            await laxcePool.connect(addr1).mint(
                addr1.address,
                -120,
                120,
                ethers.utils.parseEther("1000"),
                ethers.utils.parseEther("1000")
            );
        });

        it("Should return correct pool balance", async function () {
            const balance0 = await laxcePool.balance0();
            const balance1 = await laxcePool.balance1();

            expect(balance0).to.be.gt(0);
            expect(balance1).to.be.gt(0);
        });

        it("Should return correct tick info", async function () {
            const tickInfo = await laxcePool.ticks(-120);
            expect(tickInfo.liquidityGross).to.be.gt(0);
        });

        it("Should return correct position info", async function () {
            const positionKey = ethers.utils.keccak256(
                ethers.utils.defaultAbiCoder.encode(
                    ["address", "int24", "int24"],
                    [addr1.address, -120, 120]
                )
            );
            
            const position = await laxcePool.positions(positionKey);
            expect(position.liquidity).to.be.gt(0);
        });
    });
});

// Mock contracts for testing
// These would typically be in separate files

contract MockERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) {
        // Implementation here
    }
    
    function mint(address to, uint256 amount) external {
        // Implementation here
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        // Implementation here
    }
    
    function balanceOf(address account) external view returns (uint256) {
        // Implementation here
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        // Implementation here
    }
}

contract MockFlashLoanReceiver {
    function laxcePoolFlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external {
        // Pay back the flash loan with fees
        // Implementation here
    }
}

contract MockBadFlashLoanReceiver {
    function laxcePoolFlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external {
        // Intentionally don't pay back
    }
} 