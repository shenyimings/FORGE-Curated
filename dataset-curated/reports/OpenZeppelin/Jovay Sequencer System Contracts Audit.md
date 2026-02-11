\- October 16, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary

**Type:** Layer 2 & Rollups  
**Timeline:** September 10, 2025 → September 22, 2025  
**Languages:** Solidity

**Findings**  
Total issues: 39 (38 resolved, 1 partially resolved)  
Critical: 0 (0 resolved) · High: 0 (0 resolved) · Medium: 11 (11 resolved) · Low: 10 (10 resolved)

**Notes & Additional Information**  
18 notes raised (17 resolved, 1 partially resolved)

Scope
-----

OpenZeppelin audited the [jovaynetwork/jovay-contracts](https://github.com/jovaynetwork/jovay-contracts) repository at commit [24f525f](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/).

Following the conclusion of the fix review, the final post-audit commit is [bdaf093a](https://github.com/jovaynetwork/jovay-contracts/tree/bdaf093ad7061824cba02021da76a25217355451).

In scope were the following files:

`sequencer_contracts
└── sys_contract
    └── artifact_src
        └── solidity
            ├── permission_control.sol
            ├── rule_mng.sol
            ├── sys_chaincfg.sol
            └── sys_staking.sol` 

System Overview
---------------

The Jovay Network is a Layer-2 network with a focus on delivering high performance and high security. It intends to achieve a high transaction throughput through a parallel-execution design which splits transactions into separate units for concurrent processing. In terms of transaction processing, the transactions are executed in parallel based on the write set information of the current block. A write set allows the sequencer to infer execution possibilities without execution of the contract. Transactions within the same group are to be executed within the order they appeared in the block. Groups should not have conflicting writes, but, should this happen, the transactions are retried serially as they appear within the block.

The audited contracts focused on permission control, rule management, chain configuration, and validator management:

*   The `PermissionControl` contract implements access control for administrator and grantee privileges, as well as the associated privilege management functions required for operations in the `InferRuleManager` contract.
*   The `InferRuleManager` contract is responsible for allowing grantees to add, remove, or modify rules within the system. These rules are used for determining the possible read/write sets of a target contract without its execution. The `InferRuleManager` also implements the logic needed to update rule states as they are evaluated for correctness. At the time of the audit, it was indicated that the initial mainnet deployment would not grant any administrator or grantee rights to any accounts. Thus, the `InferRuleManager` contract may be unused initially.
*   The `ChainCfg` contract stores a record (in checkpoint format) of the configurations for specific key-value pairs related to epoch operations. In addition, it allows the `DPoSValidatorManager` contract, or the intrinsic system address, to set the next config to be used.
*   The `DPoSValidatorManager` contract contains the logic needed to advance epochs and set the next stored config through the `ChainCfg` contract. In addition, it contains logic for the management of validators. It was indicated that the version under audit was a simplified contract with staking functionality removed.

Security Model and Trust Assumptions
------------------------------------

The following trust assumptions were made during the audit:

*   The Jovay team indicated that the zero address has the ability to call functions in sequencer system contracts on the network and that it would be under the team's control.
*   It is assumed that the intrinsic system address (`0x1111111111111111111111111111111111111111`) is used as the sender of some sequencer system contracts by chain code.
*   It is assumed that the off-chain components of the network, which may integrate with the in-scope contracts, operate as intended.

### Privileged Roles

The audited contracts implement custom access control for sensitive functions.

Within the `PermissionControl` and the `InferRuleManager` contracts:

*   **`_administrator`**: granted to the deployer of the contract and is responsible for adding accounts to the `grantees_` array, removing addresses from the `grantees_` array, and transferring the super administrator role to another account.
*   **`grantee`**: granted by the `_administrator` account and has the ability to add any rule, or delete or modify rules of which it is the owner.

Within the `InferRuleManager` contract:

*   **`_administrator`**: granted to the deployer of the contract and is responsible for adding accounts to the `grantees_` array, removing addresses from the `grantees_` array, updating the proving results, and transferring the super administrator role to another account.
*   **`grantee`**: granted by the `_administrator` account and has the ability to add any rule, or delete or modify rules of which they are the owners.

The `ChainCfg` contract implements an `onlyOwner` modifier which allows any one of three addresses to change the current `rootSys` address or set the chain configuration. These three accounts are:

*   **`rootSys`**: at deployment time, this is the zero address.
*   **`sysStaking`**: this is the address where the `DPoSValidatorManager` contract is to be deployed (`0x4100000000000000000000000000000000000000`).
*   **`intrinsicSys`**: this is assumed to be a Jovay-controlled system address (`0x1111111111111111111111111111111111111111`).

In the `DPoSValidatorManager` contract, `intrinsicSys` is assumed to be a Jovay-controlled system address (`0x1111111111111111111111111111111111111111`) that has the ability to call the two variants of `advanceEpoch` found within the contract.

Medium Severity
---------------

### Incorrect Return Value in `getWithdrawEffectiveWindow`

The [`getWithdrawEffectiveWindow` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2644-L2648) of the `DPoSValidatorManager` contract contains two issues that cause incorrect return values:

*   `Strings.parseUint` returns a `uint256` value which is then cast to `uint8`, creating a truncation risk. If the configuration value exceeds 255, the function will return an incorrect truncated value.
*   `parseUint` returns 0 when given empty input, and since `SysChainCfg` returns empty strings for non-existent keys, this function silently returns 0 when the configuration key is unset rather than failing explicitly.

These issues can lead to incorrect withdrawal timing calculations, potentially allowing premature withdrawals or blocking legitimate ones depending on the intended configuration values.

Consider changing the return type of the `getWithdrawEffectiveWindow` function to `uint256` in order to prevent truncation and adding validation to revert when `getChainCfg` returns empty strings to ensure that the configuration key exists before parsing.

_**Update:** Resolved in [pull request #12](https://github.com/jovaynetwork/jovay-contracts/pull/12). The Jovay team stated:_

> _We have fixed this by removing the unused function._

### `_transferTo` Silently Ignores Failure

The [`_transferTo` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2518-L2552) of the `DPoSValidatorManager` contract silently handles transfer failures by emitting events instead of reverting or returning a success status. When transfers fail due to insufficient balance or call failures, the function emits an `ErrorOccurred` event and returns without indicating failure to the caller. This design prevents calling functions from knowing whether transfers succeeded, potentially leading to inconsistent contract state where the contract believes a transfer occurred while it actually failed.

Consider either reverting on transfer failures to ensure atomicity, or returning a boolean success value so that the calling functions can handle failures appropriately.

_**Update:** Resolved in [pull request #13](https://github.com/jovaynetwork/jovay-contracts/pull/13). The Jovay team stated:_

> _We fixed this by removing the unused function._

### `view` Functions Return Future-Dated Chain Configuration

The [`get_config`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L40) and [`get_configs`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L52) functions always return the latest checkpoint without checking if it is effective. When [`set_config`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L74) creates a checkpoint, it sets `effectiveBlockNum` to `block.number + 1`, meaning the configuration should only become active in the next block. This allows transactions in the same block as a configuration update to immediately use the new parameters, defeating the intended one-block delay. The deferred activation mechanism becomes ineffective, potentially causing inconsistency between components that expect the delay.

Consider modifying the getter functions to check `effectiveBlockNum <= block.number` before returning a checkpoint, falling back to the previous effective checkpoint if the latest one is not yet active.

_**Update:** Resolved in [pull request #22](https://github.com/jovaynetwork/jovay-contracts/pull/22)._

### Native Tokens Can Become Stuck in `DPoSValidatorManager`

The `DPoSValidatorManager` contract has a `payable` [`receive`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2657-L2665) function that emits a `BalanceReceived` event when it [receives](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2658-L2664) native tokens. However, the contract does not expose any way to transfer native tokens out of the contract. Thus, any funds received remain locked in the contract.

Consider removing the `receive` function if the contract is not intended to handle native token transfers.

_**Update:** Resolved in [pull request #19](https://github.com/jovaynetwork/jovay-contracts/pull/19). The Jovay team stated:_

> _We fixed this by removing the unused code._

### Metahash Filter Not Implemented in Rule-Existence Check

The [`checkExist` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L50) only checks for address and selector matches but ignores the `metahash` parameter when determining rule existence. Although `metahash` is documented as a filter value in the [`InferRule` struct](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L15), the `checkExist` function only uses it in a `require` statement to ensure that both the address and the metahash are not zero. This prevents adding multiple rules with the same contract address and selector but different metahashes, as [`addRule`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L130) will fail with "InferRule already exist" even when the metahash differs. The implementation contradicts the design where metahash should serve as a filter for rule selection.

Consider verifying the intended purpose of metahash in the rule filtering system. If metahash should function as a filter, modify the `checkExist` function to include metahash comparison alongside the address and selector checks.

_**Update:** Resolved in [pull request #19](https://github.com/jovaynetwork/jovay-contracts/pull/19). The Jovay team stated:_

> _We fixed this by removing the relevant code._

### Missing Rule Manager Epoch Advance

The [`advanceEpoch` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2585) in `DPoSValidatorManager` does not call the [`advanceEpoch` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L318) of the `InferRuleManager` contract.`InferRuleManager`'s epoch advancement transitions rules from `INIT`/`UPDATED` states to `IN_PROVING` and from `PROVING_SUCCESS` to `IN_USE` states. Without coordination between these epoch functions, rule state transitions may become desynchronized from validator epoch changes, potentially affecting rule activation timing.

Consider calling `InferRuleManager`'s `advanceEpoch` function within the `DPoSValidatorManager`'s epoch advancement if synchronized rule and validator state transitions are intended.

_**Update:** Resolved in [pull request #19](https://github.com/jovaynetwork/jovay-contracts/pull/19). The Jovay team stated:_

> _We fixed this by removing the relevant code._

### Unreadable Historical Checkpoints

The `ChainCfg` contract stores configuration checkpoints but only exposes the latest one through [`get_config`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L40) and [`get_configs`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L52). The `configCps` array is `private`, making historical checkpoints inaccessible. This design stores checkpoint data without providing any way to access it, reducing the utility of the checkpoint mechanism. The checkpoint system appears to be incomplete since historical configurations cannot be queried, limiting the contract's ability to provide the configuration history.

Consider either exposing functions to read historical checkpoints if historical data access is intended, or simplifying the design by removing the checkpoint mechanism in case only the current configuration matters.

_**Update:** Resolved in [pull request #23](https://github.com/jovaynetwork/jovay-contracts/pull/23) which limits the size of the `configCps` array to one item._

### `updateValidator` Calls Will Fail

The `DPoSValidatorManager` contract is missing functionality that is required for the successful operation of the `updateValidator` function. The [`updateValidator`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2554-L2577) function is intended to allow owners to update the details of their validators. However, the function suffers from a self-inflicted DoS because the `DPoSValidatorManager` contract has no methods for adding validators. This could be indicative of unimplemented logic, and it creates confusion around the purpose of the `DPoSValidatorManager` contract for system integrators.

Since `updateValidator` is a `public` function that relies on missing logic, consider implementing the logic required for validators to be added. If such logic is not needed within this deployment, consider removing the `updateValidator` function to improve code clarity and avoid calls which are guaranteed to fail.

_**Update:** Resolved in [pull request #19](https://github.com/jovaynetwork/jovay-contracts/pull/19). The Jovay team stated:_

> _We fixed this by removing the affected code._

### Grantees Can Approve or Deny Any Rules in Proving

The `InferRuleManager` contract allows grantees to add rules which are used to infer the read/write set for specific contracts. These rules, when adding [new entries](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L134) or updating [existing rules](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L165), are set to an `INIT` or `UPDATED` state, before they are moved to an `IN_PROVING` state during a call to [`advanceEpoch`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L324-L330). During this call, the rules that are in proving are [emitted](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L339) for off-chain components to prove. The result of this proving is provided through a call to [`updateProvingResult`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L283-L310), which updates the rule state to either `PROVING_SUCCESS` or `PROVING_FAILURE`.

However, the `updateProvingResult` function is access-controlled through the [`checkAdminPermission`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L89-L95) function, which checks if a caller is either the `administrator_` or a current `grantee_`. Consequently, grantees are able to bypass proving by calling `updateProvingResult` as soon as their rules are set to `IN_PROVING`. In addition, a grantee is also able to grief other grantees by marking their rules as `PROVING_FAILURE`, forcing those grantees to update their rules in order to be proven again.

Consider replacing the `checkAdminPermission` check in `updateProvingResult` with the [`checkSuperPermission`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L70-L76) function to prevent grantees from approving their own rules or griefing other grantees.

_**Update:** Resolved in [pull request #19](https://github.com/jovaynetwork/jovay-contracts/pull/19). The Jovay team stated:_

> _We fixed this by removing `InferRuleManager`._

### Metahash Parameter Not Used in Permission Check

The [`checkPermission(_metahash)` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L97) does not use the `_metahash` parameter meaningfully in its permission logic. The function returns `true` if the caller has admin permissions, but when admin permissions fail, it only checks if `_metahash` is non-zero before returning `false`, without implementing any metahash-based authorization logic. This suggests that the function may be incomplete or the metahash parameter serves no intended purpose, potentially indicating unfinished functionality.

Consider reevaluating the intended design and comparing it with the current implementation. If metahash-based authorization is not intended, remove the `checkPermission(_metahash)` function and use `checkAdminPermission` directly.

_**Update:** Resolved in [pull request #19](https://github.com/jovaynetwork/jovay-contracts/pull/19/files). The team stated:_

> _We fixed this by removing the relevant code._

### `DPoSValidatorManager` Contains Unnecessary Logic

The version of the [`DPoSValidatorManager`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2335-L2666) contract under review has been modified to remove some functionality that is unnecessary for the current deployment. However, this process has left code remnants that appear to be unused. This creates difficulty for integrators as it obfuscates the intended purpose of the contract.

The [`hexStringToBytes`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2442-L2465) `public` function is unused and can be removed:

The following `internal` functions are unused and can be removed:

*   [`sliceBytes`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2467-L2477)
*   [`fromHexChar`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2479-L2490)
*   [`_transferTo`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2518-L2552)
*   [`getWithdrawEffectiveWindow`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2644-L2648)
*   [`getChainCfg`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2650-L2655)

The following state variables and constants can be removed (unless required by some other off- or on-chain component):

*   [`validators`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2353) (as well as the associated [`Validator`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2337-L2351) struct)
*   [`MIN_VALIDATOR_STAKE`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2358)
*   [`MIN_DELEGATOR_STAKE`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2359)
*   [`MIN_POOL_STAKE`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2360)
*   [`MAX_POOL_STAKE`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2361)
*   [`EPOCH_DURATION`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2362)

The following events can be removed:

*   [`DomainUpdate`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2372-L2380)
*   [`ValidatorReward`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2390-L2398)
*   [`ValidatorWithdrawStake`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2400-L2407)
*   [`StakeAdded`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2408-L2412)
*   [`ValidatorRegistered`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2413-L2416)
*   [`ValidatorExitRequested`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2418)
*   [`ErrorOcurred`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2420-L2425) (only used within the unused `_transferTo` function)

The `DPoSValidatorManager` contract inherits [`ReentrancyGuard`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2336). However, the `nonReentrant` modifier is not used (or required) within the contract, and so the import can be removed.

In addition to the above, consider implementing the following changes:

*   The `_poolId` and `_priority_fees` [parameters](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2586-L2587) in `advanceEpoch` serve no purpose within the function and can be removed.
*   [`pendingAddPoolIds`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2355) and [`pendingExitPoolIds`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2356) will always be empty arrays, as there is no method to add values to these arrays. These arrays and their associated viewers ([`isValidatorPendingAdd`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2508-L2510), [`isValidatorPendingExit`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2512-L2516), [`getPendingAddValidators`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2628-L2634), and [`getPendingExitValidators`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2636-L2642)) can be removed as they serve no functional purpose.
*   Similarly to the above, [`activePoolIds`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2354) is only used within the [`EpochChange`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2602) event, but it will always be an empty array. Thus, the field can be removed from the aforementioned event, along with `activePoolIds` and its associated `view` functions ([`isValidatorActive`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2504-L2506) and [`getActiveValidators`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2624-L2626)) can be removed.

Since there is a large amount of unused logic within the `DPoSValidatorManager` contract, in the interest of improved code clarity, gas efficiency, and maintainability, consider removing or modifying the aforementioned components.

_Note that the changes suggested above, together with the changes recommended within the issue "Inefficient Key Value Storage" would allow the contract size to shrink drastically from 2666 lines to around 140 lines._

_**Update:** Resolved in [pull request #19](https://github.com/jovaynetwork/jovay-contracts/pull/19/files). The Jovay team stated:_

> _We have already deployed a version of the code to the testnet. To maintain storage layout compatibility for the upgrade, the following variables and inherited contracts cannot be removed._
> 
> *   _`validators` (as well as the associated `Validator` struct)_
> *   _`ReentrancyGuard`_
> *   _`pendingAddPoolIds`_
> *   _`pendingExitPoolIds`_
> *   _`activePoolIds`_
> 
> _Aside from the above, we have removed the related code to fix this problem._

Low Severity
------------

### Incomplete Test Suite

The sequencer contracts lack a test suite within the provided repository. Without test coverage, bugs may go undetected during development and future changes may introduce regressions.

Consider implementing a comprehensive test suite using a framework like Foundry or Hardhat.

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

### Non-Standard Development Practices

The project uses flattened files instead of importing dependencies, lacks a development framework like Foundry or Hardhat, and follows unconventional naming conventions. File names like `sys_staking.sol` and `rule_mng.sol` use `snake_case` instead of the standard `PascalCase` convention (e.g., `DPoSValidatorManager.sol`, `InferRuleManager.sol`, etc.). These practices make the codebase harder to maintain, reduce tooling compatibility, and deviate from established Solidity community standards.

Consider adopting a standard development framework, using imports for dependencies, and following conventional naming patterns.

_**Update:** Resolved in [pull request #53](https://github.com/jovaynetwork/jovay-contracts/pull/53)._

### Insufficient Documentation and Comments

The codebase lacks documentation and has sparse inline comments. The [`DPoSValidatorManager` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2336) and other contracts contain unexplained variables and functions without NatSpec documentation. This makes it difficult to verify the intended behavior and requires making assumptions during code review, increasing the likelihood for bugs to be missed.

Consider adding comprehensive inline comments, NatSpec documentation for all `public` functions, and detailed explanations for any complex logic and state variables.

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47) and [pull request #58](https://github.com/jovaynetwork/jovay-contracts/pull/58/commits)._

### Code Duplication in `InferRuleManager`

The [`InferRuleManager`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol) contract duplicates all the functions and events that are found within the [`PermissionControl`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol) contract.

To simplify the contract design and improve code clarity, consider importing the `PermissionControl` contract instead of reimplementing its logic within `InferRuleManager`.

_**Update:** Resolved in [pull request #19](https://github.com/jovaynetwork/jovay-contracts/pull/19/files). The Jovay team stated:_

> _We fixed this by removing `rule_mng.sol`._

### Floating Pragma

Pragma directives should be fixed to clearly identify the Solidity version with which the contracts will be compiled.

Throughout the codebase, multiple instances of floating pragma directives were identified:

*   `permission_control.sol` has the [`solidity ^0.8.20`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L3) floating pragma directive.
*   `rule_mng.sol` has the [`solidity ^0.8.20`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L2) floating pragma directive.
*   `sys_chaincfg.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L2) floating pragma directive.
*   `sys_staking.sol` has the [`solidity ^0.8.20`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2) floating pragma directive.

Consider using fixed pragma directives.

_**Update:** Resolved in [pull request #44](https://github.com/jovaynetwork/jovay-contracts/pull/44/files)._

### Missing Zero-Address Checks

When operations with address parameters are performed, it is crucial to ensure that the address is not set to zero. Setting an address to zero is problematic because it has special burn/renounce semantics. This action should be handled by a separate function to prevent accidental loss of access during value or ownership transfers.

Throughout the codebase, multiple instances of missing zero-address checks were identified:

*   The [`_new_admin`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L49) operation within the contract `PermissionControl` in `permission_control.sol`
*   The [`_addr`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L70) operation within the contract `PermissionControl` in `permission_control.sol`
*   The [`_new_admin`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L367) operation within the contract `InferRuleManager` in `rule_mng.sol`
*   The [`_addr`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L388) operation within the contract `InferRuleManager` in `rule_mng.sol`

Consider always performing a zero-address check before assigning a state variable.

_**Update:** Resolved in [pull request #43](https://github.com/jovaynetwork/jovay-contracts/pull/43)._

### Empty Constructors

The [`DPoSValidatorManager`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2435) and [`ChainCfg`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L25) contracts have empty constructors that serve no purpose. In `ChainCfg`, the `rootSys` variable remains uninitialized, which may indicate missing initialization logic. Empty constructors add unnecessary code without functionality and may indicate incomplete initialization.

Consider removing the empty constructors or adding proper initialization logic, particularly for `ChainCfg`'s `rootSys` variable if initialization is intended.

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

### Wrong Revert Message in `updateValidator`

The [`updateValidator` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2563) uses the same error message ("Validator does not exist") for two different validation checks. The second `require` statement checks ownership but uses an incorrect error message that should indicate unauthorized access rather than non-existence.

Consider using a more appropriate error message like "Not validator owner".

_**Update:** Resolved in [pull request #19](https://github.com/jovaynetwork/jovay-contracts/pull/19/files)._

During development, having well described TODO/Fixme comments will make the process of tracking and solving them easier. However, these comments might age and important information for the security of the system might be forgotten by the time it is released to production. As such, they should be tracked in the project's issue backlog and resolved before the system is deployed.

Throughout the codebase, multiple instances of TODO/Fixme comments were identified:

*   The TODO comment in [line 7 of `permission_control.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L7)
*   The TODO comment in [line 2570 of `sys_staking.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2570)

Consider removing all instances of TODO/Fixme comments and instead tracking them in the issues backlog. Alternatively, consider linking each inline TODO/Fixme to the corresponding issues backlog entry.

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

### Incorrect `AdminRevoked` Event Parameter

The [`AdminRevoked` event](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L73) declares its parameter as `revoker`, implying it should log the address performing the revocation. However, the [`revokeAdmin` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L88) emits the revoked address instead of the revoker's address. This mismatch between parameter name and actual value could confuse off-chain tools and create incorrect audit trails.

Consider either renaming the event parameter to `revoked` or emitting `msg.sender` to match the intention behind the parameter name.

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

Notes & Additional Information
------------------------------

### Old Library Version

The [`DPoSValidatorManager` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2336) uses OpenZeppelin contracts version `5.1.0`, whereas the latest version is `5.4.0`.

Consider updating to the latest OpenZeppelin version to benefit from security improvements and additional functions within the `Strings` library.

_**Update:** Resolved in [pull request #58](https://github.com/jovaynetwork/jovay-contracts/pull/58). The `Strings` library was updated to `5.4.0`. The `ReentrancyGuard` contract was left as it is for storage-slot compatibility. The Jovay team stated:_

> _Considering the versions already deployed, upgrading to 5.4.0 would introduce storage-slot incompatibilities. To maintain compatibility, additional variables would need to be added. Since this compatibility change does not improve security but imposes an additional readability cost, the upgrade will not be considered at this time._

### Linear Complexity Creates DoS Vectors

Multiple contracts use unbounded arrays with linear time operations that can lead to self-inflicted DoS as the arrays grow. In [`ChainCfg.set_config`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L60), each configuration update loops through all existing configs, resulting in quadratic time complexity. The [`get_config` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L40) performs linear searches through the config array. In addition, once a config is set it cannot be removed, and combined with the quadratic cost of adding configs, keeping unused configs becomes problematic. Once a DoS situation is reached, it becomes impossible to add more configs with there being no way of clearing the stale ones.

In [`InferRuleManager`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol), functions like [`checkExist`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L55), [`delRule`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L204), [`updateRule`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L169), and [`advanceEpoch`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L322) all perform linear time array iterations. The [`DPoSValidatorManager`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2492) uses linear time array searches in [`isArrayContains`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2492). [`PermissionControl`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol) has linear time operations in [`checkGrantPermission`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L31) and [`revokeAdmin`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L80). As these arrays grow, gas costs increase linearly or quadratically, eventually reaching block gas limits and preventing further operations. This creates practical limits on configuration entries, rule additions, and validator operations.

Consider using `EnumerableSet` or `EnumerableMap` (part of the OpenZeppelin contracts library) for constant-time lookups and additions. For `ChainCfg`, consider using the OpenZeppelin `Checkpoints` library which provides logarithmic time complexity for historical data queries.

_**Update:** Partially resolved in [pull request #23](https://github.com/jovaynetwork/jovay-contracts/pull/23) by reducing the maximum size of the `configCps` array to two checkpoints (the effective checkpoint and the pending checkpoint). The Jovay team stated:_

> _We have fixed this. Currently, only the system admin can set these configurations. The number of chain configurations is currently limited. Adding chain configurations is a significant change that requires updating the overall software version. There are currently no plans to add any. Since this interface will not be called by external users, there is a low risk of this issue occurring in practice._

### Variable Could Be `immutable`

If a variable is only ever assigned a value from within the `constructor` of a contract, it should be declared as `immutable`.

Within `rule_mng.sol`, the [`prove_threshold_` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L39) could be made `immutable`.

To better convey the intended use of variables and to potentially save gas, consider adding the `immutable` keyword to variables that are only set in the constructor.

_**Update:** Resolved in [pull request #19](https://github.com/jovaynetwork/jovay-contracts/pull/19/files). The Jovay team stated:_

> _We fixed this by removing `rule_mng.sol`._

### Unused Enum

In `rule_mng.sol`, the [`CreateMethod` enum](https://github.com/jovaynetwork/jovay-contracts/tree/audit/mainnet/dev/blob/24f525f379558eed27441f7233e5921591e0063d/solidity/rule_mng.sol#L7) is unused.

To improve the overall clarity, intentionality, and readability of the codebase, consider either using or removing any currently unused enums.

_**Update:** Resolved in [pull request #19](https://github.com/jovaynetwork/jovay-contracts/pull/19/files). The Jovay team stated:_

> _We fixed this by removing `rule_mng.sol`._

### Use Custom Errors

Since Solidity version 0.8.4, custom errors provide a cleaner and more cost-efficient way to explain to users why an operation failed. Throughout the codebase, the `require` statements use strings instead of custom errors.

For conciseness and gas savings, consider replacing `require` and `revert` messages with custom errors.

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

### Unused Function With `internal` or `private` Visibility

The [`checkAdminPermission` function](https://github.com/jovaynetwork/jovay-contracts/tree/audit/mainnet/dev/blob/24f525f379558eed27441f7233e5921591e0063d/solidity/permission_control.sol#L22-L28) in `permission_control.sol` is unused.

To improve the overall clarity, intentionality, and readability of the codebase, consider using or removing any currently unused functions.

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

### Lack of Indexed Event Parameters

Throughout the codebase, multiple instances of events not having any indexed parameters were identified:

*   The [`SuperTransferred` event](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L40-L43) of `permission_control.sol`
*   The [`AdminGranted` event](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L63-L65) of `permission_control.sol`
*   The [`AdminRevoked` event](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L73-L75) of `permission_control.sol`
*   The [`RuleAdded` event](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L116-L126) of `rule_mng.sol`
*   The [`RuleUpdated` event](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L146-L156) of `rule_mng.sol`
*   The [`RuleDeleted` event](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L192-L195) of `rule_mng.sol`
*   The [`ProvingResultUpdated` event](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L277-L281) of `rule_mng.sol`
*   The [`SuperTransferred` event](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L358-L361) of `rule_mng.sol`
*   The [`AdminGranted` event](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L381-L383) of `rule_mng.sol`
*   The [`AdminRevoked` event](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L391-L393) of `rule_mng.sol`

To improve the ability of off-chain services to search and filter for specific events, consider [indexing event parameters](https://solidity.readthedocs.io/en/latest/contracts.html#events).

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47). Most of the instances were contained within the now-removed `InferRuleManager` contract._

### State Variable Visibility Not Explicitly Declared

Within `sys_chaincfg.sol`, the [`configCps` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L17) lacks an explicitly declared visibility.

For improved code clarity, consider always explicitly declaring the visibility of state variables, even when the default visibility matches the intended visibility.

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

### Use of `uint/int` Instead of `uint256/int256`

`uint/int` is an alias for `uint256/int256`. However, for clarity and consistency, it is recommended to use `uint256/int256` explicitly in contracts.

Throughout the codebase, multiple instances of `uint/int` being used instead of `uint256/int256` were identified:

*   The [`uint`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L204) in `rule_mng.sol`
*   The [`uint`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L224) in `rule_mng.sol`
*   The [`uint`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2423) in `sys_staking.sol`
*   The [`uint`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2456) in `sys_staking.sol`
*   The [`uint`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2469) in `sys_staking.sol`
*   The [`uint`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2470) in `sys_staking.sol`
*   The [`uint`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2473) in `sys_staking.sol`
*   The [`uint`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2496) in `sys_staking.sol`
*   The [`uint`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2518) in `sys_staking.sol`
*   The [`uint`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2520) in `sys_staking.sol`
*   The [`uint`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2538) in `sys_staking.sol`

In favor of explicitness, consider replacing all instances of `int/uint` with `int256/uint256`.

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47). The Jovay team stated:_

> _We fixed this by removing `rule_mng.sol`._

### Function Visibility Overly Permissive

Throughout the codebase, multiple instances of functions having overly permissive visibility were identified:

*   The [`checkSuperPermission`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L14-L20) function in `permission_control.sol` with `internal` visibility could be limited to `private`.
*   The [`checkAdminPermission`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L22-L28) function in `permission_control.sol` with `internal` visibility could be limited to `private`.
*   The [`checkGrantPermission`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L30-L38) function in `permission_control.sol` with `internal` visibility could be limited to `private`.
*   The [`getSuperAdmin`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L54-L56) function in `permission_control.sol` with `public` visibility could be limited to `external`.
*   The [`getGranteeAdmin`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L59-L61) function in `permission_control.sol` with `public` visibility could be limited to `external`.
*   The [`addRule`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L128-L144) function in `rule_mng.sol` with `public` visibility could be limited to `external`.
*   The [`updateRule`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L158-L190) function in `rule_mng.sol` with `public` visibility could be limited to `external`.
*   The [`delRule`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L196-L242) function in `rule_mng.sol` with `public` visibility could be limited to `external`.
*   The [`getAllRules`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L245-L259) function in `rule_mng.sol` with `public` visibility could be limited to `external`.
*   The [`getNextId`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L262-L264) function in `rule_mng.sol` with `public` visibility could be limited to `external`.
*   The [`getContractRules`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L267-L275) function in `rule_mng.sol` with `public` visibility could be limited to `external`.
*   The [`updateProvingResult`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L283-L310) function in `rule_mng.sol` with `public` visibility could be limited to `external`.
*   The [`getSuperAdmin`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L372-L374) function in `rule_mng.sol` with `public` visibility could be limited to `external`.
*   The [`getGranteeAdmin`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L377-L379) function in `rule_mng.sol` with `public` visibility could be limited to `external`.
*   The [`changeSys`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L33-L38) function in `sys_chaincfg.sol` with `public` visibility could be limited to `external`.
*   The [`get_config`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L40-L50) function in `sys_chaincfg.sol` with `public` visibility could be limited to `external`.
*   The [`get_configs`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L52-L58) function in `sys_chaincfg.sol` with `public` visibility could be limited to `external`.
*   The [`hexStringToBytes`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2442-L2465) function in `sys_staking.sol` with `public` visibility could be limited to `external`.
*   The [`sliceBytes`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2467-L2477) function in `sys_staking.sol` with `internal` visibility could be limited to `private`.
*   The [`_fromHexChar`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2479-L2490) function in `sys_staking.sol` with `internal` visibility could be limited to `private`.
*   The [`isArrayContains`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2492-L2502) function in `sys_staking.sol` with `internal` visibility could be limited to `private`.
*   The [`isValidatorPendingExit`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2512-L2516) function in `sys_staking.sol` with `public` visibility could be limited to `external`.
*   The [`_transferTo`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2518-L2552) function in `sys_staking.sol` with `internal` visibility could be limited to `private`.
*   The [`advanceEpoch`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2579-L2583) function in `sys_staking.sol` with `public` visibility could be limited to `external`.
*   The [`setChainEpochBlock`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2606-L2622) function in `sys_staking.sol` with `internal` visibility could be limited to `private`.
*   The [`getWithdrawEffectiveWindow`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2644-L2648) function in `sys_staking.sol` with `internal` visibility could be limited to `private`.
*   The [`getChainCfg`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2650-L2655) function in `sys_staking.sol` with `internal` visibility could be limited to `private`.

To better convey the intended use of functions and to potentially realize some additional gas savings, consider changing a function's visibility to be only as permissive as required.

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

### Lack of SPDX License Identifier

The [`rule_mng.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol) file does not have an SPDX license identifier.

To avoid legal issues regarding copyright and follow best practices, consider adding SPDX license identifiers to files as suggested by the [Solidity documentation](https://docs.soliditylang.org/en/latest/layout-of-source-files.html#spdx-license-identifier).

_**Update:** Resolved in [pull request #19](https://github.com/jovaynetwork/jovay-contracts/pull/19/files). The Jovay team stated:_

> _We fixed this by removing `rule_mng.sol`._

### Missing Security Contact

Providing a specific security contact (such as an email address or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

All of the sequencer contracts are missing a security contact:

*   The [`PermissionControl` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol)
*   The [`InferRuleManager` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol)
*   The [`ChainCfg` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol)
*   The [`SysChainCfg` interface](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol)
*   The [`DPoSValidatorManager` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol)

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

### Inconsistent Order Within Contracts

All the sequencer contracts deviate from the Solidity Style Guide due to having inconsistent ordering of functions:

*   The [`PermissionControl` contract in `permission_control.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol)
*   The [`InferRuleManager` contract in `rule_mng.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol)
*   The [`ChainCfg` contract in `sys_chaincfg.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol)
*   The [`DPoSValidatorManager` contract in `sys_staking.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol)

To improve the project's overall legibility, consider standardizing ordering throughout the codebase as recommended by the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-layout) ([Order of Functions](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-functions)).

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

### Constants Not Using `UPPER_CASE` Format

Throughout the codebase, multiple instances of constants being declared using the `UPPER_CASE` format were identified:

*   The `sysStaking` constant declared in [line 22 of `sys_chaincfg.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L22)
*   The `intrinsicSys` constant declared in [line 23 of `sys_chaincfg.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L23)
*   The `sysChainCfg` constant declared in [line 2367 of `sys_staking.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2367-L2368)
*   The `intrinsicSys` constant declared in [line 2369 of `sys_staking.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2369-L2370)

According to the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html#constants), constants should be named with all capital letters with underscores separating words. For better readability, consider following this convention.

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

### Use `calldata` Instead of `memory`

When dealing with the parameters of `external` functions, it is more gas-efficient to read their arguments directly from `calldata` instead of storing them to `memory`. `calldata` is a read-only region of memory that contains the arguments of incoming `external` function calls. This makes using `calldata` as the data location for such parameters cheaper and more efficient compared to `memory`. Thus, using `calldata` in such situations will generally save gas and improve the performance of a smart contract.

Throughout the codebase, multiple instances where function parameters should use `calldata` instead of `memory` were identified:

*   In `sys_chaincfg.sol`, the [`keys`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L60) parameter
*   In `sys_chaincfg.sol`, the [`values`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_chaincfg.sol#L60) parameter
*   In `sys_staking.sol`, the [`_description`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2556) parameter
*   In `sys_staking.sol`, the [`_endpoint`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2557) parameter

Consider using `calldata` as the data location for the parameters of `external` functions to optimize gas usage.

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

### Inconsistent Code Formatting

The codebase contains formatting inconsistencies including non-standard line breaks and whitespace usage. These formatting issues reduce code readability and maintainability.

Consider using `forge fmt` or another automated formatter to ensure consistent code formatting across the entire codebase.

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

### `updateValidator` Requires Redundant Inputs

The `DPoSValidatorManager` contract's [`updateValidator`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/sys_staking.sol#L2554-L2559) function is used to update the `_description`, `_endpoint`, and/or `_new_owner` information of an existing validator. The issue is that even if only one field needs to be changed the caller has to supply the existing values of the other inputs within the function call. While there is a check that the `_new_owner` address is not `address(0)`, the `_description` and `_endpoint` fields do not have the same checks and may be inadvertently altered by a caller.

Consider coding an implementation where fields can be updated independently. Alternatively, consider clearly noting this behavior in the NatSpec for the `updateValidator` function.

_**Update:** Resolved in [pull request #19](https://github.com/jovaynetwork/jovay-contracts/pull/19/files#diff-606478a32eb449fb8e0d81c93b384bc7234bb17b4d9106d15132957b77d1897b). The Jovay team stated:_

> _We fixed this by removing the unused `updateValidator` function._

### Typographical Errors

The [`getGranteeAdmin` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/permission_control.sol#L58) has a misleading comment which claims that it will "return administrator\_", whereas it actually returns `grantees_`. In addition, the word "selector" is misspelled as [`selctor`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L12) in the `InferRule` struct and in [the `addRuleEvent` event](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/sequencer_contracts/sys_contract/artifact_src/solidity/rule_mng.sol#L123).

Consider updating the comment to "return grantees\_" and correcting "selctor" to "selector".

_**Update:** Resolved in [pull request #47](https://github.com/jovaynetwork/jovay-contracts/pull/47)._

Conclusion
----------

The audited codebase is an update to the system predeploys that allow the Jovay Network to handle chain configuration, the management of access control, and epoch advancement within the validator management system. In addition, it supports the management of read/write rules that may be required later as the Jovay Network evolves. In general, the codebase showed careful consideration for the management of chain configurations. However, the audit revealed instances where certain functionality had been partially removed or left incomplete, which contributed to several medium-severity findings.

Of the medium-severity issues not related to incomplete logic, one relates to an unsafe cast when returning the effective withdrawal window from within the validator manager contract, potentially altering the withdrawal window used. Another issue related to the control structure implementations used within the contracts under review, which could create self-inflicted DoS due to the way in which the complexity of operations increases as the array size grows. Regarding the rule management, it was found that the implementation of the rule filter using metahashes appeared to contradict its stated design. Apart from this, an issue surfaced where rule proposers could set their own newly added rules as successfully proven permissionlessly.

Suggestions were also made to improve the overall clarity of the codebase and to remove unnecessary logic. In particular, limited docstrings make it difficult to judge the correctness of feature implementations within some contracts. Furthermore, adding a comprehensive test suite to the repo is recommended. It is worth noting that the Jovay team indicated that some of the functionality under audit would not be deployed immediately and that the in-scope contracts were simplified from earlier versions that had a larger feature set. This may explain the instances of partially removed or incomplete implementations within the codebase.

The Jovay team was consistently responsive and collaborative throughout the engagement, and we greatly appreciate their support during the audit process.