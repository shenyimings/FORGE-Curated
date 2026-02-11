\- July 3, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

**Type:** Cross-Chain  
**Timeline:** May 15, 2025 → May 26, 2025**Languages:** Solidity

**Findings**Total issues: 13 (13 resolved)  
Critical: 0 (0 resolved) · High: 1 (1 resolved) · Medium: 3 (3 resolved) · Low: 3 (3 resolved)

**Notes & Additional Information**6 notes raised (6 resolved)

Scope
-----

OpenZeppelin conducted a differential audit of the [across-protocol/contracts](https://github.com/across-protocol/contracts) repository, with the base at commit [7362cd0](https://github.com/across-protocol/contracts/tree/7362cd06aa8e97666f59446df018899f5858506c) (master) and the head at commit [b84dbfa](https://github.com/across-protocol/contracts/tree/b84dbfae35030e0f2caa5509b632c10106a32330).

In scope were the following files:

`contracts
├── external
│   └── interfaces
│       ├── IERC20Auth.sol
│       └── IPermit2.sol
├── handlers
│   └── MulticallHandler.sol
├── interfaces
│   └── SpokePoolPeripheryInterface.sol
├── libraries
│   └── PeripherySigningLib.sol
└── SpokePoolPeriphery.sol` 

System Overview
---------------

The Across protocol is a cross-chain bridge designed for fast and cost-effective transfers of ERC-20 tokens and native assets across various networks. It allows users (depositors) to lock assets on an origin chain, which are then made available to them on a destination chain by relayers who front their own capital. The protocol refunds the relayers by sending funds available on the chain of relayers' choice or by tapping into the HubPool on Ethereum if a specific chain does not have enough funds. This audit focuses on a new set of peripheral smart contracts intended to enhance the functionality, flexibility, and user experience of interacting with the Across V3 ecosystem.

### `SpokePoolPeriphery`

The `SpokePoolPeriphery` contract acts as a user-facing entry point to the Across protocol, significantly expanding the options available for initiating cross-chain transfers. Its core functionalities include the following:

*   **Swap and Bridge**: A flagship feature allowing users to bridge assets even if they do not hold the specific token required by the SpokePool. The contract can take a user-specified `swapToken`, execute a trade on a designated external exchange to convert it into the `inputToken` accepted by Across, and then initiate the bridge deposit - all within a single, atomic transaction. This functionality supports proportional output adjustment, where the amount of tokens to be received on the destination chain can be proportionally increased if the swap yields more `inputToken` than the user's specified minimum.
*   **Versatile Token Authorization**: The contract integrates multiple industry-standard mechanisms for authorizing token transfers from users, providing flexibility and enabling gas-efficient interactions:
    *   Standard ERC-20 `transferFrom` for pre-approved tokens
    *   Native currency (e.g., ETH) deposits, which are automatically wrapped into their WETH equivalent if a non-zero `msg.value` is provided
    *   EIP-2612 `permit`
    *   Permit2 (`permitWitnessTransferFrom`) for batch approvals and more advanced signature-based permissions via the canonical `Permit2` contract
    *   EIP-3009 `receiveWithAuthorization` for tokens supporting this ERC-20 extension
*   **Isolated Swap Execution via `SwapProxy`**: To enhance security and modularity, all swap operations are delegated to a dedicated `SwapProxy` contract. The `SpokePoolPeriphery` deploys this proxy and transfers tokens to it for swapping. The `SwapProxy` then handles token approvals to the specified exchange or to the Permit2 contract and executes the swap calldata on the target exchange. Finally, the output token is transferred back to the `SpokePoolPeriphery` contract.

### `MulticallHandler` Changes

The changes to the `MulticallHandler` contract involve the addition of the `makeCallWithBalance` function which can be used to fill given calldata with specified tokens' balances of the `MulticallHandler` contract and to call the target contract using this modified calldata. This feature is useful whenever the amount of tokens that arrive on a target chain is not known when the calldata is specified, which can be the case when the _swap and bridge_ functionality from the `SpokePoolPeriphery` contract is used, and a depositor does not know the output amount from the swap when they sign the data for the deposit.

It is worth noting that the depositors themselves are responsible for providing the correct tokens and offsets where the balances should be filled, keeping in mind that balances may be represented in smaller types than `uint256` and that specifying wrong offsets may lead to unintended consequences, such as loss of funds. Users should also keep in mind that the `makeCallWithBalance` function will not work with exchanges that require providing a negative token amount as a parameter as it is only capable of filling the calldata with non-negative balances. All depositors are encouraged to study the `makeCallWithBalance` function's documentation in order to understand all of its risks and limitations.

### `PeripherySigningLib`

The `PeripherySigningLib` is a library that supports the signature-based features of `SpokePoolPeriphery`. Its contributions include:

*   **Standardized Hashing**: Provides functions to compute EIP-712-compliant typed data hashes for the `BaseDepositData`, `Fees`, `DepositData`, and `SwapAndDepositData` structs. This ensures consistent and secure signature generation and verification.
*   **Signature Deserialization**: Offers a utility function to parse a raw byte signature into its `v, r, s` components, simplifying signature handling in the main contract logic.

Security Model and New Trust Assumptions
----------------------------------------

The introduction of these peripheral contracts expands the Across protocol's functionality and, consequently, introduces new elements to its security model and specific trust assumptions:

*   The `swapAndBridge` functionality relies on external exchanges specified by the user (or a trusted frontend). The security of user funds during a swap is contingent upon the security of the chosen exchange and the integrity of the `routerCalldata` provided. A compromised exchange or malicious calldata could lead to a loss of funds.
*   Users (or frontends acting on their behalf) are responsible for the correctness and safety of parameters like exchange addresses, router calldata for swaps, `MulticallHandler` instructions, and EIP-712 signed messages, as incorrect or malicious inputs can lead to failed transactions, loss of funds, or unintended interactions. It is assumed that users only utilize trusted exchanges, specify reasonable minimum token output amounts, and provide correct EIP-712 signatures. Furthermore, it is assumed that they specify the correct calldata for the `MulticallHandler` contract and that they take care of transferring any tokens remaining in this contract to their accounts at the end of each interaction with it.
*   The use of Permit2 implies trust in the security and operational integrity of the canonical `Permit2` contract. It is assumed that this contract behaves in a correct manner. It is also important to note that the `SpokePoolPeriphery` contract depends on the existence of the `Permit2` contract on the chain where it is deployed. We assume that the `SpokePoolPeriphery` contract will be only deployed on blockchains where the `Permit2` contract exists.
*   The users are responsible for submitting correct data for swaps, which includes, but is not limited to, specifying reasonable minimum swap output token amount and deposit output amount. It is assumed that users specify correct data for deposits and swaps.
*   Submitters (e.g., relayers) should always simulate the signed swap transaction off-chain before submission. Since `swapProxy` blindly calls the user-specified `exchange` with arbitrary `routerCalldata`, a malicious signer can point it at a contract that, for example, enters an infinite loop or performs a return bomb attack exhausting all the gas before reverting. Without simulation, the relayer bears the full gas cost of a failing call (a gas-griefing attack) and receives no compensation.

High Severity
-------------

### Incorrect Nonce Passed to the `Permit2.permit` Function

The [`performSwap` function](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L67) of the `SwapProxy` contract allows for providing tokens for a swap to a specified exchange using several different methods. In particular, it allows for approving tokens for the swap [through the `Permit2` contract](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L86-L101). In order to do that, it [approves the given token amount to the `Permit2` contract](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L86) and [calls the `permit` function of the `Permit2` contract](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L88-L101).

However, the [nonce specified for that call](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L95) is global for the entire contract, whereas the `Permit2` contract stores [a separate nonce for each (owner, token, spender) tuple](https://github.com/Uniswap/permit2/blob/cc56ad0f3439c502c246fc5cfcc3db92bb8b7219/src/interfaces/IAllowanceTransfer.sol#L85). As a result, any attempt to use a different (token, spender) pair from the ones used in the first `performSwap` function call will result in the [revert](https://github.com/Uniswap/permit2/blob/cc56ad0f3439c502c246fc5cfcc3db92bb8b7219/src/AllowanceTransfer.sol#L138) due to nonce mismatch.

Consider storing and using separate nonces for each (token, spender) pair in the `SwapProxy` contract.

_**Update:** Resolved in [pull request #1013](https://github.com/across-protocol/contracts/pull/1013) at commit [`3cd99c4`](https://github.com/across-protocol/contracts/pull/1013/commits/3cd99c4c9362f743a233c0747bc7829e604edfa8)._

Medium Severity
---------------

### Possible Replay Attacks on `SpokePoolPeriphery`

The [`SpokePoolPeriphery` contract](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L140) allows users to deposit or swap-and-deposit tokens into a SpokePool. In order to do that, the assets are first transferred from the depositor's account, optionally swapped to a different token, and then finally deposited into a SpokePool.

Assets can be transferred from the depositor's account in several different ways, including approval followed by the [`transferFrom` call](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L236-L240), [approval through the ERC-2612 `permit` function followed by `transferFrom`](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L267-L268), [transfer through the `Permit2` contract](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L295-L302), and [transfer through the ERC-3009 `receiveWithAuthorization` function](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L328-L338). The last three methods require additional user signatures and may be executed by anyone on behalf of a given user. However, the [data to be signed for deposits or swaps and deposits](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/interfaces/SpokePoolPeripheryInterface.sol#L70-L105) with ERC-2612 `permit` and with ERC-3009 `receiveWithAuthorization` does not contain a nonce, and, as such, the signatures used for these methods once can be replayed later.

The attack can be performed if a victim signs data for a function relying on the ERC-2612 `permit` function and wants to deposit tokens once again using the same method and token [within the time window determined by the `depositQuoteTimeBuffer` parameter](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePool.sol#L1306-L1307). In such a case, an attacker can first approve tokens on behalf of the victim and then call the [`swapAndBridgeWithPermit` function](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L249) or the [`depositWithPermit` function](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L357), providing a signature for a deposit or swap-and-deposit from the past, that includes fewer tokens than the approved amount.

As a result, the tokens will be deposited and potentially swapped, using the data from an old signature, forcing the victim to either perform an unintended swap or bridge the tokens to a different chain than intended. Furthermore, since the attack consumes some part of the `permit` approval, it will not be possible to deposit tokens on behalf of a depositor using the new signature until the full amount of tokens is approved by them once again. A similar attack is also possible in the case of functions that rely on the ERC-3009 `receiveWithAuthorization` function, but it requires the amount of tokens being transferred to be identical to the amount from the past.

Consider adding a nonce field into the [`SwapAndDepositData` and `DepositData` structs](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/interfaces/SpokePoolPeripheryInterface.sol#L70-L105) and storing a nonce for each user in the `SpokePoolPeriphery` contract, which should be incremented when a signature is verified and accepted.

_**Update:** Resolved in [pull request #1015](https://github.com/across-protocol/contracts/pull/1015). The Across team has added a `permitNonces` mapping and extended both `SwapAndDepositData` and `DepositData` with a `nonce` field. In `swapAndBridgeWithPermit` and `depositWithPermit`, the contract now calls `_validateAndIncrementNonce(signatureOwner, nonce)` before verifying the EIP-712 signature, ensuring each permit-based operation can only be executed once. ERC-3009 paths continue to rely on the token’s own nonce; a replay here would require a token to implement both ERC-2612 and ERC-3009, a user to reuse the exact same nonce in both signatures, and both are executed within the narrow `fillDeadlineBuffer`. Given the unlikely convergence of these conditions, the risk is negligible in practice._

### Possible DoS Attack on Swapping via `Permit2`

The [`SwapProxy` contract](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L26) contains the [`performSwap` function](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L67), which allows the caller to execute a swap in two ways: [by approving or sending tokens to the specified exchange](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L81-L84), or by [approving tokens through the `Permit2` contract](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L86-L101). However, since it is possible to supply any address as the `exchange` parameter and any call data through the `routerCalldata` parameter of the `performSwap` function, the `SwapProxy` contract may be forced to perform an [arbitrary call to an arbitrary address](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L108).

This could be exploited by an attacker, who could force the `SwapProxy` contract to call the [`invalidateNonces` function](https://github.com/Uniswap/permit2/blob/cc56ad0f3439c502c246fc5cfcc3db92bb8b7219/src/AllowanceTransfer.sol#L113) of the `Permit2` contract, specifying an arbitrary spender and a nonce higher than the current one. As a result, the nonce for the given (token, spender) pair will be [updated](https://github.com/Uniswap/permit2/blob/cc56ad0f3439c502c246fc5cfcc3db92bb8b7219/src/AllowanceTransfer.sol#L124). If the `performSwap` function is called again later, it [will attempt to use a subsequent nonce](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L95), which has been invalidated by the attacker and the code inside `Permit2` will [revert due to nonces mismatch](https://github.com/Uniswap/permit2/blob/cc56ad0f3439c502c246fc5cfcc3db92bb8b7219/src/AllowanceTransfer.sol#L138).

As the `performSwap` function is the only place where the nonce passed to the `Permit2` contract is updated, the possibility of swapping a given token on a certain exchange will be blocked forever, which impacts all the functions of the [`SpokePoolPeriphery` contract](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L140) related to swapping tokens. The attack may be performed for many different (tokens, exchange) pairs.

Consider not allowing the `exchange` parameter to be equal to the `Permit2` contract address.

_**Update:** Resolved in [pull request #1016](https://github.com/across-protocol/contracts/pull/1016) at commit [`713e76b`](https://github.com/across-protocol/contracts/pull/1016/commits/713e76b8388d90b4c3fbbe3d16b531d3ef81c722)._

### Incorrect EIP-712 Encoding

The [`PeripherySigningLib` library](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/libraries/PeripherySigningLib.sol#L6) contains the EIP-712 encodings of certain types as well as helper functions to generate their EIP-712 compliant hashed data. However, the [data type of the `SwapAndDepositData` struct](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/libraries/PeripherySigningLib.sol#L12-L13) is incorrect as it contains the `TransferType` member [of an enum type](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/interfaces/SpokePoolPeripheryInterface.sol#L18-L25), which is not supported by the EIP-712 standard.

Consider replacing the `TransferType` enum name used to generate the `SwapAndDepositData` struct's data type with `uint8` in order to be compliant with EIP-712.

_**Update:** Resolved in [pull request #1017](https://github.com/across-protocol/contracts/pull/1017) at commit [`c9aaec6`](https://github.com/across-protocol/contracts/pull/1017/commits/c9aaec6d26993314e0bf878cd4eb89f447194789)._

Low Severity
------------

### `deposit` Will Not Work for Non-EVM Target Chains

The [`deposit` function](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L189) of the `SpokePoolPeriphery` contract allows users to deposit native value to the SpokePool. However, its `recipient` and `exclusiveRelayer` arguments are both of type `address` and are [cast](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L209-L215) to `bytes32`. As a result, it is not possible to bridge wrapped native tokens to non-EVM blockchains.

Consider changing the type of the `recipient` and `exclusiveRelayer` arguments of the `deposit` function so that callers are allowed to specify non-EVM addresses for deposits.

_**Update:** Resolved in [pull request #1018](https://github.com/across-protocol/contracts/pull/1018) at commit [`3f34af6`](https://github.com/across-protocol/contracts/pull/1018/commits/3f34af68b7602873e59a5a54b7c9cb0982f49d0e)._

### Integer Overflow in `_swapAndBridge`

In the [`_swapAndBridge` function](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L575), the adjusted output amount is [calculated](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L604-L606) as the product of `depositData.outputAmount` and `returnAmount` divided by `minExpectedInputTokenAmount`. If `depositData.outputAmount * returnAmount` exceeds `2^256–1`, the transaction will revert immediately on the multiply step, even when the eventual division result would fit. This intermediate overflow is invisible to users, who only see a generic failure without an explanatory error message.

Consider using OpenZeppelin’s [`Math.mulDiv(a, b, c)`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/48bd2864c6c696bf424ee0e2195f2d72ddd1a86c/contracts/utils/math/Math.sol#L204) to compute `floor(a*b/c)` without intermediate overflow. Alternatively, consider documenting the possible overflow scenario.

_**Update:** Resolved in [pull request #1020](https://github.com/across-protocol/contracts/pull/1020) at commit [`e872f04`](https://github.com/across-protocol/contracts/pull/1020/commits/e872f045bd2bbdb42d8ca74c2133d0afa63ae07b) by documenting the potential overflow scenario._

### Inflexible Fee Recipient Field Blocks Open Relaying

Currently, every `DepositData` and `SwapAndDepositData` payload must include a hard-coded [fee recipient address](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/interfaces/SpokePoolPeripheryInterface.sol#L72), and upon successful deposit or swap-and-bridge, the periphery pays submission fees to that exact address. While this ensures that the user knows in advance exactly who will receive their fee, it also prevents open relayer competition or fallback options when the chosen relayer underperforms or is unavailable.

Consider keeping the explicit fee recipient field option in `SwapAndDepositData` but introduce a "zero‐address" convention:

*   If the fee recipient is equal to the zero address, the periphery should default to using `msg.sender` as the payee.
*   If the fee recipient is not the zero address, transfer fees to the signed `recipient`.

_**Update:** Resolved in [pull request #1021](https://github.com/across-protocol/contracts/pull/1021) at commit [`f2218c0`](https://github.com/across-protocol/contracts/pull/1021/commits/f2218c0f8daf4fc68a72c10d8b606f9a6cf3ccdc)._

Notes & Additional Information
------------------------------

### Function Renaming Suggestion

The [`deposit` function](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L189) of the `SpokePoolPeriphery` contract allows users to deposit native value to the SpokePool. While it is possible to specify the `inputToken` parameter, it is not possible to deposit other tokens through this function. As a result, it could be renamed to `depositNative` or a similar name in order to make this fact clear.

Consider renaming the `deposit` function in order to improve the readability of the codebase.

_**Update:** Resolved in [pull request #1019](https://github.com/across-protocol/contracts/pull/1019) at commit [`a69ad79`](https://github.com/across-protocol/contracts/pull/1019/commits/a69ad7910abfcffa510ce18ef5cdfc0a8c89adc6)._

### Optimization Opportunities

Throughout the codebase, multiple opportunities for code optimization were identified:

*   The checks validating that a given address refers to a contract in lines [204](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L204), [231](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L231), and [553](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L553) are not necessary in cases where the addresses do not refer to contracts. This is because the subsequent calls in lines [207](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L207), [233](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L233), and [555](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L555) will revert as the Solidity compiler inserts similar code-size checks before each high-level call.
*   The "0x" string passed to the [`permit` call](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L88-L101) could be replaced with "".
*   [This check](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L203) could be removed as the same check is [already performed](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePool.sol#L1340) in SpokePools.
*   The `replacement` argument of the [`makeCallWithBalance` function](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/handlers/MulticallHandler.sol#L123) could be stored in `calldata` instead of `memory`.
*   The use of the [`Lockable`](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L9) contract is inefficient. OpenZeppelin’s [`ReentrancyGuard`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/0034c302241c4b1a1685272d4df42ca5d64b8c34/contracts/utils/ReentrancyGuard.sol) delivers significantly lower gas overhead by using a two‐word `uint256` status in place of a `bool`, reducing SSTORE costs, and swapping long revert strings for a 4-byte custom error to shrink both the bytecode and the revert gas cost. For deployments on chains that support EIP-1153 (transient storage), adopting [`ReentrancyGuardTransient`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/d183d9b07a6cb0772ff52aa4e3e40165e99d6359/contracts/utils/ReentrancyGuardTransient.sol) can nearly eliminate reentrancy‐guard gas costs.

Consider implementing the above suggestions in order to improve the gas efficiency of the codebase.

_**Update:** Resolved in [pull request #1022](https://github.com/across-protocol/contracts/pull/1022) at commit [`c3e7f3d`](https://github.com/across-protocol/contracts/pull/1022/commits/c3e7f3dee95112afb0f22ecb2230392b8063989e)._

### Insufficient Documentation

Throughout the codebase, multiple instances of insufficient documentation were identified: - The [`makeCallWithBalance` function](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/handlers/MulticallHandler.sol#L123) of the `MulticallHandler` contract allows for replacing specified offsets of a given call data with the current token or native balances. However, the purpose of this function and the correct way of using it may not be immediately clear to the users. As such, the function would benefit from the additional documentation describing its purpose, limitations, and correct usage. One additional limitation that could be listed is that this function is not capable of filling negative balances. Hence, decentralized exchanges, which require input token amounts to be negative, would not be supported. - The documentation of the [`swapAndBridge`](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L226), [`swapAndBridgeWithPermit`](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L249), [`swapAndBridgeWithPermit2`](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L282), and [`swapAndBridgeWithAuthorization`](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L314) functions could mention the fact that they do not support native value as the output token of the swaps and, as a result, it is only possible to deposit non-native tokens to a SpokePool through these functions. - The [`PeripherySigningLib`](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/libraries/PeripherySigningLib.sol) library does not include any top-of-file NatSpec annotations describing its purpose, usage, or any relevant details. Without a contract-level NatSpec comment block, readers and automated documentation tools will not have a concise overview of what this library is for or how to integrate with it.

Consider expanding the documentation in the aforementioned instances in order to improve the clarity of the codebase.

_**Update:** Resolved in [pull request #1023](https://github.com/across-protocol/contracts/pull/1023) at commit [`047283e`](https://github.com/across-protocol/contracts/pull/1023/commits/047283e0a4bee4f79c9a6f31c788986c1f07209d)._

### Typographical Errors

Throughout the codebase, multiple instances of typographical errors were identified: - In [line 48](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/handlers/MulticallHandler.sol#L48) of the `MulticallHandler.sol` file, "calldData" should be "callData". - In [line 113](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/interfaces/SpokePoolPeripheryInterface.sol#L113) of the `SpokePoolPeripheryInterface.sol` file, "on" could be removed. - In [line 500](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L500) of the `SpokePoolPeriphery.sol` file, "depositData/swapAndDepositData" could be "DepositData/SwapAndDepositData".

Consider correcting all instances of typographical errors in order to improve the clarity and readability of the codebase.

_**Update:** Resolved in [pull request #1024](https://github.com/across-protocol/contracts/pull/1024) at commit [`18296cb`](https://github.com/across-protocol/contracts/pull/1024/commits/18296cbd072d0d6f46f2a5bddfafa54551562c7c)._

### Unused Code

Throughout the codebase, multiple instances of unused code were identified: - In the `SpokePoolPeriphery.sol` file, the [`InvalidSignatureLength` error](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L165) is unused - In the `SpokePoolPeripheryInterface.sol` file, the [import](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/interfaces/SpokePoolPeripheryInterface.sol#L6) is unused

To improve the overall clarity and maintainability of the codebase, consider removing any instances of unused code.

_**Update:** Resolved in [pull request #1025](https://github.com/across-protocol/contracts/pull/1025) at commit [`767cb9f`](https://github.com/across-protocol/contracts/pull/1025/commits/767cb9ff1ffe1f2fbe023d83f51dd5ef50f5a9d2)._

### Misleading Documentation

Throughout the codebase, multiple instances of misleading documentation were identified:

*   The [`swapAndBridgeWithPermit`](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L267) and [`depositWithPermit`](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L375) functions are [documented to fail](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/interfaces/SpokePoolPeripheryInterface.sol#L154) if the provided token does not support the EIP-2612 `permit` function. However, the implementation contradicts this statement because, in both functions, the call to `permit` is wrapped in a `try/catch` block, and any failure is silently ignored.
*   [This comment](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L325) refers to the `transferWithAuthorization` function, whereas it should mention the `receiveWithAuthorization` function instead.
*   The documentation for the [`SpokePoolPeriphery` contract](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L140) and the [`SpokePoolPeripheryInterface` interface](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/interfaces/SpokePoolPeripheryInterface.sol#L16) contains an [outdated comment](https://github.com/across-protocol/contracts/blob/b84dbfae35030e0f2caa5509b632c10106a32330/contracts/SpokePoolPeriphery.sol#L136-L137) claiming that certain variables are not marked immutable or set in the constructor to allow deterministic deployment. This is no longer true as the variables are now immutable and set in the constructor.

Consider fixing the instances mentioned above in order to enhance the clarity of the codebase.

_**Update:** Resolved in [pull request #1026](https://github.com/across-protocol/contracts/pull/1026) at commit [`f8f484a`](https://github.com/across-protocol/contracts/pull/1026/commits/f8f484a1520bcdd91f020671dc185aca2118f901)._

Conclusion
----------

The under-review changes made to the periphery contracts introduced new possibilities for depositing assets to SpokePools. They enable third-party entities to deposit or swap-and-deposit funds on behalf of any user who provides a valid signature. Furthermore, they protect users from losing their native tokens in case they specify an incorrect SpokePool address for the deposit.

While the audit uncovered several issues related to swap logic and signature handling, the code was found to be solid and well-organized. The Risk Labs team is appreciated for being responsive and answering the audit team's questions throughout the audit.