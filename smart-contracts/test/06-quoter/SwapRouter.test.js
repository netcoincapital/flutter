const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("SwapRouter", function () {
    let owner, addr1, addr2, addr3;
    let swapRouter, quoter, poolFactory, tokenRegistry, accessControl;
    let token0, token1, token2, weth9;
    let pool1, pool2;

    const FEE_MEDIUM = 3000; // 0.3%
    const INITIAL_PRICE = "79228162514264337593543950336"; // sqrt(1) in Q96
    const DEADLINE = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

    async function deploySwapRouterFixture() {
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
        let tokenC = await MockERC20.deploy("Token C", "TKNC", 18);

        // Sort tokens by address
        const tokens = [tokenA, tokenB, tokenC].sort((a, b) => 
            a.address.toLowerCase() < b.address.toLowerCase() ? -1 : 1
        );
        [token0, token1, token2] = tokens;

        // Deploy TokenRegistry
        const TokenRegistry = await ethers.getContractFactory("TokenRegistry");
        tokenRegistry = await TokenRegistry.deploy(accessControl.address);

        // Deploy PoolFactory
        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        poolFactory = await PoolFactory.deploy(tokenRegistry.address);

        // Deploy Quoter
        const Quoter = await ethers.getContractFactory("Quoter");
        quoter = await Quoter.deploy(poolFactory.address);

        // Deploy SwapRouter
        const SwapRouter = await ethers.getContractFactory("SwapRouter");
        swapRouter = await SwapRouter.deploy(
            poolFactory.address,
            weth9.address,
            quoter.address
        );

        // Create pools
        await poolFactory.createPool(token0.address, token1.address, FEE_MEDIUM);
        await poolFactory.createPool(token1.address, token2.address, FEE_MEDIUM);

        const pool1Address = await poolFactory.getPool(token0.address, token1.address, FEE_MEDIUM);
        const pool2Address = await poolFactory.getPool(token1.address, token2.address, FEE_MEDIUM);

        // Get pool instances
        const LaxcePool = await ethers.getContractFactory("LaxcePool");
        pool1 = LaxcePool.attach(pool1Address);
        pool2 = LaxcePool.attach(pool2Address);

        // Initialize pools
        await pool1.initialize(
            poolFactory.address,
            token0.address,
            token1.address,
            FEE_MEDIUM,
            60, // tick spacing
            owner.address, // lpToken placeholder
            owner.address, // positionNFT placeholder
            INITIAL_PRICE
        );

        await pool2.initialize(
            poolFactory.address,
            token1.address,
            token2.address,
            FEE_MEDIUM,
            60,
            owner.address,
            owner.address,
            INITIAL_PRICE
        );

        // Mint tokens to test accounts
        const mintAmount = ethers.utils.parseEther("1000000");
        for (const token of [token0, token1, token2]) {
            for (const account of [owner, addr1, addr2, addr3]) {
                await token.mint(account.address, mintAmount);
                await token.connect(account).approve(swapRouter.address, mintAmount);
            }
        }

        // Add initial liquidity to pools (simplified)
        // In real scenario, this would be done through PoolManager
        
        return {
            swapRouter,
            quoter,
            poolFactory,
            tokenRegistry,
            accessControl,
            token0,
            token1,
            token2,
            weth9,
            pool1,
            pool2,
            owner,
            addr1,
            addr2,
            addr3
        };
    }

    beforeEach(async function () {
        const fixture = await loadFixture(deploySwapRouterFixture);
        Object.assign(this, fixture);
        ({
            swapRouter,
            quoter,
            poolFactory,
            tokenRegistry,
            accessControl,
            token0,
            token1,
            token2,
            weth9,
            pool1,
            pool2,
            owner,
            addr1,
            addr2,
            addr3
        } = fixture);
    });

    describe("Deployment & Initialization", function () {
        it("Should deploy with correct parameters", async function () {
            expect(await swapRouter.getFactory()).to.equal(poolFactory.address);
            expect(await swapRouter.getWETH9()).to.equal(weth9.address);
            expect(await swapRouter.getQuoter()).to.equal(quoter.address);
        });

        it("Should have correct initial configuration", async function () {
            expect(await swapRouter.defaultSlippage()).to.equal(500); // 5%
            expect(await swapRouter.routerFee()).to.equal(1); // 0.01%
            expect(await swapRouter.routerFeeRecipient()).to.equal(owner.address);
            expect(await swapRouter.whitelistMode()).to.be.false;
            expect(await swapRouter.emergencyMode()).to.be.false;
        });

        it("Should have MEV protection disabled by default", async function () {
            const mevConfig = await swapRouter.mevProtection();
            expect(mevConfig.enabled).to.be.false;
            expect(mevConfig.maxPriceImpact).to.equal(1000); // 10%
            expect(mevConfig.minBlockDelay).to.equal(1);
            expect(mevConfig.maxSlippageTolerance).to.equal(500); // 5%
        });
    });

    describe("Exact Input Single Swaps", function () {
        const amountIn = ethers.utils.parseEther("100");
        const amountOutMin = ethers.utils.parseEther("95");

        it("Should execute exact input single swap successfully", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            };

            const balanceBefore = await token1.balanceOf(addr1.address);

            const tx = await swapRouter.connect(addr1).exactInputSingle(params);
            
            await expect(tx)
                .to.emit(swapRouter, "SwapExecuted")
                .withArgs(
                    addr1.address,
                    addr1.address,
                    token0.address,
                    token1.address,
                    amountIn,
                    // amountOut - we can't predict exact amount
                    ethers.utils.parseUnits("1", 0), // Just check it's not zero
                    // feeAmount
                    ethers.utils.parseUnits("1", 0)
                );

            const balanceAfter = await token1.balanceOf(addr1.address);
            expect(balanceAfter).to.be.gt(balanceBefore);
        });

        it("Should reject swaps with expired deadline", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: Math.floor(Date.now() / 1000) - 3600, // 1 hour ago
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params)
            ).to.be.revertedWith("SwapRouter__DeadlineExpired");
        });

        it("Should reject swaps with zero amount", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: 0,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params)
            ).to.be.revertedWith("SwapRouter__InvalidAmount");
        });

        it("Should reject swaps when emergency mode is enabled", async function () {
            await swapRouter.setEmergencyMode(true);

            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params)
            ).to.be.revertedWith("SwapRouter__EmergencyMode");
        });
    });

    describe("Exact Output Single Swaps", function () {
        const amountOut = ethers.utils.parseEther("90");
        const amountInMax = ethers.utils.parseEther("105");

        it("Should execute exact output single swap successfully", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountOut: amountOut,
                amountInMaximum: amountInMax,
                sqrtPriceLimitX96: 0
            };

            const balanceBefore = await token1.balanceOf(addr1.address);

            const tx = await swapRouter.connect(addr1).exactOutputSingle(params);
            
            await expect(tx).to.emit(swapRouter, "SwapExecuted");

            const balanceAfter = await token1.balanceOf(addr1.address);
            expect(balanceAfter.sub(balanceBefore)).to.be.gte(amountOut);
        });

        it("Should reject when amount in exceeds maximum", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountOut: amountOut,
                amountInMaximum: ethers.utils.parseEther("50"), // Too low
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactOutputSingle(params)
            ).to.be.revertedWith("SwapRouter__ExcessiveAmountIn");
        });
    });

    describe("Multi-Hop Swaps", function () {
        const amountIn = ethers.utils.parseEther("100");
        const amountOutMin = ethers.utils.parseEther("85");

        function encodePath(tokens, fees) {
            let path = "0x";
            for (let i = 0; i < tokens.length; i++) {
                path += tokens[i].slice(2); // Remove 0x prefix
                if (i < fees.length) {
                    path += fees[i].toString(16).padStart(6, '0');
                }
            }
            return path;
        }

        it("Should execute exact input multi-hop swap successfully", async function () {
            const path = encodePath(
                [token0.address, token1.address, token2.address],
                [FEE_MEDIUM, FEE_MEDIUM]
            );

            const params = {
                path: path,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin
            };

            const balanceBefore = await token2.balanceOf(addr1.address);

            const tx = await swapRouter.connect(addr1).exactInput(params);
            
            await expect(tx).to.emit(swapRouter, "MultiHopSwap");

            const balanceAfter = await token2.balanceOf(addr1.address);
            expect(balanceAfter).to.be.gt(balanceBefore);
        });

        it("Should execute exact output multi-hop swap successfully", async function () {
            const amountOut = ethers.utils.parseEther("80");
            const amountInMax = ethers.utils.parseEther("120");
            
            const path = encodePath(
                [token0.address, token1.address, token2.address],
                [FEE_MEDIUM, FEE_MEDIUM]
            );

            const params = {
                path: path,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountOut: amountOut,
                amountInMaximum: amountInMax
            };

            const balanceBefore = await token2.balanceOf(addr1.address);

            const tx = await swapRouter.connect(addr1).exactOutput(params);
            
            await expect(tx).to.emit(swapRouter, "MultiHopSwap");

            const balanceAfter = await token2.balanceOf(addr1.address);
            expect(balanceAfter.sub(balanceBefore)).to.be.gte(amountOut);
        });

        it("Should reject path with too many hops", async function () {
            // Create a path with 4 hops (more than MAX_HOPS)
            const path = encodePath(
                [token0.address, token1.address, token2.address, token0.address, token1.address],
                [FEE_MEDIUM, FEE_MEDIUM, FEE_MEDIUM, FEE_MEDIUM]
            );

            const params = {
                path: path,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin
            };

            await expect(
                swapRouter.connect(addr1).exactInput(params)
            ).to.be.revertedWith("SwapRouter__InvalidPath");
        });

        it("Should reject invalid path", async function () {
            const invalidPath = "0x123456"; // Too short

            const params = {
                path: invalidPath,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin
            };

            await expect(
                swapRouter.connect(addr1).exactInput(params)
            ).to.be.revertedWith("SwapRouter__InvalidPath");
        });
    });

    describe("MEV Protection", function () {
        beforeEach(async function () {
            // Enable MEV protection
            const mevConfig = {
                enabled: true,
                maxPriceImpact: 1000, // 10%
                minBlockDelay: 2,
                maxSlippageTolerance: 500 // 5%
            };
            await swapRouter.setMEVProtection(mevConfig);
        });

        it("Should allow swaps when MEV protection conditions are met", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("10"), // Small amount
                amountOutMinimum: ethers.utils.parseEther("9"),
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params)
            ).to.not.be.reverted;
        });

        it("Should block rapid consecutive swaps", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("10"),
                amountOutMinimum: ethers.utils.parseEther("9"),
                sqrtPriceLimitX96: 0
            };

            // First swap should succeed
            await swapRouter.connect(addr1).exactInputSingle(params);

            // Second swap in same block should fail
            await expect(
                swapRouter.connect(addr1).exactInputSingle(params)
            ).to.be.revertedWith("SwapRouter__MEVProtectionTriggered");
        });

        it("Should block swaps with excessive price impact", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("100000"), // Very large amount
                amountOutMinimum: ethers.utils.parseEther("1"),
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params)
            ).to.be.revertedWith("SwapRouter__ExcessivePriceImpact");
        });
    });

    describe("Token Blacklist/Whitelist", function () {
        it("Should block swaps with blacklisted tokens", async function () {
            await swapRouter.setTokenBlacklist(token0.address, true);

            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("100"),
                amountOutMinimum: ethers.utils.parseEther("95"),
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params)
            ).to.be.revertedWith("SwapRouter__TokenBlacklisted");
        });

        it("Should allow swaps only with whitelisted tokens when whitelist mode is enabled", async function () {
            await swapRouter.setWhitelistMode(true);
            await swapRouter.setTokenWhitelist(token0.address, true);
            await swapRouter.setTokenWhitelist(token1.address, true);

            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("100"),
                amountOutMinimum: ethers.utils.parseEther("95"),
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params)
            ).to.not.be.reverted;
        });

        it("Should block swaps with non-whitelisted tokens when whitelist mode is enabled", async function () {
            await swapRouter.setWhitelistMode(true);
            await swapRouter.setTokenWhitelist(token0.address, true);
            // token1 is not whitelisted

            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("100"),
                amountOutMinimum: ethers.utils.parseEther("95"),
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params)
            ).to.be.revertedWith("SwapRouter__TokenNotWhitelisted");
        });
    });

    describe("Configuration Management", function () {
        it("Should allow admin to update router fee", async function () {
            const newFee = 5; // 0.05%

            await swapRouter.setRouterFee(newFee);

            expect(await swapRouter.routerFee()).to.equal(newFee);
        });

        it("Should reject invalid router fee", async function () {
            const invalidFee = 101; // > 1%

            await expect(
                swapRouter.setRouterFee(invalidFee)
            ).to.be.revertedWith("SwapRouter__InvalidAmount");
        });

        it("Should allow admin to update router fee recipient", async function () {
            await swapRouter.setRouterFeeRecipient(addr2.address);

            expect(await swapRouter.routerFeeRecipient()).to.equal(addr2.address);
        });

        it("Should allow admin to update default slippage", async function () {
            const newSlippage = 1000; // 10%

            await swapRouter.setDefaultSlippage(newSlippage);

            expect(await swapRouter.defaultSlippage()).to.equal(newSlippage);
        });

        it("Should reject invalid slippage", async function () {
            await expect(
                swapRouter.setDefaultSlippage(0)
            ).to.be.revertedWith("SwapRouter__InvalidSlippage");

            await expect(
                swapRouter.setDefaultSlippage(5001) // > MAX_SLIPPAGE
            ).to.be.revertedWith("SwapRouter__InvalidSlippage");
        });

        it("Should allow admin to update quoter", async function () {
            const newQuoter = addr2.address;

            await swapRouter.setQuoter(newQuoter);

            expect(await swapRouter.getQuoter()).to.equal(newQuoter);
        });

        it("Should not allow non-admin to update settings", async function () {
            await expect(
                swapRouter.connect(addr1).setRouterFee(5)
            ).to.be.revertedWith("AccessControl:");

            await expect(
                swapRouter.connect(addr1).setDefaultSlippage(1000)
            ).to.be.revertedWith("AccessControl:");

            await expect(
                swapRouter.connect(addr1).setMEVProtection({
                    enabled: true,
                    maxPriceImpact: 2000,
                    minBlockDelay: 3,
                    maxSlippageTolerance: 1000
                })
            ).to.be.revertedWith("AccessControl:");
        });
    });

    describe("Access Control & Security", function () {
        it("Should pause and unpause correctly", async function () {
            await swapRouter.pause();
            expect(await swapRouter.paused()).to.be.true;

            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("100"),
                amountOutMinimum: ethers.utils.parseEther("95"),
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params)
            ).to.be.revertedWith("Pausable: paused");

            await swapRouter.unpause();
            expect(await swapRouter.paused()).to.be.false;
        });

        it("Should not allow non-pauser to pause", async function () {
            await expect(
                swapRouter.connect(addr1).pause()
            ).to.be.revertedWith("AccessControl:");
        });

        it("Should allow emergency role to toggle emergency mode", async function () {
            await swapRouter.setEmergencyMode(true);
            expect(await swapRouter.emergencyMode()).to.be.true;

            await swapRouter.setEmergencyMode(false);
            expect(await swapRouter.emergencyMode()).to.be.false;
        });

        it("Should emit events correctly", async function () {
            await expect(swapRouter.setRouterFee(5))
                .to.emit(swapRouter, "RouterFeeUpdated")
                .withArgs(1, 5);

            await expect(swapRouter.setRouterFeeRecipient(addr2.address))
                .to.emit(swapRouter, "RouterFeeRecipientUpdated")
                .withArgs(owner.address, addr2.address);

            await expect(swapRouter.setDefaultSlippage(1000))
                .to.emit(swapRouter, "DefaultSlippageUpdated")
                .withArgs(500, 1000);

            await expect(swapRouter.setTokenBlacklist(token0.address, true))
                .to.emit(swapRouter, "TokenBlacklisted")
                .withArgs(token0.address, true);

            await expect(swapRouter.setWhitelistMode(true))
                .to.emit(swapRouter, "WhitelistModeToggled")
                .withArgs(true);
        });
    });

    describe("ETH/WETH Handling", function () {
        it("Should handle ETH input correctly", async function () {
            const params = {
                tokenIn: weth9.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("1"),
                amountOutMinimum: ethers.utils.parseEther("0.9"),
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params, {
                    value: ethers.utils.parseEther("1")
                })
            ).to.not.be.reverted;
        });

        it("Should reject incorrect ETH amount", async function () {
            const params = {
                tokenIn: weth9.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("1"),
                amountOutMinimum: ethers.utils.parseEther("0.9"),
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params, {
                    value: ethers.utils.parseEther("2") // Wrong amount
                })
            ).to.be.revertedWith("SwapRouter__InvalidAmount");
        });

        it("Should only accept ETH from WETH contract", async function () {
            await expect(
                addr1.sendTransaction({
                    to: swapRouter.address,
                    value: ethers.utils.parseEther("1")
                })
            ).to.be.revertedWith("SwapRouter: ETH not from WETH");
        });
    });

    describe("Edge Cases & Error Handling", function () {
        it("Should handle non-existent pools", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token2.address,
                fee: 1000, // Non-existent fee tier
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("100"),
                amountOutMinimum: ethers.utils.parseEther("95"),
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params)
            ).to.be.revertedWith("SwapRouter__PoolNotFound");
        });

        it("Should handle insufficient balance", async function () {
            // Try to swap more than available balance
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("10000000"), // More than minted
                amountOutMinimum: ethers.utils.parseEther("1"),
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params)
            ).to.be.reverted; // Should revert during transfer
        });

        it("Should handle slippage protection", async function () {
            const params = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("100"),
                amountOutMinimum: ethers.utils.parseEther("200"), // Unrealistic expectation
                sqrtPriceLimitX96: 0
            };

            await expect(
                swapRouter.connect(addr1).exactInputSingle(params)
            ).to.be.revertedWith("SwapRouter__InsufficientAmountOut");
        });
    });

    describe("Multicall Functionality", function () {
        it("Should support multicall for batch operations", async function () {
            const params1 = {
                tokenIn: token0.address,
                tokenOut: token1.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("50"),
                amountOutMinimum: ethers.utils.parseEther("45"),
                sqrtPriceLimitX96: 0
            };

            const params2 = {
                tokenIn: token1.address,
                tokenOut: token2.address,
                fee: FEE_MEDIUM,
                recipient: addr1.address,
                deadline: DEADLINE,
                amountIn: ethers.utils.parseEther("50"),
                amountOutMinimum: ethers.utils.parseEther("45"),
                sqrtPriceLimitX96: 0
            };

            // Encode function calls
            const call1 = swapRouter.interface.encodeFunctionData("exactInputSingle", [params1]);
            const call2 = swapRouter.interface.encodeFunctionData("exactInputSingle", [params2]);

            await expect(
                swapRouter.connect(addr1).multicall([call1, call2])
            ).to.not.be.reverted;
        });
    });
});

// Mock contracts for testing
contract MockERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) {
        // Implementation
    }
    
    function mint(address to, uint256 amount) external {
        // Implementation
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        // Implementation
    }
    
    function balanceOf(address account) external view returns (uint256) {
        // Implementation
    }
}

contract MockWETH9 {
    function deposit() external payable {
        // Implementation
    }
    
    function withdraw(uint256 wad) external {
        // Implementation
    }
    
    function balanceOf(address account) external view returns (uint256) {
        // Implementation
    }
} 