\- August 26, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

**Type:** DeFi/Stablecoin  
**Timeline:** March 27, 2025 → May 5, 2025**Languages:** Solidity

**Findings**Total issues: 46 (5 resolved)  
Critical: 1 (1 resolved) · High: 2 (2 resolved) · Medium: 7 (2 resolved) · Low: 13 (0 resolved)

**Notes & Additional Information**23 notes raised (0 resolved)

Scope
-----

OpenZeppelin audited the [UMAprotocol/managed-oracle](https://github.com/UMAprotocol/managed-oracle) repository at commit [fc03083](https://github.com/UMAprotocol/managed-oracle/tree/fc03083eca91c880efa8918c6d9532af9362f00d). The files that were diff-audited were compared against their versions present in the [UMAprotocol/protocol](https://github.com/UMAprotocol/protocol) repository at commit [6a23be1](https://github.com/UMAprotocol/protocol/blob/6a23be19d8a0dbee4475db9ff52ce4d9572212b5).

In scope were the following files:

`src
├── common
│   ├── implementation
│   │   ├── AddressWhitelist.sol (diff)
│   │   └── DisableableAddressWhitelist.sol
│   └── interfaces
│       └── DisableableAddressWhitelistInterface.sol
└── optimistic-oracle-v2
    └── implementation
        ├── ManagedOptimisticOracleV2.sol
        └── OptimisticOracleV2.sol (diff)` 

The final state of the audited codebase, including all implemented resolutions, is reflected in commit [5b33321](https://github.com/UMAprotocol/managed-oracle/commit/5b333218c137403e11b8742dc4567d3d4b8162e3).

System Overview
---------------

The UMA Optimistic Oracle protocol is designed for the efficient and rapid resolution of data requests on-chain. It operates on a "propose and dispute" model, whereby a proposed value is accepted as true after a set "liveness" period, provided no one challenges it. A proposer stakes a bond to submit a price, and if another party believes that the price is incorrect, they can also stake a bond to dispute it.

An undisputed proposal is settled optimistically, rewarding the proposer, while a disputed price is escalated to UMA's Data Verification Mechanism (DVM) for ultimate resolution, which then determines the winner and allocates the bonds and rewards accordingly. This core protocol is extended by the `ManagedOptimisticOracleV2`, which introduces a layer of administrative control, allowing designated managers to customize parameters like bond sizes and liveness periods for specific requests.

### New Contracts

The `ManagedOptimisticOracleV2` contract implements a multi-tiered, role-based access-control system to govern the oracle's operational parameters. At the highest level, the `DEFAULT_ADMIN_ROLE` holds the exclusive authority to upgrade the contract's implementation. Below this, the `REGULAR_ADMIN` role is responsible for managing system-wide settings, which includes configuring the default proposer and requester whitelists, and setting constraints such as the maximum bond and minimum liveness period. The contract also introduces a `REQUEST_MANAGER` role, which is managed by the `REGULAR_ADMIN`. This role has the ability to apply custom configurations to individual price requests, allowing it to override default parameters by setting specific bond amounts, liveness periods, and proposer whitelists on a per-request basis.

The `DisableableAddressWhitelist` contract extends the base `AddressWhitelist` contract by introducing a mechanism to toggle its enforcement. When enforcement is disabled, all addresses are considered whitelisted, effectively bypassing the underlying whitelist checks.

### Diff Changes

The `AddressWhitelist` contract was updated to ensure compatibility with the latest OpenZeppelin version and to improve its extensibility for inheriting contracts. The `OptimisticOracleV2` contract was refactored to support upgradeability using the UUPS proxy pattern, and several of its functions have been made virtual to allow for extension by child contracts like `ManagedOptimisticOracleV2`. This refactoring also modernized the code by replacing the `SafeMath` library with Solidity's native overflow protection.

Security Model and Trust Assumptions
------------------------------------

As mentioned above, the `ManagedOptimisticOracleV2` contract involves multiple roles, and the security model of this system relies on a layered approach to access control and a set of critical trust assumptions regarding its administrators and configurations. The entities in charge of these roles are expected to follow best practices for account security, including robust key management and multi-factor authentication where applicable. The integrity and proper functioning of the protocol are contingent upon these assumptions always holding true.

*   It is assumed that entities holding the `DEFAULT_ADMIN_ROLE`, `REGULAR_ADMIN`, and `REQUEST_MANAGER` roles operate in the best interest of the protocol and its users. The owner of the `AddressWhitelist` and `DisableableAddressWhitelist` contracts is trusted to manage the whitelist entries and enforcement status appropriately.
*   The proper setup and ongoing maintenance of the `requesterWhitelist`, `defaultProposerWhitelist`, and any `customProposerWhitelists` are critical for controlling access and participation.
*   The `DisableableAddressWhitelist` mechanism's `isEnforced` state is assumed to be managed correctly and in accordance with the desired access policies.
*   The whitelists used in the `ManagedOptimisticOracleV2` contract are expected to match the implementation of the `DisableableAddressWhitelist` contract.
*   Proposers and disputers must trust the requester's on-chain contract to honestly handle callbacks triggered by state transitions in the price request lifecycle. These callbacks can give the requester the ability to denial-of-service (DoS) transitions such as dispute or settlement.

Low Severity
------------

### Currencies Do Not Accept a Bond By Default

The [`ManagedOptimisticOracleV2`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol) contract introduces per-currency maximum bond amounts that are stored in the [`maximumBonds` mapping](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L107). These limits can be set either during initialization by the [contract initializer](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L132) or later by an [authorized admin](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L198C4-L200C6). If no maximum bond is explicitly set for a given currency, the mapping returns its default value of zero. As a result, any non-zero bond passed to the contract will fail validation via the [`_validateBond()`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L474C5-L476C6) function, effectively preventing the usage of that currency until configured.

If this behavior is intentional, consider clearly documenting it in both the code and user-facing documentation. Alternatively, instead of defaulting to rejection, consider changing the logic such that currencies with unset maximum bond values have no enforced limit.

_**Update:** Resolved in [pull request #22](https://github.com/UMAprotocol/managed-oracle/pull/22) at commit [ab33c3e](https://github.com/UMAprotocol/managed-oracle/pull/22/commits/ab33c3eed39c0f9dcf40ef1c595cddb11975080a). The UMA team added two comments to clarify the default rejection of a currency when no bond range is configured._

### The `RequestManagerAdded` and `RequestManagerRemoved` Events Can Be Wrongfully Emitted

The [`addRequestManager`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L177C4-L180C6) and [`removeRequestManager`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L187C4-L190C6) functions of the [`ManagedOptimisticOracleV2` contract](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol) are responsible for assigning and revoking the `REQUEST_MANAGER` role and are implemented through the `grantRole` and `revokeRole` functions of `AccessControlUpgradeable`.

These functions also emit the `RequestManagerAdded` and `RequestManagerRemoved` events unconditionally, regardless of whether the role was actually granted or revoked. This means that if `addRequestManager` is called for an address that already has the `REQUEST_MANAGER` role, or `removeRequestManager` is called for an address that does not, the corresponding event will still be emitted, which could be misleading for off-chain services that rely on these events to track state changes. Furthermore, these events are redundant, considering the fact that the `AccessControlUpgradeable` contract already emits the `RoleGranted` and `RoleRevoked` events.

Consider removing the `RequestManagerAdded` and `RequestManagerRemoved` events entirely.

_**Update:** Resolved in [pull request #23](https://github.com/UMAprotocol/managed-oracle/pull/23) at commit [46774d9](https://github.com/UMAprotocol/managed-oracle/pull/23/commits/46774d9ebba77616a2802cca960e43052934e397)._

### Missing Interface Validation for Whitelist Contracts

The [`ManagedOptimisticOracleV2`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol) contract includes several functions that accept external contract addresses expected to implement the `DisableableAddressWhitelistInterface`, such as the [`setDefaultProposerWhitelist`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L216), [`setRequesterWhitelist`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L225), and [`requestManagerSetProposerWhitelist`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L304) functions. However, these functions do not verify whether the provided addresses actually implement the expected interface, which can result in runtime errors or incorrect behavior if an invalid contract is passed.

Consider supporting the [ERC-165 standard](https://eips.ethereum.org/EIPS/eip-165) in both the `AddressWhitelist` and `DisableableAddressWhitelist` contracts to facilitate safe and standardized interface detection. In addition, consider enforcing interface compliance through runtime checks to ensure that the provided whitelist contracts implement the `DisableableAddressWhitelistInterface`.

_**Update:** Resolved in [pull request #17](https://github.com/UMAprotocol/managed-oracle/pull/17) at commit [7bb517c](https://github.com/UMAprotocol/managed-oracle/pull/17/commits/7bb517c71a94bd6d2aef2b661efb3e0e79de75dd). The `DisableableAddressWhitelist` contract was replaced with `DisabledAddressWhitelist`, thereby changing the implementation from an owner-controlled toggle for the enforcement of the list to a hard-coded implementation that can be set in the `ManagedOptimisticOracleV2` contract. Both the `DisabledAddressWhitelist` and `AddressWhitelist` contract now extend `ERC165` while `ManagedOptimisticOracleV2` performs runtime checks whenever a whitelist is set._

### Missing Test Suite

The in-scope contracts, including [`OptimisticOracleV2`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol) and [`ManagedOptimisticOracleV2`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol), implement a sophisticated system for managing optimistic price requests. This system involves complex state transitions, financial stakes in the form of bonds, and a multi-layered access-control model. As such, the security and reliability of dependent protocols are critically reliant on the correctness of this logic.

Throughout the repository, there is an absence of a dedicated test suite for the contracts in scope. Without automated tests, there is no formal, repeatable process to verify that the contracts function as intended. Verifying the correctness of the intricate state machine, access-control logic, and financial calculations is left to manual review, which is error-prone and time-consuming. Furthermore, the lack of a regression suite means that future changes to the codebase could inadvertently introduce critical vulnerabilities without being detected.

Consider implementing a comprehensive test suite that covers the functionality of the scoped contracts. This suite should include unit tests for individual functions, integration tests to validate the interactions between contracts, and fork tests to simulate behavior in a realistic on-chain environment. The tests should validate expected outcomes, proper handling of edge cases, and adherence to the access control model. Establishing robust test coverage would significantly improve the maintainability and security posture of the system.

_**Update:** Resolved in [pull request #25](https://github.com/UMAprotocol/managed-oracle/pull/25) at commit [31b47fd](https://github.com/UMAprotocol/managed-oracle/pull/25/commits/31b47fd090ee0eb1b201debf31ace1cf99e44d39). Tests for the `ManagedOptimisticOracleV2` contract were added._

### Problematic Whitelist Implementation

The [`AddressWhitelist` contract](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/common/implementation/AddressWhitelist.sol) provides functionality for managing lists of approved addresses. It uses a mapping to store the status of an address and a separate, dynamic array, `whitelistIndices`, to store every address ever added. The `getWhitelist` function iterates through this array to return a list of currently active members.

The current implementation of the whitelist has several drawbacks:

*   The [`removeFromWhitelist` function](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/common/implementation/AddressWhitelist.sol#L55) only changes the status of an address to `Out` but does not remove it from the `whitelistIndices` array. This "soft delete" causes the array to grow indefinitely, leading to an increasing gas cost for enumeration.
*   The [`getWhitelist` function](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/common/implementation/AddressWhitelist.sol#L79) iterates through this ever-growing array twice, making it highly inefficient and creating a potential out-of-gas condition if the list becomes too large, as [commented](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/common/implementation/AddressWhitelist.sol#L73-L76).
*   The usage of the three statuses (`None`, `Out`, and `In`) is not only redundant compared to only two (`Out` and `In`), it also introduces an inconsistent state. First, if an address is removed from the whitelist despite having never been added, its [status is set](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/common/implementation/AddressWhitelist.sol#L57) to `Out`. Second, if the address is then added to the whitelist, the address [is **not** added](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/common/implementation/AddressWhitelist.sol#L41-L44) to `whitelistIndices` but still marked as `In` with an event emitted, although the address will not be included in `getWhitelist`.
*   Since the project already utilizes the OpenZeppelin Contracts library, this custom implementation also introduces redundant code, as a more robust and gas-efficient alternative is already available in the [`EnumerableSet`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.4.0/contracts/utils/structs/EnumerableSet.sol) library.

Consider refactoring the `AddressWhitelist` contract to use the [`EnumerableSet.AddressSet`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.4.0/contracts/utils/structs/EnumerableSet.sol#L307) library provided by OpenZeppelin. Be aware that this adoption would shift the storage layout. As such, upgradeable contracts depending on `AddressWhitelist` should be handled with care.

_**Update:** Resolved in [pull request #24](https://github.com/UMAprotocol/managed-oracle/pull/24) at commit [81bd067](https://github.com/UMAprotocol/managed-oracle/pull/24/commits/81bd0679fae07e1da3d3dfa66afca31f428334ff)._

### Minimum Liveness Can Be Set Beyond Valid Bounds

The [`setMinimumLiveness` function](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L207) of the `ManagedOptimisticOracleV2` contract allows the admin to set a new global minimum liveness without validating that the value falls within the bounds enforced by the underlying `OptimisticOracleV2`. If `minimumLiveness` is set above the maximum value accepted by `OptimisticOracleV2,` subsequent attempts of a [requester](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol#L244C5-L256C6) or [request manager](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L284C5-L294C6) to set custom liveness values will fail, resulting in a DoS for that functionality.

While this scenario is unlikely to materialize in practice, as it requires a misconfigured call from a privileged admin, the risk can be fully mitigated by adding validation. Thus, consider updating the `_setMinimumLiveness` function to enforce that the new value respects the bounds accepted by `OptimisticOracleV2`, preventing any accidental misconfiguration.

_**Update:** Resolved in [pull request #7](https://github.com/UMAprotocol/managed-oracle/pull/7) at commit [bd0fe60](https://github.com/UMAprotocol/managed-oracle/pull/7/commits/bd0fe60b6c72225147ff0a6b3e6d0ad0f496017e)._

Notes & Additional Information
------------------------------

### Use of Storage Gaps for Upgradeability

The [`OptimisticOracleV2.sol` contract](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol) is designed to be upgradeable and currently uses the storage gap pattern (`uint256[998] private __gap;`) to reserve space for future state variables. This is a widely used technique to prevent storage collisions in child contracts when the parent contract is upgraded with new variables.

However, while functional, the storage gap pattern is a manual and somewhat opaque method for managing upgradeability. It does not provide a clear, structured approach for how storage should be organized, especially in contracts with complex inheritance. This can make reasoning about the overall storage layout difficult for developers and auditors.

Consider adopting the namespaced storage pattern defined in [EIP-7201](https://eips.ethereum.org/EIPS/eip-7201). This standard provides a robust and explicit convention for managing storage layouts in upgradeable contracts. By grouping related state variables into structs and assigning them a unique, deterministic storage location based on a namespace ID, EIP-7201 makes the storage layout modular and easier to understand. Adopting this standard would improve the long-term maintainability and developer ergonomics of the contract's upgradeability strategy.

_**Update:** Acknowledged, not resolved. The team stated:_

> _This is a pretty involved change and will break storage assumptions of the contracts already deployed (since last week) which are still using `__gap` instead. Thanks for bringing this up though, we will consider using this pattern in future contracts._

### Inconsistent Use of Re-entrancy Guard on `view` Functions

Throughout the `OptimisticOracleV2` contract, `external view` functions such as [`getRequest`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol#L529) and [`getState`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol#L547) are protected with the [`nonReentrantView` modifier](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/common/implementation/Lockable.sol#L38). This modifier prevents these functions from being called back into during the execution of a state-changing function, ensuring that they cannot read from a temporarily inconsistent state.

In the `ManagedOptimisticOracleV2` contract, new `external view` functions have been introduced, namely [`getCustomProposerWhitelist`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L362) and [`getProposerWhitelistWithEnforcementStatus`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L381). However, these functions, do not use the `nonReentrantView` modifier. This creates an inconsistency with the established security pattern of the parent contract. While no direct exploit was identified from this omission due to robust state checks elsewhere, it represents a deviation from parent contract.

Consider adding the `nonReentrantView` modifier to all new `external` `view` functions in `ManagedOptimisticOracleV2`. This would enforce a consistent security posture across the entire contract system, improve clarity for developers and auditors, and harden the contract against potential re-entrancy vectors that could arise from future integrations.

_**Update:** Resolved in [pull request #28](https://github.com/UMAprotocol/managed-oracle/pull/28) at commit [77b6f82](https://github.com/UMAprotocol/managed-oracle/pull/28/commits/77b6f8267718ad20bdcc7fdaa0a090ba7794f486)._

### Code Improvement Opportunities

Throughout the codebase, multiple opportunities for code improvement were identified:

*   To save gas at deployment and reduce the code size, consider combining the [`_getManagedRequestId`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L460C4-L467C1) and [`getManagedRequestId`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L402C4-L409C1) functions into a single, `public` version.
*   The [`ManagedOptimisticOracleV2Events`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L18) and [`ManagedOptimisticOracleV2`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L53) contracts are redundantly split and do not improve legibility as they exist within the same file. Consider moving the `ManagedOptimisticOracleV2Events` contract into a separate file, or simply removing it and adding the events directly in the `ManagedOptimisticOracleV2` contract.
*   There are several casts to `address` that are redundant, such as [the conversion of `msg.sender`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L248) in the `requestPrice` function, or the conversions of `requester` in the [`proposePriceFor`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol#L366), [`disputePriceFor`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol#L457), and [`_settle`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol#L652) functions. Consider removing these unnecessary casts.
*   The codebase does not make use of [named mapping parameters](https://soliditylang.org/blog/2023/02/01/solidity-0.8.18-release-announcement/), neither [in the `AddressWhitelist` contract](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/common/implementation/AddressWhitelist.sol#L18) nor [in the`ManagedOptimisticOracleV2` contract](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L97C5-L107C91). Consider enhancing mapping documentation by using named parameters.
*   The [`newImplementation` name of the `address` parameter](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L166) in the `_authorizeUpgrade` function is unused, consider removing it.
*   The `isSet` boolean flag in the [`CustomBond` and `CustomLiveness`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L65-L73) structs is unnecessary because its state can be inferred from the value of `amount` or `liveness`, respectively. A zero value for either of these fields is not a sensible setting, so it can be used to signify that no custom value has been set, while any non-zero value indicates a custom setting is active. Removing this redundant boolean simplifies the logic and saves an extra storage slot for each struct, reducing the overall gas cost.

Consider addressing the identified instances to improve the quality and maintainability of the codebase.

_**Update:** Resolved in [pull request #27](https://github.com/UMAprotocol/managed-oracle/pull/27) at commit [dc580dd](https://github.com/UMAprotocol/managed-oracle/pull/27/commits/dc580dd52303af90c89a0b41aa407b0acc8f8682)._

### Naming Suggestions

Throughout the codebase, multiple opportunities for naming improvements were identified:

*   The term "whitelist" is used to describe a list of addresses that are permitted to perform certain actions. While historically common, the terms "whitelist" and "blacklist" can carry implicit connotations. In recent years, the technology industry has been moving towards more neutral and descriptive language that avoids potentially loaded terms. Consider replacing the term "whitelist" with "allowlist" throughout the codebase.
*   To maintain consistency, the [`REGULAR_ADMIN`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L88) and [`REQUEST_MANAGER`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L91) roles could be renamed to `REGULAR_ADMIN_ROLE` and `REQUEST_MANAGER_ROLE`.
*   The [`liveness` field](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L76) of the `InitializeParams` struct could be renamed to `defaultLiveness`.

To improve the legibility of the codebase, consider addressing the suggestions made above.

_**Update:** Resolved in [pull request #16](https://github.com/UMAprotocol/managed-oracle/pull/16) at commit [acba673](https://github.com/UMAprotocol/managed-oracle/pull/16/commits/acba673684cf456452f6b3657a5866439213e5ea) and [pull request #5](https://github.com/UMAprotocol/managed-oracle/pull/5) at commit [f747326](https://github.com/UMAprotocol/managed-oracle/pull/5/commits/f7473260e7abc582672515441910a9d10ae662a8). The team stated:_

> _We'd like to stick to whitelist naming for legacy reasons. Many systems use the whitelist naming. We will consider renaming in the future._

### Use Custom Errors

Since Solidity version 0.8.4, custom errors provide a cleaner and more cost-efficient way to explain to users why an operation failed.

The [`OptimisticOracleV2`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol) and [`ManagedOptimisticOracleV2`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol) contracts use `require` and `revert` messages.

For conciseness and gas savings, consider replacing `require` and `revert` messages with custom errors.

_**Update:** Resolved in [pull request #8](https://github.com/UMAprotocol/managed-oracle/pull/8) at commit [7d085a8](https://github.com/UMAprotocol/managed-oracle/pull/8/commits/7d085a8ce0ee2f760a314ba4292677e62adec61e)._

### Missing Security Contact

Providing a specific security contact (such as an email address or an ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

The [`OptimisticOracleV2`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol), [`ManagedOptimisticOracleV2`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol), [`AddressWhitelist`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/common/implementation/AddressWhitelist.sol), and [`DisableableAddressWhitelist`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/common/implementation/DisableableAddressWhitelist.sol) contracts do not have a security contact.

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in [pull request #10](https://github.com/UMAprotocol/managed-oracle/pull/10) at commit [210c517](https://github.com/UMAprotocol/managed-oracle/pull/10/commits/210c5170d446657319e07b240f400626e48722b4)._

### Function Visibility Overly Permissive

Throughout the codebase, multiple instances of functions with unnecessarily permissive visibility were identified:

In `ManagedOptimisticOracleV2`:

*   The [`_setMaximumBond`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L416-L420) function with `internal` visibility could be limited to `private`.
*   The [`_setMinimumLiveness`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L427-L430) function with `internal` visibility could be limited to `private`.
*   The [`_setDefaultProposerWhitelist`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L436-L440) function with `internal` visibility could be limited to `private`.
*   The [`_setRequesterWhitelist`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L446-L450) function with `internal` visibility could be limited to `private`.
*   The [`_getManagedRequestId`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L460-L466) function with `internal` visibility could be limited to `private`.
*   The [`_validateBond`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L474-L476) function with `internal` visibility could be limited to `private`.
*   The [`_getEffectiveProposerWhitelist`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L498-L507) function with `internal` visibility could be limited to `private`.

In `OptimisticOracleV2`:

*   The [`_getId`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol#L591-L597) function with `internal` visibility could be limited to `private`.
*   The [`_getState`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol#L676-L696) function with `internal` visibility could be limited to `private`.
*   The [`_getOracle`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol#L698-L700) function with `internal` visibility could be limited to `private`.
*   The [`_getStore`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol#L706-L708) function with `internal` visibility could be limited to `private`.
*   The [`_getIdentifierWhitelist`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol#L710-L712) function with `internal` visibility could be limited to `private`.
*   The [`_getTimestampForDvmRequest`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol#L714-L726) function with `internal` visibility could be limited to `private`.
*   The [`_stampAncillaryData`](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol#L733-L737) function with `internal` visibility could be limited to `private`.

To better convey the intended use of functions, consider changing the functions' visibility to be only as permissive as required. Otherwise, consider documenting that the contracts are expected to be extended by third party developers.

_**Update:** Resolved in [pull request #26](https://github.com/UMAprotocol/managed-oracle/pull/26) at commit [ce47fb4](https://github.com/UMAprotocol/managed-oracle/pull/26/commits/ce47fb4f2e3148438417b9c93c0b0ef51cb05e5f)._

Client Reported
---------------

### `DisableableAddressWhitelist` Is Not Enforced By Default

The [`DisableableAddressWhitelist` contract](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/common/implementation/DisableableAddressWhitelist.sol) extends the [`AddressWhitelist` contract](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/common/implementation/AddressWhitelist.sol) and introduces the [`isEnforced` flag](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/common/implementation/DisableableAddressWhitelist.sol#L12) to control whether the whitelist logic is active or not. By default, this flag is not explicitly set during construction and therefore defaults to `false`, meaning the whitelist is not enforced, and any address will pass the check. This creates a possibility for the owner to mistakenly assume that the whitelist is active without explicitly enabling it.

Consider modifying the `DisableableAddressWhitelist` contract to set the `isEnforced` flag to `true` by default, ensuring that whitelist behavior is enforced unless explicitly disabled.

_**Update:** Resolved in [pull request #6](https://github.com/UMAprotocol/managed-oracle/pull/6) at commit [2a816e1](https://github.com/UMAprotocol/managed-oracle/pull/6/commits/2a816e13ee3fc15d6f16626bedd9c5c5c01d5482). The UMA team stated:_

> _Not relevant anymore, as we moved from `DisableableAddressWhitelist` to two separate contracts: `DisabledAddressWhitelist` + `AddressWhiteList`, which have clear behaviours consistent with their names_

### Misleading or Incomplete Documentation

Throughout the codebase, multiple instances of misleading or incomplete documentation were identified:

*   The [`@return` NatSpec](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L360) of the `getCustomProposerWhitelist` function should be changed to `@return DisableableAddressWhitelistInterface`, as per the implementation.
*   The [`@dev` NatSpec](https://github.com/UMAprotocol/managed-oracle/blob/fc03083eca91c880efa8918c6d9532af9362f00d/src/optimistic-oracle-v2/implementation/ManagedOptimisticOracleV2.sol#L395) of the `getManagedRequestId` function is incorrect.

Consider addressing the above instances to improve the clarity of the codebase.

_**Update:** Resolved in [pull request #9](https://github.com/UMAprotocol/managed-oracle/pull/9) at commit [b8a7ea2](https://github.com/UMAprotocol/managed-oracle/pull/9/commits/b8a7ea20b5ce8f859c4d333c009275a0c54d2b5c). The first suggestion does no longer apply with the removal of the `DisableableAddressWhitelistInterface`._

Conclusion
----------

This report concludes a three-day audit of the managed-oracle protocol. Our analysis indicates that the protocol's design and implementation are fundamentally sound. We have identified several areas where code improvements can be made, and these have been detailed as findings in this report. These suggestions aim to enhance the robustness and efficiency of the existing codebase.

The codebase is well-commented and thoroughly documented, which greatly facilitated the review process. We would also like to commend the UMA team for their proactive approach in conducting their own internal audit, which had already identified several of the same points that we have raised. It was a pleasure to collaborate with them, and we appreciate their commitment to security and code quality.