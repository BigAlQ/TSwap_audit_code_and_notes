// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { PoolFactory } from "../../src/PoolFactory.sol";
import { TSwapPool } from "../../src/TSwapPool.sol";
import { Handler } from "test/invariant/Handler.t.sol";

contract Invariant is StdInvariant, Test {
    // these pools have 2 assets
    ERC20Mock poolToken;
    ERC20Mock weth;

    // We are gonna need the contracts
    PoolFactory factory;
    TSwapPool pool; // This will be out poolToken/Weth  pool
    Handler handler;

    int256 constant STARTING_X = 100e18; // Starting ERC20 liquidity for pool
    int256 constant STARTING_Y = 50e18; // Starting WETH liquidity for pool

    function setUp() public {
        weth = new ERC20Mock();
        poolToken = new ERC20Mock();
        factory = new PoolFactory(address(weth));
        pool = TSwapPool(factory.createPool(address(poolToken)));

        // Create and approve the liquidity to be place into the liquidity pools
        poolToken.mint(address(this), uint256(STARTING_X));
        weth.mint(address(this), uint256(STARTING_Y));

        poolToken.approve(address(pool), type(uint64).max);
        weth.approve(address(pool), type(uint64).max);

        // Deposit the liquidity into the liquidity pools
        pool.deposit(uint256(STARTING_Y), uint256(STARTING_Y), uint256(STARTING_X), uint64(block.timestamp));

        handler = new Handler(pool);

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.swapPoolTokenForWethBasedOnOutputWeth.selector;

        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors })); // Restrict fuzzing to this
            // specific set of functions from the handler
            // will be called
        targetContract(address(handler)); // This contracts functions will be called randomly and fuzzed
    }

    function statefulFuzz_constantProductForumulaStaysTheSameX() public {
        // assert()
        // The change in the pool size of WETH should follow this function:
        // ∆x = (β/(1-β)) * x
        // ????
        // What we can do to calculate this, in a handler we can:
        // keep track of delta x:
        // actual Delta X == ∆x = (β/(1-β)) * x
        assertEq(handler.actualDeltaX(), handler.expectedDeltaX());
    }

    function invariant_constantProductForumulaStaysTheSameY() public {
        // assert()
        // The change in the pool size of WETH should follow this function:
        // ∆x = (β/(1-β)) * x
        // ????
        // What we can do to calculate this, in a handler we can:
        // keep track of delta x:
        // actual Delta X == ∆x = (β/(1-β)) * x
        assertEq(handler.actualDeltaX(), handler.expectedDeltaY());
    }
}
