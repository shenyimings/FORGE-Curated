\- March 11, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

Type

Account Abstraction

Timeline

From 2025-01-13

To 2025-02-05

Languages

Solidity

Total Issues

31 (27 resolved, 2 partially resolved)

Critical Severity Issues

0 (0 resolved)

High Severity Issues

1 (1 resolved)

Medium Severity Issues

2 (1 resolved)

Low Severity Issues

10 (8 resolved, 2 partially resolved)

Notes & Additional Information

18 (17 resolved)

Scope
-----

We audited the [zksync-sso-clave-contracts](https://github.com/matter-labs/zksync-sso-clave-contracts) repository at commit [fc0af34](https://github.com/matter-labs/zksync-sso-clave-contracts/tree/fc0af3442594ad2dc343dbb2b918e478251bc293).

In scope were the following files:

`src
├── auth
│   ├── Auth.sol
│   ├── BootloaderAuth.sol
│   ├── HookAuth.sol
│   └── SelfAuth.sol
├── helpers
│   ├── TimestampAsserterLocator.sol
│   ├── TokenCallbackHandler.sol
│   └── VerifierCaller.sol
├── interfaces
│   ├── IHookManager.sol
│   ├── IHook.sol
│   ├── IModule.sol
│   ├── IModuleValidator.sol
│   ├── IOwnerManager.sol
│   ├── ISsoAccount.sol
│   ├── ITimestampAsserter.sol
│   └── IValidatorManager.sol
├── libraries
│   ├── Errors.sol
│   ├── SessionLib.sol
│   ├── SignatureDecoder.sol
│   └── SsoStorage.sol
├── managers
│   ├── HookManager.sol
│   ├── OwnerManager.sol
│   └── ValidatorManager.sol
├── validators
|   ├── SessionKeyValidator.sol
|   └── WebAuthValidator.sol
├── AAFactory.sol
├── AccountProxy.sol
├── SsoAccount.sol
├── SsoBeacon.sol
├── EfficientProxy.sol
├── TransparentProxy.sol
├── batch/BatchCaller.sol
└── handlers/ERC1271Handler.sol` 

System Overview
---------------

The code under review introduces the `SsoAccount` contract, a more customizable smart account that plugs into the existing `bootloader` Account Abstraction (AA) framework. As such, it is invoked identically to the `DefaultAccount`, following these steps:

1.  The `bootloader` calls [`validateTransaction`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L70) to decide if the transaction should be executed or not.
2.  If the transaction is sponsored by a paymaster, the `bootloader` calls [`prepareForPaymaster`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L165). Otherwise, the `SsoAccount` contract funds the transaction itself through [`payForTransaction`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L151).
3.  The `bootloader` calls [`executeTransaction`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L95), which initiates an arbitrary call with the `SsoAccount` as `msg.sender`. The `SsoAccount` inherits the [`BatchCall` functionality](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/batch/BatchCaller.sol#L27), creating the opportunity for complex execution flows with only one necessary validation.

A transaction could be valid if paired with a 65-byte long ECDSA signature based on the secp256k1 curve, which, when recovered, corresponds to one of the accounts' [`k1Owners`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L191-L195). In addition, the `SsoAccount` contract has the ability to attach other functionalities to itself. These functionalities can be:

*   hooks to run just before the validation step (`validationHooks`).
*   custom contracts that can validate through [an arbitrary logic](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/handlers/ERC1271Handler.sol#L44-L45).
*   hooks to run just before and after the execution step (`executionHooks`).

Besides the `SsoAccount` contract, the code under review implements two contracts that can serve as custom transaction validators: [`SessionKeyValidator`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L19) and [`WebAuthValidator`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L18).

### `SessionKeyValidator`

The `SessionKeyValidator` contract is a module that allows an `SsoAccount` contract to create granular execution sessions for custom signers. Each session has an expiration timestamp and specifies a signer of the session, the amount that can be send to the `bootloader` contract as transaction fees, the amount that can be send with transfers or function calls during the execution step, as well as function selector and parameter constraints for arbitrary calls. A transaction meant to be validated by the `SessionKeyValidator` contract should be accompanied by information that links it to a particular session, as well as a valid ECDSA signature that recovers to the session owner's address.

The current implementation of the validator does not require any validation hooks to process the transaction. Furthermore, the session information is not persistent in storage, meaning it must be passed along with the transaction. Only the session hash (together with usage tracking information) is persisted in storage. If the transaction intends to call functionality that was not whitelisted, the transaction will revert when looping over all the defined policies for the session. Most of the functionality is implemented in the `SessionLib` library, complementary to the aforementioned contract.

### `WebAuthValidator`

The `WebAuthValidator` contract is a module that allows an `SsoAccount` contract to validate a transaction through [WebAuthn](https://developer.mozilla.org/en-US/docs/Web/API/Web_Authentication_API) passkeys. The account can add public keys corresponding to multiple signing domains. A transaction is considered valid if the accompanying data can be parsed to a JSON that has the necessary `WebAuthn` verification fields, the `challenge` field matches the transaction's hash, and the transaction signature recovers to the public key of the specified signing domain.

### Upgradeability and `SsoAccount` Deployment

New `SsoAccount` contracts can be deployed [through the `AAFactory` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/AAFactory.sol#L13).

It is important to note that each `SsoAccount` is upgradeable and loads its' implementation from the [`SsoBeacon` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoBeacon.sol#L12), which is a more efficient [`BeaconProxy`](https://docs.openzeppelin.com/contracts/5.x/api/proxy#BeaconProxy). Hence, the implementation of different accounts can not be upgraded independently, and upgrading one will impact all of them.

In turn, the `SessionKeyValidator`, `WebAuthValidator` and `AAFactory` contracts are also upgradeable and will sit behind [`TransparentProxy`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/TransparentProxy.sol) instances, which are more efficient [`TransparentUpgradeableProxies`](https://docs.openzeppelin.com/contracts/5.x/api/proxy#TransparentUpgradeableProxy).

### Design Choices and Limitations

Several design limitations were identified throughout the audit. While not necessarily a security risk, they should be taken into consideration as they limit functionality or could hinder user experience:

1.  While an `SsoAccount` contract can grant arbitrary signers access to granular execution sessions, all transactions will flow through the same account and, hence, will share the same nonce within ZKsync. As a result, race conditions can appear where two session owners submit a transaction and only one of them succeeds while the other one reverts.
2.  If an `SsoAccount` contract is not sponsored by a paymaster, it will supply the transaction fee by itself and be refunded any remaining gas at the end of execution. However, when tracking and enforcing transaction fee spending limits, the `SessionKeyValidator` contract does not take into account refunds and always [decreases the spending allowance by the full transaction fee](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol#L247). Thus, it is expected that a session owner will be able to spend fewer funds on transaction fees than initially intended.
3.  The `SessionKeyValidator` contract requires the presence and correct linking of a `TimestampAsserter` contract. Since the current implementation of the `TimestampAsserterLocator` contract hardcodes the addresses of the `TimestampAsserter` within ZKsync, the `TimestampAsserterLocator` will require changes when deploying to any other ZK chain.
4.  Currently it is not possible for `SessionKeyValidator` contract's expired sessions to be automatically deleted. These expired sessions can accumulate unless regularly cleared by each `SsoAccount` contract.
5.  It is important to note that the implementations behind validators are custom and up to the developers, and no assumptions should be made around underlying behaviour or ways of integrating. For example, during the uninstall process, the `SessionKeyValidator` reverts if there are still active sessions, while the `WebAuthValidator` has no such checks.
6.  There are no restrictions against [removing all `k1Owners`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/OwnerManager.sol#L26-L28) or [validators](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/ValidatorManager.sol#L34-L43). If all transaction validations methods of an account are removed, the account would be locked, without the possibility of validating and executing any transactions.
7.  The implementation of the `ERC1271Handler isValidSignature` function does not run the [validation hooks](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/handlers/ERC1271Handler.sol#L28). Hence, a signature that was considered invalid by the `SsoAccount` contract might pass validation through the `ERC1271` flow, or vice-versa. Additionally, the `SessionKeyValidator` contract [does not support this signature validation method](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L75-L77), and hence all transactions that leverage it will be invalid within the `ERC1271` flow.
8.  During the `WebAuthValidator` transaction validation flow, it is possible that [the supplied `clientDataJSON`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L102) contains multiple occurrences of the same `WebAuthn` key. Due to implementation details within the `JSONParserLib` library, using the [`at` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L117) will return the last encountered occurrence of a key. Hence, if a `clientDataJSON` object with both a valid and an invalid `challenge` value is supplied, transaction validation will depend on which `challenge` value appears first.
9.  Within the [`WebAuthValidator` transaction validation flow](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L55-L70), the same public key can correspond to multiple origin domains.
10.  Once a hook or a validator is added to the linked lists of an `SsoAccount` contract, the `onInstall` function of the hook or validator is called. It is important to note that the `initData` passed as parameter is not enforced to be non-empty ([\[1\]](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/ValidatorManager.sol#L61), [\[2\]](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L103)). This detail should be considered when implementing a hook or a validator, and revert in case empty initialization data is not wanted.
11.  The [`removeHook` and `unlinkHook` functions](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L35-L44) remove a hook from the corresponding set and then call the `onUninstall` function. Any hooks that need to callback during the `onUninstall` function call and check that they are attached to the account might revert because the hook's address will have been removed and will no longer appear as attached.
12.  When deploying a new account through the `AAFactory` contract, the [`initialize` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L49-L55) will not require any validators nor `k1Owner`s to pass, which would result in a locked account.

Security Model
--------------

The `WebAuthValidator` contract transaction validation flow uses Solady's `JSONParserLib` library. It is important to note that `JSONParserLib` library can revert, or not, the transaction if the `JSON` is malformed or does not contain fields that were requested. In several method, the output validation is delegated to the contract that uses the library. Such cases [were not explicitly handled](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L117) by the codebase under review, although no attack pattern was uncovered.

The `SsoAccount` contract can attach to other validation or execution hooks which it will change the dynamic of the transaction workflow. As the protocol does not limit nor defines how those should behave at a bare minimum, hooks can be improperly implemented. Available validators can give some notions for them but there are no hook contracts that can be used as a role model.

Continuing with the standardization, a few calls do not present a defined guideline, such as the `onInstall` or `onUninstall` functions. Sensitive functionalities tied to hook and validation management can possibly be called when they are not supposed to, potentially causing issues in the underlying hook and validation contracts that assume certain management workflow.

### Privileged Roles and Trust Assumptions

Throughout the audit, the following trust assumptions were made:

*   A new `SsoAccount` can be [deployed by anyone](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/AAFactory.sol#L45), at which time the initial `validators` and `k1Owners` will be set.
    
*   Only the `bootloader` can call an `SsoAccount`'s [`validateTransaction`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L70), [`payForTransaction`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L151), [`prepareForPaymaster`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L165), and [`executeTransaction`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L95) functions.
    
*   Upon the correct validation of a transaction, the `SsoAccount` contract will [execute the intended action](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L110-L138), either on itself or on arbitrary targets. Only the account itself can trigger [`BatchCall` functionality](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/batch/BatchCaller.sol#L32).
    
*   The account can add or remove [hooks](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L30-L38), [`k1Owners`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/OwnerManager.sol#L21-L28), as well as [validators](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/ValidatorManager.sol#L29-L37).
    
*   A hook attached to an account can [perform actions before the transaction validation or before and/or after execution](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L61-L90).
    
*   Within the `SessionKeyValidator` contract, an account can [create and grant a session](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L81), as well as [revoke any session previously granted](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L115-L128). Due to the complexity of [the `SessionSpec` structure](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol#L86), the creator of a session is trusted to supply valid session information, with reasonable transfer and function call limits, as well as constraint indices set to the right offsets of the targeted function parameters. Moreover, it is crucial that the session does not have multiple policies for the same `target` address or `target` + `function selector` combination, as this can cause unexpected behaviour when tracking spending limits. Moreover, sessions are [not fully validated on-chain](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L81-L94) and only a [few items are checked](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L84-L89).
    
*   Within the `WebAuthValidator` contract, an account can [store public keys for custom signing domains](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L55), enabling transaction validation through signature recovery to the correct public key.
    
*   The owners of the `SessionKeyValidator`, `WebAuthValidator`, and `AAFactory` contracts' `TransparentProxy` are allowed to change the underlying implementations. The owner of the `SsoBeacon` is able to change the implementation of the `SsoAccount` contract's proxies. They are trusted to act in the protocol's best interest and to not perform any malicious activities. Each account's owner is trusted to thoroughly verify each validation mechanism it attaches to its account. This includes `k1Owner` and/or custom validators and hooks, as these actors can enable the correct validation of malicious transactions, or on the contrary, have such strict transaction validation logic that the system becomes locked and devoid of the capacity to remove these actors.
    

Production Readiness
--------------------

Throughout the audit, several areas for improvement were identified that could further enhance the quality and security of the codebase:

*   There are numerous TODO and question comments left in the code (e.g. [update fee allowance](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol#L247)), pointing to several improvement directions, necessary testing, or existing limited/imperfect functionality.
*   While general technical documentation has been developed, there is limited documentation on the specifications that are needed for an external hook or validation contract to be fully complaint with the expected workflow. Moreover, some data passed as input is not properly documented, being possible to mistakenly encode data (e.g. for the constraints in the policies) that will not be able to be decoded as it should, resulting in the erroneous execution of the expected transaction or the reversion of it.
*   The codebase could benefit from expanding the current test suite to cover more edge cases, as well as complex flows such as an account with several validation and execution hooks, or adding or removing hooks through batched actions. In addition, the codebase could benefit from integration tests validating that the `SsoAccount` contract works as intended when plugged into the `bootloader` and the encompassing ZKsync system.
*   Since the codebase offers significant flexibility when it comes to implementing and attaching hooks or validators to an `SsoAccount` contract, developers should pay an extra attention to its design choices and limitations as well as ensure that a thorough testing is performed, validating the entire transaction flow.

High Severity
-------------

### Lack of Output Validation Can Lock the `SsoAccount`

Throughout the codebase, the functionalities calling the [`add`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/structs/EnumerableSet.sol#L171) and the [`remove`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/structs/EnumerableSet.sol#L181) methods of the `EnumerableSet` library do not check the returned value and incorrectly assume that the code would revert in case of an error. This makes the following scenarios possible:

*   When [removing or unlinking a hook](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L35-L44), it is possible for the caller to supply an incorrect `isValidation` flag. The code will attempt to remove the execution hook from the incorrect list, fail silently in doing so, yet proceed with calling the [`onUninstall` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L37) in the hook's contract. Depending on the hook's implementation, it is possible that subsequent transaction validation or execution will revert, since from the hook's standpoint, it is no longer attached to the `SsoAccount` contract or has cleared the necessary state. This can lead to the indefinite lockup of the account. Consider validating the return value of the `add` or `remove` calls to prevent silent failures. In addition, the current implementation allows a hook to be both a validation and execution hook, and since both interfaces have the `onInstall` and `onUninstall` functions, adding or removing a hook from both lists could cause unexpected behavior. Thus, consider enforcing that a hook contract is used for either validation or execution.
*   When [adding or removing `k1Owner` addresses](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/OwnerManager.sol#L40-L50), it is possible that the caller attempts to add a duplicate `k1Owner` address or remove an address that did not have this role. While the `_k1Owners` set would remain unchanged, the `K1AddOwner` and `K1RemoveOwner` events would nonetheless be emitted, which could affect off-chain indexers that track them. Consider validating the return value of the `add` or `remove` calls, and revert when the calls fail.
*   When [adding or removing a module validator](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/ValidatorManager.sol#L28C2-L43C4), it is possible for the caller to attempt to add a duplicate module validator or remove an address that did not have this role. Similarly, while the sets would remain unchanged, the `onInstall` and `onUninstall` functions would be called, which would produce unexpected behavior depending on the implementation. Consider validating the return value of the `add` or `remove` calls and reverting when the calls fail.

_**Update:** Resolved in [pull request #260](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/260) and [pull request #311](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/311). The pull request also introduces the ability for an execution hook to return `bytes32 context` from the `preExecutionHook` call, and pass it to the `postExecutionHook` call._

Medium Severity
---------------

### Transaction Can Be Executed in Unintended Period

The [`SessionKeyValidator` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L19) provides an `SsoAccount` with the functionality to create sessions with custom transfer and call policies. The policies can enforce a limit of funds that the session owner is allowed to send through a `transfer` or a function call. The limits are specified either for [the entire lifetime of the session](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol#L68) or as a [per-`period` allowance](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol#L69), allowing the session owner to only spend `amount` of funds every `period` seconds. When sending a transaction, a user will attach additional `calldata` to their call, which decodes to the [specifications of the session they intend to use and the `periodIds`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L149) they want to spend funds from. Depending on the remaining allowances for the session, the transaction can fail validation.

It is important to note that the `periodIds` is not included in a transaction's hash since it is appended at the end of the `transaction.signature` field and this field is not used [during the encoding process](https://github.com/matter-labs/era-contracts/blob/main/system-contracts/contracts/libraries/TransactionHelper.sol#L149). Hence, it can be modified without the user's consent. If validation fails for a transaction where the session owner intended to only spend funds from a period with `periodId` 10, a malicious actor could observe the transaction in the mempool and resend it with different `periodIds`, potentially achieving execution and spending allowances from unintended periods. A similar rationale and attack pattern can be applied to any information held within `transaction.signature` which is not the `signature` itself but auxiliary data to be used through the validation process, such as [the `validator` field](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L199).

Consider adding a mechanism to protect against different entities submitting the same transaction with different parameters intended for validation.

_**Update:** Acknowledged, will resolve. The Matter Labs team stated:_

> _`periodIds` are not meant to be semantically interpreted the same way as e.g. uniswap's trade deadline. They merely serve as auxiliary data that enables calculating `block.timestamp / period` during validation. If it was possible to use `block.timestamp` directly, there would be no need in supplying `periodIds`, and hence there would be no such issue. `periodIds` are not signed and thus should not be treated by the users/developers as guarantees that transaction will be executed strictly within provided periods. If the users/developers care that a failed transaction can be replayed with different `periodIds`, they should simply send another transaction to increase the nonce and prevent a potential replay. That being said, the point that `validator` and `validatorData` in general is not signed is completely valid and might become an attack vector in future modules. Currently, there is no way to allow signing arbitrary auxiliary data within any of the allowed transaction types on ZKsync. We will make sure to clearly reflect this in the developer documentation to prevent potential `validatorData` misuse in future modules._

### Adding or Removing Execution Hooks Causes Unexpected Behaviour

Through the [`runExecutionHooks` modifier](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L77), each execution hook attached to an `SsoAccount` contract will run logic both [before](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L82) and [after](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L88) transaction execution. If the transaction adds or removes an execution hook, the current implementation might not function accordingly:

*   If an execution hook is removed, the whole transaction will revert, as the [`totalHooks` variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L79) is not updated and the [`postExecutionHook` for loop](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L87C5-L89C6) will run out of bounds. In practice, this results in an inability to remove execution hooks. Moreover, since the [`OpenZeppelin EnumerableSet` library](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/structs/EnumerableSet.sol#L136) does not have ordering guarantees after updating the set, it is possible that the `postExecutionHooks` are run in a different order.
*   If an execution hook is added, the same issue with the ordering guarantees applies. Moreover, it is possible that the newly added hook's `postExecutionHook` function is executed, while an older hook will be neglected.

Consider reviewing the execution hooks flow and determining what is the expected behavior in case a hook is added or removed in between pre- and post-execution. If only the same hooks are expected to run, consider caching both the `totalHooks` variable and the list of hooks.

_**Update:** Resolved in [pull request #281](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/281/files)._

Low Severity
------------

### `error` Keyword Used For Variable Naming

In the [`ERC1271Handler`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/handlers/ERC1271Handler.sol#L35-L37) and the [`SsoAccount`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L191-L193) contracts, the `error` keyword is being used to name a variable that holds the error returned from a call to `ECDSA tryRecover`.

However, the `error` keyword is similar to `Error`, which is a reserved keyword used to [to define custom errors in Solidity](https://soliditylang.org/blog/2021/04/21/custom-errors/). This can lead to confusion and potential errors when maintaining the codebase. Consider renaming the variable to something different that still reflects its purpose.

_**Update:** Resolved in [pull request #292](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/292)._

### Storage Slot Points to Clave Protocol

The `SsoStorage` library defines the storage structure of all the different variables used by the `SsoAccount` contract. The structure is stored at [a pre-calculated slot](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SsoStorage.sol#L7) to prevent collisions and reduce the attack surface. However, the slot used corresponds to the [Clave protocol](https://github.com/getclave/clave-contracts/blob/0719581143537dde145291a6ea45ac308c2d0f6c/contracts/libraries/ClaveStorage.sol#L7).

Consider changing the storage slot to a different one that is specific to the ZKsync SSO Account project. Moreover, consider documenting how that hash was calculated as the [Clave protocol has done](https://github.com/getclave/clave-contracts/blob/0719581143537dde145291a6ea45ac308c2d0f6c/contracts/libraries/ClaveStorage.sol#L5).

_**Update:** Resolved in [pull request #269](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/269) at commit [52bc7f9](https://github.com/matter-labs/zksync-sso-clave-contracts/commit/52bc7f91a4dc4405f811a7a1b0727783ef24718d) and in [pull request #306](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/306)._

### Gas Optimization

Throughout the codebase, multiple opportunities for gas optimization were identified:

*   The `signature` parameter of the [`isValidSignature`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/handlers/ERC1271Handler.sol#L33) function from the `ERC1271Handler` contract and [`validateSignature`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L76) function from the `WebAuthValidator` contract could be declared as `calldata` instead of `memory`. Consider using `calldata` when appropriate.
*   In the `SsoStorage` library, the [`__gap_0`, `__gap_2`, and `__gap_4` variables](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SsoStorage.sol#L13-L26) follow a non-sequential nomenclature and are redundant. It is possible to combine them under a single `__gap` variable that is cheaper yet still protects against future upgrades. Consider using a single `__gap` variable instead or documenting the reason for such a decision.
*   When closing a session within the `SessionKeyValidator` contract, the status is [marked as `Closed`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L117), preventing the validation of a transaction or the recreation of the session. Simultaneously, the rest of the [`SessionStorage` structure](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol#L33) becomes unreachable through the existing implementation. Consider deleting the unnecessary state for the particular account to recover gas upon closing a session.
*   Within the [`webAuthVerify` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L101) of the `WebAuthValidator` contract, the [`rs[0]` and `rs[1]` bytes32 variables](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L106) cannot be smaller than 0. For the current implementation, consider requiring them to be zero instead of equal or less than zero.

When performing these changes, aim to reach an optimal trade-off between gas optimization and readability. Having a codebase that is easy to understand reduces the chance of errors in the future and improves transparency for the community.

_**Update:** Partially resolved in [pull request #294](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/294). The Matter Labs team stated:_

> _About the third point, to delete session state other than the status, we have to pass the `StorageSpec` into `revokeKey`, since there is no way to otherwise know the targets and selectors of the policies, the states of which we want to delete. Requiring to pass `StorageSpec` into `revokeKey` can negatively impact other system components, which would make revoking sessions harder for the users. Hence we decided not to change our approach there._

### Redundant Association of Access Control

The [`Auth` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/auth/Auth.sol#L14) inherits access control modifiers from the `BootloaderAuth`, `SelfAuth`, and `HookAuth` contracts. `Auth` is then inherited by the [`HookManager`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L22), [`ValidatorManager`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/ValidatorManager.sol#L21), and [`OwnerManager`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/OwnerManager.sol#L17) contracts. However, the [`HookAuth` functionality](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/auth/HookAuth.sol#L14) is unused as the `ValidatorManager` contract only uses the [`onlySelf` modifier](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/ValidatorManager.sol#L29) and the `SsoAccount` contract only uses the [`onlyBootloader` modifier](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L74). This means that each contract inheriting from `Auth` will only be using one particular feature from it, resulting in inheriting redundant code which increases maintenance effort and reduces readability.

In order to improve the maintainability and clarity of the codebase, consider deleting `Auth` and modifying each contract that requires authentication to only inherit the necessary authentication modifiers, as it is being done with the [`BatchCaller` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/batch/BatchCaller.sol#L8) with the `SelfAuth` contract.

_**Update:** Resolved in [pull request #275](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/275)._

### Unsafe ABI Encoding

It is not an uncommon practice to use `abi.encodeWithSignature` or `abi.encodeWithSelector` to generate calldata for a low-level call. However, the first option is not typo-safe and the second option is not type-safe. The result is that both of these methods are error-prone and should be considered unsafe.

Throughout the codebase, multiple instances of unsafe ABI encoding were identified:

*   The use of [`abi.encodeWithSelector`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L43) within the [`HookManager.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol)
*   The use of [`abi.encodeWithSelector`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol#L289) within the [`SessionLib.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol)
*   The use of [`abi.encodeWithSelector`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/ValidatorManager.sol#L42) within the [`ValidatorManager.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/ValidatorManager.sol)

Consider replacing all the occurrences of unsafe ABI encoding with `abi.encodeCall` which checks whether the supplied values actually match the types expected by the called function and also avoids errors caused by typos.

_**Update:** Resolved in [pull request #269](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/269) at [commit dd96b2e](https://github.com/matter-labs/zksync-sso-clave-contracts/commit/dd96b2ef0f4aef7a04f52f19c0016e7cc11a39ad) and [commit 69c614a](https://github.com/matter-labs/zksync-sso-clave-contracts/commit/69c614a815e30080f50a33caa47fdc2657e6ce4a)._

### Missing or Incomplete Documentation

Throughout the codebase, multiple instances of missing or incomplete documentation were identified:

*   The documentation of the [`validateSignature` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L73) of the `SessionKeyValidator` contract does not detail why this particular validator should not be used for signature validation.
*   The [`beacon` storage variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/AAFactory.sol#L21) of the `AAFactory` contract is not documented, consider mentioning that it will point to an instance of the `SsoBeacon` contract.
*   Consider adding more documentation around the [`verifier` address](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/helpers/VerifierCaller.sol#L7) of the `VerifierCaller` contract, detailing where the precompile code can be found for analysis.
*   Consider adding more documentation around the validation process of the [`WebAuthValidator` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol). For example, details about why [the validation checks against `r` and `s`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L106) are important, what is the meaning of the [33rd byte of `authenticatorData`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L111), why [the first and third least significant flag bits are special](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L23), and detailing why only the `type`, `challenge`, `origin`, and `crossOrigin` fields are important and why the rest are not relevant for the on-chain part of the implementation.
*   In the [`WebAuthValidator` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L117), the `at` method states that "duplicated keys, the last item with the key WILL be returned". This means that if there are multiple `challenge`s in the JSON, if the last one is successful, then the process will pass. However, if the successful one is before the last `challenge`, then the outcome will be different. Consider documenting this behavior to users or preventing the possibility of having a non-deterministic outcome due to repeated types.

Consider reviewing the whole codebase for missing docstrings and missing documentation around each step of the implementation. In addition, consider documenting any hidden code assumptions or expected behaviors of system components.

_**Update:** Partially resolved in [pull request #285](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/285) and [pull request #290](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/290). The Matter Labs team stated:_

> _About the third point: "Verifier caller is verifier-agnostic, could be a precompile or a contract, so doesn't make sense to add it there"_
> 
> _JSON Parsing behavior: Duplicate keys in JSON is explicitly implementation-defined behavior in the JSON RFC (https://datatracker.ietf.org/doc/html/rfc8259#section-4). While the previous behavior of throwing for ambiguous JSON might improve strictness, in practice this JSON is generated from browsers without the developer's intervention so duplicate keys would be a violation on the client side's standard. See https://www.w3.org/TR/webauthn-2/#dictdef-collectedclientdata for the expected format from the client._

### `SsoAccount` Can Call `updateAccountVersion` and `updateNonceOrdering`

When the `SsoAccount` executes a call to the `DEPLOYER_SYSTEM_CONTRACT` [through the `batchCall` functionality](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/batch/BatchCaller.sol#L38C7-L46C10), the function selectors are not validated similar to how they are in the [`DefaultAccount` contract](https://github.com/matter-labs/era-contracts/blob/84d5e3716f645909e8144c7d50af9dd6dd9ded62/system-contracts/contracts/DefaultAccount.sol#L148C12-L152C78) or in the [`_executeCall` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L119C6-L122C70) of the `SsoAccount`. This would allow accounts to call [`updateAccountVersion`](https://github.com/matter-labs/era-contracts/blob/84d5e3716f645909e8144c7d50af9dd6dd9ded62/system-contracts/contracts/ContractDeployer.sol#L68) or [`updateNonceOrdering`](https://github.com/matter-labs/era-contracts/blob/84d5e3716f645909e8144c7d50af9dd6dd9ded62/system-contracts/contracts/ContractDeployer.sol#L77), which could lead to arbitrary nonce integration issues.

Consider adding the above-mentioned check to prevent any unexpected behavior.

_**Update:** Resolved in [pull request #293](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/293) and [pull request #305](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/305)._

### Unused Code

Throughout the codebase, multiple instances of unused or redundant code were identified:

*   The [functionality from the `HookAuth` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/auth/HookAuth.sol#L14) is unused and can be entirely removed. The [`NOT_FROM_HOOK` error](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/Errors.sol#L19) should be removed after following the previous recommendation.
*   The `Errors` library is unused in [`Auth.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/auth/Auth.sol#L7), [`OwnerManager`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/OwnerManager.sol#L6), and [`SignatureDecoder.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SignatureDecoder.sol#L4).
*   The [`IERC777Recipient` interface](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/interfaces/ISsoAccount.sol#L7) import in the `ISsoAccount` interface.
*   The [`Transaction` structure](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/handlers/ERC1271Handler.sol#L6) import in the `ERC1271Handler` contract.

To improve the clarity and quality of the codebase, consider reviewing the above instances and removing any unused or redundant code.

_**Update:** Resolved in [pull request #276](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/276)._

### Reverted Output From Batch Execution Is Dismissed

When [one of the batch call fails](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/batch/BatchCaller.sol#L50-L52) and `allowFailure` is set to `true`, the `revert` is not propagated and the execution continues.

However, no information is emitted about which calls reverted. Moreover, the returned data from failed calls is dismissed, and it might be important for debugging. Consider emitting an event that specifies the index of the reverted call and the returned data.

_**Update:** Resolved in [pull request #293](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/293) and [pull request #313](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/313). It is important to note that the `getReturnData` function updates the free memory pointer to a location which is not aligned to a multiple of 32 bytes. While this does not currently pose a security risk, issues could arise if the code is ever modified in such a way where data is stored starting at the misaligned location, and then read from an aligned location, or vice versa._

### `SsoAccount` Contract Deployment Can Be Frontrun

Any user can [deploy](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/AAFactory.sol#L45) a new `SsoAccount` contract through the `AAFactory` contract. As inputs, the function takes a `_salt` and a `_uniqueAccountId` to use for a `create2` call.

However, any other user could observe the transaction in the mempool and frontrun, performing a deployment while blocking the original one. This serves as both a denial-of-service and loss-of-funds attack vector: a user could pair the deployment with a transfer of funds to the predicted address, and unintentionally send funds to an `SsoAccount` they do not control.

Consider mitigating this situation by adding a storage variable that serves as `uniqueAccountId`, and is incremented with each successful deployment. Additionally, consider using the `msg.sender` as part of the salt.

_**Update:** Resolved in [pull request #295](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/295) and [pull request #309](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/309)._

Notes & Additional Information
------------------------------

### Use of Suboptimal Decoding Function

In the `_validateTransaction` function of the `SsoAccount` contract, the [decoding of the `_transaction.signature` field](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L199) is handled by the [`decodeSignature` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SignatureDecoder.sol#L8) of the `SignatureDecoder` library. However, since the `validatorData` output is not needed in this particular case, consider using the [`decodeSignatureNoHookData` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SignatureDecoder.sol#L15C1-L16C1) from the `SignatureDecoder` library instead.

_**Update:** Resolved in [pull request #269](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/269) at commit [9b4591a](https://github.com/matter-labs/zksync-sso-clave-contracts/commit/9b4591a6069e823fc8b9a4bc11114a3e27b0eaf9)._

### Naming Suggestions

Throughout the codebase, multiple opportunities for improved naming were identified:

*   The [`keyExists` variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L65) of the `WebAuthValidator` contract will be assigned `true` if the key is new and `false` if it is updated. Hence, consider changing the variable's name to `keyIsNew` to prevent the misunderstanding of such output.
*   The events and functions within the [`OwnerManager` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/OwnerManager.sol#L17) are named as `k1<...>Owner` ([`k1AddOwner`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/OwnerManager.sol#L21), [`k1IsOwner`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/OwnerManager.sol#L31), [`K1AddedOwner`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/interfaces/IOwnerManager.sol#L13), and others). Since they refer to an entity called `k1Owner`, consider changing the names to adhere to the `k1Owner<...>` and `<...>K1Owner` formats. This would also be more consistent with the rest of the codebase ([`HookAdded`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/interfaces/IHookManager.sol#L13), [`addModuleValidator`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/ValidatorManager.sol#L29)).

_**Update:** Resolved in [pull request #269](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/269) at commit [a39df4d](https://github.com/matter-labs/zksync-sso-clave-contracts/commit/a39df4de7c35678485536188ff360895fd6618c9) and in [pull request #308](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/308)._

### Indirect Imports

Throughout the codebase, multiple instances of dependencies being imported indirectly from other packages were identified:

*   The [`INonceHolder`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L8) and [`IContractDeployer`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/AAFactory.sol#L4) interfaces are imported from `Constants.sol`.
*   The [`IERC165` interface](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L15) is imported from `TokenCallbackHandler.sol`.

Indirect imports can create confusion and potentially cause issues with the version management of the underlying files. In order to improve the readability of the codebase and reduce the possibility of introducing bugs when maintaining the code, consider resolving the instances mentioned above and reviewing the codebase for other occurrences.

_**Update:** Resolved in [pull request #267](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/267)._

### Typographical Errors

Throughout the codebase, multiple instances of typographical errors were identified:

*   In [`IHookManager`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/interfaces/IHookManager.sol#L22), "it's" should be "its".
*   In [`ISsoAccount`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/interfaces/ISsoAccount.sol#L18), "are contract" should be "are contracts".

Consider correcting any instances of typographical errors to improve the clarity and readability of the codebase.

_**Update:** Resolved in [pull request #269](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/269) at commit [2c6f44c](https://github.com/matter-labs/zksync-sso-clave-contracts/commit/2c6f44c2a37ad76fcf36b7da71bba5a256eb9d97)._

### Mismatching Implementation and Interface

The interface and implementation of the [`ISsoAccount.initialize` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/interfaces/ISsoAccount.sol#L29) mismatch due to having a different name for the "owners" function parameter: [`k1Owners`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/interfaces/ISsoAccount.sol#L29) and [`initialK1Owners`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L46), respectively.

Consider matching the two names to improve the function's clarity.

_**Update:** Resolved in [pull request #277](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/277)._

### Lack of SPDX License Identifier

The [`IModule.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/interfaces/IModule.sol) file is lacking an SPDX license identifier.

To avoid legal issues regarding copyright and follow best practices, consider adding SPDX license identifiers to files as suggested by the [Solidity documentation](https://docs.soliditylang.org/en/latest/layout-of-source-files.html#spdx-license-identifier).

_**Update:** Resolved in [pull request #262](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/262). Additionally, a `pragma solidity ^0.8.24;` directive was added in [pull request #304](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/304)._

### Function Visibility Overly Permissive

Throughout the codebase, multiple instances of functions with unnecessarily permissive visibility were identified:

*   The [`_addHook`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L92-L106) and [`_removeHook`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L108-L116) functions in `HookManager.sol` with `internal` visibility could be limited to `private`.
*   The [`_k1RemoveOwner`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/OwnerManager.sol#L46-L50) function in `OwnerManager.sol` with `internal` visibility could be limited to `private`.
*   The [`_addValidationKey`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L98-L102) function in `SessionKeyValidator.sol` with `internal` visibility could be limited to `private`.
*   The [`checkCallPolicy`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol#L196-L223) and [`remainingLimit`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol#L341-L358) functions in `SessionLib.sol` with `internal` visibility could be limited to `private`.
*   The [`_validateTransaction`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L183-L208), [`_incrementNonce`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L213-L220), [`_executeCall`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L110-L138), and [`_safeCastToAddress`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L224-L227) functions in `SsoAccount.sol` with `internal` visibility could be limited to `private`.
*   The [`_removeModuleValidator`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/ValidatorManager.sol#L66-L70) function in `ValidatorManager.sol` with `internal` visibility could be limited to `private`.
*   The [`supportsInterface`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L153-L158) function in `WebAuthValidator.sol` with `public` visibility could be limited to `external`.

To better convey the intended use of functions, consider changing a function's visibility to be only as permissive as required.

_**Update:** Resolved in [pull request #278](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/278)._

### Missing Named Parameters in Mappings

Since [Solidity 0.8.18](https://github.com/ethereum/solidity/releases/tag/v0.8.18), developers can utilize named parameters in mappings. This means mappings can take the form of `mapping(KeyType KeyName? => ValueType ValueName?)`. This updated syntax provides a more transparent representation of a mapping's purpose.

Throughout the codebase, multiple instances of mappings without named parameters were identified:

*   The [`accountMappings` state variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/AAFactory.sol#L24) in the `AAFactory` contract
*   The [`sessionCounter`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L27) and [`sessions`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L29) state variables in the `SessionKeyValidator` contract

Consider adding named parameters to mappings in order to improve the readability and maintainability of the codebase.

_**Update:** Resolved in [pull request #279](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/279)._

### Misleading Documentation

Throughout the codebase, multiple instances of misleading documentation were identified:

*   The docstrings of the [`k1AddOwner`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/interfaces/IOwnerManager.sol#L23) and [`k1RemoveOwner`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/interfaces/IOwnerManager.sol#L31) functions from the `IOwnerManager` interface imply that the functions can be called by whitelisted modules, which is not the case.
*   The docstrings of the [`HookManager`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L19) and [`OwnerManager`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/OwnerManager.sol#L14) contracts imply that the addresses are stored inside linked lists, whereas they are stored inside enumerable sets.
*   [The following comment](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/AAFactory.sol#L65) mentions `hooks` for initialization, whereas only `moduleValidators` and `k1Owners` are set.

Consider addressing the above instances of misleading documentation to improve the quality and clarity of the codebase.

_**Update:** Resolved in [pull request #287](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/287)._

### Inconsistent Use of Custom Errors

Since Solidity version 0.8.4, custom errors provide a cleaner and more cost-efficient way to explain to users why an operation failed. Even though there are cases where they are being used, it is recommended to use them consistently.

The [`AAFactory.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/AAFactory.sol), [`SessionKeyValidator.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol), [`SessionLib.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol), [`TimestampAsserterLocator.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/helpers/TimestampAsserterLocator.sol), and [`WebAuthValidator.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol) files use `require` messages. Consider updating them to use custom errors consistently.

_**Update:** Resolved in [pull request #298](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/298) at commit [a955d59](https://github.com/matter-labs/zksync-sso-clave-contracts/commit/a955d5959332280b7c213a94ae8b8535a5bad455)._

During development, having well-described TODO comments will make the process of tracking and solving them easier. However, if not addressed in time, these comments might age and important information for the security of the system might be forgotten by the time it is released to production. Thus, such comments should be tracked in the project's issue backlog and resolved before the system is deployed.

Throughout the codebase, multiple instances of TODO comments were identified:

*   The `TODO` comment in [line 247 of `SessionLib.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol#L247)
*   The `TODO` comment in [line 75 of `SsoAccount.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol#L75)

Moreover, there are places in the codebase, such as in the [`CallSpec` struct](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol#L100) of the `SessionLib` library, that have questions about the current implementation and whether further changes should be made to it. Ideally, all TODO comments and open questions about the codebase should be implemented and resolved before reaching production.

Consider removing all instances of TODO comments and instead tracking them in the issues backlog. Alternatively, consider linking each inline TODO to the corresponding issues backlog entry.

_**Update:** Resolved. The Matter Labs team stated:_

> _The issues are already tracked in the backlog, however, the comments are still left in the codebase for additional context._

### Modified Contracts Still Point to Clave as the Author

The [`HookManager` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/managers/HookManager.sol#L22) and the [`IValidationHook`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/interfaces/IHook.sol#L12) and [`IExecutionHook`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/interfaces/IHook.sol#L23) interfaces have been changed compared to the original code forked from Clave. However, they still reference Clave as the author.

In modified contracts, consider stating that while Clave was the original author, extensive modifications have been made since then.

_**Update:** Resolved in [pull request #288](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/288)._

### Implicit Casting

In the [`WebAuthValidator`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L106), an implicit cast is performed to compare the `bytes32` values of `r` and `s` to an explicit `uint256` zero.

To improve the readability of the code, consider explicitly casting the `bytes32` to `uint256`, as done by [OpenZeppelin's `P256` library](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/P256.sol#L164).

_**Update:** Resolved in [pull request #286](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/286) and [pull request #310](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/310)._

### Using the `rawVerify` Function Could Be Facilitated

The [`rawVerify` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L180) of the `WebAuthValidator` contract is used to strictly [test the validity of a transaction signature](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L185), without going through [the other transaction validation steps](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L106C5-L146C6). Note that compared to the `validateTransaction` function, the `rawVerify` function does not receive the [`authenticatorData`, `clientDataJSON` and `rs`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L102) as parameters but rather the [already signed `message`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L181). This creates an inconsistency that complicates user experience and creates room for error due to the different inputs expected by the two functions. Since the [`_createMessage` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L160) is `private`, a user would have to implement their own means of obtaining the message.

In order to reduce the probability of errors during off-chain message creation, consider updating the `rawVerify` function to receive a fat signature as well, which it should first deconstruct to `authenticatorData`, `clientDataJSON`, and `rs` before creating the message and feeding it to `callVerifier`.

_**Update:** Resolved in [pull request #312](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/312/commits/4004ec007aa71c22786cffede7a5228bd8ba5c5b) at commit `4004ec0`. The function used for only testing purposes has been removed. The Matter Labs team stated:_

> _Removed to reduce confusion. We might come back to new tests later (larger change) that cover provided suggestions instead of the standalone precompile flow comparison._

### `SessionKeyValidator`'s `validateTransaction` Function Disregards Signature Parameter

The [`validateTransaction` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L142) of the `SessionKeyValidator` contract decodes [the `transaction.signature` field](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L147) instead of decoding [the supplied `signature` parameter](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L144). While this does not pose a security risk, it is inconsistent with [how `WebAuthValidator` is implemented](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L90).

Consider making code behavior consistent by decoding the supplied `signature` field in all cases.

_**Update:** Resolved in [pull request #307](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/307)._

### Inconsistent Order Within Contracts

Throughout the codebase, multiple instances of contracts having an inconsistent order of functions were identified:

*   The [`SessionKeyValidator`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol), [`SsoAccount`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/SsoAccount.sol), and [`WebAuthValidator`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol) contracts interlace functions with different visibilities. Consider either consistently ordering by logical sense or grouping the functions by visibility.
*   The [`SessionLib` library](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/libraries/SessionLib.sol) interlaces `enums` and `structs`.
*   The [`WebAuthValidator` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol) interlaces storage variables with events.

To improve the project's overall legibility, consider standardizing ordering throughout the codebase as recommended by the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-layout) ([Order of Functions](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-functions)). Alternatively, consider ordering by logical sense.

_**Update:** Acknowledged, will resolve. The Matter Labs team stated:_

> _It was decided to postpone reordering due to it being potentially disruptive to ongoing development (as it introduces a lot of conflicts)._

### Inconsistency Between Specifications and Implementation

The `IModule` interface [states](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/interfaces/IModule.sol#L10) that a call to the `onInstall` function "MUST revert on error (e.g., if the module is already enabled)". However, the current implementation allows the [`WebAuthValidator`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/WebAuthValidator.sol#L35-L39) and the [`SessionKeyValidator`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L52-L56) contracts to call such function multiple times when calling it directly from the `SsoAccount` contract with a different `data` input after the validators have been enabled.

In favor of keeping a consistent codebase, consider either restricting the calls to already enabled validators or redefining the specifications.

_**Update:** Resolved in [pull request #298](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/298) at commit [f13d0bd](https://github.com/matter-labs/zksync-sso-clave-contracts/commit/f13d0bd1325ccf65944f4b03dbfdf28f2a97e4a4)._

### Validation Not Failing Early

During the [session creation](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/fc0af3442594ad2dc343dbb2b918e478251bc293/src/validators/SessionKeyValidator.sol#L88-L89) in the `SessionKeyValidator` contract, the `expiresAt` parameter is used to set the `minuteBeforeExpiration` variable to either 0 or one minute before the supplied expiration. If `minuteBeforeExpiration` is 0, the transaction will revert within the `assertTimestampInRange` function of the `TimestampAsserter` contract.

Consider reverting earlier and explicitly, by adding an `if` statement that reverts the transaction if `sessionSpec.expiresAt` is smaller than 60.

_**Update:** Resolved in [pull request #298](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/298) at commit [a955d59](https://github.com/matter-labs/zksync-sso-clave-contracts/commit/a955d5959332280b7c213a94ae8b8535a5bad455)._

Conclusion
----------

The code under review introduces an innovative and modular smart contract account design that supports customization with flexible transaction validation methods and execution hooks. These accounts can be created and initialized without restrictions, integrating seamlessly into the ZKsync account abstraction flow, just like the existing `DefaultAccount`.

The project offers significant flexibility when it comes to implementing and attaching hooks or validators to an `SsoAccount` contract, the only requirement being the presence of the `onInstall` and `onUninstall` methods. While convenient as it supports creative development, this freedom of implementation can cause errors when integrating with the `SsoAccount` contract. Hence, addresses with privileged rights over an `SsoAccount` contract should research and do due diligence before attaching a new hook or custom validator.

In addition, while the existing test suite covers a broad range of scenarios, there is room for further improvement. Expanding test coverage and strengthening the suite would help ensure compliance with specifications while identifying potential errors and edge cases in the implementation.

We encourage the Matter Labs team to implement the fixes suggested in this audit. These include enhancing the test suite with extensive unit, integration, and backward-compatibility testing, and resolving outstanding backlog items. Nonetheless, the codebase feels quite robust, with direct flows and helpful documentation. The Matter Labs team has demonstrated exceptional responsiveness and collaboration throughout this process, promptly addressing questions and offering valuable insights. The technical documentation accompanying the codebase has been instrumental in understanding the high-level architecture of the ZKsync SSO components and their upgradeability.