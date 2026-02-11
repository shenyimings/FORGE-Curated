\- March 12, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

Type

DeFi

Timeline

From 2024-12-02

To 2024-12-10

Languages

Solidity

Total Issues

10 (8 resolved)

Critical Severity Issues

0 (0 resolved)

High Severity Issues

0 (0 resolved)

Medium Severity Issues

0 (0 resolved)

Low Severity Issues

2 (1 resolved)

Notes & Additional Information

8 (7 resolved)

Scope
-----

We audited the [fireblocks/fireblocks-smart-contracts](https://github.com/fireblocks/fireblocks-smart-contracts) repository at commit [cf1bb85](https://github.com/fireblocks/fireblocks-smart-contracts/tree/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8).

In scope were the following files:

`contracts
├── gasless-contracts
│   ├── AccessRegistry
│   │   ├── AccessListUpgradeableGasless.sol
│   │   ├── AllowListGasless.sol
│   │   └── DenyListGasless.sol
│   ├── ERC1155FGasless.sol
│   ├── ERC20FGasless.sol
│   ├── ERC721FGasless.sol
│   ├── GaslessFactory.sol
│   └── TrustedForwarder.sol
├── gasless-upgrades
│   ├── AccessRegistry
│   │   ├── AllowListV2.sol
│   │   └── DenyListV2.sol
│   ├── ERC1155FV2.sol
│   ├── ERC20FV2.sol
│   └── ERC721FV2.sol
└── library
    ├── MetaTx
    │   └── ERC2771ContextInitializableUpgradeable.sol
    └── Proxy
        └── Proxy.sol` 

System Overview
---------------

The Fireblocks [Gasless contracts](https://github.com/fireblocks/fireblocks-smart-contracts/tree/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts) are an extension of the Fireblocks Upgradeable Tokens, allowing them to support meta transactions by leveraging [the ERC-2771 standard](https://eips.ethereum.org/EIPS/eip-2771). These contracts inherit from the `ERC2771ContextInitializableUpgradeable` contract which allows users to optionally set a trusted forwarder, thereby providing users the flexibility to choose between gasless or non-gasless versions.

Along with the gasless versions of the utility tokens, access control, and access list, a [`GaslessFactory`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol) contract has also been introduced. This is a singleton contract that allows its users to deploy deterministic and non-deterministic contracts through meta transactions. In addition, a [`TrustedForwarder`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/TrustedForwarder.sol) contract has been added, which directly inherits the OpenZeppelin contract library's `ERC2771Forwarder` contract. Both the `GaslessFactory` and `TrustedForwarder` contracts are non-upgradeable.

The repository also introduces another set of contracts called [`Gasless upgrades`](https://github.com/fireblocks/fireblocks-smart-contracts/tree/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-upgrades), which allow for upgrading the initial version of the contracts to the gasless version, and thereby introduce support for meta transactions. These contracts enforce that [only the contracts on version 1 can upgrade to version 2](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-upgrades/AccessRegistry/AllowListV2.sol#L85), ensuring compatibility between the two versions and avoiding any storage collisions. A `Proxy` contract has also been introduced, which inherits the OpenZeppelin contract library's `ERC1967Proxy` contract, ensuring that Fireblocks' library users have a standardized version of the proxy contracts.

Security Model and Trust Assumptions
------------------------------------

In addition to the roles inherited via the chain of inheritance, a `CONTRACT_ADMIN_ROLE` role has been defined in the following contracts. This role can update the trusted forwarder for each respective contract.

*   `AccessListUpgradeableGasless` contract
*   `AllowListV2` contract
*   `DenyListV2` contract
*   `ERC1155FGasless` contract
*   `ERC1155FV2` contract
*   `ERC20FGasless` contract
*   `ERC20FV2` contract
*   `ERC721FGasless` contract
*   `ERC721FV2` contract

It is assumed that the accounts in charge of the above roles and actions always act in the intended manner.

Low Severity
------------

### Limitation in Asset Transfer Capabilities During Contract Deployment in `GaslessFactory`

The `GaslessFactory` contract facilitates the deployment of new contracts through two primary functions: [`deploy`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol#L108-L138) and [`deployDeterministic`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol#L161-L177). The `deploy` function enables standard contract creation, while `deployDeterministic` allows for deterministic contract deployment using the `CREATE2` opcode. Despite their utility in contract deployment, both functions exhibit a limitation as they are not marked as `payable`. This restriction prevents users from sending native assets alongside the contract deployment transaction. Consequently, any scenario requiring the newly deployed contract to hold a native asset balance upon creation cannot be accommodated.

Furthermore, this limitation extends to the `postConfig` function, which is designed for calling functions of the newly deployed contracts as part of their initial configuration. Since `postConfig` also does not support sending native assets along with the function calls, it restricts the initialization capabilities, particularly for contracts whose setup functions require a native asset transfer.

This constraint not only limits the versatility of the `GaslessFactory` contract in deploying and configuring a wide range of contracts, but also complicates the deployment process for contracts designed to hold or manage native assets immediately upon creation. To overcome this limitation and enhance the `GaslessFactory` contract's functionality, consider making `deploy` and `deployDeterministic` functions `payable` and pass along the amount to the `create` or `create2` function. This will enable the two functions to accept native asset transfers as part of the contract deployment process and allow users to deploy contracts that require an initial native asset balance.

By implementing the aforementioned recommendations, the `GaslessFactory` contract will improve its utility and flexibility, accommodating a broader range of deployment and configuration scenarios, including those requiring immediate asset management capabilities.

_**Update:** Acknowledged, not resolved. The Fireblocks team stated:_

> _This design was intentional as it keeps the `GaslessFactory` code clean and simple. We have no use cases for `payable` functions and want to avoid having extra code to handle edge cases like potential loss of funds or their recovery._

### Premature Event Emission in GaslessFactory's `_execute` Function

The [`_execute` function](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol#L220-L227) of the `GaslessFactory` contract is designed to facilitate gasless transactions by delegating function calls to other contracts. However, an issue arises with the order of operations within this function, specifically concerning the emission of the [`FunctionExecuted` event](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol#L225). The event is emitted prior to the actual execution of the delegated function call. This premature event emission leads to a scenario where the event logs a result of zero, regardless of the actual outcome of the function call that follows.

This behavior can mislead off-chain services or users monitoring these events, as the `FunctionExecuted` event suggests the completion of a function call without accurately reflecting its result. In a blockchain environment, where transparency and accuracy of operations are paramount, such discrepancies can undermine trust in the system's reliability.

Consider adjusting the sequence of operations within the `_execute` function. Specifically, the `FunctionExecuted` event should be emitted only after the delegated function call has been successfully executed. This ensures that the event accurately reflects the outcome of the function call, aligning with the expectations set by its emission. By implementing this change, the `GaslessFactory` contract will enhance its operational transparency and reliability, providing accurate feedback to the system's participants through event emissions.

_**Update:** Resolved in [pull request #1](https://github.com/fireblocks/fireblocks-smart-contracts/pull/1) at commit [43a713b](https://github.com/fireblocks/fireblocks-smart-contracts/pull/1/commits/43a713bc30ba7a3f4457632d2814b4597170ab70)._

Notes & Additional Information
------------------------------

### Ambiguous Calls to Parent Contract

Throughout the codebase, multiple instances of ambiguous calls to parent contracts were identified:

*   The [`super._msgSender`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/AccessRegistry/AccessListUpgradeableGasless.sol#L110) in the `AccessListUpgradeableGasless` contract
*   The [`super._msgData`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/AccessRegistry/AccessListUpgradeableGasless.sol#L126) in the `AccessListUpgradeableGasless` contract
*   The [`super._msgSender`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-upgrades/AccessRegistry/AllowListV2.sol#L125) in the `AllowListV2` contract
*   The [`super._msgData`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-upgrades/AccessRegistry/AllowListV2.sol#L141) in the `AllowListV2` contract
*   The [`super._msgSender`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-upgrades/AccessRegistry/DenyListV2.sol#L126) in the `DenyListV2` contract
*   The [`super._msgData`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-upgrades/AccessRegistry/DenyListV2.sol#L142) in the `DenyListV2` contract
*   The [`super._msgSender`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-upgrades/ERC1155FV2.sol#L132) in the `ERC1155FV2` contract
*   The [`super._msgData`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-upgrades/ERC1155FV2.sol#L148) in the `ERC1155FV2` contract
*   The [`super._msgSender`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/ERC20FGasless.sol#L150) in the `ERC20FGasless` contract
*   The [`super._msgData`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/ERC20FGasless.sol#L166) in the `ERC20FGasless` contract
*   The [`super._msgSender`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-upgrades/ERC20FV2.sol#L129) in the `ERC20FV2` contract
*   The [`super._msgData`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-upgrades/ERC20FV2.sol#L145) in the `ERC20FV2` contract
*   The [`super._msgSender`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-upgrades/ERC721FV2.sol#L133) in the `ERC721FV2` contract
*   The [`super._msgData`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-upgrades/ERC721FV2.sol#L149) in the `ERC721FV2` contract
*   The [`super._msgSender`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol#L236) in the `GaslessFactory` contract
*   The [`super._msgData`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol#L246) in the `GaslessFactory` contract
*   The [`super._contextSuffixLength`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol#L256) in the `GaslessFactory` contract

To avoid ambiguous calls to parent contracts, consider explicitly specifying the parent contract's function being called.

_**Update:** Resolved in [pull request #2](https://github.com/fireblocks/fireblocks-smart-contracts/pull/2) at commit [2ef4c95](https://github.com/fireblocks/fireblocks-smart-contracts/pull/2/commits/2ef4c95105a9405f022e97bd9d79b16ac703ce11)._

### Compatibility Issues of GaslessFactory Contract with ZkSync Era Deployment Mechanism

[The `GaslessFactory` contract](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol), designed for facilitating contract deployments and operations without gas fees, encounters significant functional discrepancies when deployed on the ZkSync Era platform. Two core issues underpin these discrepancies: the method of address derivation and the prerequisites for contract deployment concerning bytecode knowledge.

1.  On Ethereum, the address of a new contract is derived through a deterministic process involving the deployer's address and the nonce (the number of transactions sent by the deployer's address). However, ZkSync Era employs [a different mechanism for address derivation](https://docs.zksync.io/zksync-protocol/differences/evm-instructions#address-derivation) which does not align with Ethereum's method. This divergence means that the `GaslessFactory` contract's expectations for address derivation and, consequently, its ability to predict or interact with newly deployed contract addresses, are misaligned with the operational realities of ZkSync Era.
    
2.  The deployment of contracts on ZkSync Era is uniquely characterized by its requirement for the hash of the contract's bytecode and [the necessity for the compiler to be aware of this bytecode in advance](https://docs.zksync.io/zksync-protocol/differences/evm-instructions#create-create2). This requirement stands in contrast to Ethereum's deployment mechanism, where the bytecode is generated and provided at the time of deployment without prior knowledge needed by the compiler. The `GaslessFactory` contract's `deploy` function, which is designed to deploy contracts dynamically without precompiled bytecode knowledge, is inherently incompatible with ZkSync Era's deployment prerequisites. This incompatibility renders the `deploy` function ineffective on ZkSync Era, as it cannot fulfill the platform's requirement for bytecode awareness prior to deployment.
    

To address these compatibility issues and enable the `GaslessFactory` contract to function as intended on ZkSync Era, consider implementing the following modifications:

1.  **Address Derivation Adaptation**: Implement a mechanism within the `GaslessFactory` contract to accommodate ZkSync Era's address derivation method. This may involve integrating ZkSync Era's address derivation logic or a contract call that can predict or determine addresses correctly within the ZkSync Era environment.
    
2.  **Precompiled Bytecode Management**: Revise the contract deployment strategy to align with ZkSync Era's requirement for precompiled bytecode knowledge. This could involve strategies such as:
    
    *   Maintaining a registry within the `GaslessFactory` contract of precompiled bytecodes for contracts intended for deployment.
    *   Developing a tool or process for precompiling contract bytecodes and registering them with the `GaslessFactory` contract or another on-chain registry before any deployment attempts.
3.  **Documentation and Developer Guidance**: Update the `GaslessFactory` contract's documentation to clearly describe its compatibility with ZkSync Era, including any limitations, prerequisites for deployment, and guidance on address derivation and precompiled bytecode management.
    

By implementing the aforementioned recommendations, the `GaslessFactory` contract can be adapted to operate effectively within the ZkSync Era ecosystem, thereby extending its utility to this emerging platform and ensuring its functionality aligns with the unique requirements of ZkSync Era's contract deployment and address management mechanisms.

_**Update:** Acknowledged, not resolved. The Fireblocks team stated:_

> _We do not intend to make custom adjustments to our code for a specific blockchain. Additionally, we have no plans to deploy this factory on ZKSync. It is worth noting that deployment on ZKSync cannot happen accidentally, as it requires a separate and intentional compilation using the ZKSync compiler._

### Prefix Increment Operator `++i` Can Save Gas in Loops

Within `GaslessFactory.sol`, multiple opportunities for saving gas by using the prefix increment operator (`++i`) were identified:

*   In [line 135](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol#L135).
*   In [line 174](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol#L174).

Consider using the prefix increment operator (`++i`) instead of the post-increment operator (`i++`) in order to save gas. This optimization skips storing the value before the increment, as the return value of the expression is ignored.

_**Update:** Resolved in [pull request #3](https://github.com/fireblocks/fireblocks-smart-contracts/pull/3) at commit [a8942e9](https://github.com/fireblocks/fireblocks-smart-contracts/pull/3/commits/a8942e9b732a25cb491640889edb0479b544e431)._

### Missing Docstrings

Within `Proxy.sol`, the docstring for the [`Proxy` contract](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/library/Proxy/Proxy.sol#L20-L29) itself is missing.

Consider thoroughly documenting all functions (and their parameters) that are part of any contract's public API. Functions implementing sensitive functionality, even if not public, should be clearly documented as well. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in [pull request #4](https://github.com/fireblocks/fireblocks-smart-contracts/pull/4) at commit [5a1aa15](https://github.com/fireblocks/fireblocks-smart-contracts/pull/4/commits/5a1aa150d5c699afa71b1ebe0f134afbfe2ccd4b)._

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Given that these contracts are templates to be utilized by other entities, consider adding a security contact within the Fireblocks repository. An example of this can be found in the [`SECURITY.md`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.1.0/SECURITY.md) of the OpenZeppelin Contracts library.

_**Update:** Resolved in [pull request #8](https://github.com/fireblocks/fireblocks-smart-contracts/pull/8) at commit [d3b7de0](https://github.com/fireblocks/fireblocks-smart-contracts/pull/8/commits/d3b7de07d253076d59f572d107206d973dcc09b3)._

### Incremental Update Is Not Wrapped in an `unchecked` Block

Since Solidity version `0.8.0`, arithmetic operations include automatic checks for overflows and underflows, which increase gas costs. In scenarios where it is highly unlikely for a positively incrementing variable to overflow within a loop, using an `unchecked` block can optimize gas usage without compromising security. Before Solidity version `0.8.22`, developers manually implemented this optimization to bypass the additional overhead from automatic overflow checks.

Within `GaslessFactory.sol`, multiple opportunities for saving gas by using the `unchecked` block were identified:

*   The [`i++`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol#L135) increment operation in the `deploy` function
*   The [`i++`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol#L174) increment operation in the `deployDeterministic` function

Consider either updating the pragma version to [`0.8.22`](https://soliditylang.org/blog/2023/10/25/solidity-0.8.22-release-announcement/) to leverage automatic overflow check optimizations or wrapping incremental updates in an `unchecked` block to save gas.

_**Update:** Resolved in [pull request #5](https://github.com/fireblocks/fireblocks-smart-contracts/pull/5) at commit [1e0c6f5](https://github.com/fireblocks/fireblocks-smart-contracts/pull/5/commits/1e0c6f5884b7d26a7e5e193261c397aef31e18f7)._

### Different Versions of OpenZeppelin Contracts Library Used

The [`Proxy` contract](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/library/Proxy/Proxy.sol) uses version `4.9.3` of the OpenZeppelin Contracts library, whereas the [`GaslessFactory`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol) and [`TrustedForwarder`](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/TrustedForwarder.sol) contracts use version `5.0.2`.

To be consistent with the rest of the codebase, consider updating the dependency in the `Proxy` contract to version `5.0.2`.

_**Update:** Resolved in [pull request #6](https://github.com/fireblocks/fireblocks-smart-contracts/pull/6) at commit [0e3be3a](https://github.com/fireblocks/fireblocks-smart-contracts/pull/6/commits/0e3be3a2ae31676f57e31e56f5ec7f58ba93c2b1)._

### Deployment Failure Revert Reason Not Propagated in `deployDeterministic`

The `GaslessFactory` contract utilizes [the `deployDeterministic` function](https://github.com/fireblocks/fireblocks-smart-contracts/blob/cf1bb85ea84cd9ce9b509e285e835b8eb459ddd8/contracts/gasless-contracts/GaslessFactory.sol#L161-L177) to create new contracts deterministically. This function is crucial for deploying contracts without requiring gas from the user, leveraging the `CREATE2` opcode for deterministic address generation. However, a limitation arises due to the use of version `5.0.x` of the OpenZeppelin Contracts library. In this version, the functionality to bubble up revert reasons during contract creation failures [is absent](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/dbb6104ce834628e473d2173bbc9d47f81a9eec3/contracts/utils/Create2.sol#L53-L55). This feature was only [introduced in version `5.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/69c8def5f222ff96f2b5beff05dfba996368aa79/contracts/utils/Create2.sol#L47-L51) of the OpenZeppelin Contracts library.

The absence of revert reason propagation means that when a contract deployment fails, the `deployDeterministic` function does not provide the caller with the specific reason for the failure. This lack of transparency can hinder debugging efforts and obscure potential vulnerabilities or logic errors in the contract code intended for deployment. It also impacts the user experience, as developers or users interacting with the `GaslessFactory` cannot easily ascertain the cause of deployment failures.

Consider upgrading the OpenZeppelin contracts library used by the `GaslessFactory` to version `5.1` or later. This newer version includes enhancements that allow revert reasons to be propagated back to the caller when a contract creation fails. Implementing this upgrade will make debugging more straightforward and improve the overall security posture by ensuring that the causes of deployment failures are transparent and actionable.

_**Update:** Resolved in [pull request #7](https://github.com/fireblocks/fireblocks-smart-contracts/pull/7) at commit [ddd1e4a](https://github.com/fireblocks/fireblocks-smart-contracts/pull/7/commits/ddd1e4a657cdf0132d5f5e3523e30e991cbdea50)._

Conclusion
----------

The Fireblocks Gasless contracts demonstrate a well-structured implementation of meta-transaction capabilities, integrating [the ERC-2771 standard](https://eips.ethereum.org/EIPS/eip-2771) seamlessly within the `ERC-20`, `ERC-721`, and `ERC-1155` Fireblocks Upgradeable Tokens. The codebase showcases a comprehensive approach to enabling gasless transactions while maintaining compatibility and flexibility for users, supported by robust design principles such as deterministic and non-deterministic contract deployments through the `GaslessFactory` contract. The codebase was found to be well-written and thoroughly documented, while the Fireblocks team timely answered any questions we had about the codebase.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kGvk2d2Zarh69UNc48bjDZ46pKN9g&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=186815618428&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=b5dc883d-d45d-4628-afc0-b2e242174c9b&redirect_url=APefjpHPVdjveinaXNaYzH5P17iriYnx8fL7ea50XeF1rGZ-q_PXgkSe36haFfel0YtNnVfogzcWJBRGetrhKFXNCZJpbsUbT49KD7QyOXKwTClgBilrRz6_7HoOTbOco8ZyVqaJi2AevBhzlDmK1WBgiAh_JlIhcUtr5A6YU-k1gV5amp9bOkyb_5QrvpjWGZodCvr8dCuA2eXSpHOncHrrARjRycN-ufO6DUrtIkbI-lyDYNLhz12RN1XTmURPcZ2P2Vyz0c8h&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Ffireblocks-gasless-contracts-audit&ts=1770534280298&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.86.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")