\- March 25, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

Type

DeFi

Timeline

From 2025-01-27

To 2025-02-06

Languages

Solidity

Total Issues

20 (15 resolved)

Critical Severity Issues

0 (0 resolved)

High Severity Issues

0 (0 resolved)

Medium Severity Issues

0 (0 resolved)

Low Severity Issues

3 (2 resolved)

Notes & Additional Information

17 (13 resolved)

Scope
-----

We audited the [wisdomtreeam/whitelist-contexts](https://bitbucket.org/wisdomtreeam/whitelist-contexts) repository at commit [4476078](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/).

The following files were fully audited:

`src
├── common
│   ├── access-control
│   │   ├── AccessControl.sol
│   │   └── IAccessControl.sol
│   ├── interfaces
│   │   ├── IBeacon.sol
│   │   └── IERC165.sol
│   └── libraries
│       ├── BytesHelper.sol
│       └── StorageSlot.sol
├── oracles
│   ├── interfaces
│   │   ├── ICompliance.sol
│   │   ├── IOracle.sol
│   │   ├── IOracleBeaconUpgrade.sol
│   │   ├── IOracleInit.sol
│   │   ├── IWhitelistComplianceOracle.sol
│   │   └── IWhitelistOracle.sol
│   └── whitelist-compliance
│       └── WhitelistComplianceOracle.sol
├── proxies
│   ├── Beacon.sol
│   └── Proxy.sol
└── tokens
    ├── ERC721
    │   ├── ERC721BasicToken.sol
    │   └── ERC721SoulboundToken.sol
    └── interfaces
        ├── erc1155
        │   └── IERC1155.sol
        ├── erc721
        │   ├── IERC721.sol
        │   ├── IERC721BeaconUpgrade.sol
        │   ├── IERC721Burnable.sol
        │   ├── IERC721Enumerable.sol
        │   ├── IERC721Errors.sol
        │   ├── IERC721Events.sol
        │   ├── IERC721Metadata.sol
        │   ├── IERC721Mintable.sol
        │   ├── IERC721Receiver.sol
        │   ├── IERC721Token.sol
        │   └── IERC721TokenInit.sol
        └── erc721Soulbound
            ├── IERC721Soulbound.sol
            ├── IERC721SoulboundBeaconUpgrade.sol
            ├── IERC721SoulboundBurnable.sol
            ├── IERC721SoulboundEnumerable.sol
            ├── IERC721SoulboundErrors.sol
            ├── IERC721SoulboundEvents.sol
            ├── IERC721SoulboundMetadata.sol
            ├── IERC721SoulboundMintable.sol
            ├── IERC721SoulboundReceiver.sol
            ├── IERC721SoulboundToken.sol
            └── IERC721SoulboundTokenInit.sol` 

The following files were diff-audited against the OpenZeppelin library release `v5.0.0`:

`src
└── common
    └── libraries
        └── Arrays.sol` 

The following files were diff-audited against the OpenZeppelin library release `v4.8.0`:

`src
└── common
    └── libraries
        ├── Math.sol
        └── Strings.sol` 

Executive Summary
-----------------

OpenZeppelin was engaged by the WisdomTree Digital team to conduct a comprehensive audit of their implementation of an oracle whitelist system that allows token standards to authenticate transfers through whitelist membership verification. Our goal was to identify potential vulnerabilities, verify adherence to best practices, and provide recommendations for enhancing the overall security and functionality of the contracts. The audit only reviewed the smart contract components intended to be deployed on-chain and did not review any deployment scripts, configurations, mock contracts, or tests.

The system includes a Whitelist Oracle designed to authorize transfers for token standards such as ERC-20 by verifying whether the recipient holds any token from a specified ERC-721 or ERC-1155 contract or is directly allowed by a custom WhitelistOracle contract. In addition, the system implements two versions of an ERC-721 token. The first, used by the Whitelist Compliance Oracle, is a non-transferable "soulbound" version that can be minted to a single address and never transferred, designed to be held by whitelisted accounts. The second is a standard implementation that, although not part of the system, serves as a foundation for more complex token designs.

This audit engaged two full-time auditors performing a manual, line-by-line review of the entire codebase as well as the use of automated code analysis for vulnerability detection. In particular, the audit validated that:

*   All functionality performs as intended.
*   The token contracts conform with the ERC-721 standard.
*   The whitelist implementation is robust and cannot be bypassed when properly integrated into a token contract.
*   External actors can only interact with the system as intended.
*   Best practices have been followed for code style and documentation.

This audit identified 20 issues. In particular, a recommendation was made to make the access control more granular to ensure that each account holding a privileged role is only capable of performing a subset of actions to reduce the overall risk from a compromised account. The remainder of the issues raised were aimed at improving the readability and maintainability of the codebase, addressing minor inconsistencies and redundancies within the code, and reducing gas costs. Overall, the codebase was found to be well-structured and to follow the best practices.

System Overview
---------------

The Whitelist Oracle system provides a compliance framework that allows token standards to authenticate transfers through whitelist membership verification. Central to this system is the `WhitelistComplianceOracle` contract, which serves as the core of the system's verification processes. In addition, the project includes two token implementations: a classic ERC-721 token and a non-transferable "Soulbound" ERC-721 token. The ERC-721 standard implementations are adapted from OpenZeppelin's library and have been modified to meet the project's requirements.

### Whitelist Compliance Oracle

The `WhitelistComplianceOracle` contract serves as the central compliance verification hub of the Whitelist Oracle system. It implements the `ICompliance` interface, facilitating seamless interaction with a registry of whitelisting contracts. This registry is crucial to the system, as it maintains a comprehensive list of contracts used to authorize token transfers. These contracts can be tokens contracts, such as `ERC721SoulboundToken` and `ERC1155`, which allow a transfer if the receiver holds at least one of the specified tokens, or an external `WhitelistOracle` contract, which can be queried to check the authorization of the transfer.

### ERC-721 Soulbound Token

The `ERC721SoulboundToken` is a non-transferable NFT implementation. Its purpose is to define membership and identity within the system. By extending the ERC-721 standard, this token variant introduces a "Soulbound" feature, ensuring that tokens are irrevocably linked to their initial receiving addresses, thereby preventing any form of transfer and enhancing the system's security and compliance capabilities. Such tokens are minted after a user has passed through KYC or AML processes.

### ERC-721 Basic Token

Although not actively utilized within the current scope of the Whitelist Oracle system, the `ERC721BasicToken` contract serves as a foundational pillar, offering essential ERC-721 functionalities complemented by role-based access control and upgradeability features. This standard implementation lays the groundwork for more complex token implementations, offering role-based access control and an upgradeability pattern as well.

### Access Control

All components inherit the `AccessControl` contract which defines specific roles for each contract within the system, ensuring a granular level of control and security. Furthermore, the adoption of the Beacon Proxy pattern for atomic upgrades and the Storage Slots pattern to prevent upgrade collisions ensures the system's longevity and adaptability.

Security Model and Trust Assumption
-----------------------------------

The Whitelist Oracle system implements multiple privileged roles through the `AccessControl` contract. The holders of such roles are expected to be non-malicious and to act in the project's best interest.

### Privileged Roles

The system introduces several distinct privileged roles, each with specific responsibilities and capabilities:

*   `DEFAULT_ADMIN_ROLE`:
    *   Assigned during the initial contract setup.
    *   Empowered to assign roles to other participants and initiate upgrades to beacons.
    *   This role is exclusively reserved for a maximum of three addresses.
*   `DELEGATED_ADMIN_ROLE`:
    *   This role is governed by both `DEFAULT_ADMIN_ROLE` and `DELEGATED_ADMIN_ROLE` holders.
    *   Admin role for `ISSUER_ROLE` and `REGISTRAR_ROLE` roles.
    *   When a `DEFAULT_ADMIN_ROLE` role is rescinded, all of its delegated roles are simultaneously revoked.
*   `REGISTRAR_ROLE`:
    *   This role is governed by both `DEFAULT_ADMIN_ROLE` and `DELEGATED_ADMIN_ROLE` holders.
    *   Authorized to oversee token-related activities, including minting or burning tokens.
*   `ISSUER_ROLE`:
    *   This role is governed by both `DEFAULT_ADMIN_ROLE` and `DELEGATED_ADMIN_ROLE` holders.
    *   Allocated for functionalities yet to be introduced.

The system also implements a mechanism to prevent the loss of access to the `DEFAULT_ADMIN_ROLE` by explicitly requiring that at least one address always holds the role.

Low Severity
------------

### Lack of Granular Permission Control in `WhitelistComplianceOracle`

The [`WhitelistComplianceOracle`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-20:24) contract inherits the `AccessControl` contract but relies solely on the owner with the `DEFAULT_ADMIN_ROLE` to manage the contract. This role has the ability to upgrade the beacon address, add and remove address contexts, enable and disable the oracle, and set the maximum number of contract contexts.

Consider implementing more granular access controls.

_**Update:** Acknowledged, not resolved. The team stated:_

> _Finding acknowledged. The restriction on the `WhitelistComplianceOracle` to only be managed by the `DEFAULT_ADMIN_ROLE` is intentional by design, this is an admin-level oracle that is only modifiable by admins within our protocol._

### Missing Event Emission

The [`setBaseURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-219:221) and [`setTokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-226:229) functions of the `ERC721SoulboundToken` contract do not emit events. This could make it challenging for off-chain applications to track changes in the contract.

Consider emitting events when updating the base URI or token URI.

_**Update:** Resolved in [pull request #5](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/5) at commit [9d6b857](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/9d6b857bbb27d3d55eddbb9ff101d12bd7a5c130). The team stated:_

> _Implemented auditors' recommended fix by adding event emits to the `setBaseURI` and `setTokenURI` functions of the `ERC721SoulboundToken` contract._

### Floating Pragma

Pragma directives should be fixed to clearly identify the Solidity version with which the contracts will be compiled. Throughout the codebase, multiple instances of floating pragma directives (`^0.8.19`) being used were identified.

Consider using fixed pragma directives.

_**Update:** Resolved in [pull request #6](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/6) at commit [7fefad4](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/7fefad4e93528560f2a468bf6015567c40cf7974). The team stated:_

> _Implemented auditors' recommended fix by changing pragma directives from floating to fixed across the codebase._

Notes & Additional Information
------------------------------

### Inconsistent Access Control When Granting The Delegated Admin Role

The [`grantDelegateAdminRole`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/common/access-control/AccessControl.sol#lines-175:177) function of the `AccessControl` contract can be executed by `DEFAULT_ADMIN_ROLE` or `DELEGATED_ADMIN_ROLE`. However, the batch version of the same functionality, the [`batchGrantDelegateAdminRole`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/common/access-control/AccessControl.sol#lines-203:206) function, can be only executed by the `DEFAULT_ADMIN_ROLE`.

Consider adjusting the access control for the `batchGrantDelegateAdminRole` function.

_**Update:** Acknowledged, not resolved. The team stated:_

> _This finding is acknowledged. For now, the restriction of the `batchGrantDelegateAdminRole` to only the `DEFAULT_ADMIN_ROLE` will remain because we want to align all of our AccessControl implementations across our protocol. In the future, once our protocol is under scope for an AccessControl upgrade, we can explore modifying this restriction._

### Redundant Code

Multiple instances of redundant or unnecessary code were identified throughout the codebase:

*   The `upgradeBeaconToAndCall` function of the [`WhitelistComplianceOracle`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-162), [`ERC721BasicTokens`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-156), and [`ERC721SoulboundToken`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-151) contracts checks whether the beacon address, passed as `newBeacon` argument, is not `address(0)`. However, the `_setBeacon` function checks for that as well, making the first `require` statement redundant. Consider removing the `require` statements within the `upgradeBeaconToAndCall` functions for those contracts.
*   The implementation of the `supportsInterface` function in [`ERC721BasicToken`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-457), [`ERC721SoulboundToken`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-403), and [`WhitelistComplianceOracle`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-338) returns `false` regardless of the result of the interface ID comparison with `0xffffffff`. Consider simplifying by directly returning false.

Consider implementing the above code changes to improve code clarity and eliminate redundancies.

_**Update:** Resolved in [pull request #7](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/7) at commit [49814d1](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/49814d13774e7190234358683dd1ff86da06dc07) and commit [9fecb7b](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/9fecb7b0b659566ff14cff1dc6e0491b22fe23ba). The team stated:_

> _Implemented auditors' recommended fixes by reducing redundancy in `upgradeBeaconToAndCall` and `supportInterface` functions of `WhitelistComplianceOracle`, `ERC721BasicToken`, and `ERC721SoulboundToken` contracts._

### Using `int/uint` Instead of `int256/uint256`

Throughout the codebase, multiple instances of `int/uint` being used instead of `int256/uint256` were identified:

*   In lines [23](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/interfaces/IWhitelistComplianceOracle.sol#lines-23), [31](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/interfaces/IWhitelistComplianceOracle.sol#lines-31), [50](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/interfaces/IWhitelistComplianceOracle.sol#lines-50), and [60](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/interfaces/IWhitelistComplianceOracle.sol#lines-60) of `IWhitelistComplianceOracle.sol`
*   In line [101](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/common/libraries/StorageSlot.sol#lines-101) of `StorageSlot.sol`
*   In lines [44](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-44), [170](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-170), [213](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-213), [221](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-221), [297](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-297), [299](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-299), [303](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-303), [317](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-317), and [369](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-369) of `WhitelistComplianceOracle.sol`

In favor of explicitness, consider replacing all instances of `int/uint` with `int256/uint256`.

_**Update:** Resolved in [pull request #8](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/8) at commit [17c7c0a](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/17c7c0a2f5b53d1d95f9b0a8e651e3efb8be9154). The team stated:_

> _Implemented auditors' recommendation by replacing all instances of `int/uint` with `int256/uint256`._

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the @custom:security-contact convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in [pull request #8](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/8) at commit [7958ca9](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/7958ca90efe6b1575dcc6a3a98c813053d01eecc). The team stated:_

> _Implemented auditors' recommendations by adding a NatSpec comment containing a security contact above each contract definition._

### Duplicate Imports

Throughout the codebase, multiple instances of duplicate imports were identified:

*   The `IERC721SoulboundToken.sol` file imports [`IERC721SoulboundEvents.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundToken.sol#lines-10) which is [already imported](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-7) as a result of importing [`IERC721Soulbound.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundToken.sol#lines-4).
*   The `IERC721Token.sol` file imports [`IERC721Events.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Token.sol#lines-10) which is [already imported](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-7) as a result of importing [`IERC721.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Token.sol#lines-4).

Consider removing any duplicate imports to improve the overall clarity and readability of the codebase.

_**Update:** Resolved in [pull request #9](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/9) at commit [b8bd4e8](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/b8bd4e8140daef5e93d8fe3c7757b8d7eb7b848b). The team stated:_

> _Implemented auditors' recommendations by removing duplicate imports of various interfaces across the codebase._

### Use Custom Errors

Since Solidity version 0.8.4, custom errors provide a cleaner and more cost-efficient way to explain to users why an operation failed.

Throughout the codebase, multiple instances of `revert` and/or `require` messages were identified:

*   In lines [20](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/proxies/Beacon.sol#lines-20) and [30](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/proxies/Beacon.sol#lines-30) of `Beacon.sol`
*   In lines [97](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-97:100), [119](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-119), [120](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-120), [121](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-121), [122](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-122), [124](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-124:127), [129](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-129), [162](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-162), [170](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-170), [199](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-199), [229](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-229), [764](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-764), and [889](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-889) of `ERC721BasicToken.sol`
*   In lines [91](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-91:94), [113](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-113) [114](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-114) [115](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-115), [116](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-116), [118](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-118:121), [123](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-123), [156](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-156), [164](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-164), [227](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-227), [235](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-235), [304](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-304), [316](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-316), [329](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-329), [341](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-341), [353](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-353), [366](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-366), [380](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-380), [563](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-563), and [713](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-713) of `ERC721SoulboundToken.sol`
*   In lines [87](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-87:90), [100](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-100), [115](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-115), [116](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-116), [118](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-118), [119](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-119), [151](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-151), [159](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-159), [172](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-172), [173](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-173), [174](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-174), [179](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-179:182), [185](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-185:188), [191](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-191:194), [198](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-198), [215](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-215), [236](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-236), [253](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-253:256), [257](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-257:260), [286](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-286), and [359](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-359) of `WhitelistComplianceOracle.sol`

For conciseness and gas savings, consider replacing `require` and `revert` messages with custom errors.

_**Update:** Resolved in [pull request #10](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/10) at commit [521ea7f](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/521ea7fff657b864b7175204be8edcfda8518fa2) and commit [a80fbd3](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/a80fbd3aa7ee6b47c34e240b7812e5f6666e96fe). The team stated:_

> _Implemented auditors' recommendations by replacing `require` and `revert` messages with custom errors across the codebase._

### Missing Docstrings

Throughout the codebase, multiple instances of missing docstrings were identified:

*   In `Beacon.sol`, the [`Upgraded` event](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/proxies/Beacon.sol#lines-17), the [`implementation` function](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/proxies/Beacon.sol#lines-35:37), and the [`upgradeTo` function](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/proxies/Beacon.sol#lines-39:41)
*   In `ERC721SoulboundToken.sol`, the [`safeMint` function](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-182:185) and the [`burn` function](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-187:189)
*   In `IOracle.sol`, the [`OracleDisabled` event](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/interfaces/IOracle.sol#lines-10), the [`OracleEnabled` event](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/interfaces/IOracle.sol#lines-11), the [`IOracleBeaconUpgrade` interface](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/interfaces/IOracleBeaconUpgrade.sol#lines-4:9), and the [`upgradeBeaconToAndCall` function](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/interfaces/IOracleBeaconUpgrade.sol#lines-5:8)

Consider thoroughly documenting all functions (and their parameters) that are part of any contract's public API. Functions implementing sensitive functionality, even if not public, should be clearly documented as well. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in [pull request #11](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/11) at commit [6c4e527](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/6c4e527fe654a252834da636f3e0683598e6ad4f). The team stated:_

> _Implemented auditors' recommendations by adding missing docstrings using natspec across codebase._

### Incorrect Docstrings

Throughout the codebase, multiple instances of incorrect docstrings were identified:

*   The comments in the [`IERC721Soulbound`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-12:148) interface are incorrect as they reference a standard ERC-721 token contract instead of the intended soulbound token implementation.
*   The comments for the `initializeWithRoles` function within the [`IERC721TokenInit`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721TokenInit.sol#lines-9:17) and [`IERC721SoulboundTokenInit`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundTokenInit.sol#lines-9:17) interfaces are incorrect. Specifically, they assert that the `ISSUER_ROLE` is designated for the issuance of new tokens, which is misleading and not the case.

Consider thoroughly documenting all functions that are part of a contract's public API. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in [pull request #12](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/12) at commit [86ef758](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/86ef758197440f2242eb5220f2b3ce82b65c23c5). The team stated:_

> _Implemented auditors' recommendations by updating incorrect docstrings with correct natspec._

### Predictable Storage Slot Preimage

The contracts store state variables using the `StorageSlot` library, which stores values in unique slots. The issue with this approach is that the slot has a known preimage for the used `keccak256`. This could lead to problems if the contracts utilizing the `StorageSlot` library grow in functionality and complexity, and contain issues that allow the attacker to write to a storage slot of their choosing.

Consider subtracting 1 from the resulting `keccak256` value.

_**Update:** Acknowledged, not resolved. The team stated:_

> _Acknowledged, we understand this is a reasonable precaution for future codebases/modifications, however, the existing logic will no longer access the previously stored data if we upgrade our existing implementation contracts to use this new slot calculation. Unless we manually migrate the state from the old slots to the new ones, our Proxy contracts will effectively “lose” the stored data. While the intent is to make it computationally infeasible for an attacker to determine a slot’s preimage, doing so in an upgrade would break backward compatibility within our protocol at this time. In our current state, no logic allows writing to these slots maliciously, thus this risk is very low. Switching the existing scheme for our protocol would be a breaking change with a significant risk of losing state data unless we carefully plan and execute a storage migration._

### Token URL Cannot Be Set for Non-Existing Tokens

The `setTokenURI` functions of the [`ERC721BasicToken`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-229) and [`ERC721SoulboundToken`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-227) contracts do not allow setting the URI for a non-existent `tokenId`. This prohibits using these contracts with a common use case in which `tokenId` metadata is set even before minting the corresponding token.

Consider lifting this restriction to not limit the flexibility of the `ERC721BasicToken` and `ERC721SoulboundToken` contracts.

_**Update:** Acknowledged, not resolved. The team stated:_

> _We acknowledge this finding. This restriction was intentional, it is a functionality we don't need to utilize in our current product scope and can be upgraded as required._

### Discrepancies Between Interfaces and Contracts

Throughout the codebase, multiple instances of discrepancies between interfaces and implementation contracts were identified:

*   In the `IERC721` interface, the `setTokenURI` function uses the parameter name [`tokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-110), whereas, the implementation uses [`tokenURI_`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-228).
*   In the `IERC721` interface, the `setBaseURI` function uses the parameter name [`baseURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-117), whereas, the implementation uses [`baseURI_`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-219).
*   In the `IERC721Soulbound` interface, the `setTokenURI` function uses the parameter name [`tokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-61), whereas, the implementation uses [`tokenURI_`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-226).
*   In the `IERC721Soulbound` interface, the `setBaseURI` function uses the parameter name [`baseURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-68), whereas, the implementation uses [`baseURI_`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-219).
*   In the `IERC165` interface, the `supportsInterface` function uses the parameter name [`interfaceId`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/common/interfaces/IERC165.sol#lines-13), whereas, the [`WhitelistComplianceOracle`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-331), [`ERC721BasicToken`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-442), and [`ERC721SoulboundToken`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-390) implementation contracts use `interfaceID`.

Consider aligning parameter names and storage location keywords between interfaces and their implementation contracts to ensure consistency and reduce potential errors.

_**Update:** Resolved in [pull request #13](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/13) at commit [9ccc869](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/9ccc86924c07393f92092b1b3c303f7e64dc19be). The team stated:_

> _Implemented auditors' recommendations by aligning parameter names and storage keywords in interfaces with their implementation contracts._

### Non-Explicit Imports Are Used

The use of non-explicit imports in the codebase can decrease code clarity and may create naming conflicts between locally defined and imported variables. This is particularly relevant when multiple contracts exist within the same Solidity file or when inheritance chains are long.

Throughout the codebase, multiple instances of non-explicit imports were identified:

*   The import in [`Beacon.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/proxies/Beacon.sol#lines-4:6), [`ERC721BasicToken.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-4:8), [`ERC721SoulboundToken.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-4:8), and [`WhitelistComplianceOracle.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-4:11)
*   The imports in [`IERC721Token.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Token.sol#lines-4:14), [`IERC721SoulboundToken.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundToken.sol#lines-4:14), and [`IWhitelistComplianceOracle.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/interfaces/IWhitelistComplianceOracle.sol#lines-4:7)
*   The imports in [`IERC1155.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc1155/IERC1155.sol#lines-6), [`IERC721.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-6:7), [`IERC721Enumerable.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Enumerable.sol#lines-6), [`IERC721Metadata.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Metadata.sol#lines-6), [`IERC721Soulbound.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-6:7), [`IERC721SoulboundEnumerable.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundEnumerable.sol#lines-6), [`IERC721SoulboundMetadata.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundMetadata.sol#lines-6), and [`IWhitelistOracle.sol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/interfaces/IWhitelistOracle.sol#lines-4)

Following the principle that clearer code is better code, consider using the named import syntax _(`import {A, B, C} from "X"`)_ to explicitly declare which contracts are being imported.

_**Update:** Resolved in [pull request #14](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/14) at commit [906e1b2](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/906e1b2a07b9f1c2e75db529e3599100546929cb) and commit [32317ad](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/32317ada3e83307d7a016e9145920e91a80fd279). The team stated:_

> _Implemented auditors' recommendations by converting imports into more explicitly named imports._

### Unused `internal` Functions

Throughout the codebase, multiple instances of unused `internal` functions were identified:

*   The [`_increaseBalance`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-463:468) and [`_increaseBalanceVanila`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-480:484) functions in `ERC721BasicToken.sol`
*   The [`_increaseBalance`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-463:468) and [`_increaseBalanceVanila`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-480:484) functions in `ERC721SoulboundToken.sol`

To improve the overall clarity, intentionality, and readability of the codebase, consider using or removing any currently unused functions.

_**Update:** Acknowledged, not resolved. The team stated:_

> _Acknowledged. The `_increaseBalance` and `_increaseBalanceVanila` functions are internal utility functions that are part of the ERC721 token implementation pattern. They serve specific purposes: `_increaseBalance` is a safety wrapper that prevents batch minting in enumerable tokens. `_increaseBalanceVanila` is the actual balance increase implementation These functions are actually used indirectly through the `_update` and `_updateVanila` functions, which are called during minting and transferring operations. However, they are called through a different code path than direct usage. Public functions like `safeMint`, `transferFrom` call `_update` which calls `_updateVanila` that modifies balances directly using similar logic as `_increaseBalanceVanila`. The reason these functions exist is to provide a hook point for extensions that "mint" tokens using an `ownerOf` override. They are currently not being used within the current implementation but we would like to keep them as they provide extension points for future functionality. We have added extra natspec to these functions explaining this in [pull request #15](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/15)._

### Inconsistent Order Within Contracts

Throughout the codebase, multiple instances of contracts having an inconsistent ordering of functions were identified:

*   The [`Beacon` contract](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/proxies/Beacon.sol)
*   The [`WhitelistComplianceOracle` contract](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol)

To improve the project's overall legibility, consider standardizing ordering throughout the codebase as recommended by the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-layout) ([Order of Functions](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-functions)).

_**Update:** Resolved in [pull request #16](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/16) at commit [6b471d6](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/6b471d66e8d74af9ae441f1b6c716730e513c30d). The team stated:_

> _Implemented auditors' recommended fixes by re-ordering functions more closely to the Solidity Style Guide._

### Function Visibility Overly Permissive

Throughout the codebase, multiple instances of functions with unnecessarily permissive visibility were identified:

*   The [`implementation`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/proxies/Beacon.sol#lines-35:37) function in `Beacon.sol` with `public` visibility could be limited to `external`.
*   The [`setBaseURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-219:222), [`setTokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-228:232), [`approve`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-238:240), [`setApprovalForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-247:249), [`safeTransferFrom`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-284:290), [`safeMint`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-330:333), [`batchSafeMint`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-339:345), [`burn`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-359:361), [`batchBurn`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-367:372), [`ownerOf`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-387:389), [`tokenOfOwnerByIndex`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-394:399), [`tokenByIndex`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-411:416), [`getApproved`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-422:425), and [`supportsInterface`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-442:458) functions in `ERC721BasicToken.sol` with `public` visibility could be limited to `external`.
*   The [`safeMint`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-182:185), [`burn`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-187:189), [`batchSafeMint`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-195:201), [`batchBurn`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-207:212), [`setBaseURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-219:221), [`setTokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-226:229), [`tokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-234:243), [`ownerOf`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-258:260), [`tokenOfOwnerByIndex`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-265:270), [`tokenByIndex`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-282:287), [`safeTransferFrom`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-298:305), [`approve`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-312:317), [`setApprovalForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-325:330), [`getApproved`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-338:342), [`isApprovedForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-349:354), [`transferFrom`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-361:367), [`safeTransferFrom`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-375:381), and [`supportsInterface`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-390:404) functions in `ERC721SoulboundToken.sol` with `public` visibility could be limited to `external`.
*   The [`supportsInterface`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-331:339) function in `WhitelistComplianceOracle.sol` with `public` visibility could be limited to `external`.

To better convey the intended use of functions and to potentially realize some additional gas savings, consider changing a function's visibility to be only as permissive as required.

_**Update:** Resolved in [pull request #17](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/17) at commit [e69bc2d](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/e69bc2dbfa52932df8751a830a7e1d2514891e5c). The team stated:_

> _Implemented auditors' recommended fix by changing function visibility to be only as permissive as required across the codebase._

### Incomplete Docstrings

Throughout the codebase, multiple instances of incomplete docstrings were identified:

*   In `ERC721BasicToken.sol`:
    
    *   For the [`name`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-177:179), [`symbol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-184:186), [`baseURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-191:193), [`tokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-198:211), [`totalSupply`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-404:406), [`getApproved`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-422:425), and [`isApprovedForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-431:433) functions, not all return values are documented.
    *   For the [`tokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-198:211), [`setTokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-228:232), [`approve`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-238:240), [`transferFrom`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-255:269), [`getApproved`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-422:425), [`setApprovalForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-247:249), [`batchSafeMint`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-339:345), [`batchBurn`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-367:372), and [`isApprovedForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-431:433) functions, the parameters are not documented.
*   In `ERC721SoulboundToken.sol`:
    
    *   For the [`name`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-171:173) and [`symbol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-178:180) functions, the return values are not documented.
    *   For the [`batchSafeMint`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-195:201), [`batchBurn`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-207:212), [`setBaseURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-219:221), [`setTokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-226:229), [`tokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-234:243), and [`setTokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-226:229) functions, the parameters are not documented.
*   In `WhitelistComplianceOracle.sol`:
    
    *   For the [`canTransfer`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-278:288) function, not all return values are documented.
    *   For the [`addContractAddress`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-167:207), [`removeContractAddress`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-213:230), and [`canTransfer`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-278:288) functions, the parameters are not documented.
*   In `IERC1155.sol`:
    
    *   For the [`setApprovalForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc1155/IERC1155.sol#lines-22), [`safeTransferFrom`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc1155/IERC1155.sol#lines-42:48), [`safeBatchTransferFrom`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc1155/IERC1155.sol#lines-66:72), [`balanceOf`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc1155/IERC1155.sol#lines-81), [`balanceOfBatch`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc1155/IERC1155.sol#lines-90:93), and [`isApprovedForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc1155/IERC1155.sol#lines-100) functions, the parameters and return values are not documented.
*   In `IERC721.sol`:
    
    *   For the [`balanceOf`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-122), [`ownerOf`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-131), [`getApproved`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-140), and [`isApprovedForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-147) functions, the return values are not documented.
    *   For the [`safeTransferFrom`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-27:32), [`safeTransferFrom`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-50:54), [`transferFrom`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-72:76), [`approve`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-91), [`setApprovalForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-103), [`balanceOf`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-122), [`ownerOf`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-131), [`getApproved`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-140), and [`isApprovedForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721.sol#lines-147) functions, the parameters are not documented.
*   In `IERC721Enumerable.sol`:
    
    *   For the [`totalSupply`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Enumerable.sol#lines-16), [`tokenOfOwnerByIndex`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Enumerable.sol#lines-22), and [`tokenByIndex`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Enumerable.sol#lines-28) functions, the return values are not documented.
    *   For the [`tokenOfOwnerByIndex`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Enumerable.sol#lines-22) and [`tokenByIndex`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Enumerable.sol#lines-28) functions, the parameters are not documented.
*   In `IERC721Events.sol`:
    
    *   For the [`Transfer`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Events.sol#lines-13), [`Approval`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Events.sol#lines-18), [`ApprovalForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Events.sol#lines-23), [`BaseURIUpdated`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Events.sol#lines-28), and [`TokenURIUpdated`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Events.sol#lines-33) events, the parameters are not documented.
*   In `IERC721Metadata.sol`:
    
    *   For the [`name`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Metadata.sol#lines-16), [`symbol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Metadata.sol#lines-21), and [`baseURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Metadata.sol#lines-26) functions, not all return values are documented.
    *   For the [`tokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Metadata.sol#lines-31) function, the parameter is not documented.
*   In `IERC721Receiver.sol`:
    
    *   For the [`onERC721Received`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721/IERC721Receiver.sol#lines-22:27) function, the parameters and return value are documented.
*   In `IERC721Soulbound.sol`:
    
    *   For the [`balanceOf`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-73) and [`ownerOf`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-82) functions, not all return values are documented.
    *   For the [`safeTransferFrom`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-27:32), [`safeTransferFrom`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-50:54), [`balanceOf`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-73), [`ownerOf`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-82), [`transferFrom`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-100:104), [`approve`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-119), [`getApproved`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-140), [`setApprovalForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-131), and [`isApprovedForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721Soulbound.sol#lines-147) functions, the parameters are not documented.
*   In `IERC721SoulboundEnumerable.sol`:
    
    *   For the [`totalSupply`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundEnumerable.sol#lines-16) and[`tokenOfOwnerByIndex`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundEnumerable.sol#lines-22) functions, not all return values are documented.
    *   For the [`tokenOfOwnerByIndex`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundEnumerable.sol#lines-22) and[`tokenByIndex`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundEnumerable.sol#lines-28) functions, the parameters are not documented.
*   In `IERC721SoulboundEvents.sol`:
    
    *   The parameters of [`Transfer`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundEvents.sol#lines-13), [`Approval`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundEvents.sol#lines-18), and [`ApprovalForAll`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundEvents.sol#lines-23) events are not documented.
*   In `IERC721SoulboundMetadata.sol`:
    
    *   For the [`name`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundMetadata.sol#lines-16), [`symbol`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundMetadata.sol#lines-21), and [`tokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundMetadata.sol#lines-26) functions, not all return values are documented.
    *   For the [`tokenURI`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundMetadata.sol#lines-26) function, the parameter is not documented.
*   In `IERC721SoulboundReceiver.sol`:
    
    *   For the [`onERC721Received`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/interfaces/erc721Soulbound/IERC721SoulboundReceiver.sol#lines-22:27) function, the parameters and the return value are not documented.

Consider thoroughly documenting all functions/events (and their parameters or return values) that are part of a contract's public API. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in [pull request #18](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/18) at commit [ec85574](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/ec855743284067fd0c5213a9ca2593cd978155c7). The team stated:_

> _Implemented auditors' recommended fix by adding more comprehensive and complete docstrings using NatSpec across the codebase._

### Gas Optimizations

Throughout the codebase, multiple opportunities for gas optimization were identified:

*   The `upgradeBeaconToAndCall` functions within the [`ERC721BasicToken`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-168), [`ERC721SoulboundToken`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-162), and [`WhitelistComplianceOracle`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-157) contracts read the beacon address from `_BEACON_SLOT` storage after setting its value to `newBeacon`. This results in an unnecessary storage read. Instead, `newBeacon` can be used to retrieve the implementation address directly.
    
*   Consider using the prefix-increment operator (`++i`) instead of the postfix-increment operator (`i++`) in order to save gas. This optimization skips storing the value before the incremental operation, as the return value of the expression is ignored.
    
    *   Within the [`batchSafeMint`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-341) and [`batchBurn`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721BasicToken.sol#lines-369) functions of the `ERC721BasicToken` contract.
    *   Within the [`batchSafeMint`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-197) and [`batchBurn`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/tokens/ERC721/ERC721SoulboundToken.sol#lines-209) functions of the `ERC721SoulboundToken` contract.
    *   In the [`i++`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-299), [`j++`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-303), and [`i++`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-317) increments of the [`removeContractAddress`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-221), [`isAddressWhitelisted`](https://bitbucket.org/wisdomtreeam/whitelist-contexts/src/44760785af1696704cdfcc56c2ba4a17ff603fb5/src/oracles/whitelist-compliance/WhitelistComplianceOracle.sol#lines-369), and `getContractAddresses` functions in `WhitelistComplianceOracle.sol`.

_**Update:** Resolved in [pull request #19](https://bitbucket.org/wisdomtreeam/whitelist-contexts/pull-requests/19) at commit [554ed97](https://bitbucket.org/wisdomtreeam/whitelist-contexts/commits/554ed97cbd8c3f09887462c5f25f0d5276a01410). The team stated:_

> _Implemented auditors' recommendations by applying gas optimization by reducing direct storage read and using a prefix-increment operator for loops._

Conclusion
----------

The Whitelist Oracle system provides a compliance framework that enables token standards such as ERC-721 and ERC-1155, as well as external oracle contracts, to authenticate transfers. During the audit, several minor issues were identified, and recommendations for improving code consistency, readability, and gas efficiency were accordingly made.

In addition, it was noted that during the audit, the branch coverage for the codebase was approximately 58%, with the coverage of key components (ERC-721 Tokens and Whitelist Compliance Oracle) ranging between 60% and 68%. It was recommended to strengthen the test suite and incorporate fuzz testing to enhance the maturity of the codebase. After the audit, the team significantly improved the test suite and reached branch coverage of 80-82% for the core components. The WisdomTree Digital team was highly cooperative and provided clear explanations throughout the audit process.

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