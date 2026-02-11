\- October 13, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

Type

DeFi

Timeline

From 2025-08-18

To 2025-08-22

Languages

Solidity

Total Issues

10 (10 resolved)

Critical Severity Issues

0 (0 resolved)

High Severity Issues

0 (0 resolved)

Medium Severity Issues

1 (1 resolved)

Low Severity Issues

6 (6 resolved)

Notes & Additional Information

3 (3 resolved)

Scope
-----

OpenZeppelin audited the [SizeCredit/very-liquid-vaults repository](https://github.com/SizeCredit/very-liquid-vaults) at commit [d5d781c](https://github.com/SizeCredit/very-liquid-vaults/tree/d5d781ceed378b8865f01b72bfe782be715888c1).

In scope were the following files:

`src
├── Auth.sol
├── IVault.sol
├── SizeMetaVault.sol
├── strategies
│   ├── AaveStrategyVault.sol
│   ├── CashStrategyVault.sol
│   └── ERC4626StrategyVault.sol
└── utils
    ├── BaseVault.sol
    ├── NonReentrantVault.sol
    └── PerformanceVault.sol` 

System Overview
---------------

The Very Liquid Vault (as audited: _Size Meta Vault_) is a modular "meta" vault that allocates its assets to underlying vaults called strategies. The meta vault is ERC-4626-compliant and allows users to deposit and withdraw an underlying asset such as USDC. The meta vault automatically allocates the underlying assets to the strategies during deposits. The strategies are also ERC-4626-compliant.

Currently, there are three types of strategy vaults. An AAVE strategy vault, a generic ERC-4626 strategy vault, and a cash strategy vault for the reserve store. The meta vault itself can also be used as a strategy vault. It can have up to 10 strategy vaults, and mix and match different types of strategy vaults. However, the meta vault and its strategy vaults must all have the same underlying asset.

The meta vault features a protocol fee system. A configurable percentage of the profit generated is allocated to the fee recipient by way of minting new shares. The protocol also includes a role-based access-control contract. Instead of each vault having its own access-control management system, they all share a single contract for unified management of roles.

Security Model and Trust Assumptions
------------------------------------

The protocol uses certain privileged roles to manage the allocation of the assets for its users.

### Privileged Roles

The protocol is governed by a role-based system managed by a single access-control contract. Below are the roles and their expected timelock setups.

*   **`DEFAULT_ADMIN_ROLE`** (7-day timelock): It has ultimate control over the system. It can upgrade contracts, grant and revoke any role, and modify critical parameters such as the performance fee percentage.
*   **`VAULT_MANAGER_ROLE`** (1-day timelock): It manages the vault's strategies and operational state. It can add new strategies, set total asset caps, and unpause the system.
*   **`GUARDIAN_ROLE`** (no timelock): It is a trusted role for incident response. It can pause the system, remove a strategy in an emergency, and cancel any pending timelock proposals.
*   **`STRATEGIST_ROLE`** (no timelock): It is responsible for tactical fund management. It can execute rebalances between strategies and reorder the deposit/withdrawal priority of strategies.

### Trust Assumptions

During the audit, the following trust assumptions were made:

*   All privileged roles are trusted to act in the best interests of the users. However, there are certain limitations on each role regarding any potential malicious actions.
*   The Admin has absolute control over the protocol through its ability to upgrade the contracts. However, the 7-day timelock reduces the required trust as it allows users to act upon any harmful upgrades.
*   The Vault Manager has also a lot of control as it can add arbitrary strategies. Similarly, the 1-day timelock reduces the required trust as it allows an exit window for the users, albeit a short one.
*   The Strategist has the lowest trust required as it can only rebalance between existing strategies. Additionally, the potential harm a Strategist can do is limited by the maximum slippage configuration that must be respected during rebalancing. The guardian is perhaps the role that requires the highest trust.
*   The guardian does not have a timelock, and it can permanently cause DoS for the protocol by pausing the contract and blocking any proposals to unpause it. The guardian can also remove a strategy with unlimited slippage, bypassing the maximum slippage limit configuration. Furthermore, the guardian can forfeit all assets during a strategy removal. Although re-adding the strategy would reclaim those assets, anyone who deposits to the vault before the re-adding of the strategy would benefit from the re-inclusion of the assets at the expense of the other users. Therefore, the guardian must be fully trusted to act non-maliciously.

Design Considerations
---------------------

Deposits and withdrawals are processed sequentially according to a priority list of strategies set by the Strategist. For example, withdrawals are fulfilled from the first strategy in the list with sufficient liquidity, then the second, and so on. This design choice requires the Strategist to frequently rebalance and reorder the strategies.

In their documentation, the team also acknowledges the following design choices:

*   The performance fee might stop being applied following major downturns as the price per share might never reach the high-water mark again.
*   Assets sent directly to vaults may be lost (except the cash strategy vault, which treats them as donations).
*   The vaults are incompatible with fee-on-transfer assets.
*   An ERC-4626 strategy vault only supports fully ERC-4626-compliant vaults that do not take any fees on deposits/withdrawals.

Medium Severity
---------------

### Incorrect Order of Operations Causes Permanent Reduction in Protocol Fees

In the `_mintPerformanceFee` function of the `PerformanceVault` contract, protocol fees are based on the difference between the current price-per-share (PPS) and the high-water-mark (HWM), which tracks the highest PPS reached and is only updated when the current PPS exceeds it. Following the [fee shares calculation](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/PerformanceVault.sol#L105), [the HWM is set to the current PPS](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/PerformanceVault.sol#L111) and then [the fee shares are minted](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/PerformanceVault.sol#L112).

This order of operations introduces dilution. Once fee shares are minted, the total supply increases while the amount of assets remains the same, which reduces PPS. Since the HWM was already updated to the pre-dilution PPS, it now sits above the post-dilution PPS. The vault will not charge another performance fee until the PPS surpasses this inflated HWM, resulting in a permanent reduction of fee revenue.

Consider updating the HWM with the current PPS value _after_ the fee shares have been minted to ensure accurate accounting and prevent permanent fee revenue loss.

_**Update:** Resolved in [pull request #38](https://github.com/SizeCredit/very-liquid-vaults/pull/38) at [commit dd634d4](https://github.com/SizeCredit/very-liquid-vaults/pull/38/commits/dd634d4a99dc63dc1eaf8d95e15435440bac7d2e)._

Low Severity
------------

The [`_update` function](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/BaseVault.sol#L180) in `BaseVault.sol` has a `notPaused` modifier which blocks all ERC-20 operations (`transfer`, `transferFrom`, `mint`, and `burn`). This is overly restrictive as it prevents user-to-user share transfers during incidents. Pausing should gate vault I/O (deposit, mint, withdraw, and redeem), not secondary-market movement of existing shares. This may cause secondary liquidity freezes, collateral issues and integration fails, and will result in the governance gaining de facto control over transferability. While this issue does not entail direct fund loss, users can still be locked into positions during pauses.

Consider removing the `notPaused` modifier from the `_update` function and applying pause checks only to vault I/O functions.

_**Update:** Resolved in [pull request #39](https://github.com/SizeCredit/very-liquid-vaults/pull/39) at commits [91a1fcf](https://github.com/SizeCredit/very-liquid-vaults/pull/39/commits/91a1fcf934241c6e4023d907e632d127d3cec685) and [e847e3f](https://github.com/SizeCredit/very-liquid-vaults/pull/39/commits/e847e3f0e76a8ce7071706e9d4d1085b22b3667e)._

### Malicious or Faulty Strategies Cannot Be Removed

The `removeStrategy` function of the `SizeMetaVault` contract calls [the `convertToAssets` function](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L215) of the strategy being removed. This call is performed even when the guardian forfeits all assets by setting [the rebalance amount](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L205) to zero. A malicious or faulty strategy can cause DoS by reverting in its `convertToAssets` function. This would prevent the removal of the strategy. Such a strategy could also be causing DoS in the core function of the meta vault, completely bricking the protocol.

Consider not [calling the strategy and rebalancing](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L215-L217) if the rebalance amount is zero.

_**Update:** Resolved in [pull request #40](https://github.com/SizeCredit/very-liquid-vaults/pull/40) at [commit 7cb122a](https://github.com/SizeCredit/very-liquid-vaults/pull/40/commits/7cb122abfbcdceb0162575d44892180be534f5d9)._

### Missing, Incomplete, and Misleading Documentation

Throughout the codebase, multiple instances of misleading documentation were identified:

*   In [`SizeMetaVault.sol`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L210), the NatSpec for `removeStrategy` incorrectly states `VAULT_MANAGER_ROLE` can call it, but the implementation correctly uses `GUARDIAN_ROLE`.
*   In [`BaseVault.sol`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/BaseVault.sol#L127), a comment above `setTotalAssetsCap` claims only the `Auth` contract can call it, but the code allows any address with `VAULT_MANAGER_ROLE`.

Throughout the codebase, multiple instances of missing or incomplete documentation were identified:

*   `Auth.sol`: [`initialize`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/Auth.sol#L29-L42)
*   `IVault.sol`: [`auth`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/IVault.sol#L13), [`totalAssetsCap`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/IVault.sol#L16)
*   `SizeMetaVault.sol`: [`initialize`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L66-L79), [`maxDeposit`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L83-L85), [`maxMint`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L88-L93), [`maxWithdraw`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L96-L98), [`maxRedeem`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L101-L106), [`totalAssets`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L110-L116), [`setPerformanceFeePercent`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L180-L182), [`setFeeRecipient`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L185-L187), [`setRebalanceMaxSlippagePercent`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L192-L194), [`addStrategy`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L198-L200), [`removeStrategy`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L210-L222), [`reorderStrategies`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L228-L245), [`rebalance`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L250-L259), [`strategies`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L351-L353), [`strategies (index)`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L356-L358), [`strategiesCount`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L361-L363), [`rebalanceMaxSlippagePercent`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L366-L368), [`isStrategy`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L371-L377), [`MAX_STRATEGIES`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L23), Events ([Lines 42 to 47](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L42-L47))
*   `AaveStrategyVault.sol`: [`initialize`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/AaveStrategyVault.sol#L70-L81), [`maxDeposit`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/AaveStrategyVault.sol#L91-L107), [`maxMint`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/AaveStrategyVault.sol#L111-L113), [`maxWithdraw`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/AaveStrategyVault.sol#L117-L125), [`maxRedeem`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/AaveStrategyVault.sol#L130-L139), [`totalAssets`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/AaveStrategyVault.sol#L144-L148), [`pool`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/AaveStrategyVault.sol#L171-L173), [`aToken`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/AaveStrategyVault.sol#L176-L178), Events ([Lines 61 to 62](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/AaveStrategyVault.sol#L61-L62))
*   `ERC4626StrategyVault.sol`: [`initialize`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/ERC4626StrategyVault.sol#L43-L51), [`maxDeposit`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/ERC4626StrategyVault.sol#L55-L57), [`maxMint`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/ERC4626StrategyVault.sol#L60-L65), [`maxWithdraw`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/ERC4626StrategyVault.sol#L68-L70), [`maxRedeem`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/ERC4626StrategyVault.sol#L73-L78), [`vault`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/ERC4626StrategyVault.sol#L106-L108), [`VaultSet` Event](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/ERC4626StrategyVault.sol#L38)
*   `BaseVault.sol`: [`initialize`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/BaseVault.sol#L64-L83), [`setTotalAssetsCap`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/BaseVault.sol#L127-L129), [`decimals`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/BaseVault.sol#L157-L159), [`maxDeposit`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/BaseVault.sol#L185-L187), [`maxMint`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/BaseVault.sol#L190-L192), [`maxWithdraw`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/BaseVault.sol#L195-L197), [`maxRedeem`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/BaseVault.sol#L200-L202), [`auth`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/BaseVault.sol#L211-L213), [`totalAssetsCap`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/BaseVault.sol#L216-L218), Events ([`52-54`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/BaseVault.sol#L52-L54))
*   `NonReentrantVault.sol`: [`deposit`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/NonReentrantVault.sol#L15-L17), [`mint`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/NonReentrantVault.sol#L19-L21), [`withdraw`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/NonReentrantVault.sol#L23-L25), [`redeem`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/NonReentrantVault.sol#L27-L29)
*   `PerformanceVault.sol`: [`deposit`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/PerformanceVault.sol#L127-L129), [`mint`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/PerformanceVault.sol#L131-L133), [`withdraw`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/PerformanceVault.sol#L135-L137), [`redeem`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/PerformanceVault.sol#L139-L141), [`highWaterMark`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/PerformanceVault.sol#L145-L147), [`performanceFeePercent`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/PerformanceVault.sol#L150-L152), [`feeRecipient`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/PerformanceVault.sol#L155-L157), State Variables ([Lines 15 to 16](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/PerformanceVault.sol#L15-L16)), Events ([Lines 39 to 42](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/PerformanceVault.sol#L39-L42))

There are also two other minor issues:

*   The [default max rebalance slippage](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L76) is assigned as a literal (`0.01e18`). This variable could instead be a named constant or there could be an inline comment specifying that the default max rebalance slippage is 1%.
*   Import paths contain unnecessary double slashes in [`BaseVault.sol`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/BaseVault.sol#L21) and [`SizeMetaVault.sol`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L10).

Consider updating the documentation to match the code, completing the NatSpec documentation, adding inline comments where relevant, and fixing the double slashes. The `@inheritdoc` tag can be used in the NatSpec documentation where relevant to prevent duplicate comments.

_**Update:** Resolved in [pull request #47](https://github.com/SizeCredit/very-liquid-vaults/pull/47) at [commit dbba5d6](https://github.com/SizeCredit/very-liquid-vaults/pull/47/commits/dbba5d6c71303be0095ba3ce8dc8a3eaa9f7d289). The Size Credit team stated:_

> _The NatSpec for events and errors was purposefully left out as we consider these self-describing. Moreover, other well-known Solidity projects such as OpenZeppelin's `openzeppelin-contracts` repository follow the same practice._

### Incorrect Return Values for Nested Meta Vaults Sharing the Same Strategy

The `_maxWithdrawFromStrategies` and `_maxDepositToStrategies` functions of the `SizeMetaVault` contract can return incorrect values in case of nested meta vaults. For example, the issue occurs if a meta vault has two strategies, one of which is an ERC-4626 strategy and the other is a meta vault strategy that has the same ERC-4626 strategy. In this scenario, if the ERC-4626 vault has a `maxDeposit` limit of 100 tokens remaining, the top-level meta vault would double count this value and return 200 tokens. However, in practice, trying to deposit 200 tokens would cause a revert, because only 100 can be deposited.

Consider documenting this behavior and either acknowledging the issue or explicitly stating that such nested strategy setups are not supported. Otherwise, updating the code to return correct values appears to be unfeasible.

_**Update:** Resolved in [pull request #41](https://github.com/SizeCredit/very-liquid-vaults/pull/41) at [commit ed2c2a8](https://github.com/SizeCredit/very-liquid-vaults/pull/41/commits/ed2c2a8d3f0ed2980c3b653564d2c9790441a09a)._

### Incomplete Reentrancy Protection

The `SizeMetaVault` contract does not have the `nonReentrant` modifier for some of its state-changing functions. Most of these functions can be argued to function properly without any reentrancy guards because they are only callable by trusted actors behind a timelock. However, since the [`setRebalanceMaxSlippagePercent`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L192) function is not behind a timelock, it would definitely benefit from having a reentrancy guard.

In addition, the [`NonReentrantVault`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/NonReentrantVault.sol) and [`PerformanceVault`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/utils/PerformanceVault.sol) contracts do not have the `nonReentrant` modifier for their parent ERC-20 contract's functions. Specifically, the `transfer` and `transferFrom` functions should be guarded. Furthermore, the vaults are also susceptible to read-only reentrancy. Applying the `nonReentrant` modifier to the state-changing functions alone does not protect against read-only reentrancy, which could make third-party contracts vulnerable if they read from a `view` function of these vaults mid-state change.

Consider adding reentrancy guards to applicable functions of the vaults, including the functions from the parent contracts.

_**Update:** Resolved in [pull request #46](https://github.com/SizeCredit/very-liquid-vaults/pull/46) at commits [7d4e04c](https://github.com/SizeCredit/very-liquid-vaults/pull/46/commits/7d4e04c57c5dff714a27a92a3356883fe5bfc9c0) and [a811e04](https://github.com/SizeCredit/very-liquid-vaults/pull/46/commits/a811e047d608aacc7e07499dbd6a9898a8e14224). The `nonReentrant` and `nonReentrantView` modifiers were added where possible and the documentation was expanded to clarify the remaining read-only reentrancy vectors. The update also removed the `notPaused` modifier from access-controlled functions which simplifies admin intervention during emergencies. The Size Credit team stated:_

> _Because of how these contracts are inherited from OpenZeppelin's `openzeppelin-contracts-upgradeable` library, practically all ERC-20 and ERC-4626 `view` functions cannot be guarded with a `nonReentrantView` modifier, since they are used internally in state-changing functions which themselves are non-reentrant. If we applied `nonReentrantView` to `public` `view` functions that are used by state-changing `public` functions, they would revert._

### Incorrect Return Value in `maxRedeem` and `maxMint` Functions

The `SizeMetaVault` and `ERC4626StrategyVault` contracts derive the return values of their `maxRedeem` and `maxMint` functions from the `maxWithdraw` and `maxDeposit` functions, respectively. This results in a precision loss during the conversion of these values. For example, in both contracts, the `maxRedeem` function [first invokes `maxWithdraw`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L102) which gets the total withdrawable assets from the underlying vault(s). The underlying vault(s) would most likely calculate the withdrawable assets [by converting users' total shares to assets](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/60b305a8f3ff0c7688f02ac470417b6bbf1c4d27/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol#L164C21-L164C44). The `maxRedeem` function then [converts these assets back to shares](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L104). The conversions from shares to assets to shares again all use floor division causing precision loss. This means that the resulting share amount would most of the time be _1 Wei_ less than the actual share amount of the user. This could badly affect the user experience and potentially lead to a DoS of the dependent contracts that expect the entire balance to be withdrawable.

Consider documenting this behavior to ensure users do not falsely assume the entire share amount is withdrawable.

_**Update:** Resolved in [pull request #49](https://github.com/SizeCredit/very-liquid-vaults/pull/49) at [commit 7e2c800](https://github.com/SizeCredit/very-liquid-vaults/pull/49/commits/7e2c8005f55f1862b23aa86c1ddc0f8e55941bf7)._

Notes & Additional Information
------------------------------

### `reorderStrategies` Function is Unnecessarily Expensive

The [`reorderStrategies`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L239-L244) function of the `SizeMetaVault` contract removes each existing strategy via `_removeStrategy` and re-adds each new one via `_addStrategy`, wasting gas due to redundant work.

Each `_removeStrategy` operation loops through and shifts existing strategies to preserve order, and then pops the last strategy. Trying to preserve the order of strategies in the process of updating the entire order is unnecessary work. Each `_addStrategy` operation following the `_removeStrategy` operation performs checks on the validity of the strategy, then pushes the strategy to the array. The [validation loop within `reorderStrategies`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L229-L236) already ensures that `newStrategiesOrder` only contains existing, non-duplicate strategies, making the `_addStrategy` checks unnecessary. This wastes gas, emits redundant `StrategyAdded` and `StrategyRemoved` events, and enlarges the reversion surface without added safety.

Consider updating the existing strategies directly in a single loop instead of [invoking the `internal` `_removeStrategy` and `_addStrategy` functions](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L238-L244).

_**Update:** Resolved in [pull request #42](https://github.com/SizeCredit/very-liquid-vaults/pull/42) at [commit fffe0e9](https://github.com/SizeCredit/very-liquid-vaults/pull/42/commits/fffe0e9730378c69aaf2b68f741d4c5136b6f35d)._

### Avoidable External Call

In the [`initialize` function](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/strategies/AaveStrategyVault.sol#L70-L81) of the `AaveStrategyVault` contract, the AAVE pool is called (external call) twice to get the same `aToken` address. Performing external calls is an expensive operation that should be avoided if possible.

Consider caching the `aToken` in a local variable by calling the AAVE pool once and using this local variable the second time.

_**Update:** Resolved in [pull request #44](https://github.com/SizeCredit/very-liquid-vaults/pull/44) at [commit 9548b93](https://github.com/SizeCredit/very-liquid-vaults/pull/44/commits/9548b93ecb865dac3a8b1608eeebd2c02dbce72a)._

### Opportunity to Break Loops Early

The looping of the strategies in the `_deposit` and `_withdraw` functions of the `SizeMetaVault` can be safely broken if the `assetsToDeposit` and `assetsToWithdraw` values, respectively, are fully consumed.

Consider breaking the loops in the `_deposit` and `_withdraw` functions if the [`assetsToDeposit`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L141) and [`assetsToWithdraw`](https://github.com/SizeCredit/very-liquid-vaults/blob/d5d781ceed378b8865f01b72bfe782be715888c1/src/SizeMetaVault.sol#L167) values, respectively, are zeroed out.

_**Update:** Resolved in [pull request #45](https://github.com/SizeCredit/very-liquid-vaults/pull/45) at [commit 553cc8f](https://github.com/SizeCredit/very-liquid-vaults/pull/45/commits/553cc8f11d3b97968f84d2bb04a9e4348c031bfb)._

Conclusion
----------

The audited codebase implements a modular ERC-4626-compliant meta vault system that allocates assets across underlying strategy vaults. The audit identified several medium- and low-severity issues related to precision loss in ERC-4626 functions, pause functionality, and strategy management.

The codebase was well-written, thoroughly tested, and comprehensively documented with clear design considerations and acknowledged limitations. The Size Credit team was very responsive throughout the audit process, answering all questions satisfactorily and providing extensive documentation about the project.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kHht0deRwMNafVQqRs1ug-lnorFIA&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=195868486513&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=abaf7967-fceb-4b33-b3ab-40aed9dd7596&redirect_url=APefjpE8ulpG6bCGC-mAg8FqVo3sYZxHpwSBZ5GLAVbuyvUciOzpJhkdIV4HpEgAAAuotaPtbp4EdJEacBTwkzpxjzX0-2vBqtb0NhiQj7CPp-mH4kgmXr00h7uvkkC34qyICpm2XxSZp6fJ-xchpvt6PMe2kwDGikrv0xsuv2bU44xdIyxkXi96dd2Tmgsb1FCp84wgFJZ5TvrBLGhYZkavB9H2cBG-86NHGKMwwIUVz9S6qYg9bMJ5PLuwBwVrZacdQv4_18uS&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Fvery-liquid-vaults-audit&ts=1770533818647&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.39.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")