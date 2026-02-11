\- February 5, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

Type

Token

Timeline

From 2024-05-23

To 2024-05-28

Languages

Solidity

Total Issues

4 (4 resolved)

Critical Severity Issues

0 (0 resolved)

High Severity Issues

0 (0 resolved)

Medium Severity Issues

0 (0 resolved)

Low Severity Issues

1 (1 resolved)

Notes & Additional Information

3 (3 resolved)

Scope
-----

We performed a diff audit of the [zksync-association/zk-governance](https://github.com/zksync-association/zk-governance) repository at commit [27763f1](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23) against commit [08ec4e7](https://github.com/zksync-association/zk-governance/blob/08ec4e7548c83572e6f09c8344f6e3390bb1b27a).

In scope were the following files:

`src
├── ZkMerkleDistributor.sol
├── ZkTokenV1.sol
├── interfaces
│   ├── IMintable.sol
│   └── IMintableAndDelegatable.sol
└── lib
    └── Nonces.sol` 

We also performed a full audit of the [zksync-association/zk-governance](https://github.com/zksync-association/zk-governance) repository at commit [410452d](https://github.com/zksync-association/zk-governance/blob/410452dce4a1fb46f97e44a330c78b5ffb53684a/) for the following file:

System Overview
---------------

The [`ZkTokenV1`](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkTokenV1.sol) contract is the core of the system and is going to be the governance token of ZKsync Era. It is an ERC-20 token with permit functionality which incorporates a voting delegation system so that token holders can delegate their voting power to a trusted representative while preserving the actual token value.

In addition to the functionalities described in the previous audit report, the system contains the following updates.

### `ZkTokenV1` Contract

A new function was added to allow delegating votes from a signer to a delegatee, adding EIP-1271 support in addition to the ECDSA signature.

### `ZkMerkleDistributor` Contract

The claiming approach has been updated. Users now have more options while claiming their tokens. Previously, users could claim and delegate simultaneously or they could claim on behalf of others and delegate simultaneously. The updated version adds two new separate functions to claim tokens, one to claim on behalf of others and one to claim for yourself, but without any voting rights delegation.

### `ZkTokenV2` Contract

This additional token contract extends from the V1 contract and was introduced with the sole purpose of renaming the token from `zkSync` to `ZKsync`, since the token was already deployed at the time of reviewing, according to the ZKsync Association team. No further features were added to it.

Low Severity
------------

### Inconsistency in Signature Verification

When claiming tokens on behalf of another account using [`claimOnBehalf`](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L140) or [`claimAndDelegateOnBehalf`](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L200), the claim information includes an [`expiry`](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L29) field which indicates at which `block.timestamp` this signature would expire. In case the `block.timestamp` is equal to or larger than the `expiry` ([\[1\]](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L148) [\[2\]](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L209)), the claiming operation will fail.

When delegating tokens using [`claimAndDelegate`](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L177) or [`claimAndDelegateOnBehalf`](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L200), the delegate information includes a similar [`expiry`](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L22) field. However, in this case, the delegation will only fail in case the [`block.timestamp` is strictly greater than the `expiry`](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkTokenV1.sol#L112).

Consider modifying the signature expiry verification process for either the claiming signature or the delegation signature in order to make it consistent for both types of signatures.

_**Update:** Resolved at commit [`410452d`](https://github.com/zksync-association/zk-governance/commit/410452dce4a1fb46f97e44a330c78b5ffb53684a). The signature expiry verification processes of both the claiming signature and delegation signature are now consistent with each other. They both check whether the expiration timestamp is strictly smaller than the current `block.timestamp`._

Notes & Additional Information
------------------------------

### Incorrect or Misleading Documentation

Throughout the codebase, a few instances of incorrect or misleading documentation were identified:

*   The documentation of the [`ZkTokenV1` contract](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkTokenV1.sol#L17) points out that the nonce used in both the `delegateBySig` and `permit` functions is the same. Consider mentioning that the same nonce is also used in the `delegateOnBehalf` function.
*   The documentation for the [`_claim` function](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L258) suggests that this function is only called internally by `claim` and `claimOnBehalf`. However, it is also called by `claimAndDelegate` and `claimAndDelegateOnBehalf`. Consider mentioning this in the documentation.
*   The documentation for the [`ZkMerkleDistributor__ClaimAmountExceedsMaximum` error](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L82) states that this error is thrown when the total amount of claimed tokens exceeds the total amount claimed. However, the error should be thrown when the total amount claimed exceeds the maximum claimable amount.
*   The documentation for the [`claimAndDelegate` function](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L171-L172) suggests that this method cannot be called by smart accounts because it is using the signature parameter that is passed to the [`delegateOnBehalf` function](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkTokenV1.sol#L110) of the `ZkTokenV1` contract. However, the `delegateOnBehalf` function does support EIP-1271 and ECDSA signatures, thereby supporting smart accounts as well. Additionally, consider changing "smart contract accounts" to "smart accounts" to be in conformity with [the official zkSync documentation](https://docs.zksync.io/build/sdks/js/accounts.html).
*   In the documentation for the [`ZkMerkleDistributor__ClaimWindowNotOpen` error](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L73), "or" should be removed.

Clear and accurate documentation helps users and developers understand the codebase. Consider reviewing all the documentation and updating any incorrect and/or misleading statements.

_**Update:** Resolved at commit [`410452d`](https://github.com/zksync-association/zk-governance/commit/410452dce4a1fb46f97e44a330c78b5ffb53684a). All the instances of incorrect or misleading documentation have been addressed._

### Unused Imports

The following instance of unused imports was identified and can be removed:

*   The [`ERC20PermitUpgradeable` import](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkTokenV1.sol#L10) in `ZkTokenV1.sol`

Consider removing any unused imports to improve the overall clarity and readability of the codebase.

_**Update:** Resolved at commit [`410452d`](https://github.com/zksync-association/zk-governance/commit/410452dce4a1fb46f97e44a330c78b5ffb53684a). The `ERC20PermitUpgradeable` import has been removed._

### Gas optimizations

Throughout the codebase, the following instances of code could benefit from gas cost optimization:

*   The [`delegateOnBehalf` function](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkTokenV1.sol#L111) in `ZkTokenV1` will copy the `_signature` data to memory.
*   Both the [`claimAndDelegate`](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L177) and [`claimAndDelegateOnBehalf`](https://github.com/zksync-association/zk-governance/blob/27763f16b7b8b4c98241c9c7ae73c045e3b52e23/src/ZkMerkleDistributor.sol#L200) functions in `ZkMerkleDistributor` will copy the `DelegateInfo` struct to memory.

The arguments mentioned above are read-only as none of their values are being modified within the functions. Consider changing the locations of these arguments from `memory` to `calldata` in order to reduce the gas amount needed to execute the functions.

_**Update:** Resolved at commit [`410452d`](https://github.com/zksync-association/zk-governance/commit/410452dce4a1fb46f97e44a330c78b5ffb53684a). All the suggested gas optimizations have been applied on the codebase._

Conclusion
----------

This update adds EIP-1271 support to the `ZkTokenV1` and `ZkMerkleDistributor` contracts in order to expand claiming and voting delegation options using the signatures of smart accounts. In addition, as a result of updates made to the claiming procedure, users now have more flexibility when claiming their tokens.

The audit yielded one low-severity issue along with a few recommendations for code improvement. The codebase is well-written, straightforward to follow, and well-documented. The codebase is a collaborative effort between ZKsync Association and ScopeLift. Both teams were very responsive throughout the engagement and answered all our questions.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kGC_5lUiKRTYbvZ621CmeUS_CHGtw&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=184043340453&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=6233b062-856d-4644-8023-2862215a7832&redirect_url=APefjpFnkXST_g1JDB8KtPpTlTHDzIIuTCNvsN-3OfMrWV1aoInNFl85ahFpMb5KtJtJMkIIBDLr2pT30IBWlRkloWDJD5kIr5tiKhBGwVDbX_KNuo6tItB0ZyaktaZY9yWPrnI5lK_s-fj8skXwW4MbON0i1OxALYD-vm3rgHuA_QesfcRRF8LqKRHY0zicrDkq5pugiPUAlFeAX9vKtGAdJn0LLe8aToLw7_y6mskWabjrUePrWgVC0Bz36QcVwbkwLbWbZKVv&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Fdistributor-diff-audit&ts=1770534287569&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.93.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")