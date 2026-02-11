\- May 12, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

Type

Cross-Chain

Timeline

From 2025-04-22

To 2025-04-24

Languages

Solidity

Total Issues

5 (5 resolved)

Critical Severity Issues

0 (0 resolved)

High Severity Issues

0 (0 resolved)

Medium Severity Issues

0 (0 resolved)

Low Severity Issues

1 (1 resolved)

Notes & Additional Information

2 (2 resolved)

Client Reported Issues

2 (2 resolved)

Scope
-----

OpenZeppelin performed a diff audit of the Across Protocol [contracts repository](https://github.com/across-protocol/contracts/) at commit [77761d7](https://github.com/across-protocol/contracts/tree/77761d74152e319e6edd6d4d766cb46c39e6f38d). Specifically, the changes introduced by [pull request #941](https://github.com/across-protocol/contracts/pull/941) and [pull request #944](https://github.com/across-protocol/contracts/pull/944) were audited.

In scope were the following files:

`contracts
├── Lens_SpokePool.sol
├── ZkSync_SpokePool.sol
└── chain-adapters
    ├── ZkStack_Adapter.sol
    └── ZkStack_CustomGasToken_Adapter.sol` 

System Overview
---------------

The Across Protocol is a cross-chain bridging protocol that enables fast token transfers between different blockchains. At the core of the protocol is the `HubPool` contract on the Ethereum mainnet which serves as a central liquidity hub and cross-chain administrator for all contracts within the system. This pool governs the `SpokePool` contracts deployed on various networks that either initiate token deposits or serve as the final destination for transfers.

The changes introduced in [pull request #941](https://github.com/across-protocol/contracts/pull/941) add support for bridging USDC tokens between Ethereum (L1) and ZK-Stack-based rollups (L2) using Circle's bridged USDC standard. Previously, bridging was done over the default ERC-20 bridge on ZK-Stack-based networks. The bridged USDC standard is an intermediate step towards full support of Circle's Cross-Chain Transfer Protocol (CCTP). The changes in this pull request update both the L1 and L2 contracts so that they can later be compatible with Circle’s CCTP.

To summarize, the bridging mechanism for USDC tokens, previously limited to the standard ERC-20 bridge, has been enhanced. The updates introduce support for two additional routing protocols defined during deployment:

1.  A custom bridge designed for Circle's Bridged (upgradable) USDC.
2.  Circle's Cross-Chain Transfer Protocol (CCTP) bridges.

The pull request is meant for the Lens protocol. However, the current implementation is modular and can be adopted by any ZK-Stack-based project.

The changes introduced with [pull request #944](https://github.com/across-protocol/contracts/pull/944) implement a [recommendation](https://github.com/OpenZeppelin/audits-uma/blob/master/reports/21-Retainer-02-Across-Incremental/issues/low/07-potentially-mutable-variable-treated-as-immutable.md) from an earlier audit. In essence, the `SHARED_BRIDGE` global variable has been removed from the `ZkStack_Adapter.sol` contract, and the direct call `BRIDGE_HUB.sharedBridge()` is used instead. The motivation is to avoid potential issues in case the bridge contract address gets updated after the adapter contract has been deployed.

Low Severity
------------

### Custom Gas Tokens Can Get Stuck In `HubPool`

The `ZkStack_CustomGasToken_Adapter` contract is used to send messages from L1 to ZK Stack-based chains with a custom gas token. The public functions within this contract are expected to be called via `delegatecall`, which will execute this contract's logic within the context of the originating contract. Particularly, the `HubPool` will [`delegatecall`](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/HubPool.sol#L901-L909) the [`relayTokens` function](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L178). This `relayTokens` function is used to bridge tokens to a ZK Stack chain. This function calls `_pullCustomGas` to define `txBaseCost` on [line 186](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L186) to compute the amount of gas tokens needed and, more importantly, [pulls the needed gas token amount](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L299) from the funder.

However, in the case when bridging using the [CCTP bridge](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L226-L228), the custom gas token is not needed, and thus the pulled tokens will end up stuck in the `HubPool`.

This issue can be generalized to other computations as well. For instance, the [`sharedBridge`](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L187C17-L187C29) should only be defined when `l1Token` is different than `usdcToken` in `ZkStack_CustomGasToken_Adapter`, and [`txBaseCost`](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_Adapter.sol#L162) should not be computed when using the CCTP bridge in `ZkStack_Adapter`.

Consider only pulling custom gas tokens within the `relayTokens` function when they are needed. More generally, consider avoiding unnecessary computation to define variables that will be used later to reduce gas costs.

_**Update:** Resolved in [pull request #975](https://github.com/across-protocol/contracts/pull/975) at commit [1725a57](https://github.com/across-protocol/contracts/pull/975/commits/1725a573972c9d533bffc77f59944b91bd12ea0d)._

Notes & Additional Information
------------------------------

### Missing and Misleading Documentation

Throughout the codebase there are a few places with missing or misleading documentation. For instance:

*   The comment on [line 203](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_Adapter.sol#L203) in `ZkStack_Adapter.sol` does not take into consideration the case when bridging USDC when `address(usdcToken) == address(0)`.
*   Similarly, the comment on [line 247](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L247) in `ZkStack_CustomGasToken_Adapter.sol` does not take into consideration the case when bridging USDC when `address(usdcToken) == address(0)`.
*   The flags `zkUSDCBridgeDisabled` and `cctpUSDCBridgeDisabled` are mutually exclusive, which is enforced with checks in the constructors [\[1\]](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_Adapter.sol#L107-L109) [\[2\]](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L130-L132) [\[3\]](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/ZkSync_SpokePool.sol#L74-L76). Consider explicitly documenting this requirement in the constructor's arguments documentation.

Consider addressing the above instances and updating the documentation to reflect the latest changes in the functionality.

_**Update:** Resolved in [pull request #973](https://github.com/across-protocol/contracts/pull/973) at commit [fa39e0d](https://github.com/across-protocol/contracts/pull/973/commits/fa39e0d15a8a4bbff11fa3cc1ac2cb07aa9b8152)._

### Relay Tokens From L1 Emits Empty Transaction Hash When Relaying USDC Through CCTP

The `relayTokens` functions [\[1\]](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_Adapter.sol#L154) [\[2\]](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L178) are used to bridge tokens from L1 to ZK Stack. Both instances define a `txHash` variable [\[1\]](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_Adapter.sol#L164) [\[2\]](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L189) which will later be assigned to the transaction hash value returned by the `BRIDGE_HUB` when initiating a bridging transaction. However, in both cases [\[1\]](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_Adapter.sol#L182-L185) [\[2\]](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L226-L228) when CCTP is enabled, the `_transferUsdc` function is used, bypassing the `BRIDGE_HUB`. This function does not return a transaction hash, however, causing the `relayTokens` functions to emit an empty `ZkStackMessageRelayed` event [\[1\]](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_Adapter.sol#L222) [\[2\]](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L266). This behavior can be confusing for users, especially when trying to index the event based on the emitted hash.

In case no off-chain components rely on the emitted event, consider removing the emitted event to avoid confusion. Otherwise, consider adding thorough documentation for the `ZkStackMessageRelayed` event, outlining its expected behavior.

_**Update:** Resolved in [pull request #976](https://github.com/across-protocol/contracts/pull/976) at commit [cc4fa0a](https://github.com/across-protocol/contracts/pull/976/commits/cc4fa0a9f35b5864889424380ffa6d567897697a) and [pull request #982](https://github.com/across-protocol/contracts/pull/982) at commit [1a23663](https://github.com/across-protocol/contracts/pull/982/commits/1a2366344ab1594341e3814dd7ad4f969ca94e6e)._

Client Reported
---------------

### Potential Revert in USDC Relayer Refunds via Custom Bridge

The [`executeSlowRelayLeaf` function](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/SpokePool.sol#L1169C14-L1169C34) is used to execute a leaf stored as part of a root bundle to refund the relayer. This will send the relayer the amount they sent to the recipient, plus a relayer fee. This function will invoke `_distributeRelayerRefunds`. If the amount to return in the leaf is positive, then send L2 -> L1 message to bridge tokens back via a chain-specific bridging method by calling the `_bridgeTokensToHubPool` function.

However, in case the `l2TokenAddress` to bridge is the USDC token and the ZK Stack custom USDC bridge is being used, the refund will revert when withdrawing through the custom ZK Stack USDC bridge on [line 154](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/ZkSync_SpokePool.sol#L154) in `ZkSync_SpokePool`, since the caller, in this case the `HubPool`, hasn't granted enough approval to the `zkUSDCBridge` to transfer tokens from the `HubPool` to the bridge.

A fix was delivered alongside the issue in [pull request #967](https://github.com/across-protocol/contracts/pull/967) by approving the needed `amountToReturn` of USDC to the `zkUSDCBridge` before calling the `withdraw` function.

_**Update:** Resolved in [pull request #967](https://github.com/across-protocol/contracts/pull/967) at commit [0bcd27a](https://github.com/across-protocol/contracts/pull/967/commits/0bcd27a7681890bcfddfc0009d325c1735e04497)._

### Restricted USDC Bridging via Shared Bridge with Custom Gas Token

In the `ZkStack_CustomGasToken_Adapter` contract, the [`relayTokens` function](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L178) facilitates bridging tokens to ZK Stack-based chains. To execute this function, the `ZkStack_CustomGasToken_Adapter` contract first [pulls the required amount of the custom gas token from the `CUSTOM_GAS_TOKEN_FUNDER`](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L186). Subsequently, it should approve the calculated `txBaseCost` for use by the `sharedBridge`.

However, in [line 230](https://github.com/across-protocol/contracts/blob/77761d74152e319e6edd6d4d766cb46c39e6f38d/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L230), instead of approving the `txBaseCost` amount to the intended `sharedBridge` contract, the approval is incorrectly directed towards the `USDC_SHARED_BRIDGE` contract. This will lead to the failure of the `relayTokens` function, specifically when attempting to bridge USDC via the shared bridge because the `sharedBridge` will not have the necessary allowance to deduct the `txBaseCost` in custom gas tokens.

Consider directing the approval of the `txBaseCost` amount of custom gas tokens to the `sharedBridge` contract address instead of the `USDC_SHARED_BRIDGE` contract address.

_**Update:** Resolved in [pull request #981](https://github.com/across-protocol/contracts/pull/981) at commit [6db3e38](https://github.com/across-protocol/contracts/pull/981/commits/6db3e382293cec7fe0cb7f3585a62d6228d7cd07)._

Conclusion
----------

OpenZeppelin conducted a diff audit of the changes introduced to the Across Protocol contracts in [pull request #941](https://github.com/across-protocol/contracts/pull/941) and [pull request #944](https://github.com/across-protocol/contracts/pull/944). The main update consists of modularized support for bridging USDC tokens between Ethereum and ZK-Stack-based chains, particularly to fit the needs for Lens (L2) using Circle's bridged (upgradable) USDC standard. Although currently meant for the Lens protocol, the added modularity is implemented in such a way that it can be reused for any ZK-Stack-based project that needs to customize their USDC bridging logic.

Overall the implementation was found to be sound. Only one client-reported issue and one low-severity issue were reported, along with various recommendations aimed at improving the documentation. The Across Protocol team is appreciated for their responsiveness throughout the audit.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kHTi1A-rTzHtc0MhuLA7Ui0A5XZOA&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=189747065167&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=8dcc6c78-295a-48b5-be2f-39d5dc0ba33d&redirect_url=APefjpGX--2q3EMakqX6RdkOa7koULHceWwbvGBfjwB-em5YRDoXK2SRKCTznm5Vn_sr4wyBUunL3OlYW-9rsIQPijay1CKDr5bk1b1_p88Gn9i4MBf6g2duvnvPEpDywAwGJ2YmAVLhEqx9AlgweRqyI3KA4fZc46pFlOTyp3ulVbynCp-Ok6ZUJtk8-ypBBt1oWngyUZvfBSCzmKNzf2_btA4rA2y8w5ZWjrT0Sivy8m3llsIiEIxS_T71UXd292IyX_i8z6LS&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Fbridged-usdc-support-audit&ts=1770534157161&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.74.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")