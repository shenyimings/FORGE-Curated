\- May 15, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

**Type:** Account Abstraction  
**Timeline:** March 5, 2025 → March 17, 2025**Languages:** Solidity

**Findings**Total issues: 34 (28 resolved, 3 partially resolved)  
Critical: 0 (0 resolved) · High: 0 (0 resolved) · Medium: 6 (2 resolved, 3 partially resolved) · Low: 9 (7 resolved)

**Notes & Additional Information**19 notes raised (19 resolved)

  
Scope

We audited the [matter-labs/zksync-sso-clave-contracts](https://github.com/matter-labs/zksync-sso-clave-contracts) repository at commit [c7714c0](https://github.com/matter-labs/zksync-sso-clave-contracts/commit/c7714c0fe0a33a23acce5aa20355f088d330b4f7).

In scope were the following files:

`src
├── TransparentProxy.sol
├── interfaces
│   └── IGuardianRecoveryValidator.sol
└── validators
    ├── GuardianRecoveryValidator.sol
    └── WebAuthValidator.sol` 

A few issues in out-of-scope files of the repository were also identified.

System Overview
---------------

The code under review introduces changes to the `SsoAccount` contract, a more customizable smart account that plugs into the existing `bootloader` Account Abstraction (AA) framework. Under review are the incremental changes made since the last audit of the protocol:

*   `TransparentProxy.sol`: The functionality to pass data during the construction stage, which will then be used alongside the implementation's code, has been added.
*   `IGuardianRecoveryValidator.sol`: A new interface meant for the new guardian validator module, respecting the `IModuleValidator` interface definition, has been added.
*   `GuardianRecoveryValidator.sol`: A new implementation of the guardian validator has been added.
*   `WebAuthValidator.sol`: An adaptation of the original `WebAuthValidator` contract has been added to allow multipass keys, primarily due to the introduction of a `credentialId` into the structure of the storage.

### `GuardianRecoveryValidator`

The validator is in charge of providing a mechanism to recover access to an `SsoAccount` in case any other validation method has been lost. The procedure to set up an account and use it as a safety measure consists of the following steps:

1.  Attach the `SsoAccount` contract to the `WebAuthValidator` and `GuardianRecoveryValidator` contracts by adding them as module validators.
2.  Invoke the `proposeValidationKey` function of the `GuardianRecoveryValidator` contract to propose a guardian throughout the `SsoAccount` contract's transaction execution workflow.
3.  The guardian must accept the proposal from their account by invoking the `addValidationKey` function of the `GuardianRecoveryValidator` contract.

Then, in case of the need for a recovery, the guardian for that particular `SsoAccount` is in charge of initiating a recovery by passing the respective account, and the hashed `originDomain` and `credentialId` values alongside the `rawPublicKey` that will be added into the `WebAuthValidator` contract. The hashed version is used in an effort to obfuscate the data with a commit-and-reveal pattern. At this point, the 24-hour waiting period begins, during which the account being recovered can cancel the recovery process.

Once the recovery window is reached (24 to 72 hours after initiating recovery), anyone can create a `Transaction` that calls the `addValidationKey` method on the `WebAuthValidator` contract. If different transaction data is provided, the execution will revert at the `Bootloader` layer. Parameters used for this call (`credentialId`, `originDomain`, and `rawPublicKey`) must exactly match those provided when initiating the recovery. If these conditions are met, the `GuardianRecoveryValidator` contract will successfully validate the transaction, allowing the execution to proceed on behalf of the `SsoAccount` contract.

When a recovery request is used, it is automatically deleted, preventing it from being executed again. However, expired yet unused recovery requests are not automatically removed. Since executing an expired recovery request is not possible, it must be overridden with a new one, which also requires waiting for a 24-hour cancellation period. The `SsoAccount` contract attached to this validator does have the option to modify and remove guardians at will, but only through a validatable `Transaction`.

Security Model and Trust Assumptions
------------------------------------

The owners of the `SsoAccount` contract trust the good will of the guardians, in that they will choose to initiate the recovery process. Failing to do so can seriously affect the capability to recover access to such an account, even if there are honest guardians registered for that account.

Furthermore, the process to recover the accounts relies on the complementary use of another validator, the `WebAuthValidator` contract, which must be functional and attached to the account. Otherwise, the guardians and their validator will not be able to successfully complete their endeavor.

### Privileged Roles

The guardians assigned to an account can:

*   Accept their role once the account has proposed them as guardians.
*   Initiate/update a recovery process for a particular account that they are the guardians for.

After a recovery has been initiated, anyone can make the `Transaction` using the `GuardianRecoveryValidator` as the validator for it, and crafting the parameters to include the passed `publicKey` to the `WebAuthValidator` contract.

Design Choices, Limitations, and Integration Issues
---------------------------------------------------

*   Even though the `SsoAccount` contract mimics the `Bootloader` flow of the `Default` account, it does not mimic the EOA behavior provided by the `Default` account. This means it could cause a reversion when calling functions protected by the `onlyBootloader` modifier or when invoking unimplemented functionalities, instead of returning empty data. Protocols that previously used the `DefaultAccount` contract might encounter issues when switching to the new `SsoAccount` contract if these behaviors are not properly handled.
*   Both `originDomain`s and `credentialId`s make use of the hashed versions when submitting the recovery request to obfuscate their values.
*   The uninstallation process can be called with an empty `data` input which will not remove/unlink any guardian-related data from the contract. Furthermore, there is no restriction for sending partial `data` (this means, not the full list of `hashedOriginDomain`).
*   The procedure expects the `WebAuthValidator` contract to be attached to the respective `SsoAccount` contract, but there is no enforcement nor validation that this is being done.

Medium Severity
---------------

### Potential Denial-of-Service While Iterating Hooks

The [`runExecutionHooks` modifier](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/managers/HookManager.sol#L79) and the [`runValidationHooks` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/managers/HookManager.sol#L63) both iterate over all elements in a set, potentially leading to excessive gas consumption as the set grows. The `runExecutionHooks` modifier contains a call to `EnumerableSet.values()`, which retrieves all elements at once, an operation with an unbounded gas cost. Similarly, `runValidationHooks` directly iterates over all validation hooks, making transaction validation increasingly expensive and potentially unusable if the number of hooks becomes too large.

Using `EnumerableSet.values()` within state-changing functions and iterating over large sets during validation is risky because retrieving or processing all elements in one go can exceed the gas limits of a single block. If the set grows beyond a certain size, these operations may render transaction execution or validation infeasible.

Consider explicitly documenting that owners should limit the number of execution and validation hooks added to the set or imposing a reasonable upper bound on the number of hooks allowed.

_**Update:** Partially resolved in [pull request #372](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/372) at commit [dff9e12](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/372/commits/dff9e1236ecb3eb0939501f898a3982857821115). The Matter Labs team stated:_

> _This is a known issue with the design of global hooks. Adding a small note to the hook interface is currently the best solution without overhauling how hooks work._

### Front-Running Scenarios During Key Registration

The `WebAuthValidator` contract utilizes two mappings for key registration: `publicKeys` for associating keys with the `accountAddress`, and `registeredAddress` for linking keys with a combination of `originDomain` and `credentialId`. This setup is designed to ensure the uniqueness of each `originDomain` and `credentialId` pair within the system. However, the implementation exposes the problem of front-running attacks that could be exploited by malicious actors.

The problem arises from the contract's [check](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L104) to prevent the registration of duplicate `originDomain` and `credentialId` combinations. Malicious users can monitor the mempool for pending transactions aimed at registering a new key. Upon detecting such a transaction, they can execute a call to register a key with the same `originDomain` and `credentialId`, but with a different, arbitrarily chosen `publicKey`. This preempts the legitimate registration attempt by occupying the intended slot.

The result culminates when the legitimate user's transaction reaches the [`onInstall` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L63), which includes a verification step to ensure that the key being added has not been registered under a different account. If an attacker has already claimed the slot, this verification fails, causing the legitimate transaction to revert and preventing the user from attaching their validator to their account.

Furthermore, the `GuardianRecoveryValidator` contract utilizes a [commit-reveal pattern over the `originDomain` and `credentialId`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L204-L206) to obfuscate their actual values before they are needed. However, a malicious user could index the past values for all the `SsoAccount` contracts attached to the `WebAuthValidator` contract, hash their values, and might be able to match (in some cases) the obfuscated values to their actual unhashed values. This would allow them to preemptively start planning an attack.

To mitigate this front-running scenario, consider introducing additional verification mechanisms that securely associate the registration attempt with the initiating account, thus preventing unauthorized preemption of key registration slots. In addition, to improve the commit-reveal pattern, consider utilizing data from the account and/or guardian during the hashing and submitting the commitment in the `WebAuthValidator` contract instead of in the `GuardianRecoveryValidator` contract.

_**Update:** Acknowledged, not resolved. The Matter Labs team stated:_

> _Given that no elastic chain operators have public mem-pools or shared sequencers this is at-best a possible future issue. The two design issues at play here are trying to make this information accessible and separating recovery concerns from authentication concerns. In the future we might consider updating the check to support a list of accounts per credential id, which would significantly complicate the UX but would prevent this kind of front-running._

### Guardian Can Overwrite Recovery Process and Render It Useless

The [`initRecovery` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L202-L215) of the `GuardianRecoveryValidator` contract lacks a crucial validation step, allowing for the overwriting of existing recovery data without any checks for ongoing recovery processes. This oversight permits a guardian to initiate a new recovery using incorrect data or to refresh the timestamp, thereby obstructing or postponing the intended recovery process.

This vulnerability is particularly problematic in scenarios where an account is protected by multiple guardians. In such cases, a single guardian acting maliciously can indefinitely disrupt the recovery process by:

1.  Overwriting existing recovery data with malicious or incorrect information.
2.  Forcing well-intentioned guardians to overwrite this malicious data with the correct information, only for the cycle to repeat ad infinitum.

This cycle not only stalls the recovery process but also leaves no recourse for removing the malicious guardian and regaining control of the account, as the necessary `Transaction` cannot be executed by any party.

To address these vulnerabilities, consider implementing a consensus mechanism among the guardians for recovery processes involving multiple guardians. Such a mechanism would only allow a recovery to proceed once a majority of guardians have concurred on the submitted parameters. Additionally, for accounts with a single guardian, consider enhancing the `initRecovery` function by incorporating a preliminary check to ascertain when a recovery process is still active. These measures will significantly mitigate the risk of overwrites and delays, thereby bolstering the security and efficacy of the recovery process.

_**Update:** Partially resolved in [pull request #379](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/379) at commit [f2b6bbf](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/379/commits/f2b6bbfe95f791f157c4174b019b59481f03643e). The Matter Labs team stated:_

> _We decided not to include an N-out-of-M design in this iteration; instead, we added a recommendation to the user-facing documentation to use a Multisig as a guardian to replicate this behavior._

### Failure to Clear `pendingRecoveryData` in `onUninstall` Allows Immediate Account Recovery Upon Reconnection

The [`onUninstall` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L84) can clear all data associated with guardians of a specific account, but it cannot clear the `pendingRecoveryData` mapping's requests. This omission allows an account to re-connect the `GuardianRecoveryValidator` contract and execute pending recovery requests within the permitted time window. This behavior contradicts the intended logic, whereby a newly reconnected account should not be able to perform actions such as calling the `addValidationKey` function from the `WebAuthValidator` contract without waiting for the required delay, as the state is expected to be cleared.

Consider explicitly clearing the `pendingRecoveryData` mapping's requests during the `onUninstall` function to prevent unauthorized immediate account recovery based on the old state of the `pendingRecoveryData` mapping.

_**Update:** Resolved in [pull request #342](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/342/files) at commit [69f4c36](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/342/commits/69f4c36abd76f6cb8cdf481ad341d1417ed99d69)._

### Incomplete Recovery Process Due to Missing Validator Attachment

The `SsoAccount` contract allows for the configuration of a guardian through the `GuardianRecoveryValidator` contract. This setup enables the guardian to initiate a recovery process aimed at regaining control of the account by adding a new public key via the `WebAuthValidator` contract. However, in the current implementation, there is an absence of a requirement for the `SsoAccount` contract to be pre-attached to the `WebAuthValidator` contract. Consequently, while a guardian may be correctly set up and linked to the `GuardianRecoveryValidator` contract, attempting to validate a subsequent transaction through the `WebAuthValidator` contract will fail if the `SsoAccount` contract does not recognize the `WebAuthValidator` as a module validator within the system, as indicated by [this check](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/SsoAccount.sol#L214).

This oversight renders the recovery process ineffective, as the successful addition of a public key does not guarantee the ability to validate future transactions through the `WebAuthValidator` contract. The implication is that both the `GuardianRecoveryValidator` and `WebAuthValidator` contracts must be correctly set up in advance for the recovery flow to function as intended.

Furthermore, the `SsoAccount` contract treats all validators as independent modules without providing a mechanism to require their collaborative operation. To address this issue and guarantee the successful completion of the recovery process, consider implementing checks during the attachment of the `SsoAccount` contract to the `GuardianRecoveryValidator` contract. These checks should ensure that the `SsoAccount` contract is also adequately attached to the `WebAuthValidator` contract, thereby securing the recovery flow's functionality. For a more comprehensive solution, consider introducing a validation hook that would enable validators to be designated as collaborative entities, rejecting transactions that attempt to disrupt this collaboration (e.g., by only adding the `GuardianRecoveryValidator` contract or by removing the `WebAuthValidator` contract after both have been attached). In addition, this hook could incorporate a whitelist of approved module validators, enhancing security for any account utilizing them.

_**Update:** Partially resolved in [pull request #343](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/343) at commit [9368f6b](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/343/commits/9368f6ba5aae63c5c36b6138ebd600517da4f1bd). The account attempting to connect to `GuardianRecoveryValidator` now needs to be linked to `webAuthValidator`. While this addresses the initial concern of the account not being connected to `webAuthValidator`, it does not fully resolve the issue. In the future, the user could uninstall `webAuthValidator` after connecting to `GuardianRecoveryValidator`, which would still leave the account unrecoverable in that scenario. The Matter Labs team stated:_

> _We will implement a check in `GuardianRecoveryValidator`'s `onInstall` to require `WebAuthValidator` to be installed in the `SSOAccount`. A more comprehensive solution, as suggested by the audit, would include extending `ValidatorManager` functionality to allow grouping validators._

### Uninstall Process Might Revert Due to Pending Guardian Acceptance

In the current implementation, if an account [passes the entire array of `hashedOriginDomain`s](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L85) that it has used (for both accepted and pending guardians), the account might fail to uninstall the `GuardianRecoveryValidator` contract from an `SsoAccount` contract using the [`removeModuleValidator` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/managers/ValidatorManager.sol#L34). This happens because the [`onUninstall` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L84) does not verify whether the guardian has accepted the guardian role (i.e., the `isReady` flag is set to `true`) before attempting to remove the account from the guardian's set of [guarded accounts](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L172). Consequently, when a guardian has a pending request and has not confirmed its acceptance, the user's account is not included in that guardian's set of guarded accounts. Attempting a removal by passing all the `hashedOriginDomain` values, including those for pending guardians, triggers the [`remove` function to return `false`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L93), causing a call revert with the [`AccountNotGuardedByAddress` custom error](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L96).

As a result, currently, users cannot fully uninstall the validator while any guardian requests remain pending, as the data associated with these pending guardians cannot be entirely cleared. Although users may attempt to exclude pending guardians from the uninstallation process by omitting the relevant `hashedOriginDomain` entries, this approach introduces risks. Specifically, pending guardians may subsequently accept their roles through the [`addValidationKey` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L164) without the account owner's knowledge. Since the user has disabled the validator module and may not actively monitor such events, newly accepted guardians could initiate account recovery processes undetected.

If the user later reinstalls the validator module, they might unexpectedly discover new guardians already in place, potentially in the midst of adding recovery keys to `WebAuthValidator` contract. Such a scenario could escalate to an `SsoAccount` contract takeover, enabling the execution of unauthorized transactions due to the user's inability to reject the addition of new public keys to their account.

Consider verifying that a guardian has confirmed their role by checking the `isReady` flag within the `accountGuardianData` structure before removing the account from the guardian's `guardedAccounts` mapping, similar to the verification implemented in the `removeValidationKey` function.

_**Update:** Resolved in [pull request #345](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/345) at commit [c36e31a](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/345/commits/c36e31a49e16816df5875f960d26b317d38d1fce)._

Low Severity
------------

### Possible Initialization of an Unusable `SsoAccount`

In the [`initialize` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/SsoAccount.sol#L59) of the `SsoAccount` contract, no validation is performed to ensure that the array arguments are non-empty. This omission allows the contract to be initialized in a state where it cannot perform any operations, rendering the account unusable.

Consider adding a validation check to ensure that at least one of the `initialValidators` or `initialK1Owners` arrays has a non-zero length before initialization. This will prevent the creation of non-functional accounts.

_**Update:** Resolved in [pull request #371](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/371) at commit [8454fce](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/371/commits/8454fce35e9178ef394466d5b99096cde7a89d36)._

### Potential Panic During Data Slicing in `_executeCall`

In the [`_executeCall` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/SsoAccount.sol#L128) of the `SsoAccount` contract, there is a slice operation performed on the `_data` parameter when handling a `DEPLOYER_SYSTEM_CONTRACT` call. The purpose of this slice operation is to retrieve the function selector, which requires at least 4 bytes of data. However, the current implementation does not validate whether the input data has sufficient length. If the provided data is shorter than 4 bytes, the slicing operation will cause a panic, abruptly terminating the execution.

Consider verifying the length of the `_data` parameter prior to slicing, and explicitly reverting with a meaningful error message if the length is insufficient.

_**Update:** Resolved in [pull request #369](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/369) at commit [f476fb1](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/369/commits/f476fb1f064a180ddfcb906c8468dac98c99da1d)._

### Builtin Getter For `pendingRecoveryData` Does Not Return `rawPublicKey`

The [`pendingRecoveryData` variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L68) is declared with a `public` visibility modifier, causing the Solidity compiler to automatically generate a `public` getter function. However, this getter will only return the struct’s simple members (`hashedCredentialId` and `timestamp`), and it will omit complex data structures such as `rawPublicKey`. This happens because automatically-generated getters for `public` state variables do not return array or mapping members within structs, even when nested. For more information, see the [Solidity documentation](https://docs.soliditylang.org/en/latest/contracts.html#getter-functions).

Since the contract already implements the `getPendingRecoveryData` getter, consider removing the automatic getter (that does not retrieve all the data) by reducing the variable's visibility.

_**Update:** Resolved in [pull request #346](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/346) at commit [832372a](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/346/commits/832372adf5bf13b3729b79581a987f28ce2acccc)._

### Misleading Error Message in `addValidationKey`

The `addValidationKey` function of the [`WebAuthValidator` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L64) is designed to add a new validation key. If the function returns `false`, then the `onInstall` function will emit the `WEBAUTHN_KEY_EXISTS` error, indicating that the key already exists. However, this error message can be misleading due to other conditions under which the function may return `false`, such as receiving an [empty input for the `rawPublicKey`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L108-L111). This lack of specificity in error reporting could lead to confusion, as users may incorrectly infer that a key exists when, in fact, the function failed due to different validation issues.

However, this error message can be misleading due to other conditions under which the function may return `false`, such as receiving an [empty input for the `rawPublicKey`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L108-L111). This lack of specificity in error reporting could lead to confusion, as users may incorrectly infer that a key exists when, in fact, the function failed due to different validation issues.

To enhance clarity and improve error handling, consider differentiating the error messages based on the failure condition. This could involve introducing a new error code for cases where the input validation fails and reserving the `WEBAUTHN_KEY_EXISTS` error strictly for scenarios where an attempt is made to add a duplicated key. By doing so, users and developers can more accurately diagnose issues and understand the contract's behavior, leading to a more robust and user-friendly experience.

_**Update:** Resolved in [pull request #333](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/333) at commit [5f89af4](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/333/commits/5f89af4ffa319aa0c96763dcbcf09db5c2e94f96)._

### Deviation From Specifications

Throughout the codebase, multiple instances of deviations from specifications were identified:

*   In line [83](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L83) of `GuardianRecoveryValidator.sol`, there is a comment regarding the functionality that purports to remove all past guardians when disabling the validator. However, if all [`hashedOriginDomains` are not passed as inputs](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L85) to the `onUninstall` function, there might still be [leftovers associated with the account](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L92-L100). Moreover, the contract lacks a mechanism to verify if all guardians associated with an account, such as a counter, have indeed been removed. Consider adding a counter that would aim to remove all the linkage between the account and the guardians.
*   In the ZkSync docs, there is [a set of limitations](https://docs.zksync.io/zksync-protocol/account-abstraction/building-smart-accounts#verification-step-limitations) that must be followed during transaction validation. These are: accounts can only interact with their own slots, context variables (e.g., `block.number`) are not allowed in account logic, and accounts must increment the nonce by 1 to prevent hash collisions. However, in the `_validateTransaction` function of the `SsoAccount` contract, there is a call to the `runValidationHooks` function, which uses the `_call` function. Since `_call` leverages the `call` opcode, it could modify state or violate the first two restrictions. In such cases, consider using the `staticcall` call for validation hooks to ensure compliance with these constraints.

To improve the clarity and maintainability of the codebase, consider resolving the aforementioned instances of deviations from specifications.

_**Update:** Resolved in [pull request #347](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/347) at commit [10efdf2](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/347/commits/10efdf242add7af7556eceb1d6d6ed8af05c68df)._

### Missing Checks for Function Arguments

When operations with `address` parameters are performed, it is crucial to ensure that the address is not set to zero. Setting an address to zero is problematic because it has special burn/renounce semantics. Thus, this action should be handled by a separate function to prevent accidental loss of access during value or ownership transfers.

Within `GuardianRecoveryValidator`, multiple instances of missing zero address checks were identified:

*   The [`_webAuthValidator`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L77) operation
*   The [`newGuardian`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L117) operation
*   The [`accountToGuard`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L171) operation
*   The [`accountToRecover`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L208) operation

Likewise, in the [`addValidationKey` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L94) of `WebAuthValidator`, there is no validation for `credentialId` and `originDomain`, allowing them to be empty or have arbitrary lengths. Furthermore, the [constructor](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/AAFactory.sol#L32-L35) of `AAFactory` currently lacks validation checks for its input parameters. This absence of validation may cause unexpected contract reverts during operation. For instance, if `_beaconProxyBytecodeHash` is set to an empty value, the `ContractDeployer` will consistently revert, rendering the factory unusable and requiring redeployment.

Consider adding appropriate validation checks for the arguments before assigning them to a state variable.

_**Update:** Resolved in [pull request #349](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/349) at commit [b65d4cf](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/349/commits/b65d4cff6a6120a7dcd6dd71c70e7abdfb20a5a9) and [pull request #333](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/333) at commit [c9c8e79](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/333/commits/c9c8e79bf03f286b2adbf8454084aaf6eabd7608)._

### Floating Pragma

Pragma directives should be fixed to clearly identify the Solidity version with which the contracts will be compiled.

Throughout the codebase, multiple instances of floating pragma directives were identified:

*   `GuardianRecoveryValidator.sol` has the [`solidity ^0.8.24`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L2) floating pragma directive.
*   `IGuardianRecoveryValidator.sol` has the [`solidity ^0.8.24`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/interfaces/IGuardianRecoveryValidator.sol#L2) floating pragma directive.
*   `TransparentProxy.sol` has the [`solidity ^0.8.24`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/TransparentProxy.sol#L2) floating pragma directive.
*   `WebAuthValidator.sol` has the [`solidity ^0.8.24`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L2) floating pragma directive.

Consider using fixed pragma directives.

_**Update:** Acknowledged, not resolved. The Matter Labs team stated:_

> _We use floating pragmas to allow easy use of these base contracts with future compiler versions and other future packages that rely on these contracts. These future versions can provide gas optimizations or security enhancements. Updating just these 4 files would be inconsistent with the rest of the project and other published zksync system contracts._

### Lack of Public Key Validation

In the [`addValidationKey` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L108), the public key is currently only checked to ensure that it is non-zero. However, this does not guarantee that the key is a valid point on the elliptic curve or that it can later be used as it should. The absence of explicit validation makes it possible to add an invalid public key, which may result in a situation where it is impossible to generate a valid signature. This could impact authentication mechanisms and may compromise system integrity.

Consider implementing a verification step to ensure that the provided public key is a valid point on the elliptic curve before adding it.

_**Update:** Acknowledged, will resolve. The Matter Labs team stated:_

> _There is also no validation that the provided k1 owner keys are valid keys, or that session k1 keys are valid. While we would accept this as a possible improvement, the additional gas required to truly validate this when adding keys would be non-trivial and would significantly change the interface of adding keys to this module._
> 
> _The idea would be to use the `webauth.create` flow that is already validated in the client and replicate that to validate in the same manner as we do for the `webauthn.get` flow with `webAuthVerify`._
> 
> _A follow-up issue was created here: **https://github.com/matter-labs/zksync-sso-clave-contracts/issues/340**._

### Missing or Incomplete Documentation

Docstrings provide essential context for contracts, functions, events, and state variables within smart contracts. They clearly explain intended behavior, usage, and relevant parameters, greatly enhancing readability, maintainability, and ease of security audits.

Multiple instances of incomplete or missing docstrings were identified in `GuardianRecoveryValidator.sol`, `IGuardianRecoveryValidator.sol`, and `WebAuthValidator.sol`. For example, in the `GuardianRecoveryValidator.sol` file, functions such as [`onInstall`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L81) and [`onUninstall`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L84-L109) lack proper documentation for their parameters. This makes it challenging for developers or auditors to clearly understand the functionality and implications of these components.

Consider thoroughly documenting all contracts, functions, events, and relevant state variables according to the [Ethereum Natural Specification Format](https://docs.soliditylang.org/en/v0.8.29/natspec-format.html) (NatSpec). This should include clear, concise explanations for all parameters and return values associated with public APIs to ensure clarity and ease of review.

_**Update:** Resolved in [pull request #380](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/380) at commit [fd8fdc9](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/380/commits/fd8fdc92d5485e5bd3af905d3565412185d45a09)._

Notes & Additional Information
------------------------------

### Non-Standardized Storage Location for `SSO_STORAGE_SLOT`

The `SsoAccount` contract currently sets the [storage offset](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/libraries/SsoStorage.sol#L8) for `SSO_STORAGE_SLOT` using the `keccak256('zksync-sso.contracts.SsoStorage') - 1` formula. Although functional, this approach deviates from the standardized method proposed by [EIP-7201](https://eips.ethereum.org/EIPS/eip-7201), specifically created to minimize the risk of storage collisions with default Solidity storage slots. Adopting this standard can also facilitate optimization opportunities in future protocol upgrades, such as those involving the Verkle state tree migration (if applicable to ZKsync).

Consider aligning the storage offset calculation for `SSO_STORAGE_SLOT` with the standardized approach outlined in EIP-7201 to ensure safer storage management.

_**Update:** Resolved in [pull request #369](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/369) at commit [45360b4](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/369/commits/45360b4958c8936f7e530fc0d8089bbcc4acbecf)._

### Unused Code

In the `GuardianRecoveryValidator` contract, several [custom errors](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L35-L37) are declared but never used:

*   `PasskeyNotMatched`
*   `CooldownPeriodNotPassed`
*   `ExpiredRequest`

Additionally, in the `SsoAccount` contract, the [`signature` variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/SsoAccount.sol#L212) is defined but never utilized. Furthermore, the [`GuardianRecoveryValidator.sol` file](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L13) includes imports for `BatchCaller` and `Call`, which are not used.

Consider removing the aforementioned unused errors, the `signature` variable, and unnecessary imports to improve code clarity, maintainability, and readability.

_**Update:** Resolved in [pull request #350](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/350) at commits [84162ef](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/350/commits/84162ef7543ac419778515c6544e6412e8a6b7db) and [66c2731](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/350/commits/66c27310c05f47762b53ae51405fd7eb353af8fd), and [pull request #377](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/377) at commit [37fe8d7](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/377/commits/37fe8d7fdaf990e21428719cc451408c2890ad4d)._

### Redundant Storage Access

The [`validateTransaction` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/a5896ac7d70cc4d4542c3bc290fe562b2cf2f473/src/SsoAccount.sol#L93) of the `SsoAccount` contract calls `_transaction.totalRequiredBalance()` twice: once to check if the account has sufficient balance and again when throwing an error if the balance is insufficient. This redundant invocation adds unnecessary computational overhead.

Since `_transaction.totalRequiredBalance()` returns the same result within this scope, repeatedly calling it is inefficient. Instead, storing the value in a local variable and reusing it would improve performance and readability. A similar inefficiency exists in the `WebAuthValidator` contract, where an unused code fragment is present [here](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L80-L82).

Consider caching the result of `_transaction.totalRequiredBalance()` in a local variable and similarly caching the `registeredAddress` in the `WebAuthValidator` contract.

_**Update:** Resolved in [pull request #369](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/369) at commit [b12ebf9](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/369/commits/b12ebf9cc771dd21a910c741418127c45a3888d3)._

### Redundant Getter for `publicKeys` in `WebAuthValidator`

In Solidity, when a state variable is declared as `public`, the compiler automatically generates a getter function for it. This getter provides access to the variable's data but may have limitations depending on the variable type. In the case of arrays or mappings, Solidity-generated getters can only return one element at a time, which can lead to there being redundant custom getter functions in the contract.

The [`publicKeys` mapping variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L37-L38) is declared with `public` visibility, prompting the compiler to generate a default getter for the `bytes32[2] publicKey` array. However, this automatically generated getter returns only one element at a time, which is insufficient for retrieving the full key. As a result, the contract also defines a separate [`getAccountKey` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L40) that returns both elements of the array. This results in redundant functionality, as one of these access methods is unnecessary.

Consider changing the visibility of the `publicKeys` mapping to a more restrictive one, such as `internal` or `private`, to prevent the compiler from generating an automatic getter. This will eliminate the redundancy and ensure that only the explicitly defined `getAccountKey` function is used for retrieving keys.

_**Update:** Resolved in [pull request #333](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/333) at commit [78b8bb0](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/333/commits/78b8bb0b39c83b618d4cfe2ecf14a298074264db). The Matter Labs team stated:_

> _We added comments and re-ordered the layout._

### Inconsistencies Between Interface and Implementation

The `IGuardianRecoveryValidator` interface and its implementation present inconsistencies in parameter naming, function ordering, and missing functions, which could hinder usability and developer experience. In particular:

*   The [`proposeValidationKey` and `removeValidationKey` functions](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/interfaces/IGuardianRecoveryValidator.sol#L8-L10) have mismatched parameter names (`externalAccount` instead of [`newGuardian`, and `externalAccount` instead of `guardianToRemove`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L116-L138), respectively).
*   The order of functions in the [interface](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/interfaces/IGuardianRecoveryValidator.sol#L12-L19) does not align with their [implementation](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L164-L202), such as with the `initRecovery` function.
*   The interface lacks critical functions found in the implementation, including the `discardRecovery`, `guardiansFor`, `guardianOf`, and `getPendingRecoveryData` functions.

Addressing these points will streamline the `IGuardianRecoveryValidator` interface, enhancing clarity and facilitating a better development experience. Consider fixing the aforementioned instances.

_**Update:** Resolved in [pull request #361](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/361) at commit [1be0586](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/361/commits/1be0586d7a62c8748572605903f46d8281831256)._

### `IGuardianRecoveryValidator` Is Not Optimized For Development

In the `IGuardianRecoveryValidator` interface, the current implementation could be optimized for better developer experience and protocol interoperability. Specifically, the [events, errors, and structs](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L18-L57) defined within the implementation could be moved to the interface level. This adjustment would not only streamline the contract's structure but also enhance its usability in diverse development scenarios.

Moving these definitions to the interface would facilitate other contracts or developers who aim to interact with, decode, or handle these specific events and errors more efficiently. It would also simplify the process for those looking to pass structs as inputs or outputs in their implementations, such as for the [`guardiansFor` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L312). Given that `IGuardianRecoveryValidator` is the primary interface interacting with these constructs, integrating them directly into the interface could significantly improve clarity and reduce the complexity for developers interfacing with the protocol.

Consider restructuring the interface to include these definitions directly. This approach not only adheres to best practices in contract design but also significantly enhances the developer experience by providing a more intuitive and accessible interface for interacting with the contract's functionalities.

_**Update:** Resolved in [pull request #361](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/361) at commit [1be0586](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/361/commits/1be0586d7a62c8748572605903f46d8281831256)._

### Refactor Opportunity Over Address Casting

The `GuardianRecoveryValidator` contract employs a [direct type casting](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L254-L256) approach to convert `uint256` to an address.

As the `safeCastToAddress` method is already present in the [`Utils` library](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/helpers/Utils.sol#L12), consider using the `safeCastToAddress` method in the `validateTransaction` function to reduce the maintenance effort.

_**Update:** Resolved in [pull request #351](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/351) at [934d446](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/351/commits/934d446875ba499aa90d45261961deb51ee3faf5) and [e735710](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/351/commits/e735710ccfb7824fdc53c4b25d53aeddd8b503d1) commits._

In the `GuardianRecoveryValidator` contract, there is an inconsistency in the types of variables used for time measurements, particularly for the [`addedAt` variable in the `Guardian` struct](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L21) and the [`timestamp` variable in the `RecoveryRequest` struct](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L27). This variation in variable types for similar time-related data points could lead to confusion and conflicts within, or outside, the contract's operations.

To improve the readability and consistency of the code, consider keeping the same variable types for similar units. Alternatively, if this resulted from a gas optimization, consider documenting the design choice over the respective `struct`.

_**Update:** Resolved in [pull request #357](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/357) at commit [70b0601](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/357/commits/70b06012d07b36ba55ae8d72d512bee16cbb9c4e)._

### Misleading Function Naming in `GuardianRecoveryValidator`

The `GuardianRecoveryValidator` contract uses function names such as [`proposeValidationKey`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L116), [`removeValidationKey`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L138), and [`addValidationKey`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L164) that suggest a similarity to functions in other validators, such as those found in the [`WebAuthValidator`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L79). However, the functionality of the functions in `GuardianRecoveryValidator` is significantly different, as they are designed to manage guardians for an account rather than validation keys.

This discrepancy can lead to confusion and errors, as the naming convention does not accurately reflect the functions' purposes. Furthermore, the interface definitions `IModule` and `IModuleValidator` do not mandate such naming conventions, increasing the risk of misuse or misunderstanding. In addition, the parameters for these functions do not align with those of their namesakes in other validators, resulting in different function selectors. This further compounds the potential for confusion and errors among developers and auditors.

To mitigate these issues and enhance clarity, it is recommended to rename these functions to more accurately describe their specific roles in managing guardians rather than validation keys. Adopting clear and descriptive naming conventions will improve code readability, reduce the risk of errors, and facilitate a better understanding of the contract's functionality.

_**Update:** Resolved in [pull request #353](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/353) at commit [ca53654](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/353/commits/ca53654621c78cac0f22c3e57b045528951240a3)._

### Use Custom Errors

Since Solidity version 0.8.4, custom errors provide a cleaner and more cost-efficient way to explain to users why an operation failed.

Multiple instances of `revert` and/or `require` messages were identified within `GuardianRecoveryValidator.sol`:

*   The [`require(transaction.data.length >= 4, "Only function calls are supported")`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L253) statement
    
*   The [`require(transaction.to <= type(uint160).max, "Overflow")`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L254) statement
    

For conciseness and gas savings, consider replacing `require` and `revert` messages with custom errors.

_**Update:** Resolved in [pull request #354](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/354) at commit [c09d2ff](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/354/commits/c09d2ffd67e1a2a0da6dbb333f7d2a1178d665e7)._

### Missing Named Parameters in Mappings

Since [Solidity 0.8.18](https://github.com/ethereum/solidity/releases/tag/v0.8.18), developers can utilize named parameters in mappings. This means mappings can take the form of `mapping(KeyType KeyName? => ValueType ValueName?)`. This updated syntax provides a more transparent representation of a mapping's purpose.

Within `GuardianRecoveryValidator.sol`, multiple instances of mappings with missing named parameters were identified:

*   The [`accountGuardians` state variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L64-L65)
*   The [`guardedAccounts` state variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L66-L67)
*   The [`pendingRecoveryData` state variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L68)
*   The [`accountGuardianData` state variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L69-L70)

If the last named parameter omission is a design choice, consider keeping a consistent coding style throughout the codebase, as there are cases such as the [`publicKey` parameter in the `publicKeys` mapping from the `WebAuthValidator` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L37-L38) that do have the name. Otherwise, consider adding named parameters to mappings in order to improve the readability and maintainability of the codebase.

_**Update:** Resolved in [pull request #358](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/358) at commit [a1bbeba](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/358/commits/a1bbeba9e89199c1be35911f267ae8239201b328)._

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Throughout the codebase, multiple instances of contracts that do not have a security contact were identified:

*   The [`GuardianRecoveryValidator` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol)
    
*   The [`IGuardianRecoveryValidator` interface](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/interfaces/IGuardianRecoveryValidator.sol)
    

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in [pull request #355](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/355) at commit [ec565fc](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/355/commits/ec565fc1c5c7f1b17dbeabfb872082c10d005fdf)._

### Prefix Increment Operator Can Save Gas in Loops

Throughout the codebase, multiple opportunities for loop iteration optimization were identified:

*   The [j++](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L86) in `GuardianRecoveryValidator.sol`
    
*   The [i++](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L89) in `GuardianRecoveryValidator.sol`
    
*   The [i++](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L315) in `GuardianRecoveryValidator.sol`
    
*   The [i++](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L73) in `WebAuthValidator.sol`
    

Consider using the prefix increment operator (`++i`) instead of the postfix increment operator (`i++`) in order to save gas. This optimization skips storing the value before the incremental operation, as the return value of the expression is ignored.

_**Update:** Resolved in [pull request #356](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/356) at commits [9125cd9](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/356/commits/9125cd9161f71d528290a598d89d092bd2c0b670) and [d6e705b](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/356/commits/d6e705bbdc84f3bf6916e4fc5e928b3548f55fef), and [pull request #378](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/378) at commit [66c1c37](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/378/commits/66c1c37ed8a6ceb85a08bfe0e14bf67fca7952d0)._

### Inconsistent Order Within Contracts

Throughout the codebase, multiple instances of contracts having an inconsistent ordering of functions were identified:

*   In the [`GuardianRecoveryValidator` contract in `GuardianRecoveryValidator.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol), the [`onlyGuardianOf` modifier](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L188) is implemented between functions and the [functions are not sorted](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L219-L246) by its visibility.
    
*   In the [`WebAuthValidator` contract in `WebAuthValidator.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol), the [`PasskeyId` struct](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L50-L53) comes after the functions and variables, and the [function ordering](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L57-L119) is not correct.
    

To improve the project's overall legibility, consider standardizing ordering throughout the codebase as recommended by the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-layout) ([Order of Functions](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-functions)).

_**Update:** Resolved in [pull request #362](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/362) at commit [ae86f43](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/362/commits/ae86f43805765c54e7d4828c0f39cb5c5ea491b3), [pull request #333](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/333) at commit [640d7c9](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/333/commits/640d7c978036828da4b381b064d34eb565863136)._

### Function Visibility Overly Permissive

Throughout the codebase, multiple instances of functions with unnecessarily permissive visibility were identified:

*   The [`initialize`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L76-L78) function in `GuardianRecoveryValidator.sol` with `public` visibility could be limited to `external`.
    
*   The [`finishRecovery`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L230-L237) function in `GuardianRecoveryValidator.sol` with `internal` visibility could be limited to `private`.
    
*   The [`_discardRecovery`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L241-L243) function in `GuardianRecoveryValidator.sol` with `internal` visibility could be limited to `private`.
    
*   The [`guardiansFor`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L312-L319) function in `GuardianRecoveryValidator.sol` with `public` visibility could be limited to `external`.
    
*   The [`guardianOf`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L325-L327) function in `GuardianRecoveryValidator.sol` with `public` visibility could be limited to `external`.
    
*   The [`getPendingRecoveryData`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L333-L338) function in `GuardianRecoveryValidator.sol` with `public` visibility could be limited to `external`.
    

To better convey the intended use of functions and to potentially realize some additional gas savings, consider changing a function's visibility to be only as permissive as required.

_**Update:** Resolved in [pull request #359](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/359) at commit [924d857](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/359/commits/924d8575a685003b074c87b57ec6be58246899f7)._

### Use `calldata` Instead of `memory`

When dealing with the parameters of `external` functions, it is more gas-efficient to read their arguments directly from `calldata` instead of storing them to `memory`. `calldata` is a read-only region of memory that contains the arguments of incoming `external` function calls. This makes using `calldata` as the data location for such parameters cheaper and more efficient compared to `memory`. Thus, using `calldata` in such situations will generally save gas and improve the performance of a smart contract.

Within `GuardianRecoveryValidator.sol`, multiple instances where function parameters should use `calldata` instead of `memory` were identified:

*   The [`rawPublicKey`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L205) parameter
*   The [dismissed](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L296) parameter

Consider using `calldata` as the data location for the parameters of `external` functions to optimize gas usage.

_**Update:** Resolved in [pull request #360](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/360) at commit [79d3725](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/360/commits/79d37255c9b72f07bec0cf6ba67ac40d48d8edca)._

### Suboptimal `ERC-165` Interface Check Implementation

The [`_supportsModuleValidator` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/managers/ValidatorManager.sol#L91) of the `ValidatorManager` contract currently checks whether a given `validator` account implements the `IModuleValidator` and `IModule` interfaces separately. Each interface check [uses three `external` calls](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/dc44c9f1a4c3b10af99492eed84f83ed244203f6/contracts/utils/introspection/ERC165Checker.sol#L38) via the `supportsERC165InterfaceUnchecked` method, resulting in a total of six `external` calls. However, the `ERC165Checker` library provides a more efficient alternative, the [`supportsAllInterfaces` function](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/dc44c9f1a4c3b10af99492eed84f83ed244203f6/contracts/utils/introspection/ERC165Checker.sol#L78), capable of verifying both interfaces simultaneously with only four `external` calls. Utilizing this method will significantly reduce gas consumption during each initialization of `SsoAccount` contract. The same applies to the [`_supportsHook` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/managers/HookManager.sol#L154) in the `HookManager` contract.

Consider replacing the separate interface checks with a single call to `supportsAllInterfaces`, supplying both `IModuleValidator` and `IModule` selectors, to optimize gas usage within the `initialize` function of the `SsoAccount` contract.

_**Update:** Resolved in [pull request #369](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/369) at commit [de51ab6](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/369/commits/de51ab6614dbd7c4877cb3ee0bda04347a9dc38f)._

### Typographical Error

In the NatSpec comment of the [`initialize` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/SsoAccount.sol#L57) in the `SsoAccount` contract, the `abi.encode(validatorAddr,validationKey))` code snippet contains an extra closing parenthesis.

Consider correcting the aforementioned typographical error.

_**Update:** Resolved in [pull request #370](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/370) at commit [aa313ab](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/370/commits/aa313ab40927d36700795008c16c8a620d3df53f)._

### Redundant Hashing Operations in `webAuthVerify`

In the [`webAuthVerify` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L147) of the `WebAuthValidator` contract, comparisons are performed between certain string fields from `clientDataJSON` and predefined constant string values. Currently, the function utilizes the [`Strings.equal` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/WebAuthValidator.sol#L179) which hashes both the provided and constant strings each time it compares them. Since these constant strings do not change, this implementation unnecessarily repeats hashing operations, increasing execution cost.

The function can be optimized by precomputing hashes for constant string values such as `"webauthn.get"` and `"false"`, storing these hashes directly in the contract. Thus, comparisons would only require hashing the input data once, avoiding redundant hashing operations.

Consider implementing this approach by storing precomputed hashes of constant values, thereby minimizing hashing operations and reducing the overall execution cost of the `webAuthVerify` function.

_**Update:** Resolved in [pull request #333](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/333) at commit [ce6f196](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/333/commits/ce6f1961394c36e4a03ac0f0743ee572887aecbf)._

Recommendations
---------------

### Code Style in `GuardianRecoveryValidator`

Several areas within the `GuardianRecoveryValidator` contract can be improved for consistency and maintainability:

*   The [`addValidationKey` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L164) returns a boolean to indicate the call's outcome, whereas [other functions](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L81-L158) in the contract do not follow this convention. Consider aligning the style of function signatures consistently across the contract.
*   The [`onUninstall` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L84) duplicates the functionality found in the [`removeValidationKey` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L138) with minor differences. Consider making the `removeValidationKey` function a `public` function and calling it from the `onUninstall` function to avoid redundancy. Note that this approach will require small adjustments to the current logic within the `removeValidationKey` function.
*   The [`onlyGuardianOf` modifier](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L188) is used only once in the [`initRecovery` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L207). Consider embedding this modifier's logic directly into the `initRecovery` function to simplify the contract's structure.
*   The [`finishRecovery` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L230) contains minimal logic and is called only once. Consider integrating its functionality directly into the [`validateTransaction` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L246) to simplify code review and avoid unnecessary runtime bytecode overhead.
*   In the [`validateTransaction` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L246), the [`storedData` variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L275) is currently accessed as a storage pointer, though its contents are only read and not modified. Since all struct elements are accessed, consider loading them into memory to optimize gas consumption.
*   In the [`proposeValidationKey` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L116), the [`newGuardian` is added to a `Guardian` struct and stored within a mapping using the key of `newGuardian` itself](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/validators/GuardianRecoveryValidator.sol#L125-L126) (`accountGuardianData[hashedOriginDomain][msg.sender][newGuardian]`). This field may be redundant. Consider revising this storage logic to avoid tautological logic, when the value is a key for a mapping and also the struct member pointed to by the key.

Consider implementing the above recommendations to improve the clarity and maintainability of the codebase.

Conclusion
----------

During the audit, the new guardian recovery validator contract and associated changes were reviewed. This new validator contract enables users to designate guardians for their `SsoAccount` accounts, allowing a recovery process to take place if users lose control over them. Recovery functionality depends on integration with both the `WebAuthValidator` and the `GuardianRecoveryValidator` contracts, introducing a new way of social recovery to the ZKsync ecosystem.

The audit identified multiple medium-severity findings, along with several low- and note-severity issues. The `GuardianRecoveryValidator` contract, being in its initial iteration, has room for improvement, such as having clearer code structure, reduction of duplicated code through component reuse, and optimizations to enhance readability and reduce execution costs. Additionally, providing more descriptive documentation, particularly for new functionality in the `WebAuthValidator` contract, would enhance clarity and maintainability. Finally, a more comprehensive test suite could also improve the quality of the codebase, in particular by adding more negative case scenarios which could have found some of the issues presented in the report.

The Matter Labs team was responsive and cooperative throughout the audit process. We appreciate their professionalism and collaboration.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kE_m8_XjmJAecDr_Z9H0yqHmZAqkQ&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=189851790177&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=e0ee2109-625e-4db0-a6ef-14dbef22a5de&redirect_url=APefjpES3fQjUpvYhLKVzUYwtEWNqTRtq4GJlMBQkpp05L03HmH2_eugIqzF_x7P_mgykx5dRobG62ASDWNWScm5_uiJaCjgHzLU3dqFCBzFCqIOJ-0aEJbsRRcDoPGzgUo_vrVqBb7wSNOa-6MkV8anpVH6KOnVhCUE3f78QASOYKZIDpL7elVvCqsV0AN3lxeSg-tddinyOoMPMNfGo4iwL0Pz7LoVcJ3kxpJzCIuJxfVJOkh-f0OZoUy-CVkk3tfEhFswXNZO&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Fmatter-labs-guardian-recovery-validator-audit&ts=1770534031772&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.65.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")