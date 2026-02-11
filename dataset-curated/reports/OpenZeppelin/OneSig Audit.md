\- November 3, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary

**Type:** DeFi / Stablecoin  
**Timeline:** March 24, 2025 → March 28, 2025  
**Languages:** Solidity

**Findings**  
Total issues: 8 (1 resolved)  
Critical: 0 (0 resolved)  
High: 0 (0 resolved)  
Medium: 0 (0 resolved)  
Low: 0 (0 resolved)

**Notes & Additional Information**  
8 notes raised (1 resolved)

Scope
-----

We audited the [Everdawn-Labs/OneSig](https://github.com/Everdawn-Labs/OneSig/) repository at commit [5ec9d07](https://github.com/Everdawn-Labs/OneSig/commit/5ec9d07d2a92214af5d1f7c6b6110ea9d4218038).

In scope were the following files:

`packages/onesig-evm/contracts/MultiSig.sol
packages/onesig-evm/contracts/OneSig.sol` 

System Overview
---------------

The OneSig is a smart contract system designed to facilitate secure, cross-chain execution of pre-authorized transactions. It enables a group of signers to collectively approve a batch of transactions off-chain, which are then represented on-chain as a Merkle root. Once the batch is signed, any user can execute individual transactions without additional permissions, as long as a valid Merkle proof and sufficient signatures are provided.

Each transaction batch is uniquely identified by a nonce and a deployment-specific identifier, ensuring ordered execution and preventing replay. This design aims to improve scalability and reduce operational complexity for multi-chain deployments, especially in environments like LayerZero where frequent configuration updates across numerous chains are necessary.

Security Model and Trust Assumptions
------------------------------------

This audit only covers the on-chain components of the OneSig system. The off-chain infrastructure responsible for generating Merkle trees was not included in the scope. As such, we assume that this off-chain system correctly implements the double-hashing and encoding process defined in the `encodeLeaf` function of the contract.

We also assume that all signers configured in the `OneSig` contract are trustworthy entities, and that the `threshold` value is set responsibly — i.e., not too low relative to the number of signers, in accordance with best practices for multisig systems.

Additionally, both OpenZeppelin and Everdawn are aware that the system allows for signature reuse across different chains due to the use of a static EIP-712 domain. Based on the protocol's documentation and stated design goals, we assume that this cross-chain signature reusability is intentional and not considered a security risk by the project team.

### Privileged Roles

The privileged actors in the system are the designated multisig signers. They are responsible for authorizing transaction batches by signing Merkle roots off-chain. Through the contract's internal logic, these signers can also collectively update the signer set and the contract’s seed value, which plays a role in signature validity. All such actions require the same threshold of signatures used for transaction execution.

Notes & Additional Information
------------------------------

### Redundant Version String in `DOMAIN_SEPARATOR`

The `OneSig` contract defines the `"0.0.1"` version string manually when constructing the [`DOMAIN_SEPARATOR`](https://github.com/Everdawn-Labs/OneSig/blob/main/packages/onesig-evm/contracts/OneSig.sol#L50), despite already declaring it as a constant ([`VERSION`](https://github.com/Everdawn-Labs/OneSig/blob/main/packages/onesig-evm/contracts/OneSig.sol#L19)). This results in redundancy and may lead to inconsistencies if the version is updated in one place and not the other.

Consider using the existing `VERSION` constant in the construction of the `DOMAIN_SEPARATOR` instead of hardcoding the version string again. This improves maintainability and reduces the risk of version mismatches during future upgrades or audits.

_**Update:** Acknowledged, not resolved._

### Missing Docstrings

Within `OneSig.sol`, in the [`LEAF_ENCODING_VERSION` state variable](https://github.com/Everdawn-Labs/OneSig/blob/5ec9d07d2a92214af5d1f7c6b6110ea9d4218038/packages/onesig-evm/contracts/OneSig.sol#L21), the docstring is missing.

Consider thoroughly documenting all functions (and their parameters) that are part of any contract's public API. Functions implementing sensitive functionality, even if not public, should be clearly documented as well. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Acknowledged, not resolved._

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Acknowledged, not resolved._

### Function Visibility Overly Permissive

Throughout the codebase, multiple instances of functions with unnecessarily permissive visibility were identified:

*   The [`getSigners`](https://github.com/Everdawn-Labs/OneSig/blob/5ec9d07d2a92214af5d1f7c6b6110ea9d4218038/packages/onesig-evm/contracts/MultiSig.sol#L203) function in `MultiSig.sol` with `public` visibility could be limited to `external`.
    
*   The [`setSeed`](https://github.com/Everdawn-Labs/OneSig/blob/5ec9d07d2a92214af5d1f7c6b6110ea9d4218038/packages/onesig-evm/contracts/OneSig.sol#L151) function in `OneSig.sol` with `public` visibility could be limited to `external`.
    
*   The [`executeTransaction`](https://github.com/Everdawn-Labs/OneSig/blob/5ec9d07d2a92214af5d1f7c6b6110ea9d4218038/packages/onesig-evm/contracts/OneSig.sol#L165) function in `OneSig.sol` with `public` visibility could be limited to `external`.
    

To better convey the intended use of functions and to potentially realize some additional gas savings, consider changing a function's visibility to be only as permissive as required.

_**Update:** Resolved. The Everdawn Labs team stated:_

> _Intended implementation. This way, it allows for additional functions with inheritance by implementers._

### Floating Pragma

Pragma directives should be fixed to clearly identify the Solidity version with which the contracts will be compiled.

`MultiSig.sol` and `OneSig.sol` have the [`solidity ^0.8.22`](https://github.com/Everdawn-Labs/OneSig/blob/5ec9d07d2a92214af5d1f7c6b6110ea9d4218038/packages/onesig-evm/contracts/MultiSig.sol#L3) floating pragma directive.

Consider using fixed pragma directives.

_**Update:** Acknowledged, not resolved._

### Lack of Indexed Event Parameters

Throughout the codebase, multiple instances of events not having any indexed parameters were identified:

*   The [`SignerSet` event](https://github.com/Everdawn-Labs/OneSig/blob/5ec9d07d2a92214af5d1f7c6b6110ea9d4218038/packages/onesig-evm/contracts/MultiSig.sol#L60) in `MultiSig.sol`
    
*   The [`ThresholdSet` event](https://github.com/Everdawn-Labs/OneSig/blob/5ec9d07d2a92214af5d1f7c6b6110ea9d4218038/packages/onesig-evm/contracts/MultiSig.sol#L66) in `MultiSig.sol`
    
*   The [`SeedSet` event](https://github.com/Everdawn-Labs/OneSig/blob/5ec9d07d2a92214af5d1f7c6b6110ea9d4218038/packages/onesig-evm/contracts/OneSig.sol#L81) in `OneSig.sol`
    
*   The [`TransactionExecuted` event](https://github.com/Everdawn-Labs/OneSig/blob/5ec9d07d2a92214af5d1f7c6b6110ea9d4218038/packages/onesig-evm/contracts/OneSig.sol#L86) in `OneSig.sol`
    

To improve the ability of off-chain services to search and filter for specific events, consider [indexing event parameters](https://solidity.readthedocs.io/en/latest/contracts.html#events).

_**Update:** Acknowledged, not resolved._

### `verifyNSignatures` Strictly Requires Exact Threshold Signatures

The [`verifyNSignatures`](https://github.com/Everdawn-Labs/OneSig/blob/5ec9d07d2a92214af5d1f7c6b6110ea9d4218038/packages/onesig-evm/contracts/MultiSig.sol#L177) function [requires](https://github.com/Everdawn-Labs/OneSig/blob/5ec9d07d2a92214af5d1f7c6b6110ea9d4218038/packages/onesig-evm/contracts/MultiSig.sol#L180) the number of provided signatures to be exactly equal to `threshold`, rejecting any input with more than the required number of signatures. This design limits flexibility and may cause execution failures in practical scenarios where extra valid signatures are included (e.g., by automated signers or off-chain tooling). It also diverges from widely adopted multisig patterns, such as Gnosis Safe, which accept any number of valid signatures greater than or equal to the threshold.

Consider relaxing the check to allow the number of signatures to be greater than or equal to the threshold. This improves compatibility with common multisig practices and reduces the chances of transaction rejections due to harmless over-signing.

_**Update:** Acknowledged, not resolved. The Everdawn Labs team stated:_

> _This should be a note at best, it does not affect security_

### EVM Version May Lead to Cross-Chain Deployment Issues

The project does not specify `evmVersion` in the Foundry or Hardhat configuration files. As a result, the contracts are compiled using the default EVM version associated with the compiler (likely `cancun` in newer Solidity versions like `^0.8.22`). This may introduce incompatibilities when deploying to blockchains that do not yet support newer opcodes such as [`PUSH0`](https://eips.ethereum.org/EIPS/eip-3855) or [`MCOPY`](https://eips.ethereum.org/EIPS/eip-5656), which were introduced in the Shanghai and Cancun upgrades respectively.

Deploying contracts that include unsupported opcodes on older EVM versions can lead to deployment failures or unexpected behavior on chains that haven't yet adopted these upgrades.

Consider explicitly setting `evmVersion` to `"paris"` (the last widely supported EVM version prior to newer opcodes being introduced) in both Foundry and Hardhat configurations. This ensures broader compatibility with a wide range of mainnets and L2s, many of which may not yet support the latest EVM opcodes. In addition, consider verifying the final bytecode produced during compilation to ensure that unsupported opcodes like `PUSH0` and `MCOPY` are not present.

_**Update:** Acknowledged, not resolved. The Everdawn Labs team stated:_

> _No change._

Conclusion
----------

The `MutiSig` contract requires a threshold of signatures from approved signers before executing a transaction. The `OneSig` contract allows a single signature set to be re-used across multiple chains by using a fixed domain separator and verifying the contract address. The codebase was found to be clean and well-written, with the audit only yielding note-severity issues along with various recommendations for code improvement.