\- July 3, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

**Type:** Cross-Chain  
**Timeline:** May 19, 2025 → May 23, 2025**Languages:** Solidity

**Findings**Total issues: 32 (11 resolved, 4 partially resolved)  
Critical: 0 (0 resolved) · High: 1 (0 resolved) · Medium: 7 (4 resolved, 1 partially resolved) · Low: 13 (1 resolved, 3 partially resolved)

**Notes & Additional Information**11 notes raised (6 resolved)

  
Scope

OpenZeppelin performed a differential audit of the [across-protocol/contracts](https://github.com/across-protocol/contracts/) repository at commit [c5d75410](https://github.com/across-protocol/contracts/tree/c5d7541037d19053ce2106583b1b711037483038) against base commit [c88ac8ad](https://github.com/across-protocol/contracts/tree/c88ac8adecdea13284531c0df54f37d74b0aa08c/). Specifically, the changes highlighted in [this diff](https://github.com/across-protocol/contracts/compare/c88ac8a...c5d75410) were the main subject of this audit.

In addition, the following two pull requests were also audited:

*   [Pull request #1031](https://github.com/across-protocol/contracts/pull/1031) at commit [e05964b](https://github.com/across-protocol/contracts/blob/e05964b074e6906e4dcb1d0fcd333dc7eb0b87be)
*   [Pull request #1032](https://github.com/across-protocol/contracts/pull/1032) at commit [06b14cdf](https://github.com/across-protocol/contracts/blob/06b14cdfb83d01ceae65b6445a4e6d629686faea)

In scope were the following files:

`contracts
├── AdapterStore.sol
├── AlephZero_SpokePool.sol
├── Arbitrum_SpokePool.sol
├── Ethereum_SpokePool.sol
├── Linea_SpokePool.sol
├── Ovm_SpokePool.sol
├── PolygonZkEVM_SpokePool.sol
├── Polygon_SpokePool.sol
├── Scroll_SpokePool.sol
├── SpokePool.sol
├── Succinct_SpokePool.sol
├── Universal_SpokePool.sol
├── ZkSync_SpokePool.sol
├── chain-adapters
│   ├── Arbitrum_Adapter.sol
│   └── Universal_Adapter.sol
├── libraries
│   ├── OFTTransportAdapter.sol
│   └── OFTTransportAdapterWithStore.sol
└── interfaces
    ├── SpokePoolInterface.sol
    └── V3SpokePoolInterface.sol` 

System Overview
---------------

Across is a cross-chain bridging protocol built around a central `HubPool` contract on Ethereum and per-chain `SpokePool` contracts deployed on supported networks. When a user initiates a cross-chain transfer, a Relayer (filler) observes the intent and fronts liquidity on the destination chain, enabling fast settlement. A network of Dataworkers submits proofs of these fill events, which the protocol uses to verify their validity and calculate the corresponding Relayer's reimbursement. Upon successful verification, the protocol does not reimburse the Relayer on the destination chain directly. Instead, the Relayer can decide where it wants to be refunded. The `HubPool` contract governs cross-chain settlement, maintains the global state, and performs final token reimbursements and accounting.

[These changes](https://github.com/across-protocol/contracts/compare/c88ac8a...c5d75410) introduce support for bridging LayerZero OFT (Omnichain Fungible Token) assets such as USDT0 by integrating LayerZero's messaging standard into Across's Transport Layer. The main bridging logic is found in the `OFTTransportAdapter` contract, which is employed in both directions:

1.  L1->L2 transfers: On the L1 side, the selected Adapters (e.g., `Arbitrum_Adapter`) inherit from the `OFTTransportAdapterWithStore` contract, which uses the global `AdapterStore` contract to map tokens to their corresponding OFT messengers.
    
2.  L2->L1 transfers: On the L2 side, each `SpokePool` contract (e.g., `Arbitrum_SpokePool`) inherits the `OFTTransportAdapter` contract via the base `SpokePool` contract and maintains its own local token-messenger mapping through a setter/getter pattern.
    

In both flows, the `_transferViaOFT` function ensures correct LayerZero fee quoting, applies a maximum allowed fee `FEE_CAP`, and invokes the OFT messenger's `send` function to relay tokens across chains. This integration allows Across to wrap LayerZero's OFT standard for cross-chain transfers within its own economic model of Relayers, fill proofs, and settlement via the Ethereum-based `HubPool` contract.

Note that the bridging mechanism described above is not used for sending user assets. As stated earlier, these are delivered by Relayers who front liquidity on the destination chain. Rather, bridging via the newly introduced `_transferViaOFT` function is part of the protocol's internal accounting that is used to rebalance liquidity across `SpokePool` contracts and the `HubPool` contract, and to reimburse Relayers by bridging tokens from L2 to the L1 `HubPool` contract. In special cases where a Relayer fills a transfer on L1 (e.g., for an L2->L1 user request), the reimbursement occurs entirely on L1 without using the aforementioned function.

Pull request #1031 removes legacy functionality that provided the option to set the address of `outputToken` to the zero address. This used to indicate that the output token is to be interpreted as the equivalent of the input token on the destination chain. The motivation for removing this functionality is the inability to determine the equivalent token for some chains. Previously the equivalence was determined through pool rebalance routes, which used to connect all supported tokens. However this is no longer the case i.e., not all tokens have a connecting pool rebalance route.

Pull request #1032 adds support for EIP-7702 delegated wallets to receive ETH, as opposed to wrapped tokens (e.g., WETH). The latter is the default token type for regular smart contracts.

Security Model and Trust Assumptions
------------------------------------

During the audit, the following trust assumptions were identified:

### `SpokePool` Admin

The `SpokePool` admin is trusted to behave honestly and responsibly. Specifically:

*   The `SpokePool` admin is trusted to correctly map the messenger to the token contract address, specifically through the [`setOftMessenger`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L362) function, which allows for overwriting the values in the `oftMessengers` mapping without thorough validation. The risk that a malicious or honest-but-negligent admin may map the OFT messenger to the wrong token address or even to a non-token address is covered by this trust assumption.
*   It is implicitly trusted that the `SpokePool` contract's admin will not change the token mapping of the messenger through the [`setOftMessenger` function](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L362-L364) while tokens are being transferred through that method and the transaction has not been mined at the origin. In such a scenario, the transfer might revert at best or cause inconsistencies.
*   The `SpokePool` contract's admin has full control over the relaying configuration. Specifically, it is [possible](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Arbitrum_SpokePool.sol#L91-L95) to end up with a configuration in which USDC tokens are relayed over the OFT bridge (instead of over CCTP). In addition, even after the OFT bridge has been configured to relay USDC tokens, they [may still](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Arbitrum_SpokePool.sol#L91) get relayed over the CCTP bridge if the latter gets enabled in the meantime.

### `AdapterStore` Admin

There is a trust assumption that the admin of `AdapterStore` is honest. Specifically, it is assumed that they [set](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AdapterStore.sol#L52) the IOFT messengers to valid IOFT addresses in the `AdapterStore` contract.

### LayerZero Backend

There is implicit trust in the LayerZero backend implementation:

*   The call to the [`send` method](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L94) in the messenger returns two structs: [`MessagingReceipt`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/interfaces/IOFT.sol#L11) and [`OFTReceipt`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/interfaces/IOFT.sol#L38). Of those, only the latter is checked, trusting that the operation is successful on the LayerZero side. In particular, this trust covers concerns in a scenario in which the OFT layer returns a receipt, but message delivery still fails at the destination, with the potential result of a loss of funds.
*   The [`quoteSend` method](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L85) from the LayerZero backend, called in the `_transferViaOFT` function call of the `OFTTransportAdapter` contract, is trusted to behave "properly". Specifically, it is trusted that LayerZero will not unreasonably increase the `fee` returned by `quoteSend`, for instance, to a value close to the `OFT_FEE_CAP` with the goal of extracting maximum economic profit from the relaying process, thereby potentially stalling execution by making it economically infeasible.

### EIP-7702 Delegation Wallets

The following trust assumptions were made regarding EIP-7702 Delegations Wallets:

*   The protocol may not be compatible with implementations of EIP-7702 wallets, as these may contain logic that might not work with the current expected flow.
*   The protocol treats EIP-7702 delegated wallets as EOAs that receive ETH as opposed to regular smart contracts receiving ERC-20 tokens. Delegated wallets may not have the `fallback` or `receive` functions implemented, which will prevent them from receiving ETH. Similarly, if the wallets do not implement respective assets' hooks (such as the ones found in ERC-1155 or ERC-721) then these will not be able to receive those assets, which will result in the transaction being reverted.
*   In view of deviated expectations after two iterations of calls, it cannot be assumed that EIP-7702 delegated wallets will not change their implementation.
*   Depending on a wallet's signature mechanism, it may be possible to have replayability attacks on different chains from those wallets.
*   As opposed to a regular EOA, sending ETH or assets with hooks could initiate a reentrancy point in the protocol.

### General Trust Assumptions

The following general trust assumptions were made as part of the audit:

*   If a token listed to be bridged over OFT supports pausability, it could lead to message-related issues similar to the high-severity issue (H-01) described in this report.
*   It is assumed that there is a single distinct messenger per token. If this assumption is violated, finality might be broken.
*   It is assumed that the admin is diligent and honest and never sets a wrong endpoint/chainID. If that happens, funds can be locked.
*   The protocol relies on Dataworkers and the optimistic oracles working correctly when it comes to keeping track of refunds and rebalances.

### Security Model

The `_unwrapwrappedNativeTokenTo` function of the `SpokePool` contract [uses](https://github.com/across-protocol/contracts/blob/06b14cdfb83d01ceae65b6445a4e6d629686faea/contracts/SpokePool.sol#L1611) the `isContract` function from the OpenZeppelin contracts library to check if an address corresponds to an EOA account. However, the `isContract` function is part of an older version of the library (4.x) and has been removed in the latest one (5.x). The use of `isContract` is strongly discouraged in view of the known risks [listed](https://docs.openzeppelin.com/contracts/4.x/api/utils#Address-isContract-address-) in the library documentation (cf. sections marked "IMPORTANT"). It is worth mentioning that this also applies to the introduction of the EIP-7702 EOA wallets that behave like a contract.

Integration
-----------

The following are some important details that should be kept in mind during future integrations:

*   The [`_transferViaOFT` function](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L57) makes an [external call](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L94) to the messenger's `send` method, where the messenger is mapped to a given LayerZero-supported token. In principle, such an external call may open the door to reentrancy attacks. Currently, this is not an issue since the `_transferViaOFT` function gets called by functions protected by the `nonReentrant` modifier. However, in future integrations, it is crucial to be aware of this fact and address it by adding the non-reentrancy feature in the `_transferViaOFT` function.
*   In the `Ethereum_SpokePool` contract, the second argument of the [`__SpokePool_init` function](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Ethereum_SpokePool.sol#L40), which is supposed to be `_crossDomainAdmin`, is set to be the same as the third argument (`_withdrawalRecipient`). The [documentation states](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Ethereum_SpokePool.sol#L32) that _"`crossDomainAdmin` is unused on this contract"_. However, it is understood that there is an assumption in play here: for the function in question, the `HubPool` contract will always be both the withdrawal recipient and the admin. In future integrations, it is recommended to keep in mind this assumption and verify that it holds. Otherwise, that address might get extra permissions that it was not meant to have.
*   Pull request #1031 removes deprecated functionalities, which include the usage of the zero address in the `outputToken` token to signal equivalence to the one provided by the router. This should be kept in mind for preserving consistency in future, and past, integrations.

Design Choices
--------------

*   The `OFTTransportAdapter` contract's implementation [restricts the usage](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L79-L81) of the extra options, composable messages, and commands from LayerZero. If certain transfers or assets do need to use them, the outcome might not be the expected one.
*   The `AdapterStore` contract allows for using different messenger types as keys for the [`crossChainMessengers` mapping](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AdapterStore.sol#L7). However, all adapters that can currently use the `AdapterStore` contract are not allowed to select such type as its value [is hardcoded](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapterWithStore.sol#L21). This means that the admin can set messengers whose type does not match the `OFT_MESSENGER` one, but messengers will not be used. Moreover, they can remain unnoticed until they can perform a malicious action in the future.
*   Not all the adapters and `SpokePool` contracts that are part of the introduced changes will allow for the usage of OFT Transport, even though they inherit the logic. These contracts use hardcoded values that, while not directly restricting the OFT Transport functionality, render it useless. However, it is worth mentioning that the attack surface could further be reduced by taking the OFT Transport logic out of the base contract (`SpokePool`).

High Severity
-------------

### Failed Messenger Can Render the Canonical Methods Useless

The [`Arbitrum_Adapter`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/Arbitrum_Adapter.sol#L133) and [`Arbitrum_SpokePool`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Arbitrum_SpokePool.sol#L94) contracts implement a new `else if` conditional statement branch to make use of the `_transferViaOFT` function from the `OFTTransportAdapter` contract. To enter into this branch, the only requirement is for the [messenger associated with that token](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/Arbitrum_Adapter.sol#L127) to [not be zero](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/Arbitrum_Adapter.sol#L132).

The call stack on the `HubPool` contract's side is: [executeRootBundle](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/HubPool.sol#L620) -> [\_sendTokensToChainAndUpdatePooledTokenTrackers](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/HubPool.sol#L876) -> [relayTokens](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/Arbitrum_Adapter.sol#L121) -> [\_transferViaOFT](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L57). In this call sequence, if the messenger throws an error in its internal operation when [sending the message](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L94) inside the innermost call to the `_transferViaOFT` function, the reversion will be propagated all the way up to the `_sendTokensToChainAndUpdatePooledTokenTrackers` function and the assets [will not be sent](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/HubPool.sol#L901-L910). Not only that, since the assets are [sent in the same call as the message with the refund roots](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/HubPool.sol#L686-L697), the roots will also not be sent to the respective `SpokePool` contract. As the bridging mechanisms are checked sequentially, the Arbitrum Gateway, which [comes after the OFT Transport method](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/Arbitrum_Adapter.sol#L132-L178), will not be able to be used as a replacement, meaning that there will be no way of transferring those funds until either the messenger resolves the conflicts or the admin role removes it from the `oftMessengers` mapping, possibly resulting in a stall situation until it gets resolved.

In order to prevent a scenario in which assets need to be moved into or out of Arbitrum (e.g., there are insufficient assets) when the OFT messenger is currently not working, consider replacing these patterns in all the affected contracts to allow for bypassing a failing messenger so that the canonical alternative can be used. Alternatively, consider using a `try-catch` mechanism to prevent the propagation of the revert that could also affect the bridging of the root hashes.

_**Update:** Acknowledged, not resolved. The team stated:_

> _This is indeed an important situation, which will not, however, be mitigated by try - catching._
> 
> _The scenario we imagine is OFT transfer breaking (messenger freezing the route) for some OFT token, say USDT. As discussed in Slack, USDT is not bridgeable in a meaningful way to L2s via canonical bridges. If the OFT messenger for that route is shut down / frozen, there's indeed no way for our system to rebalance USDT to that destination chain because OFT is supposed to be the only available bridge option for USDT._
> 
> _If a situation like this ever happens though, it's crucial that the engineering team knows about it immediately. We can not just silently try catch, because system will not continue to operate correctly without the rebalance required by it (e.g. we're trying to repay relayers on Arbitrum with USDT that's not in Spoke's balance -> that won't work). The mitigation scenario we envision is the following:_
> 
> _1\. We deploy a new `ArbitrumAdapter` with commented `_transferViaOft` line commented out, allowing bundle to execute._
> 
> _2\. At this point, any USDT relayer refund leaves on Arbitrum will fail to execute and will page us a lot. We deal with this by modifying the executor (probably) to suppress this noise._
> 
> _3\. Once OFT is back unfrozen for this path, we use `relaySpokePoolAdminFunction` in conjunction with something like [Arbitrum\_SendTokensAdapter.sol](https://github.com/across-protocol/contracts/blob/a5fbdf13a95a7eaf50eb907c85ec03845a4aacd0/contracts/chain-adapters/Arbitrum_SendTokensAdapter.sol) (change it's code to OFT logic) to backfill the missing USDT tokens on L2 (that were not executed properly during 1)._
> 
> _Otherwise, if OFT route is never unfrozen, we have no way to repay the relayers on Arbitrum. Summing this up, doing anything other than sending the funds through the OFT adapter should require manual intervention. (i.e. no try-catch and drop the sending of funds)._

Medium Severity
---------------

### Insufficient Validation of Sent Amount in `OFTTransportAdapter`

In the `OFTTransportAdapter` contract, the [`_transferViaOFT` function](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L94-L97) gets the `OFTReceipt` output containing two elements: the amount sent at origin and the amount received at destination. The current implementation only validates the amount received at destination, ensuring that it matches the input amount specified by the user. However, this approach overlooks the validation of the amount sent, potentially increasing the attack surface.

Due to the lack of validation of values sent at origin, a scenario might materialize whereby the messenger could take more assets at origin, deposit the correct lesser amount at destination, and pass the check. [LayerZero's documentation on the `_debit` function](https://docs.layerzero.network/v2/developers/evm/oft/quickstart#constructing-an-oft-contract) states that _"In NON-default OFT, amountSentLD could be 100, with a 10% fee, the amountReceivedLD amount is 90, therefore amountSentLD CAN differ from amountReceivedLD."_. The current implementation tries to mitigate this through the [`forceApprove` call](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L92) method associated with the token. Still, if its implementation allows flexible or greater values than the amount sent, the outcome would rely on the assumption that the messenger does not take more than needed.

Consider imposing restrictions on the values sent at origin to reduce the attack surface and prevent situations such as the aforementioned ones. In addition, consider validating that the tokens used through the OFT messenger do not present a behavior deviation or edge cases when using the approval functionality.

_**Update:** Resolved in [pull request #1027](https://github.com/across-protocol/contracts/pull/1027)._

### Compromised Messengers Cannot Be Removed

In the `SpokePool` contract, the [\_setOftMessenger](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L1739) function allows for adding or updating an OFT messenger address for a particular token. However, if the current messenger is compromised or needs to be taken down, there is no functionality that would allow the admin to remove it from the available messengers (without replacing it with a new one).

Furthermore, it is not possible to use the `_setOftMessenger` function to set it to zero, as there is a [validation done over its token](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L1740) that would revert if the messenger is set to the zero address or to an address that does not have the `token` method implemented or to an address that does not match the passed one. Since temporarily setting a (compromised) messenger address to a dummy contract that implements the `token` method could also be dangerous as it might not stop the whole OFT flow, the admin might not be able to react fast enough and stop using it.

Consider implementing a method that would allow the admin to remove a messenger from the storage.

_**Update:** Resolved in [pull request #1034](https://github.com/across-protocol/contracts/pull/1034). The team stated:_

> _Added ability for admin to always set messenger to zero address._

### OFT Transfer Might Revert Due to Non-Zero ZRO Token Fee Quote

The `OFTTransportAdapter` contract implements the [`_transferViaOFT` function](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L57), meant to interact with the OFT messenger and send the funds with that method. To do so, it first [quotes the fees](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L85), which are returned as [native or ZRO token fees](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/interfaces/IOFT.sol#L18-L19). Later, this same output is used as [part of the message](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L94).

Even though the `OFTTransportAdapter` contract instructs that it will [pay the fees in native tokens](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L85), there is no validation that the value for fees in ZRO tokens is zero, meaning that it will be passed once again to the messenger. This means that if the implementation of the messenger outputs both quotes at the same time, it might not recognize with which asset it will be paid, resulting in a reversion if it tries to get paid with ZRO. As seen in an [example from LayerZero](https://docs.layerzero.network/v2/developers/evm/oft/quickstart#calling-send), in the case of paying in native tokens, the `lzTokenFee` parameter is set to zero.

In order to prevent unexpected outcomes and reversions, especially if the messenger deviates in behavior, consider asserting that the returned `lzTokenFee` is zero when quoting for the cost. Furthermore, consider adding more scenarios to the [mocked contracts](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/test/MockOFTMessenger.sol#L18-L20) to validate proper integration with protocols.

_**Update:** Resolved in [pull request #1029](https://github.com/across-protocol/contracts/pull/1029). The team stated:_

> _Added a zero-check for `lzTokenFee` and added some fee negative-scenario tests (partially addressing M-04)._

### Insufficient Test Coverage

Throughout the codebase, and in particular in the added changes, multiple instances of insufficient test coverage were identified:

*   There are different test suites implemented at the same time, namely Hardhat and Foundry. Maintaining different suites instead of having all under the same one adds friction and error-proneness, and increases the cost for the developer to keep it secure.
*   Similar contracts in the protocol use different test suites. In particular, [Universal contracts](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/test/evm/foundry/local/Universal_Adapter.t.sol#L16) rely on Foundry, while the [Arbitrum](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/test/evm/hardhat/chain-adapters/Arbitrum_Adapter.ts#L59) contracts rely on Hardhat. Standardizing the tests would allow for testing similar contracts under the same cases, which could be beneficial when finding edge cases or bugs.
*   New additions only add 5 single positive overall cases to the suite, leaving many other edge cases untested and not asserting any negative situations.
*   The values used for testing the outgoing fees have been [set to zero](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/test/evm/foundry/local/Universal_Adapter.t.sol#L291), as a result of which the whole fee protection is bypassed.
*   Contracts are not fuzzed to find edge cases that could be used for exploits.
*   There is a lack of integration with the LayerZero protocol, which requires analyzing its caveats, edge cases, and behaviors, and testing the project under such conditions.

Insufficient testing, while not a specific vulnerability, implies a high probability of additional undiscovered vulnerabilities and bugs. It also exacerbates multiple interrelated risk factors in a complex code base. This includes a lack of complete, implicit specification of the functionality and exact expected behaviors that tests normally provide, which increases the chances of correctness issues being missed. It also requires more effort to establish basic correctness and reduces the effort spent exploring edge cases, thereby increasing the chances of missing complex issues.

Moreover, the lack of repeated automated testing of the full specification increases the chances of introducing breaking changes and new vulnerabilities. This applies to both previously audited code and future changes to currently audited code. Underspecified interfaces and assumptions increase the risk of subtle integration issues which testing could reduce by enforcing an exhaustive specification.

To address these issues, consider implementing a comprehensive multi-level test suite. Such a test suite should comprise contract-level tests with 95%-100% coverage, per chain/layer deployment, and integration tests that test the deployment scripts as well as the system as a whole, along with per chain/layer fork tests for planned upgrades. Crucially, the test suite should be documented in such a way that a reviewer can set up and run all these test layers independently of the development team. Some existing examples of such setups can be suggested for use as reference in a follow-up conversation. In addition, consider merging all the test suites into a single one for better maintenance. Implementing such a test suite should be of very high priority to ensure the system's robustness and reduce the risk of vulnerabilities and bugs.

_**Update:** Partially resolved in [pull request #1038](https://github.com/across-protocol/contracts/pull/1038). The team stated:_

> _Addressed these 2 points:_
> 
> _\- New additions only add 5 single positive overall cases to the suite, leaving many other edge cases untested and not asserting any negative situations._
> 
> _\- The values used for testing the outgoing fees have been set to zero, as a result of which the whole fee protection is bypassed._
> 
> _Added multiple new local (unit) test-cases (fee ones were added as part of the fix for issue M-03) as well as a fork test for sending USDT via a `Universal_Adapter`. A fork test can be run with this command:_
> 
> _`NODE_URL_1=<your-ethereum-rpc-url> forge test --match-path test/evm/foundry/fork/UniversalAdapterOFT.t.sol`_

### OFT Transfers Revert if Chains Have Different Local Decimals

In the `OFTTransportAdapter` contract, the `_transferViaOFT` function [checks](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L97) if the expected value received at the end matches the input passed at origin. In LayerZero, the [default value for the local decimals is 18](https://docs.layerzero.network/v2/developers/evm/oft/quickstart#constructing-an-oft-contract), but it can be changed. In such a scenario, the `amountReceivedLD` value will be expressed in local decimals at destination and it will not match the `_amount` input expressed in local decimals at origin. Consequently, the transfer will revert, and movement using the OFT mechanism in that combination will get stalled. Note that the movement will work if the decimals on both chains are the same.

Consider taking into account the difference in decimals on both chains and performing the conversions when validating the received amount.

_**Update:** Acknowledged, not resolved. Assets that implement different decimals on source and destination, and therefore deviate from the [default implementation](https://github.com/LayerZero-Labs/LayerZero-v2/blob/88428755be6caa71cb1d2926141d73c8989296b5/packages/layerzero-v2/evm/oapp/contracts/oft/OFTCore.sol#L356), might override the `OFTAdapter._debit()` and `OFTCore._debitView()` functions, causing the reversion of the validations in the `_transferViaOFT` function. OFT implementations whose decimals are the same might not present this issue._

_The team stated:_

> _`_transferViaOft` flow: We're interacting with OFTAdapter on chain. Here's [default implementation](https://github.com/LayerZero-Labs/LayerZero-v2/blob/88428755be6caa71cb1d2926141d73c8989296b5/packages/layerzero-v2/evm/oapp/contracts/oft/OFTAdapter.sol#L20) of that. We're calling (call is to `OFTAdapter` which inherits `OFTCore`):_
> 
> _`OFTCore.send()` -> `OFTAdapter._debit()` -> `OFTCore._debitView()`_
> 
> _This call chain starts [here](https://github.com/LayerZero-Labs/LayerZero-v2/blob/88428755be6caa71cb1d2926141d73c8989296b5/packages/layerzero-v2/evm/oapp/contracts/oft/OFTCore.sol#L173). Within `_debitView`, which is the default OFT implementation, we see [this](https://github.com/LayerZero-Labs/LayerZero-v2/blob/88428755be6caa71cb1d2926141d73c8989296b5/packages/layerzero-v2/evm/oapp/contracts/oft/OFTCore.sol#L349):_
> 
> _`amountSentLD = _removeDust(_amountLD);`_ _`amountReceivedLD = amountSentLD;`_
> 
> _Amounts received and sent are both in the local decimals of the \*source chain(, so decimal discrepancies will not be a problem in the default OFT implementation. USDT0 uses the same underlying logic (although their [contracts](https://vscode.blockscan.com/ethereum/0xcd979b10a55fcdac23ec785ce3066c6ef8a479a4) are upgradeable)._
> 
> _All in all, we don't expect to support tokens with non-standard decimal implementation in `_debit()` nor do we expect OApps to override this function in terms of decimals logic. What we might expect some OApps do is maybe override `_debit` in terms of adding extra fees, we won't be able to support those just yet._

### Inconsistent Use of the `__gap` Variable

Throughout the codebase, multiple instances where the `__gap` variable is being used inconsistently were identified, which could cause security and operational problems.

The number of reserved slots does not seem to follow a particular pattern. For example, it has been set as [1000 in cases where no local storage variables have been defined](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/upgradeable/MultiCallerUpgradeable.sol#L77), but it is [also 1000 in cases where local storage variables have been defined](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Arbitrum_SpokePool.sol#L15-L19). This means that the sum of the reserved slots and the used-up slots (i.e., used by the definition of storage variables) does not add up to a common value, sometimes greatly exceeding the value of the rest of the contracts. This is, for instance, the case with the `SpokePool` contract which defines multiple storage variables but also keeps [997 slots reserved](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L1762) using the `__gap` variable, resulting in the total value of storage slots being greater than 1000. The importance of keeping a common value is that it helps check whether a possible collision could happen between contracts, in particular when they inherit each other.

In addition, not having proper [documentation for keeping track](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L1759-L1762) of which slot represents which storage variable could cause a mismatch between the slots used and the variables defined. This might push the storage layout of the inheritance and cause storage collisions. Moreover, it has been observed that, in the [past](https://github.com/across-protocol/contracts/pull/991/files#diff-c828c513da79ba8aaef90514612391ab755989974a14d8e480ae02ebd9cfb4be), changes have been made to the `__gap` variable that [increased its length](https://github.com/across-protocol/contracts/pull/991/files#diff-c828c513da79ba8aaef90514612391ab755989974a14d8e480ae02ebd9cfb4beR1786) while [removing a storage variable](https://github.com/across-protocol/contracts/pull/991/files#diff-c828c513da79ba8aaef90514612391ab755989974a14d8e480ae02ebd9cfb4beL122). Such changes are dangerous as they can create situations in which a new variable that is added after such a change might not have an empty value and could be used in an exploit.

Consider reviewing the whole protocol to assert that the slots are being used as planned, comprehensively documenting the variables and their slots in the respective `__gap` variable. Additionally, from now onward, consider standardizing the value that will be used for future contracts.

_**Update:** Resolved in [pull request #1039](https://github.com/across-protocol/contracts/pull/1039). The team stated:_

> _Updated `__gap` documentation._

### EIP-7702 EOA Accounts' Treatment Could Result in Reentrancy

When the `to` address is detected as a EIP-7702 EOA wallet by the [`_is7702DelegatedWallet`](https://github.com/across-protocol/contracts/blob/06b14cdfb83d01ceae65b6445a4e6d629686faea/contracts/SpokePool.sol#L1611) function when sending ETH or WETH, the `_unwrapwrappedNativeTokenTo` function from the `SpokePool` contract will first convert the WETH into ETH and then [send](https://github.com/across-protocol/contracts/blob/06b14cdfb83d01ceae65b6445a4e6d629686faea/contracts/SpokePool.sol#L1613) it to the wallet with a low level `.call` call. As such, this low level call does not limit the gas to 2300, being able to perform more complex operations.

Also, as the EIP-7702 EOA wallets could use any implementation, it might be possible that their `receive` or `fallback` method implement malicious logic to reenter the protocol when it is not expected.

Although several functions are protected against reentrancy, consider reducing the attack vector in the protocol by treating the EIP-7702 EOA wallets as contracts by sending WETH. Alternately, consider reducing the gas stipend for the low level `.call` call so it cannot perform any storage change nor external call to another contract.

_**Update:** Acknowledged, not resolved. The team stated:_

> _The fill functionality already supports external calls with unlimited gas budgets at the same point in the code. From our perspective, any ETH call to a 7702 wallet could also trigger a callback into the contract via the `handleV3AcrossMessage` callback right after with no state changes in between. We cannot think of any cases where re-entrancy would be a problem in one case, but not the other._
> 
> _For the protocol to function with its current feature set, it must be resilient to re-entrancy, in general. If the protocol is not resilient to re-entrancy, then we think that should be addressed in a way that covers all cases, not just the ETH to 7702 case._
> 
> _We do not think these changes will impact the security of the protocol, so we acknowledge, but choose not to make the suggested changes._

Low Severity
------------

### Lack of Validation On Linked Messengers

In the `SpokePool` contract, there is no standard way of checking whether a contract supports specific interfaces or features. In particular, when adding a messenger, the [single check](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L1740) being performed is whether the input address matches its `token` function against the one passed. As the `token` function is pretty common in a diverse set of contracts, a contract could be mistakenly passed that implements a `token` function and retrieves the particular token, but is not an `IOFT` type of contract. In such a scenario, the assignment will pass but will result in unexpected situations.

In the Ethereum ecosystem, more thorough validation can be accomplished if a contract is compliant with [EIP-165](https://eips.ethereum.org/EIPS/eip-165). An interface is a collection of functions that define a set of behaviors. By implementing a standard, contracts can expose a function to query whether they support specific interfaces, making it easier for other contracts to understand their capabilities. Since messengers might be upgraded and new functionality can be added to existing contracts, this standardization would also allow new versions to ensure backward compatibility.

Furthermore, the `IOFT` interface does [define the interface ID](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/interfaces/IOFT.sol#L48), which could be used to complement such validation when setting the messengers. Also, note that in the `AdapterStore` contract, the messengers added through [any of the functions](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AdapterStore.sol#L28-L64) are not being checked as they are in the [`SpokePool` contract](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L1740).

Consider defining and implementing a standard interface detection mechanism in modules that interact with external contracts to improve their overall usability, safety, and efficiency by providing a consistent way for contracts to query and identify the features they support. Moreover, consider performing the same verification in the `AdapterStore` contract to be consistent with the messengers' additions.

_**Update:** Partially resolved in [pull request #1033](https://github.com/across-protocol/contracts/pull/1033). The team stated:_

> _Added part of suggested change: IOFT validation on `AdapterStore.sol` side via calling `.token()`. This is meant to be human-error protection more than anything. Implementing EIP-165 calls was a bit too much to add._

### Misleading Documentation

Throughout the codebase, multiple instances of misleading documentation were identified:

*   In the `Universal_Adapter` contract, the [inline documentation states](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/Universal_Adapter.sol#L74) that the `relayTokens` function _"only uses the `CircleCCTPAdapter` to relay USDC tokens to CCTP enabled L2 chains"_. While this is partially true for that token, the new implementation also allows for using the [OFT method](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/Universal_Adapter.sol#L90-L92).
*   A [comment](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AlephZero_SpokePool.sol#L3) in the `AlephZero_SpokePool` contract states that _" Arbitrum only supports v0.8.19"_. However, on Arbiscan, newer versions are also [listed](https://arbiscan.io/solcversions) as being supported.

Consider updating the documentation to reflect the current behavior of the functionality.

_**Update:** Partially resolved in [pull request #1030](https://github.com/across-protocol/contracts/pull/1030). Only the `Universal_Adapter` contract has been updated._

### Logic Not Fully Deprecated

The `SpokePool` contract implements the basics of keeping track of the respective [OFT messengers against tokens](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L1739-L1749). It also inherits the [`OFTTransportAdapter` contract](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L226), to which it passes the respective input parameters from the `constructor` function. Currently, only the Arbitrum-based contracts (cf. AlephZero) and Universal `SpokePool` and adapters make use of such OFT functionality. This means that on any other chain, these `constructor` parameters are [set to zero](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Polygon_SpokePool.sol#L94-L96).

This approach raises the following issues:

*   Even though the [`_transferViaOFT` function](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L57) is not called in the implementation of such adapters or `SpokePool`s, and that possibly the [messenger and/or the token might not be set](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L85-L92), the usage of zero values in the [`OFT_DST_EID` and `OFT_FEE_CAP` parameters](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L45-L46) might increase the attack surface due to how they are [being used as checks](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L88). This could give rise to potential problems in a future upgrade where the flow could reach such a call and make it part of an exploit.
*   The admin can still [add/modify the messengers' mapping](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L362-L364) at will, as these functionalities are not blocked when the contract does not need the OFT feature. This could be a potential attack vector for future operations, in which a current admin could pass a certain messenger attached to a token while the chain does not support the OFT functionality, to then have it ready in the future once that changes.

Consider restricting the functionality of the OFT inherited by the adapters and the `SpokePool`s when they are not being used to prevent the aforementioned scenarios and reduce the attack surface.

_**Update:** Acknowledged, not resolved. The team stated:_

> _Having `SpokePool` inherit `OFTTransportAdapter` allows us to add OFT functionality to more spokes down the line more easily. What is more, `OFT_FEE_CAP` is meant to be protecting from sending an overly excessive fee. It's not responsible for protection against other scenarios. Set to `0`, it still fulfills it's role. Protection against incorrectly setting OFT messengers etc. depends on admin being honest._

### Abstract Contracts Allow Direct Modification of State Variables

The `internal` and `public` state variables in `abstract` contracts allow them to be directly modified by child contracts. This may break the expected properties for the state variables and limit off-chain monitoring capabilities due to the lack of event emissions for changes to the variables.

Specifically, in `SpokePool.sol`, the `SpokePool` abstract contract contains the [`oftMessengers`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L117) state variable which is `public`. Moreover, as the `oftMessengers` mapping is only being accessed by setters and getters inside the `SpokePool` contract, there is no need for keeping such high visibility on the child contracts.

Consider using `private` visibility for state variables in abstract contracts. In addition, consider creating `internal` functions for updating these variables which emit appropriate events and verifying if the desirable conditions are met.

_**Update:** Acknowledged, not resolved. The team stated:_

> _The proposed solution brings with it a limitation of not being able to see the set messengers on e.g. etherscan. While possible to mitigate by adding an additional public getter on the SpokePool, we feel like SpokePool code is already complex and adding code like this can overwhelm someone trying to understand it more. We'd like to keep the current visibility of `oftMessengers`_

### Missing Zero-Address Checks

When operations with address parameters are performed, it is crucial to ensure the address is not set to zero. Setting an address to zero is problematic because it has special burn/renounce semantics. This action should be handled by a separate function to prevent accidental loss of access during value or ownership transfers.

Throughout the codebase, there are multiple instances where operations are missing a zero address check:

*   The [`_setMessenger(messengerType, dstDomainId, srcChainToken, srcChainMessenger)`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AdapterStore.sol#L34) operation within the contract `AdapterStore` in `AdapterStore.sol`.
*   The [`_setMessenger(messengerTypes[i], dstDomainIds[i], srcChainTokens[i], srcChainMessengers[i])`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AdapterStore.sol#L52) operation within the contract `AdapterStore` in `AdapterStore.sol`.
*   The [`_adapterStore`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapterWithStore.sol#L17) operation within the contract `OFTTransportAdapterWithStore` in `OFTTransportAdapterWithStore.sol`.
*   The [`_setOftMessenger(token, messenger)`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L363) operation within the contract `SpokePool` in `SpokePool.sol`.

Consider adding a zero address check before assigning a state variable.

_**Update:** Acknowledged, not resolved. The team stated:_

> _After internal discussion, we think that zero-address checks here are a bit of overkill because all the functions mentioned are only callable by admin (except for `_adapterStore` case, but that's contract creation, and this contract can only be used within the system after admin action)_

### Missing Docstrings

Throughout the codebase, multiple instances of missing docstrings were identified. Particularly, in the following files:

*   `AdapterStore.sol`
*   `Arbitrum_Adapter.sol`
*   `Arbitrum_SpokePool.sol`
*   `OFTTransportAdapter.sol`
*   `OFTTransportAdapterWithStore.sol`
*   `Ovm_SpokePool.sol`
*   `PolygonZkEVM_SpokePool.sol`
*   `Polygon_SpokePool.sol`
*   `Scroll_SpokePool.sol`
*   `SpokePool.sol`
*   `Succinct_SpokePool.sol`
*   `Universal_Adapter.sol`
*   `Universal_SpokePool.sol`
*   `ZkSync_SpokePool.sol`

Consider thoroughly documenting all functions (and their parameters) that are part of any contract's public API, events, storage variables, and constants. Functions implementing sensitive functionality, even if not public, should be clearly documented as well. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Partially resolved at commit [84f87be](https://github.com/across-protocol/contracts/commit/84f87beed89c427d45e1c1ef7a0080d1e82f94ba). The team stated:_

> _Added docstrings to:_
> 
> _\- `AdapterStore.sol`_ _\- `OFTTransportAdapter.sol`_ _\- `OFTTransportAdapterWithStore.sol`_
> 
> _to keep changes to the OFT scope._

### Floating Pragma

Pragma directives should be fixed to clearly identify the Solidity version with which the contracts will be compiled.

Throughout the codebase, multiple instances of floating pragma directives were identified:

*   `AdapterStore.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AdapterStore.sol#L2) floating pragma directive.
*   `AlephZero_SpokePool.sol` has the [`solidity ^0.8.19`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AlephZero_SpokePool.sol#L5) floating pragma directive.
*   `Arbitrum_Adapter.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/Arbitrum_Adapter.sol#L2) floating pragma directive.
*   `Arbitrum_SpokePool.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Arbitrum_SpokePool.sol#L2) floating pragma directive.
*   `Ethereum_SpokePool.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Ethereum_SpokePool.sol#L2) floating pragma directive.
*   `Linea_SpokePool.sol` has the [`solidity ^0.8.19`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Linea_SpokePool.sol#L5) floating pragma directive.
*   `OFTTransportAdapter.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L2) floating pragma directive.
*   `OFTTransportAdapterWithStore.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapterWithStore.sol#L2) floating pragma directive.
*   `Ovm_SpokePool.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Ovm_SpokePool.sol#L2) floating pragma directive.
*   `PolygonZkEVM_SpokePool.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/PolygonZkEVM_SpokePool.sol#L2) floating pragma directive.
*   `Polygon_SpokePool.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Polygon_SpokePool.sol#L2) floating pragma directive.
*   `Scroll_SpokePool.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Scroll_SpokePool.sol#L2) floating pragma directive.
*   `SpokePool.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L2) floating pragma directive.
*   `Succinct_SpokePool.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Succinct_SpokePool.sol#L2) floating pragma directive.
*   `Universal_Adapter.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/Universal_Adapter.sol#L2) floating pragma directive.
*   `Universal_SpokePool.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Universal_SpokePool.sol#L2) floating pragma directive.
*   `ZkSync_SpokePool.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/ZkSync_SpokePool.sol#L2) floating pragma directive.

Consider using fixed pragma directives.

_**Update:** Acknowledged, not resolved. The team stated:_

> _After internal discussion, we concluded that moving to a fixed pragma is not something we'd like to do as a part of this audit. Maybe in the future! Thanks for the suggestion._

### Different Pragma Directives Are Used

In order to clearly identify the Solidity version with which the contracts will be compiled, pragma directives should be fixed and consistent across file imports.

Throughout the codebase, multiple instances of varying pragma directives were identified:

*   `AlephZero_SpokePool.sol` has the [`pragma solidity ^0.8.19;`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AlephZero_SpokePool.sol#L5) pragma directive but imports [`Arbitrum_SpokePool.sol`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Arbitrum_SpokePool.sol) which has a different pragma directive.
*   `Linea_SpokePool.sol` has the [`pragma solidity ^0.8.19;`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/Linea_SpokePool.sol#L5) pragma directive but imports [`SpokePool.sol`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol) which has a different pragma directive.

Consider using the same, fixed pragma directive across all files.

_**Update:** Acknowledged, not resolved. The team stated:_

> _After internal discussion, we concluded that moving to a fixed pragma is not something we'd like to do as a part of this audit. Maybe in the future! Thanks for the suggestion._

### Adapter Implementation Could Be Misused

The `Arbitrum_Adapter` contract on L1 is being used by the `HubPool` contract which [`delegateCall`s its execution](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/HubPool.sol#L901-L909). All the [parameters passed to the constructor](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/Arbitrum_Adapter.sol#L80-L85) are being used to set immutable variables, meaning that these can later be used during the `delegateCall`. However, this also creates the possibility for someone to use the adapters as an entry point to the system instead of going through the `HubPool` contract since all the parameters are also set there. Even though the `Arbitrum_Adapter` contract should not have any assets under regular conditions, if a user mistakenly sends assets to it, another actor might take the opportunity to [relay these assets](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/Arbitrum_Adapter.sol#L121) to a personal address.

In order to prevent the aforementioned case, consider enforcing that the implementation cannot be used when being called directly.

_**Update:** Acknowledged, not resolved. The team stated:_

> _Adapter implementation is not supposed to hold any assets. We might consider this problem in the future, but not as a part of this audit._

### Protocol Cannot Overcome OFT Fee Increase Without Upgrading

To prevent sending tokens through the OFT messaging system with unreasonable fees, the `OFTTransportAdapter` contract imposes a [cap on the fees](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L21-L25), and they are stored as an immutable parameter. This contract is being used for both the [adapters](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/Arbitrum_Adapter.sol#L81) and the [`SpokePool`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L226) contracts. However, if messaging fees exceed the cap, all [OFT transfers will fail](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L88). As a result of the immutable nature of the cap, there is no straightforward way of increasing it further to resolve the problem. This would necessitate deploying a new adapter and setting it with the [`setCrossChainContracts` function](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/HubPool.sol#L338) from the `HubPool` contract, or deploying a new `SpokePool` contract with the new value and perform an upgrade.

Since both of the above ways to address the fees exceeding the cap might render the protocol unusable during cost fluctuations, consider implementing functionalities to modify the cap. Alternatively, consider thoroughly documenting a contingency plan to resolve such a situation as fast as possible once it emerges.

_**Update:** Acknowledged, not resolved. The team stated:_

> _"This would necessitate deploying a new adapter and setting it with the `setCrossChainContracts` function from the `HubPool` contract, or deploying a new `SpokePool` contract with the new value and perform an upgrade." - this is our standard way of updating these params, yes._
> 
> _We have a high cap of 1 ETH set for our deployments, so we don't expect that to be a problem. What is more, the failing OFT transfer will not make the system unusable. It might delay the execution of the bundle or a leaf, which might delay relayer repayments. User deposits and fills will still work as expected so we have time to react to this problem if it arises._

### Transfers of Fee-On-Transfer Tokens Will Revert

The [`_transferViaOFT`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L57) function of the `OFTTransportAdapter` contract allows for using the OFT transport between chains. To assert that the assets have arrived correctly, the function implements a check that [compares](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L97) the amount sent from one chain with the amount received on the other chain. However, if the underlying token charges fees on transfers, the two amounts will differ (i.e., the input `_amount` will not match the output `amountReceivedLD`).

Consider implementing the necessary logic to allow for the transfer of fee-on-transfer tokens. Alternatively, consider documenting the fact that fee-on-transfer tokens cannot be used with OFT transfers when the fees are enabled.

_**Update:** Acknowledged, not resolved. The team stated:_

> _Yes, that's fine. We plan on only supporting reputable tokens without fees on transfer._

### LayerZero's Dust Removal Might Revert OFT Transfers

In the `_transferViaOFT` function of the `OFTTransportAdapter` contract, the final verification [checks](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L97) that the amount of assets passed as input matches the amount that will be received at destination. However, when invoking the messenger during the transfer, the [`_removeDust` function](https://docs.layerzero.network/v2/developers/evm/oft/quickstart#example) in LayerZero will be called, which will remove all those digits from the input amount that cannot be represented by the `sharedDecimals` value (by default, 6). This means that if the `_amount` input has a leftover after the integer division of the `decimalConversionRate` value, then the `amountReceivedLD` value will be lesser than the `_amount` value by that dust, so the two will not match.

Relatedly, there is an [inline comment](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L69-L71) that states _" Setting `minAmountLD` equal to `amountLD` protects us from any changes to the sent amount due to internal OFT contract logic, e.g. `_removeDust`"_, referring to the [two values](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L73-L74) being the same and equal to the amount sent, the `_amount` input. However, it is worth noting that this measure does not offer greater protection against dust removal since the latter is accomplished through the final [check on the `oftReceipt` output](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L97). Indeed, this check only employs the amount sent (`_amount`) and not the minimum amount, but even if validation with the minimum amount is not performed, the dust removal protection would still be caught by the final check with the `oftReceipt` output. Even though the amount is being passed by the Dataworker when submitting the bundle, it should be noted that the input amount could be converted before sending it through the OFT messenger so that it does not contain any dust in the first place, minimizing the cases of reversion.

Consider implementing the necessary calculation and conversion to prevent dust from reverting the transaction. In particular, the amount could be rounded up to the next precision given by the `decimalConversionRate` value to prevent sending fewer assets than those passed by the Dataworker.

_**Update:** Acknowledged, not resolved. The team stated:_

> _It's a design decision we went with: we added this rounding requirement to the relevant UMIP as a requirement for correctness of a bundle. So dataworker is responsible for providing correct decimals. Otherwise the bundle is deemed incorrect If there's a bug in dataworker code, OFT send will indeed revert; that's desired behavior._

### Function Selectors On Deprecated Functions Are Not Locked

[Pull request 1031](https://github.com/across-protocol/contracts/pull/1031/commits/e05964b074e6906e4dcb1d0fcd333dc7eb0b87be) removes already announced deprecated functionalities, such as the `depositDeprecated_5947912356` and `depositFor` functions, alongside their `_deposit` internal function.

However, as these entry points are removed, future versions of the codebase might introduce new functions that could have the same function selector as the removed ones. In such case, a protocol that might have used the deprecated functionalities could now call to the new ones with unexpected outcomes.

Similarly, if a `fallback` function is used in the future, depending on its implementation, it might take the calldata of protocols using the old deprecated functionalities with similar results.

In order to prevent the reuse of the deprecated function selectors, consider keeping the public functions' declaration, without their original definition, and reverting the calls to them.

_**Update:** Resolved in [pull request #1048](https://github.com/across-protocol/contracts/pull/1048/commits/0e262bf992636db588e122f3e4f8399b1fdb6e4f) at commit `0e262bf`._

Notes & Additional Information
------------------------------

### Zero-Address Validation Bypass in `SpokePool`

The `_setOftMessenger` function of the `SpokePool` contract [performs a check](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L1740) to validate that the proposed OFT messenger contract is the appropriate one for the given token. However, there is a scenario whereby if the messenger has not set its token, an admin is able to link the messenger to the zero address as the `_token` parameter. Even though consecutive calls to that zero-address token [would fail](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L92) in the OFT transfer flow, it is recommended to reduce the attack surface of edge cases.

Consider validating that the token address input is not the zero address at all times.

_**Update:** Acknowledged, not resolved. The team stated:_

> _That's fine, we trust the admin not to do this._

### Typographical Errors in Documentation and Comments

Typographical errors reduce readability and may cause misunderstandings. Throughout the codebase, multiple instances of typographical errors were identified:

*   In `OP_Adapter.sol`, the documentation in [line 41](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/OP_Adapter.sol#L41) states "Desination", whereas it should be "Destination".
*   In `OFTTransportAdapter.sol`, the documentation in [line 54](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L54) states "trasnfer", whereas it should be "transfer".

Consider correcting any instances of typographical errors and using spell-checking tools to avoid their recurrence.

_**Update:** Resolved in [pull request #1035](https://github.com/across-protocol/contracts/pull/1035)._

### Possible Duplicate Event Emissions

When a setter function does not check if the value has changed, it creates a possibility for spamming events which indicate that the value has changed even when it has not. Spamming the same values repeatedly can potentially confuse off-chain clients.

In the `SpokePool` contract, when [setting the new messenger](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L1743), the new values can be identical to the ones in storage, allowing for [triggering the same event](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L1744) multiple times by setting the same value.

Consider adding a check that reverts the transaction if the value being set is identical to the existing one.

_**Update:** Acknowledged, not resolved. The team stated:_

> _We rely on admin to not produce duplicate "set events"._

### Redundant Getter Function

When state variables use `public` visibility in a contract, a getter method for the variable is automatically included.

In the `SpokePool` contract, the [`_getOftMessenger` function](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L1747-L1749) is redundant because the [`oftMessengers` state variable](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L117) already has a getter.

To improve the overall clarity, intent, and readability of the codebase, consider removing any redundant getter functions or documenting the reasons to keep them.

_**Update:** Acknowledged, not resolved. The team stated:_

> _We feel like operating with _raw_ `oftMessengers` mapping from a child contract is more dangerous (easier for a programmer to make a mistake) than using a getter._

### Function Visibility Overly Permissive

Throughout the codebase, multiple instances of functions having unnecessarily permissive visibility were identified:

*   The [`_setOftMessenger`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L1739-L1745) function in the `SpokePool` contract with `internal` visibility could be limited to `private`.
*   The [`setOftMessenger`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L362) function in the `SpokePool` contract with `public` visibility could be limited to `external`, as it must be called by the admin.

To better convey the intended use of functions and to potentially realize some additional gas savings, consider changing a function's visibility to be only as permissive as required.

_**Update:** Resolved in [pull request #1041](https://github.com/across-protocol/contracts/pull/1041)._

### Non-Explicit Imports

The use of non-explicit imports in the codebase can decrease code clarity and may create naming conflicts between locally defined and imported variables. This is particularly relevant when multiple contracts exist within the same Solidity file or when inheritance chains are long.

Throughout the codebase, multiple instances of non-explicit/global imports were identified:

*   The [import "./libraries/OFTTransportAdapter.sol";](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L15) import in `SpokePool.sol`
*   The [import "../libraries/OFTTransportAdapterWithStore.sol";](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/chain-adapters/Universal_Adapter.sol#L11) import in `Universal_Adapter.sol`

Following the principle that clearer code is better code, consider using the named import syntax _(`import {A, B, C} from "X"`)_ to explicitly declare which contracts are being imported.

_**Update:** Resolved in [pull request #1036](https://github.com/across-protocol/contracts/pull/1036)._

### Multiple Contract Declarations Per File

Within [`AdapterStore.sol`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AdapterStore.sol), multiple contracts or libraries have been declared. These are the [`MessengerTypes` library](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AdapterStore.sol#L6) and the [`AdapterStore` contract](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AdapterStore.sol#L15-L65).

Consider separating the contracts into their own files to make the codebase easier to understand for developers and reviewers.

_**Update:** Acknowledged, not resolved. The team stated:_

> _With `MessengerTypes` lib being so small, I feel like it improves readability rather than subtracts from it._

### Missing Named Parameters in Mappings

Since [Solidity 0.8.18](https://github.com/ethereum/solidity/releases/tag/v0.8.18), developers can utilize named parameters in mappings. This means that mappings can take the form of `mapping(KeyType KeyName? => ValueType ValueName?)`. This updated syntax provides a more transparent representation of a mapping's purpose.

Throughout the codebase, multiple instances of mappings without named parameters were identified:

*   The [`crossChainMessengers` state variable](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AdapterStore.sol#L17) in the `AdapterStore` contract
*   The [`oftMessengers` state variable](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L117) in the `SpokePool` contract

Consider adding named parameters to mappings in order to improve the readability and maintainability of the codebase.

_**Update:** Resolved in [pull request #1040](https://github.com/across-protocol/contracts/pull/1040)._

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Throughout the codebase, multiple instances of contracts missing a security contact were identified:

*   The [`MessengerTypes` library](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AdapterStore.sol#L6)
*   The [`AdapterStore` contract](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/AdapterStore.sol#L15)
*   The [`OFTTransportAdapterWithStore` contract](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapterWithStore.sol#L8)

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in [pull request #1037](https://github.com/across-protocol/contracts/pull/1037)._

### Custom Errors in `require` Statements

Since Solidity [version `0.8.26`](https://soliditylang.org/blog/2024/05/21/solidity-0.8.26-release-announcement/), custom error support has been added to `require` statements. Initially, this feature was only available through the IR pipeline. However, Solidity [`0.8.27`](https://soliditylang.org/blog/2024/09/04/solidity-0.8.27-release-announcement/) extended its support to the legacy pipeline as well.

Throughout the codebase, multiple instances where `if-revert` statements could be replaced with `require` statements were identified:

*   The [`if (nativeFee > OFT_FEE_CAP) revert OftFeeCapExceeded()`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L88) statement in `OFTTransportAdapter.sol`
*   The [`if (nativeFee > address(this).balance) revert OftInsufficientBalanceForFee()`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L89) statement in `OFTTransportAdapter.sol`
*   The [`if (_amount != oftReceipt.amountReceivedLD) revert OftIncorrectAmountReceivedLD()`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/libraries/OFTTransportAdapter.sol#L97) statement in `OFTTransportAdapter.sol`
*   The [`if (IOFT(_messenger).token() != _token) { revert OFTTokenMismatch(); }`](https://github.com/across-protocol/contracts/blob/c5d7541037d19053ce2106583b1b711037483038/contracts/SpokePool.sol#L1740-L1742) statement in `SpokePool.sol`

For conciseness and gas savings, consider replacing `if-revert` statements with `require` statements.

_**Update:** Acknowledged, not resolved. The team stated:_

> _Tried to address this, but `OFTTransportAdapter` is inherited by many other contracts and the new version requirement was not trivial to fix. E.g. "stack too deep" errors appeared. Might consider moving to 0.8.27 in the future for `require` with custom errors!_

### Unused Errors Due To Deprecated Logic

After the removal of the `_deposit` function from the `SpokePool` contract, the [`InvalidRelayerFeePct`](https://github.com/across-protocol/contracts/blob/e05964b074e6906e4dcb1d0fcd333dc7eb0b87be/contracts/interfaces/SpokePoolInterface.sol#L59) and [`MaxTransferSizeExceeded`](https://github.com/across-protocol/contracts/blob/e05964b074e6906e4dcb1d0fcd333dc7eb0b87be/contracts/interfaces/SpokePoolInterface.sol#L60) errors are no longer in use.

Consider removing the unused errors.

_**Update:** Resolved in [pull request #1047](https://github.com/across-protocol/contracts/pull/1047/commits/2de2d5033c7caf7f5edbc02f7a39dfe430599b93) at commit `2de2d50`._

Conclusion
----------

The reviewed code introduces an OFT LayerZero bridging mechanism to the Across protocol in order to enhance the existing setup. To do so, the `OFTTransportAdapter` contract has been introduced, implementing the necessary parsing to interact with the OFT messengers. Due to the difference in how Adapters and the `SpokePool` contract interact, the `AdapterStore` and the `OFTTransportAdapterWithStore` contracts have been added to be used as a beacon for the rest of the Adapters during the `delegatecall` in the `HubPool` contract. On the `SpokePool` side, an internal mapping has been added to the `SpokePool` contracts in order to keep track of such linkage between tokens and the respective messengers. Currently, only the Universal, Arbitrum, and AlephZero adapters will make use of this OFT feature, while the rest of the adapters and `SpokePool`s were either left unmodified or have been hardcoded with null values to prevent the OFT functionality's usage.

In addition, pull requests #1031 and #1032 were added into the scope. These removed legacy functionality related to the ability to set the address of the output token to the zero address and added support for transferring ETH to EIP-7702 delegated wallets.

Overall, the addition of the OFT feature appears to be sound. That said, it may still benefit from adding more test suits, enforcing a stronger deprecation of the flow in the chains that currently will not be used, and documenting some of the design choices made in the implementation. Furthermore, a roadmap for the upcoming changes in this feature would complement the documentation to better explain the potential roadblocks. The changes introduced by pull request #1031 are well-motivated. As for #1032, concerns were listed as to its compliance with the EIP-7702 standard, specifically in the treatment of delegated EOAs as regular EOAs, as opposed to regular contracts.

The changes in scope rely on multiple trust assumptions, which were duly listed, along with some integration points to keep in mind in future integrations, in this report.

The Risk Labs team has been very helpful throughout the engagement, answering all of the audit team's questions promptly and in great detail.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kEqbMu3kxAZ4OjVESZTwZoD1PlSaw&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=191806428705&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=c26fec88-6ac7-432a-8918-742d0f5465d3&redirect_url=APefjpFpjVA2ZQYTTioWt6Gv1E1hQ-OXg9i7OUA0BF94rQGNsk1e9Yh5lEIR5kj4NFmd0hILO8s3iEnF6R922oSg5JU10Wx2VR54y7Uq2or1W0iuNSsa8CpbG9QHkXRuYiNs5X7RYuVYLCs57IIKveuHaW_unBbsDy7irIo-5Wydz8Gg4SqVeU88YVGqRc9Oyz1qfM0p4gNHB4efCA4o6kB43FhzoDNUk50L8Om-os_0fXM4lyY-M1vki5u0ixcFYCr4d8J2jD7n&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Facross-protocol-oft-integration-differential-audit&ts=1770534030646&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.64.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")