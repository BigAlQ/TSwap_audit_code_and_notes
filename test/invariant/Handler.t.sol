// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { TSwapPool } from "../../src/TSwapPool.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";

contract Handler is Test {
    TSwapPool pool;
    ERC20Mock weth;
    ERC20Mock poolToken;

    address liquidityProvider = makeAddr("lp");
    address swapper = makeAddr("swapper");

    // Ghost variables (they dont actually exist in our contract)
    // Initial Balances
    int256 public startingY; // WETH this contract currently holds
    int256 public startingX; // pool tokens this contract currently holds.

    // Deposits
    int256 public expectedDeltaY; // expected amount of WETH to be deposited into the pool
    int256 public expectedDeltaX; // the expected amount of the pool token that needs to be deposited to match the given
        // expectedDeltaY WETH
        // deposit while maintaining the pool’s token ratio.

    // Change in balance for this contract
    int256 public actualDeltaX;
    int256 public actualDeltaY;

    constructor(TSwapPool _pool) {
        pool = _pool;
        weth = ERC20Mock(_pool.getWeth());
        poolToken = ERC20Mock(_pool.getPoolToken());
    }

    // Simulates a swap operation where the handler wants to get a specific amount of WETH from the pool.
    // Determines how much pool token to input to get that output WETH.

    function swapPoolTokenForWethBasedOnOutputWeth(uint256 outputWeth) public {
        outputWeth = bound(outputWeth, pool.getMinimumWethDepositAmount(), weth.balanceOf(address(pool)));

        if (outputWeth >= weth.balanceOf(address(pool))) {
            return;
        }
        //  ∆x = ( β / (1-β) ) * x

        // Uses the constant product formula to compute how many pool tokens you need to provide for the desired
        // outputWeth.
        uint256 poolTokenAmount = pool.getInputAmountBasedOnOutput(
            outputWeth, poolToken.balanceOf(address(pool)), weth.balanceOf(address(pool))
        );
        // Check overflow
        if (poolTokenAmount > type(uint64).max) {
            return;
        }

        startingY = int256(weth.balanceOf(address(pool)));
        startingX = int256(poolToken.balanceOf(address(pool)));
        expectedDeltaY = int256(-1) * int256(outputWeth); // the contract is sending WETH to the pool to get the swap
            // done. (I think the swappers balance will increase?)
        expectedDeltaX = int256(poolTokenAmount); // the amount of pool tokens
            // the pool contract expecst to receive in exchange for the weth?

        if (poolToken.balanceOf(swapper) < poolTokenAmount) {
            poolToken.mint(swapper, poolTokenAmount - poolToken.balanceOf(swapper) + 1);
        }

        vm.startPrank(swapper);
        poolToken.approve(address(pool), type(uint256).max);
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));

        vm.stopPrank();

        uint256 endingY = weth.balanceOf(address(pool));
        uint256 endingX = poolToken.balanceOf(address(pool));

        // calculate delta balance for actual delta
        int256 actualDeltaX = int256(endingX) - int256(startingX);
        int256 actualDeltaY = int256(endingY) - int256(startingY);
    }

    function deposit(uint256 wethAmount) public {
        // Lets make sure its a reasonable amount to avoid overflow
        uint256 minWeth = pool.getMinimumWethDepositAmount();
        wethAmount = bound(wethAmount, minWeth, type(uint64).max);

        startingY = int256(weth.balanceOf(address(this)));
        startingX = int256(poolToken.balanceOf(address(this)));
        expectedDeltaY = int256(wethAmount);
        expectedDeltaX = int256(pool.getPoolTokensToDepositBasedOnWeth(wethAmount));

        // deposit
        vm.startPrank(liquidityProvider);

        weth.mint(liquidityProvider, wethAmount);
        poolToken.mint(liquidityProvider, uint256(expectedDeltaX));

        weth.approve(address(pool), type(uint256).max);
        poolToken.approve(address(pool), type(uint256).max);

        pool.deposit(wethAmount, 0, uint256(expectedDeltaX), uint64(block.timestamp));
        vm.stopPrank();

        // actual
        uint256 endingY = weth.balanceOf(address(pool));
        uint256 endingX = poolToken.balanceOf(address(pool));

        // calculate delta balance for actual delta
        int256 actualDeltaX = int256(endingX) - int256(startingX);
        int256 actualDeltaY = int256(endingY) - int256(startingY);
    }
}
