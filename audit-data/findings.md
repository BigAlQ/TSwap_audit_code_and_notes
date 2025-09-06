### [S-#] TITLE (Root Cause + Impact)

**Description:**

**Impact:**

**Proof of Concept:** (or proof of code)

**Recommended Mitigation:**

## High

### [H-1] Incorrect fee calculation in `TSwapPool::getInputAmountBasedOnOutput` causes protocol to take too many tokens from users, resulting in lost fees

**Description:** The `getInputAmountBasedOnOutput` function is intended to calculate the amount of tokens a user should deposit given an amount of output tokens. However, the function currently miscalculates the resulting amount. When calculating the fee, it scales the amount by 10_000 instead of 1_000.

**Impact:** Protocol takes more fees than expected from users.

**Recommended Mitigation:** Consider making the following change to the function.

```diff
function getInputAmountBasedOnOutput(
        uint256 outputAmount,
        uint256 inputReserves,
        uint256 outputReserves
    )
        public
        pure
        revertIfZero(outputAmount)
        revertIfZero(outputReserves)
        returns (uint256 inputAmount)
    {
+        return ((inputReserves * outputAmount) * 1_000) / ((outputReserves - outputAmount) * 997);
-        return ((inputReserves * outputAmount) * 10_000) / ((outputReserves - outputAmount) * 997);
    }
```

### [H-2] Lack of slippage protection in `TSwapPool::swapExactOutput` causes users to potentially receive way fewer tokens

**Description:** The `swapExactOutput` function does not include any sort of slippage protection. This function is similar to what is done in `TSwapPool::swapExactInput`,where the function specifies a `minOutputAmount`, the `swapExactOutput` function should specify a `maxInputAmount`.

**Impact:** If market conditions change before the transaction processes, the user could get a much worse swap.

**Proof of Concept:** 
1. The price of weth right now is 1,000 USDC 
2. User inputs a `swapExactOutput` looking for 1 WETH
    1. inputToken = USDC
    2. outputToken = Weth 
    3. outputAmount = 1
    4. deadline = whatever
3. The function does not offer a maxInput amount
4. As the transaction is pending in the mempool, the market changes!
And the price change is HUGE -> 1 WETH is now 10,000 USDC. 10x more than the user expected.
5. The transaction completes, but the user sent the protocol 10,000 USDC instead of the expected 1,000 USDC

**Proof of Code:**

```solidity

function testSlippage() {
        uint256 initialLiquidity = 100e18;
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);

        // Deposit liquidity into the pool via a liquidity provider

        pool.deposit({
            wethToDeposit: initialLiquidity,
            minimumLiquidityTokensToMint: 0,
            maximumPoolTokensToDeposit: initialLiquidity,
            deadline: uint64(block.timestamp)
        });
        vm.stopPrank();

        // We initilize a user with 11 pool tokens

        address someUser = makeAddr("someUser");
        uint256 userInitialPoolTokenBalance = 11e18;
        poolToken.mint(someUser, userInitialPoolTokenBalance);

        // Initilize another user with 100_000 pool tokens 
        address richUser = makeAddr("richUser");
        uint256 userInitialPoolTokenBalance = 100000e18;
        poolToken.mint(richUser, userInitialPoolTokenBalance);
        vm.startPrank(richUser);

        // We get the price of WETH in poolTokens

        uint256 originalWethPrice = pool.getPriceOfOneWethInPoolTokens(); 
        console.log("The original weth price is: ");
        console.log(originalWethPrice);

        // User 1 wants to buy 1 WETH from the pool, paying with pool tokens expecting the original weth price, but then a whale purchases a lot of WETH
        // The whale decreases the supply of WETH, which increases the price of Weth, and User 1 has to pay the higher price.
        
        // Rich user / Whales purcahse of weth
        poolToken.approve(address(pool), type(uint256).max);
        pool.swapExactOutput(poolToken, weth, 10 ether, uint64(block.timestamp));
        vm.stopPrank();

        // Some users purcahse
        vm.startPrank(richUser);

        poolToken.approve(address(pool), type(uint256).max);
        pool.swapExactOutput(poolToken, weth, 1 ether, uint64(block.timestamp));
        vm.stopPrank();

    }
```

**Recommended Mitigation:** We should include a `maxInputAmount` so the user guarentees he only can spend up to a certain limit, and they can predict how much they will spend on the protocol.

```diff
     function swapExactOutput(
        IERC20 inputToken, 
+        uint256 maxInputAmount,
.
.
.
    inputAmount = getInputAmountBasedOnOutput(outputAmount, inputReserves, outputReserves);
+   if(inputAmount > maxInputAmount){
+       revert();
+   } 
    _swap(inputToken, inputAmount, outputToken, outputAmount);
```

### [H-3] `TSwapPool::sellPoolTokens` mismatches input and output tokens causing users to receive the incorrect amount of tokens.

**Description:** The `sellPoolTokens` function is intended to allow users to easily sell pool tokens and receive WETH in exchange. Users indicate how many pool tokens they're willing to sell in the `poolTokenAmount` parameter. However, the funcion currently miscalcuates the swapped amount.

This is due to the fact that the `swapExactOutput` function is called, whereas the `swapExactInput` function is the one that should be called. Because users specify the exact amount of input tokens, not output.

**Impact:** Users will swap the wrong amount of tokens, which is a severe disruption of protocol functionality.

**Recommended Mitigation:**

Consider changing the implementation to use `swapExactInput` instead of `swapExactOutput`. Note that this would also require changing the `sellPoolTokens` function to accept a new parameter (ie `minWethToReceive` to be passed to `swapExactInput`)

```diff
    function sellPoolTokens(
        uint256 poolTokenAmount,
+       uint256 minWethToReceive
    ) external returns (uint256 wethAmount) {
-        return swapExactOutput(i_poolToken, i_wethToken, poolTokenAmount, uint64(block.timestamp));
+        return swapExactInput(i_poolToken, poolTokenAmount, i_wethToken, minWethToReceive , uint64(block.timestamp));
    }
```

Additionally, it might be wise to add a deadline to the function, as there is currently no deadline. (MEV later)

## Medium

### [M-1] `TSwapPool::deposit` is missing deadline check causing transactions to complete even after the deadline

**Description:** The `deposit` function accepts a deadline parameter, which according to the documentation is the deadline for the transaction to be completed by. However, this parameter is never used. As a consequence, operations that add liquidity to the pool might be executed at unexpected times, in market conditions where the deposit rate is unfavorable.

<!-- MEV attacks -->

**Impact:** Transactions could be sent when market conditions are unfavorable to deposit, even when adding a deadline parameter.

**Proof of Concept:** The `deadline` parameter is unused.

**Recommended Mitigation:** Consider making the following change to the function.

```diff
   function deposit(
        uint256 wethToDeposit,
        uint256 minimumLiquidityTokensToMint,
        uint256 maximumPoolTokensToDeposit,
        uint64 deadline
    )
        external
+       revertIfDeadlinePassed(deadline)
        revertIfZero(wethToDeposit)
        returns (uint256 liquidityTokensToMint)
    {
```

## Lows

### [L-1] `TSwapPool::LiquidityAdded` event has parameters out of order

**Description:** When the `LiquidityAdded` event is emitted in the `TSwapPool::_addLiquidityMintAndTransfer` function, it logs values in an incorrect order. The `poolTokensToDeposit` value should go in the third parameter position, whereas the `wethToDeposit` value should go second.

**Impact:** Event emission is incorrect, leading to off-chain functions potentially malfunctioning.

**Recommended Mitigation:**

```diff
-        emit LiquidityAdded(msg.sender, poolTokensToDeposit, wethToDeposit);
+        emit LiquidityAdded(msg.sender, wethToDeposit, poolTokensToDeposit);
```

### [L-2] The `TSwapPool::swapExactInput` function always returns 0 incorrectly

**Description:** The `swapExactInput` function is expected to return the actual amount of tokens bought by the caller. However, while it declares the names return value `output` it is never assigned a value, nor does it use an explicit return statement.

**Impact:** The return value will always be 0, giving incorrect info to the caller.

**Proof of Concept:** (or proof of code)

**Recommended Mitigation:**


## Informationals

### [I-1] The error `PoolFactory::PoolFactory__PoolDoesNotExist` is not used and should be removed

```diff
- error PoolFactory__PoolDoesNotExist(address tokenAddress);
```

### [I-2] The PoolFactory doesn't have a zero check for the wethToken address

```diff
 constructor(address wethToken) {
+        if(wethToken == address(0)){
+            revert();
+        }
        i_wethToken = wethToken;
    }
```

### [I-3] `PoolFactory::createPool` should use `.symbol()` instead of `.name()`

```diff
-        string memory liquidityTokenSymbol = string.concat("ts", IERC20(tokenAddress).name());
+       string memory liquidityTokenSymbol = string.concat("ts", IERC20(tokenAddress).symbol());
```

### [I-4] Event is missing `indexed` fields

Index event fields make the field more quickly accessible to off-chain tools that parse events. However, note that each index field costs extra gas during emission, so it's not necessarily best to index the maximum allowed per event (three fields). Each event should use three indexed fields if there are three or more fields, and gas usage is not particularly of concern for the events in question. If there are fewer than three fields, all of the fields should be indexed.

<details><summary>4 Found Instances</summary>

- Found in src/PoolFactory.sol [Line: 35](src/PoolFactory.sol#L35)

```diff
-      event PoolCreated(address tokenAddress, address poolAddress);
+      event PoolCreated(address indexed tokenAddress, address indexed poolAddress);
```

- Found in src/TSwapPool.sol [Line: 43](src/TSwapPool.sol#L43)

```diff
-    event LiquidityAdded(address indexed liquidityProvider, uint256 wethDeposited, uint256 poolTokensDeposited);
+    event LiquidityAdded(address indexed liquidityProvider, uint256 indexed wethDeposited, uint256 indexed poolTokensDeposited);
```

- Found in src/TSwapPool.sol [Line: 44](src/TSwapPool.sol#L44)

```diff
-      event LiquidityRemoved(address indexed liquidityProvider, uint256 wethWithdrawn, uint256 poolTokensWithdrawn);
+      event LiquidityRemoved(address indexed liquidityProvider, uint256 indexed wethWithdrawn, uint256 indexed poolTokensWithdrawn);
```

- Found in src/TSwapPool.sol [Line: 45](src/TSwapPool.sol#L45)

```diff
-      event Swap(address indexed swapper, IERC20 tokenIn, uint256 amountTokenIn, IERC20 tokenOut, uint256 amountTokenOut);
+      event Swap(address indexed swapper, IERC20 indexed tokenIn, uint256  amountTokenIn, IERC20 indexed tokenOut, uint256 amountTokenOut);
```

</details>

### [I-5] The `TSwapPool` constructor doesn't have zero address checks for weth and pool tokens

**Recommended Mitigation:** Consider making the following change to the function.

```diff
constructor(
        address poolToken,
        address wethToken,
        string memory liquidityTokenName,
        string memory liquidityTokenSymbol
    )
        ERC20(liquidityTokenName, liquidityTokenSymbol)
    {
+       if(poolToken == address(0) || wethToken == address(0)){
+           revert();
+}
s        i_wethToken = IERC20(wethToken);
        i_poolToken = IERC20(poolToken);
    }

```

### [I-6] The `TSwapPool::deposit` function makes an internal call before changing a variable

**Recommended Mitigation:** Consider making the following change to the function.

```diff
else {
            // This will be the "initial" funding of the protocol. We are starting from blank here!
            // We just have them send the tokens in, and we mint liquidity tokens based on the weth
-           _addLiquidityMintAndTransfer(wethToDeposit, maximumPoolTokensToDeposit, wethToDeposit);
            liquidityTokensToMint = wethToDeposit;
+           _addLiquidityMintAndTransfer(wethToDeposit, maximumPoolTokensToDeposit, wethToDeposit);
        }
```

### [I-7] The `TSwapPool::swapExactInput` function is public when it should be external

**Description:** The `TSwapPool::swapExactInput` function is public but is never used within the contract so it should be public.

**Recommended Mitigation:** Consider making the following change to the function.

```diff
function swapExactInput(
        IERC20 inputToken, // e input token to swap / sell ie: DAI
        uint256 inputAmount, // e  amount of the input token to swap
        IERC20 outputToken, // e the output token to buy / ie weth
        uint256 minOutputAmount, // e minimum output amount to recieve of weth from dai
        uint64 deadline // e deadline for when the transaction should expire
    )
+       sexternal
-       public
        revertIfZero(inputAmount)
        revertIfDeadlinePassed(deadline)
        returns (
```

## Gas

### [G-1] `TSwapPool::MINIMUM_WETH_LIQUIDITY` is a constant and does not add utility when emitted in an event

**Recommended Mitigation:** Consider making the following change to the error and the revert:

```diff
-            error TSwapPool__WethDepositAmountTooLow(uint256 minimumWethDeposit, uint256 wethToDeposit);
+            error TSwapPool__WethDepositAmountTooLow(uint256 wethToDeposit);

-            revert TSwapPool__WethDepositAmountTooLow(MINIMUM_WETH_LIQUIDITY, wethToDeposit);
+            revert TSwapPool__WethDepositAmountTooLow(wethToDeposit);


```

### [G-2] The `TSwapPool::deposit` function has an unused variable local variable that wastes gas

**Recommended Mitigation:** Consider making the following change to the function.

```diff
 if (totalLiquidityTokenSupply() > 0) {
            uint256 wethReserves = i_wethToken.balanceOf(address(this));
-            uint256 poolTokenReserves = i_poolToken.balanceOf(address(this));

```
