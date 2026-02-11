\- November 10, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

### Summary

**Type:** DeFi  
**Timeline:** June 23, 2025 → July 11, 2025  
**Languages:** Solidity

**Findings**  
Total issues: 13 (9 resolved, 1 partially resolved)  
Critical: 0 (0 resolved)  
High: 0 (0 resolved)  
Medium: 3 (2 resolved)  
Low: 5 (4 resolved, 1 partially resolved)

**Notes & Additional Information**  
5 (3 resolved)

**Client Reported Issues**  
0 (0 resolved)

Scope
-----

We audited [`lombard-finance/smart-contracts`](https://github.com/lombard-finance/smart-contracts) repository at commit [`9e5c6b1`](https://github.com/lombard-finance/smart-contracts/tree/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d) In scope were the following files:

`contracts
├── LBTC
│   ├── AssetRouter.sol
│   ├── BaseLBTC.sol
│   ├── NativeLBTC.sol
│   ├── StakedLBTC.sol
│   ├── StakedLBTCOracle.sol
│   └── libraries
│       ├── Assert.sol
│       ├── Assets.sol
│       ├── Redeem.sol
│       └── Validation.sol
├── gmp
│   ├── Mailbox.sol
│   └── libs
│       ├── GMPUtils.sol
│       └── MessagePath.sol
├── libs
│   ├── Actions.sol
│   └── LChainId.sol
└── stakeAndBake
    └── StakeAndBake.sol` 

After completion of the audit, the Lombard team introduced several changes to the contracts. The main changes were as follows:

*   the previously shared data across all tokens, such as the commision for redeeming for BTC, was made specific to each individual token.
*   the `NativeLBTC` storage structure was fixed to prevent collisions after upgrade, since a previous version has been already deployed in a chain.

These changes, included in commit [`2356372`](https://github.com/lombard-finance/smart-contracts/commit/2356372925a11ccd8bd97ccb00ab098c5aa118e0), were reviewed as part of the fix review process and no additional issues were identified.

Overview
--------

Lombard General Message Passing (GMP) is the cross-chain transport layer that allows LBTC and other Lombard assets to move between different blockchains while preserving 1 to 1 backing and preventing liquidity fragmentation.

On EVM chains, the audited contracts implement the on‑chain half of this transport layer. In particular:

*   **Mailbox.sol**: Emits `MessageSent` events for outbound payloads, verifies notary proofs for inbound payloads, and dispatches them to the receiving contract.
    
*   **GMPUtils.sol & MessagePath.sol**: Libraries that provide deterministic path hashing and other helpers so that off‑chain notaries can reference the same paths.
    
*   **AssetRouter.sol**: Connect LBTC family tokens and GMP. Handles deposits, redemptions, fee accounting and forwarding payloads to the Mailbox.
    
*   **NativeLBTC.sol & StakedLBTC.sol & StakeAndBake.sol**: ERC‑20 wrappers around native BTC or staked LBTC that use the AssetRouter & Mailbox to be able to leverage GMP.
    

### Transport Layer Overview

A message starts when a user calls `Mailbox.sendMessage`, specifying the destination chain and an encoded payload. The Mailbox will check that the path is enabled and the payload is under the max size. It then collects the fees from the user and emits `MessageSent` with the canonical payload hash.

Off‑chain notaries then observe the event, verify the chain specific metadata, and sign the payload hash once a quorum is reached.

Then, on the destination chain a relayer submits the payload and its proof to the `Mailbox.deliverAndHandle`. The Mailbox verifies that the proof passes threshold of notary signatures. It then dispatches the payload to the recipient address. In the `LBTC` flow the recipient is the `AssetRouter` which mints or burns `LBTC` as its required.

The entire flow is stateless on the sending side and its prevents relay attacks on the receiving side thanks to the `payloadHash` mapping.

Security Model and Trust Assumptions
------------------------------------

*   **Honest notaries**: It is assumed that a majority of the notaries from the network behave honestly. A dishonest quorum could forge messages or halt messages by refusing to sign them.
    
*   **Privileged Roles Management**: It is assumed that all privileged roles are held in governance controlled multisigs. A compromised role could take away all the security guarantees on the contracts side. (See Privileged Roles)
    
*   **Reasonable parameters**: `feePerByte` must stay aligned with real relayer costs. Mispricing can either block users (if too high) or expose operators to spam DoS (if too low). Also `dustFeeRate` should be set to a value small enough that doesn't prevent redemptions.
    

### Privileged Roles

**Mailbox**

*   **DEFAULT\_ADMIN\_ROLE**: Allows granting and revoking roles, managing message paths, pausing the contract and setting the default maximum payload size and fee per byte.
    
*   **PAUSER\_ROLE**: Can pause the mailbox, effectively stopping all message sending and receiving.
    
*   **TREASURER\_ROLE**: Can withdraw accumulated fees via `withdrawFee()` and rescue stranded ERC‑20 tokens.
    

**AssetRouter**

*   **DEFAULT\_ADMIN\_ROLE**: Allows managing routes, changing Bascule, Oracle & Mailbox addresses, adjusting token configurations, updating dust fee rate, and toggling global redeem switch.
    
*   **OPERATOR\_ROLE**: Can set the maximum mint commission via `setMaxMintCommission()`.
    
*   **CALLER\_ROLE**: Authorised caller for the staking token, can call `changeRedeemFee()` and `toggleRedeem()` for token.
    

**NativeLBTC/StakedLBTC**

*   **DEFAULT\_ADMIN\_ROLE**: Allows toggling the BTC reedem flag, changing the name, symbol, consortium, treasury, Bascule, AssetRouter, and unpausing the token.
    
*   **PAUSER\_ROLE**: Can pause the token, preventing transfers and mints.
    
*   **MINTER\_ROLE**: Can call `mint()`, `batchMint()`, `burn()` and `transfer()` functions.
    
*   **CLAIMER\_ROLE**: Can execute `mintV1WithFee()/mintWithFee()` and `batchMintV1WithFee()/batchMintWithFee()` functions.
    
*   **OPERATOR\_ROLE**: Defined but not referenced in current code (reserved for future use).
    

**StakedLBTCOracle**

*   **OWNER**: Allows changing the `consortium` address and setting the `maxAheadInterval` parameter,

Medium Severity
---------------

### Missing Lower Bound on User-Specified Fees in Minting

The address holding the `CLAIMER_ROLE` can mint `NativeLBTC` by calling [`mintV1WithFee`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/NativeLBTC.sol#L289-L296) or [`batchMintV1WithFee`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/NativeLBTC.sol#L305-L330), providing a [`DepositBtcActionV1`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/libs/Actions.sol#L15-L22) payload signed by the validators and a `feePayload`, signed by the recipient. The [actual fee applied is the minimum](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/NativeLBTC.sol#L426) of the `maximumFee`, set by the contract owner, and the `fee` specified by the user in the signed `feePayload`.

While the contract ensures that the [fee signed by the user is non-zero](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/libs/Actions.sol#L382-L384), it can be set to arbitrarily small values (e.g. `1 wei`). In such cases, this minimal fee would be applied (even if `maximumFee` is non-zero), rendering the fee mechanism ineffective in preventing denial-of-service (DoS) attacks, its primary intended purpose.

The same issue arises also in the `StakedLBTC` contract.

Consider enforcing a minimum fee threshold (at least when `maximumFee` is not zero) to ensure the minting fee remains an effective mechanism against DoS attacks.

_**Update:** Acknowledged, not resolved. The Lombard team stated:_

> _The nature of both functions (`mintWithFee` and `batchMintWithFee`) presumes that a certain address with CLAIMER role will trigger mint on behalf of the user and pay gas for this transaction. The fee is meant to compensate claimer's expenses. So it is claimer's responsibility to choose mint payloads with the fee level it considers as acceptable. Also depending on situation claimer might decide to subsidize the mint and let it through despite fee accepted by the user is too low. So I do not think any changes are necessary._

### AssetRouter setRoute function doesn't use fromChainId parameter

In the `AssetRouter` contract, the [`setRoute` function](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/AssetRouter.sol#L115) utilizes the `fromToken` and `toChainId` parameters to generate a unique route key.

However the `fromChainId` function parameter is not used at all. There are two possible scenarios, where either the `fromChainId` it is always expected to be the same one, in which then it should not be a function parameter, or where it is expected to support multiple chains.

In the case that it should support different values `fromChainId`, there is a risk in which a identical token address could exist on two different chains, which would cause that the second `setRoute` call would overwrite the first in storage. This is because the `CREATE2` opcode makes creating identical addresses across EVM chains trivial. So if for some reason a token has decided to have the same address across different chains, new routes would overwrite the previous ones causing the router to malfunction.

Consider either removing the `fromChainId` parameter or it to generate the key alongside `fromToken` and \`toChainId.

_**Update:** Resolved in [pull request #248](https://github.com/lombard-finance/smart-contracts/pull/248)._

### Insufficient Input Validation When Updating the Ratio

In the `StakedLBTCOracle` contract, the[`publishNewRatio`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/StakedLBTCOracle.sol#L109-L114) function allows setting a new ratio using a valid signed payload. However, the current implementation lacks sufficient input validation, which can lead to incorrect behavior in contracts relying on the reported ratio:

*   At [initialization](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/StakedLBTCOracle.sol#L81) the`$.switchTime` and `$.currentRatio` are zero, [therefore](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/StakedLBTCOracle.sol#L149-L151) immediately after initialization `$.prevRatio` will be zero. Since the `ratio()` function [returns the `prevRatio`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/StakedLBTCOracle.sol#L157-L163) until the `switchTime` is reached, the ratio returned immediately after initialization is zero. This can cause problems to functions like [`getRate()`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/StakedLBTCOracle.sol#L125-L127), that will revert due to a division by zero.
    
*   The [`_publishNewRatio`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/StakedLBTCOracle.sol#L129-L145) function does not enforce that the provided `switchTime` is not in the past.
    
*   The implementation permits multiple signed payloads with the same `switchTime` but different ratios. Because `switchTime` is not required to be strictly increasing, this opens the door to race conditions where conflicting updates are repeatedly submitted and overwrite one another, resulting in fluctuating ratio values.
    
*   The `prevRatio` [is not necessarily updated](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/StakedLBTCOracle.sol#L149-L151) when a new `ratio` and `switchTime` are being submitted. This can result in the system using an outdated prevRatio beyond the intended period, as can be seen in the following scenario:
    
*   Suppose that `prevRatio = r0`, `currentRatio = r1`, `switchTime = s1` and the current `block.timestamp` is `t1 < s1` . The`ratio()` returns `r0`.
    
*   Someone calls `publishNewRatio()` with `ratio = r2`and `switchTime = s2` . After this call we have `prevRatio` is still `r0` as long as the time is `< s2`, even if it is `> s1` the previous switch time, `currentRatio = r2` and `ratio()` returns`r0`.
    
*   If `publishNewRatio` is called again at `t2 < s2`, after the call we have `prevRatio = r0` again, `currentRatio = r3` etc.
    

Consider initializing the `prevRatio` and apply stricter input validation in `publishNewRatio` to fix the issues described above.

_**Update:** Resolved in [pull request #250](https://github.com/lombard-finance/smart-contracts/pull/250) and [pull request #253](https://github.com/lombard-finance/smart-contracts/pull/253/commits/57d47521b8795bba41a4d38fc1a8f1bf8321a467). The Lombard team implemented a fix that initializes the `prevRatio` to 1 and added extra checks that prevent competing ratio updates. It is still possible to submit a `switchRatio` that is in the past, but this is intentional. The Lombard team also stated:_

> _The possibility to submit switch times that are in the past is intentional. The reason for it is the fast the ratio update payload is to be generated by validator consensus (Ledger consensus), that means we have an consensus agreement about what is correct new ratio and correct switch time. At the same time anyone can submit this payload to the oracle smart-contract. In some chains there might be a delay before transaction is submitted due to different reasons. As a result such transaction might be executed after switch time set in payload. This is not something that we expect to happen every time, but still possible and the payload is still legitimate. Consensus is not supposed to issue payload on demand and individually for each chain._

Low Severity
------------

### Incorrect Selector Value

In the `Assets` library, the `REDEEM_FROM_NATIVE_TOKEN_SELECTOR` has been computed as [`bytes4(keccak256("redeemForBTC(bytes32,bytes,uint64)"))`](https://github.com/lombard-finance/smart-contracts/blob/794ca81b17b6d98af0096a3f2e8758c035a45642/contracts/LBTC/libraries/Assets.sol#L40-L41). However, the [`amount` argument of `encodeRedeemNativeRequest`](https://github.com/lombard-finance/smart-contracts/blob/794ca81b17b6d98af0096a3f2e8758c035a45642/contracts/LBTC/libraries/Assets.sol#L118) is of type `uint256`, not `uint64`. This mismatch can result in incorrect selector computation and encoding.

Consider computing and setting the correct selector value.

_**Update:** Resolved in [pull request #238](https://github.com/lombard-finance/smart-contracts/pull/238/files)._

### Missing check that Redemption Fee is Less than Amount

In [`AssetRouter::calcUnstakeRequestAmount`](https://github.com/lombard-finance/smart-contracts/blob/794ca81b17b6d98af0096a3f2e8758c035a45642/contracts/LBTC/AssetRouter.sol#L394-L418), the redemption fee for the provided token is computed, and then the [difference](https://github.com/lombard-finance/smart-contracts/blob/794ca81b17b6d98af0096a3f2e8758c035a45642/contracts/LBTC/AssetRouter.sol#L405) `amount - redeemFee` is passed to `Validation::calcFeeAndDustLimit` without verifying that `redeemFee` is indeed less than `amount`.

Although the latest versions of Solidity do not allow overflows and will revert if `redeemFee` exceeds `amount`, `calcUnstakeRequestAmount` is a `view` function intended to inform the user of the expected amount after fees. Therefore, it would be better to emit an informative error message if the amount cannot cover the fees.

Consider explicitly checking that `redeemFee` is less than `amount` and revert gracefully with a clear error message if the condition is not met.

_**Update:** Resolved in [pull request #238](https://github.com/lombard-finance/smart-contracts/pull/238/files)._

### Incorrect Enforcement of Total Gas Limit in `batchStakeAndBake`

The [comment](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/stakeAndBake/StakeAndBake.sol#L130) above the `setGasLimit` function suggests that the `gasLimit` represents the total maximum gas that it is allowed to be spent in a [`batchStakeAndBake`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/stakeAndBake/StakeAndBake.sol#L157-L180) operation. However, in practice, this limit is applied [separately to each individual call of `stakeAndBakeInternal`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/stakeAndBake/StakeAndBake.sol#L169) within the batch, rather than the cumulative gas used by the entire batch.

Consider enforcing the `gasLimit` as a cap to the total gas consumed by the batch. Alternatively, if the per-call application of the gas limit is intended, apply this limit also to the [`stakeAndBake`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/stakeAndBake/StakeAndBake.sol#L198-L209) function and update the comment on `setGasLimit` to avoid confusion and better represent the implementation.

_**Update:** Resolved in [pull request #248](https://github.com/lombard-finance/smart-contracts/pull/248/files)._

### Insufficient Error Handling

In the `StakeAndBake` contract, the `batchStakeAndBake` function utilizes a [`try/catch`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/stakeAndBake/StakeAndBake.sol#L169-L175) pattern for each individual `stakeAndBakeInternal` call to ensure that a failure in one operation does not revert the entire batch. However, the current implementation [catches only error messages emitted by failing revert or require statements](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/stakeAndBake/StakeAndBake.sol#L173-L175), but it will not catch `Panic` or custom errors (e.g. those emitted by the `ERC20PermitUpgradeable` contract during a failed signature verification). This limitation can lead to unhandled exceptions, causing full batch reversion.

Consider including a general catch case in the `try/catch` block to ensure that all error types are appropriately handled.

_**Update:** Resolved in [pull request #248](https://github.com/lombard-finance/smart-contracts/pull/248)._

### Potential Conflict with `isNative` Routes When Changing the Native Token in `AssetRouter`

In the `AssetRouter` contract, the owner is responsible for setting allowed routes using the [`setRoute`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/AssetRouter.sol#L115-L140) function. The logic ensures that if either the source or the destination chain is the local chain and the corresponding token of the route is marked as `isNative`, then [it must match the contract's stored nativeToken](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/AssetRouter.sol#L127-L132). Therefore, it prevents defining multiple routes with different `isNative` tokens for the local chain.

However, if the owner [updates the contract's `nativeToken`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/AssetRouter.sol#L300-L304) and then defines a new route for this updated token, the previous route involving the old `nativeToken` will still exist, resulting in a temporary state where two routes for the local chain involve different local `isNative` tokens. This violates the intended uniqueness constraint until the old route is manually removed.

Consider automatically removing the old route when calling `changeNativeToken` function to ensure consistency and prevent possible conflicts.

_**Update:** Partially resolved in [pull request #250](https://github.com/lombard-finance/smart-contracts/pull/250). The Lombard team stated:_

> _We added code that removes what can be removed easily. But changing native token itself is a sort of emergency situation that should not happen even once unless we did a mistake when we configure the contracts. So if it happens we will remove all related routes manually. Again, hope this will never happen even once._

Notes & Additional Information
------------------------------

### Explicit Pause Check Missing

The [`StakedLBTC`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/StakedLBTC.sol) token is `Pausable`, but the [`mint`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/StakedLBTC.sol#L338-L347) and [`mintWithFee`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/StakedLBTC.sol#L376-L383) functions, that can be invoked by anyone providing a valid staking proof, can currently be called even when the contract is paused. This behavior is inconsistent with the [`batchMint`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/StakedLBTC.sol#L354-L366) and [`batchMintWithFee`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/StakedLBTC.sol#L392-L411) functions, which correctly block execution when the contract is paused.

Although calls to `mint` and `mintWithFee` will eventually fail if the contract is paused, since the `AssetRouter` will [call back](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/AssetRouter.sol#L737) the `StakedLBTC`, the [`_update`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/d3a84f4f51f2a8e5b1c89777c0a8733dc94e0eba/contracts/token/ERC20/extensions/ERC20PausableUpgradeable.sol#L36-L38) function will be invoked through `_mint`, which revert when the contract is paused. However it is better to include an explicit pause check, similar to that in `batchMint` and `batchMintWithFee`, to improve code clarity and ensure an early revert saving gas.

Consider adding an explicit check in both `mint` and `mintWithFee` to ensure that they can be called only when the contract is not paused.

_**Update:** Acknowledged, not resolved. The Lombard team stated:_

> _Caller should access AssetRouter directly for all mint-related actions. mint\* functions are left in token contracts for backward compatibility and might be removed in future versions. So we prefer to leave these the way they are._

### Redundant Conditional Branch

In the `AssetRouter:calcUnstakeRequestAmount` function, there is an [`if` statement](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/AssetRouter.sol#L400-L408) that checks whether the token is native or not and calculates the unstake amount accordingly. However, in both the native and non-native case, the unstake amount calculation logic is identical, rendering the `if` statement redundant.

Consider simplifying the code by removing the unnecessary `if` condition. This will reduce code complexity and slightly decrease the gas consumption.

_**Update:** Acknowledged, not resolved. The Lombard team stated:_

> _We might need to have different fee for native and non-native tokens since the nature of tokens and their prices are supposed to be different. So we would like to keep the code like it is now to simplify future updates of this kind._

*   The [`GMPUtils::bytes32ToAddress()`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/gmp/libs/GMPUtils.sol#L101-L106) function converts a `bytes32` input to an `address` by discarding the higher 12 bytes. A [comment](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/gmp/libs/GMPUtils.sol#L97) warns the user that many different inputs could be decoded to the same address. However, this warning is misleading. The function includes an [explicit check](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/gmp/libs/GMPUtils.sol#L102-L104) to ensure that the higher 12 bytes are zero and reverts otherwise, guaranteeing a one-to-one mapping from valid inputs to addresses. Consider updating the comment to accurately reflect the function's behavior
    
*   In `Actions.sol` the [comment](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/libs/Actions.sol#L47-L52) above `struct RatioUpdate` is not related to the structure and should be removed.
    

Consider fixing these comments to improve clarity and maintainability for users and developers.

_**Update:** Resolved in [pull request #250](https://github.com/lombard-finance/smart-contracts/pull/250)._

### Gas Optimization Opportunities

*   In the [`Mailbox::deliverAndHandle()`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/gmp/Mailbox.sol#L407-L430) function, the `rawPayload` is first [decoded](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/gmp/Mailbox.sol#L419-L421) to get the `payload` and subsequently `payloadHash` is [computed](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/gmp/Mailbox.sol#L422) as the `hash()` of `rawPayload`. However, this hash has been already computed during decoding and is available as [`payload.id`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/gmp/libs/GMPUtils.sol#L73). Consider using the `payload.id` instead of recalculating the`hash(rawPayload)`, to reduce gas consumption and simplify the code.
    
*   In the `AssetRouter::_AssetRouter_init()` function, there is an [initial check](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/AssetRouter.sol#L102-L104) to ensure that the provided `mailbox_` is not the zero address. However, this same check is performed again in the [`_changeMailbox`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/AssetRouter.sol#L773) function. Consider removing the initial zero address check to eliminate redundancy and reduce gas consumption.
    

Consider fixing these issues to optimize gas usage.

_**Update:** Resolved in [pull request #250](https://github.com/lombard-finance/smart-contracts/pull/250)._

### Unrestricted Empty `reinitialize()` Function

In the `StakedLBTC` contract, there is an empty [`reinitialize()`](https://github.com/lombard-finance/smart-contracts/blob/9e5c6b10e2fb8d06aed0dfa4fe6a34ca73b4721d/contracts/LBTC/StakedLBTC.sol#L115C4-L115C57) function with a `reinitializer(2)` modifier, but no access control. While this function has no other effect on the contract, calling it will still increment the version ([`_initialized`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/8e72027e9deb1c0a7b6b00972f95621e7cb5bc66/contracts/proxy/utils/Initializable.sol#L152-L164) variable) to 2, which could be confusing for users monitoring the contract.

Consider removing the `reinitialize()` function or if you plan to add logic to it in a future update, ensure appropriate access control is in place.

_**Update:** Resolved at commit [3217859](https://github.com/lombard-finance/smart-contracts/pull/252/commits/3217859848d48003c8e66f4ae76da0c032daaccb)._ 

Conclusion
----------

In this audit, we examined the contracts of the GMP Protocol and the changes made to the Lombard contracts to integrate with it. The code was well written, accompanied by an extensive test suite. No critical vulnerabilities were identified, but a few medium and low severity issues were found.

The Lombard team was cooperative, providing all necessary context and responded promptly to our questions, enabling a smooth and effective audit process.