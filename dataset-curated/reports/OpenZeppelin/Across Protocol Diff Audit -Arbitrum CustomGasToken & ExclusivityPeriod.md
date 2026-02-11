\- May 12, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

**Type:** DeFi  
**Timeline:** August 28, 2024 → August 30, 2024**Languages:** Solidity

**Findings**Total issues: 13 (8 resolved)  
Critical: 1 (1 resolved) · High: 0 (0 resolved) · Medium: 1 (0 resolved) · Low: 4 (2 resolved)

**Notes & Additional Information**7 notes raised (5 resolved)

  
Scope

We audited the pull requests (PRs) [#584](https://github.com/across-protocol/contracts/pull/584) and [#585](https://github.com/across-protocol/contracts/pull/585) of the [across-protocol/contracts](https://github.com/across-protocol/contracts/) repository. The merge commit [f56146a](https://github.com/across-protocol/contracts/commit/f56146a01ca9c62e6206a2c23c55dbe01a25a912) was used as the reference for both sets of changes.

In scope were the following files:

`contracts
├── chain-adapters
│   ├── Arbitrum_CustomGasToken_Adapter.sol
│   └── Arbitrum_CustomGasToken_Funder.sol
└── SpokePool.sol` 

System Overview
---------------

The [Across Protocol](https://github.com/across-protocol/contracts/) has been designed to enable instant token transfers across multiple blockchain networks. At the core of the protocol is the `HubPool` contract on the Ethereum mainnet, which serves as a central liquidity hub and cross-chain administrator for all contracts within the system. This pool governs the `SpokePool` contracts deployed on various networks that either initiate token deposits or serve as the final destination for transfers.

The protocol recently underwent updates through PRs **#584** and **#585**.

[**PR #584**](https://github.com/across-protocol/contracts/pull/584) modified how the protocol handles exclusivity in relay operations. It replaced the `exclusivityDeadline` with an `exclusivityPeriod`, ensuring that the exclusivity window is dynamically calculated based on when the origin chain transaction is mined. This update includes:

*   Adjusting how the deadline is set. This has been done by adding the user-defined period to the current time at the moment of transaction mining.
*   Refining timestamp checks within both the deposit and fill methods to align with the new approach.

One additional reason for implementing the above changes is that now, the period is relative to when the transaction is included in a block, and it does not rely on an external timestamp anymore.

[**PR #585**](https://github.com/across-protocol/contracts/pull/585) introduced two new contracts specifically designed to enhance the protocol’s operations between the Ethereum and Arbitrum networks:

*   **`Arbitrum_CustomGasToken_Funder`:** This contract securely stores ERC-20 tokens used as gas tokens for cross-chain transaction fees from L1 to L2. The contract restricts token withdrawal capabilities to the owner, ensuring secure management of these funds.
    
*   **`Arbitrum_CustomGasToken_Adapter`:** This contract replicates the functionality of the existing `Arbitrum_Adapter`. Additionally, it allows using the custom gas tokens instead of ETH to pay the transaction fees for cross-chain messages, providing more flexibility in managing gas costs.
    

Security Model and Trust Assumptions
------------------------------------

### Reentrancy Protection and Trust Assumptions

The following observations were made regarding the security model and trust assumptions of the audited codebase:

*   **Gas Token Management:** The `Arbitrum_CustomGasToken_Adapter` contract relies on the correct management of gas tokens by the funder contract. It uses these tokens for cross-chain transaction fees, and the secure withdrawal of these tokens is strictly controlled by the owner of this contract which inherits OpenZeppelin's `Ownable` contract. This ensures that only the owner can execute withdrawal operations.
    
*   **Delegatecall Assumptions:** According to the documentation and the design of the `Arbitrum_CustomGasToken_Adapter` contract, this contract is intended to be called via `delegatecall`. This means that the security practices and protections, including reentrancy guards, must be implemented in the contract that executes the `delegatecall`.
    
*   **Contract Initialization:** The `Arbitrum_CustomGasToken_Adapter` contract introduces the flexibility to use custom gas tokens instead of ETH for paying transaction fees. This is particularly helpful for certain Arbitrum L2 and L3 environments. A key assumption in the security model is that the initial configurations set during the construction of the `Arbitrum_CustomGasToken_Adapter` contract - such as `L2_MAX_SUBMISSION_COST` and other critical variables — are correctly and securely defined at the time of deployment.
    
*   **Front-Running Opportunities & Assumptions:** Frontrunning is not considered a risk due to the design of the protocol's proposal mechanism. To interact with the `HubPool`, a proposer must submit a bundle that passes a liveness challenge period, typically lasting 2 hours. After this period, the proposal is assumed to be valid, with the protocol operating under the assumption that no malicious root bundle will ever be validated. Furthermore, only one valid proposal can exist for a given set of block ranges, ensuring that no competing valid proposals can overlap. The strict validation rules, combined with the fact that proposers have no control over the actual contents of the proposal beyond setting block ranges within predefined constraints, significantly reduce the possibility of frontrunning or manipulating the outcome of proposals.
    
    This structure effectively mitigates frontrunning risks, as the final proposal is locked in and publicly verified after the liveness period. Since execution of the proposal, including any pre-funded tokens (like custom gas tokens), only occurs after a proposal is deemed valid, there is no opportunity for frontrunning during this phase.
    

### Privileged Roles

As mentioned above, the only privileged role within the contracts introduced in PR #585 is found in the `Arbitrum_CustomGasToken_Funder` contract. The owner is meant to be the `HubPool` contract, which will delegatecall the `Arbitrum_CustomGasToken_Adapter` contract, triggering the logic that withdraws funds from the funder contract.

In contrast, the `Arbitrum_CustomGasToken_Adapter` contract does not include any direct access control mechanisms. It is designed to be called via delegatecall, meaning that access control and permissions should be enforced by the contract executing the delegatecall (e.g., the `HubPool`).

Critical Severity
-----------------

### Wrong Scaling for Amount of Gas Tokens

The `Arbitrum_CustomGasToken_Adapter` [contract](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L130) is an adapter meant to handle cases where the destination chain uses a custom token to charge gas fees. Such a token might have non-standard decimals so proper scaling must be performed in order to correctly calculate the amounts.

The `_pullCustomGas` [function](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L284) of this contract is used both by the [`relayTokens`](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L221) and [`relayMessage`](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L195) functions to calculate the amount of gas tokens needed to pay for the chosen operation. This function first calculates the amount owed in the `getL1CallValue` [function](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L285) and then [withdraws](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L286) this amount from the `CUSTOM_GAS_TOKEN_FUNDER` contract (a specialized contract that holds the gas token funds needed).

The `getL1CallValue` function calculates the required amount of gas tokens by using the following formula:

`return L2_MAX_SUBMISSION_COST + L2_GAS_PRICE * l2GasLimit` 

In the above formula:

*   `L2_MAX_SUBMISSION_COST` is the amount of gas allocated to pay for the base submission fee of the L1->L2 operation. [According](https://github.com/OffchainLabs/nitro-contracts/blob/main/src/bridge/AbsInbox.sol#L236) to the `AbsInbox` Arbitrum contract, this amount must be represented with an 18-decimal scale.
*   `L2_GAS_PRICE` is the gas price bid for the immediate L2 execution attempt. According to the same `AbsInbox` contract, the scale should also be 18 decimals.
*   `l2GasLimit` is a parameter which is in pure units of gas and depends on which operation (`relayTokens` or `relayMessage`) is being performed.

As one can see, the amount returned by the `getL1CallValue` function is in an 18-decimal scale and is directly used for withdrawing funds from the custom gas token funder. However, this is incorrect since the custom gas token might have a different scale.

For example, if the custom gas token is USDC which has 6 decimals, the amount being charged is off the scale by a factor of `10**(18 - 6)`. The result is that the `Arbitrum_CusstomGasToken_Adapter` logic will withdraw an amount way bigger than what is needed. What is worse is that such an amount is then directly passed to the `createRetryableTicket` [function](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L206) of the L1 Arbitrum inbox contract, which is then responsible for [pulling](https://github.com/OffchainLabs/nitro-contracts/blob/main/src/bridge/ERC20Inbox.sol#L139) these tokens out of the calling contract, overcharging the needed amount by many factors.

Consider scaling the amount returned by the `getL1CallValue` function by the amount of decimals of the custom gas token, using the scaled value to withdraw the correct amount from the funder contract, and passing it to the `createRetryableTicket` function.

_**Update:** Resolved in [pull request #589](https://github.com/across-protocol/contracts/pull/589). The Risk Labs team stated:_

> _Nice catch._

Medium Severity
---------------

### Outdated `SafeERC20` Contract Does Not Approve to Zero First

Some ERC-20 tokens (like USDT on the Ethereum mainnet) do not work properly when one attempts to change the allowance from an existing non-zero value. The `Arbitrum_CustomGasToken_Adapter` contract [currently](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L255) utilizes an outdated version of the `SafeERC20` library from OpenZeppelin which does not set the spender’s allowance to zero before updating it to the new value.

To mitigate potential issues with tokens that require resetting the allowance to zero before any updates, it is recommended that the OpenZeppelin [`SafeERC20`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol) library be updated to the latest version. Doing this will ensure compatibility with tokens that enforce the requirement of setting the allowance to zero first, thereby preventing related issues.

_**Update:** Acknowledged, not resolved. The Risk Labs team stated:_

> _Updating to the latest OZ versions will introduce a lot of contract changes and peer dependency updates, which we do not think is within the scope of this audit. For example, see the contract changes [here](https://github.com/across-protocol/contracts/pull/591). As you can see, it is very messy._
> 
> _On the approve issue, we think you should have pointed us more in the direction of why we should set the approval to 0. We had to read through the release notes to arrive at [this](https://github.com/OpenZeppelin/openzeppelin-contracts/pull/4231) thread where it became clear to us that certain tokens like USDT require approvals to be set to 0 first._
> 
> _This makes sense to us but we do not think we need to make any changes. The contracts have no other way to set allowances (unless the owner manually does this via admin action) and the allowance is expected to be fully utilized in the function call. Therefore, we expect allowances to be 0 outside of a transaction. This is why we think we are safe when it comes to tokens with approval logic like that of USDT._

Low Severity
------------

### Floating Pragma

Pragma directives should be fixed to clearly identify the Solidity version with which the contracts will be compiled.

Throughout the codebase, multiple instances of floating pragma directives were identified:

*   `Arbitrum_CustomGasToken_Adapter.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L2) floating pragma directive.
*   `Arbitrum_CustomGasToken_Funder.sol` has the [`solidity ^0.8.0`](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Funder.sol#L2) floating pragma directive.

Consider using fixed pragma directives.

_**Update:** Acknowledged, not resolved. The Risk Labs team stated:_

> _This matches the existing style and we prefer to use floating pragma in the Solidity files and set the exact version in `hardhat.config`. For some contracts like `Linea_SpokePool`, `Arbitrum_SpokePool`, and `SpokePoolVerifier`, we require a fixed version so we set that there._

### Missing Docstrings

Throughout the codebase, multiple instances of missing docstrings were identified:

*   In `Arbitrum_CustomGasToken_Adapter.sol`, the [`FunderInterface` interface](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L11-L13)
*   In `Arbitrum_CustomGasToken_Adapter.sol`, the [`withdraw` function](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L12)
*   In `Arbitrum_CustomGasToken_Adapter.sol`, the [`L2_CALL_VALUE` state variable](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L144)
*   In `Arbitrum_CustomGasToken_Adapter.sol`, the [`RELAY_TOKENS_L2_GAS_LIMIT` state variable](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L146)
*   In `Arbitrum_CustomGasToken_Adapter.sol`, the [`RELAY_MESSAGE_L2_GAS_LIMIT` state variable](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L147)
*   In `Arbitrum_CustomGasToken_Adapter.sol`, the [`L1_INBOX` state variable](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L152)
*   In `Arbitrum_CustomGasToken_Adapter.sol`, the [`L1_ERC20_GATEWAY_ROUTER` state variable](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L154)
*   In `Arbitrum_CustomGasToken_Adapter.sol`, the [`CUSTOM_GAS_TOKEN_FUNDER` state variable](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L159)
*   In `Arbitrum_CustomGasToken_Funder.sol`, the [`Arbitrum_CustomGasToken_Funder` contract](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Funder.sol#L8-L19)

Consider thoroughly documenting all functions (and their parameters) that are part of any contract's public API. Functions implementing sensitive functionality, even if not public, should be clearly documented as well. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in [pull request #592](https://github.com/across-protocol/contracts/pull/592)._

### Replace `require` Statements with Custom Errors

As stated in the [official](https://soliditylang.org/blog/2021/04/21/custom-errors/) release of Solidity 0.8.4, utilizing custom errors can reduce runtime and deployment costs, as indicated by the [following](https://blog.openzeppelin.com/defining-industry-standards-for-custom-error-messages-to-improve-the-web3-developer-experience) benchmark, while also improving clarity in error handling.

Consider replacing all [`require` statements](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L183) with custom errors.

_**Update:** Resolved in [pull request #593](https://github.com/across-protocol/contracts/pull/593)._

### Potential Locked ETH in `Arbitrum_CustomGasToken_Adapter`

The `Arbitrum_CustomGasToken_Adapter` contract designates the [`relayMessage`](https://github.com/across-protocol/contracts/blob/9674ed0f9fbecb6a1fda87e9d5081a91eb47042c/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L195) and [`relayTokens`](https://github.com/across-protocol/contracts/blob/9674ed0f9fbecb6a1fda87e9d5081a91eb47042c/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L221) functions as `payable`. However, these functions are designed to pay gas fees using the custom gas token instead of ETH. Consequently, the `payable` attribute is unnecessary since no `msg.value` (ETH) is utilized in these transactions. Leaving the `relayMessage` and `relayTokens` functions marked as `payable` can lead to potential issues whereby the ETH sent to the contract remains locked and inaccessible. This is because the ETH would cease to be usable or refundable during the execution of these functions.

To ensure that the ETH is not inadvertently trapped in the contract, consider removing the `payable` attribute from both functions. If that is not possible because the `HubPool` needs to `delegatecall` while maintaining the `payable` keyword, consider documenting this behavior.

_**Update:** Acknowledged, not resolved. The Risk Labs team stated:_

> _We cannot do this because other adapters' implementations of these functions do use `msg.value`. Removing it from just `Arbitrum_CustomGasToken_Adapter` produces the following compile-time error:_

`TypeError: Overriding function changes state mutability from "payable" to "nonpayable".  
   --> contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol:195:5:  
    |  
195 |     function relayMessage(address target, bytes memory message) external override {  
    |     ^ (Relevant source part starts here and spans across multiple lines).  
Note: Overridden function is here:  
  --> contracts/chain-adapters/interfaces/AdapterInterface.sol:22:5:  
   |  
22 |     function relayMessage(address target, bytes calldata message) external payable;  
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


TypeError: Overriding function changes state mutability from "payable" to "nonpayable".  
   --> contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol:221:5:  
    |  
221 |     function relayTokens(  
    |     ^ (Relevant source part starts here and spans across multiple lines).  
Note: Overridden function is here:  
  --> contracts/chain-adapters/interfaces/AdapterInterface.sol:34:5:  
   |  
34 |     function relayTokens(  
   |     ^ (Relevant source part starts here and spans across multiple lines).


Error HH600: Compilation failed` 

> _Moreover, the Adapter is meant to be delegate-called by the HubPool which does have a fallback function so this is not a risk at all._

Notes & Additional Information
------------------------------

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Throughout the codebase, multiple instances of contracts lacking a security contact were identified:

*   The [`Arbitrum_CustomGasToken_Adapter` contract](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol).
*   The [`Arbitrum_CustomGasToken_Funder` contract](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Funder.sol).

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in [pull request #601](https://github.com/across-protocol/contracts/pull/601)._

### Non-Explicit Imports Are Used

The use of non-explicit imports in the codebase can decrease code clarity and may create naming conflicts between locally defined and imported variables. This is particularly relevant when multiple contracts exist within the same Solidity file or when inheritance chains are long.

Throughout the codebase, multiple instances of global imports were identified:

*   The [import "./interfaces/AdapterInterface.sol";](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L4) import in `Arbitrum_CustomGasToken_Adapter.sol`
*   The [import "@openzeppelin/contracts/token/ERC20/IERC20.sol";](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L6) import in `Arbitrum_CustomGasToken_Adapter.sol`
*   The [import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L7) import in `Arbitrum_CustomGasToken_Adapter.sol`
*   The [import "../external/interfaces/CCTPInterfaces.sol";](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L8) import in `Arbitrum_CustomGasToken_Adapter.sol`
*   The [import "../libraries/CircleCCTPAdapter.sol";](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L9) import in `Arbitrum_CustomGasToken_Adapter.sol`
*   The [import "@openzeppelin/contracts/access/Ownable.sol";](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Funder.sol#L4) import in `Arbitrum_CustomGasToken_Funder.sol`
*   The [import "@openzeppelin/contracts/token/ERC20/IERC20.sol";](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Funder.sol#L5) import in `Arbitrum_CustomGasToken_Funder.sol`
*   The [import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Funder.sol#L6) import in `Arbitrum_CustomGasToken_Funder.sol`

Following the principle that clearer code is better code, consider using the named import syntax _(`import {A, B, C} from "X"`)_ to explicitly declare which contracts are being imported.

_**Update:** Resolved in [pull request #600](https://github.com/across-protocol/contracts/pull/600)._

### Lack of Input Validation

The `L2_MAX_SUBMISSION_COST` and the `CUSTOM_GAS_TOKEN_FUNDER` [parameters](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L184-L185) of the `Arbitrum_CustomGasToken_Adapter` contract are set in the constructor without any sort of input validation.

Consider assessing whether input validation is necessary for the aforementioned parameters. If so, consider implementing validation checks to ensure the integrity of the adapter.

_**Update:** Acknowledged, not resolved. The Risk Labs team stated:_

> _This adapter is designed to be hardcoded by the deployer and replaced if any parameters need to be changed. It is also designed to be delegate-called so it is easy to replace. We do not see a need to validate this in the constructor. Instead, we consider it the deployer's responsibility to add a safe deploy script._

### Lack of Backward Compatibility with DAI

The new `Arbitrum_CustomGasToken_Adapter` [contract](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L130) is inspired by the `Arbitrum_Adapter` [contract](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_Adapter.sol#L144). However, when adapting it to host the custom gas token logic, the backward [compatibility](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_Adapter.sol#L253) with legacy routers has been removed, making the custom gas token adapter incompatible with DAI.

Consider documenting any relevant differences between the current codebase and the codebases that served as its inspiration. This will help better communicate the code intent and make it easier to understand.

_**Update:** Acknowledged, not resolved. The Risk Labs team stated:_

> _This is clearly not an issue. The reason we have a special DAI edge case in the `Arbitrum_Adapter` is because the DAI Arbitrum token bridge has a different interface from the default bridge. It remains to be seen whether DAI will have a different interface when bridging to a new L2 supported by the `CustomGasToken_Adapter`. The reason the existing DAI code would not obviously work is because that DAI bridge uses the native token to pay for L1 to L2 messages, not a custom gas token._

### Incomplete or Incorrect Docstrings

Within `Arbitrum_CustomGasToken_Adapter.sol`, multiple instances of incomplete docstrings were identified:

*   In the [`nativeToken`](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L32) and [`bridge`](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L45) functions, not all return values are documented.
*   In the [`getL1CallValue`](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L280-L282) function, the `l2GasLimit` parameter is not documented.
*   In the [`constructor`](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L170) of the `Arbitrum_CustomGasToken_Adapter` contract, the `_l2MaxSubmissionCost` parameter is not documented.
*   In line [126](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/chain-adapters/Arbitrum_CustomGasToken_Adapter.sol#L126) of the `Arbitrum_CustomGasToken_Adapter` contract, the docstring is either unclear or incorrect.
*   In line [526](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/SpokePool.sol#L526) of the `SpokePool` contract, "reayer" should be "relayer".

Consider thoroughly documenting all functions/events (and their parameters or return values) that are part of a contract's public API. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in [pull request #599](https://github.com/across-protocol/contracts/pull/599)._

### Redundant Call

In the `depositV3` [function](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/SpokePool.sol#L532) of the `SpokePool` contract, the `getCurrentTime` function is called again in [line 595](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/SpokePool.sol#L595), despite having already been invoked before in [line 558](https://github.com/across-protocol/contracts/blob/f56146a01ca9c62e6206a2c23c55dbe01a25a912/contracts/SpokePool.sol#L558).

Consider reusing the cached value instead of repeating the function call.

_**Update:** Resolved in [pull request #594](https://github.com/across-protocol/contracts/pull/594)._

### Backward Compatibility Concern with `exclusivityPeriod` Update

The recent [PR #584](https://github.com/across-protocol/contracts/pull/584) introduced a significant change by replacing the `exclusivityDeadline` input with an `exclusivityPeriod`. This update alters how the exclusivity deadline is determined, shifting from a fixed future timestamp to a period calculated relative to the time when the origin chain transaction is mined. This change is not backward compatible, as integrators now need to pass a relative time period instead of a specific future timestamp as they did previously. If an integrator fails to adapt to this change, there is a risk of funds being locked for an extended period, potentially causing significant disruptions.

Consider explicitly documenting the aforementioned changes in the upgrade notes or the migration guide. Clear documentation will help integrators understand the new requirements and avoid issues related to the improper setting of the `exclusivityPeriod` input.

_**Update:** Resolved in [pull request #595](https://github.com/across-protocol/contracts/pull/595)._

Conclusion
----------

The Across protocol enables rapid token transfers between Ethereum L1 and L2 chains. Users deposit funds, relayers transfer the funds to the destination, and depositors receive the amount minus a fee. The `HubPool` contract on L1 manages liquidity, coordinating with the `SpokePool` contracts on each supported chain. On the other hand, Oval captures Oracle Extractable Value (OEV) generated by price updates in DeFi protocols.

The protocol recently underwent significant updates as part of PRs [#584](https://github.com/across-protocol/contracts/pull/584) and [#585](https://github.com/across-protocol/contracts/pull/585). These updates introduced changes to how relay exclusivity is managed and enhanced cross-chain gas fee handling, particularly between Ethereum and Arbitrum. Notably, the update now allows cross-chain transactions to be executed using custom gas tokens instead of ETH to pay fees.

The audit yielded one critical- and one medium-severity vulnerability, along with several lower-severity ones. In addition, various recommendations were made to improve the clarity, readability, and robustness of the codebase.

Throughout the audit, the Risk Labs team provided us with useful context, fast and detailed explanations, as well as valuable insights which helped us better understand the codebase and the changes made to it.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kEv8XoLV6YxwhDTxidaXVet88oXDw&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=179923637025&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=e60a814a-34fa-436a-b626-9a4bc04d4c74&redirect_url=APefjpEeGrvBl8enVkf3Ge6zh_dY79HOHBz3QoflLH34bisfkvl919KPQ0Pwy0xOpl2L8wC3AKUzIbYJ7qHkD5v3zMap4gEvDbkS2CwddZiT63KGomJZr3nRNxhbJ55a7T5Ke2AtDXYSVzNS2CvP1Sya00M8GtFEtF1Q5X3vk-vUSKUHBVEgWLASbrDmsSG5gZ3vSwWD3Fj_9Lx1bHOS7NUo_0tnLvzbuqsMKTZIlV9PtMSlkXud5naXQAIy8M-WpyvZmEUgWiho&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Facross-protocol-diff-audit&ts=1770534036917&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.66.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")