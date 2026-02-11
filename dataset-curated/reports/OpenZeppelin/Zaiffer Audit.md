\- November 27, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

**Summary**

**Type:** Token  
**Timeline:** September 29, 2025 → October 14, 2025  
**Languages:** Solidity

**Findings**  
Total issues: 37 (36 resolved)  
Critical: 1 (1 resolved) · High: 3 (3 resolved) · Medium: 3 (3 resolved) · Low: 17 (17 resolved)

**Notes & Additional Information**  
13 notes raised (12 resolved)

Scope

OpenZeppelin audited the [pyratzlabs/software/usdx](https://gitlab.com/pyratzlabs/software/usdx) repository at commit [f508108](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/tree/f5081087f9bc31564b0d401b4da697a6631cd7dc).

In scope were the following files:

`smart-contracts
└── contracts
    ├── admin
    │   ├── AdminProvider.sol
    │   └── FeeManager.sol
    ├── batcher
    │   └── ERC7984TransferBatcher.sol
    ├── factory
    │   ├── DeploymentCoordinator.sol
    │   ├── RegulatedERC7984UpgradeableFactory.sol
    │   └── WrapperFactory.sol
    ├── swap
    │   └── swap_v0.sol
    ├── token
    │   ├── ERC7984Upgradeable.sol
    │   └── RegulatedERC7984Upgradeable.sol
    └── wrapper
        └── Wrapper.sol` 

_**Update:** The fixes for the findings highlighted in this report - with the exception of N-05, which has been acknowledged - have all been merged in [pull request #23](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/23) at commit [6f2318a9](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/tree/6f2318a9848eee288dde2dc4a2027f5d9f53f88a)._

System Overview
---------------

The system under review provides a comprehensive framework for creating and managing confidential tokens using Zama FHEVM. It allows for the wrapping of standard ERC-20 and native tokens into privacy-preserving equivalents that conform to the ERC-7984 standard. The architecture is designed to be modular, with a clear separation of concerns between token logic, administrative controls, and peripheral services like swapping and batch transfers. Core functionalities include regulated, confidential transactions, fee collection for various operations, and a decentralized deployment process coordinated through specialized factories.

### Deployment Coordinator

The `DeploymentCoordinator` contract serves as the central entry point for deploying new confidential token systems. It orchestrates the creation of a `Wrapper` and a `RegulatedERC7984Upgradeable` confidential token pair for a given underlying asset. This contract centralizes the deployment logic, ensuring that all components are linked correctly. Specifically, the contract:

*   utilizes two specialized factories, `WrapperFactory` and `RegulatedERC7984UpgradeableFactory`, to handle the creation of the respective contracts
*   collects a deployment fee, which is transferred to a recipient designated in the `FeeManager`
*   is responsible for correctly initializing the new confidential token and granting the necessary roles, such as assigning the `WRAPPER_ROLE`, to the `Wrapper` contract

### Factories

The system uses a split-factory architecture to manage contract creation and stay within the bytecode size limits:

*   **`RegulatedERC7984UpgradeableFactory`**: This factory is solely responsible for deploying new instances of the `RegulatedERC7984Upgradeable` token behind an ERC-1967 proxy. It is controlled by `DeploymentCoordinator`.
*   **`WrapperFactory`**: This factory is responsible for deploying new instances of the `Wrapper` contract. It is also controlled by `DeploymentCoordinator`.

### Regulated ERC-7984

`RegulatedERC7984Upgradeable` is the core confidential token contract. It is an upgradeable implementation of the ERC-7984 standard with additional features for regulatory compliance and access control. Specifically, the contract:

*   encrypts balances and transfer amounts using the FHEVM
*   uses `AccessControl` to manage privileged roles, primarily the `WRAPPER_ROLE` (for minting/burning) and the `DEFAULT_ADMIN_ROLE` (for upgrades and administration)
*   introduces a transaction identifier, `nextTxId`, to help track and order operations
*   integrates with an `AdminProvider` instance to enforce compliance checks, such as consulting a `SanctionsList` before processing transactions. The `AdminProvider` contract defines a regulator address that is enabled to decrypt any balance or amount

### Wrapper

The `Wrapper` contract facilitates the conversion between a standard, public token (ERC-20 or ETH) and its confidential counterpart. Specifically, the contract:

*   locks the public asset within the contract and mints a corresponding amount of confidential tokens to a user's address via the `RegulatedERC7984Upgradeable` contract (i.e., **wrapping**)
*   burns a user's confidential tokens and releases the corresponding amount of the underlying public asset back to them (i.e., **unwrapping**)
*   performs asynchronous FHE operations, where a decryption request is sent to the FHEVM and a follow-up transaction (`finalizeUnwrap`) is required to complete the process
*   calculates and facilitates the collection of wrapping and unwrapping fees as defined in the `FeeManager`

### Admin Provider

The `AdminProvider` is the central hub for accessing shared administrative and configuration contracts. By routing administrative interactions through this contract, the system decouples core contracts from specific policy implementations, allowing for easier updates to administrative logic. It provides access to `FeeManager`, `SanctionsList`, and the regulator address.

### Fee Manager

The `FeeManager` contract manages all fee logic for the ecosystem. It defines the fees for wrapping, unwrapping, deployment, and batch transfers. Specifically, the contract:

*   allows a privileged administrator to set fee rates (as basis points or flat fees) and the recipient address for collected fees
*   includes a feature to grant fee waivers to addresses with the `SWAPPER_ROLE`, intended for trusted system components like the automated swap contract

### ERC-7984 Transfer Batcher

The `ERC7984TransferBatcher` utility contract enhances user experience by allowing multiple confidential transfers to be executed in a single on-chain transaction. Specifically, the contract:

*   accepts an array of transfer instructions
*   collects a flat fee for the batch operation, as specified by `FeeManager`
*   includes a retry mechanism, allowing a user to resubmit a failed transfer from a previous batch

### Swap

The `swap_v0` contract enables swaps between different confidential tokens. It acts as an intermediary that bridges the confidential token ecosystem with an external Automated Market Maker (AMM), such as Uniswap:

1.  A user initiates a swap by making a confidential transfer to the `swap_v0` contract.
2.  The contract unwraps the incoming confidential token to its public underlying asset.
3.  It then executes a token swap on the external AMM.
4.  Finally, it wraps the output public asset into its corresponding confidential token and sends it to the final recipient.

The entire flow is designed to handle potential failures in the AMM swap by returning the original funds to the user.

### Upgradeability

The system employs a selective upgradeability model. Only the core confidential token contract, `RegulatedERC7984Upgradeable`, is designed to be upgradeable. Each instance is deployed as a UUPS (Universal Upgradeable Proxy Standard) proxy, meaning upgrade logic is contained within the implementation contract and controlled by an account with the `DEFAULT_ADMIN_ROLE`. Per `DeploymentCoordinator`, the `AdminProvider` owner is initially set up with this role. This allows for fixing bugs or adding features to individual token contracts after deployment.

All other core infrastructure contracts, including the `DeploymentCoordinator`, `WrapperFactory`, `RegulatedERC7984UpgradeableFactory`, `Wrapper`, `AdminProvider`, and `FeeManager`, are immutable. Changes to their logic would require deploying new instances and updating the dependent contracts to point to the new addresses. However, this is not always possible: a `Wrapper` integrates with a specific `AdminProvider`, underlying asset, and confidential token, and cannot easily be redeployed due to the funds it holds. Thus, this approach lacks flexibility.

Security Model and Trust Assumptions
------------------------------------

The system's security relies on a combination of the FHEVM's cryptographic guarantees for confidentiality and a robust set of trust assumptions placed on privileged actors and external systems. While the FHEVM ensures that transaction amounts remain private, the overall integrity, availability, and correctness of the ecosystem depend on the honest and secure behavior of administrators, the correct configuration of its components, and the reliability of integrated external protocols.

During the course of the audit, the following trust assumptions were made:

*   **Administrator Honesty**: The system is centrally controlled by administrators holding highly privileged roles (`owner` or `DEFAULT_ADMIN_ROLE`). These actors are trusted to manage the ecosystem honestly. Their responsibilities include deploying and upgrading contracts, setting critical addresses (like factories and the `AdminProvider`), managing fees, and assigning roles. A malicious administrator could upgrade token contracts to a malicious implementation, set unfair fees, or disrupt the system's operation.
*   **Regulator Honesty**: The `regulator` address, configured via the `AdminProvider`, can decrypt any balance and transfer amount of the confidential tokens, while the owner of the `SanctionList` can block and unblock users to use these tokens. It is assumed that these roles will not abuse their power to arbitrarily leak private user data or block legitimate users.
*   **Fee Recipient Approval**: The fee recipient needs to approve all `Wrapper` instances such that these can execute a `confidentialTransferFrom` in case of a refund.
*   **Underlying FHEVM Security**: The confidentiality of all balances and transaction amounts is entirely dependent on the security of the underlying Zama FHEVM and its associated libraries. The model assumes the cryptographic primitives, node software, and the `fhevm/solidity` library are correctly implemented and free of vulnerabilities.
*   **External DEX and Token Integrity**: The `SwapV0` contract relies on an external Uniswap-compatible router. It is assumed that the router address is legitimate and that the router itself behaves as expected. A malicious router could steal funds during a swap. Additionally, it is assumed that all underlying tokens wrapped by the system are standard ERC-20 tokens and not rebase tokens, as rebasing could de-balance the 1:1 asset backing in `Wrapper`. It is also assumed that tokens are vetted to work reliably before being used in the protocol. For example, tokens with non-standard `approve` logic (e.g., reverting on `approve(address, 0)`) would break the swap failure handling logic.
*   **`SwapV0` ETH Incompatibility**: The `SwapV0` contract is designed exclusively for token-to-token swaps and does not support native ETH as either an input or an output asset. The contract cannot receive ETH from a DEX and lacks a payable `receive` function to accept direct ETH transfers. Its implementation only calls the `swapExactTokensForTokens` function of the Uniswap router and lacks the logic to handle ETH-specific functions or to manage `msg.value` when wrapping ETH. Consequently, it is assumed that the swap functionality will not be used with any confidential token pair that has native ETH as its underlying asset, as such attempts would consistently fail.
*   **Secure Off-Chain Operations**: The security of all privileged accounts depends on secure off-chain key management. It is assumed these keys are not compromised. The asynchronous unwrapping process also relies on off-chain components to monitor events and submit the `finalizeUnwrap` transaction. This service is expected to have persistent availability.
*   **Correct Initialization and Configuration**: It is assumed that all contracts are initialized with correct parameters. This includes the `AdminProvider` being configured with the correct `FeeManager` and `SanctionsList` addresses, and fees being set to reasonable values.
*   **Operational Integrity of the Coordinator**: The `DeploymentCoordinator` owner is trusted to manage the factory addresses. If a factory is replaced, the owner must ensure that the `DeploymentCoordinator` correctly accepts ownership of the new factory contract to maintain its ability to deploy new pairs.

Critical Severity
-----------------

### Replay of `finalizeUnwrap` Call Leads to Loss of Backing Assets

The [`Wrapper` contract](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol) serves as the custodian for the underlying assets that back a corresponding confidential token, managing the entire lifecycle of wrapping and unwrapping. The unwrapping process is an asynchronous, two-step operation initiated when a user calls `confidentialTransferAndCall` on the confidential token contract. This call invokes the `onConfidentialTransferReceived` function on the `Wrapper`, which then burns the user's confidential tokens and requests decryption of the amount from an FHE oracle. The process concludes when the oracle calls back the [`finalizeUnwrap`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L143) function to execute the final transfer of the underlying assets.

A critical vulnerability exists in the `finalizeUnwrap` function, which can be replayed using previously valid parameters. During a legitimate unwrap, the function retrieves recipient data from the `_receivers` mapping and then deletes the entry. An attacker, however, can re-submit the same request parameters, which will pass the signature check. This replayed call will read from the now-empty storage slot, loading a default `ReceiverEntry` struct where the `to` address and `txId` are zero. The function then transfers the underlying assets to this zero address, causing their permanent loss. Repeated exploitation allows for the systematic draining of the contract's backing funds, rendering the confidential tokens unbacked and valueless. Affected assets involve ETH, WETH, as well as certain ERC-20 tokens that allow transfers to the zero address (e.g., USDT).

To mitigate this vulnerability, consider introducing a validation check within the `finalizeUnwrap` function. This check should require that the `to` address and/or `txId`, loaded from the `_receivers` mapping, is not zero before the function proceeds with the asset transfer.

_**Update:** Resolved in [pull request #5](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/5) at commit [6954855](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/5/diffs?commit_id=6954855fcddadead99a3daf090dd805d2d64ec7c)._

High Severity
-------------

### Missing Return Value Check on ERC-20 Transfers in Wrapper

The [`Wrapper`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol) contract is responsible for all `wrap` and `unwrap` operations, which are fundamental to maintaining the 1:1 asset peg between the standard ERC-20 token and its confidential counterpart. The integrity of this contract is critical to the solvency of its specific token pool.

The `wrap` and `finalizeUnwrap` functions execute [`transferFrom`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L137) and [`transfer`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L172) calls on the underlying ERC-20 token contract but fail to check the boolean return value of these calls. Certain ERC-20 tokens, particularly older or non-compliant ones, may return `false` to indicate a transfer failure instead of reverting the transaction. In such a scenario, the `wrap` function could mint confidential tokens without having received the underlying assets, or the `finalizeUnwrap` function could complete the unwrapping process without successfully sending the underlying tokens to the user. Both cases would break the token's backing and lead to a loss of funds.

Consider using OpenZeppelin's `SafeERC20` library for all interactions with the underlying ERC-20 token. The library's `safeTransfer` and `safeTransferFrom` functions wrap the low-level calls and include the necessary return value check, reverting the transaction if the transfer is unsuccessful. Integrating this library is a standard security practice that will ensure the atomicity of wrap and unwrap operations, thereby guaranteeing the integrity of the funds held in custody by the `Wrapper` contract.

_**Update:** Resolved in [pull request #7](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/7) at commit [1cd8a83](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/7/diffs?commit_id=1cd8a8365ec407a4f7ef952e8776635d887ea16e)._

### Undercollateralized Confidential Tokens Due to Fee-on-Transfer Tokens

The [`Wrapper.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol) contract is responsible for wrapping an underlying ERC-20 token into a confidential equivalent. The `wrap` function calculates the amount of confidential tokens to mint based on the `amount_` parameter provided by the user. This amount is then used to execute a [`transferFrom`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L137) call to pull the underlying tokens into the `Wrapper` contract.

When the underlying asset is a fee-on-transfer token, the `Wrapper` contract receives a smaller amount of tokens than what was specified in the `transferFrom` call due to the token's inherent fee mechanism. The current implementation does not account for this discrepancy. It proceeds to mint confidential tokens based on the user-supplied `amount_`, rather than the actual amount of underlying tokens received. This results in the confidential token becoming undercollateralized, as the total supply of the confidential token is not fully backed by the underlying asset.

To ensure that the confidential token remains fully collateralized, consider modifying the `wrap` function to calculate the amount of tokens to mint based on the actual amount of underlying tokens received. This can be achieved by measuring the `Wrapper` contract's balance of the underlying token before and after the `transferFrom` operation. The difference in balance should then be used as the basis for minting the new confidential tokens.

_**Update:** Resolved in [pull request #6](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6) at commit [5de8c76](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6/diffs?commit_id=5de8c760c3f0da51455fcf86ab7f780edb1e1fdc)._

### Incorrect Refund Logic Causes Fee Loss in Failed ETH Unwraps

The [`finalizeUnwrap`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L143) function of the `Wrapper` contract contains logic to handle failures during the final step of an ETH unwrap. If the low-level call to transfer the unwrapped ETH to the recipient fails, the function is designed to initiate a refund, returning the collected fee and re-minting the user's originally burned confidential tokens.

In the event of a failed ETH transfer, the refund logic incorrectly attempts to execute a [`confidentialTransfer`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L178) of the fee amount from the `Wrapper` contract's own address. The `Wrapper` contract does not hold these fee tokens, as they were sent to the designated fee recipient during the first phase of the unwrap process. Due to the specific behavior of the confidential token, which handles insufficient balances by transferring an encrypted amount of zero rather than reverting, this operation fails silently. While the subsequent `mint` call correctly refunds the user's principal, the fee is never returned, resulting in a partial but permanent loss of funds for the user in this failure scenario.

To ensure that users are fully reimbursed during a failed unwrap, consider modifying the refund logic for the failed ETH transfer case. Instead of using `confidentialTransfer`, the function should use `confidentialTransferFrom` to pull the fee tokens directly from the fee recipient's address and send them to the user. This approach mirrors the correct refunding logic found in the subsequent `else` block of the same function.

_**Update:** Resolved in [pull request #6](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6) at commit [5de8c76](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6/diffs?commit_id=5de8c760c3f0da51455fcf86ab7f780edb1e1fdc)._

Medium Severity
---------------

### Lost Dust on ETH Wrapping Due to Rate Conversion

The [`wrap` function](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L112) of the `Wrapper` contract is responsible for converting underlying assets, including ETH, into their corresponding confidential tokens. When wrapping ETH, the function takes an `amount_` parameter and requires the accompanying `msg.value` to be equal to this amount. The number of confidential tokens to be minted is determined by dividing the input `amount_` by the `rate` defined in the `confidentialToken` contract.

The division operation used to calculate the `scaledAmount` truncates any remainder. If the provided `amount_` is not a perfect multiple of `rate`, the remainder portion of the value (`amount_ % rate`) is accepted into the contract as part of `msg.value` but is not accounted for in the subsequent minting logic. This excess value, or "dust", becomes permanently locked within the `Wrapper` contract, as no mechanism exists to refund the difference to the user.

Consider forwarding the remainder portion to the `to_` address to refund any excess value. Note that the refund cannot be sent to `msg.sender` as that would mean sending value to the `SwapV0` contract due to its integration.

_**Update:** Resolved in [pull request #6](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6) at commit [5de8c76](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6/diffs?commit_id=5de8c760c3f0da51455fcf86ab7f780edb1e1fdc)._

### Unsafe and Incompatible ERC-20 Approve Calls

The [`SwapV0` contract](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol) facilitates token swaps by interacting with a Uniswap V2-compatible router. This process requires the contract to grant token approvals to the router before executing the swap, and then to the corresponding `Wrapper` contract to wrap the output token on success, or re-wrap the input token on failure. These approval operations are fundamental to the contract's ability to manage token flows during swaps.

The contract's implementation of these approvals presents two distinct issues. First, it uses direct, unwrapped calls to the `approve` function on the token's interface and does not check the boolean return value \[[1](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L72), [2](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L102), [3](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L112-113)\]. This is unsafe because some ERC-20 tokens might not revert on failure but instead return `false`, which would cause the swap to fail silently or unpredictably. Second, the contract sets new approvals without first resetting the existing allowance to zero. This makes it incompatible with certain widely-used tokens, such as USDT, which require the allowance to be cleared before a new non-zero value is set. As a result, swaps involving these tokens would consistently fail.

Consider using OpenZeppelin's `SafeERC20` library and replacing all direct `approve` calls with `forceApprove`. This function is specifically designed to address these issues: it ensures that any existing allowance is first reset to zero before the new value is applied, and it also validates the return value of the underlying call, reverting the transaction on any failure. Adopting `forceApprove` will make the swap functionality significantly more secure, reliable, and compatible with the broad ecosystem of ERC-20 tokens.

_**Update:** Resolved in [pull request #9](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/9) at commit [4682438](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/9/diffs?commit_id=4682438d3b7249b4ae994fe10ff6212a4c12d639)._

### User Funds Can Be Permanently Lost During Unwrapping

The unwrapping process is a two-step operation. It begins when a user calls `confidentialTransferAndCall` on the confidential token, which immediately transfers the user's tokens to the `Wrapper` contract. This triggers the [`onConfidentialTransferReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L64) callback, where the `Wrapper` burns the tokens it now owns (on behalf of the user) and transfers the associated fee to the fee recipient. The `Wrapper` contract then requests the asynchronous decryption of the amounts. The process concludes in a subsequent transaction when [`finalizeUnwrap`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L143) is called to execute the final delivery of the underlying asset.

The issue is that the `Wrapper` takes ownership of and burns the user's tokens in the first step, before the final delivery of the underlying asset is confirmed. In the second step, `finalizeUnwrap` attempts to transfer the underlying token to the recipient. If this final [transfer](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L172) fails (e.g., if the underlying token contract blocks the transfer), the entire call reverts. However, the user's confidential tokens (both principal and the fee) would have already been destroyed in the prior transaction. The contract lacks a recovery path for this failure, resulting in the permanent and irrecoverable loss of the user's funds.

Consider implementing a robust recovery mechanism within the `finalizeUnwrap` function using OpenZeppelin's `SafeERC20` library. The underlying token transfer should be performed using `trySafeTransfer`, which returns a boolean success value instead of reverting on failure. If the transfer is unsuccessful, the contract should execute a compensating action as seen in the `else` branch of mismatching amounts and fees.

_**Update:** Resolved in [pull request #8](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/8) at commit [4522288](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/8/diffs?commit_id=4522288049383d13cab8a786b8fcd452136f452d)._

Low Severity
------------

### Ambiguous and Brittle Design for Global Transaction Tracking

The system uses a [`nextTxId`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L127) counter from each `RegulatedERC7984Upgradeable` token as a primary identifier for operations. This ID is consumed by multiple contracts with the goal of providing a unified transaction history. It is used in the [`Wrapper`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L80) for unwraps, the [`ERC7984TransferBatcher`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L49) for batch transfers, and the global `SwapV0` \[[1](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L45), [2](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L100)\] contract for atomic swaps.

This tracking architecture is flawed in two significant ways:

1.  **It is brittle:** The `Wrapper` contract [temporarily decrements](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L80) the global `nextTxId` and relies on an [implicit side effect](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol#L306) of the calling token's contract to restore it. This creates a fragile, non-obvious dependency.
2.  **It is ambiguous:** Since each confidential token has its own independent `nextTxId` counter, the `txId` is only unique within the scope of a single token contract. When a global contract like `SwapV0` [emits an event](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/main/contracts/swap/swap_v0.sol?ref_type=heads#L105-116) containing a `txId`, it is unclear which token the ID belongs to. This forces off-chain clients to perform complex logic to deduce the event's context, undermining the goal of a simple tracking system.

Consider rearchitecting the transaction tracking system to use the `requestId` from `FHE.requestDecryption` as the standard identifier for all complex, asynchronous operations, and removing the `txId` from these flows entirely. For the `Wrapper` unwrap, the `requestId` would be emitted in `UnwrapInitiated` and `UnwrappedFinalized` events to create an explicit link. For the `SwapV0` contract, this same `requestId` could be propagated through the callback `data` to the final `Swap` event, providing a clear end-to-end trace. This change would simplify the codebase by removing all `txId` manipulation and would resolve the ambiguity in events from global contracts, making the entire system more robust, modular, and easier for off-chain services to interpret correctly.

_**Update:** Resolved in [pull request #6](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6) at commit [5de8c76](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6/diffs?commit_id=5de8c760c3f0da51455fcf86ab7f780edb1e1fdc) and [pull request #19](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/19) at commit [de80505](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/19/diffs?commit_id=de80505571e12b54279b4bcf5853fe01a6433a11)._

### Potential Fee Reduction Due to Multiplication Overflow in `getUnwrapFee`

The [`FeeManager`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol) contract contains the [`getUnwrapFee`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol#L68) function, which is responsible for calculating the fee applied during the unwrapping of confidential tokens. This fee is determined by multiplying the encrypted unwrap `amount` by `unwrapFeeBasisPoints` and subsequently dividing the product by 10,000. These arithmetic operations are performed on encrypted 64-bit unsigned integers (`euint64`) using the FHE library.

The [`FHE.mul(amount, FHE.asEuint64(unwrapFeeBasisPoints))`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol#L74) multiplication operation is susceptible to an integer overflow if the `amount` being unwrapped is sufficiently large. In the event of an overflow, the resulting encrypted value wraps around, producing a much smaller number than the true mathematical product. Consequently, the fee calculated from this incorrect value will be significantly lower than intended, leading to a potential loss of revenue for the protocol.

To mitigate this, consider implementing a safeguard within the [`getUnwrapFee`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol#L68) function. A conditional check using `FHE.select` should be employed after first handling the zero-fee case. This check would compute the product of the `amount` and `unwrapFeeBasisPoints` and compare it against the original `amount`. If the product is greater than or equal to the `amount`, it suggests that no overflow has occurred, and the fee is the product divided by 10,000. If an overflow is detected, the fee should be calculated as `type(uint64).max / 10_000`, representing the maximum possible fee. It is important to carefully evaluate the gas implications of this change. This check introduces a computational overhead to every `getUnwrapFee` transaction to guard against a highly unlikely edge case, the impact of which is limited to a loss of protocol fees rather than a direct risk to user funds.

_**Update:** Resolved in [pull request #6](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6) at commit [5de8c76](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6/diffs?commit_id=5de8c760c3f0da51455fcf86ab7f780edb1e1fdc)._

### Missing Input Validation in `FeeManager` Constructor

The constructor of the [`FeeManager`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol) contract is responsible for initializing the contract's state, including the [`wrapFeeBasisPoints`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol#L54) and [`unwrapFeeBasisPoints`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol#L55) parameters. These values are used throughout the system to calculate percentage-based fees for wrapping and unwrapping tokens, with 10,000 representing 100%.

The constructor does not validate that the initial `wrapFeeBasisPoints` and `unwrapFeeBasisPoints` values are less than or equal to the maximum of 10,000. This is inconsistent with the corresponding setter functions, `setWrapFeeBasisPoints` and `setUnwrapFeeBasisPoints`, which both contain this essential check. The absence of this validation could allow the contract to be deployed with an invalid configuration, potentially leading to fees greater than 100% and causing transaction reverts or other unexpected behavior.

To ensure that the contract is always initialized with a valid fee structure, consider adding the same validation logic present in the setter functions to the constructor. This involves requiring that the `wrapFeeBasisPoints_` and `unwrapFeeBasisPoints_` parameters are less than or equal to 10,000.

_**Update:** Resolved in [pull request #10](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/10) at commit [cd4f685](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/10/diffs?commit_id=cd4f68567cce527273de8169966924f9159416c9)._

### Potential Re-entrancy in `finalizeUnwrap`

The [`finalizeUnwrap`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L143) function in `Wrapper.sol` is responsible for completing the unwrapping process. This involves decrypting the amount to be unwrapped, transferring the underlying asset (either ETH or an ERC-20 token) to the user, and updating contract state.

This function does not fully adhere to the Checks-Effects-Interactions (CEI) pattern. It performs [several external calls](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L170-186) before all internal state changes are completed. Specifically, the transfer of the underlying asset (`IERC20.transfer` or a low-level `.call`) and the callback to `onUnwrapFinalizedReceived` occur before the final state updates to `nextTxId` and its associated lock. If the receiver address wanted, they could perform more actions by reentering the Wrapper or other contracts that causes events being emitted under the same transaction ID.

To mitigate this risk, consider refactoring the `finalizeUnwrap` function to strictly follow the CEI pattern. All state changes, such as updating the `nextTxId` and releasing the lock, should be completed _before_ any external calls are made.

_**Update:** Resolved in [pull request #6](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6) at commit [5de8c76](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6/diffs?commit_id=5de8c760c3f0da51455fcf86ab7f780edb1e1fdc)._

### Opaque Swap Failures

The [`SwapV0`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol) contract facilitates token swaps by interacting with an external Uniswap router. The [`onUnwrapFinalizedReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L58) function contains the logic to execute the swap and handle potential failures. When a swap call to the Uniswap router fails, the `try/catch` block correctly catches the error and executes recovery logic in the [`_handleUniswapFailure`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L108) function. This recovery logic wraps the tokens back to the user. However, the reason for the original swap failure is caught but never logged or emitted. This makes it difficult for users and off-chain monitoring tools to diagnose and understand why a swap failed.

To improve observability and user experience, consider enhancing the error-handling mechanism. An event should be emitted within the `catch` block that includes details about the failed swap, such as the error reason string or data returned by the failing call. This would provide valuable debugging information for users and developers.

_**Update:** Resolved in [pull request #11](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/11) at commit [d44005b](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/11/diffs?commit_id=d44005b21eebef3361ffbaa3eeabb00138dc6683)._

### Missing Ownership Checks on Encrypted Arguments

The system's contracts frequently interact with encrypted values of type `euint64`. Several external and public functions across the codebase accept these encrypted values as parameters to perform operations such as calculating fees, burning tokens, or processing confidential transfers. The FHE library provides mechanisms to enforce access control on who can use specific encrypted values.

Multiple functions that receive encrypted `euint64` arguments do not perform the necessary ownership checks to ensure the caller is authorized to use the provided encrypted value. This omission centralizes security assumptions in the calling contracts and removes a critical defense-in-depth validation layer. The following functions are affected:

*   [`FeeManager.getUnwrapFee`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol#L68)
*   [`RegulatedERC7984Upgradeable.burn`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L180)
*   [`SwapV0.onConfidentialTransferReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L26)
*   [`Wrapper.onConfidentialTransferReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L64)

Consider adding an explicit ownership check at the beginning of each affected function to validate that the caller has permission to use the encrypted arguments. This can be accomplished by using a `require` statement with `FHE.isSenderAllowed(amount)`. This ensures that each contract correctly enforces access control over the encrypted data it receives.

_**Update:** Resolved in [pull request #32](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/32) at commit [10d5997](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/32/diffs?commit_id=10d599717215de8170fc250ccd71cdfba6ca0f29)._

### Incorrect Fee Refund in `finalizeUnwrap`

The [`Wrapper` contract](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol) manages the unwrapping of confidential tokens. The process begins in the [`onConfidentialTransferReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L64) function, which requests the asynchronous decryption of several values, including the `expectedFee` and the `actualFee` transferred to the fee recipient. The `finalizeUnwrap` function later receives these decrypted values to either complete the unwrap operation by sending the underlying assets to the user or, if a discrepancy is found, to refund the amounts.

An inconsistency exists in the order of fee-related values between the [encoding](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L95) and [decoding](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L153) steps. In [`onConfidentialTransferReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L64), the [`actualFee`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L92) is placed into the [`cts`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L93) array for decryption before the [`expectedFee`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L60). However, the [`finalizeUnwrap`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L143) function decodes these values into local variables in the reverse order, assigning the decrypted `actualFee` to `expectedFeeAmount` and the `expectedFee` to `actualFeeAmount`. This variable swap causes incorrect behavior in the refund path. This issue requires an unlikely event: forwarding the fee to the recipient silently failed and caused `actualFee` to be zero. In this scenario, where `actualFee != expectedFee`, the refund logic incorrectly uses `actualFeeAmount` (which holds the original `expectedFee`) for the refund transfer, causing the fee recipient to refund an amount greater than what it actually received.

Consider aligning the serialization and deserialization order of the fee amounts. This can be achieved by either correcting the order of the local variable assignments in the `finalizeUnwrap` function to match the encoding order from `onConfidentialTransferReceived`, or by modifying the encoding order in `onConfidentialTransferReceived` to match the existing decoding logic in `finalizeUnwrap`.

_**Update:** Resolved in [pull request #6](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6) at commit [5de8c76](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6/diffs?commit_id=5de8c760c3f0da51455fcf86ab7f780edb1e1fdc)._

### Insufficient Validation in `SwapV0` Contract

The [`SwapV0`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol) contract is designed to facilitate swaps between different confidential tokens. The process begins with a two-step operation to unwrap the source confidential token into its underlying asset. During the second step, a callback to the [`onUnwrapFinalizedReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L58) function executes a trade on an external decentralized exchange, converting the source underlying asset into the target underlying asset. Finally, the contract [interacts](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L103) with the target asset's `Wrapper` to wrap the newly acquired tokens, delivering the destination confidential token to the end user.

The contract exhibits two distinct vulnerabilities related to insufficient input and sender validation, which can lead to frozen funds or theft of residual assets.

*   **Mismatched Swap Path**: The [`onConfidentialTransferReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L58) function decodes the swap `path` from user-provided data but fails to verify that the input token of the path (`path[0]`) matches the underlying asset of the confidential token (`msg.sender`) initiating the swap. A user can thus initiate a swap with one confidential token while providing a path that starts with a different, unrelated token. This causes the contract to successfully unwrap the correct underlying asset but later fail when attempting to trade the incorrect one on the DEX. This reverts the entire second phase of the transaction and permanently locks the user's funds in the `Wrapper`.
*   **Unregistered Wrappers:** The contract does not verify that the input and output tokens in a swap path have corresponding wrapper contracts registered in the [`DeploymentCoordinator`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L16). If a swap is initiated where the output token's wrapper is not registered, the final `wrap` call will fail. This failure reverts the entire second phase of the unwrap transaction, leaving the user's underlying tokens held within the input `Wrapper` contract while their original confidential tokens remain burned, thus freezing the assets indefinitely until the coordinator is updated.
*   **Unauthenticated Callback:** The external [`onUnwrapFinalizedReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L58) function does not validate that the caller (`msg.sender`) is a legitimate `Wrapper` contract. An attacker can call this function directly, supplying a malicious router address and a path corresponding to any residual "dust" tokens held by the `SwapV0` contract. The contract will then approve the attacker's malicious router to spend these tokens, allowing the attacker to transfer them out.

To address these issues, consider implementing the following validation checks:

*   In the `onConfidentialTransferReceived` function, add a check to ensure the input token of the swap path matches the underlying asset of the confidential token that initiated the call. This can be done by adding a requirement that `path[0]` is equal to `cToken.underlying()`.
*   In the [`onConfidentialTransferReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L58) function, add a pre-emptive check to query the [`DeploymentCoordinator`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L16) and ensure that both the first and last tokens in the swap `path` have valid, non-zero wrapper addresses registered. This will prevent swaps from starting if they are destined to fail, thereby avoiding the asset freeze scenario.
*   In the [`onUnwrapFinalizedReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L58) function, add a requirement to validate that `msg.sender` is the official wrapper contract for the input token (`path[0]`). This can be achieved by fetching the expected wrapper address from the `DeploymentCoordinator` and comparing it against the caller's address.

_**Update:** Resolved in [pull request #12](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/12) at commit [c46a137](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/12/diffs?commit_id=c46a137cad6fb0115757f400dfbede9e24f008c9)._

### Direct Calls to `name` and `symbol` May Fail for Non-Standard ERC-20 Tokens

The [`DeploymentCoordinator`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L16) contract includes a [`deploy`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L66) function that orchestrates the creation of a new wrapper and confidential token pair for an underlying ERC-20 asset. During this process, the function retrieves the `name` and `symbol` of the underlying token to programmatically generate a name and symbol for the new confidential token.

The contract currently assumes that the underlying token conforms to the standard `IERC20Metadata` interface, where the [`name()`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L84) and [`symbol()`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L85) functions return a `string`. This assumption fails for some non-standard ERC-20 tokens, like MKR, which implement these functions to return a `bytes32` value instead. Attempting to deploy a wrapper for such a token will cause the external call to revert, which in turn causes the entire deployment to fail. This effectively prevents the system from supporting these non-standard tokens.

To ensure broader compatibility with different ERC-20 token implementations, consider replacing the direct external calls with internal helper functions that can gracefully handle both `string` and `bytes32` return types. Similar to the existing `_tryGetAssetDecimals` function, these new helpers for `name` and `symbol` could use a `try/catch` block. The `try` block would attempt to decode a `string` return value, while the `catch` block would have to handle the fallback case.

_**Update:** Resolved in [pull request #31](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/31) at commit [4bd3c29](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/31/diffs?commit_id=4bd3c29e62dbd417e258a6d71784831f57efb603)._

### Ambiguous Success Flag in Unwrap Operation

The unwrap process is initiated via a `confidentialTransferAndCall` invocation to the `Wrapper` contract. A key characteristic of the underlying confidential token is that a transfer from an account with an insufficient balance does not revert but instead proceeds with an encrypted amount of zero.

The [`onConfidentialTransferReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L64) function does not currently account for this zero-amount case when determining the outcome of the operation. If the function receives an encrypted zero, the [`success`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L84) flag is still evaluated as `true` because this flag only reflects whether subtracting the fee resulted in an underflow (which it does not for a zero amount). This ambiguous `true` value is then carried through the entire two-step process, causing the final `UnwrappedFinalized` event to incorrectly report a successful operation for what was effectively a non-operation, masking the initial transfer failure.

To ensure that the `success` flag accurately reflects the outcome, consider modifying its calculation in the `onConfidentialTransferReceived` function. The flag should be the result of a logical AND operation between the existing underflow check and an additional FHE comparison to verify the incoming `amount` is not zero. This would ensure that the `success` flag is only true for valid, non-zero unwraps, leading to more accurate event reporting. It should be noted that this change introduces a gas-intensive FHE operation, so the team should weigh the benefit of more accurate reporting against the increased transaction cost for every unwrap.

_**Update:** Resolved in [pull request #6](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6) at commit [5de8c76](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6/diffs?commit_id=5de8c760c3f0da51455fcf86ab7f780edb1e1fdc)._

### Floating Pragma

Pragma directives should be fixed to clearly identify the Solidity version with which the contracts will be compiled.

Throughout the codebase, multiple instances of floating pragma directives were identified. The [`ERC7984TransferBatcher.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol) contract uses the `solidity >=0.8.7 <0.9.0` directive while the rest of the contracts use `solidity ^0.8.27`.

Consider using fixed pragma directives.

_**Update:** Resolved in [pull request #13](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/13) at commit [4373257](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/13/diffs?commit_id=4373257261578fb45c8403886a1af41226135ec0)._

### `RetryTransfer` Events Can Be Blocked by Cross-Token ID Collisions

[`ERC7984TransferBatcher`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol) stores the sender of each confidential transfer in [`txIdToSender`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L19), keyed only by the numeric transaction ID emitted by [`RegulatedERC7984Upgradeable`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol). Since every confidential token instance starts its counter with 1, two tokens can produce identical IDs and can be used with the same batcher.

When token B writes an entry for an ID that token A previously used, the original sender recorded for token A is overwritten. If that sender later submits a batch specifying `retryFor` equal to the overwritten ID, the guard throws the [`OnlyOriginalSenderCanRetry`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L12) error, causing the transaction to revert. Operationally, the first sender loses the ability to emit the `RetryTransfer` event for that ID. No token transfers are executed or hijacked.

Consider namespacing the mapping by token address (e.g., as `mapping(address => mapping(uint256 => address))`), and applying the same indexing in both the write path and the guard to prevent cross-token collisions.

_**Update:** Resolved in [pull request #16](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/16) at commit [3f6a2f6](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/16/diffs?commit_id=3f6a2f6bc21d48ccf6e43216b99990830242411f)._

### Empty Batches Emit Invalid `BatchTransfer` Ranges

The [`confidentialBatchTransfer`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L32) function of [`ERC7984TransferBatcher`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol) records `cToken.nextTxId()` as the `startTxId` before iterating over the transfer array and computes `cToken.nextTxId() - 1` as `endTxId` after the loop. The function emits both values in the `BatchTransfer` event.

When the [`transfers`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L51) array is empty, the loop is skipped such that `cToken.nextTxId()` remains unchanged. Hence, subtracting one yields `endTxId = startTxId - 1`, so the event advertises a range where the ending transaction ID is smaller than the starting ID. Off-chain consumers that rely on the event for bookkeeping read an interval of negative length, leading to incorrect accounting or analytics.

Consider reverting when the transfer array is empty, or alternatively emit `startTxId` as both bounds so that the announced interval remains well-formed.

_**Update:** Resolved in [pull request #17](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/17) at commit [44f7844](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/17/diffs?commit_id=44f7844bdb08d6305c40489e21071e9aa733df01)._

### Missing Bounds Check on Rate Parameter

The [`RegulatedERC7984Upgradeable`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol) contract is initialized with a [`rate_`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L110) parameter that defines the conversion factor between the confidential token's units and its underlying asset's units. This rate is used in the [`Wrapper`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L110) contract to calculate the corresponding amounts when wrapping underlying tokens into confidential tokens and unwrapping them back. The [`initialize`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L92) function does not validate the `rate_` parameter against any bounds. A `rate_` of zero can be provided during initialization, which renders the token's conversion logic invalid and can lead to reverts in downstream operations that rely on it. Conversely, an excessively large `rate_` can cause a multiplication overflow revert in the [`Wrapper`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol) contract's [`finalizeUnwrap`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L143) function when calculating the [`underlyingAmount`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L168) to be paid out.

Consider introducing both a lower and an upper bound check for the `rate_` parameter within the `initialize` function. The rate should be required to be non-zero. In addition, an upper bound, such as `10**57`, can provide a sanity check to prevent a definitive overflow issue.

_**Update:** Resolved in [pull request #14](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/14) at commit [d242b7d](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/14/diffs?commit_id=d242b7da1f0c84f16091574e38aea26249d05bba)._

### Excessive Unwrap Fee Locks User Balances

The [`onConfidentialTransferReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L64) callback of the [`Wrapper`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol) contract is invoked after the user transfers an encrypted amount to the wrapper. It calls [`_getFeeAndBurnAmounts`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L56) to split the `amount` into burn and fee components. In the event where the calculated fee should exceed the incoming amount, this helper returns `false` as a `success` flag and the burn and fee amounts being zero. Thus, no burn or fee transfer takes place, while the wrapper keeps the users confidential tokens.

In the second unwrap step, [`finalizeUnwrap`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L143) decodes passed cleartext and sees `success` being `false`. The function emits [`UnwrappedFinalized`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L196) and exits without minting or transferring the captured balance back to the original sender. Since the confidential tokens remain under the wrapper’s control, the user cannot reclaim them and the deposit is permanently locked.

Consider adding explicit reimbursement logic for the failure case, such as minting or transferring the original amount back, so that every unwrap request either completes successfully or restores the user’s balance.

_**Update:** Resolved in [pull request #6](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6) at commit [5de8c76](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6/diffs?commit_id=5de8c760c3f0da51455fcf86ab7f780edb1e1fdc)._

### Default Admin Role Overloaded with Operational Privileges

The [`FeeManager`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol) exposes [setter functions](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol#L91-127) that are gated by `DEFAULT_ADMIN_ROLE`. In the current configuration, the same role responsible for assigning privileges to other accounts is also empowered to mutate operational parameters, such as fee rates and recipients. Combining governance and operational responsibilities increases the blast radius: any compromise or misuse of the default admin immediately translates into arbitrary fee manipulation. Industry practice isolates administrative delegation from day-to-day configuration so that role management and business actions can be monitored, audited, and controlled independently.

Consider introducing a dedicated role (e.g., `FEE_MANAGER_ROLE`) for mutating fee parameters, leaving `DEFAULT_ADMIN_ROLE` solely responsible for granting and revoking roles.

_**Update:** Resolved in [pull request #18](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/18) at commit [d69be06](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/18/diffs?commit_id=d69be06398f4bfdb6c5188ff0d0477916ed41eb7)._

### Deploy-Fee Check Allows Accidental Overpayment

[`DeploymentCoordinator.deploy`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L66) retrieves the deploy fee from `FeeManager` and enforces [`msg.value`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L73) to be greater than or equal to the required fee before proceeding. Any excess value supplied by the caller is forwarded to the fee recipient without refund, so overpaying (e.g., due to UI rounding, front-end bugs, or user error) silently transfers additional ETH.

While the fee call itself is trusted, callers have no recourse to recover the surplus once the transaction completes. Aligning the check with the expected amount avoids this footgun. Consider requiring `msg.value == requiredFee`, or alternatively refunding the excess before forwarding the payment, so that callers cannot overpay inadvertently.

_**Update:** Resolved in [pull request #15](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/15) at commit [76e6172](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/15/diffs?commit_id=76e617266606fc331de29dc5495e96a73618da83)._

Notes & Additional Information
------------------------------

### Gas Optimizations

During the review, multiple opportunities for gas optimization were identified. While these do not impact the core logic of the contracts, implementing them can lead to reductions in both deployment and runtime transaction costs:

*   In the [`RegulatedERC7984UpgradeableFactory`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/RegulatedERC7984UpgradeableFactory.sol), a new implementation of the [`RegulatedERC7984Upgradeable`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/contracts/token/RegulatedERC7984Upgradeable.sol?ref_type=heads#L53) contract is deployed on every execution of `deployConfidentialToken`. This is extremely gas-intensive. A single canonical implementation should be deployed, and its address should be stored in the `DeploymentCoordinator` to be used for all subsequent proxy deployments.
*   In the [`RegulatedERC7984UpgradeableFactory`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/RegulatedERC7984UpgradeableFactory.sol), `name_` and `symbol_` are passed as `memory` in the [`deployConfidentialToken`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/contracts/factory/RegulatedERC7984UpgradeableFactory.sol?ref_type=heads#L22) function, meaning a copy to memory while a second copy is made for the call encoding. With `calldata` location one copy can be saved.
*   Within the [`FeeManager.getUnwrapFee`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/main/contracts/admin/FeeManager.sol?ref_type=heads#L68) function, the public [`unwrapFeeBasisPoints`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/contracts/admin/FeeManager.sol?ref_type=heads#L74) variable is converted to an encrypted `euint64` on every call. This unnecessary encryption can be avoided by using the FHE library's more gas-efficient scalar-based arithmetic functions, such as `FHE.mul(euint, uint)`.
*   In the [`RegulatedERC7984Upgradeable`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol) contract's [`_update`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L231) function, the result of the `regulator()` external call is used multiple times. Caching this value in a local stack variable at the beginning of the function would avoid repeated `SLOAD` and external call operations. Similarly, each `_checkSanctions` on the `from` and `to` address involves an external call to fetch the `sanctionsList`. This can be fetched once for both.
*   The storage layout in [`RegulatedERC7984Upgradeable`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol) can be improved. The `uint8 _decimals`, `bool _isNextTxIdLocked`, and `address _underlying` variables can be reordered to be packed into a single storage slot, saving `SSTORE` costs during contract initialization. Note that this change cannot be applied to an already-deployed contract via an upgrade.

Consider addressing the gas improvement opportunities outlined above to reduce overall deployment and transaction costs.

_**Update:** Resolved in [pull request #20](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/20) at commit [6a80582](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/20/diffs?commit_id=6a80582da2b424e6b534b55e8e6e31c468767da3)._

### Overly Permissive FHE Allowances Result in Unnecessary Gas Costs

During an unwrap operation, the [`Wrapper`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol) contract calls the [`FeeManager.getUnwrapFee`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L212) function to calculate the appropriate fee. This involves a two-way communication of encrypted values: the `Wrapper` passes the encrypted `amount` to the `FeeManager`, and the [`FeeManager`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol) calculates and returns an encrypted `fee` to the `Wrapper`. The FHEVM's Access Control List (ACL) system is used to grant the necessary permissions for this cross-contract interaction.

In both stages of this process, the contracts use `FHE.allow` to grant permissions. First, the `Wrapper` grants a persistent allowance to the `FeeManager` for the `amount`, and second, the `FeeManager` grants a persistent allowance back to the `Wrapper` for the resulting `fee`. However, in both instances, the permission is only required for the duration of the single transaction. Using `FHE.allow` creates a long-lasting permission in storage, which is inefficient for a value that is only needed transiently. This results in unnecessary storage writes and higher gas costs for every unwrap transaction.

To optimize gas consumption and correctly scope the permissions, consider replacing the `FHE.allow` calls with `FHE.allowTransient` in both contracts. The `FHE.allow` call in the `Wrapper` contract's [`_getUnwrapFee`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L214) function, as well as the corresponding calls in the `FeeManager` contract's [`getUnwrapFee`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol#L68) function, should be updated. This will ensure that permissions are granted only for the duration of the transaction, avoiding needless storage writes and reducing the overall gas cost of the unwrap process.

_**Update:** Resolved in [pull request #6](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6) at commit [5de8c76](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6/diffs?commit_id=5de8c760c3f0da51455fcf86ab7f780edb1e1fdc)._

### Inconsistent and Inaccurate ERC-7201 Namespace Identifiers

The project's upgradeable contracts, [`ERC7984Upgradeable`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol#L31) and [`RegulatedERC7984Upgradeable`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L67), use the [ERC-7201 standard](https://eips.ethereum.org/EIPS/eip-7201) to define persistent storage layouts and prevent storage slot collisions. This standard relies on a unique, well-defined namespace identifier for each contract's storage struct, which is hashed to determine the storage slot.

An analysis of the contracts revealed two related issues regarding the implementation of this standard:

*   **Incorrect Formula:** The `@custom:storage-location` NatSpec comments in both contracts incorrectly reference a non-existent `erc7984` formula. A correct formula for the standard being used is `erc7201`.
*   **Inconsistent Namespace Domains:** The domain used for the namespace ID is inconsistent across the inheritance chain. The `ERC7984Upgradeable` contract uses the `pyratzlabs` domain, while its child contract, `RegulatedERC7984Upgradeable`, uses the `zaiffer` domain, which can create confusion.

To improve code clarity, maintainability, and adherence to the standard, consider making the following corrections. First, update the `@custom:storage-location` comments in both `ERC7984Upgradeable.sol` and `RegulatedERC7984Upgradeable.sol` to reference the correct `erc7201` formula. Second, establish a single, consistent domain namespace for the entire project and apply it to the storage location identifiers in all relevant contracts.

_**Update:** Resolved in [pull request #21](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/21) at commit [bcf3418](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/21/diffs?commit_id=bcf34189d57d07dc806720802d839cb979faf0da)._

### Gas-Intensive Fee Mechanism Using Confidential Tokens

The current design of the [`Wrapper`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol) contract mandates that all fees for both [wrapping](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L127) and [unwrapping](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L92) are processed using the confidential token. During a wrap operation, a portion of the value is minted as a separate amount of confidential fee tokens. During an unwrap operation, the fee is calculated using encrypted arithmetic, and the resulting encrypted fee amount is moved via a `confidentialTransfer`.

While this approach keeps all value calculations within the confidential domain, it is highly inefficient in terms of gas consumption. Operations involving encrypted values are substantially more expensive than their standard ERC-20 or ETH counterparts. By handling fees exclusively with confidential tokens, the system imposes significant gas overhead on every wrap and unwrap transaction where a fee is applicable.

To significantly reduce transaction costs for users, consider re-architecting the fee mechanism to operate on the underlying, non-confidential asset. For wrapping, the fee could be collected directly from the underlying tokens before the remaining amount is converted into confidential tokens. For unwrapping, the full confidential amount could be converted to the underlying asset first, after which the fee could be calculated and transferred in the clear. This change would replace expensive FHE operations with standard, cheaper token transfers, leading to considerable gas savings.

_**Update:** Resolved in [pull request #6](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6) at commit [5de8c76](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/6/diffs?commit_id=5de8c760c3f0da51455fcf86ab7f780edb1e1fdc)._

### Stateful Disclosure Mechanism Diverges from Latest Reference Implementation

The [`ERC7984Upgradeable`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol) contract provides a two-step process for revealing encrypted values, consisting of the [`discloseEncryptedAmount`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol#L240) and [`finalizeDiscloseEncryptedAmount`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol#L254) functions. This mechanism allows a user to request the decryption of an encrypted amount, which is then finalized in a subsequent transaction, emitting an [`AmountDisclosed`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol#L266) event with the cleartext value.

The contract's current implementation of this process is stateful, using a `_requestHandles` mapping to link each `finalize` call to a unique, prior disclose request. This design provides a strong on-chain guarantee that an `AmountDisclosed` event can only be emitted for a value this contract explicitly requested to disclose, and it prevents replays of the finalization step. This implementation, while robust, diverges from the more recent, stateless version in the [OpenZeppelin reference library](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/blob/v0.3.0-rc.0/contracts/token/ERC7984/ERC7984.sol#L198-L228), which omits this stateful check in favor of lower gas costs.

Consider reviewing the trade-offs between the current stateful implementation and the stateless model in the reference library. The current design provides stronger on-chain integrity guarantees against unsolicited or replayed events. However, if minimizing transaction costs is a primary objective, aligning with the more gas-efficient stateless model could be beneficial. The team should evaluate which approach best fits the project's specific security posture and performance requirements.

_**Update:** Acknowledged._

### Code Quality and Improvement Opportunities

The review identified several areas where the codebase could be improved in terms of code quality, clarity, consistency, and adherence to best practices. Addressing these points would enhance the long-term maintainability and robustness of the contracts:

*   **Disable Initializers:** Initializable contracts should call `_disableInitializers()` within their constructor. This is a measure for upgradeable contracts that prevents the implementation contract from being initialized.
*   **Use `AccessControlDefaultAdminRules`:** Contracts inheriting `AccessControl` could use the `AccessControlDefaultAdminRules` extension. This would enforce a more robust admin management policy, including a mandatory two-step ownership transfer and an optional time delay, enhancing security.
*   **Unused `Ownable2Step` Inheritance:** The [`Wrapper`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol) contract inherits from `Ownable2Step` but does not use any of the ownership features. Consider removing this as an inherited contract.
*   **Use Specific Internal Helpers:** The public [`mint`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L198) and [`burn`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L180) functions in [`RegulatedERC7984Upgradeable`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol) call the generic [`_update`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L231) function directly. For improved code clarity and abstraction, they should instead use the more specific [`_mint`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol#L277) and [`_burn`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol#L282) internal functions provided by the parent [`ERC7984Upgradeable`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol) contract.
*   **Use Getter for State Variables:** The [`mint`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L198), [`burn`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L180), and [`_update`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L231) functions in [`RegulatedERC7984Upgradeable`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol) access the `_nextTxId` storage variable directly. They should instead use the public `nextTxId()` getter function for more consistent and encapsulated access to state.
*   **Unused Return Value:** The internal [`_incrementNextTxId`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L119) function in [`RegulatedERC7984Upgradeable`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol) is defined to return a `uint256`, but this return value is not used where the function is called. The function signature should be updated to not return a value.
*   **Inconsistent Grantee in `allowTransient` Calls:** In the [`onConfidentialTransferReceived`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L64) function of the `Wrapper` contract, permissions are granted using `FHE.allowTransient` to both `address(confidentialToken)` and `msg.sender`. Since the function logic ensures these two addresses are identical, using both identifiers for the same entity is inconsistent and may confuse readers. For clarity, a single identifier, preferably `msg.sender`, should be used for all such calls within the function.
*   **Custom Errors:** In [`ERC7984TransferBatcher.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol), an unsuccessful fee transfer reverts with the ["Fee transfer failed"](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L46) revert string. Consider replacing it with a custom error.
*   **Missing License:** The [`ERC7984TransferBatcher.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol) file is lacking an SPDX license identifier. Consider defining one.
*   **Call Encoding:** In [`RegulatedERC7984UpgradeableFactory.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/RegulatedERC7984UpgradeableFactory.sol), the `initialize` call encoding is done with [`abi.encodeWithSelector`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/RegulatedERC7984UpgradeableFactory.sol#L33), which is error-prone. Consider doing the encoding with `abi.encodeCall` instead.
*   **Visibility:** Within `swap_v0.sol`, the [`coordinator` state variable](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L18) lacks an explicitly declared visibility. Consider marking it as `public` explicitly.
*   **Unnecessary Casts:** In [`AdminProvider.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/AdminProvider.sol) the [`address`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/AdminProvider.sol#L55) casts on the regulator address are extra as well as the [`FeeManager`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L36) cast in [`ERC7984TransferBatcher.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol) on the `adminProvider.feeManager` call. Consider removing them.
*   **Naming Inconsistency:** The [`RegulatedERC7984Storage`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L67) struct defines various state variables with a leading underscore. Consider renaming [`adminProvider`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L70) with a leading underscore for consistency.

Consider implementing the above-listed suggestions to improve the overall quality, clarity, and maintainability of the codebase.

_**Update:** Resolved in [pull request #22](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/22) at commit [28907fb](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/22/diffs?commit_id=28907fb1ea787bac99db0ed34dca1be517e5d7fc) and [pull request #23](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/23) at commit [cce9a4b](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/23/diffs?commit_id=cce9a4b7fa18d836ea8ef6c4342723cebdda1ac2)._

### Documentation Gaps

Throughout the codebase, multiple instances of code with missing documentation were identified:

*   [`Wrapper.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol): Public and callback functions lack NatSpec describing the sequence (confidential transferAndCall, wrapper callbacks, relayer finalize) and omit parameter/return documentation, leaving the wrapping workflow opaque to integrators.
*   [`AdminProvider.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/AdminProvider.sol): File exposes core mutators with no NatSpec and readers get no documentation on ownership expectations or side effects.
*   [`FeeManager.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol): Entire fee configuration surface lacks documentation, so callers and reviewers cannot see expected ranges or behavior.
*   [`ERC7984TransferBatcher.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol): Contract and entry points are undocumented despite coordinating confidential transfers, leaving call semantics unclear.
*   [`swap_v0.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol): Swap workflow has no descriptive comments, making callback flows and expected data formats opaque.
*   [`RegulatedERC7984Upgradeable.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol): Docstring references [“EIP20”](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L62) compatibility while ERC‑20 is probably meant.

Furthermore, two instances of incomplete docstrings were identified:

*   In [`RegulatedERC7984UpgradeableFactory.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol), the [`deployConfidentialToken`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/RegulatedERC7984UpgradeableFactory.sol#L22) function does not document the [`underlying_`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/RegulatedERC7984UpgradeableFactory.sol#L27) parameter.
*   In [`ERC7984Upgradeable.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol), the [`finalizeDiscloseEncryptedAmount`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol#L254) function does not document the `requestId`, `cleartexts`, `decryptionProof` parameters.

Lastly, the following comment appears to be incorrect:

*   The [`DeploymentCoordinator`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol) `@dev` comment states "Maintains the same interface as the original WrapperFactory while using split architecture", yet the contract exposes `deploy(address)` that returns both `Wrapper` and `RegulatedERC7984Upgradeable`. The `WrapperFactory` only offers `deployWrapper()` returning a `Wrapper`. Because the signatures and return types differ, the statement is inaccurate and should be updated or removed.

Consider thoroughly documenting the majority of the codebase following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in [pull request #24](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/24) at commit [7fd6f85](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/24/diffs?commit_id=7fd6f8551cb2b1cc2a0ce827ab989cddd0667229)._

### Lack of Indexed Event Parameters

Throughout the codebase, multiple instances of events not having any indexed parameters were identified:

*   The [`BatchTransfer` event](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L15) of [`ERC7984TransferBatcher.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol)
*   The [`RetryTransfer` event](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L16) of [`ERC7984TransferBatcher.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol)
*   The [`Wrapped` event](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L42) of [`Wrapper.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol)

To improve the ability of off-chain services to search and filter for specific events, consider indexing event parameters.

_**Update:** Resolved in [pull request #25](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/25) at commit [7eb4c9c](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/25/diffs?commit_id=7eb4c9c72f5d83a0fdd958967eb77406d17f2ce0)._

### Missing Security Contact

Including a dedicated security contact (e.g., an email address or ENS name) in a smart contract streamlines vulnerability reporting. It lets code owners define the disclosure channel, reducing misrouting and missed reports. It also helps when third-party libraries are involved: if an issue originates upstream, maintainers know exactly whom to contact with details and mitigation guidance.

Throughout the codebase, none of the contracts and interfaces have a security contact defined in their documentation. Thus, consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in [pull request #26](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/26) at commit [e54abcb](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/26/diffs?commit_id=e54abcb2225652d8ff6d872552194e564ebf7d81)._

### Missing Named Parameters in Mappings

Since [Solidity 0.8.18](https://github.com/ethereum/solidity/releases/tag/v0.8.18), mappings can include named parameters to provide more clarity about their purpose. Named parameters allow mappings to be declared in the form `mapping(KeyType KeyName? => ValueType ValueName?)`. This feature enhances code readability and maintainability.

Throughout the codebase, multiple instances of mappings without named parameters were identified:

*   The [`txIdToSender` state variable](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L19) in the [`ERC7984TransferBatcher`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L19) contract.
*   The [`deployedWrappers` state variable](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L22) in the [`DeploymentCoordinator`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol) contract.
*   The [`deployedConfidentialTokens` state variable](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L25) in the [`DeploymentCoordinator`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol) contract.
*   The [`_operators`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol#L271) state variable in the [`ERC7984Upgradeable`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol) contract could have the `uint48` value named to clarify it as a timestamp.

Consider adding named parameters to mappings in order to improve the readability and maintainability of the codebase.

_**Update:** Resolved in [pull request #27](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/27) at commit [f5d3bdb](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/27/diffs?commit_id=f5d3bdbd922e9e1458a87c6d1685c76eae4002ce)._

### Unused Code

Throughout the codebase, multiple instances of unused code were identified:

*   In `ERC7984Upgradeable.sol`, the [`ERC7984UnauthorizedCaller` error](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/ERC7984Upgradeable.sol#L61) is unused.
*   In `RegulatedERC7984Upgradeable.sol`, the [`TransferFeeInfo` event](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L77) is unused.
*   In `RegulatedERC7984Upgradeable.sol`, the [`FeeManager` import](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L12) can be removed.
*   In `RegulatedERC7984Upgradeable.sol`, the [`_PLACEHOLDER` state variable](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L63) is unused.
*   In `RegulatedERC7984Upgradeable.sol`, the [`FHESenderNotAllowed`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L18), [`IncorrectETHFeeAmount`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L28), and [`ETHTransferFailed`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L33) errors are unused.
*   In `RegulatedERC7984Upgradeable.sol`, the [`Transfer`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L50) event and therefore [`IConfidentialERC20`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/token/RegulatedERC7984Upgradeable.sol#L40) interface are not used.
*   In `FeeManager.sol`, the [`TransferFeeUpdated`](https://gitlab.com/9pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/admin/FeeManager.sol#L23) event is unused.
*   In `Wrapper.sol`, the [`console.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L5) import can be removed.

To improve the overall clarity and readability of the codebase, consider removing any unused code.

_**Update:** Resolved in [pull request #28](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/28) at commit [f9400b1](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/28/diffs?commit_id=f9400b1e214e3119d13cd282a4606fe224b99d8a)._

### Outbound Fee Transfer Precedes Batch Execution

The [`confidentialBatchTransfer`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L32) function in [`ERC7984TransferBatcher`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol) forwards `msg.value` to the fee recipient before iterating over the transfer array. No explicit state change occurs prior to the call, yet the pattern proceeds with the external interaction ahead of the loop that performs the core batch operation.

Although the fee recipient is trusted and the call can revert on failure, the ordering diverges from the common checks-effects-interactions convention and mildly expands the surface for unexpected behavior if the recipient re-enters or exhausts gas. Postponing the ETH transfer would keep the external interaction as the final step once the batch has succeeded.

Consider relocating the [`feeRecipient.call`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L45) to the end of the function so that the outbound transfer only happens after all confidential transfers have completed.

_**Update:** Resolved in [pull request #29](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/29) at commit [5e9edd9](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/29/diffs?commit_id=5e9edd9ac788f7cc8bb74f7932cfd10190cac099)._

### Function Visibility Overly Permissive

Throughout the codebase, multiple instances of functions having overly permissive visibility were identified:

*   The [`confidentialBatchTransfer`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol#L32) function in [`ERC7984TransferBatcher.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/batcher/ERC7984TransferBatcher.sol) with `public` visibility could be limited to `external`.
*   If [`DeploymentCoordinator.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol) is not meant to be inherited, the [`_getDeployFee`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L167), [`_getFeeRecipient`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L173), [`fallbackUnderlyingDecimals`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L178) and [`_maxDecimals`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/factory/DeploymentCoordinator.sol#L182) functions with `internal` visibility could be limited to `private` while dropping `virtual`.
*   Similarly in [`swap_v0.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol), the [`_handleUniswapSuccess`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L94) and [`_handleUniswapFailure`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/swap/swap_v0.sol#L108) function with `internal` visibility could be limited to `private`.
*   In [`Wrapper.sol`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol), the [`_getFeeAndBurnAmounts`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L56), [`_getWrapFee`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L207), [`_getUnwrapFee`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L212), and [`_getFeeRecipient`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L218) function with `internal` visibility could be limited to `private`. The [`wrap`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L112) and [`finalizeUnwrap`](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/blob/f5081087f9bc31564b0d401b4da697a6631cd7dc/contracts/wrapper/Wrapper.sol#L143) function with `public` visibility could be limited to `external`.

To better convey the intended use of functions and to potentially realize some additional gas savings, consider changing a function's visibility to be only as permissive as required.

_**Update:** Resolved in [pull request #30](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/30/diffs?commit_id=af8aef2bdf0a2d7ae5bd8ae83e305932b51cb378) at commit [af8aef2](https://gitlab.com/pyratzlabs/software/usdx/smart-contracts/-/merge_requests/30/diffs?commit_id=af8aef2bdf0a2d7ae5bd8ae83e305932b51cb378)._

Conclusion
----------

The audited smart contracts introduce a comprehensive system for creating, managing, and interacting with confidential tokens (ERC-7984) using Zama FHEVM. The system includes factories for deploying token pairs, a wrapper for handling underlying assets, and batching capabilities for efficient transfers.

The audit identified several critical- and high-severity issues that require immediate attention. These include a critical vulnerability in the `finalizeUnwrap` function that allows for replayed transactions, leading to a systematic draining of the contract's backing assets.

Moreover, several high-severity issues threaten the system's integrity, such as the minting of undercollateralized tokens due to improper handling of fee-on-transfer tokens and missing return value checks on ERC-20 transfers. Further risks of permanent fund loss for users were identified in scenarios involving failed unwrapping processes and incorrect refund logic for fees.

The codebase was found to be well-structured with a clear separation of concerns, making it generally easy to follow. However, the system could be improved by enforcing more consistent input validation, optimizing for gas efficiency, and standardizing error handling. Furthermore, the test suite should be significantly extended to cover more edge cases, especially regarding failure and recovery scenarios, before the system is deployed to production.

For future iterations, the team could draw further inspiration from the latest [OpenZeppelin Confidential Contracts](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/blob/v0.3.0-rc.0/) library, which might lead to revisiting certain design choices like the separate Wrapper and Token architecture. Given the complexity of the system and the nature of the recommended changes, it is strongly advised that another audit be conducted if major architectural modifications are made.

The Pyratzlabs team is appreciated for their cooperation throughout this engagement and for choosing OpenZeppelin to help secure this novel project.