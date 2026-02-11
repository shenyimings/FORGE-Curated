\- January 8, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

Type

DeFi

Timeline

From 2024-12-18

To 2024-12-20

Languages

Solidity

Total Issues

11 (11 resolved)

Critical Severity Issues

0 (0 resolved)

High Severity Issues

1 (1 resolved)

Medium Severity Issues

1 (1 resolved)

Low Severity Issues

5 (5 resolved)

Notes & Additional Information

4 (4 resolved)

Client Reported Issues

0 (0 resolved)

Scope
-----

We performed an incremental audit on the [forta-network/forta-firewall-contracts](https://github.com/forta-network/forta-firewall-contracts) repository between commits [`c42acc8`](https://github.com/forta-network/forta-firewall-contracts/tree/c42acc8c0ef74689731aaaa4fe19216f22b36f5c) and [`09feff1`](https://github.com/forta-network/forta-firewall-contracts/tree/09feff1d712011470d49d54f2462e3204c11afaf).

In scope were the following files:

`src/
├── AttesterWallet.sol
├── CheckpointExecutor.sol
├── ExternalFirewall.sol
├── Firewall.sol
├── FirewallPermissions.sol
├── FirewallRouter.sol
├── SecurityValidator.sol
├── TrustedAttesters.sol
└── interfaces
    ├── FirewallDependencies.sol
    ├── IAttesterWallet.sol
    ├── ICheckpointHook.sol
    ├── IExternalFirewall.sol
    ├── IFirewall.sol
    ├── ISecurityValidator.sol
    └── ITrustedAttesters.sol` 

System Overview
---------------

This diff-audit focused on the primary changes introduced by the Forta team:

*   Addition of the `AttesterWallet` Contract: An ERC-20 upgradeable contract with extra functionality. It maintains native currency balances, called FORTAGAS, per user transaction origin and spends them when an attester stores an attestation on behalf of such an origin.
*   Creation of the `FirewallRouter` Contract: Introduced to enhance modularity and upgradeability for firewall management. It enables the firewall to be upgraded, allowing integrator contracts to point to the `FirewallRouter` instead of a specific firewall instance.
*   Creation of the `TrustedAttesters` Contract: A centralized registry for managing trusted attesters. It improves security by employing role-based access control mechanisms, ensuring only authorized attesters can interact with the system.
*   Modification to the `SecurityValidator` Contract: The `storeAttestationForOrigin` function has been added, allowing the storage of attestations tied to specific origins. This feature simplifies attestation handling and adds flexibility to the system.
*   Deletion of the `AttestationForwarder` Contract: This contract has been removed.
*   Upgrade of OpenZeppelin Contracts Library: The OpenZeppelin library has been upgraded to version 5.1.0 and now utilizes the `TransientSlot` library instead of `StorageSlot` for managing transient storage.

Privileged Roles
----------------

Two new contracts introduce or extend privileged roles:

*   `DEFAULT_ADMIN_ROLE`: Can grant and revoke roles such as Attester Managers and upgrade the `SecurityValidator` address on the `AttesterWallet` contract.
*   `ATTESTER_MANAGER_ROLE`: Can grant and revoke the `TRUSTED_ATTESTER` role within `TrustedAttesters`.
*   `TRUSTED_ATTESTER_ROLE`: Can store attestations for a `beneficiary` and get reimbursed for an arbitrary `chargeAmount` from an arbitrary `chargeAccount`.

Security Model and Trust Assumptions
------------------------------------

*   Trusted attesters are assumed not to misbehave by spending arbitrary users' FORTAGAS to store attestations.
*   Trusted attesters are assumed not to spend more FORTAGAS than necessary to store attestations.
*   Trusted attesters are assumed not to use attestations signed by an arbitrary account. This is currently not enforced, as it is pending confirmation that only trusted attesters can sign them when storing.
*   The owner of the `TrustedAttesters` contract effectively holds the trusted attester role, as the contract is upgradable. The owner must retain the trusted attester role to avoid reversion of the store attestation call to the security validator contract.

High Severity
-------------

### Overflow in `quantize` Function Can Cause a DoS

The [`quantize` function](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/Quantization.sol#L20-L24) contains a vulnerability caused by an intermediate overflow during sequential operations in the return statement:

`return  ((n  >>  offset)  <<  offset)  +  (2  **  offset)  -  1;` 

When `offset = 256` (calculated as `8 * Math.log256(n)` for sufficiently large `n`), the operation `2 ** offset` results in an overflow since `2^256` exceeds the maximum value of a `uint256`. This overflow affects the intermediate result of the addition:

`((n  >>  offset)  <<  offset)  +  (2  **  offset)` 

Because Solidity performs this addition first, the overflow in the intermediate result causes the function to revert when it encounters an overflow. The subtraction `- 1` is never reached, as the overflow prevents further execution.

Consider refactoring the formula so that the full second term `(2 ** offset - 1)` is calculated first, in order to prevent the overflow. Additionally, consider adding fuzz tests to your test suite in order to detect edge cases in this `quantize` calculation.

_**Update:** Resolved in [pull request #47](https://github.com/forta-network/forta-firewall-contracts/pull/47/files)._

Medium Severity
---------------

### Applying Comparison to Raw Signed Integers Causes Unexpected Results

The [`_secureExecution` function](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/Firewall.sol#L179-L197) in the `Firewall` contract has a vulnerability that arises when the [`byteRange`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/Firewall.sol#L193) extracted from calldata represents a signed integer. In this case, the data is [cast](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/Firewall.sol#L194) to a `uint256`, resulting in a loss of the original signedness.

If the `byteRange` represents a negative integer, its two's complement representation is treated as a large positive unsigned value when converted to `uint256`. This can lead to unexpected behavior during threshold checks in [`_checkpointActivated`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/Firewall.sol#L232-L257), such as [`ref >= checkpoint.threshold`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/Firewall.sol#L247). Negative values, once interpreted as large unsigned integers, could either incorrectly satisfy or fail the comparison, bypassing the intended validation logic.

Consider properly documenting the behavior of calldata extraction and casting, including its implications on signedness, to ensure the firewall can reliably protect functions handling various data types.

_**Update:** Resolved in [pull request #48](https://github.com/forta-network/forta-firewall-contracts/pull/48/files)._

Low Severity
------------

### Missing Docstrings

Throughout the codebase, multiple instances of missing docstrings were identified:

*   In `AttesterWallet.sol`, the [`initialize` function](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/AttesterWallet.sol#L34-L43)
*   In `FirewallRouter.sol`, the [`firewall` state variable](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/FirewallRouter.sol#L15)
*   In `FirewallRouter.sol`, the [`updateFirewall` function](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/FirewallRouter.sol#L54-L56)

Consider thoroughly documenting all functions (and their parameters) that are part of any contract's public API. Functions implementing sensitive functionality, even if not public, should be clearly documented as well. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in [pull request #49](https://github.com/forta-network/forta-firewall-contracts/pull/49/files)._

### Missing Zero Address Checks

When assigning an address from a user-provided parameter, it is crucial to ensure the address is not set to zero. Setting an address to zero is problematic because it has special burn/renounce semantics. This action should be handled by a separate function to prevent accidental loss of access during value or ownership transfers.

Throughout the codebase, there are multiple instances where assignment operations are missing a zero address check:

*   The [`beneficiary`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/AttesterWallet.sol#L109) and [`_securityValidator`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/AttesterWallet.sol#L65) assignment operations within the contract `AttesterWallet`.
*   The [`origin`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/SecurityValidator.sol#L103) assignment operation within the contract `SecurityValidator`.

Consider adding a zero address check before assigning a state variable.

_**Update:** Resolved in [pull request #50](https://github.com/forta-network/forta-firewall-contracts/pull/50/files)._

### Incomplete Docstrings

Throughout the codebase, multiple instances of incomplete docstrings were identified:

*   In `AttesterWallet.sol`, the [`withdraw`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/AttesterWallet.sol#L80-L85) function parameters `amount` and `beneficiary` are not documented.
*   In `AttesterWallet.sol`, the [`withdrawAll`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/AttesterWallet.sol#L90-L93) function parameter `beneficiary` is not documented.
*   In `AttesterWallet.sol`, the [`storeAttestationForOrigin`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/AttesterWallet.sol#L102-L114) function parameters `chargeAccount` and `chargeAmount` are not documented.
*   In `CheckpointExecutor.sol`, the [`attestedCall`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/CheckpointExecutor.sol#L56-L62) function does not have all return values documented.
*   In `ExternalFirewall.sol`, both `executeCheckpoint` functions ([\[1\]](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/ExternalFirewall.sol#L34-L36), [\[2\]](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/ExternalFirewall.sol#L44-L46)) parameter `caller` are not documented.
*   In `Firewall.sol`, the functions [`getAttesterControllerId`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/Firewall.sol#L126-L128), [`getCheckpoint`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/Firewall.sol#L154-L163) and [`attestedCall`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/Firewall.sol#L171-L177) do not have all return values documented.
*   In `FirewallRouter.sol`, both `executeCheckpoint` functions ([\[1\]](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/FirewallRouter.sol#L28-L30), [\[2\]](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/FirewallRouter.sol#L38-L40) parameter `caller` are not documented.
*   In `SecurityValidator.sol`, the functions [`getCurrentAttester`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/SecurityValidator.sol#L126-L128), [`hashAttestation`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/SecurityValidator.sol#L134-L144),[`executeCheckpoint`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/SecurityValidator.sol#L154-L200) and [`executionHashFrom`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/SecurityValidator.sol#L267-L273) do not have all return values documented.
*   In `TrustedAttesters.sol`, the [`isTrustedAttester`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/TrustedAttesters.sol#L27-L29) function does not have all return values documented.

Consider thoroughly documenting all functions/events (and their parameters or return values) that are part of a contract's public API. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in [pull request #51](https://github.com/forta-network/forta-firewall-contracts/pull/51/files)._

### Lack of Input Validation

Within [`AttesterWallet`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/AttesterWallet.sol), all functions should ensure that amounts are not zero.

Consider implementing input validations in functions where parameters must be confined within specific boundaries. Furthermore, ensure that variables used across different functions are checked against the same boundaries to maintain consistency and integrity.

_**Update:** Resolved in [pull request #52](https://github.com/forta-network/forta-firewall-contracts/pull/52/files)._

### Inability to Modify Firewall Access After Contract Deployment

The `FirewallRouter` contract inherits from `FirewallPermissions`, which provides an internal [`_updateFirewallAccess`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/FirewallPermissions.sol#L51-L54) function to update the `firewallAccess` variable. While the `firewallAccess` is [updated in the constructor](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/FirewallRouter.sol#L19), there is no explicit function in `FirewallRouter` to invoke this internal function, making it impossible to update the `firewallAccess` variable after contract deployment.

Consider implementing a restricted function to allow updates to `firewallAccess` after deployment in order to improve flexibility.

_**Update:** Resolved in [pull request #53](https://github.com/forta-network/forta-firewall-contracts/pull/53/files)._

Notes & Additional Information
------------------------------

### Lack of License Specification

The following instances were found where no license or a wrong one was specified:

*   [`TrustedAttesters.sol`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/TrustedAttesters.sol#L1) contract
*   [`ITrustedAttesters.sol`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/interfaces/ITrustedAttesters.sol#L1) interface
*   [`SecurityValidator.sol`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/SecurityValidator.sol) contract

The use of `// SPDX-License-Identifier: UNLICENSED` in the code indicates that no explicit license has been specified. This has significant implications:

*   **Restricted Usage by Default:** Without a license, others are not granted permission to copy, modify, or distribute the code. Copyright laws automatically apply, protecting the code, and any use without permission could be considered infringement.
*   **Enforceability Concerns:** Even though the code is legally protected, the absence of a clear license might make it harder to enforce these rights. Some users may mistakenly believe that the code is open for use due to the lack of a license statement.
*   **No Attribution Requirements:** Since no license is provided, there are no conditions like attribution requirements. However, others are not permitted to use the code at all without explicit permission from the author.

To ensure control over how your code is used, consider specifying a license and enforcing consistency on the license specified across the rest of the contracts. A license provides legal protection by establishing clear usage terms, which helps prevent misuse and encourages collaboration.

_**Update:** Resolved in [pull request #54](https://github.com/forta-network/forta-firewall-contracts/pull/54/files)._

### Use Custom Errors

Since Solidity version 0.8.4, custom errors provide a cleaner and more cost-efficient way to explain to users why an operation failed.

Throughout the codebase, instances of revert and/or require messages were found. For instance:

*   In the `AttesterWallet.sol` file, the [`require`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/AttesterWallet.sol#L49) statement with the message "sender is not a trusted attester". This error is also inconsistent with the same one raised on the [`SecurityValidator`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/SecurityValidator.sol#L69) contract. Consider emitting the same custom error instead.
*   In the `Firewall.sol` file, the [`require`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/Firewall.sol#L137) statement with the message "refStart is larger than refEnd".
*   In the `FirewallPermissions.sol` file, the [`require`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/FirewallPermissions.sol#L22-L24) statement with the message "caller is not firewall admin".
*   In the `FirewallPermissions.sol` file, the [`require`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/FirewallPermissions.sol#L29-L32) statement with the message "caller is not checkpoint manager".
*   In the `FirewallPermissions.sol` file, the [`require`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/FirewallPermissions.sol#L37-L39) statement with the message "caller is not logic upgrader".
*   In the `FirewallPermissions.sol` file, the [`require`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/FirewallPermissions.sol#L44-L47) statement with the message "caller is not checkpoint executor".
*   In the `FirewallPermissions.sol` file, the [`require`](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/FirewallPermissions.sol#L52) statement with the message "new firewall access contract cannot be zero address".

For conciseness and gas savings, consider replacing require and revert messages with custom errors.

_**Update:** Resolved in [pull request #55](https://github.com/forta-network/forta-firewall-contracts/pull/55/files)._

### State Variable Visibility Not Explicitly Declared

Within SecurityValidator.sol, the [`trustedAttesters` state variable](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/SecurityValidator.sol#L57) lacks an explicitly declared visibility.

For improved code clarity, consider always explicitly declaring the visibility of state variables, even when the default visibility matches the intended visibility.

_**Update:** Resolved in [pull request #56](https://github.com/forta-network/forta-firewall-contracts/pull/56/files)._

### Unused Named Return Variables

Named return variables are a way to declare variables that are meant to be used within a function's body for the purpose of being returned as that function's output. They are an alternative to explicit in-line `return` statements.

Within `Firewall.sol`, multiple instances of unused named return variables were identified:

*   The [`validator` return variable](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/Firewall.sol#L101) of the `getFirewallConfig` function
*   The [`checkpointHook` return variable](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/Firewall.sol#L102) of the `getFirewallConfig` function
*   The [`attesterControllerId` return variable](https://github.com/forta-network/forta-firewall-contracts/blob/09feff1d712011470d49d54f2462e3204c11afaf/src/Firewall.sol#L103) of the `getFirewallConfig` function

Consider either using or removing any unused named return variables.

_**Update:** Resolved in [pull request #57](https://github.com/forta-network/forta-firewall-contracts/pull/57/files)._

Conclusion
----------

Throughout the audit process, a few issues were identified, leading to recommendations aimed at improving code consistency, readability, and gas efficiency.

In addition to these recommendations, the codebase would benefit from a strengthened test suite, including fuzz tests to identify critical vulnerabilities, as well as an expansion of unit tests to achieve a test coverage rate above 95%. This is essential for adhering to the highest standards of security and reliability, thereby significantly enhancing code safety.

The Forta team's approach to the audit process was highly commendable. Their prompt responses, willingness to engage in discussions about the findings, and dedication to improving their product's security were particularly noteworthy. Despite the issues identified, the potential of the Forta Firewall remains strong, with its capability to significantly enhance DeFi security.