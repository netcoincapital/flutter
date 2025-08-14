const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SwapMath Library", function () {
    let swapMath;
    let owner, addr1;

    // Constants for testing
    const Q96 = ethers.BigNumber.from("79228162514264337593543950336");
    const INITIAL_PRICE = Q96; // sqrt(1) in Q96
    const FEE_MEDIUM = 3000; // 0.3%

    before(async function () {
        [owner, addr1] = await ethers.getSigners();

        // Deploy a test contract that uses SwapMath library
        const SwapMathTest = await ethers.getContractFactory("SwapMathTest");
        swapMath = await SwapMathTest.deploy();
        await swapMath.deployed();
    });

    describe("Constants", function () {
        it("Should have correct Q notation constants", async function () {
            expect(await swapMath.Q96()).to.equal(Q96);
            expect(await swapMath.Q128()).to.equal("340282366920938463463374607431768211456");
        });

        it("Should have correct tick range", async function () {
            expect(await swapMath.MAX_TICK()).to.equal(887272);
            expect(await swapMath.MIN_TICK()).to.equal(-887272);
        });

        it("Should have correct fee denominator", async function () {
            expect(await swapMath.FEE_DENOMINATOR()).to.equal(1000000);
        });
    });

    describe("Swap Calculations", function () {
        const liquidity = ethers.utils.parseEther("1000");
        const amountIn = ethers.utils.parseEther("100");

        it("Should calculate exact input swap correctly", async function () {
            const params = {
                sqrtPriceCurrentX96: INITIAL_PRICE,
                sqrtPriceTargetX96: 0,
                liquidity: liquidity,
                amount: amountIn, // positive for exact input
                fee: FEE_MEDIUM,
                zeroForOne: true
            };

            const result = await swapMath.calculateSwap(params);
            
            expect(result.amountCalculated).to.be.gt(0);
            expect(result.sqrtPriceX96).to.be.gt(0);
            expect(result.feeAmount).to.be.gt(0);
            expect(result.gasUsed).to.be.gte(50000);
        });

        it("Should calculate exact output swap correctly", async function () {
            const amountOut = ethers.utils.parseEther("90");
            
            const params = {
                sqrtPriceCurrentX96: INITIAL_PRICE,
                sqrtPriceTargetX96: 0,
                liquidity: liquidity,
                amount: amountOut.mul(-1), // negative for exact output
                fee: FEE_MEDIUM,
                zeroForOne: true
            };

            const result = await swapMath.calculateSwap(params);
            
            expect(result.amountCalculated).to.be.gt(amountOut);
            expect(result.sqrtPriceX96).to.be.gt(0);
            expect(result.feeAmount).to.be.gt(0);
        });

        it("Should reject swap with zero price", async function () {
            const params = {
                sqrtPriceCurrentX96: 0,
                sqrtPriceTargetX96: 0,
                liquidity: liquidity,
                amount: amountIn,
                fee: FEE_MEDIUM,
                zeroForOne: true
            };

            await expect(
                swapMath.calculateSwap(params)
            ).to.be.revertedWith("SwapMath__InvalidPrice");
        });

        it("Should reject swap with zero liquidity", async function () {
            const params = {
                sqrtPriceCurrentX96: INITIAL_PRICE,
                sqrtPriceTargetX96: 0,
                liquidity: 0,
                amount: amountIn,
                fee: FEE_MEDIUM,
                zeroForOne: true
            };

            await expect(
                swapMath.calculateSwap(params)
            ).to.be.revertedWith("SwapMath__InsufficientLiquidity");
        });

        it("Should reject swap with zero amount", async function () {
            const params = {
                sqrtPriceCurrentX96: INITIAL_PRICE,
                sqrtPriceTargetX96: 0,
                liquidity: liquidity,
                amount: 0,
                fee: FEE_MEDIUM,
                zeroForOne: true
            };

            await expect(
                swapMath.calculateSwap(params)
            ).to.be.revertedWith("SwapMath__InvalidAmount");
        });
    });

    describe("Amount Calculations", function () {
        const liquidity = ethers.utils.parseEther("1000");
        const amountIn = ethers.utils.parseEther("100");

        it("Should calculate amount out for given amount in", async function () {
            const amountOut = await swapMath.getAmountOut(
                amountIn,
                liquidity,
                INITIAL_PRICE,
                true // zeroForOne
            );

            expect(amountOut).to.be.gt(0);
            expect(amountOut).to.be.lt(amountIn); // Should be less due to slippage and fees
        });

        it("Should calculate amount in for given amount out", async function () {
            const amountOut = ethers.utils.parseEther("90");
            
            const amountInRequired = await swapMath.getAmountIn(
                amountOut,
                liquidity,
                INITIAL_PRICE,
                true // zeroForOne
            );

            expect(amountInRequired).to.be.gt(amountOut); // Should be more due to slippage and fees
        });

        it("Should return zero for zero input", async function () {
            const amountOut = await swapMath.getAmountOut(
                0,
                liquidity,
                INITIAL_PRICE,
                true
            );
            expect(amountOut).to.equal(0);

            const amountIn = await swapMath.getAmountIn(
                0,
                liquidity,
                INITIAL_PRICE,
                true
            );
            expect(amountIn).to.equal(0);
        });

        it("Should handle different swap directions", async function () {
            const amountOut0for1 = await swapMath.getAmountOut(
                amountIn,
                liquidity,
                INITIAL_PRICE,
                true // zeroForOne
            );

            const amountOut1for0 = await swapMath.getAmountOut(
                amountIn,
                liquidity,
                INITIAL_PRICE,
                false // oneForZero
            );

            // Results should be different for different directions
            expect(amountOut0for1).to.not.equal(amountOut1for0);
        });

        it("Should reject calculations with insufficient liquidity", async function () {
            await expect(
                swapMath.getAmountOut(amountIn, 0, INITIAL_PRICE, true)
            ).to.be.revertedWith("SwapMath__InsufficientLiquidity");

            await expect(
                swapMath.getAmountIn(amountIn, 0, INITIAL_PRICE, true)
            ).to.be.revertedWith("SwapMath__InsufficientLiquidity");
        });
    });

    describe("Price Calculations", function () {
        const liquidity = ethers.utils.parseEther("1000");
        const amountIn = ethers.utils.parseEther("100");

        it("Should calculate new price after swap", async function () {
            const newPrice = await swapMath.getNewPrice(
                INITIAL_PRICE,
                liquidity,
                amountIn,
                true // zeroForOne
            );

            expect(newPrice).to.be.gt(0);
            expect(newPrice).to.not.equal(INITIAL_PRICE);
        });

        it("Should decrease price for token0 -> token1 swap", async function () {
            const newPrice = await swapMath.getNewPrice(
                INITIAL_PRICE,
                liquidity,
                amountIn,
                true // zeroForOne
            );

            expect(newPrice).to.be.lt(INITIAL_PRICE);
        });

        it("Should increase price for token1 -> token0 swap", async function () {
            const newPrice = await swapMath.getNewPrice(
                INITIAL_PRICE,
                liquidity,
                amountIn,
                false // oneForZero
            );

            expect(newPrice).to.be.gt(INITIAL_PRICE);
        });

        it("Should reject price calculation with zero liquidity", async function () {
            await expect(
                swapMath.getNewPrice(INITIAL_PRICE, 0, amountIn, true)
            ).to.be.revertedWith("SwapMath__InsufficientLiquidity");
        });

        it("Should reject price out of range", async function () {
            const extremeAmount = ethers.utils.parseEther("1000000000");
            
            await expect(
                swapMath.getNewPrice(INITIAL_PRICE, liquidity, extremeAmount, true)
            ).to.be.revertedWith("SwapMath__PriceOutOfRange");
        });
    });

    describe("Price Impact", function () {
        it("Should calculate price impact correctly", async function () {
            const priceBefore = INITIAL_PRICE;
            const priceAfter = INITIAL_PRICE.mul(95).div(100); // 5% decrease

            const impact = await swapMath.calculatePriceImpact(priceBefore, priceAfter);
            
            expect(impact).to.be.approximately(500, 10); // ~5% in basis points
        });

        it("Should handle price increase", async function () {
            const priceBefore = INITIAL_PRICE;
            const priceAfter = INITIAL_PRICE.mul(105).div(100); // 5% increase

            const impact = await swapMath.calculatePriceImpact(priceBefore, priceAfter);
            
            expect(impact).to.be.approximately(500, 10); // ~5% in basis points
        });

        it("Should return zero for zero price before", async function () {
            const impact = await swapMath.calculatePriceImpact(0, INITIAL_PRICE);
            expect(impact).to.equal(0);
        });

        it("Should return zero for same prices", async function () {
            const impact = await swapMath.calculatePriceImpact(INITIAL_PRICE, INITIAL_PRICE);
            expect(impact).to.equal(0);
        });
    });

    describe("Liquidity Calculations", function () {
        const amount0 = ethers.utils.parseEther("100");
        const amount1 = ethers.utils.parseEther("100");
        const sqrtRatioA = INITIAL_PRICE.mul(90).div(100); // Lower price
        const sqrtRatioB = INITIAL_PRICE.mul(110).div(100); // Higher price

        it("Should calculate liquidity for given amounts", async function () {
            const liquidity = await swapMath.getLiquidityForAmounts(
                sqrtRatioA,
                sqrtRatioB,
                amount0,
                amount1
            );

            expect(liquidity).to.be.gt(0);
        });

        it("Should calculate amounts for given liquidity", async function () {
            const liquidity = ethers.utils.parseEther("1000");
            
            const amounts = await swapMath.getAmountsForLiquidity(
                sqrtRatioA,
                sqrtRatioB,
                liquidity
            );

            expect(amounts.amount0).to.be.gt(0);
            expect(amounts.amount1).to.be.gt(0);
        });

        it("Should handle reversed price ratios", async function () {
            // Pass prices in wrong order - function should handle it
            const liquidity = await swapMath.getLiquidityForAmounts(
                sqrtRatioB, // Higher price first
                sqrtRatioA, // Lower price second
                amount0,
                amount1
            );

            expect(liquidity).to.be.gt(0);
        });
    });

    describe("Utility Functions", function () {
        it("Should estimate gas correctly", async function () {
            const gasFor1Hop = await swapMath.estimateGas(1, false);
            const gasFor2Hops = await swapMath.estimateGas(2, false);
            const gasComplex = await swapMath.estimateGas(1, true);

            expect(gasFor2Hops).to.be.gt(gasFor1Hop);
            expect(gasComplex).to.be.gt(gasFor1Hop);
        });

        it("Should calculate optimal swap amount", async function () {
            const reserve0 = ethers.utils.parseEther("1000");
            const reserve1 = ethers.utils.parseEther("1000");
            const fee = FEE_MEDIUM;

            const optimalAmount = await swapMath.calculateOptimalSwapAmount(
                reserve0,
                reserve1,
                fee
            );

            expect(optimalAmount).to.be.gt(0);
            expect(optimalAmount).to.be.lt(reserve0);
        });

        it("Should calculate square root correctly", async function () {
            const input = 100;
            const result = await swapMath.sqrt(input);
            
            expect(result).to.equal(10);
        });

        it("Should return correct min/max ticks for fee tiers", async function () {
            const minTick500 = await swapMath.getMinTickForFee(500);
            const maxTick500 = await swapMath.getMaxTickForFee(500);
            
            expect(minTick500).to.equal(-887220);
            expect(maxTick500).to.equal(887220);

            const minTick3000 = await swapMath.getMinTickForFee(3000);
            const maxTick3000 = await swapMath.getMaxTickForFee(3000);
            
            expect(minTick3000).to.equal(-887200);
            expect(maxTick3000).to.equal(887200);
        });

        it("Should validate price ranges correctly", async function () {
            const validRange = await swapMath.isValidPriceRange(
                INITIAL_PRICE.mul(90).div(100),
                INITIAL_PRICE.mul(110).div(100)
            );
            expect(validRange).to.be.true;

            const invalidRange1 = await swapMath.isValidPriceRange(0, INITIAL_PRICE);
            expect(invalidRange1).to.be.false;

            const invalidRange2 = await swapMath.isValidPriceRange(INITIAL_PRICE, INITIAL_PRICE);
            expect(invalidRange2).to.be.false;
        });
    });

    describe("Edge Cases", function () {
        it("Should handle very small amounts", async function () {
            const smallAmount = 1; // 1 wei
            const liquidity = ethers.utils.parseEther("1000");

            const amountOut = await swapMath.getAmountOut(
                smallAmount,
                liquidity,
                INITIAL_PRICE,
                true
            );

            expect(amountOut).to.be.gte(0);
        });

        it("Should handle very large liquidity", async function () {
            const largeLiquidity = ethers.utils.parseEther("1000000000");
            const amountIn = ethers.utils.parseEther("100");

            const amountOut = await swapMath.getAmountOut(
                amountIn,
                largeLiquidity,
                INITIAL_PRICE,
                true
            );

            expect(amountOut).to.be.gt(0);
        });

        it("Should handle precision edge cases", async function () {
            const preciseAmount = ethers.BigNumber.from("123456789012345678");
            const liquidity = ethers.utils.parseEther("1000");

            const amountOut = await swapMath.getAmountOut(
                preciseAmount,
                liquidity,
                INITIAL_PRICE,
                true
            );

            expect(amountOut).to.be.gt(0);
        });
    });

    describe("Mathematical Properties", function () {
        const liquidity = ethers.utils.parseEther("1000");

        it("Should maintain consistency between getAmountOut and getAmountIn", async function () {
            const amountIn = ethers.utils.parseEther("100");
            
            // Calculate amount out for given amount in
            const amountOut = await swapMath.getAmountOut(
                amountIn,
                liquidity,
                INITIAL_PRICE,
                true
            );

            // Calculate amount in required for that amount out
            const requiredAmountIn = await swapMath.getAmountIn(
                amountOut,
                liquidity,
                INITIAL_PRICE,
                true
            );

            // Should be approximately equal (allowing for rounding)
            const difference = requiredAmountIn.sub(amountIn).abs();
            const tolerance = amountIn.div(1000); // 0.1% tolerance
            
            expect(difference).to.be.lte(tolerance);
        });

        it("Should have monotonic behavior", async function () {
            const amounts = [
                ethers.utils.parseEther("10"),
                ethers.utils.parseEther("50"),
                ethers.utils.parseEther("100")
            ];

            const outputs = [];
            for (const amount of amounts) {
                const output = await swapMath.getAmountOut(
                    amount,
                    liquidity,
                    INITIAL_PRICE,
                    true
                );
                outputs.push(output);
            }

            // Outputs should be increasing (monotonic)
            expect(outputs[1]).to.be.gt(outputs[0]);
            expect(outputs[2]).to.be.gt(outputs[1]);
        });

        it("Should respect fee calculations", async function () {
            const amountIn = ethers.utils.parseEther("100");
            const expectedFee = amountIn.mul(FEE_MEDIUM).div(1000000);

            const params = {
                sqrtPriceCurrentX96: INITIAL_PRICE,
                sqrtPriceTargetX96: 0,
                liquidity: liquidity,
                amount: amountIn,
                fee: FEE_MEDIUM,
                zeroForOne: true
            };

            const result = await swapMath.calculateSwap(params);
            
            // Fee should be approximately correct
            const feeDifference = result.feeAmount.sub(expectedFee).abs();
            const tolerance = expectedFee.div(100); // 1% tolerance
            
            expect(feeDifference).to.be.lte(tolerance);
        });
    });
});

// Helper contract for testing SwapMath library
contract SwapMathTest {
    using SwapMath for SwapMath.SwapParams;
    
    function Q96() external pure returns (uint256) {
        return SwapMath.Q96;
    }
    
    function Q128() external pure returns (uint256) {
        return SwapMath.Q128;
    }
    
    function MAX_TICK() external pure returns (int24) {
        return SwapMath.MAX_TICK;
    }
    
    function MIN_TICK() external pure returns (int24) {
        return SwapMath.MIN_TICK;
    }
    
    function FEE_DENOMINATOR() external pure returns (uint256) {
        return SwapMath.FEE_DENOMINATOR;
    }
    
    function calculateSwap(SwapMath.SwapParams memory params) 
        external 
        pure 
        returns (SwapMath.SwapResult memory) 
    {
        return SwapMath.calculateSwap(params);
    }
    
    function getAmountOut(
        uint256 amountIn,
        uint256 liquidity,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) external pure returns (uint256) {
        return SwapMath.getAmountOut(amountIn, liquidity, sqrtPriceX96, zeroForOne);
    }
    
    function getAmountIn(
        uint256 amountOut,
        uint256 liquidity,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) external pure returns (uint256) {
        return SwapMath.getAmountIn(amountOut, liquidity, sqrtPriceX96, zeroForOne);
    }
    
    function getNewPrice(
        uint160 sqrtPriceX96,
        uint256 liquidity,
        uint256 amountIn,
        bool zeroForOne
    ) external pure returns (uint160) {
        return SwapMath.getNewPrice(sqrtPriceX96, liquidity, amountIn, zeroForOne);
    }
    
    function calculatePriceImpact(
        uint160 priceBefore,
        uint160 priceAfter
    ) external pure returns (uint256) {
        return SwapMath.calculatePriceImpact(priceBefore, priceAfter);
    }
    
    function getLiquidityForAmounts(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) external pure returns (uint128) {
        return SwapMath.getLiquidityForAmounts(sqrtRatioAX96, sqrtRatioBX96, amount0, amount1);
    }
    
    function getAmountsForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) external pure returns (uint256 amount0, uint256 amount1) {
        return SwapMath.getAmountsForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }
    
    function estimateGas(
        uint256 hops,
        bool hasComplexPath
    ) external pure returns (uint256) {
        return SwapMath.estimateGas(hops, hasComplexPath);
    }
    
    function calculateOptimalSwapAmount(
        uint256 reserve0,
        uint256 reserve1,
        uint24 fee
    ) external pure returns (uint256) {
        return SwapMath.calculateOptimalSwapAmount(reserve0, reserve1, fee);
    }
    
    function sqrt(uint256 x) external pure returns (uint256) {
        return SwapMath.sqrt(x);
    }
    
    function getMinTickForFee(uint24 fee) external pure returns (int24) {
        return SwapMath.getMinTickForFee(fee);
    }
    
    function getMaxTickForFee(uint24 fee) external pure returns (int24) {
        return SwapMath.getMaxTickForFee(fee);
    }
    
    function isValidPriceRange(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96
    ) external pure returns (bool) {
        return SwapMath.isValidPriceRange(sqrtPriceAX96, sqrtPriceBX96);
    }
} 