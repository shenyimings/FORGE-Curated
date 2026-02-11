\- May 15, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

**Type:** Account Abstraction  
**Timeline:** April 3, 2025 → April 11, 2025**Languages:** Solidity

**Findings**Total issues: 33 (31 resolved)  
Critical: 0 (0 resolved) · High: 1 (1 resolved) · Medium: 3 (3 resolved) · Low: 12 (11 resolved)

**Notes & Additional Information**17 notes raised (16 resolved)

Scope
-----

OpenZeppelin audited the [matter-labs/zksync-sso-clave-contracts](https://github.com/matter-labs/zksync-sso-clave-contracts) repository at commit [ed21d09](https://github.com/matter-labs/zksync-sso-clave-contracts/tree/ed21d09add8da99d9c82d0f7c30659625c6636e6).

In scope were the following files:

`src
├── OidcKeyRegistry.sol
├── validators
│   └── OidcRecoveryValidator.sol
└── handlers
    └── ERC1271Handler.sol (diff audit for changes made in 2c20eb0)` 

System Overview
---------------

The code under review introduces a new type of account recovery with OpenID Connect (OIDC) to the `SsoAccount`, using OIDC along with zero-knowledge proofs to recover account control that has been lost, in addition to the existing recovery validators. Also under review was the `ERC1271Handler` contract against the `2c20eb0` commit, where the ERC-712 logic was removed to simplify the protocol. For an overview of `SSOAccount` and other validators, please refer to the previous audit reports.

The new OIDC recovery is useful because it allows users to recover lost account access through external OpenID Providers (OPs), such as Google. For that purpose, two new contracts were introduced: `OidcKeyRegistry` and `OidcRecoveryValidator`.

### `OidcKeyRegistry`

The `OidcKeyRegistry` stores OIDC keys of OPs, which can be added and deleted only by the contract owner. A circular buffer of eight keys is used for each issuer identifier (`issHash`). When a ninth key is added, it overrides the first key, maintaining the circular structure. Any key in the buffer can be removed by the owner. After removal, the remaining keys are compacted to occupy consecutive storage slots.

### `OidcRecoveryValidator`

The `OidcRecoveryValidator` is the main contract used for this OIDC-based recovery flow. To use this contract for recovering access, a user must enable it beforehand on their `SSOAccount` and ensure that `WebAuthValidator` is also installed as a validator. While the user still has access to their account, they should call the `addOidcAccount` function. This function requires the hash of OIDC data (constructed by hashing the subject identifier, the audience for the ID Token, the issuer identifier, and a user-specific salt) along with the OIDC issuer as a second argument. The data from this call is stored and later used during the recovery.

Using the OIDC data stored in the contract, along with other parameters required by the zero-knowledge circuit, the user can generate a proof to demonstrate control of the specified account. They can use another account to call the `startRecovery` function, submitting the proof and other parameters, including the address to be recovered. If the data is valid, the account is set to a “ready to recover” status, and a pending passkey hash is recorded. Note that the proof includes a time limit, after which it can no longer be used for verification.

Once the recovery process begins, anyone can initiate a call from the account being recovered, triggering the `validateTransaction` function. Successful execution requires providing the valid preimage of the passkey hash. The only allowed contract call at this point is to `WebAuthValidator` via the `addValidationKey` function, which sets the validation key for the account and completes the recovery.

### `ERC1271Handler`

The `ERC1271Handler` contract has been updated in commit `2c20eb0`, removing the ERC-712 logic to simplify the flow. OpenZeppelin has been asked to validate the new version of this contract.

Security Model, Trust Assumptions, and Privileged Roles
-------------------------------------------------------

During the audit, the following trust assumptions regarding the security model and privileged roles were made:

*   The owner of the `OidcKeyRegistry` is responsible for providing valid and up-to-date OIDC keys. Otherwise, users will be unable to recover access to their accounts.
*   The owner of the `SSOAccount` must not remove the `WebAuthValidator` from its validators. Otherwise, the `OidcRecoveryValidator` cannot be used to recover the account.

Design Choices, Limitations, and Integration Issues
---------------------------------------------------

During the assessment, potential concerns related to cross-account and multchain replay scenarios were discussed. While no immediate multichain risks were identified, the project's future roadmap includes building an ecosystem where additional chains may be deployed on top of the current infrastructure.

In this context, including the wallet address being recovered in the [`senderHash` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L213) and the unique nonce may serve as a preventative measure to avoid possible replay attacks across accounts that share auxiliary addresses. It is also worth noting that the current salt derivation process may be considered weak and should be strengthened accordingly. Lastly, the codebase could benefit from expanding the current test suite to cover more edge cases, including zk-proof verification flow.

High Severity
-------------

### Potential Signature Replay Attack in `ERC1271Handler`

The `isValidSignature` function is commonly used to verify signatures in scenarios where an external account is not required to initiate a call. It ensures that the contract allows the execution of some logic based on the check of provided inputs.

In the [`isValidSignature` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/handlers/ERC1271Handler.sol#L25) of the `ERC1271Handler` contract, insufficient checks may allow nearly any action if the contract calling `isValidSignature` does not fully validate the provided data or hash. For [EOA signatures](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/handlers/ERC1271Handler.sol#L26-L30) (65-byte signatures), there are no restrictions on how the hash is constructed, and the function only confirms the signature’s validity and its association with a `k1owner`. An attacker could reuse a historical transaction hash and signature and execute actions on behalf of the account. Additionally, EIP712 logic [was removed](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/391/files#diff-0ccc238950d01904211315cbce3cbf00b0c0f9638eed008de404ad766def9a2dL41) in the alternative validation method, permitting cross-chain attacks and the reuse of signatures across different accounts. Previously, [`_hashTypedDataV4`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/21c8312b022f495ebe3621d5daeed20552b43ff9/contracts/utils/cryptography/EIP712.sol#L109) included the chain ID and the verifier contract in the hash, safeguarding against such misuse.

Consider implementing the approach described in [ERC7739](https://eips.ethereum.org/EIPS/eip-7739), which proposes a defensive rehashing scheme specifically designed to address ERC1271 signature replay vulnerabilities—particularly across multiple smart accounts managed by the same EOA. This approach employs nested EIP-712 typed structures to maintain readability while effectively preventing signature replays. Additionally, consider protecting alternative validation methods, such as those using a validator, from signature replay attacks.

_**Update:** Resolved in [pull request #439](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/439) and commit [19747f1c](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/439/commits/19747f1c8d3ad65c7c5bb6bcd4e295246b3c57ee). The fix leverages the [ERC1271.sol](https://github.com/Vectorized/solady/commits/4c895b961d45c53a49ed500cfc76868b7ee1328b/src/accounts/ERC1271.sol) contract from the Solady library. Our team did not conduct an independent security review of this dependency and instead relied on the [audit report](https://github.com/Vectorized/solady/blob/main/audits/cantina-spearbit-coinbase-solady-report.pdf) provided in the GitHub repository. However, the integration of the contract was thoroughly reviewed. The Matter Labs team stated:_

> _We implemented ERC7739 to prevent signature replay attacks as well as ensure that the signed contents are fully visible to the user upon signing._

Medium Severity
---------------

### Incorrect Key Ordering in `_compactKeys` Function Leads to Potential Overwriting of New Keys

The [`_compactKeys` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L158) of the `OidcKeyRegistry` contract manages a list of keys in a ring-like structure, rearranging elements after one is removed to maintain compactness and continuity. However, it handles the ordering process by starting from the current index pointer instead of resetting to zero, leading to unintentional key rearrangements and potential data integrity concerns.

For example, if the key array is `[0, key1, key2, key3, key4, 0, 0, 0]` with the current `keyIndexes` pointer at `key4`, and `key3` is removed, the function reorders the keys from that pointer onward, producing `[key4, key1, key2, 0, 0, 0, 0, 0]`. After this operation, the insertion pointer incorrectly moves to index 2 (`key2`), causing the next new key to be inserted at index 3. This misalignment risks overwriting `key4` first in future operations, contradicting the FIFO principle which dictates that `key1` (the oldest key) should be replaced first. Consequently, newer keys could be overwritten prematurely, leading to potential data loss and unintended replacements.

Consider revising the `_compactKeys` function to preserve the original ordering after each compaction, regardless of the current insertion pointer’s position, ensuring that the FIFO sequence is maintained and preventing the overwriting of newer keys.

_**Update:** Resolved in [pull request #429](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/429) at commit [1829cf8](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/429/commits/1829cf8d51f2211913d14f26281254e50b7633e1) and in [pull request #435](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/435) at commit [8071a0ec](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/435/commits/8071a0ece4be78397c78e0f8d07df387bffac406)._

### Insufficient Validation of RSA Moduli and Exponent in `_validateKeyBatch`

The [`_validateKeyBatch` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L207) of the `OidcKeyRegistry` contract uses [`_hasNonZeroExponent`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L236) and [`_validateModulus`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L251) to validate the exponent and modulus, respectively. The `_validateModulus` function is responsible for verifying RSA moduli in cryptographic operations, ensuring they meet basic structural requirements for secure usage.

The `_validateModulus` function checks each chunk for size and non-zero values but does not enforce a minimum bit length to prevent factoring attacks. It also does not ensure that the modulus is odd, which is typically required because RSA moduli are the product of two odd primes. In addition, the exponent is only checked against zero, leaving the possibility of smaller exponents that may be vulnerable to known attacks.

Consider implementing a check to ensure the modulus meets a secure minimum bit length (for example, 2048 bits), verifying that it is odd, and enforcing a minimum exponent threshold of at least 65537. These measures will help strengthen the cryptographic properties of the system and mitigate multiple potential attack vectors.

_**Update:** Resolved in [pull request #430](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/430) at commit [1999421](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/430/commits/19994218756b2d8e0cc3678185fdd8ed8b4bf533). The Matter Labs team stated:_

> _Regarding the recommendations:_ - _The **modulus is always interpreted as a 2048-bit number**. The contract receives an array of 17 chunks of 121 bits each. All of them together are later interpreted by the circuit as a 2048-bit modulus._ - _The **recommendation to verify that the modulus is odd has been addressed.** We have implemented validation that takes into account the specific Circom formatting used for big numbers, where the modulus is encoded as 17 chunks and the least significant chunk it’s at the left (same order as little-endian for bytes). Our implementation ensures that the first chunk is not 0 mod 2, effectively validating that the modulus is odd as required for RSA security._ - _Regarding the exponent threshold (65537), **the contract no longer handles variable exponents** - this value is hardcoded in the circuit, eliminating the need for runtime validation._

### Unauthorized Control via Manipulated `pendingPasskeyHash` in `startRecovery` Process

When both the `OidcRecoveryValidator` and `WebAuthValidator` contract are active for an account, and the account owner loses access, a recovery process can be initiated using a zero-knowledge (ZK) proof. This proof demonstrates ownership of the associated OIDC identity, as registered in the `OidcRecoveryValidator` contract. Once the proof and associated data are verified, any party can call the `startRecovery` function to begin account recovery.

Although most parameters in the [`startRecovery` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L201) are validated by both the ZK circuit and the contract, there is no verification of the `data.pendingPasskeyHash` before [it is written to the account’s storage](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L239C58-L239C76). This enables a scenario where the party initiating recovery (who has access to the valid ZK proof) could submit a malicious `pendingPasskeyHash` (one for which they possess the corresponding private key). As a result, they can complete the recovery through the `WebAuthValidator` contract, effectively taking control of the account, even if they were not the intended recipient of the recovery request.

Consider adding a public signal to the ZK proof to bind the `pendingPasskeyHash` parameter to the proof itself, and store this hash only after the proof has been verified.

_**Update:** Resolved in [pull request #431](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/431) at commit [ba4967a](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/431/commits/ba4967ac13586e6b859393a135ee0fb5b7372b28). The Matter Labs team stated:_

> _In order to address this issue we included the `pendingPasskeyHash` inside the content of the JWT nonce. The nonce content was previously calculated as:_

`keccak256(abi.encode(msg.sender,  oidcData.recoverNonce,  data.timeLimit));` 

> _Now it’s calculated as:_ `solidity keccak256(abi.encode(msg.sender, targetAccount, data.pendingPasskeyHash, oidcData.recoverNonce, data.timeLimit));` _This ensures that the user actually wanted to use the given passkey, and also makes the pendingKeyHash part of the data being checked by the circuit._

Low Severity
------------

### Duplicate `kid` Values in `OidcKeyRegistry` Allow for Partial Key Deletion and Retrieval

In the `OidcKeyRegistry` contract, the [`addKeys` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L100) enables the addition of multiple keys simultaneously. Although this function performs several validations, it lacks a crucial check to prevent the insertion of multiple keys with identical `kid` values. This oversight may result in inconsistent states within the key registry, particularly when the [`deleteKey`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L191-L193) function is used. The `deleteKey` function is designed to remove a key based on its `kid` value. However, it only removes the first occurrence of a matching `kid`, leaving any additional duplicates intact.

For example, if an entity inadvertently adds multiple keys with the same `kid` and later attempts to revoke a compromised key by its `kid`, only a single instance—the first match—will be removed. The remaining duplicate keys with the same `kid` will persist in the registry, potentially leaving the system vulnerable. Furthermore, this issue impacts the [`getKey` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L118) which is intended for retrieving a key by its `kid`. Similar to the `deleteKey` function, the `getKey` function will only return the first key that matches the provided `kid`, ignoring any additional keys with the same `kid` that may have been erroneously added.

To mitigate this issue and preserve the integrity of the key management process, consider implementing a validation mechanism in both the `addKeys` and `addKey` functions to enforce the uniqueness of each `kid` value.

_**Update:** Resolved in [pull request #432](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/432) at commit [bc71d5e](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/432/commits/bc71d5eda89f1e8c3b027255b30b2c321bca4862)._

### Front-Running in `addOidcAccount` Account Registration

The [`OidcRecoveryValidator`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L21) contract uses a `digestIndex` mapping to associate unique identifiers (`oidcDigest`) with user accounts. This mechanism ensures that each identifier is distinct within the system. However, the current implementation allows for a scenario in which a malicious user can perform a front-running attack.

Specifically, an attacker can monitor the pending registration transactions in the mempool. Upon detecting a legitimate user's attempt to register an `oidcDigest`, the attacker can submit their own transaction using the same `oidcDigest`, thereby claiming it first. As a result, when the legitimate transaction eventually reaches the [`addOidcAccount` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L163-L179), the verification step fails due to the `oidcDigest` already being registered, causing the transaction to revert and preventing the legitimate user from associating their validator with their account.

_Note that given that no elastic chain operators have public mem-pools or shared sequencers, this is a possible future issue._

Consider implementing additional verification steps or securing transaction commitment mechanisms that bind the registration request directly to the originating account. This approach would effectively prevent attackers from preemptively claiming `oidcDigest` identifiers.

_**Update:** Acknowledged, not resolved. The Matter Labs team stated:_

> _Given that **no elastic chain operators have public mem-pools or shared sequencers, this is at best a possible future issue**. The design rationale lies in avoiding the requirement for users to input their address during account recovery. In the future, we might consider removing the one-to-one OIDC-to-Google account restriction, which would significantly complicate the UX but would prevent this kind of front-running._

### Builtin Getter for `OIDCKeys` Does Not Return `n`

The [`OIDCKeys` variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L77) is declared with a `public` visibility modifier, causing the Solidity compiler to automatically generate a `public` getter function. However, this getter will only return the struct’s simple members (`issHash`, `kid`, and `e`), and it will omit complex data structures such as `n`. This happens because automatically generated getters for `public` state variables do not return array or mapping members within structs, even when nested. For more information, see the [Solidity documentation](https://docs.soliditylang.org/en/latest/contracts.html#getter-functions).

Since the contract already implements the `getKeys` getter, consider removing the automatic getter (that does not retrieve all the data) by reducing the variable's visibility.

_**Update:** Resolved in [pull request #433](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/433) at commit [cd57ff7](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/433/commits/cd57ff75e430a332bf2462cebc9f823cfcf5540a)._

### Potential Loss of Ownership During Transfer

The [`OidcKeyRegistry` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L11) implements a single-step ownership transfer process which may lead to unintended loss of ownership if the new owner address is incorrect or inaccessible. This pattern does not provide a safeguard to recover from such scenarios, and any mistake in the transfer can result in permanent loss of administrative control.

The issue lies in the absence of a confirmation step during the ownership transfer. In the current implementation, ownership is immediately reassigned once the transfer function is called, without requiring the new owner to accept the role. This increases the risk of errors during execution, particularly if an incorrect or unprepared address is specified.

Consider using the [`Ownable2StepUpgradeable`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/7c8e90046cdf3447971c201c1940d489fa2064bb/contracts/access/Ownable2StepUpgradeable.sol#L26) contract from the OpenZeppelin library, which introduces a two-step transfer pattern. This approach requires the new owner to explicitly accept ownership, reducing the chance of accidental loss of control and improving operational safety.

_**Update:** Resolved in [pull request #422](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/422) at commit [77036be](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/422/commits/77036be9bff968bf49046ba4c525f4c8f791ac23)._

### Inflexible Recovery Process Termination in `OidcRecoveryValidator`

The `OidcRecoveryValidator` contract, as currently implemented, lacks a method to halt an initiated recovery process without complete termination of the account's linkage to its issuer. Once the recovery process is [initiated](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L239-L241), if the subsequent transaction that triggers the `validateTransaction` function is not executed, the only way to [abort the recovery process](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L283) is by invoking the [`deleteOidcAccount` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L182).

However, the `deleteOidcAccount` function is designed to sever the connection between an account and its issuer entirely. Utilizing it to discontinue an ongoing recovery process consequently eliminates the possibility of future recoveries unless the [`addOidcAccount` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L163) is called again to reestablish the linkage. This binary choice compels users to decide between retaining a potentially vulnerable recovery option or completely losing their account's recovery functionality, a decision that is less than ideal for user security and convenience.

To address this limitation, consider introducing a feature that permits users to selectively revoke or invalidate an ongoing recovery process without the need to eliminate the entire account and issuer connection. This enhancement would significantly improve the flexibility and security of the recovery process, offering users better control over their recovery options.

_**Update:** Resolved in [pull request #441](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/441) at commit [d52ddf9](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/441/commits/d52ddf9337f8fabfcc7bf6525b255b1a187ebbc5). The Matter Labs team stated:_

> _We added a new method `cancelRecovery` that allows a user to cancel a recovery for their own account. This can be used for the case where an OIDC based recovery was started but not finished, and then the user was able to recover their account in a different way (for example, using guardians)._
> 
> _We also added a time validation as part of `L-06`, which also works a way to cancel an ongoing recovery._

### Delayed Recovery Validation May Compromise Account Security

In the `OidcRecoveryValidator` contract, the account recovery process flow is divided into two separate function calls, with the `startRecovery` and `validateTransaction` functions, due to the high gas consumption associated with verifying zero-knowledge proofs. This design choice introduces a potential security vulnerability related to the timing of these operations.

The initial `startRecovery` function [includes a check](https://www.openzeppelin.com/news/[link](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L202-L203)) to ensure that the recovery process is not initiated after the expiration of the proof. However, this verification does not account for the time elapsed between the execution of the `startRecovery` call and the `validateTransaction` call. Consequently, there exists a significant time window in which the recovery process can be completed long after the execution of the `startRecovery` contract. This delayed validation poses a risk, especially if account control is regained through alternative means, but the recovery process remains pending execution via `validateTransaction` through the validation on the `OidcRecoveryValidator` contract.

To mitigate this risk and enhance the security of the recovery process, consider implementing an additional check within the `validateTransaction` function to verify the timeliness of the recovery action, successfully validating the transaction if it is still within the time window. This check should ensure that the recovery is still valid at the time of the `validateTransaction` function execution, thereby eliminating the possibility of having an undesired time window in the recovery flow. Moreover, it is worth noting that a user might initiate recovery of the account through a different mechanism (such as with a Guardian) even if they are still in the time window for the OIDC recovery process.

_**Update:** Resolved in [pull request #423](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/423) at commit [21d16e5](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/423/commits/21d16e5e6635a88e7ca3d636680b5fb50ef2c9c5). The Matter Labs team stated:_

> _We have implemented a time validation window of 10 minutes between the initiation and execution of the recovery process. This duration is considered sufficient since the most time-intensive operation - proof generation - occurs before the `startRecovery` function is called. By enforcing this time constraint, we ensure that delayed recoveries cannot be executed beyond the intended window._

### Old `digestIndex` Not Released on OIDC Account Update

The [`OidcRecoveryValidator` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L21) uses [a `digestIndex`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L108) to ensure the uniqueness of OIDC (OpenID Connect) digests associated with user accounts. Each time a user adds or updates their OIDC account via the [`addOidcAccount` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L163), a digest representing the OIDC data is stored to [prevent reuse](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L175). This mechanism ensures that no two accounts can register the same OIDC identity, maintaining integrity across the recovery process.

However, when a user updates their OIDC account, the [previously assigned `digestIndex` value](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L175) is not cleared. As a result, the old OIDC digest remains reserved under the user's account even though it is no longer in use. If the user later attempts to restore a previously valid OIDC digest, for example, to revert to an earlier identity, they will be blocked by the [uniqueness check](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L164), which still considers the old digest as taken, despite it originally belonging to the same user.

Consider explicitly clearing the user's old `digestIndex` value before assigning the new one during an account update. This would allow legitimate reuse of previously held digests and ensure consistency in digest management.

_**Update:** Resolved in [pull request #424](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/424) at commit [d7a71ca](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/424/commits/d7a71caed03e2163afe3ff98c9144e529fb530b3)._

### The `addOidcAccount` Function Always returns `false`

In the [`addOidcAccount` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L163), the returned boolean indicates whether an account has been newly added or merely updated. The function [checks](hhttps://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L167) the current state by inspecting the length of the `oidcDigest` field within the stored account data, which is then emitted via the `OidcAccountUpdated` event and returned by the function. According to the [documentation](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L162), the function should return `true` if a new key is added and `false` if an existing key is updated.

However, the logic currently implemented misunderstands how length is calculated for the `bytes32` type. The length of a `bytes32` value is always 32 bytes, regardless of the content, meaning the `accountData[msg.sender].oidcDigest.length == 0` condition will consistently evaluate to `false`. Consequently, the returned value and the emitted event will incorrectly indicate that an account is always updated rather than newly created, potentially causing confusion or misinterpretation of account status. It is worth mentioning that the [correct check](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L319) is being performed in the `oidcDataForAddress` function.

In favor of being able to detect when a new key is added and improving code consistency, consider whether comparing the value of `oidcDigest` to zero (e.g., `oidcDigest == bytes32(0)`) might more accurately reflect whether the account is new, rather than relying on its length.

_**Update:** Resolved in [pull request #424](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/424) at commit [d7a71ca](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/424/commits/d7a71caed03e2163afe3ff98c9144e529fb530b3). The Matter Labs team stated:_

> _This issue has no PR for itself because it was resolved as part of `L-07`._

### Inconsistencies in Account Recovery Data During Recovery Process

When an OpenID Connect (OIDC) identifier is linked to an account, the [`addOidcAccount` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L163) only updates three specific parameters in the `accountData` mapping and one in the `digestIndex` mapping for the concerned account. This selective update process neglects the `readyToRecover`, `pendingPasskeyHash`, and `recoverNonce` fields, leaving them at their default values or preserving their previous states. Such behavior creates a risk of inconsistencies, as outdated data could potentially lead to misleading behaviors or the misuse of obsolete recovery states.

The core issue arises when the [recovery process is initiated](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L201) and a specific [set of parameters](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L172-L174) is verified. However, before the `validateTransaction` call occurs, these parameters might get overwritten by a subsequent invocation of the `addOidcAccount` function by the account. This action updates the aforementioned parameters without fully resetting the `OidcData` variables, inadvertently leaving the `readyToRecover` flag active and the `pendingPasskeyHash` variable set from a prior session. This scenario becomes problematic when an account initiates a recovery using a specific `publicKey` and, after gaining access through another recovery method, the user decides to update the `accountData` by calling the `addOidcAccount` function, not realizing that the original `publicKey` can still be set when using the `OidcRecoveryValidator` contract as the validator.

Realizing such a scenario requires the functions to be executed from the account itself, indicating that access was previously granted through another method and that the user needs to proactively participate in order for this to happen. Nonetheless, to minimize the risk associated with unexpected recovery flows and to enhance the integrity of the recovery process, particularly not mixing data from 2 different recovery processes, consider implementing mechanisms that reset or suitably update all pertinent fields within the `accountData` mapping whenever an OIDC identifier is added or the recovery process is initiated.

_**Update:** Resolved in [pull request #425](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/425) at commit [aa78035](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/425/commits/aa7803581e3f4edf848846a06184c5c6fc38dfcb)._

### Insufficient Validation in Recovery Process May Lead to Wasted Recovery Attempts

The `OidcRecoveryValidator` contract introduces a mechanism for account recovery, culminating in the addition of a new `publicKey` to the `WebAuthValidator` contract. Initially, an account is [linked to an `oidcDigest`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L163), and upon the need for recovery, a [submission process is initiated](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L201) that verifies proofs against the `oidcDigest`. If verification is successful, any participant can execute a transaction to incorporate the new `publicKey` into the [`WebAuthValidator`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/WebAuthValidator.sol#L94).

However, a problem arises when the `credentialId` and `originDomain` parameters do not meet some of the requirements in the `WebAuthValidator` contract, in which the call [will not revert but will instead return a `false` output](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/WebAuthValidator.sol#L100-L111). In such a scenario, the call will be considered successful without reversion, regardless of the non-inclusion of the `publicKey`. As a result, the [recovery attempt will be consumed](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L282-L283) and a new recovery will be needed.

This flaw not only risks the unnecessary consumption of recovery attempts due to parameter mismatches but also exposes the problem of users who, knowledgeable of the user's `publicKey`, could deliberately consume the recovery attempt by submitting transactions with arbitrary, incorrect parameters alongside the `publicKey`, that will not pass the `WebAuthValidator` contract requirements.

To mitigate the risk of wasted recovery attempts and protect against potential misuse, consider binding the `credentialId` and `originDomain` arguments within the [zkProof](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L235) and storing this binding in the contract for subsequent validation in the `validateTransaction` function. This change ensures that these parameters remain immutable during the `validateTransaction` call, preventing unauthorized or unintended consumption of recovery attempts.

_**Update:** Resolved in [pull request #426](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/426) at commit [35ff79c](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/426/commits/35ff79ced9f7ae5e90232913dc17c9213e7b2bb5)._

### Insufficient Validation of `iss` Argument Length in `addOidcAccount`

The `addOidcAccount` function includes a check to ensure that the `iss` (issuer) argument is [not empty](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L165). This value is later used within a zero-knowledge circuit, where its length is expected to be less than 32 characters, based on the [template argument definition](https://github.com/Moonsong-Labs/zksync-social-login-circuit/blob/27cda6e74492fbad4aa3ca37ff5084ed391b534b/jwt-tx-validation.circom#L43) and the [constant value](https://github.com/Moonsong-Labs/zksync-social-login-circuit/blob/27cda6e74492fbad4aa3ca37ff5084ed391b534b/jwt-tx-validation.circom#L138) provided. While the lower bound is enforced by the existing validation, the upper bound (critical for zero-knowledge proof verification) is not.

As a result, values longer than the expected maximum can be stored, even though they would not be valid for proof generation or verification in the zero-knowledge circuit. This creates a discrepancy between what can be stored on-chain and what can be successfully proven off-chain.

Consider enforcing an upper bound on the `iss` argument length to ensure that it is strictly less than 32 characters, in addition to the existing non-zero length check.

_**Update:** Resolved in [pull request #427](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/427) at commit [22d3b4f](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/427/commits/22d3b4fe8212f46a33c5f87fb444951217b59aa5)._

### `OidcRecoveryValidator` Does Not Follow the ERC-1271 Flow

The [`validateSignature` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L289) of the `OidcRecoveryValidator` contract reverts when being called. This happens because the validator is only supposed to provide a recovery mechanism to the account instead of validating any other kind of transaction. However, its current implementation deviates from the expected [ERC-1271 flow](https://eips.ethereum.org/EIPS/eip-1271) by reverting on calls instead of returning a boolean value. This behavior contrasts with the intended flow, where the `validateSignature` function should signal a negative outcome by returning `false` to let the `ERC1271Handler` contract not return the [magic value](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/handlers/ERC1271Handler.sol#L37).

Given that analogous validator contracts within the system [return `false`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/GuardianRecoveryValidator.sol#L296) under similar conditions, aligning the `OidcRecoveryValidator` contract's behavior with this pattern would enhance consistency and predictability in the signature validation process. Therefore, consider modifying the `validateSignature` function to return `false` instead of reverting, ensuring that it adheres to the established ERC-1271 flow.

_**Update:** Resolved in [pull request #428](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/428) at commit [5141a07](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/428/commits/5141a07c5d84a6e3bba4330989a0bc55079218fc)._

Notes & Additional Information
------------------------------

### Using `uint8` for Constants Is More Expensive Than `uint256`

In both `OidcKeyRegistry` and `OidcRecoveryValidator`, `uint8` is being used for constants (e.g., for the [`MAX_KEYS` constant](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L13)). However, this introduces unnecessary overhead during deployment, as additional range checks are required, making the deployment more expensive. For instance, using `uint8` in the `OidcKeyRegistry` costs around `28,267,888` gas, whereas `uint256` costs about `28,175,109`, saving approximately `92,779` gas.

Since these values are constants and manually verified to be within the expected range, there is no added risk in switching to `uint256`. Consider updating `uintN` constants to `uint256` to optimize deployment costs.

_**Update:** Resolved in [pull request #399](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/399) at commit [d0c788e](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/399/commits/d0c788e251052b8fac8da60c295ad3726618a317)._

### Inconsistent License in `OidcKeyRegistry.sol`

The [`OidcKeyRegistry.sol` file](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L1) uses the `UNLICENSED` license, while the rest of the codebase is either licensed under GPL-3.0 or MIT. This inconsistency may create uncertainty around usage and distribution.

Consider updating the license in `OidcKeyRegistry.sol` to align with the rest of the codebase, such as GPL-3.0 or MIT.

_**Update:** Resolved in [pull request #400](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/400) at commit [894321c](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/400/commits/894321c0da30db3ef8c00330b16bfb37b979acb9)._

### Redundant Local Variable in `_validateModulus`

In the [`_validateModulus` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L251), the `uint256 limit` variable is calculated as `(1 << 121) - 1`. Currently, the `limit` is computed within the function on every invocation and, as this value remains unchanged throughout the function execution, recalculating it repeatedly consumes unnecessary gas.

Consider defining `limit` as a constant outside the `_validateModulus` function to avoid unnecessary recalculations and reduce gas usage.

_**Update:** Resolved in [pull request #401](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/401) at commit [7e36375](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/401/commits/7e36375021f0778f7c9149c63d688e2ccf14743c)._

### Use of `uint` Instead of `uint256`

While `uint` is an alias for `uint256`, for clarity and consistency, it is recommended to use `uint256` explicitly.

Within `OidcRecoveryValidator.sol`, multiple instances of `uint` being used instead of `uint256` were found:

*   The [`uint`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L86) in line 86
*   The [`uint`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L87) in line 87
*   The [`uint`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L88) in line 88
*   The [`uint`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L217) in line 217
*   The [`uint`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L221) in line 221
*   The [`uint`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L226) in line 226
*   The [`uint`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L334) in line 334

In favor of explicitness, consider replacing all instances of `uint` with `uint256`.

_**Update:** Resolved in [pull request #402](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/402) at commit [13312f8](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/402/commits/13312f822673cbd8a2bd4126f6611c0f93f2a4b7)._

### Magic Numbers in the Code

Throughout the codebase, multiple instances of literal values with unexplained meanings were identified.

*   The [`8`s](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L231) literal in `OidcRecoveryValidator.sol`
*   The [`248`s](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L233) literal in `OidcRecoveryValidator.sol`
*   The [`32`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L334) literal in `OidcRecoveryValidator.sol`
*   The [`32`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L335) literal in `OidcRecoveryValidator.sol`
*   The [`8`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L335) literal in `OidcRecoveryValidator.sol`
*   The [`8`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L336) literal in `OidcRecoveryValidator.sol`

Consider defining and using `constant` variables instead of using literals or properly documenting the literals values to improve the readability and maintainability of the codebase.

_**Update:** Resolved in [pull request #403](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/403) at commit [acd7822](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/403/commits/acd7822c86719453b297fc4c6afbac8fcede540e)._

### Use Custom Errors

Since Solidity version 0.8.4, custom errors provide a cleaner and more cost-efficient way to explain to users why an operation failed.

In `OidcRecoveryValidator.sol`, multiple instances of `require` messages were identified:

*   The [`require(_keyRegistry != address(0), "_keyRegistry cannot be zero address")`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L128) statement
*   The [`require(_verifier != address(0), "_verifier cannot be zero address")`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L129) statement
*   The [`require(_webAuthValidator != address(0), "_webAuthValidator cannot be zero address")`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L130) statement
*   The [`require(oidcDigest != bytes32(0), "oidcDigest cannot be empty")`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L164) statement
*   The [`require(bytes(iss).length > 0, "oidcDigest cannot be empty")`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L165) statement

For conciseness, gas savings, and consistency with the rest of the codebase that makes use of [custom errors](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/WebAuthValidator.sol#L64), consider replacing `require` and `revert` messages with custom errors.

_**Update:** Resolved in [pull request #404](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/404) at commit [2e27794](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/404/commits/2e27794fc8fd7cde80f5e38fe439eca5487ff72f)._

### Missing Event Emission in `startRecovery`

When the [`startRecovery` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L201-L242) of the `OidcRecoveryValidator` contract is invoked, it does not trigger any event.

Consider emitting an event to reflect that a recovery has started, which would improve the clarity of the codebase and ease off-chain monitoring.

_**Update:** Resolved in [pull request #405](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/405) at commit [a375b7a](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/405/commits/a375b7acd151e11276ec36463b5ac3b9abc291e4)._

### State Variable Visibility Not Explicitly Declared

Within [`OidcRecoveryValidator.sol`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol), multiple instances of state variables lacking an explicitly declared visibility were identified:

*   The [`PUB_SIGNALS_LENGTH` state variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L23)
*   The [`accountData` state variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L105)
*   The [`digestIndex` state variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L108)

For improved code clarity, consider always explicitly declaring the visibility of state variables, even when the default visibility matches the intended visibility.

_**Update:** Resolved in [pull request #434](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/434) at commit [41e77cb](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/434/commits/41e77cb18b19194e5f4c303d6837783d1bcaa998)._

### Circular Buffer Initialization Causes Counterintuitive Key Indexing

In the implementation of the `OidcKeyRegistry` contract, keys are added to a circular buffer with an initial offset. This design choice results in non-intuitive behavior during the buffer's initial population cycle. Specifically, when fully initializing the ring with a series of keys, the last key provided in the sequence is assigned to the zero index of the buffer. This occurs due to the [offset applied](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L148) during the key addition process, which effectively shifts the position of the initially added keys.

For example, when populating a ring buffer intended to hold eight keys with five specific keys, one might expect the keys to sequentially occupy indices from zero to four. However, the actual placement after the first addition cycle ranges from indices one to five (`| 0 | k1 | k2 | k3 | k4 | k5 | 0 | 0 |`). Similarly, when adding a full cycle of eight keys, the last key (`k8`) occupies the zero index (`| k8 | k1 | k2 | k3 | k4 | k5 | k6 | k7 |`). This disrupts the expected sequential ordering established during the initialization.

Consider adjusting the key addition logic to ensure that the first key added occupies the zero index of the buffer, maintaining consistent and intuitive indexing throughout the buffer's lifecycle.

_**Update:** Resolved in [pull request #435](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/435) at commit [8071a0e](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/435/commits/8071a0ece4be78397c78e0f8d07df387bffac406)._

### Missing Interface for `OidcRecoveryValidator` Contract

The [`OidcRecoveryValidator` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L21) lacks an interface that corresponds to its available implementation functions, such as [`addOidcAccount`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L163) and [`deleteOidcAccount`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L182). In addition, definitions such as [events, errors, and structs](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L25-L102) can be included within this interface to improve developer experience and protocol interoperability. This change would streamline the contract's structure and enhance usability across different development contexts. Moving these definitions into the interface would also simplify interactions, event decoding, error handling, and passing structs as input or output parameters in other contracts.

Consider creating an interface that directly includes the above-mentioned definitions. This approach aligns with best practices in smart contract design and enhances developer experience by providing a clearer, more intuitive way to interact with the contract’s functionalities.

_**Update:** Resolved in [pull request #408](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/408) at commit [02e0df0](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/408/commits/02e0df0ffd4f2936bb0edb4b8d7816a6d68996b0)._

### Refactor and Improvement Opportunities

Throughout the codebase, multiple opportunities for code improvement were identified:

*   In the [`OidcRecoveryValidator` contract](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L11), two contract addresses (`keyRegistry` and `verifier`) are stored as raw `address` types and then cast to their respective contract types only when accessed. These casting operations are performed only once throughout the contract. Instead of casting the `address` to a contract at the point of use, consider updating the constructor to include the casting operation and adjust the type of the storage variable accordingly. This approach would not only streamline the contract code by eliminating the need for casting at the point of use but also potentially reduce gas costs associated with the casting operation.
*   The [`OidcDigestAlreadyRegisteredInAnotherAccount` custom error](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L169) reverts with the `oidcDigest` argument when the digest has already been registered. However, the `oidcDigest` is provided by the caller and is therefore already known, making its inclusion potentially redundant. It would be more useful if the error included the address of the account that has registered the digest. Consider replacing such a parameter.
*   The [`for` loop](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L220) in the `startRecovery` function iterates `key.n.length` times and the auxiliary variable `index` is incremented on each iteration. However, after the loop completes, `index` will be equal to the number of elements in `key.n`. Consider not incrementing the `index` variable inside the loop. Instead, assign the length of `key.n` directly to `index`.
*   The [casting of each `Key.n`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L221) in the `for` loop is unnecessary, as each `n` element in the array is already a [`uint256` variable](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L27). Consider removing such casting.
*   The current implementation of the [`startRecovery` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L201) splits [`senderHash`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L231) into two values using multiple bitwise shift operations. This can be optimized by applying a single bitwise mask after calling the `_reverse` function, setting the most significant byte (in little-endian format) to zero. The [last element](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L233) of the `publicInputs` can be simplified by truncating `senderHash` to `uint8` and then casting it back to `uint256`. This approach reduces stack operations, decreases the number of constants pushed onto the stack, and achieves better gas efficiency compared to multiple shifts.
*   The current implementation of the `_reverse` function reverses bytes by using additional intermediate variables and multiple arithmetic operations per iteration, consuming approximately 29k gas per call. This can be optimized by replacing it with a bitwise accumulation approach, where the result is built by repeatedly shifting the output left by one byte and combining it with the least significant byte of the input. The optimized version reduces gas usage to approximately 3.9k per call.

To improve the readability and gas efficiency of the codebase, consider applying the aforementioned recommendations.

_**Update:** Resolved in [pull request #410](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/410) at commit [26529e1](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/410/commits/26529e122749907d319bac5000390a85d92ff479)._

### Unnecessary `override` Keyword in `onInstall` and `onUninstall`

In the `OidcRecoveryValidator` contract, the [`onInstall`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L139) and [`onUninstall`](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L155) functions are marked with the `override` keyword. This usage suggests that these functions are intended to override implementations from a parent contract. However, these functions implement abstract function declarations from an interface instead of overriding concrete implementations from an ancestor contract. In Solidity, the `override` keyword is used to indicate that a function is overriding a function from a base contract. When a function is merely implementing an interface's method, the use of `override` is not necessary. In this case, the use of the `override` keyword could potentially lead to confusion regarding the inheritance structure of these functions, as it points to an inheritance relationship that does not exist.

To enhance code clarity and accurately reflect the inheritance and implementation structure, consider removing the `override` keyword from the `onInstall` and `onUninstall` function declarations in all places where it is not needed.

_**Update:** Resolved in [pull request #411](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/411) at commit [5b48556](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/411/commits/5b48556198f73abfeff53943204d40d9332ded26)._

### Redundant External Call to `hashIssuer` in `OidcRecoveryValidator`

The [`hashIssuer` function](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L210) of the `OidcKeyRegistry` contract is invoked in the `startRecovery` function of the `OidcRecoveryValidator` contract. This function performs a simple hashing operation on a single input argument. Since the logic is minimal and does not rely on any internal state of the `OidcKeyRegistry` contract, calling it externally introduces unnecessary complexity and potential gas overhead.

Consider moving the `hashIssuer` function directly into the `OidcRecoveryValidator` contract or duplicating its logic within the contract to avoid the external call.

_**Update:** Acknowledged, not resolved. The Matter Labs team stated:_

> _The method `hashIssuer` inside `OidcKeyRegistry` ensures consistent hash generation for issuers. While duplicating this logic would yield minimal gas savings, it would create redundant code that might need synchronization if changes occur in the future._
> 
> _Considering the low gas costs in the elastic chain ecosystem, we consider that maintaining the external method call is preferable to duplicating the logic._

### Endianness Mismatch in `senderHash` Representation Between Contract and Circuit

The `startRecovery` function [splits](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L231-L233) the 32‑byte `senderHash` into two 31‑byte fields to fit the circuit’s input size. The [first part](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L231) is produced by right‑shifting the hash, which moves the zero inserted by the shift to the least‑significant end, and then discarding that zero, yielding a [little‑endian](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L230) sequence `B1 … B31` (with `B0` already extracted). The second part is obtained by isolating the least‑significant byte (`B0`) without reversal, leaving it unchanged in the least‑significant byte of the word. As a result, the same logical value is encoded partly in little‑endian and partly in its original order before being supplied to the circuit.

Because the circuit appears to expect a uniform byte order for the entire 32‑byte value, this mixed representation can cause the circuit to reconstruct an incorrect `senderHash`, leading to failed proofs or other unexpected verification results.

Consider encoding both parts in the single endianness expected by the circuit—for example, reverse the full 32‑byte hash before splitting or omit reversal for both parts—so that the contract and circuit consume an identical byte order and the hash can be reconstructed unambiguously.

_**Update:** Resolved in [pull request #436](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/436) at commit [d0cf420](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/436/commits/d0cf4204e31fd291e0ea88456ea9ee0d3679329d). The Matter Labs team stated:_

> _We changed the the serialization of the txHash to simply take the first 31 bytes in the first element (without any kind of reverse) and the last byte in a second element (also without any revert)._
> 
> _We also made the changes in the circuit input generation code to be coherent with this. Those changes were also considered in the documentation of the circuit._
> 
> _This also allowed us to remove the `_reverse` internal function that was only being used here._

In the `OidcRecoveryValidator` contract, the `startRecovery` function [includes a comment](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L219) intended to describe the structure of the `publicInputs` array. Specifically, the comment currently states: “First `CIRCOM_BIGINT_CHUNKS` elements are the OIDC provider public key.” This can be misleading to readers who assume the RSA public key includes both the modulus and the exponent, as per standard cryptographic definitions.

The implementation, however, only [includes the modulus](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/OidcKeyRegistry.sol#L22) in these elements. The exponent is not part of this structure, contrary to what might be inferred from the current comment. This inconsistency can cause confusion for developers or auditors reviewing the code, particularly those relying on the comment to understand the data layout without inspecting the logic in detail.

Consider updating the comment to accurately reflect the content of the input, such as: “First `CIRCOM_BIGINT_CHUNKS` elements are the OIDC provider modulus.” This will improve code readability and help ensure correct assumptions about the key structure.

_**Update:** Resolved in [pull request #442](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/442) at commit [5d8d557](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/442/commits/5d8d55700a755789214d609382369811bac29f34)._

### Redundant Inheritance from `VerifierCaller` in `OidcRecoveryValidator`

The `OidcRecoveryValidator` contract inherits from the `VerifierCaller` contract. However, in the current implementation of the `OidcRecoveryValidator` contract, none of the functions or features provided by the `VerifierCaller` contract are utilized.

This results in unnecessary inheritance, which can increase the contract size and complicate the codebase without providing any functional benefit.

Consider removing the inheritance of the `VerifierCaller` contract in the `OidcRecoveryValidator` contract to simplify the contract and reduce potential maintenance overhead.

_**Update:** Resolved in [pull request #408](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/408/files#diff-51ffac239beb4bdcc415db8bf9e007723a57df383e1ee6dfbf5ce11a5813ea53R21) at commit [02e0df0f](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/408/commits/02e0df0ffd4f2936bb0edb4b8d7816a6d68996b0). The Matter Labs team stated:_

> _This issue was solved as part of [`N-10` fix](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/408/files#diff-51ffac239beb4bdcc415db8bf9e007723a57df383e1ee6dfbf5ce11a5813ea53R21)._

### Inconsistent Handling of `addOidcAccount` Return Value in `OidcRecoveryValidator`

The current [`onInstall` implementation](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/ed21d09add8da99d9c82d0f7c30659625c6636e6/src/validators/OidcRecoveryValidator.sol#L149) ignores the return value of the `addOidcAccount` function. This might be confusing for readers, as it’s not immediately clear whether the return value is intentionally disregarded or if it’s an oversight.

Consider documenting the reasoning behind ignoring the return value of the `addOidcAccount` function.

_**Update:** Resolved in [pull request #440](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/440) at commit [0e6415e](https://github.com/matter-labs/zksync-sso-clave-contracts/pull/440/commits/0e6415e0d3b64813ddc06384ad3137700e65f310). The Matter Labs team stated:_

> _The **return value was removed** because it was not being utilized anywhere in the codebase._

Conclusion
----------

The reviewed code introduces an OIDC-based account recovery mechanism to enhance the existing `SsoAccount` setup, as well as updates to the `ERC1271Handler` to streamline the protocol. This integration leverages zero-knowledge proofs for secure and flexible recovery procedures.

Overall, the addition of OpenID Connect recovery presents a clear path for users to restore access through familiar external identity providers. The creation of `OidcKeyRegistry` for managing OP keys and the `OidcRecoveryValidator` for facilitating zero-knowledge-based proof-of-control effectively extends the account’s resilience. Integrating these components with the existing `WebAuthValidator` ensures a consistent process for validation and eventual recovery.

The Matter Labs team is greatly appreciated for being responsive and cooperative throughout the audit process.