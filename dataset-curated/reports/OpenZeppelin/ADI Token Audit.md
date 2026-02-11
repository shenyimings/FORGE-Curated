\- October 9, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary

**Type:** DeFi  
**Timeline:** May 16, 2025 → May 23, 2025  
**Languages:** Solidity

**Findings**  
Total issues: 5 (5 resolved)  
Critical: 0 (0 resolved) · High: 0 (0 resolved) · Medium: 0 (0 resolved) · Low: 1 (1 resolved)

**Notes & Additional Information**  
4 notes raised (4 resolved)

Scope
-----

OpenZeppelin audited the adi-token-smart-contract repository at commit 520521db.

In scope were the following files:

`ADI
└── contracts
    ├── ADI.sol
    ├── extensions
    │   ├── TokensRescuer.sol
    │   └── ZeroAddrChecker.sol
    └── interfaces
        └── ITokensRescuer.sol` 

System Overview
---------------

This audit covers the ADI token, which acts as a gas token on the ADI Blockchain and supports minting, burning, and token recovery. It is based on OpenZeppelin’s upgradeable ERC-20 implementation and includes the following functionalities:

*   Controlled minting and burning
*   Token-rescue functionality for recovering mistakenly sent tokens
*   Role-based access for minting, burning, and rescue operations

Security Model and Trust Assumptions
------------------------------------

The system uses cryptographic signatures, role-based access control, and multi-sig approval to enforce security and governance.

### Privileged Roles

The ADI token uses OpenZeppelin’s `AccessControlUpgradeable` contract to manage access. Key roles include the following:

*   `DEFAULT_ADMIN_ROLE`: Controls the minting and rescue of ADI tokens.
*   `BURNER_ROLE`: Allows for the burning of ADI tokens.

Low Severity
------------

### Missing Docstring

Within `ADI.sol`, the docstring for the `BURNER_ROLE` state variable is missing.

Consider thoroughly documenting all functions/events (and their parameters or return values) that are part of a contract's public API. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in commit 0c9c6fd0._

Notes & Additional Information
------------------------------

### Non-Explicit Imports Are Used

The use of non-explicit imports in the codebase can decrease code clarity and may create naming conflicts between locally-defined and imported variables. This is particularly relevant when multiple contracts exist within the same Solidity file or when inheritance chains are long.

In `ADI.sol` and `TokenRescuer.sol`, non-explicit/global imports are being used.

Following the principle that clearer code is better code, consider using the named import syntax (`import {A, B, C} from "X"`) to explicitly declare which contracts are being imported.

_**Update:** Resolved in commit bb48dd15._

### `public` Functions or Variables Prefixed With Underscore

`public` functions and variables should not be prefixed with an underscore.

In `ADI.sol`, the `__ADI_init` function is `public` but has been prefixed with an underscore.

Consider renaming the `__ADI_init` function to `initialize` to follow the convention.

_**Update:** Resolved in commit 008a7836._

### Role Identifier Not Hashed

In the `ADI` contract, the identifier for the `BURNER_ROLE` is assigned as the `bytes32` value of the string literal. The common convention is to hash the string (i.e., by using `keccak256`) instead of using the raw string directly.

Consider hashing the string when declaring the `BURNER_ROLE` constant to align with the standard practice.

_**Update:** Resolved in commit eddfe82f._

### Lack of Security Contact

Providing a specific security contact (such as an e-mail address or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Throughout the codebase, multiple instances of contracts missing a security contact were identified:

*   The `ADI` contract
*   The `TokensRescuer` abstract contract
*   The `ZeroAddrChecker` library

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in commits 101229d2 and 1c15b59c._ 

Conclusion
----------

The ADI Token serves as the ADI Blockchain's gas token with secure minting, burning, and upgradeable functionality.

No concerning issues were identified in the codebase, while several recommendations aimed at improving code readability and maintainability were made.

The ADI team was helpful and responsive throughout the audit period, providing valuable insights into the project.