\- November 10, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

### Summary

**Type:** Bridge  
**Timeline:** September 29, 2025 → October 7, 2025  
**Languages:** Solidity

**Findings**  
Total issues: 16 (16 resolved)  
Critical: 0 (0 resolved)  
High: 0 (0 resolved)  
Medium: 4 (4 resolved)  
Low: 5 (5 resolved)

**Notes & Additional Information**  
7 (7 resolved)

Scope
-----

OpenZeppelin audited the [lombard-finance/smart-contracts](https://github.com/lombard-finance/smart-contracts) repository at commit [63d4076](https://github.com/lombard-finance/smart-contracts/tree/63d407689cb50212992a6bd7ad1b0d0d80ca5287).

In scope were the following files:

`contracts
├── LBTC
│   └── BridgeTokenAdapter.sol
│   
└── bridge         
    ├── providers
    │    ├── BridgeTokenPool.sol      
    │    └── LombardTokenPoolV2.sol 
    │      
    └── BridgeV2.sol` 

System Overview
---------------

In this audit, four smart contracts of the Lombard Protocol were reviewed. These contracts facilitate cross-chain token bridging and integration with Chainlink’s CCIP (Cross-Chain Interoperability Protocol). Specifically, the audit scope included the following contracts:

*   `BridgeV2`: This contract handles token deposits—either directly from users or indirectly through CCIP relayers. Upon receiving a deposit, the contract burns the tokens and emits a message for the Mailbox (as described in our [previous report](https://github.com/OpenZeppelin/audits-lombard/tree/main/reports/06-LBTC-Contracts)). Relayers monitor these messages and trigger the corresponding mint function on the destination chain to complete the bridging process.
    
*   `LombardTokenPoolV2`: This contract enables integration with the CCIP system. Instead of interacting directly with the bridge, users interact through CCIP. Their tokens are transferred to the Pool contract, which invokes the `lockOrBurn` function. After performing a series of validations, this function calls the deposit function on the bridge contract. Conversely, on the destination chain, the `releaseOrMint` function is executed to validate inputs, communicate with the `Mailbox`, and instruct the bridge to mint tokens to the intended recipient by calling `handlePayload` function.
    
*   `BridgeTokenPool`: This contract is a variation of `LombardTokenPoolV2`, designed to operate with token adapters instead of directly handling the underlying tokens.
    
*   `BridgeTokenAdapter`: Since the `BridgeV2` contract requires tokens to implement a specific interface, the tokens that do not conform to this interface will have to use this adapter. The adapter acts as a wrapper token, with permission to mint and burn the underlying asset, thereby ensuring compatibility with the bridge. This contract has been developed to accommodate the BTC.b token to support the Lombard bridge, and will be granted minting privileges for the BTC.b token on Avalanche. The minting and burning operations for BTC.b must be routed through the adapter contract. If a user attempts to burn their BTC.b tokens to get back BTC directly calling the `unwrap` function of BTC.b contract, the Lombard team will simply mint these tokens back to the user, who should then follow the intended process.
    

Security Model and Trust Assumptions
------------------------------------

The contracts reviewed in this audit interact with multiple external components, and their overall security depends on the correct and expected behavior of these dependencies.

In particular, the system is designed to integrate with Chainlink’s CCIP. As such, it is assumed that CCIP functions as intended, and that tokens have been successfully transferred to the appropriate Pool contract (`LombardTokenPoolV2` or `BridgeTokenPool`) before invoking the `lockOrBurn` function. Since CCIP does not support forwarding additional value via `msg.value`, it is expected that the `BridgeV2` contract will configure the maximum fee discount for the Pool contracts, effectively ensuring that CCIP-based transactions incur zero fees.

The latest Version of CCIP supports tokens with different decimal configurations on each side of the bridge. In a burn-and-mint bridge, this can lead to a loss of precision when tokens are transferred from a chain with more decimals to one with fewer. Since tokens on the source side are burned, any loss of precision results in a permanent loss of those tokens. The Lombard team is expected to configure the tokens on both sides with the same number of decimals.

Furthermore, CCIP imposes gas limits on the operations it executes. It is assumed that the Lombard team has reviewed these limits and configured them appropriately to guarantee that all required actions can be completed without exceeding the available gas. The bridge relies on relayers to transmit messages between chains. There is no built-in mechanism to cancel a deposit that has not been finalized. Therefore, it is assumed that all legitimate deposits will be finalized by the relayers in a timely manner.

The bridge implements a rate limit on token minting on the destination side, but not on deposits at the source. Consequently, a large deposit may succeed on the source chain but remain pending until the rate limit on the destination chain is raised. It is expected that the bridge owner will manually increase the rate limit when such a deposit is identified to allow its successful finalization.

The `BridgeV2` contract exposes two `deposit` functions:

*   The first is intended to be called by whitelisted relayers, such as the CCIP Token Pool contracts. Any user can interact with these relayers to bridge tokens. It is expected that the relayer has already received and holds the tokens before invoking the bridge, as these tokens will be burned from the relayer’s address.
*   The second deposit function is designed for direct interaction by whitelisted users.

The `BridgeTokenAdapter` contract is expected to grant the `MINTER` role exclusively to the Bridge contract (there is also a `batchMint` function, but this is not used by the `BridgeV2` and is included solely for interface compatibility), and must have both minting and burning permissions for the underlying BTC.b Token. The bridge is in turn expected to grant appropriate token allowances to the adapter contract. The BTC.b token will grant the `BridgeTokenAdaptor` minting privileges through `migrateBridgeRole` function. The `unwrap` function in the BTC.b contract only allows EOAs to unwrap the token. Hence, special care will be taken if `BrdigeTokenAdaptor` is upgraded to support the `unwrap` functionality of the BTC.b token.

Finally, the `spendDeposit` function in the adapter contract is expected to be called only once, at the time the underlying token grants the adapter its minter role. This call is solely for registering the total balance of the underlying token in the internal ledger.

### Privileged Roles

Throughout the in-scope codebase, the following privileged roles were identified:

*   **Owner of the `BridgeV2` Contract** : The owner has the authority to add or remove chains where bridging is permitted, define allowed pairs of source and destination tokens, configure fee discounts for specific addresses, and set rate limits for tokens minted on the destination chain. It is expected that the owner will ensure consistency across chains by configuring the same token pairs on both sides of each bridge. For example, if a token is allowed to be bridged from Chain A to Chain B, the reverse pairing (from Chain B to Chain A) should also be enabled. Moreover, the owner is responsible for adjusting rate limits when necessary, such as to accommodate larger deposits.
    
*   **Owner of the `LombardTokenPoolV2` and `BridgeTokenPool` Contracts**: The owner is responsible for configuring pool-related token details and maintaining up-to-date information about tokens that can be bridged. It is expected that the configuration of these Pool contracts remains consistent with that of the `BridgeV2` contract to ensure coherent bridging behavior across the system.
    
*   **`BridgeTokenAdapter` Roles**:
    
    *   **Default Admin Role**: The holder of this role can assign other roles, update key protocol parameters (such as consortium configurations), and unpause the protocol if it has been paused.
    *   **Pauser Role**: The holder of this role can pause the protocol in case of emergencies or detected anomalies. It is expected to be used only when necessary to prevent potential harm to users or the system.
    *   **Minter Role**: The bridge adapter must be authorized by the underlying token contract to mint and burn tokens on arbitrary addresses. The holder of the `MINTER` role can perform these actions. It is expected that this role is exclusively assigned to the bridge contract, which should invoke mint and burn functions only in response to legitimate deposit and bridging events.

Medium Severity
---------------

### Token Pool Deployment May Fail for Some Tokens

The constructor of the `LombardTokenPoolV2` contract [calls `token_.decimals()` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/LombardTokenPoolV2.sol#L56-L57) to fetch the decimals of the token. However, according to the ERC-20 spec, the [`decimals` function is optional](https://eips.ethereum.org/EIPS/eip-20#methods). Hence, there is a possibility that, for a given token, the `decimals` function may not exist at all. The inherited `TokenPool` contract of the CCIP [acknowledges this possibility and resolves using](https://github.com/smartcontractkit/chainlink-ccip/blob/0e3e0fc5c0f70f0d50dca66b139142ddf3009294/chains/evm/contracts/pools/TokenPool.sol#L132-L140) `try-catch` blocks. This could lead to the `LombardTokenPoolV2` contract never be deployed for certain tokens.

Since the inherited `TokenPool` contract already calls `decimals` function on the token and compares against the given constructor parameter, instead of relying on an on-chain call that may revert, consider modifying the constructor so that it accepts the decimals value as an explicit parameter that is supplied off-chain or through the configuration.

_**Update:** Resolved at commit [3c71001](https://github.com/lombard-finance/smart-contracts/pull/303/commits/3c710014a5fe9151f93130097a4b9540483cd33c). The Lombard team stated:_

> Implemented fallback ratio for `LombardTokenPoolV2`. `BridgeTokenPool` always sets the fallback ratio to 0 because the implementation of the contract is known before deployment.

### Lack of Cross-Verification for Destination Token

The [`lockOrBurn`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/LombardTokenPoolV2.sol#L79-L119) function of the `LombardTokenPoolV2` and `BridgeTokenPool` contracts is designed to be invoked by the CCIP and calls the [`deposit`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L281-L298) function of the `BridgeV2` contract, which in turn burns the local token referenced by the [`i_token`](https://github.com/smartcontractkit/chainlink-ccip/blob/5146b8403f92ed755dc102bed66a0b63e037d22c/chains/evm/contracts/pools/TokenPool.sol#L100) variable. Within the `deposit` function, a verification step ensures that `i_token` is an approved token for bridging and the target chain is permitted. The [`destinationToken`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L358-L367) address is also retrieved from the `allowedDestinationToken` mapping of the `BridgeV2` contract.

The Pool contracts maintain [their own record of the destination token](https://github.com/smartcontractkit/chainlink-ccip/blob/5146b8403f92ed755dc102bed66a0b63e037d22c/chains/evm/contracts/pools/TokenPool.sol#L86), which can be obtained via the [`getRemoteToken`](https://github.com/smartcontractkit/chainlink-ccip/blob/5146b8403f92ed755dc102bed66a0b63e037d22c/chains/evm/contracts/pools/TokenPool.sol#L404-L408) function. These two values are expected to be the same. However, this consistency is not verified either during the setup phase, when the values are assigned, or during the execution of the `lockOrBurn` function. A mismatch between these two addresses could cause bridge malfunction, as CCIP may attempt to interact with a destination token pool corresponding to a different token than the one expected by the bridge.

Consider either adding a consistency check in `lockOrBurn` ensuring that these two values are equal or, when the owner invokes [`applyChainUpdates`](https://github.com/smartcontractkit/chainlink-ccip/blob/5146b8403f92ed755dc102bed66a0b63e037d22c/chains/evm/contracts/pools/TokenPool.sol#L459-L524) in the Pool contract, validating that the destination token aligns with the bridge's value for the destination token.

_**Update:** Resolved at commits [b736e59](https://github.com/lombard-finance/smart-contracts/pull/303/commits/b736e598187989d1d7f860acd7ca5abd8818c9d3), [ef5e24f](https://github.com/lombard-finance/smart-contracts/commit/ef5e24fedd31d95f49d5bdfa8ed4b9c0de92e7e1) and [987a4af](https://github.com/lombard-finance/smart-contracts/commit/987a4af99df8ff6a4e3c851160a18b13118cf205)._

### Unnecessary Infinite Approval to Bridge by the `BridgeTokenPool` Contract

In the [`lockOrBurn`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/BridgeTokenPool.sol#L38-L69) function of the `BridgeTokenPool` contract, a call is made to the [`deposit`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L281-L298) function of the `BridgeV2` contract. This function internally invokes [`_burnToken`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L392-L396), which in turn calls [`transferFrom`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L308-L316) of the `BridgeTokenAdapter` contract. The `transferFrom` operation first moves the underlying `BridgeToken` to the `BridgeTokenAdapter` from the caller which is the `BridgeTokenPool` contract and then transfers the tokens to the `BridgeV2` contract.

For this operation to succeed, the `BridgeTokenPool` contract must have granted approval to the `BridgeTokenAdapter` contract. [This approval is granted in the constructor of the `BridgeTokenPool` contract](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/BridgeTokenPool.sol#L28). However, the `BridgeTokenPool` contract inherits `LombardTokenPoolV2`, and in the constructor of the latter, [infinite approval is granted to the `BridgeV2` contract](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/LombardTokenPoolV2.sol#L69). This approval is necessary for tokens without an adapter, as for them, the `_burnToken` function transfers the tokens directly from the pool to the Bridge contract. In contrast, the additional infinite approval to the `BridgeTokenAdapter` in `BridgeTokenPool` is redundant. Although the `BridgeTokenPool` contract is not expected to hold tokens, maintaining this unnecessary infinite approval is risky, especially if changes are introduced in future upgrades.

Consider removing the unnecessary infinite approval given to the `BridgeV2` contract in the `BridgeTokenPool`'s constructor.

_**Update:** Resolved at commit [4b2cf8b](https://github.com/lombard-finance/smart-contracts/pull/303/commits/4b2cf8b47c3b0c21618988912997586fe81c452d)._

### Insufficient Input Validation in `deposit` May Lead to Stuck Bridging Transactions

In the `BridgeV2` contract, the [`deposit`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L281-L298) function accepts the `recipient` as a `bytes32` argument, since the destination chain is not necessarily EVM compatible. Currently, the function only checks that the [`recipient` is non-zero](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L342-L344).

However, when bridging to an EVM-compatible destination chain, the [`recipient` is converted to an `address`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L537) in the destination by taking the lowest 20 bytes and verifying that the remaining are zero. If this condition is not met, the transaction on the destination chain will revert, preventing the bridging process from finalizing and potentially causing permanently locked funds. This issue could occur either accidentally or intentionally (e.g., to force the relayers to attempt to finalize a transaction that will always revert). A similar issue exists with the `sender` argument: on the destination side, a [non-zero sender is required](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L522-L524), but `deposit` does not verify this.

Consider adding these extra checks which will guarantee that the cross-chain transactions can always be finalized.

_**Update:** Resolved at commit [c1c6528](https://github.com/lombard-finance/smart-contracts/pull/303/commits/c1c6528c5130d39946490939d8fbf04f5cc5722e), at commit [e8d9daf](https://github.com/lombard-finance/smart-contracts/pull/303/commits/e8d9daf365c48a7575fe9bede25df923008a6b23), and at commit [9fca809](https://github.com/lombard-finance/smart-contracts/pull/303/commits/9fca809b1c05b60b7a6a26782946f3783bd81296)._

Low Severity
------------

### Missing Validation in `addDestinationToken` May Cause Unusable Bridge Paths

In the `BridgeV2` contract, the [`addDestinationToken`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L95-L138) function verifies that `destinationChain` and `sourceToken` are non-zero, but it never checks that the supplied `destinationToken` is also non-zero. As a result, the owner could accidentally store a zero address as the destination token. Such a mistake [would force any deposit involving that `sourceToken` and `destinationChain` to revert](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L365-L367).

Except for the check that the `destinationToken` is non-zero, extra validation is needed to ensure that the `destinationToken` is compatible with the expected address format in the destination chain. For example, for EVM chains, all higher-order bytes, except for the lowest 20 bytes, should be 0. [Otherwise, the transaction will revert on the destination chain](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L535).

Consider adding additional input validation for `destinationToken` to prevent accidental misconfiguration.

_**Update:** Resolved at commit [c083e0f](https://github.com/lombard-finance/smart-contracts/pull/303/commits/c083e0fdd17cc2b0818c4e3dc49369421648ee41) and commit [4050f9a](https://github.com/lombard-finance/smart-contracts/commit/4050f9ae7b3da4d96e40cc74a090615e73df9470)._

### Missing Input Validation

Several functions in the codebase lack proper input validation to ensure that critical parameters are non-zero or correctly configured. Such missing checks can result in unintended behavior.

Throughout the codebase, multiple instances of missing input validation were identified:

*   The [`constructor`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/BridgeTokenPool.sol#L19-L29) of `BridgeTokenPool` does not validate that the `tokenAdapter` address is non-zero.
*   The [`BridgeV2::setTokenRateLimits`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L209-L219) function does not verify that the `Config.window` is non-zero. If `window` is set to zero, the `else` branch in [`RateLimits::availableAmountToSend`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/libs/RateLimits.sol#L71-L94) will always revert due to a division by zero.
*   The [`BridgeV2::rescueERC20`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L549-L555) function does not check that the `to` address is non-zero. While many ERC-20 tokens revert on transfers to the zero address, this behavior is not guaranteed for all implementations.

Consider adding explicit input validation to avoid any problems.

_**Update:** Resolved at commit [58561fc](https://github.com/lombard-finance/smart-contracts/pull/303/commits/58561fc6ebaaa67e45b937df61718bce2c55d499)._

### Inconsistent Allowed Destination Token Logic May Cause Confusion

The [`BridgeV2::getAllowedDestinationToken`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L154-L165) function, given a destination chain and a source token, returns the corresponding destination token address. When this function returns a non-zero address, it implies that the source token can be bridged to the destination chain and receive an equivalent amount of the destination token.

However, this assumption may not always hold true. A destination chain [could be removed from the list](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L81-L93) of allowed chains without first cleaning its associated destination tokens in the `allowedDestinationToken` mapping. As a result, `getAllowedDestinationToken()` may still return a non-zero address for a chain that is no longer a valid destination. This inconsistency can lead to confusion or integration errors for external protocols interacting with the `BridgeV2` contract, as they may incorrectly assume that the bridge route is still active.

Consider either removing all the associated destination tokens before removing a destination chain or modifying `getAllowedDestinationToken` function to return a non-zero address if both the destination chain and token are allowed.

_**Update:** Resolved at commit [6331c79](https://github.com/lombard-finance/smart-contracts/pull/303/commits/6331c796fe019a99843a17fb6c0619d69d2d9ca7)._

### Missing Docstrings

Throughout the codebase, multiple instances of missing docstrings were identified:

*   In `BridgeTokenAdapter.sol`, the [`BridgeTokenChanged` event](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L27-L30), [`initialize` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L65-L76), [`getConsortium` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L149-L151), [`getAssetRouter` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L153-L155), [`isNative` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L157-L159),[`isRedeemsEnabled` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L161-L166), [`getTreasury` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L168-L170), [`getRedeemFee` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L172-L177), [`getFeeDigest` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L179-L185).
    
*   In `BridgeV2.sol`, the [`MSG_VERSION` state variable](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L53), [`initialize` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L62-L72), [`addDestinationToken` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L95-L138), [`getAllowedDestinationToken` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L154-L165), [`removeDestinationToken` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L167-L207), [`setTokenRateLimits` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L209-L219), [`getTokenRateLimit` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L221-L233), [`setSenderConfig` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L235-L253), [`getSenderConfig` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L255-L259), [`getFee` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L261-L269),[`decodeMsgBody` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L492-L540),[`destinationBridge` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L557-L561), [`mailbox` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L563-L565).
    
*   In `BridgeTokenPool.sol`, the [`getTokenAdapter` state variable](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/BridgeTokenPool.sol#L17)
    
*   In `LombardTokenPoolV2.sol`, the [`PathSet` event](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/LombardTokenPoolV2.sol#L28-L32), [`PathRemoved` event](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/LombardTokenPoolV2.sol#L33-L37), [`typeAndVersion` state variable](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/LombardTokenPoolV2.sol#L45),[`bridge` state variable](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/LombardTokenPoolV2.sol#L47), [`removePath` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/LombardTokenPoolV2.sol#L206-L220).
    

Consider thoroughly documenting all functions (and their parameters) that are part of any contract's public API. Functions implementing sensitive functionality, even if not public, should be clearly documented as well. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved at commit [5f3c625](https://github.com/lombard-finance/smart-contracts/pull/303/commits/5f3c62520c1ceb02e9108fc2444f02c3949a8c30)._

### Incomplete Docstrings

Throughout the codebase, multiple instances of incomplete docstrings were identified:

*   In `BridgeTokenAdapter.sol`:
    *   In the [`changeConsortium`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L92-L96) function, the `newVal` parameter is not documented.
    *   In the [`changeTreasuryAddress`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L100-L104) function, the `newValue` parameter is not documented.
    *   In the [`changeBridgeToken`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L141-L145) function, the `newVal` parameter is not documented.
    *   In the [`getBascule`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L188-L190) function, not all return values are documented.
    *   In the [`spendDeposit`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L282-L304) function, the `payload` and `proof` parameters are not documented.
    *   In the [`transferFrom`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L308-L316) function, the `from`, `to`, and `amount` parameters are not documented.
    *   In the [`burn`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L320-L328) function, the `amount` parameter is not documented.
*   In `BridgeTokenAdapter.sol`, in the [`burn`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L332-L338) function, the `from` and `amount` parameters are not documented.
*   In `BridgeV2.sol`:
    *   In the [`setDestinationBridge`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L82-L93) function, the `destinationChain` and `destinationBridge_` parameters are not documented.
    *   In the [`setAllowance`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L142-L152) function, the `token`, `tokenAdapter`, and `allow` parameters are not documented.
    *   In the [`deposit`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L281-L298) function, the `destinationChain` and `sender` parameters are not documented.
    *   In the [`deposit`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L310-L326) function, the `destinationChain` parameter is not documented.
*   In `BridgeTokenPool.sol`, in the [`lockOrBurn`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/BridgeTokenPool.sol#L38-L78) function, the `lockOrBurnIn` parameter and some return values are not documented.
*   In `LombardTokenPoolV2.sol`:
    *   In the [`lockOrBurn`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/LombardTokenPoolV2.sol#L79-L119) function, the `lockOrBurnIn` parameter and some return values are not documented.
    *   In the [`releaseOrMint`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/LombardTokenPoolV2.sol#L132-L169) function, the `releaseOrMintIn` parameter and some return values are not documented.
    *   In the [`setPath`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/LombardTokenPoolV2.sol#L172-L204) function: The `remoteChainSelector`, `lChainId`, and `allowedCaller` parameters are not documented.

Consider thoroughly documenting all functions/events (and their parameters or return values) that are part of a contract's public API. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved at commit [7c2824c](https://github.com/lombard-finance/smart-contracts/pull/303/commits/7c2824ce1392a65c9ad9c048963a222a552769df) and commit [c9e55c6](https://github.com/lombard-finance/smart-contracts/pull/303/commits/c9e55c66262cade4c315ca719faafe30c7770056)._

Notes & Additional Information
------------------------------

### Redundant Mapping in `BridgeV2`

The `BridgeV2` contract maintains information about which tokens can be bridged and their corresponding destination chains and tokens. To manage this, it uses two mappings that essenctially store the same information:

*   [`allowedDestinationToken`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L39): It has the destination chain and source token address as the key and the destination token as the value.
*   [`allowedSourceToken`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L40): It has the destination chain and the destination token address as the key and the source token as the value.

The entries of these mappings are always being [set](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L95-L138) and [removed](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L167-L207) together. However, the `removeDestinationToken` function requires both the source and the destination tokens as inputs, without verifying that the provided pair matches the stored mapping entries. This can lead to incorrect removals or inconsistencies in the contract's state. In addition, the `allowedSourceToken` mapping appears to not be used anywhere in the contracts, making it redundant.

Consider using a single mapping to simplify the logic and make the code clearer and less error-prone. If the contract is already deployed, avoid removing the unused mapping from storage to prevent collisions and not updating it in the functions.

_**Update:** Resolved at commit [64bb444](https://github.com/lombard-finance/smart-contracts/pull/303/commits/64bb444a7f89ff0f0bccdaec0a8bb7c176a3494e). The Lombard team stated:_

> _The variable used to have more strict validation._

### `require` Statement Does Not Check for Any Conditions

In Solidity, using `revert()` is recommended when no conditions are being checked. In [`BridgeTokenAdapter.sol`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol), in line [`183`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L183), `require(False)` is used. However, `revert()` would be more appropriate.

Consider replacing all instances of `require(False)` with `revert()` for improved clarity and maintainability of the codebase.

_**Update:** Resolved at commit [3dd79ca](https://github.com/lombard-finance/smart-contracts/pull/303/commits/3dd79ca529ef971ef1c57fd47ae9d9ad5666a1cd)._

Throughout the codebase, multiple instances of misleading comments were identified:

*   In `BridgeV2::setTokenRateLimits`, there is a [comment](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L213) which states that the chain ID is not used anywhere. However, this is contradicted in the very next line, [where the rate limit ID is computed by hashing the chain ID](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L215).
*   The comment in [line 301, above the `deposit` function](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L301), states that "Deposits and burns tokens from tx sender to be minted on `destinationChain`". However, this is incorrect as the function deposits on behalf of the spender but burns from the transaction sender.

Consider addressing the aforementioned instances misleading comments to avoid confusion during future upgrades or audits.

_**Update:** Resolved at commit [1086236](https://github.com/lombard-finance/smart-contracts/pull/303/commits/10862364c125404a0ff37ee2f326b5216ef0355d)._

### Unnecessary Cast

The [`address(getTokenAdapter)` cast](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/BridgeTokenPool.sol#L57) in the `BridgeTokenPool` contract is unnecessary.

To improve the overall clarity and intent of the codebase, consider removing any unnecessary casts.

_**Update:** Resolved at commit [39bd27d](https://github.com/lombard-finance/smart-contracts/pull/303/commits/39bd27d36b0b4f56ea389b9b4b57e45f6435fa12)._

### Interface `IBridgeV2` Not Advertised in `supportsInterface`

The [`BridgeV2`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L24-L30) contract inherits the [`IBridgeV2`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/IBridgeV2.sol) interface. However, the implementation of [`supportsInterface`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L567-L573) currently only recognizes `IHandler` and `IERC165`. As a result, calls such as `supportInterface(IBridgeV2)` will erroneously return `false`.

Consider updating the `supportsInterface` function to include `IBridgeV2`.

_**Update:** Resolved at commit [9b12a4f](https://github.com/lombard-finance/smart-contracts/pull/303/commits/9b12a4f92485f5b66c8c0ec48992384971047d32)._

### Unused Imports

Throughout the codebase, multiple instances of unused imports were identified:

*   [`import {BaseLBTC} from "./BaseLBTC.sol";`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol#L12) in `BridgeTokenAdapter.sol`.
*   [`import {FeeUtils} from "../libs/FeeUtils.sol";`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L10) in `BridgeV2.sol`
*   [`import {IAdapter} from "./adapters/IAdapter.sol";`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol#L11) in `BridgeV2.sol`
*   [`import {RateLimits} from "../libs/RateLimits.sol";`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/IBridgeV2.sol#L4) in `IBridgeV2.sol`
*   [`import {IBridge} from "../IBridge.sol";`](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/adapters/TokenPool.sol#L7) in `TokenPool.sol`

Consider removing unused imports to improve the overall clarity and readability of the codebase.

_**Update:** Resolved at commit [c1e10be](https://github.com/lombard-finance/smart-contracts/pull/303/commits/c1e10be319848567be744ade9630ea3562d08e23)._

### Missing Security Contact

Providing a specific security contact (such as an email address or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Throughout the codebase, multiple instances of contracts not having a security contact were identified:

*   The [`BridgeTokenAdapter` contract](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/LBTC/BridgeTokenAdapter.sol)
*   The [`BridgeV2` contract](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/BridgeV2.sol)
*   The [`IBridgeV2` interface](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/IBridgeV2.sol)
*   The [`LombardTokenPool` contract](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/adapters/TokenPool.sol)
*   The [`BridgeTokenPool` contract](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/BridgeTokenPool.sol)
*   The [`LombardTokenPoolV2` contract](https://github.com/lombard-finance/smart-contracts/blob/63d407689cb50212992a6bd7ad1b0d0d80ca5287/contracts/bridge/providers/LombardTokenPoolV2.sol)

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved at commit [86409f1](https://github.com/lombard-finance/smart-contracts/pull/303/commits/86409f1827bafaf1e9d16b1c1e933827b95a9860)._

Conclusion
----------

This audit reviewed the `BridgeV2` contract of the Lombard Protocol, which is responsible for burning tokens upon deposit on the source chain and minting them on the destination chain. The Pool contracts designed for integration with the Chainlink CCIP protocol were also examined, along with the Token Adapter contract that enables compatibility with non-standard token interfaces such as that of the BTC.b token.

During the assessment, several medium- and low-severity issues were identified, primarily related to insufficient input validation. Addressing these findings will further strengthen the protocol’s overall security posture.

Overall, the codebase demonstrated high quality and sound design practices. The Lombard team was responsive, collaborative, and professional throughout the engagement, which contributed to a smooth and efficient audit process.