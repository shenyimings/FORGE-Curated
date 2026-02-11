\- August 27, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

**Type:** Cross-Chain  
**Timeline:** August 25, 2025 → August 25, 2025**Languages:** Solidity

**Findings**Total issues: 2 (2 resolved)  
Critical: 0 (0 resolved) · High: 0 (0 resolved) · Medium: 2 (2 resolved) · Low: 0 (0 resolved)

**Notes & Additional Information**0 notes raised (0 resolved)

Scope
-----

OpenZeppelin conducted a diff audit of the [across-protocol/contracts](https://github.com/across-protocol/contracts) repository at head commit [d9826e3](https://github.com/across-protocol/contracts/pull/1075/commits/d9826e30b51bbb3067df07c9532f4a5f6fe56f1c) against base commit [f2415a2](https://github.com/across-protocol/contracts/commit/f2415a29af7aadd61321d26da51d14a233ec2db8).

In scope were the following files:

`contracts/Polygon_SpokePool.sol
contracts/chain-adapters/Polygon_Adapter.sol` 

System Overview
---------------

The changes under review prepare the Across protocol Polygon contracts for the USDT (USDT0) rollout. This is achieved by wiring in an additional bridge path using OFT (LayerZero’s Omnichain Fungible Token) alongside the existing Polygon PoS and Circle CCTP flows:

*   **Polygon SpokePool**: The constructor now accepts OFT config (destination EID + native-fee cap) and, on withdrawals, routes by asset: CCTP for USDC, OFT if a messenger is registered for the token, and otherwise through the Polygon PoS bridge.
    
*   **Polygon Adapter (L1→L2)**: This adapter adds OFT for tokens (notably USDT0) when an OFT messenger is configured. Otherwise, it falls back to the Polygon PoS bridge.
    

Privileged Roles and Trust Assumptions
--------------------------------------

The in-scope changes added neither any new privileged roles nor did they modify any existing roles. Please refer to previous audit reports for more information on privileged roles within this codebase.

During the audit, the following trust assumptions were made:

*   It is assumed that the correct [`_oftDstEid`](https://github.com/across-protocol/contracts/blob/d9826e30b51bbb3067df07c9532f4a5f6fe56f1c/contracts/Polygon_SpokePool.sol#L85) is set in `Polygon_SpokePool`.
*   It is assumed that the correct [`_oftDstEid`](https://github.com/across-protocol/contracts/blob/d9826e30b51bbb3067df07c9532f4a5f6fe56f1c/contracts/chain-adapters/Polygon_Adapter.sol#L102) is set in `Polygon_Adapter`.
*   It is assumed that the OFT messenger contracts are correctly set in the pre-configured [`oftMessengers`](https://github.com/across-protocol/contracts/blob/d9826e30b51bbb3067df07c9532f4a5f6fe56f1c/contracts/SpokePool.sol#L118) for `Polygon_SpokePool`.
*   It is assumed that the OFT messenger contracts are correctly set in [`OFT_ADAPTER_STORE`](https://github.com/across-protocol/contracts/blob/d9826e30b51bbb3067df07c9532f4a5f6fe56f1c/contracts/libraries/OFTTransportAdapterWithStore.sol#L30-L32) for `Polygon_Adapter` on Ethereum mainnet.

Medium Severity
---------------

### Excess Gas Remains in `SpokePool`

The `Polygon_SpokePool` contract is intended to support sending USDT0 to Ethereum mainnet. This is done when an account calls the [`executeRelayerRefundLeaf` function](https://github.com/across-protocol/contracts/blob/d9826e30b51bbb3067df07c9532f4a5f6fe56f1c/contracts/SpokePool.sol#L1208-L1212) of the `Polygon_SpokePool` contract. Within this function, a call is made to the [`_transferViaOFT` function](https://github.com/across-protocol/contracts/blob/d9826e30b51bbb3067df07c9532f4a5f6fe56f1c/contracts/libraries/OFTTransportAdapter.sol#L69) of the `SpokePool` contract, in which `_messenger.quoteSend` is used to return the amount of fees which should be forwarded with the [`_messenger.send` call](https://github.com/across-protocol/contracts/blob/d9826e30b51bbb3067df07c9532f4a5f6fe56f1c/contracts/libraries/OFTTransportAdapter.sol#L102).

The caller of the `executeRelayerRefundLeaf` function must call `quoteSend` first to obtain the fee cost beforehand in order for them to forward the appropriate amount of gas with the call. If the price moves downwards in between obtaining the quote and calling `executeRelayerRefundLeaf`, then the excess native tokens sent with the call will remain in the contract.

Consider returning the excess native tokens to the caller at the end of the transaction.

**Update:** _Resolved in [pull request #1082](https://github.com/across-protocol/contracts/pull/1082)._

### Fee Cap May Be Too Low

A [fee cap](https://github.com/across-protocol/contracts/blob/d9826e30b51bbb3067df07c9532f4a5f6fe56f1c/deploy/011_deploy_polygon_spokepool.ts#L24) of `1e18` is set upon the deployment of the `Polygon_SpokePool` contract. Since the fee is calculated for execution on the destination chain but is expressed in source-chain-native tokens, the fee required may be higher than the set `feeCap`. On the Polygon network, the native token is POL and 1 unit of POL is equal to USD ~0.24. This is unlikely to cover the execution fee for the destination chain (Ethereum mainnet). For example, fees for USDT0 transfers from L2 chains such as Optimism to Ethereum mainnet are quoted at USD ~1.26 at this time (about 5 POL). The LayerZero documentation also provides a helpful [example](https://docs.layerzero.network/v2/concepts/protocol/transaction-pricing#example-scenario) of fee calculation for Polygon to Ethereum mainnet transfers. Therefore, cross-chain transfers for USDT0 - where the destination chain is Ethereum mainnet - may fail.

Consider setting a higher fee cap which takes into account the lower relative value of the native POL token to ETH.

**Update**: _Resolved in [commit 6a9655e](https://github.com/across-protocol/contracts/pull/1083/commits/6a9655ea8bc7d7f526f6c7be7a94509372703a93)._

Conclusion
----------

The changes under review support the OFT functionality of USDT0 tokens on the Polygon network. The changes require an upgrade to the `Polygon_SpokePool` contract on the Polygon network and the `Polygon_Adapter` contract on Ethereum mainnet. Additional pathways were introduced within the `Polygon_SpokePool` and the `Polygon_Adapter` contracts, which utilize the `_transferViaOFT` function found in the previously audited `OFTTransportAdapterWithStore` contract to support sending USDT0 via LayerZero.

The review revealed two medium-severity issues. The first issue is related to the cap on fees set for the `Polygon_SpokePool` contract, which may have led to a failure to bridge USDT0 to Ethereum mainnet. The second issue relates to the refunding of excess gas, should a stale quote be used.

Overall, the changes implemented appear to be sound and are only restricted to the files necessary to support bridging USDT0 across the Ethereum mainnet and Polygon networks.