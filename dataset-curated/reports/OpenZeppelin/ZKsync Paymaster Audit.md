\- February 5, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

Type

Layer 2

Timeline

From 2024-04-14

To 2024-04-19

Languages

Solidity

Total Issues

9 (8 resolved)

Critical Severity Issues

0 (0 resolved)

High Severity Issues

0 (0 resolved)

Medium Severity Issues

0 (0 resolved)

Low Severity Issues

3 (3 resolved)

Notes & Additional Information

6 (5 resolved)

Scope
-----

We audited the [zksync-association/zk-governance](https://github.com/zksync-association/zk-governance) repository at commit [70011bb](https://github.com/zksync-association/zk-governance/tree/70011bb4092a774ff96d4e68cb80313ee1b33e74).

In scope were the following files:

`contracts
├── interfaces/
│   ├── IAADistributorPaymaster.sol
│   ├── IPaymaster.sol
│   ├── IPaymasterFlow.sol
│   ├── ISignatureBasedPaymaster.sol
│   └── IZkMerkleDistributor.sol
├── AADistributorPaymaster.sol
├── Constants.sol
└── SignatureBasedPaymaster.sol` 

System Overview
---------------

The ZKsync Association team is conducting a token airdrop and intends to cover the gas costs associated with claiming and delegating these tokens. This improves the user experience by eliminating the need for participants to pay their own fees or to have ZKsync ETH in their wallets at the time of claiming. There are two expected use cases and the code under review contains a supporting paymaster contract for each one.

In the first case, the ZKsync Association team will run an off-chain service to collect user signatures which will allow them to claim and delegate tokens on behalf of the users. In this way, ZKsync Association will submit the ZKsync transactions and pay the associated gas costs. However, for security and convenience reasons, these transactions will be executed in parallel from multiple different Matter Labs "sender" accounts. The `SignatureBasedPaymaster` contract can be used to identify and sponsor any transaction sent from an authorized sender account. It uses a hierarchical key architecture so that more secure keys can authorize and revoke the operational senders.

However, some airdrop recipients may be account abstraction wallets that cannot support the off-chain use case, either because they do not fully conform to [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271) (which would be necessary for a ZKsync Association sender account to act on their behalf) or their frontend user interface does not expose this functionality. This brings us to the second case. In this scenario, they can use the `AADistributorPaymaster` contract which will sponsor the gas costs of arbitrary transactions, provided:

*   The transaction originates from a recipient of the airdrop.
*   The recipient is a smart contract.
*   The transaction does not exceed a configurable per-transaction ETH limit.
*   The recipient has not reached a configurable per-account sponsored transaction limit.

Security Model and Privileged Roles
-----------------------------------

The signature-based paymaster and account abstraction paymaster have different trust assumptions and privileged roles:

### `SignatureBasedPaymaster`

*   The `SignatureBasedPaymaster` has an owner and signer address.
*   The owner is intended to be a multisig wallet while the signer is an EOA which can create ECDSA signatures.
*   The owner can change the signer address.
*   The owner or signer can approve multiple simultaneous sender addresses, each up to a specified expiry timestamp.
*   Each sender can use the paymaster for any transaction until the expiry timestamp.
*   The signer can also approve a sender (and corresponding expiry timestamp) with an off-chain signature which the sender would provide with their first sponsored transaction.
*   The owner or signer can cancel a sender's approval that has not yet been processed.
*   Only approvals from the current signer are valid, and thus if the signer is changed, any unprocessed approvals from the previous signer are invalidated.
*   The owner can withdraw any ETH or tokens held by the paymaster.

### `AADistributorPaymaster`

*   The `AADistributorPaymaster` has an owner address.
*   The owner can change the per-transaction sponsored ETH limit and the per-account sponsored transaction limit.
*   Each airdrop recipient account abstraction wallet can use the paymaster for (almost) arbitrary transactions. Naturally, this implies that it can perform operations other than claiming and delegating tokens, but the extent of abuse is constrained by these limits.
*   The owner can withdraw any ETH or tokens held by the paymaster.

Low Severity
------------

### Race Condition During Cancelation

If the owner or signer calls [cancelNonce](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/SignatureBasedPaymaster.sol#L175) but the spender's transaction that uses the active nonce is confirmed first, this call will incorrectly cancel the next nonce.

Consider providing the target nonce to the `cancelNonce` function and reverting whenever it is not the expected value.

_**Update:** Resolved at commit [79e005e](https://github.com/zksync-association/zk-governance/commit/79e005e7802b9b7446d9939b215aa3c25700e394)._

### Naming Suggestion

The second [`NonceCanceled` event](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/interfaces/ISignatureBasedPaymaster.sol#L8) parameter is named `newNonce` but it corresponds to the nonce that is canceled.

Consider renaming it to describe the relevant nonce.

_**Update:** Resolved at commit [1dcf101](https://github.com/zksync-association/zk-governance/commit/1dcf1011fef9982efa4e93d7b413059c344a3b4e)._

### Incomplete Docstrings

Throughout the codebase, there are multiple instances of incomplete docstrings. For instance, the [postTransaction](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/interfaces/IPaymaster.sol#L90-L97) function in `IPaymaster.sol`, and the `_txHash` and `_suggestedSignedHash` parameters are not documented. In addition, for the [domainSeparator](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/SignatureBasedPaymaster.sol#L190-L192) function in `SignatureBasedPaymaster.sol`, the return value is not documented.

Consider thoroughly documenting all functions/events (and their parameters or return values) that are part of a contract's public API. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved at commit [e002b6e](https://github.com/zksync-association/zk-governance/commit/e002b6e82dfab5644624ac0392e2a61f47344d9c)._

Notes & Additional Information
------------------------------

### Typographical Errors

The following typographical errors were identified in the codebase. Consider correcting them.

*   ["amout"](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/interfaces/IPaymaster.sol#L87) should be "amount".
*   ["implementated"](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/interfaces/IPaymasterFlow.sol#L9) should be "implemented".
*   ["pay"](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/SignatureBasedPaymaster.sol#L39) should be "pays".

_**Update:** Resolved at commit [f6a605c](https://github.com/zksync-association/zk-governance/commit/f6a605c77312dc5d448e82e57b95c5f1b26d3b53)._

### Code Simplification

The [`try-catch` logic](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/SignatureBasedPaymaster.sol#L88) is only used to choose between two scenarios: either a new signature needs to be processed or the sender is relying on a previous signature. The intermediate case, where a provided buffer cannot be decoded correctly and is therefore ignored, does not appear to be a valid use case. As such, instead of executing the `catch` block in this scenario, it would be simpler and more natural for the function to revert.

Consider only attempting to decode and process the signature when the `innerInputs` buffer is not empty. In either case, the `approvedSenders` mapping can be checked afterwards (outside the `if` statement).

_**Update:** Resolved at commit [a67e188](https://github.com/zksync-association/zk-governance/commits/a67e188bf2fd7f71bd83433de018fad297f6bc3b)._

### Unnecessary Cast

The `uint256` casts for the transaction [`from`](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/AADistributorPaymaster.sol#L81) and [`to`](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/AADistributorPaymaster.sol#L100) parameters are redundant since they already have type `uint256`.

For simplicity, consider removing the redundant cast.

_**Update:** Resolved at commit [1f9c0f1](https://github.com/zksync-association/zk-governance/commit/1f9c0f15fe4dfe904c01834eaea7692d17859b4f)._

### Variables Could Be `immutable`

If a variable is only ever assigned a value from within the `constructor` of a contract, then it could be declared as `immutable`.

Within `AADistributorPaymaster.sol`, there are variables that could be `immutable`:

*   The [`zkMerkleDistributor` state variable](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/AADistributorPaymaster.sol#L35)
*   The [`CACHED_MERKLE_ROOT` state variable](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/AADistributorPaymaster.sol#L38)

To better convey the intended use of variables and to potentially save gas, consider adding the `immutable` keyword to variables that are only set in the constructor.

_**Update:** Resolved not an issue. The ZKsync Association team stated:_

> _Acknowledged. In ZKsync using immutable is a bit more expensive than direct storage access. Due to this reason, we decided to leave the current approach._

### Use Custom Errors

Throughout the codebase, we identified instances where `require` statements are used instead of revert messages with custom errors.

Since Solidity version 0.8.4, custom errors provide a cleaner and more cost-efficient way to explain to users why an operation failed.

For conciseness and gas savings, consider replacing `require` and revert messages with custom errors.

_**Update:** Acknowledged, not resolved. The ZKsync Association team stated:_

> _Acknowledged._

### Function Visibility Overly Permissive

Throughout the codebase, there are various functions with unnecessarily permissive visibility:

*   The [`setMaxPaidTransactionsPerAccount`](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/AADistributorPaymaster.sol#L142-L145) function in `AADistributorPaymaster.sol` with `PUBLIC` visibility could be limited to `EXTERNAL`.
*   The [`setMaxSponsoredEth`](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/AADistributorPaymaster.sol#L149-L152) function in `AADistributorPaymaster.sol` with `PUBLIC` visibility could be limited to `EXTERNAL`.
*   The [`withdraw`](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/AADistributorPaymaster.sol#L157-L169) function in `AADistributorPaymaster.sol` with `PUBLIC` visibility could be limited to `EXTERNAL`.
*   The [`withdraw`](https://github.com/zksync-association/zk-governance/blob/70011bb4092a774ff96d4e68cb80313ee1b33e74/contracts/SignatureBasedPaymaster.sol#L152-L164) function in `SignatureBasedPaymaster.sol` with `PUBLIC` visibility could be limited to `EXTERNAL`.

To better convey the intended use of functions and to potentially realize some additional gas savings, consider changing a function's visibility to be only as permissive as required.

_**Update:** Resolved at commit [ba8d36a](https://github.com/zksync-association/zk-governance/commit/ba8d36a0a1123c091dd446871283cf5e947d887d)._

Recommendations
---------------

### Monitoring Recommendations

While audits help in identifying potential security risks, the Matter Labs team is encouraged to also incorporate automated monitoring of on-chain contract activity into their operations. Ongoing monitoring of deployed contracts helps in identifying potential threats and issues affecting the production environment.

*   Monitor the number of transactions used and change `setMaxPaidTransactionsPerAccount` such that genuine users would never run out of transactions while minimizing the harm done by malicious users who may be taking advantage of the gas sponsorship in `AADistributorPaymaster`.
*   The gas price should be monitored to ensure that `setMaxSponsoredEth` is suitable for the current gas prices.
*   The `AADistributorPaymaster` does not assume many behaviors from account abstraction wallets. However, these wallets may still have unexpected properties which either do not comply with the paymaster's expectations or can make claiming through the wallet user interface counterintuitive. It is recommended to investigate reports of users having difficulty claiming their airdrop, especially from account abstraction wallets.

Conclusion
----------

The codebase allows ZKsync to cover the gas costs associated with airdrop claiming for both EOAs and account abstraction wallets. The code was of a high quality and only fixes for minor issues were suggested to further improve the codebase. We appreciate the ZKsync Association team for providing us with detailed documentation and being very responsive in answering any questions we had about the project.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kHqa9q-F4voKktnWNsVOKwxP-a1BQ&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=185199249476&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=716ce159-bcdb-4859-a9b6-68b169cbd959&redirect_url=APefjpHzP36Nvrx5bEpZ7eX4rIk7-STQak0UW_qns3daXZpMrRuWnDp39Edx_gmc2Mbf2vdkgxX-23lXaF_YJIa16ajEnr9w8CiYK02_rH5yTFjiL9xLE_H_tSqi5wRDAoyDju9N9J6OeXD0OmpKK6j46XnXUgHXI3y7IXvDcbbWZ6263-2lXKINNdRQATzJCZjzysIxqR6AzPn5XnFTBCZ-q-jHkPQinP7ty6qZm1ItkZrLL11ZeVWQ4KFNm-mc9oTsuOYaEbP1&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Fzksync-paymaster-audit&ts=1770534280914&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.89.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")