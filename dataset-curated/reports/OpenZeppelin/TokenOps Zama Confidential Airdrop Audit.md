\- January 6, 2026

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

**Summary**

**Type:** Cryptography  
**Timeline:** From 2025-12-08 → To 2025-12-17  
**Languages:** Solidity

**Findings**  
Total issues: 8 (7 resolved)  
Critical: 0 (0 resolved) · High: 0 (0 resolved) · Medium: 1 (1 resolved) · Low: 4 (3 resolved)

**Notes & Additional Information**  
3 notes raised (3 resolved)

Scope
-----

OpenZeppelin audited the [VestingLabs/tokenops-fhe-airdrop](https://github.com/VestingLabs/tokenops-fhe-airdrop) repository at commit [275139f](https://github.com/VestingLabs/tokenops-fhe-airdrop/tree/275139f994bfd4d5269a93598112974b11dd3a6a).

In scope were the following files:

`contracts/
├── deployer/CREATE3Deployer.sol
├── factory/ConfidentialAirdropFactory.sol 
├── interfaces/
│   ├── IConfidentialAirdropCloneable.sol 
│   └── IConfidentialAirdropFactory.sol
└── ConfidentialAirdropCloneable.sol` 

System Overview
---------------

The system of smart contracts under review has been designed to enable a confidential airdrop. In this context "confidential" means that the token amounts being transferred to each airdrop participant are hidden, but the recipient addresses are not. This is a property of the underlying asset, which is an ERC-7984 Confidential Token. Each airdrop will handle the distribution of one confidential token.

The confidential airdrop is an instance of `ConfidentialAirdropCloneable.sol`, implemented as a proxy. This contract has functions that process off-chain signatures of `{recipient, encrypted amount}` pairs. If the signatures are valid and came from a holder of the `DEFAULT_ADMIN_ROLE`, they will be processed one time and the encrypted amount of tokens will be disbursed to the recipient. This may happen until the end of the claim window, which may be optionally extended by the `DEFAULT_ADMIN_ROLE`. Optionally, a "gas fee" can be charged, which is paid in the native token by the recipient upon claiming their token disbursement.

The `DEFAULT_ADMIN_ROLE` of the confidential airdrop may set the gas fee before its deployment. They may also change whether the airdrop is "paused" or not, which prevents the claiming of tokens. They can extend the claiming window as well, allowing users more time to claim their airdropped assets. They may withdraw any tokens which are not the airdrop tokens in order to claim any accidentally-sent assets to the contract. Finally, at any time, they may `withdraw` all airdrop tokens to an admin-specified address.

The `FEE_COLLECTOR_ROLE` is able to collect "gas fees" which are optionally used by the airdrop contract, and has no other powers. It is fully separated from the `DEFAULT_ADMIN_ROLE`.

The `ConfidentialAirdropFactory` contract enables deployment of the `ConfidentialAirdropCloneable` contract, and controls various parameters assigned at deployment, such as the gas fee and fee collector. The `ConfidentialAirdropFactory` contract provides many helper functions for deploying a confidential airdrop, such as functions for deploying the airdrop with or without funding it automatically, and address-prediction functions.

The system enables the deployment of the `ConfidentialAirdropFactory` contract via CREATE3. [CREATE3 is a library from Solady](https://github.com/Vectorized/solady/blob/main/src/utils/CREATE3.sol). It leverages proxies, the CREATE opcode, and the CREATE2 opcode to create arbitrary contracts at predictable addresses. Within the context of this system, CREATE3 enables an entity to deploy the same airdrop contract at the same address on multiple chains.

### Solady Dependencies

This system is built on top of Solady libraries for deploying clones, specifically [`LibClone.sol`](https://github.com/Vectorized/solady/blob/main/src/utils/LibClone.sol) and [`CREATE3.sol`](https://github.com/Vectorized/solady/blob/main/src/utils/CREATE3.sol). As these libraries are out-of-scope for this audit, they are assumed to work as documented.

Security Model and Trust Assumptions
------------------------------------

This system is designed exclusively for the Zama protocol airdrop. So, it can be assumed that special use cases will not need accommodation. Throughout this audit, the general-purpose extensibility of the audited contracts is not considered. For example, it is assumed that the signer will be a single EOA. Thus, it is assumed that there will be no need for smart-account or contract signature verification such as ERC-1271.

The admin of individual confidential airdrops is trusted not to withdraw all funds from the airdrop except in extenuating circumstances like an emergency or after the claim window has ended.

The admin of a confidential airdrop is also trusted to only interact with "safe" tokens via the `withdrawOtherToken` and `withdrawOtherConfidentialToken` functions. The admin will interact only with sufficiently popular, known token contracts, based on OpenZeppelin or similar standard contracts, with no modifications. The admin is trusted not to interact with any suspicious, low-use, or non-standard-behavior tokens.

Admins are trusted to properly fund any confidential airdrops with sufficient tokens for all recipients, and to not sign disbursements that total more than the original confidential token balance of the airdrop. If more disbursements are signed than tokens available, race conditions may be created, and transfers will silently fail, consuming signatures without sending users tokens.

Finally, admins are trusted to only release signatures to users after funding the airdrop contract. In the event that signatures are used before contract funding, transfers will silently fail while consuming signatures. The "start time" parameter should be used to allow sufficient time for funding the contract before users can begin claiming.

The `CREATE3Deployer` is assumed to be used only for deploying the `ConfidentialAirdropFactory` contract via the `deploy` function. It is assumed that the `deployWithValue` function is unused within the context of this system.

### Privileged Roles

Throughout the in-scope codebase, multiple privileged actions and roles were identified:

#### `ConfidentialAirdropCloneable.sol`

*   `FEE_COLLECTOR_ROLE`: This is the admin of its own role, meaning it can set new `FEE_COLLECTOR_ROLE` holders. This role can withdraw the gas fees that are paid by claimers when claiming tokens.
*   `DEFAULT_ADMIN_ROLE`: This role is responsible for signing messages for airdrop claims. These signatures include the recipient and amount of airdropped tokens to claim. This role can withdraw the entire encrypted balance of the airdrop contract at any time. They are trusted not to do this except in the case of emergencies. This role can pause/unpause the airdrop contract, preventing airdrop claims. This can grant its own role, meaning it can set new `DEFAULT_ADMIN_ROLE` holders. This role can extend the claim window if `CAN_EXTEND_CLAIM_WINDOW` is set to `true` upon airdrop deployment. This role can withdraw accidentally-sent "other" tokens, both confidential and not to an external address.

#### `ConfidentialAirdropFactory.sol`

*   `FEE_MANAGER_ROLE`: This role can set the `feeCollector`, which is a single address that is assigned the `FEE_COLLECTOR_ROLE` within the context of `ConfidentialAirdropCloneable` upon its creation. This role can also set the "default gas fee", which is used when creating a new instance of `ConfidentialAirdropCloneable`. This role can set or delete the "custom fee" for a user, which will be used in place of the "default gas fee" if it is "enabled" when a `ConfidentialAirdropCloneable` instance is deployed.
*   `DEFAULT_ADMIN_ROLE`: This role can assign the `DEFAULT_ADMIN_ROLE` or the `FEE_MANAGER_ROLE` to new addresses within the context of the `ConfidentialAirdropCloneable` contract.
*   `feeCollector`: This role is not a role managed by the `AccessControl` module. This is because it is set up to only be a single address. Whenever a new instance of `ConfidentialAirdropCloneable` is created, this address will be assigned the `FEE_COLLECTOR_ROLE`.

#### `CREATE3Deployer.sol`

*   `DEPLOYER_ROLE`: This role is able to call the `deploy` and `deployWithValue` functions, which deploy a contract via CREATE3 and optionally transfer native tokens to it.
*   `DEFAULT_ADMIN_ROLE`: This role is able to assign the `DEPLOYER_ROLE` and the `DEFAULT_ADMIN_ROLE` within the `CREATE3Deployer` contract.

### Privacy Guarantees

This system is designed to be "confidential" via Zama's fhEVM architecture. Specifically, this means that the amounts sent to the airdrop and amounts sent to each user will be hidden from the public.

This design does not hide the fact that certain addresses have received airdrops or the creation of the airdrop contract. All confidential token transfers to/from the airdrop will emit events including the sender and recipient.

Medium Severity
---------------

### `withdrawOtherConfidentialToken` Function Can Leak fhEVM Allowance

The `withdrawOtherConfidentialToken` function uses an `allowTransient` call to ensure that some external, confidential token has the ability to transfer out some encrypted amount. However, this encrypted value is [provided by the confidential token in question, via the `confidentialBalanceOf` call](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L461). In practice, this means that some external confidential token contract may be able to provide a handle which it does not have access to, and gain access to it via this call. Even with transient access, the external contract may gain access to an encrypted value, either via copying the handle (e.g., by using `FHE.add(encryptedBalance, 0)`) or by calling `FHE.allowThis(encryptedBalance)`.

Note that for a well-behaved token following the OpenZeppelin Confidential Contracts ERC-7984 template, the only way for an address to obtain tokens is through a confidential transfer or a mint. Both the [`_transfer` path](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/blob/f0914b66f9f3766915403587b1ef1432d53054d3/contracts/token/ERC7984/ERC7984.sol#L252-L256) and the [`_mint` path](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/blob/f0914b66f9f3766915403587b1ef1432d53054d3/contracts/token/ERC7984/ERC7984.sol#L242-L245) utilize [`_update`](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/blob/f0914b66f9f3766915403587b1ef1432d53054d3/contracts/token/ERC7984/ERC7984.sol#L275), which will provide [the recipient (in this case, the Confidential Airdrop Clone) access to the balance handle](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/blob/f0914b66f9f3766915403587b1ef1432d53054d3/contracts/token/ERC7984/ERC7984.sol#L301). So, it can be reasonably assumed that the token contract will not need authorization of this handle, as it should already have it.

Consider removing the [`allowTransient` call in line 469 of `ConfidentialAirdropCloneable.sol`](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L469). Note that for a malicious contract to gain access to a handle they should not have, it will require [`DEFAULT_ADMIN_ROLE` to call the `withdrawOtherConfidentialToken` function](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L456). Consider also checking the handles returned by confidential token contracts for `confidentialBalanceOf`, and ensuring that they do not match handles associated with confidential airdrop amounts.

_**Update:** Resolved in [pull request #16](https://github.com/VestingLabs/tokenops-fhe-airdrop/pull/16) at commit [56bcffe](https://github.com/VestingLabs/tokenops-fhe-airdrop/commit/56bcffe5c29e35ead0d36a113052ac802801f75d). The Zama team stated:_

> _We have removed the `FHE.allowTransient()` call and have added NatSpec documentation stating that this function only works with standard ERC-7984 implementations. Regarding the additional recommendation to check handles: we have decided not to implement it as it would only apply to non-standard confidential tokens, which is documented in the NatSpec._

Low Severity
------------

### Claim Time Can Be Extended After Airdrop End

The [`extendClaimWindow` function](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L392) can be called at any time, including after a claim window has ended. Logically, this does not make sense and may confuse users. This also may be used to claim tokens by a malicious admin in the distant future, long after an airdrop has ended.

Consider making the [`isClaimWindowActive()` function](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L408) `public`, then implementing an `isClaimWindowActive()` check within `extendClaimWindow` to disallow re-opening claim windows that have already ended. Alternatively, consider only allowing the claim window to be extended in a constant period after the airdrop end (e.g., within 3 days after the airdrop end).

_**Update:** Acknowledged, not resolved. The Zama team stated:_

> _We have decided to not fix this. We intentionally allow the admin to extend the claim window after it has ended. This provides operational flexibility for scenarios where users need additional time to claim. The admin is a trusted role with full control over the airdrop._

### `togglePause` Function May Be Insecure

The [`togglePause` function](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L383) is callable by holders of the `DEFAULT_ADMIN_ROLE`. The function [sets `isPaused` to its current opposite](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L384). In the event that there is an emergency that requires the airdrop to be paused, and there are at least two holders of the `DEFAULT_ADMIN_ROLE`, there could be two potential downsides of this design.

First, both admins may detect that a pause is needed, and both call `togglePause` at roughly the same time, causing the airdrop to be quickly paused and then unpaused. Second, the admins may alternatively notice that a pause is needed, after which they will need to coordinate who is designated to pause the contract. This may waste valuable time in an emergency situation.

Consider changing the `togglePause` function to include a `bool toPause` input parameter. This will allow either admin to react quickly, and will not nullify the effect if a second call is made to pause the contract.

_**Update:** Resolved in [pull request #14](https://github.com/VestingLabs/tokenops-fhe-airdrop/pull/14) at commit [9b9764a](https://github.com/VestingLabs/tokenops-fhe-airdrop/commit/9b9764a70f4fd063e74d3426ac9f4a51c5bfb5a8). The Zama team stated:_

> _We have replaced the `togglePause()` function with the `setPaused(bool paused)` function so that multiple admins can safely call `setPaused(true)` without accidentally unpausing. This eliminates race conditions and the need for coordination between admins during emergencies._

### Duplicate and Similar Code

Within `ConfidentialAirdropCloneable`, the [`claim`](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L206), [`getClaimAmount`](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L266), and [`isSignatureValid`](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L310) functions all follow very similar flows.

Each function does the following:

1.  Checks the [`isPaused` value](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L312)
2.  Checks that the [claim window is open](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L314-L316)
3.  [Computes a `structHash` and checks if it has been claimed](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L318-L324)
4.  [Computes the `digest` and recovers the `signer`](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L327-L328)
5.  [Verifies that the signer has the `DEFAULT_ADMIN_ROLE`](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L330-L331)

Since this code is repeated nearly identically 3 times, consider instead encapsulating it in an `internal` function or functions. This will make the contract more succinct and ensure that logic remains consistent between functions and after updates. Consider creating two separate functions, one which checks the paused status, claim window, and then returns whether the signature has been claimed, and one function which returns whether the `DEFAULT_ADMIN_ROLE` was the validated signer of the message. This will allow for the subtle differences between the various `external` functions while still permitting code re-use. Consider also making the [`isClaimWindowActive` function](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L408) `public` and leveraging it to replace the [checks on the pause state and claim window duration](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L272-L276).

_**Update:** Resolved in [pull request #15](https://github.com/VestingLabs/tokenops-fhe-airdrop/pull/15) at commit [8dd8af9](https://github.com/VestingLabs/tokenops-fhe-airdrop/commit/8dd8af92e517bd5768bf1b9ed28f720c1bc728cd). The Zama team stated:_

> _We have extracted the shared logic into reusable internal functions: `_requireClaimWindowActive()`, `_computeStructHash()`, and `_isValidAdminSignature()`. We have also changed `isClaimWindowActive()` from `external` to `public` to allow internal reuse._

### `deploymentBlockNumber` Variable Inconsistent on Arbitrum One Chain

The `initialize` function in the `ConfidentialAirdropCloneable` contract [sets `deploymentBlockNumber` to the current block number](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L82), which is intended to store the deployment block number of the airdrop contract.

However, on the [Arbitrum One chain](https://docs.arbitrum.io/build-decentralized-apps/arbitrum-vs-ethereum/block-numbers-and-time#ethereum-or-parent-chain-block-numbers-within-arbitrum), `block.number` returns _a value close to (but not necessarily exactly) the block number of the first non-Arbitrum ancestor chain (Ethereum Mainnet) at which the sequencer received the transaction._ This behavior can lead to confusion during off-chain analysis when interpreting the `deploymentBlockNumber`.

Arbitrum One provides a [precompile contract](https://docs.arbitrum.io/build-decentralized-apps/arbitrum-vs-ethereum/block-numbers-and-time#arbitrum-block-numbers) that exposes the `arbBlockNumber()` function to retrieve Arbitrum’s native block number. Consider checking the `chainId` for Arbitrum One chain and using the `arbBlockNumber()` system call to fetch the block number instead.

_**Update:** Resolved in [pull request #20](https://github.com/VestingLabs/tokenops-fhe-airdrop/pull/20) at commit [014cffb](https://github.com/VestingLabs/tokenops-fhe-airdrop/commit/014cffb1e55000a046eeaa93c0871d1d1442d84a). The Zama team stated:_

> _We have added the `_getBlockNumberish()` helper following Uniswap's BlockNumberish pattern. On Arbitrum (chain ID 42161), we use ArbSys precompile's `arbBlockNumber()` instead of `block.number`. We have also added an interface and tests._

Notes & Additional Information
------------------------------

### `withdrawGasFee` Function Uses `ZeroBalance()` for Two Different Conditions

In `ConfidentialAirdropCloneable`, the [`withdrawGasFee(address recipient, uint256 amount)` function](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L360) allows an address with `FEE_COLLECTOR_ROLE` to withdraw collected native ETH fees. The function reuses the `ZeroBalance()` error for both [`balance == 0`](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L364) and [`withdrawAmount > balance`](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L372). While the former is correct, the latter conflates “no balance available” with “requested amount exceeds available balance.” This mislabeling can mislead off-chain monitoring and tests that distinguish between an empty contract and an excessive withdrawal request (e.g., when `balance = 1 ether` and `amount = 2 ether`, which currently reverts with `ZeroBalance()`).

Consider introducing and using a distinct custom error such as `InsufficientBalance()` (or `AmountExceedsBalance()`) for the `withdrawAmount > balance` branch, keeping `ZeroBalance()` exclusively for `balance == 0`. In addition, consider updating tests, monitoring processes, and operator playbooks to react appropriately to the new revert reason.

_**Update:** Resolved in [pull request #17](https://github.com/VestingLabs/tokenops-fhe-airdrop/pull/17) at commit [6737727](https://github.com/VestingLabs/tokenops-fhe-airdrop/commit/6737727adb81f57bacb9eb9a184cbc4569114929). The Zama team stated:_

> _We have added a distinct `InsufficientBalance` error for when `withdrawAmount > balance`, keeping `ZeroBalance` error for when `balance == 0`. We have also updated the corresponding test expectation._

### Missing Security Contact

Providing a specific security contact (such as an email address or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Throughout the codebase, multiple instances of contracts not having a security contact were identified:

*   The [`ConfidentialAirdropCloneable` contract](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol)
*   The [`CREATE3Deployer` contract](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/deployer/CREATE3Deployer.sol)
*   The [`ConfidentialAirdropFactory` contract](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/factory/ConfidentialAirdropFactory.sol)
*   The [`IConfidentialAirdropCloneable` interface](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/interfaces/IConfidentialAirdropCloneable.sol)
*   The [`IConfidentialAirdropFactory` interface](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/interfaces/IConfidentialAirdropFactory.sol)

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in [pull request #18](https://github.com/VestingLabs/tokenops-fhe-airdrop/pull/18) at commit [a44bf6f](https://github.com/VestingLabs/tokenops-fhe-airdrop/commit/a44bf6f1af5aa383ea47a23346586ce70e6acf7b). The Zama team stated:_

> _We have added `@custom:security-contact security@zama.ai` to all contracts and interfaces following the OpenZeppelin Wizard convention._

The `ConfidentialAirdropCloneable` contract relies on EIP-712 typed data signatures for authorization in `claim`, `getClaimAmount`, and `isSignatureValid`, computing the struct hash with the on-chain `CLAIM_TYPEHASH`. The deployed `CLAIM_TYPEHASH` is derived from the canonical string `Claim(address recipient,bytes32 encryptedAmount)` (no space after the comma), and signatures are validated via `_hashTypedDataV4` and `recover`.

However, the NatSpec comment for the [`claim` function documents](https://github.com/VestingLabs/tokenops-fhe-airdrop/blob/275139f994bfd4d5269a93598112974b11dd3a6a/contracts/ConfidentialAirdropCloneable.sol#L36) the type as `Claim(address recipient, bytes32 encryptedAmount)` (with a space). Since EIP-712 type hashes are whitespace-sensitive, off-chain implementations that follow the documented string compute a different type hash, resulting in a different `structHash` and `digest`.

Consider updating the NatSpec comment to exactly mention `Claim(address recipient,bytes32 encryptedAmount)`.

_**Update:** Resolved in [pull request #19](https://github.com/VestingLabs/tokenops-fhe-airdrop/pull/18) at commit [04e2d09](https://github.com/VestingLabs/tokenops-fhe-airdrop/commit/04e2d0998cd7bd13c439fe959e6bc68eaf8daf5c). The Zama team stated:_

> _We have updated the NatSpec comment to match the actual `CLAIM_TYPEHASH` definition without a space after the comma._

Conclusion
----------

The codebase under review comprises a new confidential airdrop contract that distributes tokens to users without revealing the amount of tokens on-chain using ZAMA's Fully Homomorphic Encryption (FHE). These confidential airdrop contracts are proxy contracts deployed via a factory using the LibClone library. The factory contract will be deployed on multiple chains using `CREATE3Deployer`.

The audit yielded one medium-severity issue involving the leakage of the confidential airdrop amount. In addition, several low- and note-level issues were reported to improve the codebase quality. Overall, the codebase was found to be comprehensively documented and sufficiently tested.

The TokenOps Team is appreciated for their excellent responsiveness and collaboration. Their strong communication significantly facilitated the review process and helped resolve issues efficiently.

Appendix
--------

### Issue Classification

OpenZeppelin classifies smart contract vulnerabilities on a 5-level scale:

*   Critical
*   High
*   Medium
*   Low
*   Note/Information

#### **Critical Severity**

This classification is applied when the issue’s impact is catastrophic, threatening extensive damage to the client's reputation and/or causing severe financial loss to the client or users. The likelihood of exploitation can be high, warranting a swift response. Critical issues typically involve significant risks such as the permanent loss or locking of a large volume of users' sensitive assets or the failure of core system functionalities without viable mitigations. These issues demand immediate attention due to their potential to compromise system integrity or user trust significantly.

#### **High Severity**

These issues are characterized by the potential to substantially impact the client’s reputation and/or result in considerable financial losses. The likelihood of exploitation is significant, warranting a swift response. Such issues might include temporary loss or locking of a significant number of users' sensitive assets or disruptions to critical system functionalities, albeit with potential, yet limited, mitigations available. The emphasis is on the significant but not always catastrophic effects on system operation or asset security, necessitating prompt and effective remediation.

#### **Medium Severity**

Issues classified as being of medium severity can lead to a noticeable negative impact on the client's reputation and/or moderate financial losses. Such issues, if left unattended, have a moderate likelihood of being exploited or may cause unwanted side effects in the system. These issues are typically confined to a smaller subset of users' sensitive assets or might involve deviations from the specified system design that, while not directly financial in nature, compromise system integrity or user experience. The focus here is on issues that pose a real but contained risk, warranting timely attention to prevent escalation.

#### **Low Severity**

Low-severity issues are those that have a low impact on the client's operations and/or reputation. These issues may represent minor risks or inefficiencies to the client's specific business model. They are identified as areas for improvement that, while not urgent, could enhance the security and quality of the codebase if addressed.

#### **Notes & Additional Information Severity**

This category is reserved for issues that, despite having a minimal impact, are still important to resolve. Addressing these issues contributes to the overall security posture and code quality improvement but does not require immediate action. It reflects a commitment to maintaining high standards and continuous improvement, even in areas that do not pose immediate risks.