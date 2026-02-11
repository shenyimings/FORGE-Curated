\- October 21, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

Type

Bridge

Timeline

From 31-07-2025

To 06-08-2025

Languages

Solidity

Total Issues

12 (12 resolved)

Critical Severity Issues

0 (0 resolved)

High Severity Issues

1 (1 resolved)

Medium Severity Issues

0 (0 resolved)

Low Severity Issues

4 (4 resolved)

Notes & Additional Information

7 (7 resolved)

Scope
-----

OpenZeppelin audited the Eclipse-Laboratories-Inc/syzygy-canonical-bridge repository at commit 5c5fac0.

In scope were the following files:

`src
├── v1
│   ├── Treasury.sol
│   └── interfaces
│       └── ICanonicalBridge.sol
└── v3
    └── CanonicalBridgeV3.sol` 

System Overview
---------------

This system includes two primary smart contracts deployed on Ethereum L1, `CanonicalBridgeV3` and `Treasury`, which operate in conjunction with an L2 bridge program and off-chain relayers. Together, these components facilitate the secure, time-delayed transfer of ETH between the Ethereum and Eclipse chains.

*   The `CanonicalBridgeV3` contract is responsible for the core bridge logic. It handles deposit initiations and withdrawal authorizations, but does not directly hold the ETH collateral. It features a robust, role-based access-control system to manage critical functions, such as pausing the bridge, authorizing withdrawals, and cancelling suspicious transactions.
    
*   The `Treasury` contract is a distinct, upgradeable contract that serves as a secure vault for all the deposited ETH. By separating the custody of funds from the `CanonicalBridgeV3` contract, it minimizes the attack surface and ensures that funds are only released after a withdrawal has been fully authorized and has passed a mandatory security delay.
    

The security model relies on a time-locked withdrawal process initiated by a trusted off-chain relayer. When a withdrawal is authorized by the `CanonicalBridgeV3` contract, it enters a 7-day fraud-detection window. During this period, an account holding the `WITHDRAW_CANCELLER_ROLE` can veto the transaction. Users can only claim their ETH from the Treasury after this window has successfully passed, providing a strong safeguard against fraudulent activity.

This structure establishes a highly secure bridge by enforcing a strict separation of concerns between logic and custody, implementing a mandatory fraud-detection window for all withdrawals, and leveraging a multi-layered, role-based security model.

Security Model and Trust Assumptions
------------------------------------

During the audit, the following trust assumptions were made:

*   **Off-chain Component Reliability**: The Bridge system depends on several critical off-chain components that must operate correctly:
    
    *   The Deposit Relayer must reliably monitor all deposit events on L1 and initiate corresponding minting operations on L2 without missing any events.
    *   The Withdraw Relayer must reliably monitor all withdrawal events and authorize corresponding withdrawals on L1 without missing any events.
    *   The Withdrawal Validator must effectively identify and delete invalid withdrawal messages within the defined fraud period.
*   **Privileged Role Integrity**: The contracts contain several privileged roles that must behave honestly. Malicious or compromised privileged addresses could cause a bridge malfunction and put users' funds at risk.
    
*   **Contract Version Management**: The deployment of `CanonicalBridgeV3` requires careful coordination:
    
    *   Previous versions (V1 and V2) of the bridge contract must be paused indefinitely before the V3 deployment.
    *   While V3 prevents the re-authorization of messages that had been previously authorized in older versions, it does not prevent messages from being first authorized in V3 and then in V1/V2. As such, pausing the older versions is essential to mitigate this risk.
    *   Messages authorized on V1/V2 and executed through V3 will retain `PENDING` status on their originating contract, allowing for their post-execution deletion. While this breaks the invariant that only `PROCESSING` or `PENDING` messages can be deleted, it has no practical consequences as long as the older versions remain paused.
*   **Fraud Period Sufficiency**: The fraud period defined in the contracts must provide adequate time for the withdrawal validation system to identify and cancel any fraudulent or invalid withdrawal messages before they can be executed.
    

### Privileged Roles

The following privileged roles were identified in the system:

#### `Treasury`

*   `DEFAULT_ADMIN_ROLE` grants full administrative control over the contract, including assigning and revoking roles.
*   `DEPOSITOR_ROLE` grants permission to deposit funds into the `Treasury` contract. The Canonical Bridge must be granted this role.
*   `WITHDRAW_AUTHORITY_ROLE` grants permission to withdraw funds from the `Treasury` contract. The Canonical bridge must be granted this role.
*   `EMERGENCY_ROLE` enables the holder to recover or move funds from the `Treasury` contract in case of emergencies or unforeseen events.
*   `PAUSER_ROLE` allows the holder to pause treasury operations (deposits and withdrawals). Emergency withdrawals are still possible even when the `Treasury` contract is paused. This role is typically used during emergencies or maintenance.
*   `STARTER_ROLE` grants permission to unpause the `Treasury` contract and resume operations after a pause.
*   `UPGRADER_ROLE` allows the holder to upgrade the `Treasury` contract to a new implementation.

#### `CanonicalBridgeV3`

*   `DEFAULT_ADMIN_ROLE` grants full administrative control over the contract, including assigning and revoking roles.
*   `WITHDRAW_AUTHORITY_ROLE` authorizes withdrawal requests and processes fund withdrawals.
*   `CLAIM_AUTHORITY_ROLE` enables the holder to claim withdrawals on behalf of other users.
*   `WITHDRAW_CANCELLER_ROLE` enables the holder to cancel pending or in-progress withdrawal requests, primarily for fraud prevention.
*   `FRAUD_WINDOW_SETTER_ROLE` permits the holder to change the fraud window duration, which is the timeframe to flag or cancel suspicious withdrawals.
*   `PAUSER_ROLE` allows the holder to pause the bridge operations, typically used during emergencies or maintenance. Cancelling a withdrawal request is still possible even if the contract has been paused.
*   `STARTER_ROLE` grants the holder the permission to unpause the bridge and resume operations after a pause.

High Severity
-------------

### Double Fee Deduction from `Treasury` for V1 Withdrawals via `CanonicalBridgeV3`

The `CanonicalBridgeV3` contract includes a `claimWithdraw` function that allows users to withdraw funds after their request has been approved—either through V3 directly or through V1 and V2. During the withdrawal process, the bridge deducts fees from the total withdrawal amount. However, in `CanonicalBridgeV1`, fees are already deducted during the call to `authorizeWithdraw`. This means that when a V1-approved withdrawal is later claimed via V3, the treasury incurs a **double fee deduction**—once in V1, and again in V3.

Consider accounting for this behavior, especially for requests from V1.

_**Update:** Resolved in pull request #10 at commit dd9b7eb. The team stated:_

> _This was a known issue, and we agree that it should be resolved. To create clean branching, we've added a `_settleWithdrawFee` function with settles allows the fees and amount to be settled in independent function calls. A corresponding `WithdrawFeeSettled` event has also been added. `v1` withdraws do not invoke the `_settleWithdrawFee` function, whereas `v2` and `v3` do. This allows clean settlement with no double fee take on the `v1` contract. Unit tests have also been upgraded with balance checks to verify that fees settle with correct amounts on all versions of the bridge._

Low Severity
------------

### `reinitialize` Missing Access Control

The `reinitialize` function of the `Treasury` contract has been declared as `external` but lacks any form of access control. While the `reinitializer(2)` modifier ensures that the function can be executed at most once after a proxy upgrade, it does not restrict who can call it. Consequently, the very first address that calls `reinitialize` after the proxy is upgraded will:

1.  receive the `DEFAULT_ADMIN_ROLE` via `_grantRole(DEFAULT_ADMIN_ROLE, msg.sender)`
2.  possess the ability to administer **all** other roles in OpenZeppelin’s `AccessControl` model. With such power, the attacker can grant themselves the `WITHDRAW_AUTHORITY_ROLE`, drain all funds, pause/unpause the contract, or even upgrade the implementation again

Consider either ensuring that the `reinitialize` function is called within the same transaction that performs the proxy upgrade, to guarantee that only the upgrader can execute the reinitializaton logic, or introducing an explicit access control, such as only allowing the previous owner to invoke `reinitialize`.

_**Update:** Resolved in pull request #11 at commit 6837c54._

### Lack of Unique Identifier in `Deposited` Events

The Deposit Relayer is responsible for listening to `Deposited` messages emitted by the `CanonicalBridge` contract on L1. These messages have the following form: `Deposited(address indexed sender, bytes32 indexed recipient, uint256 amountWei, uint256 amountLamports)`.

Multiple deposits with identical parameters (sender, recipient, and amount) will produce indistinguishable events. This becomes especially problematic when multiple identical deposits occur within the same transaction. While the off-chain component assigns IDs to these deposits using the transaction hash and an index (to distinguish separate deposits in the same transaction), there is no identifier assigned on-chain, which reduces the overall robustness of the design.

Consider adding a unique identifier to the `Deposited` event, such as a nonce maintained by `CanonicalBridge` and incremented with each successful deposit.

_**Update:** Resolved in pull request #10 at commit 2ca368c. The team stated:_

> _This is a good comment, and also a known issue. The intent with V3 was to not break or update the `ICanonicalBridge` interface in any way, so this prevents us from modifying the `Deposited` event directly. However, we agree that deposits should be indexible with a deterministic id, so a new event has been added to the V3 contract. `event DepositedWithId( address indexed sender, bytes32 indexed recipient, uint256 amountWei, uint256 amountLamports, uint64 depositId );` The idea behind this event is that is preserves the old event, but adds a unique `uint64` type for the Eclipse side to consume (Solana program takes u64s for deposit account PDA generation). Currently, this uint64 is taken to be the somewhat convoluted. `low_64(tx_hash) + event_index` We've chosen `keccak(depositIndex++)` as the formula for deposits, because it preserves the pseudorandom character of the previous deposit nonces. The new event type is better, because V3 events can then be indexed using event queries, as opposed to scanning every block to pick out transaction hashes. This is a longstanding problem with deposits, so it's good to fix it. The old event is still emitted for backwards compatibility. In the future (i.e. if we go to a uint256 bridge), a new ledger would need to be deployed on the Eclipse side. That would facilitate 256 bit `depositIds` and `withdrawIds`. We have been considering this security upgrade for a while, but for now we will stick with the 64-bit security for deposit and withdraw ids._

### Incomplete Docstrings

Within `ICanonicalBridge.sol`, multiple instances of incomplete docstrings and non-compliance with NatSpec were identified:

*   In the `Deposited` event, the `amountLamports` parameter is not documented.
*   In the `WithdrawClaimed` event, the `remoteSender` parameter is not documented.
*   In the `PAUSER_ROLE` function, not all return values are documented.
*   In the `STARTER_ROLE` function, not all return values are documented.
*   In the `WITHDRAW_AUTHORITY_ROLE` function, not all return values are documented.
*   In the `CLAIM_AUTHORITY_ROLE` function, not all return values are documented.
*   In the `WITHDRAW_CANCELLER_ROLE` function, not all return values are documented.
*   In the `FRAUD_WINDOW_SETTER_ROLE` function, not all return values are documented.
*   In the `MIN_DEPOSIT` function, not all return values are documented.
*   In the `TREASURY` function, not all return values are documented.
*   In the `fraudWindowDuration` function, not all return values are documented.
*   In the `startTime` function, not all return values are documented.
*   In the `withdrawMessageStatus` function, not all return values are documented.
*   In the `withdrawMessageStatus` function, not all return values are documented.
*   In the `withdrawMessageHash` function, not all return values are documented.
*   In the `withdrawMsgIdProcessed` function, not all return values are documented.

Consider thoroughly documenting all functions/events (and their parameters or return values) that are part of a contract's public API. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in pull request #10 at commit 3781a92._

### Missing Zero-Address Checks

Immutable variables are set once at deployment and cannot be modified. Therefore, it is essential to carefully validate the values assigned to them. In particular, when assigning addresses, a check ensuring that the address is non-zero should be performed to avoid accidentally assigning the zero address, which would permanently disable any functionality tied to that variable.

Within `CanonicalBridgeV3.sol` contract's constructor, multiple instances of immutable addresses being set without performing a non-zero check were identified:

*   The `TREASURY` address
*   The `CANONICAL_BRIDGE_V1` address
*   The `CANONICAL_BRIDGE_V2` address

Consider adding a zero-address check before assigning these immutable addresses.

_**Update:** Resolved in pull request #10 at commit 106fdfa._

Notes & Additional Information
------------------------------

### Function Visibility Overly Permissive

Throughout the codebase, multiple instances of functions with unnecessarily permissive visibility were identified:

*   The `getVersionComponents` function in `Treasury.sol` with `public` visibility could be limited to `external`.
*   The `getVersionComponents` function in `CanonicalBridgeV3.sol` with `public` visibility could be limited to `external`.
*   The `setFraudWindowDuration` function in `CanonicalBridgeV3.sol` with `public` visibility could be limited to `external`.

To better convey the intended use of functions and to potentially realize some additional gas savings, consider changing a function's visibility to be only as permissive as required.

_**Update:** Resolved in pull request #10 at commit 1cf4a56 and pull request #11 at commit 55b58ab._

### Unused Struct in `Treasury` Contract

In the `Treasury` contract, a `StorageV1` struct is defined but remains unused in the current version of the code.

Consider removing the unused struct to reduce the size of the contract and enhance readability.

_**Update:** Resolved in pull request #11 at commit 637c937._

### NatSpec Parameter Name Does Not Match Struct Field in `WithdrawMessage`

In line 18 of `ICanonicalBridge.sol`, the NatSpec comment documents the first field of `WithdrawMessage` as `pubKey`, yet the struct actually declares that field as `from`. Any off-chain tooling or contract that relies on the documentation will encode/decode the message incorrectly, leading to broken withdrawals or lost funds.

Consider addressing the parameter name mismatch to prevent any issues.

_**Update:** Resolved in pull request #10 at commit 105932a._

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Throughout the codebase, multiple instances of contracts missing security contacts were identified:

*   The `Treasury` contract
*   The `ICanonicalBridge` interface
*   The `CanonicalBridgeV3` contract

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in pull request #10 at commit f1f2983. The team stated:_

> _We've decided not to remediate this in the solidity code, and have included the ImmuneFi link in our documentation instead._

### Redundant `return` Statement

To improve the readability of the contract, it is recommended to remove redundant `return` statements from functions that have named returns.

The `return true;` statement in `Treasury.sol` is redundant.

Consider removing the redundant return statement in functions with named returns to improve the readability of the contract.

_**Update:** Resolved in pull request #11 at commit a34963c._

### Redundant Reassignment of `fraudWindowDuration` in Constructor

The `fraudWindowDuration` variable of the `CanonicalBridgeV3` contract is initialized with the default value of `7 days` when defined. However, it is redundantly reassigned the same default value within the constructor.

Consider removing the unnecessary reassignment to simplify the code and slightly reduce gas usage.

_**Update:** Resolved in pull request #10 at commit 7834b0f._

### Inaccurate Description of Deleted Messages Status in Documentation

When deleting a withdrawal message, `startTime` and `withdrawMsgIdProcessed` are set to 0. As a result, the status of the message becomes `UNKNOWN`, allowing it to be re-authorized. However, this behavior contradicts the documentation, which states that the state of a deleted message should be `CLOSED`.

Consider updating the documentation to accurately reflect this behavior.

_**Update:** Resolved in pull request #10 at commit edebe3c._

Conclusion
----------

This audit focused on the recent changes made to the `CanonicalBridgeV3` and `Treasury` contracts of the Eclipse Bridge. A high-severity issue was identified involving the double deduction of fees from the `Treasury` contract during withdrawals that had been authorized in a previous version but are being executed in the updated version of the canonical bridge.

Overall, the codebase demonstrated high quality and was supported by a comprehensive test suite. The Eclipse team was highly responsive and collaborative throughout the engagement, contributing to a smooth and efficient audit process.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kGiZvW8y7taHsAcTsBAF8whfb9i-w&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=195527189109&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=ca21ce82-3f91-4826-a2d0-212111abea68&redirect_url=APefjpGWr-yNwsVk3BH3EeCQleFAYLuiTIKTD4AxfEnSWojTpt7zdPvFR6tGtG5NDtEt0FwEspqDpjKRjuK-zPJKAUfro98oIxGSIDi--D0GEXsAD2fH9-Nux7uK7UhjLcjfiGCgV1FSpLEmMZpxpxAWfUy5xCg_z9ep0MPpWihLlekSl-qgAXc3BPxzteI0ZIxdIzKZfVI79G0Xl2_F2IAochDQS3HUYOUrUFI2--LxrD-qz4CGjqvEj6NnbBVpDMmuAXwyYMwX&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Feclipse-solidity-bridge-audit&ts=1770533797511&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.37.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")