\- August 4, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

**Type:** DeFi/Stablecoin  
**Timeline:** March 27, 2025 → May 5, 2025**Languages:** Solidity

**Findings**Total issues: 46 (5 resolved)  
Critical: 1 (1 resolved) · High: 2 (2 resolved) · Medium: 7 (2 resolved) · Low: 13 (0 resolved)

**Notes & Additional Information**23 notes raised (0 resolved)

Scope
-----

OpenZeppelin audited the [AladdinDAO/fx-protocol-contracts](https://github.com/AladdinDAO/fx-protocol-contracts/tree/56a47eab8d10334e479df83a2b13a8b68ce390e9) repository at commit [56a47ea](https://github.com/AladdinDAO/fx-protocol-contracts/commit/56a47eab8d10334e479df83a2b13a8b68ce390e9).

In scope were the following files:

`contracts/
├── core/
│   ├── pool/
│   │   ├── AaveFundingPool.sol
│   │   ├── BasePool.sol
│   │   ├── PoolConstant.sol
│   │   ├── PoolErrors.sol
│   │   ├── PoolStorage.sol
│   │   ├── PositionLogic.sol
│   │   └── TickLogic.sol
│   ├── FlashLoans.sol
│   ├── FxUSDBasePool.sol
│   ├── FxUSDRegeneracy.sol
│   ├── PegKeeper.sol
│   ├── PoolManager.sol
│   ├── ProtocolFees.sol
│   ├── ReservePool.sol
│   └── SavingFxUSD.sol
├── fund/
│   ├── strategy/
│   │   ├── AaveV3Strategy.sol
│   │   └── StrategyBase.sol
│   ├── AssetManagement.sol
│   └── IStrategy.sol
└── price-oracle/
    ├── BTCDerivativeOracleBase.sol
    ├── ETHPriceOracle.sol
    ├── LSDPriceOracleBase.sol
    ├── SpotPriceOracleBase.sol
    ├── StETHPriceOracle.sol
    ├── WBTCPriceOracle.sol
    └── interfaces/
        ├── IPriceOracle.sol
        ├── ISpotPriceOracle.sol
        └── ITwapOracle.sol` 

System Overview
---------------

The f(x) Protocol allows users to efficiently create leveraged positions. It does this by facilitating the leveraging of positions and their aggregation into easily rebalanceable units. This minimizes the risk of full liquidation as the price of the position's asset fluctuates. These positions are demarcated with fxUSD tokens, which the protocol is designed to peg to USDC, broadening the appeal of the fxUSD token in the wider DeFi market. The protocol is large and encompasses many contracts. As such, given the protocol's size and complexity, its [documentation](https://fxprotocol.gitbook.io/fx-docs) can be consulted for an in-depth review of the mechanics of the system as a whole.

This audit covers the new functionality of the f(x) Protocol's "2.0" upgrade, which can be broadly categorized into three parts:

*   **Core Pool Mechanisms**: Found in the `core` directory, these contracts provide the core functionality for building positions and maintaining the pegged value of the debt tokens (fxUSD).
    
*   **Price Oracle Infrastructure**: The protocol relies on real-time pricing of assets to correctly value positions and maintain the fxUSD-USDC peg. The contracts in the `price-oracle` directory work to integrate price feeds into the protocol.
    
*   **Asset Management and Reallocation Infrastructure**: While positions are open and collateral is deposited, the protocol aims to earn interest from those funds by depositing them into other DeFi protocols. The contracts in the `fund` directory aim to make this as efficient and seamless as possible.
    

### Core Mechanisms

At the heart of the protocol is the `AaveFundingPool` contract. Each of these contracts handles the leveraged positions for a specific collateral asset. Currently, there is one `AaveFundingPool` contract for WBTC and one for stETH. These contracts handle the accounting for the entire market of positions, organizing them by how collateralized they are.

In addition, these contracts provide entry points for various market actions like creating new positions, adjusting existing ones, rebalancing positions that are losing value, and liquidating positions that are outside the acceptable collateralization range. These entry points are not accessible by all network participants and are controlled by a `PoolManager` contract.

The `PoolManager` contract is where the collateral for all the positions of all the pools actually resides. It is in charge of correctly moving tokens into and out of the pools and dispatching market operations to the appropriate `AaveFundingPool` contract. It offers flashloans for the assets it holds and has an entry point for creating, adjusting, and ending positions. To demarcate the value of each position, fxUSD tokens are minted when positions are opened, with one token representing one dollar of debt.

The fxUSD contract is represented in this scope as the `FxUSDRegeneracy` contract. And because each position is overcollateralized with borrowed assets, each fxUSD token is overcollateralized as well and is burned when positions are adjusted down via deliberate choice or through market pressure (i.e., rebalance or liquidation).

These rebalances and liquidations come from the `FxUSDBasePool` contract, known as the stability pool. This contract is generally in charge of many activities that maintain the health of the protocol. If the relative price of fxUSD or USDC becomes too far away from the peg, the stability pool facilitates market operations to buy and sell these tokens to bring the relative price back to one. Fees are deposited into this contract, increasing its value over time.

The other contracts in this core layer include the `PegKeeper`, which acts as a go-between for the stability pool's market operations, the `ReservePool` contract which covers any collateral losses from undercollateralized debt, and the `SavingFxUSD` contract, known as fxSAVE, which is an ERC-4626 "wrapper" around the stability pool that automatically reinvests any accruals. Wrapping stability pool shares into fxSAVE actually involves a two-step process involving an out-of-scope contract known as the gauge.

### Price Oracles

The f(x) 2.0 price oracle fetches prices from multiple data sources, including Chainlink, Uniswap, Curve, and Balancer, to calculate spot prices and anchor prices. The anchor price is mainly based upon Chainlink's oracle price feed using predefined encodings with the aggregator address, scale, and heartbeat set by the owner role. While the spot prices are fetched from multiple pools, only the minimum price (`minPrice`) and maximum price (`maxPrice`) of those prices are taken into consideration.

Both minimum price and maximum price are allowed a deviation of up to `maxPriceDeviation` threshold from the anchor price. For the WBTC pool, the max deviation is 2%, while for the stETH pool, the max deviation is 1%. If the minimum or maximum price deviation exceeds the threshold, then the anchor price is used instead. The `minPrice` is used for operating on positions, liquidations, and rebalancing, while the `maxPrice` is used during `redeem` operations to avoid arbitrage.

### Asset Management

Since the protocol holds large amounts of tokens, the asset management contracts add the functionality to deposit one contract's tokens into other, yield-bearing contracts. The `AaveV3Strategy` contract deposits tokens into an Aave lending pool while the `AssetManagement` contract allows integration with these strategies. `PoolManager`, in turn, inherits the `AssetManagement` contract, allowing it to earn yield while investors hold their leveraged positions.

Security Model and Trust Assumptions
------------------------------------

The contracts in scope are tightly integrated with each other and depend on correct configuration in order to work correctly. As such, during the course of this audit, the following trust assumptions were made:

*   Variables set at construction or initialization are correct in referring to the protocol contracts that they should. During upgrades, the new implementation ensures that correct values are set at construction, especially for the immutable variables.
*   External protocols work as described. Chainlink, Curve, and Aave are all protocols that are connected to the contracts in this scope.
*   All other f(x) Protocol contracts work as described, and the possessors of the different roles within the protocol act competently and in good faith.

### Privileged Roles By Contract

#### `AaveFundingPool`

The `DEFAULT_ADMIN_ROLE` can:

*   alter fee percentages for opening, closing, or funding a position
*   alter collateralization thresholds for minimum and maximum collateralization, rebalances, and liquidations
*   alter the maximum amount that can be taken from any tick during a redemption
*   set the price oracle
*   change role allocations in the contract

The `EMERGENCY_ROLE` can:

*   pause or unpause the ability to create or increase positions
*   allow or forbid redemptions of fxUSD directly for collateral. The collateral in this case comes directly from the least collateralized positions
*   allow or forbid borrowing when a position is being created. In this case, borrowing means the minting of new fxUSD tokens

The `PoolManager` contract:

*   allows anyone to call `operate` and `redeem`
*   allows the stability pool to call `rebalance`, and `liquidate`. This can extend to anyone should the stability pool's total value not meet a threshold

#### `AaveV3Strategy`

The `HARVESTER_ROLE` can:

*   withdraw rewards from the Aave lending pool and send them to the stability pool as [defined in the documentation](https://fxprotocol.gitbook.io/fx-docs/earn-with-f-x/protocol-revenue-and-distribution#eth-xpositions), even for strategies that have been discontinued

The `operator` can:

*   deposit new tokens into the Aave lending pool strategy
*   withdraw tokens from the Aave lending pool
*   call arbitrary code on the contract

The operator role is intended for contracts like the pool manager and the stability pool that inherit the `AssetManagement` contract.

#### `FxUSDBasePool`

The `DEFAULT_ADMIN_ROLE` can:

*   set and unset the strategy contract for an asset
*   set the redemption waiting period
*   set the instant redemption fee percentage
*   set the price at which USDC is considered to have depegged
*   change role allocations in the contract

The `ASSET_MANAGER_ROLE` can:

*   deposit tokens into its strategy

The `PegKeeper`'s `STABILIZE_ROLE` can:

*   swap fxUSD or USDC from the pool for the other

#### `FxUSDRegeneracy`

The `PoolManager` can:

*   mint or burn new fxUSD tokens as it handles positions in the pools

The `PegKeeper`'s `BUYBACK_ROLE` can

*   buy fxUSD with USDC

#### `PegKeeper`

The `BUYBACK_ROLE` can:

*   buy fxUSD with USDC directly from the fxUSD (`fxUSDRegeneracy`) contract

The `STABILIZE_ROLE` can:

*   swap fxUSD or USDC in the stability pool for the other

The `DEFAULT_ADMIN_ROLE` can:

*   set the address of f(x)'s `MultiPathConverter` contract (used for) swapping assets
*   set the address of the curve pool for fxUSD/USDC
*   set the price threshold where fxUSD is considered to have depegged from USDC
*   change role allocations in the contract

#### `PoolManager`

The `DEFAULT_ADMIN_ROLE` can:

*   update fee percentages, and where these fees get paid to
*   set the address of various integrated contracts, such as the reserve pool, treasury, and reward splitter
*   allocate, update, or discontinue the strategy contract for an asset
*   register new pools for users to create positions in
*   update the debt and collateral capacity for each pool
*   add or remove a scaling factor provider for any asset
*   set a threshold amount of value below which, if the stability pool falls, will allow anyone to call `rebalance` and `liquidate`
*   change role allocations in the contract

The `ASSET_MANAGER_ROLE` can:

*   deposit tokens into its strategy

The `HARVESTER_ROLE` can:

*   collect funding fees from the pools

The `EMERGENCY_ROLE` can:

*   pause or unpause all activity in the pools (i.e. operate, redeem, rebalance, & liquidate)

The stability pool allows anyone to:

*   perform rebalancing and liquidations on positions in the pools

#### `ReservePool`

The `DEFAULT_ADMIN_ROLE` can:

*   withdraw any tokens or ETH in the pool
*   change role allocations in the contract

The `PoolManager` can:

*   send funds from the reserve pool to cover undercollateralized loans or redemptions

#### `SavingFxUSD`

The `DEFAULT_ADMIN_ROLE` can:

*   update the amount of tokens the contract will hold before depositing it into a Liquidity Gauge contract
*   change role allocations in the contract

The `CLAIM_FOR_ROLE` can:

*   request redemptions for anyone

#### Oracles

The `owner` can:

*   update maximum price deviation threshold allowed from anchor price
*   update on-chain spot encodings for fetching spot prices

Critical Severity
-----------------

### Attacker can Lock User Funds through Redeem Function

The [redeem function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol#L307-L334) in the `PoolManager` contract of the protocol allows any user to burn `fxUSD` and receive collateral at a cheaper than market rate in return. The purpose of this function is to prevent depegging scenarios of the `fxUSD` stablecoin through a disincentive. During the function call, the `PoolManager` contract calls the [`redeem` function of the `BasePool` contract](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L191-L245) to calculate the collateral to be returned. This function starts liquidating from the top tick until the desired amount of `rawDebts` (fxUSD) is covered via the [`_liquidateTick` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L233). During this function call, the top tick is always shifted to a [new parent node](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/TickLogic.sol#L198) and the old node becomes its child node.

It is important to note that there is no [minimum rawDebt](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L191) (fxUSD to be burned) requirement placed in the `redeem` function. This allows an attacker to redeem small amounts of fxUSD and create multiple nodes for a tick without shifting it from the top tick and to push the positions of that tick down into a spiral of 100s to 1000s of child nodes.

Additionally, the [`operate` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L73-L188) in the `BasePool` contract always [updates the position](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L102) to the latest parent node from the current child node before any other calculations. Note that the [`_getRootNodeAndCompress` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/TickLogic.sol#L65-L85) which gets the root node for a position, is a recursive function which is easily prone to stack overflow error.

An attacker can leverage the above mentioned liquidate tick design, the missing minimum rawDebt check, and the recursion property to execute the following steps:

1.  Repeatedly call the `redeem` function with a minimal amount of rawDebt(fxUSD) to burn (For example burning 2 wei around 150 times). This ensures that the [top tick](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/TickLogic.sol#L229-L232) is never updated and 150 child nodes are created.
    
2.  Call the `redeem` function again with a calculated high amount to shift to new top tick to target more positions.
    
3.  Once the targeted tick has become the top tick again, repeat step 1.
    

Due to this mechanism, whenever the user tries to close or update one of those affected positions using the `operate` function, the `_getRootNodeAndCompress` will fail with stack overflow error as child nodes are above certain limit. This [POC](https://gist.github.com/jainil-oz/557243b7fd29cca6025bcfc85f79f21b) demonstrates the stack overflow behavior by manipulating the top tick and locking the funds of all positions corresponding to that tick. The users won't be able to close or update their positions, they can only be rebalanced or liquidated, thus their funds will get locked.

To address the underlying issue, consider migrating to a non-recursive version of the `_getRootNodeAndCompress` function. To further prevent gas griefing attacks via the `redeem` function, consider implementing additional checks such as a minimum `rawDebt` requirement to ensure that the top tick always moves, which would increase the difficulty for any attacker attempting to target a tick.

_**Update:** Resolved in [pull request #22](https://github.com/AladdinDAO/fx-protocol-contracts/pull/22)._

The team has migrated to an iterative version of the `_getRootNodeAndCompress()` function and added a minimum `rawDebts` requirement for the `redeem`, `rebalance`, and `liquidate` functionalities. An admin function has also been added to compress the node chain in case of any unintended behaviors detected through the off-chain monitoring of the tree structure.  
The f(x) Protocol team stated:

> _We have implemented the following changes in response to the observed edge cases:_
> 
> *   _**Minimum Raw Debt Threshold Added**: We have introduced a minimum raw debt requirement for `redeem`, `rebalance`, and `liquidate` operations to prevent dust-level abuse and ensure tick movement._
> *   _**Tick Movement Check**: The `redeem` function now reverts in case the tick does not move, guarding against stale state transitions._
> *   _**Path Compression Function**: We have replaced the recursive `getRootNodeAndCompress` function with a non-recursive internal version to avoid stack overflow. A `public` admin version is also available for manually compressing excessively long chains._
> 
> _The above changes improve protocol stability while retaining the ability to monitor and adapt to edge-case scenarios dynamically._

High Severity
-------------

### Flashloan Functionality is Blocked

The [`flashLoan` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FlashLoans.sol#L67-L97) of the `FlashLoans` contract uses the [`returnedAmount < amount + fee`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FlashLoans.sol#L87) condition to validate repayment. However, `returnedAmount` is [computed](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FlashLoans.sol#L86) as the post-callback balance minus the pre-loan balance, which only represents the extra tokens sent to cover fees. As a result, `returnedAmount < amount + fee` is always `true`, causing every flash loan to revert unless the borrower somehow returns the entire principal, plus fee, as the fee.

Consider changing the condition to `returnedAmount < fee` so that the function correctly enforces repayment of the fee.

_**Update:** Resolved in [pull request #17](https://github.com/AladdinDAO/fx-protocol-contracts/pull/17). This pull request fixes the issue by calculating `prevBalance` after the token transfer to the receiver. Additionally, compliance to [EIP-3156](https://eips.ethereum.org/EIPS/eip-3156) standard will be achieved once M-01 is resolved._

### Pools Can Be Subject to Price Manipulation Leading to Early Liquidations or Arbitrage

The [price oracles](https://github.com/AladdinDAO/fx-protocol-contracts/tree/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle) in the protocol are designed to fetch the prices of the collateral from the Chainlink Data feed which [acts as the `anchorPrice`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/StETHPriceOracle.sol#L36-L43) and also uses multiple on-chain pools to fetch spot prices which act as [`minPrice` and `maxPrice` of the same](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/LSDPriceOracleBase.sol#L180-L207). `minPrice` is derived by taking the lowest of all the spot prices fetched and, similarly, `maxPrice` is derived by taking the highest of the spot prices fetched.

The [`getPrice` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/LSDPriceOracleBase.sol#L85-L99) of the oracle contracts ensures that the `minPrice` and `maxPrice` values returned from the on-chain pools have not deviated from the `anchorPrice` by more than 1%. If the price has [deviated by more than 1%](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/LSDPriceOracleBase.sol#L91-L97), it resets the respective deviated `minPrice` or `maxPrice` to `anchorPrice`. The `minPrice` of the collateral is used during [operating positions](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L92), [rebalancing](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L250), and [liquidations](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L388). On the other hand, the `maxPrice` is used in the [`redeem`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L196) functionality.

However, despite the `minPrice` and `maxPrice` being allowed a deviation of 1%, only one pool is required to manipulate the price. Thus, an attacker can target the pool with the lowest TVL or a pool where manipulation can be possible in the same transaction, and manipulate the price in such a way that it causes the `anchorPrice` to deviate exactly by 1% and [bypass the deviation check](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/LSDPriceOracleBase.sol#L91-L97).

This manipulation of 1% of the prices allows malicious liquidators to lower the `minPrice` to force vulnerable positions to get liquidated early and generate more profits. Similarly, `maxPrice` can be manipulated to deviate by more than 1% and reset to `anchorPrice`, which opens up arbitrage opportunities during the `redeem` functionality.

By collapsing all spot prices into one `minPrice` and one `maxPrice`, and then forcing any outlier back to the anchor, the intended multi-pool resilience is negated. In practice, the system always falls back to either a single manipulated pool or the anchor feed. In other words, compromising just one low-TVL pool turns the “diversified” oracle into a single point of failure.

For example, the current [stETH price oracle](https://fxprotocol.gitbook.io/fx-docs/risk-management/oracle/steth) depends upon 3 pools for the ETH/USD spot price: [WETH/USDC Uniswap V2](https://app.uniswap.org/explore/pools/ethereum/0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc), [WETH/USDC Uniswap V3 0.05%](https://app.uniswap.org/explore/pools/ethereum/0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640), and [WETH/USDC Uniswap V3 0.3%](https://app.uniswap.org/explore/pools/ethereum/0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8). The attacker only needs to manipulate one of these pools, and given that the TVL of the Uniswap V2 pool currently stands at $19 million, it is easily manageable for an attacker to deviate the price by 1% and generate profit by liquidating high-value positions. The Uniswap V3 pools can also be subject to manipulation by a combination of multiple transactions.

Consider redesigning the price oracle to not be dependent upon a single spot price if possible. Alternatively, consider ensuring that the [selected pools](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/src/utils/oracle.ts), upon which spot prices are fetched, meet the minimum TVL requirement calculated based on the maximum liquidation profits possible and the fees paid to deviate the pool by 1% of the TVL.

_**Update:** Resolved. The WETH/USDC Uniswap V2 pool with low TVL will be removed. In addition, the f(x) Protocol team has implemented sufficient risk-control measures, including an in-house team to monitor the liquidity of all the pools._

The f(x) Protocol team stated:

> _The core price data used by the f(x) Protocol oracle comes from Chainlink. If the protocol goes down, the f(x) Protocol administrator needs to intervene actively and urgently stop all core functions of the f(x) Protocol, such as `operate` positions, `rebalance`, `redeem`, and `liquidate`, to avoid losses of f(x) Protocol users' assets. When the Chainlink oracle is operating normally, the protocol sets different ranges of deviation thresholds for different quoted assets._
> 
> _When the price fluctuation of the quoted asset does not exceed this range, the current quoted data is kept unchanged, which may cause a small range of price differences between the Chainlink quote and the actual market price. For operations that are very sensitive to price accuracy, such as position liquidations on the f(x) Protocol, a small range of price difference may also cause large positions to lose too much principal. As such, the data provided by Chainlink is not suitable for direct use. In order to deal with the problem of delayed Chainlink price updates, the f(x) Protocol supplements and integrates spot price data from multiple DEXs._
> 
> _Although spot prices are closer to the real-time market status, they are more likely to be manipulated. To avoid any price manipulations on DEXes, the f(x) Protocol weighs the characteristics of Chainlink's price stability and the timeliness of DEX spot prices and builds a balance mechanism, which forms the current f(x) Protocol oracle quotation rules, namely: the f(x) Protocol selects all DEX spot price data and the anchor price provided by Chainlink to obtain the maximum price data `maxPrice` and the minimum price data `minPrice`._
> 
> _If the price deviation between the maximum price data `maxPrice` (minimum price data `minPrice`) and the `anchorPrice` does not exceed the preset parameter `maxPriceDeviation`, the data is considered valid. Otherwise, the `anchorPrice` will be used as the valid data. Under the current f(x) price acquisition rules, if a malicious attacker manipulates the spot price of a DEX to deviate from the price range of the protocol preset parameter `maxPriceDeviation`, then f(x) Protocol will eventually use the more credible `anchorPrice` as the effective price._
> 
> _Compared with the best price in the current market, the pricing strategy of f(x) Protocol may cause users to lose a very small proportion of their assets when prices are manipulated or when market prices fluctuate greatly. This is similar to the inevitable slippage in AMM and is an acceptable compromise under the premise of ensuring system robustness. On the other hand, this design can greatly reduce the risk of spot price attacks and better protect the security of users' assets. Therefore, on the whole, we believe that the current pricing strategy of f(x) Protocol is in the best interests of users._
> 
> _Regarding the question "manipulating a specific pool so that its price deviates by exactly 1% from the `anchorPrice`, bypassing deviation detection, and creating arbitrage opportunities.", we analyze the functional modules that use these prices in f(x) Protocol (taking stETH assets as an example):_
> 
> _**Functional modules using `minPrice`: `operate` positions, `rebalance`, and `liquidate` operations.**_
> 
> _1\. **`operate` positions operation**: `minPrice` price data is only used to determine the value of user collateral when there is over-collateralization. Even if the attacker manipulates the minimum price to make it deviate from the `anchorPrice` by 1%, due to the existence of the over-collateralization mechanism, the price manipulation behavior of a single transaction will not have any adverse effects on the protocol._
> 
> _2\. **`rebalance` and `liquidate` operations**: From the above analysis, we can know that, in theory, it is possible to control the `minPrice` to make it deviate from the `anchorPrice` by just 1%, but in practice, attackers need to consider the difficulty and attack cost more. In most cases, f(x) Protocol performs `rebalance` and `liquidate` operations accompanied by a sharp drop in the price of the collateral asset._
> 
> _First, the spot price of each DEX fluctuates greatly at this time, and the `anchorPrice` corresponding to Chainlink also changes accordingly. It is very difficult to accurately manipulate the spot price so that the price difference between it and the `anchorPrice` is within 1% (ensuring the maximization of potential attack profits)._
> 
> _Secondly, even if the attacker happens to construct a matching `minPrice`, due to the sharp drop in the price of the collateral asset at this time, there must be a large number of swap transactions in the corresponding pool, so the 1% profit earned by the attacker is likely to be insufficient to cope with slippage, handling fees and other fees, which further compresses the arbitrage space._
> 
> _Finally, the `anchorPrice` provided by Chainlink combines the price data of various protocols or exchanges in the current market and provides the average price of the current market. The price change itself is lagging. When the price of the collateral asset falls, it is very likely that the spot price of some DEXs will differ from the `anchorPrice` by more than 1%. In this case, if the protocol directly uses the `anchorPrice`, the attack behavior will be more complicated and require additional costs (pull all pool prices exceeding 1% back to within 1%)._
> 
> _In summary, the attacker's method of manipulating the minimum price to make it deviate from the `anchorPrice` by 1% faces great difficulty, uncertainty, and high cost, and is difficult to achieve._
> 
> _**Functional module using `maxPrice`: `redeem` operation**._
> 
> _3\. In the upcoming upgraded version, the `redeem` operation will only be allowed to be executed when the fxUSD token is unpegged. Assuming that the current fxUSD is unpegged, although this situation is rare, the attacker needs to manipulate all spot prices at this time to make the spot prices that exceed the `anchorPrice` fall back to the `anchorPrice` in order to redeem the higher value collateral. Obviously, this attack requires the attacker to pay the cost of controlling multiple pools. From the final result, even if the attacker finally uses the `anchorPrice` to redeem the collateral assets, the price is still in a reasonable price range in the market, although this price is not the most favorable price for the user's position and there is no significant arbitrage space._
> 
> _Overall, the attacker's solution of manipulating a specific pool to control the spot price and bypass deviation detection to achieve the purpose of arbitrage liquidation is very difficult to implement and requires a high attack cost. In order to deal with oracle price manipulation, f(x) Protocol has introduced a series of risk control measures, from obtaining effective price solutions to real-time monitoring on the chain, such as the following:_
> 
> *   _1\. As mentioned in the question, f(x) Protocol selects the pool with good liquidity and top TVL in the current market as the spot price source for different collateral assets._
> *   _2\. For different collateral assets, f(x) Protocol combines the deviation threshold of Chainlink's `anchorPrice` and designs different preset parameters `maxPriceDeviation`._
> *   _3\. When running on the current chain, multiple watchers are added to quickly adjust user positions when the price of the mortgage asset fluctuates greatly, greatly reducing the probability of user positions being liquidated._
> 
> _Therefore, we believe that the current price mechanism of f(x) Protocol has achieved a reasonable trade-off between anti-manipulation and market reflection, which is in the best interests of users. And, in the meantime, we have an in-house team that is monitoring the liquidity of all pools and will remove pools with small liquidity._
> 
> _At the end, we would like to present the rationale behind our current oracle design:_
> 
> *   _**Anchor Price from Chainlink**: Serves as the base for all comparisons._
> *   _**Deviation Thresholds**: Each asset has a max price deviation (e.g., 1% for stETH, 2% for WBTC). If spot prices stay within this deviation from the anchor, they are accepted; otherwise, the system falls back to `anchorPrice`._
> *   _**Spot Price Aggregation**: Spot prices are collected from multiple high-liquidity DEX pools to reduce manipulation exposure._
> 
> _**Key Mitigation Points**:_
> 
> *   _If an attacker manipulates a single DEX pool beyond the deviation threshold, its price is ignored._
> *   _The use of `minPrice` for liquidation and `maxPrice` for redemption ensures a defensible balance between reactivity and manipulation resistance._
> *   _`redeem` is only enabled off-peg, and even then, arbitrage is economically infeasible._
> *   _The WETH/USDC Uniswap V2 pool with low TVL has been removed._
> *   _All spot sources are selected for depth and reliability, and additional on-chain watchers assist with fast-moving markets._
> 
> _We believe that this approach achieves a strong trade-off between market responsiveness and security._

Medium Severity
---------------

### Flashloan Functionality Does Not Follow ERC-3156 Standard

[ERC-3156](https://eips.ethereum.org/EIPS/eip-3156) specifies:

> _After the callback, the `flashLoan` function MUST take the amount + fee token from the receiver, or revert if this is not successful._

Instead of taking the token, [`flashLoan`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FlashLoans.sol#L86) expects the caller to have returned the tokens. This will stop the contract from integrating with any compliant `IERC3156FlashBorrower` contracts as they will not return the tokens to the contract here.

[ERC-3156](https://eips.ethereum.org/EIPS/eip-3156) further specifies:

> _The `flashFee` function MUST return the fee charged for a loan of amount token. If the token is not supported `flashFee` MUST revert._

The use of the word "supported" is ambiguous here, in that it does not specify that a maximum loan amount of zero means that a token is "unsupported." However, the ERC does conflate returning zero in `maxFlashLoan` to mean that a token is unsupported. Therefore, in situations where `maxFlashLoan` will return zero, `flashFee` must revert. Currently, the function simply [calculates a fraction of the amount given](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FlashLoans.sol#L59), regardless of the token.

Consider fixing the `flashLoan` and `flashFee` functions to be compliant with ERC-3156 as described above.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Redemption Waiting Can Be Gamed

The [`requestRedeem` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L315-L325) of the `FxUSDBasePool` contract registers a redeem request from a user. Once the `redeemCoolDownPeriod` period has passed, the user can redeem that amount of fxBASE token and get back fxUSD and USDC as per the ratio in the pool. The motivation for this functionality is to avoid high levels of redemption causing a run on the stability pool.

However, there is no expiry of the redemption request made by the user. A user can deposit in the pool and immediately call the `requestRedeem` function to register their request to redeem. Afterward, they redeem at any time once the cool-down period has expired. This would make the redemption request functionality useless.

Consider adding an expiration time for the redemption requests. After this time, redeeming should not be allowed and the user should have to request a redemption again.

_**Update:** Acknowledged, not resolved. The f(x) Protocol team stated:_

> _The current redemption design prevents deposit and redeem from happening in the same block. As long as the `redeemCoolDownPeriod` is non-zero, users must wait before redeeming, which acts as a sufficient deterrent to immediate arbitrage. Therefore, we do not believe any further changes are required at this time._

### Pool at Capacity Cannot Be Liquidated

Each pool in the `PoolManager` contract has a maximum capacity of collateral that it can hold. The `_changePoolCollateral` function [reverts if the change surpasses the capacity](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol#L688). When a tick has bad debt, the protocol uses funds from the `ReservePool` contract to cover the uncollateralized part of the debt to be able to facilitate the liquidation.

When a pool is liquidated through the [`liquidate` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol#L386) of the `PoolManager` contract, the funds pulled from the reserve are [added to the current pool's collateral amount](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol#L416). If the sum of the funds from the reserve and the current balance surpasses the capacity (i.e., capacity<bonusFromReserve+balancecapacity < bonusFromReserve + balance), the liquidation will fail.

Consider adding the reserve's funds to the pool collateral variables after the liquidation collateral has been subtracted.

_**Update:** Acknowledged, not resolved. The f(x) Protocol team stated:_

> _The case is rare, and given the low likelihood of it occurring in practice, we have opted not to make any changes at this time. The current implementation maintains simpler and more predictable behavior, and modifying the reserve collateral logic could introduce unnecessary complexity for an edge case that has minimal user impact._

### Stale Value of `totalStableToken` Used in Stability Pool

The [sync modifier](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L165-L174) updates the `totalStableToken` variable to the latest value in case the stable token has been deposited into a strategy and is generating yield. All external functionalities such as `deposit`, `redeem`, etc. update this `totalStableToken` variable using the `sync` modifier before proceeding further.

However, the [previewDeposit](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L226), [previewRedeem](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L246), and [nav](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L257) functions of the FxUSDStabilityPool contract use a stale value of `totalStableToken` variable, which could lead to incorrect return values from these `view` functions. For example, to protect against inflation attacks, `previewDeposit` could end up returning more shares than what the user had specified as [`minSharesOut` during deposit](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L307), causing it to revert.

Consider modifying the functions to calculate the latest value of `totalStableToken`.

_**Update:** Resolved in [pull request #21](https://github.com/AladdinDAO/fx-protocol-contracts/pull/21)._

The ERC-4626 Vault contract uses the [\_decimalsOffset](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/08566bfe0d19384af30a70815251fa913a19678b/contracts/token/ERC20/extensions/ERC4626.sol#L279-L281) function to add more precision to share values. The issue is that the value returned by `_decimalsOffset` is 0 if the underlying token has 18 decimals (which is the case for most tokens, including fxBASE).

Since the [`totalAssets` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/SavingFxUSD.sol#L154-L156) is dependent upon `balanceOf(address(this))`, when `totalSupply` is 0, an attacker can mint 10 shares for 10 wei of fxBASE, and then donate 100e18 fxBASE tokens directly to the contract to inflate the price-per-share of fxSAVE. When a user deposits 1e18 worth of shares, they will get 0 shares in return, whereas the attacker may only lose 1e17 shares. It can be observed that the attacker can lock 1e18 of a user's assets at the cost of ~1e17 fxBASE tokens.

Since the pool is already deployed, the likelihood of this attack vector materializing is quite low. Nonetheless, consider sending some fxSAVE tokens to a dead address to ensure that the `totalSupply` of fxSAVE is never 0.

_**Update:** Acknowledged, not resolved. The f(x) Protocol team stated:_

> _This issue was only relevant during the launch phase. Our production deployment of the fxSAVE token included a guarded launch mechanism which ensured that the total supply was never zero at runtime. Therefore, we consider this issue effectively mitigated in practice._

### Minimum Price Deviation Is Calculated Incorrectly in Price Oracles

The [`getPrice()` function of `ETHPriceOracle`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/ETHPriceOracle.sol#L61-L74), [the `getPrice()` function of `LSDPriceOracleBase`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/LSDPriceOracleBase.sol#L85-L99), [the `getPrice()` and `getExchangePrice()` functions of `BTCDerivativeOracleBase`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/BTCDerivativeOracleBase.sol#L58-L72), all calculate the minimum price deviation by using the `(anchorPrice - minPrice) / minPrice > maxDeviation` formula. If the deviation is higher than the max deviation allowed, the minimum price is reset to the anchor price.

However, this calculation is incorrect. It checks the deviation from `minPrice` which makes deviation restrictive and causes it to always be less than the max deviation allowed from the anchor price. The correct formula is to check the deviation against `anchorPrice` instead of `minPrice`: `(anchorPrice - minPrice) / anchorPrice > maxDeviation`.

When calculating the minimum price deviation, consider checking the deviation against `anchorPrice` instead of `minPrice`.

_**Update:** Resolved in [pull request #20](https://github.com/AladdinDAO/fx-protocol-contracts/pull/20)._

### Users Can Open Null Positions

The [`operate` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol#L259-L264) in `PoolManager` contract allows any user to open, close or update their positions. If a user wants to close their position, they can simply use the minimum amount of `int256` (i.e. [`type(int256).min` parameter for `newDebt` and `newColl`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L128-L157)) while providing their `positionId` parameter. If the `positionId` parameter is 0 then it's considered a new position to be opened.

However, it is observed that users that have no positions created, can call the `operate` function with the `type(int256).min` parameter for both `newDebt` and `newColl` with `positionId` = 0 and mint null positions with latest `positionId`. This could create ambiguity for off-chain analysis due to event spamming. This is not an ideal behavior as protocol fees are also not charged for opening such positions.

Consider adding a further check in the `operate` function to avoid null positions being minted.

Update: Acknowledged, not resolved. The f(x) Protocol team stated:

> _We acknowledge the issue where users can trigger the operate function with `type(int256).min` values for both `newDebt` and `newColl` with `positionId = 0`, resulting in a “null” position being minted. While this behavior does not pose any functional or economic risk to the protocol (no collateral, no debt, no system impact), we agree it may cause off-chain event noise or indexing ambiguity._
> 
> _Resolution Approach:_
> 
> *   _The current implementation does not charge protocol fees for zero-value operations._
>     
> *   _To maintain clean off-chain indexing and avoid unnecessary event spam, we plan to implement a filter that rejects no-op state transitions (i.e., zero collateral and zero debt for new positions) in a future release._
>     
> 
> _\_This is a non-critical UX-level issue with no impact on funds or protocol logic, but we value the feedback and will improve clarity for integrators and indexers._

Low Severity
------------

### Missing L2 Sequencer Uptime Checks

If an L2 sequencer goes offline, users will lose access to read/write APIs, effectively rendering applications on the L2 network unusable—unless they interact directly through L1 optimistic rollup contracts.

While the L2 itself may still be operational, continuing to serve applications in this state would be unfair, as only a small subset of users could interact with them. To prevent this, [Chainlink recommends](https://docs.chain.link/data-feeds/l2-sequencer-feeds) integrating their Sequencer Uptime Feeds into any project deployed on an L2. These feeds help detect sequencer downtime, allowing applications to respond appropriately.

Several oracle calls in the codebase may return inaccurate data during sequencer downtime, including:

*   The [`AggregatorV3Interface(aggregator).latestRoundData`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L279) call in `FxUSDBasePool.sol`
*   The [`AggregatorV3Interface(aggregator).latestRoundData`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/SpotPriceOracleBase.sol#L59) call in `SpotPriceOracleBase.sol`

To help your applications while deploying on `Base` chain identify when the sequencer is unavailable, you can use a data feed that tracks the last known status of the sequencer at a given point in time.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Strategy Allocation Could Fail

The [`alloc` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L40) of the `AssetManagement` contract does not verify whether the strategy supports the specified token. In the case of `AaveV3Strategy`, any unknown tokens sent to it will not be recoverable because [`withdraw()`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol#L53) and [`kill()`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol#L63) can only interact with the token specified in `ASSET`.

Consider checking whether the strategy's `ASSET` is the same as the `asset` in `alloc()`.

_**Update:** Acknowledged, not resolved. The f(x) Protocol team stated:_

> _Strategy allocation is currently controlled by a multisig governance process. Execution is carefully reviewed before approval. Looking forward, as the protocol transitions to fully on-chain governance, we will enhance strategy validation logic to make such failures structurally impossible._

### Incorrect Strategy for an Asset can be Never Be Updated

In the [`alloc` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L40-L44) of the `AssetManagement` contract, there is no validation whether the new strategy address is valid and supports `kill()` function. Once an incorrect address is set, both the [`kill()` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L33) and [`alloc()` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L42) to update the strategy will revert due to this `Strategy.kill()` not being supported.

Consider adding proper validation on added strategy addresses during `alloc()` function or allow the replacement of strategies without a call to `kill`.

_**Update:** Acknowledged, not resolved. The f(x) Protocol team stated:_

> _This issue shares the same category as L-02. Currently, updates to strategy allocation are gated by multisig and are reviewed carefully before execution. In the future, on-chain governance enhancements will introduce stricter validation logic, improving upgrade safety and modularity._

### Minimum Debt Requirement for a Position Is Not Enforced Correctly

In the `operate` function of `BasePool` contract, the [`newRawDebt` value is required to be greater than `MIN_DEBT`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L83) which is 1e9. `newRawDebt` is then [converted to debt shares](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L148), which divides the `rawDebt` with `debtIndex`, resulting in a value that is less than 1e9 minimum debt shares requirement.

However, while [adding this position to a tick](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L176), the function again checks for `MIN_DEBT` requirement of 1e9 against the `debtShares`, which will revert the function call. Hence, users will not be able to open a position with an amount greater than `MIN_DEBT` until the converted `debtShares` are strictly higher than 1e9. Thus, as time passes, `debtIndex` will increase, causing the actual minimum debt requirement to increase as well.

Consider converting `MIN_DEBT` into a `MIN_SHARES` requirement that uses the debt index in `_addPositionToTick`. Alternatively, consider checking for the `MIN_DEBT` requirement immediately before the call to `_addPositionToTick` with the `rawDebts` variable is made, and removing the check within the function.

_**Update:** Acknowledged, not resolved. The f(x) Protocol team stated:_

> _We acknowledge the observation. The current `MIN_DEBT` check is intentionally minimal and only used to avoid edge-case tick computation errors. Based on its functional intent and low impact, we believe that the current implementation is sufficient._

### Different Pragma Directives

In order to clearly identify the Solidity version with which the contracts will be compiled, pragma directives should be fixed and consistent across file imports.

No file in scope uses a fixed Solidity version and many of them differ in the versions they use. As such, consider using the same, fixed pragma version in all the files.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Misleading Return Value in `_takeAccumulatedPoolFee`

The [`_takeAccumulatedPoolFee`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L441-L458) function of the `ProtocolFees` contract returns a `fees` variable that is overwritten three times: first by `accumulatedPoolOpenFees`, then by `accumulatedPoolCloseFees`, and finally by `accumulatedPoolMiscFees`. As a result, the returned value only reflects the last category. In addition, no internal or external caller ever uses this return value, making it meaningless and potentially confusing.

Consider removing the unused return value to improve the clarity and maintainability of the codebase.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Inconsistent Sanity Checks for On-Chain Spot Encodings in Oracle Contracts

The `updateOnchainSpotEncodings` setter function should validate its inputs. However, the non‑empty check is only performed in some oracles:

*   [`BTCDerivativeOracleBase.updateOnchainSpotEncodings`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/BTCDerivativeOracleBase.sol#L111) reverts when `prices.length == 0`.
*   [`ETHPriceOracle.updateOnchainSpotEncodings`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/ETHPriceOracle.sol#L108-L110) has no check on `prices.length`.
*   [`LSDPriceOracleBase.updateOnchainSpotEncodings`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/LSDPriceOracleBase.sol#L131) applies the check only for one `spotType`.

This inconsistency allows empty or malformed encodings to be set, which can lead to read functions reverting or returning invalid data.

Consider adding a uniform sanity check in every `updateOnchainSpotEncodings` implementation to ensure data integrity across all oracles.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Possible Duplicate Event Emissions

When a setter function does not check if the value being set is different from the existing one, it becomes possible to set the same value repeatedly, creating the possibility for event spamming. Repeated emission of identical events can also confuse off-chain clients.

Throughout the codebase, multiple instances of such possibilities were identified:

*   The [`_updateRedeemCoolDownPeriod`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L565-L572) sets the `redeemCoolDownPeriod` and emits an event without checking if the value has changed.
*   The [`_updateInstantRedeemFeeRatio`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L576-L583) sets the `instantRedeemFeeRatio` and emits an event without checking if the value has changed.
*   The [`_updateConverter`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PegKeeper.sol#L193-L200) sets the `converter` and emits an event without checking if the value has changed.
*   The [`_updateCurvePool`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PegKeeper.sol#L204-L211) sets the `curvePool` and emits an event without checking if the value has changed.
*   The [`_updatePriceThreshold`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PegKeeper.sol#L215-L220) sets the `priceThreshold` and emits an event without checking if the value has changed.
*   The [`_updateThreshold`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol#L600-L605) sets the `permissionedLiquidationThreshold` and emits an event without checking if the value has changed.
*   The [`_updatePriceOracle`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolStorage.sol#L245-L252) sets the `priceOracle` and emits an event without checking if the value has changed.
*   The [`_updateTreasury`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L275-L282) sets the `treasury` and emits an event without checking if the value has changed.
*   The [`_updateOpenRevenuePool`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L286-L293) sets the `openRevenuePool` and emits an event without checking if the value has changed.
*   The [`_updateCloseRevenuePool`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L297-L304) sets the `closeRevenuePool` and emits an event without checking if the value has changed.
*   The [`_updateMiscRevenuePool`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L308-L315) sets the `miscRevenuePool` and emits an event without checking if the value has changed.
*   The [`_updateReservePool`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L319-L326) sets the `reservePool` and emits an event without checking if the value has changed.

Consider adding a check that reverts the transaction if the value being set is the same as the existing one.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Inheritance Correctness

The `ProtocolFees` contract inherits the `PausableUpgradeable` contract, but does not implement any pause functionality. `ProtocolFees` is then inherited by the `FlashLoans` and `PoolManager` contracts that do implement pause functionality. Furthermore, throughout the codebase, it appears that the intention of the developers was to inherit interfaces for implementing contracts. For example, `AaveFundingPool` inherits `IAaveFundingPool` and `IPool`, `ETHPriceOracle` inherits `IPriceOracle`, etc. However, the `AaveV3Strategy` contract does not inherit the `IStrategy` interface and thus breaks the apparent convention.

Consider having `StrategyBase` inherit `IStrategy` and having `FlashLoans` inherit `PausableUpgradeable` while removing it from `ProtocolFees`.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Gap Variables Allow Future Storage Collision

Within the codebase, multiple instances of contracts utilizing gap variables were identified:

*   [ProtocolFees](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L464)
*   [BasePool](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L619)
*   [PoolStorage](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolStorage.sol#L470)
*   [PositionLogic](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PositionLogic.sol#L139)
*   [TickLogic](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/TickLogic.sol#L251)
*   [AssetManagement](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L28)
*   [StrategyBase](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/StrategyBase.sol#L16)

Gap variables allow inherited contracts to expand their storage in the future without it colliding with the storage of the inheriting contracts. Since the codebase is already in production, it is important to ensure that any storage changes are reflected in the gap variables.

To better mitigate the risk of storage collision in upgradeable contracts for new deployments, consider utilizing [namespace storage](https://eips.ethereum.org/EIPS/eip-7201) or using the custom storage layout that became available in [Solitidy version 0.8.29](https://soliditylang.org/blog/2025/03/12/solidity-0.8.29-release-announcement/).

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the theoretical risk of future storage layout collision due to unstructured gap variables. However, the affected contracts are already deployed, and altering the storage layout would pose significant risk to data integrity and contract behavior. Going forward, we plan to adopt name-spaced storage techniques or structured layout support introduced in Solidity 0.8.29+ to mitigate such risks in future iterations._

### Usage of Transient Storage can Lower Gas Costs

PegKeeper sets a storage variable `context` when its `buyback` and `stabilize` functions are called and restores it when those calls are done. The contract uses this variable to ensure that the `onSwap` function is being called in the context of the other functions. This is precisely one of the use cases for [transient storage](https://eips.ethereum.org/EIPS/eip-1153), which became available in [Solidity in version 0.8.24](https://soliditylang.org/blog/2024/01/26/transient-storage/).

In order to save gas on these calls, consider setting the context in transient storage rather than in permanent storage.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Missing Docstrings

Throughout the codebase, multiple instances of missing docstrings were identified:

*   All contract and interface definitions. For example, the [`AaveFundingPool` contract](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/AaveFundingPool.sol#L13) should have NatSpec comments above it.
*   In `AaveFundingPool.sol`, the [`initialize` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/AaveFundingPool.sol#L101-L126)
*   In `AaveV3Strategy.sol`, the [`POOL`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol#L16), [`INCENTIVE`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol#L18), [`ASSET`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol#L20), [`ATOKEN`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol#L22), and [`principal`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol#L24) state variables along with the [`totalSupply`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol#L42-L44), [`deposit`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol#L46-L51), [`withdraw`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol#L53-L60), and [`kill`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol#L62-L67) functions
*   In `AssetManagement.sol`, the [`ASSET_MANAGER_ROLE`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L15) and [`allocations`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L22) state variables along with the [`kill`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L30-L38), [`alloc`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L40-L44), and [`manage`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L46-L52) functions.
*   In `FxUSDBasePool.sol`, the [`initialize`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L196-L219) and [`updateInstantRedeemFeeRatio`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L535-L537) functions
*   In `FxUSDRegeneracy.sol`, the [`initialize`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDRegeneracy.sol#L150-L158) and [`initializeV2`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDRegeneracy.sol#L160-L163) functions
*   In `IStrategy.sol`, the [`totalSupply`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/IStrategy.sol#L6), [`deposit`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/IStrategy.sol#L8), [`withdraw`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/IStrategy.sol#L10), [`kill`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/IStrategy.sol#L12), and [`harvest`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/IStrategy.sol#L14) functions
*   In `PegKeeper.sol`, the [`initialize`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PegKeeper.sol#L96-L108) function
*   In `PoolManager.sol`, the [`initialize`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol#L184-L204) and [`initializeV2`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol#L206-L219) functions
*   In `ReservePool.sol`, the [`receive` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ReservePool.sol#L69)
*   In `SavingFxUSD.sol`, the [`execute`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/SavingFxUSD.sol#L34-L48) and [`initialize`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/SavingFxUSD.sol#L125-L142) functions
*   In `StrategyBase.sol`, the [`HARVESTER_ROLE`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/StrategyBase.sol#L8) and [`operator`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/StrategyBase.sol#L10) state variables, as well as the [`harvest`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/StrategyBase.sol#L29-L31) and [`execute`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/StrategyBase.sol#L33-L39) functions

Consider thoroughly documenting all functions (and their parameters) that are part of any contract's public API. Functions implementing sensitive functionality, even if not public, should be clearly documented as well. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Incomplete Docstrings

Throughout the codebase, multiple instances of incomplete docstrings were identified:

*   In `BTCDerivativeOracleBase.sol`, the `isRedeem` parameter of the [`getBTCDerivativeUSDAnchorPrice`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/BTCDerivativeOracleBase.sol#L52-L54) function is not documented.
*   In `PoolManager.sol`, the `collateralCapacity` and `debtCapacity` parameters of the [`registerPool`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol#L515-L529) function are not documented.
*   In `ReservePool.sol`, the `amount` parameter of the [`withdrawFund`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ReservePool.sol#L94-L96) function is not documented.

Consider thoroughly documenting all functions/events (and their parameters or return values) that are part of a contract's public API. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

Notes & Additional Information
------------------------------

### Misleading Storage Description

Several storage slots are documented in a way that could lead to confusion. For example, in the `ProtocolFees` contract, the comments above [`_miscData`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L92-L96) show the components of the slot being laid out with the zero index on the left whereas, the prevailing convention is to show slots with the zero index on the right. This confusion is compounded by the designation of the left side as the most significant bits (MSB), which is correct under the standard convention but incorrect if the layout is reversed.

Throughout the codebase, multiple instances of such misleading storage-slot descriptions were identified:

*   [`miscData`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolStorage.sol#L105-L109), [`rebalanceRatioData`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolStorage.sol#L117-L121), [`indexData`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolStorage.sol#L127-L131), [`shareData`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolStorage.sol#L139-L143), and [`positionMetadata`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolStorage.sol#L148-L152) in the `PoolStorage` contract
*   [`_miscData`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L92-L96) in the `ProtocolFees` contract
*   [`fundingMiscData`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/AaveFundingPool.sol#L81-L85) in the `AaveFundingPool` contract

To avoid confusion, consider either reversing the storage depiction so that index 0 starts on the right (aligning with Solidity conventions) or swapping the positions of the most and least significant bits in the comments to match the current left-to-right depiction.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Lack of event emissions

Throughout the codebase, multiple instances of functions updating the state without an event emission were identified:

*   The [kill](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L30-L38), [alloc](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L40-L44), and [manage](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L46-L52) functions in `AssetManagement.sol`
*   The [updateOnchainSpotEncodings function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/BTCDerivativeOracleBase.sol#L108-L114) in `BTCDerivativeOracleBase.sol`
*   The [updateOnchainSpotEncodings function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/LSDPriceOracleBase.sol#L125-L137) in `LSDPriceOracleBase.sol`

Consider emitting events whenever state changes are performed in these functions for improved transparency and better monitoring capabilities.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Silent Shortfall in `_transferOut`

The [`_transferOut`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L57-L68) function of the `AssetManagement` contract is meant to transfer a precise amount of assets to the receiver, falling back to the associated strategy if the contract holds insufficient balance. It first sends its on‑hand tokens and then calls the strategy’s [`withdraw`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L63) function for the shortfall.

However, in the `AaveV3Strategy` contract, the [`withdraw`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol#L55) function does not revert when asked to withdraw more than the strategy’s available liquidity. Instead, it simply withdraws as much as possible. As a result, `_transferOut` may complete without error while transferring less than the intended amount, violating the expectation that it either succeeds fully or reverts.

Consider adding a post‑withdraw sanity check in the `_transferOut` function to verify that the full amount was transferred and reverting otherwise.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

Through the codebase, multiple instances of incorrect or inaccurate comments were identified:

*   The comment `“The price is valid iff |maxPrice‑minPrice|/minPrice < maxPriceDeviation”` in [`BTCDerivativeOracleBase`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/BTCDerivativeOracleBase.sol#L57), [`ETHPriceOracle`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/ETHPriceOracle.sol#L60), and [`LSDPriceOracleBase`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/[LSDPriceOracleBase](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/LSDPriceOracleBase.sol#L71).sol#L8) does not align the code, which actually uses `< 2 * maxPriceDeviation`.
*   In [`LSDPriceOracleBase`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/LSDPriceOracleBase.sol#L71), a comment refers to the LSD/ETH pair, whereas, it should state LSD/USD.

Consider correcting the above-mentioned comments to improve the clarity and readability of the codebase.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Hardcoded Addresses

In the `SavingFxUSD.sol` file, multiple instances of hardcoded addresses were identified:

*   The [`0xAffe966B27ba3E4Ebb8A0eC124C7b7019CC762f8`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/SavingFxUSD.sol#L70) value
*   The [`0x365AccFCa291e7D3914637ABf1F7635dB165Bb09`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/SavingFxUSD.sol#L73) value

Consider declaring hardcoded addresses as `immutable` variables and initializing them through constructor arguments. This allows code to remain the same across deployments on different networks and mitigates situations where contracts need to be redeployed due to having incorrect hardcoded addresses.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Use `calldata` Instead of `memory`

When dealing with the parameters of `external` functions, it is more gas-efficient to read their arguments directly from `calldata` instead of storing them to `memory`. `calldata` is a read-only region of memory that contains the arguments of incoming `external` function calls. This makes using `calldata` as the data location for such parameters cheaper and more efficient compared to `memory`. Thus, using `calldata` in such situations will generally save gas and improve the performance of a smart contract.

Throughout the codebase, multiple instances where function parameters should use `calldata` instead of `memory` were identified:

*   In `AaveFundingPool.sol`, the [`name_`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/AaveFundingPool.sol#L103) parameter
*   In `AaveFundingPool.sol`, the [`symbol_`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/AaveFundingPool.sol#L104) parameter
*   In `BTCDerivativeOracleBase.sol`, the [`encodings`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/BTCDerivativeOracleBase.sol#L108) parameter
*   In `ETHPriceOracle.sol`, the [`encodings`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/ETHPriceOracle.sol#L99) parameter
*   In `FxUSDBasePool.sol`, the [`_name`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L198) parameter
*   In `FxUSDBasePool.sol`, the [`_symbol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L199) parameter
*   In `FxUSDRegeneracy.sol`, the [`_name`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDRegeneracy.sol#L150) parameter
*   In `FxUSDRegeneracy.sol`, the [`_symbol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDRegeneracy.sol#L150) parameter
*   In `FxUSDRegeneracy.sol`, the [`_minOuts`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDRegeneracy.sol#L324) parameter
*   In `LSDPriceOracleBase.sol`, the [`encodings`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/LSDPriceOracleBase.sol#L125) parameter
*   In `ProtocolFees.sol`, the [`pools`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L197) parameter
*   In `SavingFxUSD.sol`, the [`params`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/SavingFxUSD.sol#L125) parameter

Consider using `calldata` as the data location for the parameters of `external` functions to optimize gas usage.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Use Custom Errors

Since Solidity version 0.8.4, custom errors provide a cleaner and more cost-efficient way to explain to users why an operation failed.

Throughout the codebase, instances of `revert` were identified in the following contracts:

| Contract | Instances |
| --- | --- |
| `FxUSDBasePool` | 2 |
| `FxUSDRegeneracy` | 4 |
| `SavingFxUSD` | 1 |
| `AssetManagement` | 2 |
| `StrategyBase` | 1 |
| `BTCDerivativeOracleBase` | 1 |
| `SpotPriceOracleBase` | 2 |

Many of these instances were reverts with [non-descriptive messages](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L49). For conciseness, clarity, and gas savings, consider replacing these `revert` messages with custom errors.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Unnecessary Casts

Within `ProtocolFees.sol`, multiple instances of unnecessary casts were identified:

*   The [`uint256(newRatio)` cast](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L331)
*   The [`uint256(newRatio)` cast](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L345)
*   The [`uint256(newRatio)` cast](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L359)
*   The [`uint256(newRatio)` cast](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L373)
*   The [`uint256(newRatio)` cast](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L387)
*   The [`uint256(newRatio)` cast](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L401)

To improve the overall clarity and intent of the codebase, consider removing any unnecessary casts.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Inconsistent Order Within Contracts

Throughout the codebase, the majority of the scoped contracts have an inconsistent ordering of functions.

*   The [`AaveFundingPool` contract in `AaveFundingPool.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/AaveFundingPool.sol)
*   The [`AaveV3Strategy` contract in `AaveV3Strategy.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol)
*   The [`AssetManagement` contract in `AssetManagement.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol)
*   The [`BTCDerivativeOracleBase` contract in `BTCDerivativeOracleBase.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/BTCDerivativeOracleBase.sol)
*   The [`BasePool` contract in `BasePool.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol)
*   The [`ETHPriceOracle` contract in `ETHPriceOracle.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/ETHPriceOracle.sol)
*   The [`FlashLoans` contract in `FlashLoans.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FlashLoans.sol)
*   The [`FxUSDBasePool` contract in `FxUSDBasePool.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol)
*   The [`FxUSDRegeneracy` contract in `FxUSDRegeneracy.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDRegeneracy.sol)
*   The [`LSDPriceOracleBase` contract in `LSDPriceOracleBase.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/LSDPriceOracleBase.sol)
*   The [`PegKeeper` contract in `PegKeeper.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PegKeeper.sol)
*   The [`PoolManager` contract in `PoolManager.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol)
*   The [`PoolStorage` contract in `PoolStorage.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolStorage.sol)
*   The [`PositionLogic` contract in `PositionLogic.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PositionLogic.sol)
*   The [`ProtocolFees` contract in `ProtocolFees.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol)
*   The [`ReservePool` contract in `ReservePool.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ReservePool.sol)
*   The [`SavingFxUSD` contract in `SavingFxUSD.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/SavingFxUSD.sol)
*   The [`SpotPriceOracleBase` contract in `SpotPriceOracleBase.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/SpotPriceOracleBase.sol)
*   The [`StrategyBase` contract in `StrategyBase.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/StrategyBase.sol)
*   The [`WBTCPriceOracle` contract in `WBTCPriceOracle.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/WBTCPriceOracle.sol)

To improve the project's overall legibility, consider standardizing ordering throughout the codebase as recommended by the [Solidity Style Guide's Layout and Order of Functions](https://docs.soliditylang.org/en/latest/style-guide.html).

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Prefix Increment Operator (`++i`) Can Save Gas in Loops

Throughout the codebase, multiple opportunities for optimizing loop iteration were identified:

*   [BTCDerivativeOracleBase](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/BTCDerivativeOracleBase.sol#L150) (1)
*   [ETHPriceOracle](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/ETHPriceOracle.sol#L137) (1)
*   [FxUSDRegeneracy](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDRegeneracy.sol#L193) (6)
*   [LSDPriceOracleBase](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/LSDPriceOracleBase.sol#L170) (3)
*   [SpotPriceOracleBase](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/SpotPriceOracleBase.sol#L88) (1)

Consider using the prefix-increment operator (`++i`) instead of the postfix-increment operator (`i++`) in order to save gas. This optimization skips storing the value before the incremental operation, as the return value of the expression is ignored.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Unused Imports

Throughout the codebase, multiple instances of unused imports were identified

*   The import [`import { ITwapOracle } from "./interfaces/ITwapOracle.sol";`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/ETHPriceOracle.sol#L10) imports unused alias `ITwapOracle` in `ETHPriceOracle.sol`
*   The import [`import { ITwapOracle } from "./interfaces/ITwapOracle.sol";`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/LSDPriceOracleBase.sol#L10) imports unused alias `ITwapOracle` in `LSDPriceOracleBase.sol`

Consider removing unused imports to improve the overall clarity and readability of the codebase.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### State Variable Visibility Not Explicitly Declared

Throughout the codebase, multiple instances of state variables lacking an explicitly declared visibility were identified:

*   In SavingFxUSD.sol, the [`fxSAVE` state variable](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/SavingFxUSD.sol#L26)
*   In SpotPriceOracleBase.sol, the [`spotPriceOracle` state variable](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/price-oracle/SpotPriceOracleBase.sol#L30)

For improved code clarity, consider always explicitly declaring the visibility of state variables, even when the default visibility matches the intended visibility.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Unused Named Return Variables

Named return variables are a way to declare variables that are meant to be used within a function's body for the purpose of being returned as that function's output. They are an alternative to explicit in-line `return` statements.

Throughout the codebase, multiple instances of unused named return variables were identified:

*   In `AaveFundingPool.sol`, the [`ratio` and `step` return variables](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/AaveFundingPool.sol#L135) of the `getOpenRatio` function
*   In `PositionLogic.sol`, the [`debtRatio` return variable](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PositionLogic.sol#L46) of the `getPositionDebtRatio` function

Consider removing these unused named return variables unless they should be used.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Unused Errors

Throughout the codebase, multiple instances of unused errors were identified:

*   The [`ErrorRebalanceOnLiquidatablePosition` error](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolErrors.sol#L57) in `PoolErrors.sol`
*   The [`ErrorInsufficientCollateralToLiquidate` error](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolErrors.sol#L59) in `PoolErrors.sol`
*   The [`ErrorRatioTooLarge` error](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ReservePool.sol#L23) in `ReservePool.sol`
*   The [`ErrorRebalancePoolAlreadyAdded` error](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ReservePool.sol#L26) in `ReservePool.sol`
*   The [`ErrorRebalancePoolNotAdded` error](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ReservePool.sol#L29) in `ReservePool.sol`

To improve the overall clarity, intentionality, and readability of the codebase, consider either using or removing any currently unused errors.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Inconsistent usage of `msg.sender`

A contract may use the `_msgSender` and `_msgData` functions in certain cases where they allow meta transactions and have overridden these methods to extract the original message `sender/data`. Consistent use of `_msgSender/msg.sender` and `_msgData/msg.data` within a contract should be manually checked. This is because any inconsistency may be an error and could have unintended consequences for executing meta transactions.

In the [`onlyOperator`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/StrategyBase.sol#L19) modifier of the `StrategyBase` contract, `msg.sender` is being used instead of `_msgSender`.

Consider manually checking for any inconsistent usage of `msg.sender` and `msg.data`, and updating such instances to follow a consistent behavior throughout the codebase.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Unused Constants

Throughout the codebase, multiple instances of unused constants were identified:

*   In `AaveFundingPool.sol`, the [INTEREST\_RATE\_OFFSET constant](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/AaveFundingPool.sol#L33)
*   In `AaveFundingPool.sol`, the [TIMESTAMP\_OFFSET constant](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/AaveFundingPool.sol#L36)
*   In `PoolConstant.sol`, the [X60 constant](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolConstant.sol#L31)
*   In `PoolConstant.sol`, the [X96 constant](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolConstant.sol#L32)

To improve the overall clarity and intent of the codebase, consider removing unused constants.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Literal Number Safety

Throughout the codebase, multiple instances of literal numbers being used directly were identified:

*   The [`50000000000000000`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/AaveFundingPool.sol#L120) literal number in `AaveFundingPool.sol`
*   The [`500000000000000000`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/BasePool.sol#L64) literal number in `BasePool.sol`
*   The [`995000000000000000`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PegKeeper.sol#L105) literal number in `PegKeeper.sol`

For literal numbers with this many digits, consider using [Ether Suffix](https://docs.soliditylang.org/en/latest/units-and-global-variables.html#ether-units), [Time Suffix](https://docs.soliditylang.org/en/latest/units-and-global-variables.html#time-units), or [Scientific Notation](https://docs.soliditylang.org/en/latest/types.html#rational-and-integer-literals). This will help improve readability and prevent misleading code that could have unintended consequences.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Magic Numbers

In the `initialize` function of the `AaveFundingPool` contract, a literal value (1e9) with unexplained meaning [is being used](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/AaveFundingPool.sol#L125).

Consider defining and using `constant` variables instead of using literals to improve the readability of the codebase.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Consider adding a NatSpec comment containing a security contact at the top of each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Missing Named Parameters in Mappings

Since [Solidity 0.8.18](https://github.com/ethereum/solidity/releases/tag/v0.8.18), developers can utilize named parameters in mappings. This means mappings can take the form of `mapping(KeyType KeyName? => ValueType ValueName?)`. This updated syntax provides a more transparent representation of a mapping's purpose.

Throughout the codebase, multiple instances of mappings without named parameters were identified:

*   The [`allocations` state variable](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L22) in the `AssetManagement` contract
*   The [`redeemRequests` state variable](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDBasePool.sol#L141) in the `FxUSDBasePool` contract
*   The [`markets` state variable](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/FxUSDRegeneracy.sol#L97) in the `FxUSDRegeneracy` contract
*   The [`poolInfo`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol#L141), [`rewardSplitter`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol#L144), and [`tokenRates`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol#L147) state variables in the `PoolManager` contract
*   The [`positionData`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolStorage.sol#L145), [`positionMetadata`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolStorage.sol#L151), [`tickBitmap`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolStorage.sol#L154), [`tickData`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolStorage.sol#L157), and [`tickTreeData`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/PoolStorage.sol#L160) state variables in the `PoolStorage` contract
*   The [`accumulatedPoolOpenFees`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L108), [`accumulatedPoolCloseFees`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L115), and [`accumulatedPoolMiscFees`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/ProtocolFees.sol#L122) state variables in the `ProtocolFees` contract
*   The [`lockedProxy` state variable](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/SavingFxUSD.sol#L105) in the `SavingFxUSD` contract

Consider adding named parameters to mappings in order to improve the readability and maintainability of the codebase.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Multiple Contract Declarations Per File

Within the [`SavingFxUSD.sol`](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/SavingFxUSD.sol), there are two contract declarations.

Consider separating the `LockFxSaveProxy` contract into its own file to make the codebase easier to understand and maintain.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Code Readability Suggestions

Throughout the codebase, multiple opportunities for improving code readability were identified:

*   The [`onlyFxSave` modifier](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/PoolManager.sol#L161) of the `PoolManager` contract ensures that the caller is the `fxBase` contract, not the `fxSAVE` contract. As such, consider renaming the modifier to `onlyFxBase`.
*   The [`totalSupply` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/strategy/AaveV3Strategy.sol#L42-L44) of the `AaveV3Strategy` contract returns the `balanceOf` of `AToken` which translates to "total deposited assets + yield generated" as this function is later used to check the total [managed assets of the strategy in the `AssetManagement` contract](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L48-L49). Consider renaming the function so that its name matches its behavior and does not create confusion while adding more strategies in the future.
*   The [`manage` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/fund/AssetManagement.sol#L46-L52) of the `AssetManagement` contract only acts as a deposit function. Consider renaming it to `deposit`.

Consider implementing the above-given renaming suggestions to improve the readability and maintainability of the codebase.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

### Unused Code

In `TickLogic`, the [`_getTick` function](https://github.com/AladdinDAO/fx-protocol-contracts/blob/56a47eab8d10334e479df83a2b13a8b68ce390e9/contracts/core/pool/TickLogic.sol#L114) spends a line computing a new ratio that it will never use. Consider removing this superfluous line.

_**Update:** Acknowledged, resolution planned. The f(x) Protocol team stated:_

> _We acknowledge the issue and plan to address it in a future update._

Conclusion
----------

The f(x) Protocol v2.0 introduces a novel stablecoin implementation—fxUSD—with improved stabilization dynamics and an advanced peg-keeping mechanism, alongside its decentralized trading platform, xPosition. The protocol relies on complex mechanisms to maintain stability using batch rebalancing, liquidation, redemption, and a "tick"-based approach for maintaining leveraged positions for each base pool.

It utilizes special stability pools, a peg keeper, funding fees, and a harvesting mechanism to reward the maintainers of the system and mitigate the risks of depegging. The system uniquely manages xPositions with a tick-based approach that groups positions into price bands of roughly 0.15% to improve efficiency while updating the positions. Multiple sources are used to determine the price of the underlying collateral token, including off-chain oracles and a combination of on-chain spot prices.

Certain integrations with the f(x) Protocol such as `Gauge`, `Convex Vault`, `SpotPriceOracle`, `RevenuePool`, `Treasury`, `fTokens`, and `MarketV2` were out of scope for this audit. In addition, the protocol largely anticipates funding user positions via external flashloan providers such as `Morpho` and `Balancer` using periphery facet contracts which were also out of scope for this audit.

Throughout the audit, the primary focus was on validating the tick logic and various edge cases regarding rebalancing, liquidation, and redemptions, while also assessing the overall economic stability of the system. The system, despite being dependent upon multiple contracts, reflected robust architecture and high resilience.

One critical-severity issue, two high-severity issues and multiple medium- and low-severity issues were identified. The critical-severity issue manipulated tick and node logic to block operate functionality. Of the high-severity issues, one was the susceptibility of the pricing scheme to a single, manipulable liquidity pool which could result in early liquidations of positions. The other one completely blocked the flashloan functionality of the protocol.

Collaboration with the f(x) Protocol team was smooth and highly effective. Their responsiveness and contextual clarity were instrumental in understanding the protocol and the broader reasoning behind the design choices.