\- May 12, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

**Type:** DeFi**Timeline:** October 7, 2024 → October 30, 2024**Languages:** Solidity
-------------------------------------------------------------------------------------

**Findings**Total issues: 29 (26 resolved, 1 partially resolved)  
Critical: 1 (1 resolved) · High: 2 (2 resolved) · Medium: 8 (8 resolved) · Low: 3 (2 resolved)

**Notes & Additional Information**14 notes raised (13 resolved, 1 partially resolved)

Scope
-----

We audited the [across-protocol/contracts](https://github.com/across-protocol/contracts) repository.

The scope consisted of five parts, listed below.

### L3 Support

In scope were the following files, audited at commit [5a0c67c](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1):

`contracts/
├── chain-adapters/
│   ├── Router_Adapter.sol
│   ├── ForwarderBase.sol
│   ├── Ovm_Forwarder.sol
│   ├── Arbitrum_Forwarder.sol
│   └── l2/
│       ├── WithdrawalHelperBase.sol
│       ├── Ovm_WithdrawalHelper.sol
│       └── Arbitrum_WithdrawalHelper.sol
└── libraries/
    └── CrossDomainAddressUtils.sol` 

In addition, we audited all the changes made to the `contracts/SpokePool*.sol` files in [PR #629](https://github.com/across-protocol/contracts/pull/629) until commit [6e86b70](https://github.com/across-protocol/contracts/tree/6e86b707b19832d2b5fc35ac51e888de017a1f0b).

### ZkStack Support

In scope were the following files, audited at commit [5a0c67c](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1):

`contracts/
└── chain-adapters/
    ├── ZkStack_Adapter.sol
    └── ZkStack_CustomGasToken_Adapter.sol` 

### Predictable Relay Hash

In scope were the changes made to the following files in [PR #639](https://github.com/across-protocol/contracts/pull/639) until commit [7641fbf](https://github.com/across-protocol/contracts/tree/7641fbf38b661e02fc00f3b33d7e587c6dc5f06f):

`contracts/
├── SpokePool.sol
├── erc7683/
│   ├── ERC7683Across.sol
│   ├── ERC7683OrderDepositor.sol
│   └── ERC7683OrderDepositorExternal.sol
└── interfaces/
    └── V3SpokePoolInterface.sol` 

### Supporting the Newest Version of ERC-7683

In scope were the changes made to the following files in commit [108be77](https://github.com/across-protocol/contracts/commit/108be77c29a3861c64bdf66209ac6735a6a87090):

`contracts/
├── SpokePool.sol
├── erc7683/
│   ├── ERC7683.sol
│   ├── ERC7683Across.sol
│   ├── ERC7683OrderDepositor.sol
│   └── ERC7683OrderDepositorExternal.sol
└── interfaces/
    └── V3SpokePoolInterface.sol` 

### World Chain Support

In scope were the changes made to the following files in [PR #646](https://github.com/across-protocol/contracts/pull/646) until commit [51c45b2](https://github.com/across-protocol/contracts/tree/51c45b2b9ca06314dac9ec4f12fe04d37da58d70) and [PR #647](https://github.com/across-protocol/contracts/pull/647) until commit [d4416cd](https://github.com/across-protocol/contracts/tree/d4416cd6ba0ac7864147cdfac5d78546a0a624b6):

`contracts/
├── WorldChain_SpokePool.sol
└── chain-adapters/
    └── WorldChain_Adapter.sol` 

System Overview
---------------

Across is an intent-based, cross-chain bridging protocol that allows users to quickly transfer their tokens between different blockchains. For more details on how the protocol works, please refer to [one of our previous audit reports](https://blog.openzeppelin.com/uma-across-v2-audit-2023).

### Summary of Changes

#### L3 Support

Until now, the Across protocol only supported blockchains that communicated with Ethereum directly, such as L2 networks. In order to communicate with SpokePools deployed on other blockchains, the HubPool deployed on Ethereum used adapters which contained the logic allowing it to send cross-chain messages. However, it was not able to communicate with blockchains which communicate with Ethereum indirectly, via L2 networks. In this audit report, such blockchains will be referred to as _L3 blockchains_, and the newest contracts added to the repository introduce support for them.

In order to support L3 blockchains, two sets of contracts have been added:

*   Forwarder contracts.
*   Withdrawal helper contracts.

**Forwarder contracts** are meant to be deployed on L2 blockchains, in between Ethereum and L3 blockchains. They are designed to pass all the messages received from Ethereum to target L3 blockchains. Each forwarder contract is able to handle communication with many different L3 blockchains. As such, it is sufficient to deploy only one of them for each L2.

The communication between Ethereum and forwarder contracts is possible by using `Router_Adapter` contracts. The `Router_Adapter` is a special type of adapter that wraps the messages designed for SpokePools so that they are first passed to the forwarders on L2s and then sent to the final targets on L3s. It is necessary to deploy one `Router_Adapter` on Ethereum per each supported L3 blockchain. This design allows for treating L3 blockchains like L2 blockchains inside the HubPool as the `Router_Adapter` contracts handle the entire L3-relevant logic and have exactly the same interface as existing L2 adapters.

While the forwarder contracts enable L1->L3 communication, the **Withdrawal helper contracts** allow for communication in the opposite direction. They are responsible for passing the tokens that they receive from L3 blockchains to the HubPool on Ethereum.

#### ZkStack Support

Two new adapters have been introduced: `ZkStack_Adapter` and `ZkStack_CustomGasToken_Adapter`. `ZkStack_Adapter` provides support for the [ZkStack](https://zkstack.io/) blockchains that use ETH as the gas token. On the other hand, `ZkStack_CustomGasToken_Adapter` has been designed to work with the remaining ZkStack blockchains. Both contracts make it possible to send custom messages and transfer tokens to the L2 targets, similar to the existing L2 adapters.

#### Predictable Relay Hash

Previously, the deposit IDs inside the `SpokePool` contract were calculated as the total number of deposits made. However, this design did not allow the relayers to perfectly predict the relay hashes that they would have to provide in order to fill deposits. This is because each deposit ID could change if other deposits had been made before it.

The current design allows for predicting deposit IDs by allowing the depositors to specify the nonce. This nonce is then used to create a deterministic deposit ID utilizing the `keccak256` hash function. The depositors are responsible for not reusing the same nonces, which could lead to deposit ID collisions inside the SpokePools.

#### Supporting the Newest Version of ERC-7683

New changes have been proposed for the `ERC-7683` standard. In this regard, two new order types have been introduced: `GaslessCrossChainOrder`, designed to be created off-chain, and `OnchainCrossChainOrder`, which could be utilized directly on-chain. Structs representing both types can contain the implementation-specific data which is then used in order to construct the `ResolvedCrossChainOrder` struct, containing the information required for the order fillers. This struct must be emitted in an event whenever any type of order is opened.

The changes introduced to the contracts in this part of the scope implement the new requirements of the `ERC-7683` standard.

#### World Chain Support

World Chain implements [Circle's bridged USDC standard](https://github.com/circlefin/stablecoin-evm/blob/master/doc/bridged_USDC_standard.md), which allows for upgrading the bridged USDC to the native USDC emitted by Circle, in the future. Because of this, both L1 and L2 standard bridges cannot be used for USDC deposits and withdrawals.

The pull requests in this part of the scope make use of the special USDC bridges deployed on Ethereum and World Chain in order to correctly bridge USDC tokens between the HubPool and the `WorldChain_SpokePool`.

Security Model and Trust Assumptions
------------------------------------

The Across protocol depends on many different external components, such as bridges and messaging mechanisms between different blockchains. Moreover, this audit has been restricted only to a part of the entire codebase. As a result, the audit was conducted under certain trust assumptions.

Throughout the audit, we assumed that all the contracts that the in-scope contracts interact with work correctly. In particular, we assumed that the bridges work as expected and correctly bridge assets between blockchains, and that `view` functions invoked on the HubPool and SpokePool contracts, such as `tokenBridges`, `remoteL1Tokens`, and `poolRebalanceRoute` return correct results. We also assumed that only assets supported both by the bridges and the target blockchains would be bridged.

Moreover, we assumed that both the L1 adapters used by the `Router_Adapter` and the L2 adapters used by the forwarder contracts work as expected. In particular, we assumed that they correctly implement the `AdapterInterface`, correctly validate provided token pairs to relay, and correctly bridge tokens and send messages across blockchains.

We also assumed that all the contracts would only be deployed on the blockchains that they are designed for. For instance, the `Ovm_WithdrawalHelper` contract will not work correctly on OVM blockchains for which there exist tokens that require custom logic for bridging, different from the one contained in the `_bridgeTokensToHubPool` function of the `Ovm_SpokePool` contract. For example, this is the case with Optimism and Blast. As such, we assumed that `Ovm_WithdrawalHelper` would not be deployed on such blockchains.

Furthermore, it was assumed that every ZkStack chain being used was configured properly, which, in particular, means that the `l2TransactionBaseCost` function used for estimating the transaction cost returns correct values. It includes situations where a custom gas token has a custom number of decimals, in which case we assume that the [base token nominator and base token denominator parameters](https://docs.zksync.io/zk-stack/running-a-zk-chain/custom-base-tokens#custom-base-token-setup) are configured correctly so that proper scaling is applied when estimating the amount of L2 gas tokens to be charged as gas expenditure. It is also worth noting that the current implementation of the adapters always uses the shared bridge exposed in the BridgeHub. It might be possible for certain tokens to require a [bridge to be used that is different from the shared bridge](https://docs.zksync.io/build/developer-reference/era-contracts/l1-ecosystem-contracts#generic-usage-of-bridgehubrequestl2transactiontwobridges). We assumed that such tokens would not be bridged using existing adapters and that only tokens supported both by the shared bridge and by the target L2 networks would be bridged.

It was also assumed that all the in-scope contracts would be initialized and configured correctly. In particular, it is assumed that the parameters related to gas calculations on ZkStack blockchains, such as `L2_GAS_LIMIT` and `L1_GAS_TO_L2_GAS_PER_PUB_DATA_LIMIT`, would be set to such values that allow for the correct execution of all transactions on each supported blockchain.

### Privileged Roles

Multiple newly introduced privileged roles are also within the scope of this audit:

*   The admin of the forwarder contracts. This account is capable of changing the forwarder contract implementations at any time, transferring tokens from them, modifying the adapters being used, and sending messages on their behalf.
*   The admin of the withdrawal helper contracts. This account is able to change the withdrawal helper contracts' implementations at any time.
*   The owner of the `ERC7683OrderDepositorExternal` contract. This account is capable of changing the `ERC-7683` destination settler used by the `ERC7683OrderDepositor` contract in order to emit `ERC-7683` fill instructions.

On top of the above, there are other privileged roles present in the contracts that have been left out of the scope of this engagement but can influence the in-scope contracts (e.g., the owner of the HubPool). For the entire list of the privileged roles present in the Across protocol, please refer to our past audits.

Ultimately, we assume that all the entities having the roles mentioned above will act responsibly, and in the best interest of the protocol and its users.

Critical Severity
-----------------

### Missing Access Control for `setDestinationSettler`

The `ERC7683OrderDepositorExternal` contract contains the `setDestinationSettler` [function](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683OrderDepositorExternal.sol#L38-L42) which provides a mapping of chain ID to that chain's settler contract address. This value is accessed through the [`_destinationSettler`](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683OrderDepositorExternal.sol#L80-L82) function of the same contract and is used by the inherited `ERC7683OrderDepositor` contract when constructing the [fill instructions](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683OrderDepositor.sol#L216) inside the [`_resolveFor`](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683OrderDepositor.sol#L161) function.

The issue is that the `setDestinationSettler` function has [no access control](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683OrderDepositorExternal.sol#L38-L42) and can be changed to any arbitrary address by any account. Consequently, a malicious user could set the `destinationSettler` address to a malicious address which is used in constructing the fill instructions. The filler on the `destinationChain` would need to give token approvals to the `destinationSettler` to execute the `fill` call. A malicious `destinationSettler` would be thus able to steal funds from the `filler`.

Since the `ERC7683OrderDepositorExternal` contract already [inherits](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683OrderDepositorExternal.sol#L16) the `Ownable` contract, consider adding the `onlyOwner` modifier to its `setDestinationSettler` function.

_**Update:** Resolved in [pull request #733](https://github.com/across-protocol/contracts/pull/733) at commit [8942780](https://github.com/across-protocol/contracts/pull/733/commits/8942780d8db73eee0f07ab62625d13f5faae3ad3)._

High Severity
-------------

### SpokePool's `fill` Function Performs Malformed Call

The `fill` [function](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/SpokePool.sol#L988) of the `SpokePool` contract is meant to adhere to the `IDestinationSettler` interface, as dictated by the latest update to the `ERC-7683` [specifications](https://github.com/across-protocol/ERCs/blob/d975d7b4b58fa3d1aa6db1763935cfa2ab1444b1/ERCS/erc-7683.md). The `fill` function is meant to internally call the `fillV3Relay` [function](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/SpokePool.sol#L864) in order to process the order data, and it does so by [making a `delegatecall` to its own `fillV3Relay` function](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/SpokePool.sol#L998-L999), passing `abi.encodePacked(originData, fillerData)` as the parameter.

However, the `fillV3Relay` function accepts two parameters, having the `repaymentChainId` as the second parameter. Since the call is constructed using `encodeWithSelector`, which is not type-safe, the compiler does not complain about the missing parameter. As an incorrect number of parameters is passed, the call to `fillV3Relay` will always revert when trying to decode the input parameters, breaking the entire execution flow. Moreover, the input data is encoded with `abi.encodePacked` the use of which is discouraged, especially when dealing with structs and dynamic types like arrays.

Consider using `encodeCall` instead of `encodeWithSelector` to ensure type safety, and providing the parameters required by the `fillV3Relay` function separately. In addition, consider explicitly making the `SpokePool` contract inherit from the `IDestinationSettler` interface as required by the `ERC-7683` standard.

_**Update:** Resolved in [pull request #744](https://github.com/across-protocol/contracts/pull/744) at commit [9f54455](https://github.com/across-protocol/contracts/pull/744/commits/9f5445571a98f13248a21acba3ac3fe40c737abd)._

### Forwarder and Withdrawal Helper Contracts Do Not Handle ETH Transfers Correctly

The [`WithdrawalHelperBase`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/WithdrawalHelperBase.sol#L18) and [`ForwarderBase`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ForwarderBase.sol#L18) contracts are designed to be deployed on L2s and assist in moving tokens and messages to and from L3 chains. These contracts are inherited by the chain-specific contracts, currently designed for Arbitrum and OVM-based blockchains. However, none of these contracts handle ETH transfers correctly. This is because they do not contain the `receive` function, which causes any attempt to transfer ETH to these contracts to fail.

In the case of forwarder contracts, the lack of the `receive` function means that WETH transfers, which rely on unwrapping before bridging such as [the transfers made through the `Optimism_Adapter`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/Optimism_Adapter.sol#L101-L105), will fail, leaving the ETH in the bridge until the contract can be upgraded. In the case of withdrawal helper contracts, the lack of the `receive` function implies that they will not be capable of unwrapping WETH [in an attempt to transfer it to Ethereum](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/Ovm_WithdrawalHelper.sol#L114-L124). Additionally, they will not be capable of receiving ETH bridged from L3s. Moreover, while the withdrawal helper contracts contain [token-bridging logic](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/WithdrawalHelperBase.sol#L87-L101), they do not support bridging ETH. This means that even if they were capable of receiving ETH and ETH was bridged to them from L3s, it could not be routed to L1.

Consider adding a `receive` function to the `ForwarderBase` and `WithdrawalHelperBase` contracts to facilitate incoming ETH transfers and the unwrapping of WETH tokens during bridging. As the contracts do not support bridging ETH directly, the `receive` function should include logic to ensure that incoming ETH is handled correctly and can be sent on to the target chain.

_**Update:** Resolved in [pull request #725](https://github.com/across-protocol/contracts/pull/725), at commit [705a276](https://github.com/across-protocol/contracts/pull/725/commits/705a2765af7b052c1268c9e6843579df2ac35659) by adding the `receive` function to forwarder and withdrawal helper contracts. Moreover, both contracts allow to transfer ETH out of them by wrapping it in case when WETH transfer is requested. The team stated:_

> _We went with this approach so that we can keep the same format as our L1 adapters for L2-L3 bridging, and as our L2 spoke pools for L2-L1 withdrawals._

Medium Severity
---------------

### `relayTokens` Calls Made By Forwarders May Fail

The [`Router_Adapter` contract](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/Router_Adapter.sol#L26) could be used as an adapter by the `HubPool` contract in order to send messages or tokens to the L3 blockchains. In order to send tokens to L3, this contract sends two messages to the intermediary L2 blockchain: [the first one](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/Router_Adapter.sol#L109-L111) is simply a call to `relayTokens` which will send a specified amount of tokens to a relevant forwarder contract on L2, and [the second one](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/Router_Adapter.sol#L115-L119) is a call to `relayMessage` which will execute the [`relayTokens` function](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ForwarderBase.sol#L119) on the forwarder contract on L2 upon arrival. This way, a forwarder contract on L2 will be instructed to send the received tokens to L3 soon after it receives them.

However, there is no guarantee that the messages sent to the forwarder contract on L2 will be delivered in the same order that they were sent. In particular, some tokens are being sent to L2 using different channels than the ones used by messages. For example, in the case of Arbitrum, the USDC token [will be bridged through the CCTP protocol](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/Arbitrum_Adapter.sol#L116-L119), but the messages [will be passed through the Arbitrum Inbox contract](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/Arbitrum_Adapter.sol#L87-L96) which is completely independent of CCTP. This may cause some messages instructing forwarder contracts to relay tokens to L3s to fail on L2s as the tokens may arrive at the L2 after an attempt to send them to L3.

Consider caching failed messages inside forwarders so that they could be re-executed by anyone in the future, possibly many at once, in a batch.

_**Update:** Resolved in [pull request #664](https://github.com/across-protocol/contracts/pull/664), at commit [d3e790f](https://github.com/across-protocol/contracts/pull/664/commits/d3e790f2fffe49655297c863ad3e35534dc80e34) by caching all the messages inside the `relayTokens` function. It is now possible to execute cached token transfers by calling the `executeRelayTokens` function. Calls can be grouped together by using the `multicall` function of the [Multicaller](https://github.com/UMAprotocol/protocol/blob/master/packages/core/contracts/common/implementation/MultiCaller.sol) contract._

### No Way to Invoke Some Privileged Functions of Forwarders

The [`ForwarderBase` contract](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ForwarderBase.sol#L18) contains several functions which could only be invoked by cross-chain messages originating from [`crossDomainAdmin`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ForwarderBase.sol#L20). These functions include the [`setCrossDomainAdmin`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ForwarderBase.sol#L69) and [`updateAdapter`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ForwarderBase.sol#L82) functions. The `ForwarderBase` contract and contracts inheriting from it are expected to be communicated with via the [`Router_Adapter` contract](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/Router_Adapter.sol#L26) deployed on L1.

However, `Router_Adapter` does not provide a way to call any functions of a forwarder contract other than `relayMessage` and `relayTokens`. This means that if it ever becomes necessary to change `crossDomainAdmin` or to change the adapter used by the forwarder contract deployed on L2, it can be only done by replacing `Router_Adapter` with another adapter which provides such functionality.

Consider implementing logic that allows for calling other privileged functions of forwarder contracts through the `Router_Adapter` contract. Alternatively, consider implementing dedicated adapters which would enable calling these privileged functions from the HubPool.

_**Update:** Resolved in [pull request #665](https://github.com/across-protocol/contracts/pull/665). The team stated:_

> _We are still deciding on how exactly we will communicate with the `ForwarderBase` and `WithdrawalHelper` contracts, but, for now, we think that upgrades to these contracts will be rare. With that in mind, we have a few approaches to fix this issue:_
> 
> _\- Under the assumption that we only really need to call admin functions upon initialization of a new L3, we can call `setCrossChainContracts` in the hub pool to map the L3's chain ID to the L2 forwarder address/withdrawal helper address and a relevant adapter (e.g. `OptimismAdapter`). This connection can then be used to configure the forwarder/withdrawal helper, after which we call `setCrossChainContracts` with the L3's chain ID mapping to the correct adapter/spoke pool pair._
> 
> _\- If we need to establish a connection (temporary or persistent), we may also want to call`setCrossChainContracts` to map some function of the L3 chain ID to the forwarder/withdrawal helper contract. Otherwise (for temporary connections only). If we only need to send a single message to an L2 contract, we could also temporarily halt communication to the L3 spoke pool by calling `setCrossChainContracts` with the L3 chain ID and the corresponding L2 contract._
> 
> _While we are still thinking of what approach we want to take, here is a PR which contain two "admin adapters" corresponding to the forwarder and withdrawal helper. These are essentially special cases of the router adapter._
> 
> _Edit: One last update here, the PR we provided is a special case of a router adapter which will just communicate with the forwarder/withdrawal helper; however, we've noticed that we don't really need to have this adapter since we can just reuse other deployed adapters to send messages to the forwarder/withdrawal helper. That is, the two bullet points above still stand; just instead of using a separate admin adapter to send these messages, we can `setCrossChainContracts` with the network adapter (e.g. `Arbitrum_Adapter, Optimism_Adapter, etc`) instead of this new admin adapter._

### Types Incompatible With `ERC-7683`

The [newest changes](https://github.com/across-protocol/ERCs/blob/d975d7b4b58fa3d1aa6db1763935cfa2ab1444b1/ERCS/erc-7683.md) to the `ERC-7683` standard redefined the types of some variables. Particularly, the variables storing the chain ID now have the `uint64` type instead of `uint32`, and some addresses are now stored in the `bytes32` type. However, the variables declared inside the [`AcrossOrderData` struct](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683Across.sol#L8-L18) still have the old types. In particular, the [`destinationChainId` member](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683Across.sol#L13) is of type `uint32` and the [`recipient` member](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683Across.sol#L14) is of the `address` type.

Consider changing the types of all affected variables so that they are in compliance with the latest version of the `ERC-7683` standard.

_**Update:** Resolved in [pull request #746](https://github.com/across-protocol/contracts/pull/746) at commit [9eebe3d](https://github.com/across-protocol/contracts/pull/746/commits/9eebe3def28a96733a663497cd62ade8db150124)._

### Some Contracts Might Not Work Properly with USDT Allowance

The `ERC7683OrderDepositorExternal` contract implements the `_deposit` function to finalize the creation of an Across V3 deposit. To do so, the function [calls](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683OrderDepositorExternal.sol#L58) the `safeIncreaseAllowance` function on the `inputToken` specified in the order details. This mechanism will work with any token under the assumption that the entire allowance will be spent by the SpokePool in the [`depositV3` function call](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683OrderDepositorExternal.sol#L60-L73). The `safeIncreaseAllowance` function is also used in the [`ZkStack_Adapter`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L147) and the [`ZkStack_CustomGasToken_Adapter`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L189) contracts, along with some other adapters like the [ZkSync\_Adapter](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkSync_Adapter.sol#L241) which are out of scope for this audit.

However, if for any reason, the entire allowance is not used after the approval, any further attempt to `safeIncreaseAllowance` with tokens that prohibit any approval change from non-zero to non-zero values, like USDT, will ultimately fail. As an example of a real impact, the second example of issue [M08](#m08) will likely produce a scenario in which subsequent calls with USDT as the custom gas token will fail, thus blocking the entire `ZkStack_CustomGasToken_Adapter`'s functionality.

Consider using the `forceApprove` [function](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/54b3f14346da01ba0d159114b399197fea8b7cda/contracts/token/ERC20/utils/SafeERC20.sol#L82) of the `SafeERC20` library to be compatible with tokens that revert on approvals from non-zero to non-zero values.

_**Update:** Resolved in [pull request #734](https://github.com/across-protocol/contracts/pull/734) at commit [ea59869](https://github.com/across-protocol/contracts/pull/734/commits/ea59869826acbb2ee70b43dd0779288bab3007e7)._

### Griefing Attacks Are Possible in ZK Adapters

The [`_computeETHTxCost` function](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L188) of the `ZkStack_Adapter` contract is used to estimate transactions' cost on L2. Whenever a message is sent from L1 to L2, this estimated transaction cost is [transferred](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L91) out of the HubPool to the native L1 inbox. Any excess value is supposed to be [refunded](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L38) to the `L2_REFUND_ADDRESS` on L2, which is expected to be an address under the control of the Across team. However, `tx.gasprice`, which is used for transaction cost estimation, is a parameter that can be manipulated by the initiator of the transaction. This opens up an attack vector whereby a malicious user can inflate the `tx.gasprice` in order to transfer ETH from the HubPool to an L2 network.

In order to perform the attack, the attacker could invoke the [`executeRootBundle` function](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/HubPool.sol#L620) of the HubPool, causing the HubPool to [call the `relayMessage` function of the adapter](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/HubPool.sol#L686). Since `tx.gasprice` is directly used for the [required gas fee calculation](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L88), the attacker can set it to a value for which the estimated fee will be equal to the entire HubPool's ETH balance. HubPool will then [transfer the ETH to L2](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L91). A similar attack could be used in order to transfer a custom gas token from the HubPool using the [`ZkStack_CustomGasToken_Adapter` contract](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L36).

While it is normally very expensive for an attacker to inflate `tx.gasprice` parameter for the entire transaction (as they have to cover the gas fee), they can receive back almost the entire invested ETH amount if they are a validator for the block in which the attack is executed.

Consider limiting the maximum `tx.gasprice` which can be used for gas fee calculation inside the `_computeETHTxCost` and the `_pullCustomGas` functions.

_**Update:** Resolved in [pull request #742](https://github.com/across-protocol/contracts/pull/742) at commit [dc4337c](https://github.com/across-protocol/contracts/pull/742/commits/dc4337cc2af46d02121eb17252847bad117fd2eb) by limiting the maximum `tx.gasprice` which can be used for gas fee calculation._

### Incorrect Parameters Passed to `permitWitnessTransferFrom`

The [`PERMIT2_ORDER_TYPE` variable](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683Across.sol#L67) stores the witness data type string, which is supposed to be passed as the `witnessTypeString` parameter to the `permitWitnessTransferFrom` function of the `Permit2` contract. As such, this variable is supposed to define the typed data that the `witness` parameter passed to that function was hashed from. However, it instead [specifies](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683Across.sol#L70) that the `witness` parameter has been hashed from the `CrossChainOrder` type, whereas in reality, [it was hashed from the `GaslessCrossChainOrder` type](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683OrderDepositor.sol#L331).

Moreover, the `witness` parameter specified is incorrect as the [`orderDataType`](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683.sol#L22) member of the `GaslessCrossChainOrder` struct is not taken into account when [calculating it](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683Across.sol#L80-L91). The same is true for the [`exclusiveRelayer`](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683Across.sol#L15) and [`depositNonce`](https://github.com/across-protocol/contracts/blob/7641fbf38b661e02fc00f3b33d7e587c6dc5f06f/contracts/erc7683/ERC7683Across.sol#L16) members of the `AcrossOrderData` struct, which are [not included](https://github.com/across-protocol/contracts/blob/7641fbf38b661e02fc00f3b33d7e587c6dc5f06f/contracts/erc7683/ERC7683Across.sol#L106-L107) in the calculation of its hash. Furthermore, the `CROSS_CHAIN_ORDER_TYPE` variable used to create the `witness` contains an incorrect encoding of the [`GaslessCrossChainOrder` struct](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683.sol#L6) as the [`originChainId` member](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683Across.sol#L55) is specified to be of type `uint32` instead of `uint64`.

Consider correcting the errors described above in order to maintain compliance with `EIP-712` and `Permit2`.

_**Update:** Resolved in [pull request #745](https://github.com/across-protocol/contracts/pull/745) at commit [b1b5904](https://github.com/across-protocol/contracts/pull/745/commits/b1b5904d992b5840efa73211707804dd690a01ed) and at commit [98c761e](https://github.com/across-protocol/contracts/commit/98c761ee9ca3a496b4a368bdf12743d727644138). The team stated:_

> _There have been some changes to ERC7682 during the audit, so these fixes are split between two commits. The first commit (and the attached PR) addresses the first paragraph and all of the second paragraph except for `depositNonce` and swapping `originChainId` to a uint64. The `depositNonce` has since been removed, and the origin chains now match as a result of the second commit._

### Attempts to Bridge WETH Using `ZkStack_CustomGasToken_Adapter` Will Fail

In order to bridge tokens from Ethereum to a ZkStack blockchain using a custom gas token, the [`relayTokens` function](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L141) of the `ZkStack_CustomGasToken_Adapter` contract can be used. In case the token to bridge is WETH, the token is first [converted](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L155) to ETH, and then that ETH is bridged [using the `requestL2TransactionTwoBridges` function](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L157-L168) of the `BridgeHub` contract. The `requestL2TransactionTwoBridges` function then [calls the `bridgeHubDeposit` function of the second bridge](https://etherscan.io/address/0x509da1be24432f8804c4a9ff4a3c3f80284cdd13#code#F1#L291) with the ETH amount specified by the caller.

However, the `bridgeHubDeposit` function [requires that the deposit amount specified equals 0](https://github.com/matter-labs/era-contracts/blob/aafee035db892689df3f7afe4b89fd6467a39313/l1-contracts/contracts/bridge/L1SharedBridge.sol#L328) in case when ETH is bridged, yet it [is specified as a nonzero amount](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L167) inside the `relayTokens` function of the adapter. This will cause any attempt to bridge WETH to L2 to revert.

In cases where WETH is being bridged, consider setting the amount to be used in the second bridge's calldata to 0.

_**Update:** Resolved in [pull request #743](https://github.com/across-protocol/contracts/pull/743) at commit [0bdad5b](https://github.com/across-protocol/contracts/pull/743/commits/0bdad5bdaacbbaaa9c89addac9e8ce8c36e8f8d5)._

### Transfers of The Target Chain's Gas Token Will Fail

The `relayTokens` [function](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L109-L122) of the `ZkStack_Adapter` is intended to facilitate transfers from the HubPool on the Ethereum Mainnet to ZkStack chains, having ETH as the gas token, via the BridgeHub. The `relayTokens` [function](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L141) of the `ZkStack_CustomGasToken_Adapter` contract enables this functionality for chains with a custom gas token.

For `ZkStack_Adapter`, when transferring WETH, the `relayTokens` function [unwraps](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L128-L144) the WETH into ETH and sends this amount to the BridgeHub as part of the `requestL2TransactionDirect` call to the `BridgeHub` contract. For ETH transfers, the `requestL2TransactionDirect` function checks that the value sent along with the call is equal to the `mintValue` of the request. However, in the `relayTokens` function, the `value` that is sent is the [`amount + txBaseCost`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L132) while `mintValue` [is only](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L135) the `txBaseCost`.

The `requestL2TransactionDirect` function [requires](https://etherscan.io/address/0x509da1be24432f8804c4a9ff4a3c3f80284cdd13#code#F1#L222) the `mintValue` field to be equal to the `msg.value` of the call, but the `mintValue` will always only be set as the `txBaseCost`, meaning that the check will always fail. In addition, the `l2Value` for the `requestL2TransactionDirect` is [fixed at 0](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L137) inside the contract, meaning that the `l2Contract` will never receive any ETH. Consequently, transfers of WETH to ZkStack chains that use ETH as a base token cannot succeed.

There is a similar issue present in the `relayTokens` function for ZkStack chains with custom gas tokens. In cases where the token to be bridged is the gas token, only the [amount needed to cover the transaction cost will be transferred](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L176) as the `amount` argument of the `relayTokens` function is ignored.

Consider amending the implementation in accordance with the guidelines for [L1 to L2 bridging](https://docs.zksync.io/build/developer-reference/era-contracts/l1-ecosystem-contracts#l1l2-communication) on ZkStack chains. For the `ZkStack_Adapter` and `ZkStack_CustomGasToken_Adapter` contracts, this will require setting the `mintValue` as the total value that is transferred with the call to `requestL2TransactionDirect`, which is `txBaseCost + amount`. The `l2Value` should also be amended to reflect the value to be transferred to the `l2Contract`.

_**Update:** Resolved in [pull request #739](https://github.com/across-protocol/contracts/pull/739) at commit [8a05161](https://github.com/across-protocol/contracts/pull/739/commits/8a05161ee34724dbe633330e38bd8ae8607e89f9)._

Low Severity
------------

### Changing `crossDomainAdmin` Will Prohibit Pending Operations

The `ForwarderBase` contract has the `setCrossDomainAdmin` [function](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ForwarderBase.sol#L69) which changes the `crossDomainAdmin` state [variable](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ForwarderBase.sol#L20). This variable is used to give access control to almost all functions within the contract, including those that are meant to be used to complete L1->L3 message passing and asset transfers. When calling `setCrossDomainAdmin`, it is assumed that there are no outstanding operations that need to be passed to another chain. This is because when operations arrive at L2, the original sender of those is the old `crossDomainAdmin` and will be blocked from continuing further.

In order to raise awareness about such behavior, consider documenting this edge case in the `setCrossDomainAdmin` function.

_**Update:** Resolved in [pull request #729](https://github.com/across-protocol/contracts/pull/729) at commit [4ba3439](https://github.com/across-protocol/contracts/pull/729/commits/4ba34394de24cf79cdce84d9ceccfe61e2b21d03)._

### Incorrect Casts

Orders inside the `ERC7683OrderDepositor` contract may be resolved either by the [`_resolve` function](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683OrderDepositor.sol#L244) or by the [`_resolveFor` function](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683OrderDepositor.sol#L161). Both functions receive an order and convert it to the [`ResolvedCrossChainOrder` struct](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683.sol#L46-L65), which contains the `minReceived` member of the `Output[]` type. However, inside both `_resolve` and `_resolveFor` functions, the `minReceived` member is [initialized](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683OrderDepositor.sol#L210) using the `block.chainId` cast to `uint32`, although the [`Output.chainId` member](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683.sol#L77) is of type `uint64`. This means that the code will revert for blockchains with `chainID` not fitting into `uint32`, although it should work for all blockchains with chain IDs lower than `type(uint64).max`.

Consider casting `block.chainId` to `uint64` instead of `uint32` when initializing `ResolvedCrossChainOrder.minReceived`.

_**Update:** Resolved in [pull request #736](https://github.com/across-protocol/contracts/pull/736) at commit [eee4a75](https://github.com/across-protocol/contracts/pull/736/commits/eee4a75eff9b65a9b09bb53cfc3177d43377f02f). The team stated:_

> _Since the audit commit hash, there has been more suggestions for ERC7683, so some of the fields to structs like `ResolvedCrossChainOrder` have changed. For example, now, the chain ID is represented as a uint256 (see [this](https://github.com/across-protocol/contracts/commit/98c761ee9ca3a496b4a368bdf12743d727644138)). In short, the casting has now just been removed altogether in the proposed PR._

### Potentially Mutable Variable Treated as Immutable

In order to bridge ERC-20 tokens to L2s, the `ZkStack_Adapter` and `ZkStack_CustomGasToken_Adapter` contracts first [approve](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L147) the relevant amount of tokens to the `SHARED_BRIDGE` and then [invoke the `requestL2TransactionTwoBridges` function](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L148-L160) of the `Bridgehub` contract, where they specify the second bridge to be used as `BRIDGE_HUB.sharedBridge()`. The `requestL2TransactionTwoBridges` function then [calls the `bridgehubDeposit` function](https://etherscan.io/address/0x509da1be24432f8804c4a9ff4a3c3f80284cdd13#code#F1#L290) on the second bridge, which [transfers tokens from the contract which initially called the Bridge Hub](https://github.com/matter-labs/era-contracts/blob/aafee035db892689df3f7afe4b89fd6467a39313/l1-contracts/contracts/bridge/L1SharedBridge.sol#L295).

However, the token approval given by the adapters is always for the immutable `SHARED_BRIDGE` address, yet the `BRIDGE_HUB.sharedBridge()` address, specified as the second bridge, returns the current value of the [`sharedBridge` variable](https://etherscan.io/address/0x509da1be24432f8804c4a9ff4a3c3f80284cdd13#code#F1#L19). Although it is unlikely that the variable will change in the future, [it is nonetheless possible](https://etherscan.io/address/0x509da1be24432f8804c4a9ff4a3c3f80284cdd13#code#F1#L111), and if that happens, none of the ZkStack adapters will be able to bridge tokens as the allowance will be given to the previous `sharedBridge` address.

Consider removing the `SHARED_BRIDGE` variable and always accessing the `sharedBridge` variable through `BRIDGE_HUB.sharedBridge()`.

_**Update:** Acknowledged, not resolved. The decision has been made to redeploy the adapters in case when the `sharedBridge` variable changes and not to call `BRIDGE_HUB.sharedBridge()` in order to save gas. `BRIDGE_HUB.sharedBridge()` calls have been replaced with the `SHARED_BRIDGE` variable accesses in the commit [3d260d7](https://github.com/across-protocol/contracts/pull/748/commits/3d260d73ba7aa3a63bdf83aad4d9ab6864cb27fc) in order to reduce gas cost further. The team stated:_

> _This is true, but we think this may be one of the few where we may want to have this behavior. This is because we call these adapters often, and since they are deployed on L1, they can become fairly expensive. For this reason, it is particularly important to minimize the gas cost whenever possible, and this is one such shortcut we take. \[...\] Particularly, in the event the bridge \_does_ change, the adapter calls would just revert, and we would need to redeploy. To be clear, if the shared bridge does change, we will need to deploy a new adapter. The hope is that in the long run, the cost of redeploying will be cheaper than making an extra call on the adapter for each new transaction.\_

Notes & Additional Information
------------------------------

### Repeated Code

The [`_setCrossDomainAdmin`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ForwarderBase.sol#L144) `internal` function of the `ForwarderBase` contract is called [inside](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ForwarderBase.sol#L71) the `setCrossDomainAdmin` external function that is only callable by the admin. However, both functions implement the same logic and emit the same events.

Consider removing duplicated logic from the external function's body and keep the logic and event emission inside the internal definition.

_**Update:** Resolved in [pull request #728](https://github.com/across-protocol/contracts/pull/728) at commit [1ecbb3f](https://github.com/across-protocol/contracts/pull/728/commits/1ecbb3f8033d26dcab57e8ddd462800649fdc253)._

### Adapters Cannot Be Removed From the Forwarder Contracts

The [`updateAdapter`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ForwarderBase.sol#L82-L86) function of the `ForwarderBase` contract allows for a new destination chain ID to be linked with the appropriate adapter for cross-chain forwarding. However, should a chain become unsupported at some time in the future, the target of the `chainId` cannot be set to `address(0)`, nor can it be deleted from the `chainAdapters` mapping.

Consider adding logic to remove an adapter for a given destination chain.

_**Update:** Resolved in [pull request #728](https://github.com/across-protocol/contracts/pull/728) at commit [b621adf](https://github.com/across-protocol/contracts/pull/728/commits/b621adf0524f2c01021f14e421efb043c1bce086)._

### Unused Struct

The [`AcrossDestinationFillerData` struct](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683Across.sol#L24-L26) declared in `ERC7683Across.sol` is not used anywhere in the codebase.

To improve the overall clarity, intentionality, and readability of the codebase, consider either using or removing any currently unused structs.

_**Update:** Resolved in [pull request #744](https://github.com/across-protocol/contracts/pull/744) at commit [9f54455](https://github.com/across-protocol/contracts/pull/744/commits/9f5445571a98f13248a21acba3ac3fe40c737abd) by using the `AcrossDestinationFillerData` struct in the `fill` function of the `SpokePool` contract._

### Misleading Docs

Throughout the codebase, multiple instances of misleading documentation were identified:

*   This [comment](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/Router_Adapter.sol#L75C15-L75C67) states that the `L2_TARGET` contract implements the `AdapterInterface`, but in reality, it implements the `ForwarderInterface`.
*   This [comment](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/Arbitrum_WithdrawalHelper.sol#L52) refers to a forwarder contract, not the withdrawal helper, and the admin is not capable of sending root bundles / messages to the withdrawal helper contract.
*   This [comment](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/WithdrawalHelperBase.sol#L49-L50) and this other [comment](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/Ovm_WithdrawalHelper.sol#L67-L68) contain the description of a non-existent `_crossDomainAdmin` parameter of the constructor.
*   The [link](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L25) specified in both the `ZkStack_Adapter` and `ZkStack_CustomGasToken_Adapter` contracts is incorrect as it points to a nonexistent location.

Consider correcting the aforementioned comments to improve the overall clarity and readability of the codebase.

_**Update:** Resolved in [pull request #728](https://github.com/across-protocol/contracts/pull/728) at commit [702f21e](https://github.com/across-protocol/contracts/pull/728/commits/702f21ee91366fbdcdb0ee402c2a114d8128c680)._

### Unused Import

The `SafeERC20` library has been [imported](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/WithdrawalHelperBase.sol#L5) in the `WithdrawalHelperBase` contract. This library is used for `IERC20` functions, but there are no such functions in this abstract contract. Since this library has also been imported in the derived [`Arbitrum_WithdrawalHelper`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/Arbitrum_WithdrawalHelper.sol#L20) and [`Ovm_WithdrawalHelper`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/Ovm_WithdrawalHelper.sol#L43) contracts, it may be removed from `WithdrawalHelperBase.sol` without consequence.

Consider removing the unused import of the `SafeERC20` library from the `WithdrawalHelperBase` contract.

_**Update:** Resolved in [pull request #728](https://github.com/across-protocol/contracts/pull/728) at commit [98100c3](https://github.com/across-protocol/contracts/pull/728/commits/98100c3dc054b8a871ec7a0fdf25224f88ccca31)._

### Missing Docstrings

Throughout the codebase, multiple instances of functions lacking proper docstrings were identified. One example is the [`_bridgeTokensToHubPool` function](https://github.com/across-protocol/contracts/blob/d4416cd6ba0ac7864147cdfac5d78546a0a624b6/contracts/WorldChain_SpokePool.sol#L51), declared inside `WorldChain_SpokePool.sol`.

Consider thoroughly documenting all functions (and their parameters) that are part of any contract's public API. Functions implementing sensitive functionality, even if not public, should be clearly documented as well. When writing docstrings, consider following the Ethereum Natural Specification Format (NatSpec).

_**Update:** Resolved in [pull request #647](https://github.com/across-protocol/contracts/pull/647) at commit [08534da](https://github.com/across-protocol/contracts/pull/647/commits/08534da0eaca36c2f7bd0d3e1899ee1fd7ee941d)._

### State Variable Visibility Not Explicitly Declared

Within the `ForwarderBase.sol` file, the [`chainAdapters` state variable](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ForwarderBase.sol#L26) lacks an explicitly declared visibility.

For improved code clarity, consider always explicitly declaring the visibility of state variables, even when the default visibility matches the intended visibility.

_**Update:** Resolved in [pull request #728](https://github.com/across-protocol/contracts/pull/728) at commit [467a207](https://github.com/across-protocol/contracts/pull/728/commits/467a2072a0cdede768d2691fd575bd34f7bc9aee)._

Throughout the codebase, multiple opportunities for comment improvement were identified:

*   This [comment](https://github.com/across-protocol/contracts/blob/51c45b2b9ca06314dac9ec4f12fe04d37da58d70/contracts/chain-adapters/WorldChain_Adapter.sol#L95) specifically refers to the WorldChain, but it could also apply to other blockchains. Consider modifying it so that it is more general.
*   In this [comment](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/WithdrawalHelperBase.sol#L15), L1 and L2 references are in lowercase which is inconsistent with the rest of the comments where they are referenced using uppercase letters. Consider changing "l1" to "L1" and "l2" to "L2" for consistency.

Consider implementing the aforementioned comment improvement suggestions in order to improve the overall clarity and readability of the codebase.

_**Update:** Resolved in [pull request #728](https://github.com/across-protocol/contracts/pull/728) at commit [30b1ecb](https://github.com/across-protocol/contracts/pull/728/commits/30b1ecbfa944a8129ce68e02d207c3c8e1ec7e28) and in [pull request #646](https://github.com/across-protocol/contracts/pull/646) at commit [f39418a](https://github.com/across-protocol/contracts/pull/646/commits/f39418a805f36e26b12ffcf50f8de2a6d2b91a87)._

### Lack of Indexed Event Parameters

Throughout the codebase, multiple instances of events without indexed parameters were identified:

*   The [`SetXDomainAdmin` event](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/WithdrawalHelperBase.sol#L29) in `WithdrawalHelperBase.sol`
*   The [`ZkStackMessageRelayed` event](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_Adapter.sol#L52) in `ZkStack_Adapter.sol`
*   The [`ZkStackMessageRelayed` event](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ZkStack_CustomGasToken_Adapter.sol#L73) in `ZkStack_CustomGasToken_Adapter.sol`

To improve the ability of off-chain services to search and filter for specific events, consider [indexing event parameters](https://solidity.readthedocs.io/en/latest/contracts.html#events).

_**Update:** Resolved in [pull request #728](https://github.com/across-protocol/contracts/pull/728) at commit [e13dd1f](https://github.com/across-protocol/contracts/pull/728/commits/e13dd1f92047361c543f4ffc25b4f2742249ffc9)._

### Naming Suggestions

Throughout the codebase, multiple opportunities for improved naming were identified:

*   The [`CROSS_CHAIN_ORDER_TYPE` variable](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683Across.sol#L49) could be renamed to `GASLESS_CROSS_CHAIN_ORDER_TYPE`.
*   The [`CROSS_CHAIN_ORDER_EIP712_TYPE` variable](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683Across.sol#L62) could be renamed to `GASLESS_CROSS_CHAIN_ORDER_EIP712_TYPE`.
*   The [`CROSS_CHAIN_ORDER_TYPE_HASH` variable](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683Across.sol#L64) could be renamed to `GASLESS_CROSS_CHAIN_ORDER_TYPE_HASH`.
*   The [`exclusivityDeadline` parameter](https://github.com/across-protocol/contracts/blob/108be77c29a3861c64bdf66209ac6735a6a87090/contracts/erc7683/ERC7683OrderDepositor.sol#L352) of the `_callDeposit` function could be renamed to `exclusivityPeriod` in order to be consistent with the `AcrossOrderData` struct. We also recommend ensuring that the code in the `SpokePool` contract is consistent with this change (i.e., the parameter is indeed treated as a period of time and not as a timestamp).

Consider renaming the variables specified above to improve code readability.

_**Update:** Resolved in [pull request #728](https://github.com/across-protocol/contracts/pull/728) at commit [03a0d1a](https://github.com/across-protocol/contracts/pull/728/commits/03a0d1ad858bddee78bfde03dca6804c924859c1)._

### File and Contract Names Mismatch

The [`ERC7683Across.sol`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/erc7683/ERC7683Across.sol) file name does not match the `ERC7683Permit2Lib` library name.

To make the codebase easier to understand for developers and reviewers, consider renaming the file to match the library name.

_**Update:** Resolved in [pull request #728](https://github.com/across-protocol/contracts/pull/728) at commit [3df9450](https://github.com/across-protocol/contracts/pull/728/commits/3df94503a975b89fcf40b8626fe18e7dc307f4cb)._

### Constant Could be Used to Denote ETH on L2s

In the ZKStack adapters, `address(1)` is used to represent ETH when it is used as the gas token. In both contracts, this value is used several times and could be declared as a constant, similar to the [`ETH_TOKEN_ADDRESS` constant](https://github.com/matter-labs/era-contracts/blob/aafee035db892689df3f7afe4b89fd6467a39313/l1-contracts/contracts/common/Config.sol#L105) which is [used](https://github.com/matter-labs/era-contracts/blob/aafee035db892689df3f7afe4b89fd6467a39313/l1-contracts/contracts/bridgehub/Bridgehub.sol#L13) in the `Bridgehub` contract.

In order to improve readability of the codebase, consider declaring `address(1)` as a constant with a descriptive name.

_**Update:** Resolved in [pull request #728](https://github.com/across-protocol/contracts/pull/728) at commit [813bf95](https://github.com/across-protocol/contracts/pull/728/commits/813bf959a6e650014e5139fd40f888f8d2d03d62)._

### Unclear Pragma Directives Are Used

In order to clearly identify the Solidity version with which the contracts will be compiled, pragma directives should be fixed and consistent across file imports. The `Ovm_WithdrawalHelper.sol` file has the pragma directive [`pragma solidity ^0.8.0;`](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/Ovm_WithdrawalHelper.sol#L3) and imports the [WithdrawalHelperBase.sol](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/WithdrawalHelperBase.sol) file, which has a different pragma directive - `^0.8.19`.

The intention seems to be to fix the version to be lower than `v0.8.20`, which is where the `PUSH0` opcode has been introduced. However, `^0.8.19` will allow any version greater than or equal to that (and lower than `v0.9.0`) to be used. In addition, the `Arbitrum_WithdrawalHelper` contract [has](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/l2/Arbitrum_WithdrawalHelper.sol#L4) a comment that states that Arbitrum only supports `v0.8.19`, but the referenced documentation states differently and indeed shows that Arbitrum now supports `PUSH0` opcode.

Consider reviewing the pragma directives to make them consistent. If there is any reason to believe that the version should be less than the `v0.8.20`, use `<=` instead of `^`.

_**Update:** Resolved in [pull request #728](https://github.com/across-protocol/contracts/pull/728) at commit [c335be2](https://github.com/across-protocol/contracts/pull/728/commits/c335be267116dff39906de5bfa980c9ed1797a9b)._

### Incorrect Interface Implementation

The [`ERC7683OrderDepositor` contract](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/erc7683/ERC7683OrderDepositor.sol#L18-L359) does implement the `IOriginSettler` interface declared in [ERC-7683](https://github.com/across-protocol/ERCs/blob/d975d7b4b58fa3d1aa6db1763935cfa2ab1444b1/ERCS/erc-7683.md). However, there are several inconsistencies between the parameters' names originally specified in the interface and the names used in the `ERC7683OrderDepositor` contract:

*   The `fillerData` parameter's name of the `openFor` function does not match the name from the `IOriginSettler` interface (`originFillerData`).
*   Return parameters of the `resolve` and `resolveFor` functions should be named in the `IOriginSettler` as they are present in the implementation.

Consider making the interface and implementation consistent with each other in order to improve code readability.

_**Update:** Partially resolved in [pull request #728](https://github.com/across-protocol/contracts/pull/728) at commit [88ae26a](https://github.com/across-protocol/contracts/pull/728/commits/88ae26a9357c002c1d39bbb7546ac9cbaeafac67). The team stated:_

> _We ended up only addressing the first bullet point of this issue. The motivation for this is that we want `resolve` and `resolveFor` to not define a return variable on the interface level. The commit attached addresses the first point, but not the second point._

Client Reported
---------------

### Deposits Not Possible After Fill Deadline

The predictability of the relay hashes enables the fillers to fill the deposits on target chains before they are created on origin chains. When a deposit is created on the origin chain, the current block timestamp is [validated](https://github.com/across-protocol/contracts/blob/7641fbf38b661e02fc00f3b33d7e587c6dc5f06f/contracts/SpokePool.sol#L1188), such that the deposit has to be made with the fill deadline in the future.

However, it is possible to have a scenario in which a pre-fill has happened for a deposit, but the deposit has not been made until the fill deadline has passed. It could for example happen as a result of a high blockchain congestion or a blockchain halt. In such a case, it will not be possible to create a deposit anymore, which results in a loss of assets for the pre-filler.

_**Update:** The team resolved this in [pull request #870](https://github.com/across-protocol/contracts/pull/870) at commit [3b21fea](https://github.com/across-protocol/contracts/pull/870/commits/3b21feabe54ba6b5f4ceafb35a5a2da01acc8b57), allowing to make deposits after the fill deadline has passed. As a side effect for the fix, it is now possible to create a deposit which has not been pre-filled, after the fill deadline. It would result in temporary transfer of assets from the depositor, but the assets will be refunded afterwards._

Recommendations
---------------

### Cross-chain Calls May Fail Due to Insufficient Assets

Communication from L1 to L3 will require the use of adapter contracts on the intermediary L2. The Across team has stated that the adapter contracts for these calls will be based on the current adapter contracts, but there are key differences that should be kept in mind.

The `Router_Adapter` contract enables the sending of cross-chain messages from L1 to L2 and then on to L3. For example, in the `Arbitrum_Adapter` contract, the `relayMessage` and `relayTokens` functions include the required gas for L2 execution inside the [function logic](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/Arbitrum_Adapter.sol#L87). This presupposes that the calling contract, the HubPool on L1, holds enough ETH to cover this gas cost. This is enforced by a [minimum balance check](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/Arbitrum_Adapter.sol#L176-L180) inside the `relayMessage` and the `relayTokens` functions.

However, on the L2, the forwarder contract is the caller to the adapter contract. The [`relayMessage` function](https://github.com/across-protocol/contracts/blob/5a0c67c984d19a3bb843a4cec9bb081734583dd1/contracts/chain-adapters/ForwarderBase.sol#L95-L134) of the `ForwarderBase` contract does not have a check to ensure that the required amount of the gas token is present to perform the L2 to L3 call. Furthermore, there does not currently appear to be any automated logic present in the protocol to provide the forwarder contracts with the assets they may need in order to pay for gas for L3 transactions.

In light of the above, it is recommended to ensure that the adapter contracts on L2 are tailored to the target L3, taking into account the target chain's gas token and bridging logic. It is also recommended to ensure that the forwarder contracts always have enough assets to be able to successfully execute both `relayMessage` and `relayTokens` functions.

### More Thorough Tests Could Be Implemented

In order to enhance the quality and security of the codebase, it is necessary to implement a comprehensive testing suite. This should include both unit tests, which test each component in isolation, and integration tests, which ensure that the interactions between different parts of the system and between the system and external components lead to the desired outcomes. Integration tests can be implemented by forking a blockchain at a specific block and interacting with the contracts already deployed and configured, such as bridges. Throughout the audit, multiple issues were identified which indicated that the current testing suite is not sufficient.

Consider implementing a thorough testing suite for the codebase. This will help ensure better code quality and greatly reduce the number of issues present in the codebase in the future.

Conclusion
----------

The audited codebase introduced support for L3 blockchains in the Across protocol and implemented new changes as laid out in the `ERC-7683` standard. In addition, several new adapters have been added, introducing support for new blockchains and modifying the logic related to calculating the IDs of deposits inside SpokePools.

Given the complexity of the protocol and the number of external components it depends on, we believe that the codebase would highly benefit from implementing integration tests, which would allow for the identification of many errors related to improper use of bridges and messaging mechanisms. We believe that the majority of issues with medium and higher severity that were identified during this engagement could have been easily detected during development by a proper integration testing suite which goes beyond mocking external components. Moreover, given that the `ERC-7683` standard is currently undergoing modifications, and it is likely that new changes will be introduced to it after the audit, we recommend ensuring that the code adheres to the final version of the standard.

The Risk Labs team has been consistently helpful throughout the engagement, promptly answering all our questions and thoroughly explaining the protocol's details.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kEFy-B8yBrZjxmSKXPNZ8HWe09ZKA&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=189846601048&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=43f04266-0def-4671-9429-ec6bf6138e15&redirect_url=APefjpGneKLuJYJTCPamPfYzsJNKsyjGv62kLqjqnuAfrepE81YMipfm-hOGFbD0i8ho0Vfwy2HnfTomT-OgtNC-X6l6EBLMdhCKAwf9DO8g0SPKPJ2_shRFXW-RaNllR0OOkZxc9ZMXCevmVoruFchVmqLuMVOeOfkfe7yebszVaplPg7ABcCeRqj8_NvcqDlcop5gHWOoy2pLqOOYFzry4TbxXi745wMPiLvKGytFTTmgdclPVUCq8VgIpspwcI7U9Vr_zuVMc&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Facross-audit&ts=1770534036912&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.68.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")