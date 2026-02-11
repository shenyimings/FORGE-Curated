\- May 12, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary  

----------

**Type:** Cross-Chain  
**Timeline:** March 31, 2025 → April 9, 2025  
**Languages:** Solidity

**Findings**Total issues: 5 (3 resolved)  
Critical: 0 (0 resolved) · High: 0 (0 resolved) · Medium: 0 (0 resolved) · Low: 2 (0 resolved)

**Notes & Additional Information**3 notes raised (all resolved)

Scope
-----

OpenZeppelin audited pull requests [#916](https://github.com/across-protocol/contracts/pull/916) and [#926](https://github.com/across-protocol/contracts/pull/926) of the [across-protocol/contracts](https://github.com/across-protocol/contracts) repository. All changes are included in the [march-evm-audit-universal-adapter](https://github.com/across-protocol/contracts/tree/march-evm-audit-universal-adapter) branch at commit [9b58d8e](https://github.com/across-protocol/contracts/commit/9b58d8edd4451cc189f4d01be4db72efd97ddd61).

In scope were the following files:

`contracts
├── chain-adapters
    ├── Universal_Adapter.sol
    ├── Solana_Adapter.sol
    └── utilities
        └── HubPoolStore.sol
├── external
    └── interfaces
        ├── IHelios.sol
├── interfaces
    └── SpokePoolInterface.sol
├── SpokePool.sol
└── Universal_SpokePool.sol` 

Part of the [`SP1Helios.sol`](https://github.com/across-protocol/sp1-helios/blob/8be3aae7622b07ba30d4eee0e9f60823616cb5b3/contracts/src/SP1Helios.sol) contract was also audited due to `Universal_SpokePool` being dependent on it. A full review of `SP1Helios.sol` is included in another audit report.

System Overview
---------------

The Across system acts as a cross-chain transfer accelerator by enabling instant token transfers across various blockchains. This is achieved by incentivizing third-party users, called "relayers", to fill cross-chain transfer requests with their own funds on the destination chain. The relayers are then refunded the filled amount by the system plus a reward for their services. The refund process uses the chain's canonical bridges, so the relayers essentially lend their capital for a certain amount of time.

The `HubPool` contract on the Ethereum mainnet is the heart of the system and its liquidity hub, while a `SpokePool` contract is deployed on each supported L2 chain. `SpokePool` contracts can be both an entry point for transfer requests or a destination point for fills. `HubPool` is able to send messages to any `SpokePool` through the common interface of the Adapter contracts in order to send instructions regarding fund rebalancing among the `SpokePool`s, relayer refunds, or slow execution of fills. Further details about the system functionality can be found in previous reports.

This review considers two kinds of changes in the codebase:

*   Removal of token/route whitelisting from `SpokePool.sol`, included in pull request #926.
*   Addition of `Universal_Adapter` and `Universal_SpokePool`, included in pull request #916.

### Removal of Token/Route Whitelisting

The whitelisting of origin-to-destination token routings has been removed by deleting the relevant check in the `SpokePool` contract's [deposit](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/SpokePool.sol#L1291) function and marking the [`enabledDepositRoutes`](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/SpokePool.sol#L78) mapping as deprecated. As a countermeasure, the responsibility to protect against filling worthless token deposits is transferred to the off-chain components of the system. Essentially, the fills are going to be refunded with a refund token other than the deposited token only if the `PoolRebalanceRoutes` mapping in `HubPool` includes some route for the deposited token. In the opposite case, the relayer will be forced to be refunded with the deposited token and amount on the deposit's origin chain. [`UMIP-179`](https://github.com/UMAprotocol/UMIPs/blob/master/UMIPs/umip-179.md) is going to be updated to formally specify these rules.

### `Universal_Adapter` and `Universal_SpokePool`

So far, any blockchain supported by the Across protocol must have its own Adapter contract deployed on L1 and a `SpokePool` contract deployed on the L2 chain. The Adapter contract is responsible for relaying L1 -> L2 messages or token transfers using the specific L1 infrastructure supporting each L2 chain's communication with L1. These messages allow `HubPool`s to communicate with the `SpokePool`s and usually include `rootBundles` data regarding pool rebalancing, relayer refunds, and slow-fill instructions, along with any message relayed by the `HubPool` contract's owner.

Instead of using an L2 chain's specific infrastructure, `Universal_Adapter` and `Universal_SpokePool` allow for a common interface and cross-chain communication mechanism for EVM L2 chains. In essence, only one `Universal_Adapter` is needed on L1, along with the new [`HubPoolStore`](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/chain-adapters/utilities/HubPoolStore.sol) contract, in order to communicate with any L2 chain supported by a `Universal_SpokePool`.

This is enforced by a combination of the [SP1](https://docs.succinct.xyz/docs/sp1/introduction) zero-knowledge VM (zkVM) and the [Helios](https://helios.a16zcrypto.com/) light client in a single contract, [`SP1Helios`](https://github.com/across-protocol/sp1-helios/blob/8be3aae7622b07ba30d4eee0e9f60823616cb5b3/contracts/src/SP1Helios.sol). Essentially, by running Reth and Revm in SP1, zk proofs for the Ethereum block execution can be generated. Then, on each L2 chain supported by a `Universal_SpokePool`, an `SP1Helios` contract is deployed. `SP1Helios` acts as an L1 light client on the L2 blockchain, where the SP1 block execution proofs can be submitted and verified and, in this manner, [synchronize](https://github.com/across-protocol/sp1-helios/blob/8be3aae7622b07ba30d4eee0e9f60823616cb5b3/contracts/src/SP1Helios.sol#L158) with the L1.

At a high level, the L1 -> L2 communication is achieved by facilitating `Universal_Adapter`, `Sp1Helios`, `HubPoolStore`, and `Universal_SpokePool` as follows. When `HubPool` relays a message to `Univeral_Adapter`, the message data is [stored in a specific storage slot of the `HubPoolStore` contract](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/chain-adapters/Universal_Adapter.sol#L58). `HubPoolStore` is deployed on L1 and is a common storage point for all messages to be relayed to any L2 `Universal_SpokePool`.

In `SP1Helios`, the `Helios` code has been extended so that the `ProofOutputs` also include an array of verifiable storage slot values of L1 contracts. Upon each update action, all the storage slot values included in the proof outputs [are stored in `SP1Helios`](https://github.com/across-protocol/sp1-helios/blob/8be3aae7622b07ba30d4eee0e9f60823616cb5b3/contracts/src/SP1Helios.sol#L211-L217). At the final step, when the `executeMessage` function in `Universal_SpokePool` on the L2 chain is triggered, the validity of the message [is verified](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/Universal_SpokePool.sol#L117-L123) by calling `SP1Helios` and checking the stored data.

According to pull request #916, the system is also compatible with an alternative zero-knowledge setup combining RiscZero with the Helios light client. While a specific implementation of a RiscZero + Helios contract was not reviewed, it is expected to implement the same `IHelios` interface as the `SP1Helios` contract. As a result, `Universal_SpokePool` can remain zkVM-agnostic as long as the underlying light client contract adheres to the expected interface.

Security Model and Trust Assumptions
------------------------------------

This audit was performed under certain trust assumptions regarding the behavior of some privileged roles in the system and of the off-chain components upon which the system depends.

More specifically, since the whitelisting of the origin/destination tokens has been abandoned, it is crucial to ensure that worthless deposited tokens will not be filled with legitimate tokens. The UMA team has informed us that the off-chain fills-related specification will be updated so that the input token is checked against the [`PoolRebalanceRoutes`](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/HubPool.sol#L58) mapping in `HubPool` along with the requested destination chain ID. If it is not mapped to an output token, then the relayer will be forced to be refunded with the deposited token and amount on the deposit's origin chain. We trust that this specification will indeed be enforced until the changes are deployed.

In addition, for the `Universal_SpokePool` contract to function properly, the `SP1Helios` contract, which verifies the storage updated in `HubPoolStore`, should be frequently updated to the most recent L1 state. It is trusted that the `PROPOSER_ROLE` entities, which are responsible for these updates, will perform consistent updates.

Furthermore, it is assumed that the `Universal_SpokePool` contracts will be deployed at distinct addresses across different chains. This assumption is critical for mitigating replay attacks involving admin messages. Since admin messages stored in the `HubPoolStore` contract target a specific address instead of a specific chain, deploying the same contract address on multiple chains would allow a malicious actor to replay an admin message intended for one chain on another. By ensuring that each `Universal_SpokePool` instance is deployed at a unique address per chain, the system avoids this class of vulnerabilities.

### Privileged Roles

There are two privileged roles that are able to trigger critical functionality in chains where the `Universal_SpokePool` is deployed:

*   The owner of the `HubPool` contract is able to make a `rootBundle` execute twice in the `Universal_SpokePool` contract. This is possible due to the special [onlyOwner `relaySpokePoolAdminFunction`](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/HubPool.sol#L249-L252) in the `HubPool` contract in combination with the [distinct nonce counter](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/chain-adapters/utilities/HubPoolStore.sol#L59-L62) used to store admin messages in the `HubPoolStore` contract. In essence, the admin is able to trigger a `rootBundles` execution twice if they relay an execution message that has already been relayed to a `Universal_SpokePool` by a non-owner user through [`HubPool.executeRootBundle`](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/HubPool.sol#L620).
*   The owner of `Universal_SpokePool` is able to [execute sensitive, access-controlled SpokePool operations](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/Universal_SpokePool.sol#L149) in case the `SP1Helios` contract has not been updated for `ADMIN_UPDATE_BUFFER` amount of time or more. This is only supposed to be useful in emergency situations where `SP1Helios` has not been updated for a long time, essentially stalling the `rootBundles` execution. It is trusted that `ADMIN_UPDATE_BUFFER` will be set to a value close to the [`SP1Helios` update threshold](https://github.com/across-protocol/sp1-helios/blob/8be3aae7622b07ba30d4eee0e9f60823616cb5b3/contracts/src/SP1Helios.sol#L167-L168) to restrict the owner's freedom of action as much as possible.

It is trusted that the privileged roles mentioned above will behave in the best interests of the protocol and its users.

Low Severity
------------

### Double Relay of a `rootBundle` Is Possible

The `HubPool` contract is able to send cross-chain messages to any L2 SpokePool through the specified adapter contract for this L2. There are two cases where `HubPool` sends cross-chain messages to one or more L2 SpokePools. First, the `HubPool`'s owner is allowed to [send](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/HubPool.sol#L249-L252) arbitrary messages to SpokePools. Second, any user is allowed to initiate a `rootBundle`'s execution on L2 by [relaying](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/HubPool.sol#L620) the `rootBundle` as a message to a SpokePool. In both cases, the message is [relayed through an adapter contract](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/HubPool.sol#L686-L695).

When the `Universal_Adapter` contract is used to [relay](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/chain-adapters/Universal_Adapter.sol#L44) an L1 -> L2 message, it ensures that the message data is [stored](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/chain-adapters/Universal_Adapter.sol#L58) in `HubPoolStore`. In turn, in `HubPoolStore`, the storage slot in which the relayed data is stored depends on the `msg.sender`. Essentially, the messages relayed by the `HubPool` owner are given a counter [`uuid` as nonce](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/chain-adapters/utilities/HubPoolStore.sol#L60), while the messages relayed by any other user are given [the challenge period end timestamp as nonce](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/chain-adapters/utilities/HubPoolStore.sol#L72).

As a consequence, in a scenario where a `rootBundle`'s execution is triggered on L1 by the `HubPool`'s owner for some specific L2 SpokePool and afterwards the same `rootBundle` is relayed to another L2 SpokePool by a user, then the `rootBundle`'s data are going to be stored twice in `HubPoolStore` in two different slots. This would allow performing the L2 actions included in the `rootBundle` twice for the SpokePool towards where the owner also triggered a message relay.

Consider not allowing storing the same `rootBundle` data in a different storage slot in `HubPoolStore` or clearly documenting the case described above and the trust assumptions regarding the `HubPool` owner.

_**Update:** Acknowledged, not resolved. The team stated:_

> _This is by design. We want the admin to be able to relay a `rootBundle` that already exists on the SpokePool (or will exist in the future)._

### Unverified `SOURCE_CHAIN_ID` in `Universal_SpokePool` Constructor

The [`Universal_SpokePool` contract](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/Universal_SpokePool.sol) integrates with the `SP1Helios` contract for Ethereum beacon chain state updates verification, using SP1 zero-knowledge proofs. The `SP1Helios` contract has an [immutable `SOURCE_CHAIN_ID`](https://github.com/across-protocol/sp1-helios/blob/8be3aae7622b07ba30d4eee0e9f60823616cb5b3/contracts/src/SP1Helios.sol#L30), typically set to `1` for Ethereum. However, this setup potentially allows for the verification of updates from other chains, introducing a possible misconfiguration risk.

The constructor of the `Universal_SpokePool` does not verify the `SOURCE_CHAIN_ID` of the `SP1Helios` contract, assuming its correctness. This lack of verification could lead to the acceptance of updates from an unintended chain, compromising the pool's integrity.

To mitigate this, it is recommended to add a verification step in the `Universal_SpokePool` constructor to ensure the `SP1Helios` contract's `SOURCE_CHAIN_ID` matches the expected chain ID. This will prevent misconfigurations and ensure data integrity by verifying updates from the correct source chain.

_**Update:** Acknowledged, not resolved. The team stated:_

> _Our aim is to have a minimal required interface of the IHelios contract. We might want to swap out this `helios` contract for other implementations which would also need to implement SOURCE\_CHAIN\_ID. Essentially, the admin of the HubPool is responsible to check that the `Universal_SpokePool` is properly configured to use an IHelios contract reading state from the correct source chain. This check should take place before executing any administrative action to `HubPool.setCrossChainContracts` and officially "enable" this spoke pool._

Notes & Additional Information
------------------------------

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Throughout the codebase, there are contracts that do not have a security contact:

*   The [`Universal_Adapter` contract](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/chain-adapters/Universal_Adapter.sol).
*   The [`Universal_SpokePool` contract](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/Universal_SpokePool.sol).

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in [pull request #951](https://github.com/across-protocol/contracts/pull/951)._

### Misleading Documentation

Throughout the codebase, multiple instances of misleading documentation were identified:

*   The [inline documentation](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/Universal_SpokePool.sol#L132-L133) of the `verifiedProofs` mapping could be clarified. While it currently describes the contents of the mapping, it doesn't accurately reflect that the mapping key corresponds to the nonce itself (as opposed to the hash of the nonce), which maps to the hash of the calldata stored in the `HubPoolStore`.
*   The [inline documentation](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/Universal_SpokePool.sol#L54-L56) of the `validateInternalCalls` modifier and `_requireAdminSender` function are referring to a `receiveL1State` function. However, this function does not exist in the codebase and should be replaced by `executeMessage`.

Consider correcting the aforementioned comments to improve the overall clarity and readability of the codebase.

_**Update:** Resolved in [pull request #952](https://github.com/across-protocol/contracts/pull/952)._

### Misleading Variable Names

Across the codebase, several instances of misleading or unclear variable names were identified, which may hinder understanding and introduce confusion during development and review:

*   In the `HubPoolStore` contract on L1, the [`relayMessageCallData` mapping](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/chain-adapters/utilities/HubPoolStore.sol#L23) associates a nonce with the hash of the calldata intended for execution on L2. The [`getStorageSlot` function](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/Universal_SpokePool.sol#L120) is then used to retrieve the value stored in this mapping at a specific block number. However, the variable assigned to the result of `getStorageSlot` is named `slotValueHash`, which may be misleading. The function returns the raw value of the storage slot and not the hash of the slot value, potentially causing confusion. Consider renaming `slotValueHash` to `slotValue` to better reflect its actual content. Additionally, update the documentation to clarify that this value corresponds to the hash of the L2 calldata, as originally stored in the `relayMessageCallData` mapping.
*   In the `Universal_SpokePool` contract, the [`verifiedProofs`](https://github.com/across-protocol/contracts/blob/9b58d8edd4451cc189f4d01be4db72efd97ddd61/contracts/Universal_SpokePool.sol#L35) mapping does not actually store proofs. Instead it maps each nonce to a boolean to indicate whether the calldata linked to this nonce has been executed to prevent replay attacks.

Consider renaming the variables highlighted above to more accurately reflect their purpose and contents, thereby improving code readability and reducing potential misunderstandings.

_**Update:** Resolved in [pull request #952](https://github.com/across-protocol/contracts/pull/952/files)._

Conclusion
----------

The Across protocol continues to evolve as a scalable cross-chain transfer system, enabling fast and secure token transfers across Ethereum and various L2 chains. Relayers fill user-initiated transfers with their own capital and are later reimbursed through canonical bridges, with the `HubPool` contract on Ethereum coordinating liquidity and messaging with the `SpokePool` contracts deployed on destination chains.

This audit reviewed recent updates to the protocol, including the removal of token and route whitelisting, and the introduction of the `Universal_Adapter` and `Universal_SpokePool` contracts. These changes demonstrate a clear push toward generalization and modularity, with support for zkVM-powered cross-chain communication via SP1 or compatible alternatives like RiscZero. This design reflects strong architectural foresight as the protocol aims to expand Across support to additional EVM-based L2s.

The Risk Labs team is appreciated for being responsive and providing detailed context throughout the engagement.