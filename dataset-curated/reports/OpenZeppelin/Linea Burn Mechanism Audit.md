\- November 4, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary

**Type:** DeFi  
**Timeline:** October 13, 2025 → October 15, 2025  
**Languages:** Solidity

**Findings**  
Total issues: 8 (5 resolved)  
Critical: 0 (0 resolved)  
High: 0 (0 resolved)  
Medium: 2 (2 resolved)  
Low: 1 (0 resolved)

**Notes & Additional Information**  
5 notes raised (3 resolved)

Scope
-----

OpenZeppelin audited the [Consensys/linea-monorepo](https://github.com/Consensys/linea-monorepo) repository at commit [8285efa](https://github.com/Consensys/linea-monorepo/tree/8285efababe0689aec5f0a21a28212d9d22df22e).

_**Update**: We have reviewed all the submissions and have finalized the audit report, with commit [bc7ccc6](https://github.com/Consensys/linea-monorepo/tree/bc7ccc63e8315b7c256e3b9e2cc3913315e79cbc) being the final commit reviewed. We note that commit [efe83ff](https://github.com/Consensys/linea-monorepo/commit/efe83ff992b38eda5fd5a58220acb6952c519f75) contains additional changes to the in-scope files, addressing issues that were identified in audit engagements conducted concurrently with that of OpenZeppelin while also making further design modifications, all of which were reviewed by the audit team. We also verified that the bytecode of the deployed contracts matches the corresponding bytecode found in the [`contracts/deployments/bytecode/2025-10-27`](https://github.com/Consensys/linea-monorepo/tree/efe83ff992b38eda5fd5a58220acb6952c519f75/contracts/deployments/bytecode/2025-10-27) directory at the addresses listed below:_

*   _`RollupRevenueVault` Implementation: [0x84a5ba2c12a15071660b0682b59e665dc2faaedb](https://lineascan.build/address/0x84a5ba2c12a15071660b0682b59e665dc2faaedb#code)_
*   _`V3DexSwapAdapter`: [0x30a20a3a9991c939290f4329cb52daac8e97f353](https://lineascan.build/address/0x30a20a3a9991c939290f4329cb52daac8e97f353#code)_
*   _`L1LineaTokenBurner`: [0x5Ad9369254F29b724d98F6ce98Cb7bAD729969F3](https://etherscan.io/address/0x5Ad9369254F29b724d98F6ce98Cb7bAD729969F3#code)_

In scope were the following files:

`contracts/src/operational
    ├── L1LineaTokenBurner.sol
    ├── RollupRevenueVault.sol
    ├── V3DexSwap.sol
    └── interfaces
        ├── IL1LineaToken.sol
        ├── IL1LineaTokenBurner.sol
        ├── IRollupRevenueVault.sol
        ├── ISwapRouterV3.sol
        ├── IV3DexSwap.sol
        └── IWETH9.sol` 

System Overview
---------------

The system consists of a set of operational smart contracts designed to manage key functions related to fees for the Linea network. These contracts facilitate the collection and processing of L2 protocol revenue, execution of the buy-and-burn mechanism for the native LINEA token, burning of ETH, and on-chain invoice generation. The architecture distributes duties between L1 and L2 contracts: privileged accounts on L2 manage the revenue, invoice submission, and initiation of the burn process, while a simple, permissionless contract on L1 manages the execution of the final token burning.

### `RollupRevenueVault`

This is an upgradeable L2 smart contract that acts as the central treasury for protocol-generated revenue and L2 DDoS fees. It is a stateful contract that collects ETH and orchestrates a multi-step process for its use. The contract's core functions include paying operational invoices submitted by a privileged `INVOICE_SUBMITTER_ROLE` and executing the `burnAndBridge` flow when triggered by a `BURNER_ROLE`. This flow first burns a fixed percentage of the contract's ETH balance, then swaps the remainder for LINEA tokens by interacting with a configurable external DEX, and finally bridges the acquired LINEA tokens to a corresponding burner contract on L1. A proxy for this vault is currently deployed at the following address: [`0xfd5fb23e06e46347d8724486cdb681507592e237`](https://lineascan.build/address/0xfd5fb23e06e46347d8724486cdb681507592e237). It is intended that the implementation of this proxy will be upgraded to this specific `RollupRevenueVault`.

### `L1LineaTokenBurner`

This is a simple, non-upgradeable L1 smart contract responsible for the final step of the token burn lifecycle. Its sole purpose is to receive LINEA tokens from the L2 `RollupRevenueVault` and destroy them. To do this, it receives LINEA tokens from the cross-chain bridge and exposes a permissionless `claimMessageWithProof` function that can be called by any actor. When triggered, this function burns the contract's entire balance of LINEA tokens and then calls the token contract to synchronize the new total supply with L2.

### `V3DexSwap`

This contract is a stateless L2 utility designed to act as a simple and secure wrapper for performing swaps on a Uniswap V3-style DEX. It is intended to be one possible implementation for the `dex` address configured in the `RollupRevenueVault`. It exposes a single `swap` function that accepts ETH, swaps it for LINEA tokens, and forwards the resulting tokens to the original caller. The function's interface requires the caller to specify safety parameters, such as a minimum output amount, to protect against slippage during the trade.

Security Model and Trust Assumptions
------------------------------------

The security model of the operational contracts relies heavily on a system of privileged roles and correctly configured external contract addresses. The integrity of the core revenue-burning mechanism is contingent on the honest and timely actions of these roles, the security of the external DEX, and the underlying cross-chain messaging infrastructure. The system is designed to be managed by a trusted group of operators who are responsible for its configuration and liveness.

The following trust assumptions critically underpin the system's security:

*   **Honesty of Privileged Actors:** The system assumes that all actors with privileged roles will act honestly and are not malicious. If any of these actors gets compromised, it could lead to a loss of funds or disruption of the protocol.
    
    *   The **`DEFAULT_ADMIN_ROLE`** in `RollupRevenueVault` is fully trusted to manage all other roles and to set and update critical contract addresses.
    *   The **`BURNER_ROLE`** in `RollupRevenueVault` is trusted to initiate the burn process in a timely manner and to provide secure, correct calldata for the DEX swap, including adequate slippage protection.
    *   The **`INVOICE_SUBMITTER_ROLE`** in `RollupRevenueVault` is trusted to submit accurate invoices for protocol expenses.
    *   The **Proxy Admin** of the `RollupRevenueVault` proxy contract is trusted to have full control over future upgrades and is assumed to act honestly and in the best interest of the protocol.
*   **External Dependencies:** The system's security is dependent on the correctness and security of several external contracts.
    
    *   The security of swaps depends on the `V3DexSwap` instance being configured with a secure and correct `ROUTER` address and the appropriate `POOL_TICK_SPACING` for the target liquidity pool. The liquidity and integrity of the underlying DEX are also assumed.
    *   It is assumed that the underlying `TokenBridge`, `L1MessageService`, and `L2MessageService` contracts are secure and will reliably deliver messages and tokens between L1 and L2.
*   **Secure Configuration and Liveness:** The system assumes that it will be deployed and maintained correctly.
    
    *   It is assumed that upon deployment of the upgradeable `RollupRevenueVault` contract, the `initialize` function will be called atomically within the same transaction to prevent a malicious actor from front-running the call and seizing control of the contract.
    *   All configurable addresses in the `RollupRevenueVault` are assumed to be set to their correct values upon initialization.
    *   The actors responsible for the `BURNER_ROLE` and `INVOICE_SUBMITTER_ROLE` are assumed to be live and to perform their duties as required. A failure to do so could cause the revenue management process to halt.

Medium Severity
---------------

### Partial Swaps Can Lead to Permanently Locked Funds

The [`V3DexSwap` contract](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/V3DexSwap.sol) is designed to be used by the `RollupRevenueVault` contract to swap ETH for LINEA tokens. Its `swap` function accepts a `_sqrtPriceLimitX96` parameter, which allows the caller to specify a price limit for the trade. Using a price limit can result in a partial swap where only a portion of the input tokens are consumed if the price limit is reached.

The `V3DexSwap` contract does not correctly handle the outcome of a partial swap. When its `swap` function is called, it converts all the received ETH into WETH. If the subsequent call to the DEX router results in a partial swap, any unswapped WETH remains in the `V3DexSwap` contract's balance. Since the `V3DexSwap` contract has no functions to withdraw or transfer leftover tokens, these remaining WETH funds become permanently locked and irrecoverable.

Consider adding logic to the `swap` function to refund any unswapped tokens. After the call to the DEX router is complete, the function could check the contract's remaining WETH balance. If the balance is greater than zero, the tokens could be unwrapped back to ETH and immediately transferred back to a designated recipient, such as the `msg.sender` (the `RollupRevenueVault`). Alternatively, given that the [`_minLineaOut` variable](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/V3DexSwap.sol#L70-L71) provides slippage protection, setting `_sqrtPriceLimitX96` to 0 can also be considered.

_**Update:** Resolved in [pull request #1604](https://github.com/Consensys/linea-monorepo/pull/1604). The Linea team stated:_

> _We have hardcoded `_sqrtPriceLimitX96` to zero and have added more robust checking on `dexSwapAdapter`. Note that now, we also burn the full token balance._

### Unprotected Reinitializer Function

The [`RollupRevenueVault` contract](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol) is an upgradeable contract that uses the OpenZeppelin `Initializable` pattern. It includes an `initialize` function for initial setup and a separate [`initializeRolesAndStorageVariables` function](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol#L98-L123) intended for future upgrades. This second function is decorated with the `reinitializer(2)` modifier, designating it to be run for a version 2 upgrade.

However, the `initializeRolesAndStorageVariables` function lacks any access control. While the `reinitializer(2)` modifier prevents the function from being called after the contract has been upgraded to version 2 or higher, it does not protect it beforehand. If the contract is initialized at version 1, any user can call this function, as the [check](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/2d081f24cac1a867f6f73d512f2022e1fa987854/contracts/proxy/utils/Initializable.sol#L120) (`_initialized < 2`) will pass. This allows a malicious actor to call the function and provide their own addresses for all critical roles, leading to a complete hostile takeover of the contract's administration and control over its funds.

The severity of this issue depends on the deployment context. For the existing, already-initialized proxy, the immediate risk is lower. The intended action is a permissioned upgrade, where the call to the reinitializer would be performed atomically, leaving no opportunity for an attacker. However, for any new deployment of this contract (e.g., on other chains), this vulnerability is critical. An attacker could back-run the legitimate initialization transaction, call this reinitializer function first, and seize administrative control and all funds within the contract.

Consider adding an appropriate access-control modifier to the `initializeRolesAndStorageVariables` function. This would restrict its execution to a privileged address, ensuring that the function can only be called during a legitimate and authorized upgrade process.

_**Update:** Resolved in [pull request #1604](https://github.com/Consensys/linea-monorepo/pull/1604). The Linea team stated:_

> _We have removed the `initialize` function. Anyone deploying a new version can jump directly to 2 with reinitialize, or they can deploy an empty upgradeable contract._

Low Severity
------------

### Generic DEX Interaction in `RollupRevenueVault`

The [`RollupRevenueVault` contract](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol) is responsible for swapping ETH revenue for LINEA tokens as part of its [`burnAndBridge` function](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol#L198-L222). The codebase also includes the [`V3DexSwap` contract](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/V3DexSwap.sol), a purpose-built utility designed to safely execute such swaps. The `V3DexSwap` contract's `swap` function performs on-chain validation of key safety parameters, such as requiring a non-zero `_minLineaOut` to protect against slippage.

The `RollupRevenueVault` contract does not directly leverage the safer, high-level interface of the `V3DexSwap` contract. Instead, it interacts with a configurable `dex` address via [a generic, low-level `dex.call`](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol#L211) that takes opaque `_swapData` as an argument. This design means that the `RollupRevenueVault` itself has no control over the safety parameters of the swap. While the `V3DexSwap` contract does perform its own on-chain checks, the vault cannot enforce that the provided `_swapData` targets the correct function or that the slippage parameters within that data are set to safe values. This places complete trust in the `BURNER_ROLE` to generate and submit secure calldata for every transaction.

Consider refactoring the `RollupRevenueVault` contract to reduce its reliance on a generic call pattern and instead integrate with a more specific swap interface like `IV3DexSwap`. The `burnAndBridge` function could be modified to accept high-level parameters such as `minimumAmountOut` and `deadline` directly. It would then use these arguments to make a high-level call to the `dex` address, which would be expected to conform to the `IV3DexSwap` interface. This change would shift the responsibility for ensuring slippage protection from a trusted off-chain role to transparent, enforceable on-chain logic.

_**Update:** Acknowledged, not resolved in [pull request #1604](https://github.com/Consensys/linea-monorepo/pull/1604). The Linea team stated:_

> _This is by design, and we have only renamed `DexSwap` to `DexSwapAdapter` for more clarity._

Notes & Additional Information
------------------------------

### Functions Updating State Without Event Emissions

As per the given documentation: "_All functions should be emitting events that allow for accurate off-chain accounting reporting."_

Throughout the codebase, multiple instances of functions updating the state without event emission were identified:

*   The [`constructor` function](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/L1LineaTokenBurner.sol#L21-L27) in `L1LineaTokenBurner.sol`
*   The [`__RollupRevenueVault_init` function](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol#L125-L160) in `RollupRevenueVault.sol`
*   The [`constructor` function](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/V3DexSwap.sol#L31-L41) in `V3DexSwap.sol`
*   The [`claimMessageWithProof` function](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/L1LineaTokenBurner.sol#L34-L44) in `L1LineaTokenBurner.sol`

Consider emitting events whenever there are state changes to improve the clarity of the codebase and make it less error-prone.

_**Update:** Resolved in [pull request #1604](https://github.com/Consensys/linea-monorepo/pull/1604). The Linea team stated:_

> _We have added new events. For the `claimMessageWithProof` function, we are relying on the internal events of `IL1LineaToken.burn` and `IL1MessageService.claimMessageWithProof`._

### Incomplete Docstrings

Throughout the codebase, multiple instances of incomplete docstrings were identified:

*   In the [`swap`](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/V3DexSwap.sol#L50-L74) function of `V3DexSwap.sol`, not all return values are documented.
*   In the [`balanceOf`](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/interfaces/IL1LineaToken.sol#L20) function of `IL1LineaToken.sol`, not all return values are documented.
*   In the [`swap`](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/interfaces/IV3DexSwap.sol#L41-L45) function of `IV3DexSwap.sol`, not all return values are documented.

Consider thoroughly documenting all functions/events (and their parameters or return values) that are part of a contract's public API. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in [pull request #1604](https://github.com/Consensys/linea-monorepo/pull/1604). The Linea team stated:_

> _We have added more NatSpec comments._

### Multiple Optimizable State Reads

In `RollupRevenueVault.sol`, multiple instances of optimizable storage reads were identified:

*   The `lineaToken` storage read in the `burnAndBridge` function can be cached in memory and subsequently used [here](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol#L217) and [here](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol#L219).
*   The `tokenBridge` storage read in the `burnAndBridge` function can be cached in memory and subsequently used [here](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol#L217) and [here](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol#L219).

Consider reducing SLOAD operations that consume unnecessary amounts of gas by caching the values in a memory variable.

_**Update:** Resolved in [pull request #1604](https://github.com/Consensys/linea-monorepo/pull/1604). The Linea team stated:_

> _The Linea Token and Token Bridge addresses are now cached._

### Lack of Indexed Event Parameters

Within `IRollupRevenueVault.sol`, multiple instances of events not having any indexed parameters were identified:

*   The [`L1LineaTokenBurnerUpdated` event](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/interfaces/IRollupRevenueVault.sol#L105)
*   The [`DexUpdated` event](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/interfaces/IRollupRevenueVault.sol#L112)
*   The [`InvoicePaymentReceiverUpdated` event](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/interfaces/IRollupRevenueVault.sol#L132)

To improve the ability of off-chain services to search and filter for specific events, consider [indexing event parameters](https://solidity.readthedocs.io/en/latest/contracts.html#events).

_**Update:** Acknowledged, not resolved. The Linea team stated:_

> _These events are not expected to change often if at all, and indexing them provides no real benefit as we do not intend on searching by the values._

### Return Value of `approve` Is Not Checked

In the `RollupRevenueVault` contract, the `burnAndBridge` function [swaps ETH for LINEA tokens](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol#L211) and [subsequently bridges them to L1](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol#L219). To facilitate this, the function calls the [`approve` method](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol#L217) of the `lineaToken` contract to grant the `tokenBridge` an allowance to spend the newly acquired tokens on the vault's behalf. This `approve` call does not check the boolean return value to verify that the allowance was successfully updated. While many modern ERC-20 tokens revert on failure, [the standard](https://eips.ethereum.org/EIPS/eip-20) allows for the `approve` function to return `false` to signal a failure.

The current Linea token reverts on a failed approval. However, as per discussions, the partners may set the `lineaToken` variable to a different token in future through [`initializeRolesAndStorageVariables` function](https://github.com/Consensys/linea-monorepo/blob/8285efababe0689aec5f0a21a28212d9d22df22e/contracts/src/operational/RollupRevenueVault.sol#L98). In that scenario, a failed approval would go undetected if the new token returns false instead of revert. The execution would then continue to the `tokenBridge.bridgeToken` call, which would revert due to the allowance being zero, causing the entire `burnAndBridge` transaction to fail and preventing the revenue-burning mechanism from operating.

Consider using OpenZeppelin’s `SafeERC20` library and its `safeApprove` function for all ERC-20 approvals. This wrapper handles the return value check internally and protects against tokens that do not return a boolean. It should be noted, however, that this does not pose a problem if the `lineaToken` contract on the specific L2 where this contract is deployed is known to revert on approval failure, as is common with standard OpenZeppelin ERC-20 implementations.

_**Update:** Acknowledged, not resolved. The Linea team stated:_

> _We are only approving WETH and the LINEA token and do not expect any issues with this. If there are any complications, the off-chain services will be doing `eth_call`s beforehand and no gas will be wasted if things are failing._

Conclusion
----------

The audited system comprises a set of operational smart contracts designed to implement a burn mechanism for ETH and LINEA tokens using L2 protocol revenue. These contracts facilitate the collection of L2 protocol revenue, payment of operational expenses, and execution of a cross-chain buy-and-burn mechanism for the native LINEA token.

Two medium-severity issue and several low-severity issues were reported, primarily concerning access control for new deployments, the handling of external interactions such as DEX calls and token approvals.

The identified issues underscore the importance of robust access control, especially for upgradeable contracts, and the need for careful validation of all external parameters and interactions within a cross-chain environment. The security of the system relies heavily on the correct implementation of these principles.

The Linea team is appreciated for being responsive and collaborative throughout the audit process.