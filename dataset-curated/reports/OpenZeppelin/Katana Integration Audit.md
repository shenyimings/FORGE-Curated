\- November 10, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

### Summary

**Type:** DeFi  
**Timeline:** June 6, 2025 → June 17, 2025  
**Languages:** Solidity, Go

**Findings**  
Total issues: 10 (6 resolved)  
Critical: 0 (0 resolved)  
High: 1 (1 resolved)  
Medium: 3 (1 resolved)  
Low: 2 (1 resolved)

**Notes & Additional Information**  
4 (3 resolved)

**Client Reported Issues**  
0 (0 resolved)

Scope
-----

We audited [pull request #176](https://github.com/lombard-finance/smart-contracts/pull/176) in the [`lombard-finance/smart-contracts`](https://github.com/lombard-finance/smart-contracts) repository at commit [`602502e`](https://github.com/lombard-finance/smart-contracts/commit/602502e8f3540230d8dd8693ecf463b7c022e771) and [pull request #302](https://github.com/lombard-finance/ledger/pull/302/files#diff-b4183254b86020859fa7adc7ba01a0b6f10c99a22279f46977e74b993494e407) in the [`lombard-finance/ledger`](https://github.com/lombard-finance/ledger) repository at commit [`2f18ece`](https://github.com/lombard-finance/ledger/commit/2f18ecef8028b25f4d5ca1f0f582fd938626f2e7).

In scope were the following files:

`smart-contracts/
└── contracts
    ├── LBTC
    │   └── NativeLBTC.sol
    └── libs
        └── Actions.sol

ledger/
├── notaryd
│   ├── config
│   │   ├── config.go
│   │   └── katana.go
│   ├── start.go
│   ├── types
│   │   ├── deposit_btc_msg.go
│   │   ├── deposit_btc_msg_v0.go
│   │   └── deposit_btc_msg_v1.go
│   └── verifier
│       ├── deposit_strategy.go
│       ├── deriveaddress
│       │   └── service.go
│       ├── unstake_strategy.go
│       └── verifier.go
└── x
    ├── deposit/keeper/query_derive_address.go
    ├── lbtc/keeper/msg_server_mint_from_session.go
    ├── notary/exported/selector.go
    ├── notary/keeper/abci.go
    └── notary/types/message_submit_payload.go` 

System Overview
---------------

Katana is an **EVM-compatible L2 network incubated by Polygon Labs and GSR**. Built with Polygon CDK, Katana’s stated mission is to eliminate liquidity fragmentation and deliver sustainable yield by concentrating activity in a tightly curated set of protocols.

Lombard Finance is integrating with the Katana protocol to supply BTC collateralized tokens by introducing **NativeLBTC**, a second `ERC20` token representing Bitcoin (BTC) that can be deposited and unstaked on Katana. This token will work alongside the existing `LBTC` asset.

The current code introduces minimal changes required to support the **Deposit V1** payload format for `NativeLBTC` while preserving full backwards compatibility:

*   **Deposit payload versioning:** `deposit_btc_msg_v1` is added, and the previous schema is renamed **V0**.
    
*   **Selective notarization:** `notaryd` now notarizes V1 deposits only when its local configuration targets the Katana chain, preventing this change from affecting other chains.
    
*   **NativeLBTC:** An ERC20 token that handles deposits, mints, and interfaces with existing bridge logic through the shared `Actions` library.
    
*   **Ledger support:** The Ledger module is extended to accept and verify V1 payloads and to notarize unstake messages originating from the `NativeLBTC` token contract.
    

Security Model and Trust Assumptions
------------------------------------

*   Katana validators and the `notaryd` service are assumed to behave honestly.
*   The operator key controlling `NativeLBTC.mint` is expected to be held in a multisig governed by Lombard.

### Privileged Roles

*   **Default admin:** Can set the privileged roles, described below, for the `NativeLBTC` contract.
*   **Operator:** Sets the maximum mint fee of the `NativeLBTC` token.
*   **Claimer:** Can mint `NativeLBTC` using a payload signed by the validators and a `feePayload` signed by the user, applying a commission to the amount.
*   **Pauser:** Can `pause` and `unpause` operations of the `NativeLBTC` token.
*   **Minter:** Can mint, using a payload signed by the validators, and burn `NativeLBTC` tokens.
*   **Notaryd verifier:** Decides whether a deposit or unstake payload is valid and signs the corresponding transaction on Katana.

High Severity
-------------

### Permits Will Break After Calling ChangeNameAndSymbol

The `NativeLBTC` contract [imports `ERC20PermitUpgradeable`](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/LBTC/NativeLBTC.sol#L25), which adds the EIP-2612 [`permit()`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/c812cefe11890ef9f28356e8503b4e5e8d0d12a6/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol#L46-L70) function to enable gasless approvals. However, the [function `_changeNameAndSymbol`](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/LBTC/NativeLBTC.sol#L471) allows changes to the token `$.name` and `$.symbol`, but does not modify [`EIP712712Storage._name`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/c812cefe11890ef9f28356e8503b4e5e8d0d12a6/contracts/utils/cryptography/EIP712Upgradeable.sol#L42), which is used in `permit`.

This change would break all new `permit()` calls, which would end up reverting, because `ERC20Permit.domainSeparator()` would still use the previous `name`.

Consider either removing the option to modify the token `name` and `symbol` or implementing a reinitialize function that invokes the `_EIP712_init` function with the updated `name`.

_**Update:** Resolved in [pull request #225](https://github.com/lombard-finance/smart-contracts/pull/225)._

Medium Severity
---------------

### Incorrect Storage Slot Hash for NATIVE\_LBTC\_STORAGE\_LOCATION

In the `NativeLBTC.sol` contract, the [`NATIVE_LBTC_STORAGE_LOCATION` variable](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/LBTC/NativeLBTC.sol#L48C30-L48C58) constant is set to `0xa9a2395ec4edf6682d754acb293b04902817fdb5829dd13adb0367ab3a26c700`. This does not match the expected output of `keccak256(abi.encode(uint256(keccak256("lombardfinance.storage.NativeLBTC")) - 1)) & ~bytes32(uint256(0xff))`, which should be `0xb773c428c0cecc1b857b133b10e11481edd580cedc90e62754fff20b7c0d6000`.

Consider updating the `NATIVE_LBTC_STORAGE_LOCATION` to the correct value.

_**Update:** Resolved in [pull request #214](https://github.com/lombard-finance/smart-contracts/pull/214/files)._

### Signatures Can Be Reused

In the `NativeLBTC.sol` contract, the `_mintV1WithFee` function [validates user signatures](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/LBTC/NativeLBTC.sol#L609-L617) authorizing fee payments. However, the function does not have any mechanism to prevent signature replays.

As a result, the same `(feePayload, userSignature)` pair can be reused multiple times by any address with `CLAIMER_ROLE`, granting them the ability to repeatedly deduct fees from a user for any future deposits, until the fee expiry time, to the same recipient. Additionally, since the fee approval is not bound to a specific deposit payload, any valid `feePayload` can be combined with any deposit payload as long as the recipient matches.

Although the total minted amount remains consistent with the underlying deposit and does not result in extra tokens minted, the design allows non-revocable fee permissions, valid for a specified time interval, that may be unintuitive for users and diverge from the EIP-2612 patterns which expect single-use signatures.

Consider introducing a per-user nonce to ensure each signature is used only once and binding fee approvals more tightly to the intended context to prevent unauthorized or unintended reuse.

_**Update:** Acknowledged, not resolved. The Lombard team stated:_

> _It is intentional design, user provide approve(signature) not for the specific deposit but for the specific time and can do many deposits during this time or do not do any deposits._

### Missing Lower Bound on User Specified Fees in Minting

The address holding the `CLAIMER_ROLE` can mint `NativeLBTC` by calling [`mintV1WithFee`](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/LBTC/NativeLBTC.sol#L343-L350) or [`batchMintV1WithFee`](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/LBTC/NativeLBTC.sol#L359-L389), providing a [`DepositBtcActionV1`](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/libs/Actions.sol#L13-L20) payload signed by the validators and a `feePayload`, signed by the user who will receive the tokens. However, the [actual fee applied is the minimum](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/LBTC/NativeLBTC.sol#L586-L590) of the `maximumFee`, set by the contract owner, and the `fee` specified by the user in the signed `feePayload`.

While the contract ensures that the [fee signed by the user is not zero](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/libs/Actions.sol#L361-L363), it can be set to arbitrarily small values (e.g., `1 wei`). In such cases, this minimal fee would be applied (even if `maximumFee` is not zero), rendering the fee mechanism ineffective in preventing denial of service (DoS) attacks, which is its primary intended purpose.

Consider enforcing a minimum fee threshold (at least when `maximumFee` is not zero) to ensure the minting fee remains an effective mechanism against DoS attacks.

_**Update:** Acknowledged, not resolved. The Lombard team stated:_

> _User can provide any fee level that he is ready to pay, but it is claimer decision if he is ready to claim for such fee. There are no guarantee that it will be claimed with any fee. Moreover gas price can be changed and if before fee level was too small, maybe some hours later will be ok._

Low Severity
------------

### Inconsistent and Redundant Storage of Token Metadata

The [`NativeLBTCStorage`](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/LBTC/NativeLBTC.sol#L29-L44) structure in the `NativeLBTC` contract includes `name` and `symbol` fields to store the token's data. However, `NativeLBTC` inherits from `ERC20Upgradeable`, which already contains an [`ERC20Storage`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/5338b9fa024b13acb7d5f3d58a97b2d43f398fc2/contracts/token/ERC20/ERC20Upgradeable.sol#L32-L41) struct with `name` and `symbol` fields. Although these inherited fields are initialized to empty strings and are not actively used, defining duplicate fields introduces unnecessary redundancy.

Additionally, the token `name` is also stored in the `_name` field of the [`EIP712Storage`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/5338b9fa024b13acb7d5f3d58a97b2d43f398fc2/contracts/utils/cryptography/EIP712Upgradeable.sol#L36-L44) struct of the `EIP712Upgradeable` contract (`NativeLBTC` inherits `ERC20PermitUpgradeable` and therefore its parent contract `EIP712Upgradeable`). While initially, this value is synchronized with the `NativeLBTC.name` value, the `NativeLBTC` contract has a [`changeNameAndSymbol` function](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/LBTC/NativeLBTC.sol#L100-L105) that can update the name and symbol of the `NativeLBTCStorage`, while leaving the others unchanged. Such inconsistency may cause issues or confuse users.

Consider using a single storage location for `name` and `symbol`. If multiple storage locations are necessary, ensure all relevant fields are consistently updated whenever changes occur.

_**Update:** Resolved at commit [4d8f795](https://github.com/lombard-finance/smart-contracts/commit/4d8f795e02c76a9a75f7a681b7db282ae95b10ca)._

### Inadequate Validation of Selector in `ValidateBasic`

In the [`ValidateBasic`](https://github.com/lombard-finance/ledger/blob/2f18ecef8028b25f4d5ca1f0f582fd938626f2e7/x/notary/exported/selector.go#L52) function of the `selector.go` file, the provided selector is verified by [comparing it against the `undefinedType` array](https://github.com/lombard-finance/ledger/blob/2f18ecef8028b25f4d5ca1f0f582fd938626f2e7/x/notary/exported/selector.go#L57-L59) instead of the set of the [six allowed selectors](https://github.com/lombard-finance/ledger/blob/2f18ecef8028b25f4d5ca1f0f582fd938626f2e7/x/notary/exported/selector.go#L17-L47). Since `undefinedType` is an uninitialized (and therefore zero-valued) byte array, any non-zero selector will incorrectly be considered valid.

Consider explicitly validating the selector by checking it against the actual set of allowed selectors to ensure proper verification.

_**Update:** Acknowledged, not resolved. The Lombard team stated:_

> _Checking if the selector is one of the supported ones is a module choice since other modules may define theirs. So, `ValidateBasic` only checks the correctness of the selector type._

Notes & Additional Information
------------------------------

### Unbounded Batch Loop in batchMint

In the `NativeLBTC.sol` contract, the functions [`batchMint`](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/LBTC/NativeLBTC.sol#L270), [`batchMintV1`](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/LBTC/NativeLBTC.sol#L315), and [`batchMintV1WithFee`](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/LBTC/NativeLBTC.sol#L359) perform minting operations within a loop that processes an arbitrary number of items. Since the number of iterations is not explicitly capped, passing in a large array may cause the transaction to run out of gas and revert. Although this behavior does not introduce a direct vulnerability, it exposes the contract to unnecessary reverts and can degrade user experience.

Consider enforcing a maximum batch size to ensure predictable gas consumption and reduce the risk of accidental reverts.

_**Update:** Acknowledged, not resolved. The Lombard team stated:_

> _The batch size is controlled on the backend, and no need to spend gas on additional checks for each transaction. Moreover, it can be hard to estimate max size, only with a very pessimistic approach can it be calculated, but in fact, it will just decrease the real max size._

### Missing Deposit Version in Error Message

In the [calculateDeterministicAddress](https://github.com/lombard-finance/ledger/blob/2f18ecef8028b25f4d5ca1f0f582fd938626f2e7/notaryd/verifier/deriveaddress/service.go#L69) function, if the computation of the auxiliary data fails, an [error](https://github.com/lombard-finance/ledger/blob/2f18ecef8028b25f4d5ca1f0f582fd938626f2e7/notaryd/verifier/deriveaddress/service.go#L79) message is generated that includes the nonce and the referral ID but omits the deposit version.

Consider including the deposit version in the error message to improve clarity and aid in debugging.

_**Update:** Resolved in [pull request #325](https://github.com/lombard-finance/ledger/pull/325)._

### Type Mismatch for `amount` in BTC Deposit Message

The `amount` field in a BTC deposit message is declared as `uint64` in the [`deposit_btc_msg_v0.go`](https://github.com/lombard-finance/ledger/blob/2f18ecef8028b25f4d5ca1f0f582fd938626f2e7/notaryd/types/deposit_btc_msg_v0.go#L24), but as a `uint256` in the [`Actions.sol`](https://github.com/lombard-finance/smart-contracts/blob/602502e8f3540230d8dd8693ecf463b7c022e771/contracts/libs/Actions.sol#L8).

Consider aligning them to `uint256` so they have the same bit size.

_**Update:** Resolved in [pull request #326](https://github.com/lombard-finance/ledger/pull/326)._

### `Vout` is not explicitly checked in `verifyTx` Method

In the [`verifyTx`](https://github.com/lombard-finance/ledger/blob/2f18ecef8028b25f4d5ca1f0f582fd938626f2e7/notaryd/verifier/deposit_strategy.go#L127) function of the `deposit_strategy.go` file, the `vout` index from the payload is not compared to the `fetchedOutput.Vout`. While from a security perspective this check is not required, as the `vout` is directly requested from the bitcoin node, an explicit `vout` comparison would keep code consistent.

Consider adding an explicit for `vout` to keep validation consistent.

_**Update:** Resolved in [pull request #355](https://github.com/lombard-finance/ledger/pull/355)._

Conclusion
----------

This review examined the changes made to the Lombard Ledger codebase to support a Katana integration. A single high severity vulnerability was identified across both codebases, along with a few medium and low severity issues. The code under review was found to be clean and well structured.

The Lombard team was cooperative and provided all necessary context, enabling a smooth and effective audit process.