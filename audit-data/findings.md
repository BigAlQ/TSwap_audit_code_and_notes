### [S-#] TITLE (Root Cause + Impact)

**Description:**

**Impact:**

**Proof of Concept:** (or proof of code)

**Recommended Mitigation:**

## High

### [H-1] `TSwapPool::deposit` is missing deadline check causing transactions to complete even after the deadline

**Description:** The `deposit` function accepts a deadline parameter, which according to the documentation is the deadline for the transaction to be completed by. However, this parameter is never used. As a consequence, operations that add liquidity to the pool might be executed at unexpected times, in market conditions where the deposit rate is unfavorable.

<!-- MEV attacks -->

**Impact:** Transactions could be sent when market conditions are unfavorable to deposit, even when adding a deadline parameter.

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
        // @audit -info: No zero address check
        i_wethToken = IERC20(wethToken);
        i_poolToken = IERC20(poolToken);
    }

```
