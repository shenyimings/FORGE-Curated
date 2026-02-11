\- February 5, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

Type

Token

Timeline

From 2024-03-11

To 2024-03-22

Languages

Solidity

Total Issues

13 (10 resolved, 1 partially resolved)

Critical Severity Issues

0 (0 resolved)

High Severity Issues

0 (0 resolved)

Medium Severity Issues

0 (0 resolved)

Low Severity Issues

6 (6 resolved)

Notes & Additional Information

7 (4 resolved, 1 partially resolved)

Scope
-----

We audited the [zksync-association/zk-governance](https://github.com/zksync-association/zk-governance) repository at commit [08ec4e7](https://github.com/zksync-association/zk-governance/tree/08ec4e7548c83572e6f09c8344f6e3390bb1b27a).

In scope were the following files:

`src
├── ZkCappedMinter.sol
├── ZkMerkleDistributor.sol
└── ZkTokenV1.sol` 

Note that some issues might refer to the [f37e3dc](https://github.com/zksync-association/zk-governance/tree/f37e3dcdb99600e73a13851d066b10f86e3c6427) commit which was the audit's early commit until the final one was delivered.

System Overview
---------------

The [`ZkTokenV1`](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkTokenV1.sol) contract is the core of the system and is going to be the governance token of ZKsync Era. It is an ERC-20 token with permit functionality which incorporates a voting delegation system so that token holders can delegate their voting power to a trusted representative while preserving the actual token value. In order to activate their voting power, each token holder must set a delegatee even if they are delegating to their own account address. Upon a token transfer, the corresponding voting power is also automatically transferred from and to the corresponding delegatees, respectively.

The token contract is a transparent upgradeable proxy and also has an access control mechanism. The default admin role is allowed to create other access roles, assign or revoke these roles, and also set a separate and dedicated admin role for each role. By default, all defined roles are managed by the default admin role.

In order to bootstrap the token's circulation, a specific amount of tokens will be minted and distributed among Matter Labs, the Foundation, and the Association, with an airdrop taking place as well. The token distribution involves two more contracts, namely [`ZkCappedMinter`](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkCappedMinter.sol) and [`ZkMerkleDistributor`](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol). These contracts are going to be assigned the `MINTER` role in the access control system of `ZkTokenV1` and will control the token minting among the beneficiaries.

More specifically, two instances of the `ZkCappedMinter` contract will be deployed: one for the Foundation and another for the Association. `ZkCappedMinter` defines an immutable admin and an immutable cap value. The admin is able to mint tokens to any address at any frequency, up to the token mint cap.

The `ZkMerkleDistributor` contract will be used to control token distribution among the beneficiaries of the public airdrop. An [immutable Merkle root](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol#L45) value will be set upon the contract's deployment, committing to all information about the qualifying addresses and amounts. Users will be allowed to claim their airdropped tokens [within a specific time window](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol#L201). In order to claim successfully, users should provide a valid Merkle proof and a delegatee account address. When the specified claiming period is over, the contract admin [is allowed to sweep](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol#L180) any airdrop amount left unclaimed and transfer it to an address of their preference.

Security Model and Trust Assumptions
------------------------------------

The system's security ultimately relies on the honest behavior of the initial admin of `ZkTokenV1`. Upon the contract's initialization, [the admin is granted](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkTokenV1.sol#L45-L47) the `DEFAULT_ADMIN_ROLE`, the `MINTER_ADMIN_ROLE`, and the `BURNER_ADMIN_ROLE` roles, along with the ownership of the proxy. As a consequence, the admin is allowed to grant or revoke token minting and burning rights to any address. The admin also can upgrade the token by changing the implementation address.

The ZKsync Association team clarified that the initial admin will be the Association's 4-out-of-7 multisig with a security precaution of having one key per person, with each key being a hardware key and not being used for any other purpose. According to the plan, once the governance system has been successfully bootstrapped and the proposals procedure is functional, all three admin roles will be handed over to a governance contract and the Association will subsequently lose all three roles. During the audit, we considered that the Association will act honestly and in accordance with the interests of the community until the admin roles are handed over to the governance.

Regarding the distribution of the token's supply, [an initial amount of funds](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkTokenV1.sol#L50) will be minted upon contract initialization for Matter Labs. There will be two instances of the `ZkCappedMinter` contract, one with the Association being the admin and the other with the Foundation being the admin. The `ZkCappedMinter` contract will control the minting for these two entities, allowing them to mint up to a defined cap amount at the frequency and the recipient(s) of their preference. The airdrop distribution will be fully controlled by the `ZkMerkleDistributor` contract, where an immutable Merkle root will be the only source of truth regarding the eligible accounts and the corresponding amounts. The ZKsync Association team shared their willingness to publish the data required to reconstruct the Merkle tree so that anyone can verify the correctness of the Merkle root.

Low Severity
------------

### The Domain of The Permit Functionality Is Not Initialized

The [`initialize`](https://github.com/zksync-association/zk-governance/blob/f37e3dcdb99600e73a13851d066b10f86e3c6427/src/ZkTokenV1.sol#L42-L50) function of the `ZkTokenV1` contract does not call [the initializer](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/fbdb824a735891908d5588b28e0da5852d7ed7ba/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol#L40-L42) of the `ERC20PermitUpgradeable` base contract. This could impact user experience when approving using the permit functionality as there will be [no readable name](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/fbdb824a735891908d5588b28e0da5852d7ed7ba/contracts/utils/cryptography/EIP712Upgradeable.sol#L59-L63) for the signing domain.

Consider initializing the `ERC20PermitUpgradeable` base contract.

_**Update:** Resolved at commit [63bdcc9](https://github.com/zksync-association/zk-governance/commit/63bdcc9b90426fd480291bec9681588f75e2b54f)._

### Claim Cap Is Not Enforced on Merkle Distributor

The `_claim` function is supposed to verify that the total claimed amount is below the maximum total claimable amount according to the [specification](https://github.com/zksync-association/zk-governance/issues/16). However, it checks a [particular amount instead](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol#L276).

Consider checking the total claimed amount instead of a particular amount.

_**Update:** Resolved at commit [f9b1389](https://github.com/zksync-association/zk-governance/commit/f9b138941a9a49c0dba867932f19a2f652428d45)._

### Claim Can Be Prevented by Anyone if Front-Ran

Both the `claim` and `claimOnBehalf` functions delegate the claimed amount at the end of their execution. However, it is possible to extract the `_delegateInfo` parameter and front-run this transaction by calling the `delegateBySig` function on the token directly. This way, the nonce is incremented due to which the whole claim transaction reverts when the delegation is attempted.

Consider redesigning the requirement for delegation upon claim or calling the `delegateBySig` function in a `try-catch` block.

_**Update:** Resolved at commit [e2f3209](https://github.com/zksync-association/zk-governance/commit/e2f3209ddc840424fe00ef6f57136bc086dd7b4f)._

### Not All Delegation Parameters Are Signed

From all the `DelegateInfo` parameters, only the [`delegatee` parameter is signed](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol#L166). As such, it is possible to front-run the transaction, change the signature to oneself while keeping the delegatee, and claim the airdrop but skip the original delegation. This way, the original transaction is fulfilled only partially because the airdrop is correctly claimed but the delegation is not correctly set.

Consider signing all the `DelegateInfo` parameters.

_**Update:** Resolved at commits [d2116b3](https://github.com/zksync-association/zk-governance/commit/d2116b3e1229144762cff497f23422c6478c170a) and [36c6145](https://github.com/zksync-association/zk-governance/commit/36c61457c8e9e31227773f54eb83c2eb3b5baee6). All the `DelegateInfo` parameters are signed except for the `expiry` which is ignored in favour of the claim signature's expiry._

### Voting Checkpoints Refer to Block Numbers Despite Unstable Block Production Frequency

The `ZkTokenV1` is the governance token that will be used for voting during an open governance proposal. For vote counting, the governor will read the users' voting power checkpoint with respect to the associated voting period. According to the current default, checkpoints are created [per block numbers](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/fbdb824a735891908d5588b28e0da5852d7ed7ba/contracts/governance/utils/VotesUpgradeable.sol#L76-L78) which will, in turn, enforce the proposals' voting period to be expressed in block numbers. However, in ZKsync Era, the block production time is not stable and it may be confusing for users to predict the voting checkpoint so as to vote in time.

In order to avoid confusion and enhance user experience, consider modifying the vote checkpoint unit to block timestamp.

_**Update:** Resolved at commit [a4a45fe](https://github.com/zksync-association/zk-governance/commit/a4a45fe277bc0d9ff7029bd887db2431183da940)._

### Problematic Edge Cases When Using `delegateBySig`

To encourage governance participation through delegation, the `delegateBySig` function [is called](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol#L218) together with a token claim. However, `delegateBySig` works only for EOA signatures and does not support ERC-1271 nor account abstraction due to backwards compatibility reasons. Given that account abstraction is common on ZKsync Era, the feature might not work as expected for some accounts.

Consider choosing another way of encouraging governance participation that will support EOAs as well as smart contracts and account abstraction.

_**Update:** Resolved at commit [4587190](https://github.com/zksync-association/zk-governance/commit/458719067813843baf230b35415822c70be1f762)._

Notes & Additional Information
------------------------------

### Initializer Is Not Disabled on Implementation

The [`ZkTokenV1`](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkTokenV1.sol) implementation is left uninitialized which allows anyone to initialize it with arbitrary values.

While this does not lead to security issues in this case, consider calling the [`_disableInitializers`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/fbdb824a735891908d5588b28e0da5852d7ed7ba/contracts/proxy/utils/Initializable.sol#L192) function in `ZkTokenV1`'s constructor to disable the initializer.

_**Update:** Acknowledged, not resolved. The ScopeLift team stated:_

> _When deployed, the token contract will be initialized in the same transaction._

### Same `nonces` Mapping Is Used for Vote Delegation and Permit

The `ERC20VotesUpgradeable` and `ERC20PermitUpgradeable` base contracts of `ZkTokenV1` use the same [`nonces`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/fbdb824a735891908d5588b28e0da5852d7ed7ba/contracts/utils/NoncesUpgradeable.sol#L17) mapping. As a consequence, it would be invalid to include the same nonce in a delegate-by-signature message and in a subsequent permit message or vice versa.

Consider clearly documenting that the nonces produced for both delegation and permit actions should respect a single order so as to avoid failing transactions.

_**Update:** Resolved at commit [604fdf9](https://github.com/zksync-association/zk-governance/commit/604fdf9540f47b48793caf57f6dae2e594953dff). Further docstrings were added to clarify how to use the nonces of both actions correctly._

### Missing Input Validation

The [`_windowStart` timestamp must be less than `_windowEnd`](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol#L111-L112). Otherwise, the `ZkMerkleDistributor` contract will not work according to the specification. However, this is not enforced in the contract.

Consider verifying that the start timestamp is less than the end timestamp in the constructor.

_**Update:** Acknowledged, not resolved. The ScopeLift team stated:_

> _If misconfigured, which is unlikely, we will deploy a new contract._

### Code Clarity Suggestions

Throughout the [codebase](https://github.com/zksync-association/zk-governance/tree/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src), a number of instances were identified where code clarity could be improved:

*   Since the `BitMap` methods are [bound](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol#L15) to the `claimedBitMap` variable, it is possible to use a shorter syntax for these methods. For example, [`BitMaps.get(claimedBitMap, _index)`](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol#L118) can be `claimedBitMap.get(_index)`. Otherwise, binding methods is not necessary.
*   The [`toTypedDataHash` function](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/01ef448981be9d20ca85f2faf6ebdf591ce409f3/contracts/utils/cryptography/MessageHashUtils.sol#L76-L85) can be used to get the typed data hash in the [`claimOnBehalf` function](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol#L154-L173) for succinctness.
*   The [`verify` function is used](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol#L207) even though the proof is a calldata. Consider using the [`verifyCalldata` function](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/01ef448981be9d20ca85f2faf6ebdf591ce409f3/contracts/utils/cryptography/MerkleProof.sol#L39-L41).

_**Update:** Partially resolved at commit [604fdf9](https://github.com/zksync-association/zk-governance/commit/604fdf9540f47b48793caf57f6dae2e594953dff). The `claimAndDelegateOnBehalf` function does not use the `toTypedDataHash` function._

### Incomplete Docstrings

Within `ZkMerkleDistributor.sol`, not all return values of the [isClaimed](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol#L117-L119) function are documented.

Consider thoroughly documenting all functions/events (and their parameters or return values) that are part of a contract's public API. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved at commit [604fdf9](https://github.com/zksync-association/zk-governance/commit/604fdf9540f47b48793caf57f6dae2e594953dff)._

### Floating Pragma

Pragma directives should be fixed to clearly identify the Solidity version with which the contracts will be compiled.

Throughout the codebase, there are multiple floating pragma directives:

*   `IMintable.sol` has the [`solidity ^0.8.24`](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/interfaces/IMintable.sol#L2) floating pragma directive.
*   `IMintableAndDelegatable.sol` has the [`solidity ^0.8.24`](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/interfaces/IMintableAndDelegatable.sol#L2) floating pragma directive.

Consider using fixed pragma directives.

_**Update:** Resolved at commit [604fdf9](https://github.com/zksync-association/zk-governance/commit/604fdf9540f47b48793caf57f6dae2e594953dff)._

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice proves beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Throughout the codebase, there are contracts that do not have a security contact:

*   The [`ZkCappedMinter` contract](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkCappedMinter.sol)
*   The [`ZkMerkleDistributor` contract](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkMerkleDistributor.sol)
*   The [`ZkTokenV1` contract](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a/src/ZkTokenV1.sol)

Consider adding a NatSpec comment containing a security contact above the contract definitions. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved at commit [604fdf9](https://github.com/zksync-association/zk-governance/commit/604fdf9540f47b48793caf57f6dae2e594953dff)._

Recommendations
---------------

### Deployment Suggestions

The system uses the [OpenZeppelin/openzeppelin-foundry-upgrades](https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades) library for deployments. This library was developed to be compatible with EVM chains but was not thoroughly tested for ZKsync Era deployments.

Given that ZKsync Era has some [differences](https://docs.zksync.io/build/developer-reference/differences-with-ethereum.html) compared to Ethereum and uses its own versions of the [Foundry toolkit](https://github.com/matter-labs/foundry-zksync) and the [Solidity compiler](https://github.com/matter-labs/era-compiler-solidity), consider thoroughly testing the deployment on ZKsync Era testnet before deploying to the ZKsync Era mainnet.

_**The ScopeLift team responded:**_

> _We modified our deployment scripts to use hardhat with ZKsync's plugins (at commit [a26da8a](https://github.com/zksync-association/zk-governance/commit/a26da8a12993dc4ef65175e5f0aad16d90310079)). This change required us to downgrade to OZ Contracts v4.9._

_As a result of the downgrade to OZ Contracts v4.9, OpenZeppelin assessed the degree of the changes and did not identify any issues. The code level changes of the library contracts used in this project are backwards compatible._

Conclusion
----------

The audit only yielded low-severity issues which indicates an overall healthy design and implementation. Several fixes were suggested to address edge cases and improve the usability, robustness, and clarity of the codebase. The in-scope contracts were inspected, taking into consideration the integrated libraries and the specifics of the ZKsync Era ecosystem.

The ScopeLift team, who developed the codebase for ZKsync Association, provided a detailed specification of the system and sufficiently covered the codebase with tests. Both ZKsync Association and ScopeLift teams were very responsive and engaged in discussions with the audit team.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kE9FD11rdwVSAPrnv_Io33J2eDaUw&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=184043227713&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=91d0cacd-47ad-4b1f-852f-2291cfabebbe&redirect_url=APefjpE5fXaI_jTh5bblZpYXj2lzvMc6dkJzZcbDfegBVUuqB_OAzyr9MR6SXhCFSV62WQ-GIVgjFEP8GhzJjlxFDEBKPcVJkP-FXwRoxidHvTD3u1s7oQKWcb02FdATjDXW0gY92Ggqm1bHG9GIOM4U2railYO4JZsG1kERFE1ED309atndkcBi1yqJ3J6o0qF6YR58TYyVwezDXVwQ1nvrNIB_hNK_NCRfQng6C64Kv3-WkqmwW3jsNQ-STl9alagK4h8YXnmY&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Fzk-token-capped-minter-and-merkle-distributor-audit&ts=1770534284480&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.92.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")