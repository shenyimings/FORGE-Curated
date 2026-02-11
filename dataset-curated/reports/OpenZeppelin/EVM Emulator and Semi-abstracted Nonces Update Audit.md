\- May 15, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

**Type:** L2 Protocol  
**Timeline:** March 20, 2025 → March 28, 2025**Languages:** Solidity + Yul

**Findings**Total issues: 17 (15 resolved, 1 partially resolved)  
Critical: 1 (1 resolved) · High: 1 (1 resolved) · Medium: 0 (0 resolved) · Low: 4 (4 resolved)

**Notes & Additional Information**11 notes raised (9 resolved, 1 partially resolved)  
Client reported issues: 0 (0 resolved)

Scope
-----

We audited the [pull request #1359](https://github.com/matter-labs/era-contracts/pull/1359) of the [matter-labs/era-contracts](https://github.com/matter-labs/era-contracts) repository at commit [cc1619c](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/).

In scope were the following files:

`system-contracts
├── contracts
│   ├── Constants.sol
│   ├── ContractDeployer.sol
│   ├── EvmEmulator.yul
│   ├── EvmGasManager.yul
│   ├── NonceHolder.sol
│   ├── SystemContractErrors.sol
│   └── interfaces
│       ├── IContractDeployer.sol
│       └── INonceHolder.sol
└── evm-emulator
    ├── EvmEmulator.template.yul
    ├── EvmEmulatorFunctions.template.yul
    ├── EvmEmulatorLoop.template.yul
    └── calldata-opcodes
       └── RuntimeScope.template.yul` 

**Note:** Only the changes introduced in the pull request were audited. The full content of the listed files was not reviewed in its entirety.

System Overview
---------------

The audited pull request can be split into two different projects:

*   Implementation of semi-abstracted nonces on the system contracts
*   EVM Emulator updates.

### EVM Emulator updates

#### Enhancing Efficiency with Pointer-based Bytecode Handling

After the changes introduced in this pull request, the `EvmEmulator` no longer copies EVM bytecodes during calls; instead, it reads them directly by pointers. This modification leverages pointers more actively, resulting in optimization improvements. By eliminating the need to copy bytecodes and utilizing pointers, the emulator enhances its efficiency, reduces memory usage, and streamlines bytecode handling.

#### Support for `modexp` Precompile

This pull request adds support for the `modexp` precompile in the EVM emulator and includes the implementation of gas calculations based on the input values, following the specifications of [EIP-2565](https://eips.ethereum.org/EIPS/eip-2565).

### Semi-Abstracted Nonces Implementation

Requiring a single sequential nonce value is limiting the sender's ability to define their custom logic in regards to transaction ordering. In particular, ZKsync SSO's session module requires the ability to send multiple transactions in parallel without any of them overriding or cancelling the other ones.

One key change introduced in this pull request is the support for [EIP-4337's semi-abstracted nonces](https://eips.ethereum.org/EIPS/eip-4337#semi-abstracted-nonce-support). Before this change, accounts across the ZKChains could opt for two modes of nonce ordering: sequential and arbitrary. After this pull request, the arbitrary ordering has been deprecated and the sequencial one has been upgraded into `KeyedSequential`.

This new ordering type, allows for parallel transactions to be executed without clashing among each other, by splitting the full `uint256` nonce field into two values: a 192-bit `key` followed by a 64-bit `sequence`. Given the same `key`, the `sequence` field follows the classical sequential order, and `userOperation`s must be executed in strictly sequential order. However, multiple `key`s can be used in parallel without affecting each other.

In order so support this change, the old feature to set values under nonces (via the `setValueUnderNonce` function) has been removed. This feature allowed specific nonce invalidation by setting a value within them in a mapping.

One thing to note is that the keyed sequential ordering is backwards compatible, so all the sequential ordering accounts are treated as having been using the `key` with value zero up until now. Updating the nonce ordering is not possible anymore, and `KeyedSequential` is the default value on account creation.

#### Integration Considerations

This change introduces several considerations that integrators should keep in mind, such as:

*   The nonce can be increased by an arbitrary value up to 2^64 through the [`increaseMinNonce` function](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L82), which means that someone could theoretically reach the max nonce by performing 2^32 calls to increase their nonce by exactly 2^32.
*   Before this change, the maximum theoretical nonce was 2^128, while now it is 2^64 per key.
*   If an account is configured to use `Arbitrary` ordering before the update is deployed, there will not be possible for this account to migrate to `KeyedSequential`. At the time of the audit, the Matter Labs team confirmed there were zero accounts using such ordering.
*   There are currently 3 different mappings tracking the nonce system. One of them is deprecated, since it kept track of nonce invalidations by setting values under them, but it is still present in the codebase. The second one keeps track of nonces with key set to zero. The last one keeps track of the different sequences of nonces per non-zero key.
*   No module in the protocol is currently using the keyed nonce specific functions.
*   Every new account after this update, will have by default `KeyedSequential` ordering with no way to update to any other.

Additionally, the `SsoAccount` contract currently uses the [`incrementMinNonceIfEquals` method](https://github.com/matter-labs/zksync-sso-clave-contracts/blob/c7714c0fe0a33a23acce5aa20355f088d330b4f7/src/SsoAccount.sol#L233) to increase the nonce after each `Transaction`. However, this method [only allows the key to be zero](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L131-L134), which means that the `SsoAccount` contract will not be able to leverage the new keyed-nonces mechanism that would allow sending multiple `Transaction`s without them reverting due to the same nonce.

Consider updating the `SsoAccount` contract to use the new `incrementMinNonceIfEqualsKeyed` method.

Security Model and Trust Assumptions
------------------------------------

During the audit, the following trust assumption was made based on the changes in this PR:

*   **LLVM Compiler Intrinsics**: The function calls within the `verbatim` statements, such as `active_ptr_swap`, `active_ptr_data_load`, and `return_data_ptr_to_active`, belong to the LLVM compiler context. It is assumed that these intrinsics are correctly implemented and secure.

Critical Severity
-----------------

### Byte-to-Bit Mismatch in Shift Operations

In both [`modexpGasCost`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/evm-emulator/EvmEmulatorFunctions.template.yul#L985) and [`mloadPotentiallyPaddedValue`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/evm-emulator/EvmEmulatorFunctions.template.yul#L1052) functions, the code calculates shift amounts in bytes but uses them directly with EVM shift instructions, which operate on bits. This results in incomplete or inaccurate shifts, as 1 byte equals 8 bits. Without converting byte-based values into their bit equivalents, the shift operations behave incorrectly.

This mismatch has several negative effects:

*   **Distorted Parameter Reads**: When used to trim or isolate components like the base, exponent, or modulus, incorrect shifts may leave behind unintended bits. This can lead to inflated sizes, skewed gas calculations, or corrupted numerical values.
*   **Exploitability Risk**: Malicious users may supply inputs that trigger these incorrect shifts, potentially manipulating gas costs or bypassing boundary checks, leading to undefined or exploitable behavior.
*   **Incorrect Memory Interpretation**: Code paths intended to mask or sanitize specific bytes may instead leave residual bits intact. This can cause logical errors when interpreting memory content.
*   **Numerical Instability**: Misaligned shift results can cause values to overflow or underflow in downstream logic. For instance, malformed bit-lengths derived from exponent parsing may cause loops to run excessively or insufficiently.

Consider ensuring that every shift amount derived from a byte difference is multiplied by 8 before applying any shift operation. This guarantees alignment with EVM's bit-level shift semantics and avoids the wide range of downstream issues stemming from partial shifts.

_**Update:** Resolved in [pull request #1383](https://github.com/matter-labs/era-contracts/pull/1383)._

High Severity
-------------

### Inner Variable Shadowing Causes Incorrect Return in `mloadPotentiallyPaddedValue`

The helper function [`mloadPotentiallyPaddedValue`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/evm-emulator/EvmEmulatorFunctions.template.yul#L1052) is intended to read a 32-byte word from memory and zero out any bytes that lie beyond a specified memory boundary. However, due to improper use of a `let` declaration inside an `if` block, the adjusted value is not actually returned.

``function mloadPotentiallyPaddedValue(index, memoryBound) -> value {
    value := mload(index)

    if lt(memoryBound, add(index, 32)) {
        memoryBound := getMax(index, memoryBound)
        let shift := sub(add(index, 32), memoryBound)
        let value := shl(shift, shr(shift, value)) // inner `value` shadows outer
    }
}`` 

In the `if` block, a new local variable named `value` is declared using `let`, which shadows the outer `value` that is the function’s return variable. As a result, any transformation applied within the block affects only the inner `value` and not the function’s output. This leads to the function returning the original unmodified result of `mload(index)`, even when part of the read spans beyond the specified memory region.

As an additional observation, while variable [shadowing is disallowed in Yul](https://github.com/ethereum/solidity/blob/297230ad32a4ba0ac2505fc1a0d391d1cd1c25a3/docs/yul.rst?plain=1#L608-L610), the current compiler does not enforce this rule and fails to emit an error. This leads to subtle logic bugs such as this one, where the code appears correct but behaves unexpectedly due to silent shadowing.

This issue has downstream implications for gas cost estimation in the `modexpGasCost` function, which relies on `mloadPotentiallyPaddedValue` to extract bounded parameters. If those values are not correctly adjusted, the computation proceeds with inaccurate inputs:

*   **Incorrect parameter sizes**: When memory bounds are exceeded, out-of-bound bytes remain in the value, leading to misinterpreted sizes.
*   **Wrong exponent iteration count**: An incorrect `Esize` affects the bit length estimation, skewing the iteration logic.
*   **Incorrect gas metering**: The gas cost may be significantly under- or over-estimated, defeating the purpose of precise metering and potentially leading to exploitability or denial of service.

Consider assigning the adjusted value directly to the return variable, avoiding the use of a shadowing `let` declaration.

_**Update:** Resolved in [pull request #1384](https://github.com/matter-labs/era-contracts/pull/1384)._

Low Severity
------------

### Missing Docstrings

Docstrings are essential to improve code readability and maintenance. Providing clear descriptions of contracts, functions (including their arguments and return values), events, and state variables helps developers and auditors better understand code functionality and purpose.

Multiple instances of missing or incomplete docstrings were identified across several contracts, such as:

*   The [`ContractDeployer`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/ContractDeployer.sol) contract, where not all functions include docstrings for their arguments and return values.
    
*   The [`INonceHolder`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/interfaces/INonceHolder.sol) interface, which only describes function names without documenting arguments and return values.
    
*   The [`IContractDeployer`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/interfaces/IContractDeployer.sol) interface, which lacks documentation for several functions, events, arguments, and return values.
    

Consider thoroughly documenting all contracts, functions, events, and relevant state variables using clear, descriptive docstrings. Documentation should adhere to the [Ethereum Natural Specification Format](https://docs.soliditylang.org/en/v0.8.29/natspec-format.html) (NatSpec) standard to enhance readability, support auditing efforts, and improve long-term maintainability.

_**Update:** Resolved in [pull request #1399](https://github.com/matter-labs/era-contracts/pull/1399) at commits [250af39](https://github.com/matter-labs/era-contracts/pull/1399/commits/250af39463102a4074f2bccb0113aa471b1c537a) and [ae0a314](https://github.com/matter-labs/era-contracts/pull/1399/commits/ae0a31412f88775799787f7b5b06c179437923bc)._

### Deprecation of Arbitrary Ordering Is Not Explicit

The new implementation of the `ContractDeployer` contract [prevents](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/ContractDeployer.sol#L79-L82) accounts from updating their nonce ordering system. Additionally, `KeyedSequential` is specified as the [default ordering](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/ContractDeployer.sol#L437-L439), which makes the `Arbitrary` ordering option fully deprecated.

However, there are still places that do not reference this deprecation of the `Arbitrary` ordering which could cause confusion. In particular:

*   The [documentation and name](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/interfaces/IContractDeployer.sol#L33-L39) of the element in the `enum` corresponding to the `Arbitrary` type in the `IContractDeployer` interface.
*   The [broad documentation](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/docs/l2_system_contracts/system_contracts_bootloader_description.md#L227-L235) of the contract when referencing the nonce ordering.

Consider updating the documentation and `enum` value to properly reflect that this nonce ordering system is now deprecated in order to improve code readability, avoid confusion, and make the current design choice explicit. Additionally, even if there is not any account with `Arbitrary` ordering configured, there is a chance that one could set it before this code is deployed. Consider adding a function that would allow any account configured to use `Arbitrary` ordering to strictly migrate to `KeyedSequential`. This would provide these accounts with a way to correctly migrate in case they unknowingly update to `Arbitrary` before the update.

_**Update:** Resolved in [pull request #1387](https://github.com/matter-labs/era-contracts/pull/1387) at commit [051b360](https://github.com/matter-labs/era-contracts/pull/1387/commits/051b360aa8180208d66a8ceb6fbcc49798f8c3dd). The Matter Labs team stated:_

> _Migrating from `Arbitrary` ordering back to `KeyedSequential` is forbidden due to the assumptions that `KeyedSequential` ordering makes. Namely, if nonce value for nonce key K is V, the assumption is that none of the values above V are used. This assumption would break if account migrates from `Arbitrary` ordering._

### Lack of Input Validation

The `_value` argument from the [`increaseMinNonce` function](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L82) in the `NonceHolder` contract lacks input validation, and it should be strictly greater than zero when called.

Consider implementing a validation check to ensure `_value > 0` in order to prevent unexpected behavior.

_**Update:** Resolved in [pull request #1388](https://github.com/matter-labs/era-contracts/pull/1388) at commits [aa15081](https://github.com/matter-labs/era-contracts/pull/1388/commits/aa1508190f2c10e3dacea86ec5a0ef1e04b931fb) and [a44fc21](https://github.com/matter-labs/era-contracts/pull/1388/commits/a44fc21f93aafe089606e5ae8bbe2205300c02f3). The `NonceIncreaseError` custom error has also been modified to inform about the minimum possible value too, which is 1._

### Unreachable Code

The helper function [`MAX_MODEXP_INPUT_FIELD_SIZE`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/evm-emulator/EvmEmulatorFunctions.template.yul#L140) restricts each input field (`Bsize`, `Esize`, `Msize`) to a maximum of 32 bytes. If any of these exceed 32, `modexpGasCost` exits early by returning [`MAX_UINT64()`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/evm-emulator/EvmEmulatorFunctions.template.yul#L1012).

Despite this restriction, the function contains a `switch` that branches on whether [`Esize > 32`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/evm-emulator/EvmEmulatorFunctions.template.yul#L1031), with logic intended to handle larger exponents. However, this branch is currently unreachable due to the enforced limit, making it effectively dead code.

This may be intentional for future-proofing, but as it stands, the logic adds unnecessary complexity.

Consider adding clear documentation explaining why this code path is currently unreachable, and under what future conditions it may become relevant.

_**Update:** Resolved in [pull request #1385](https://github.com/matter-labs/era-contracts/pull/1385). The Matter Labs team stated:_

> _This is intentional indeed - `MAX_MODEXP_INPUT_FIELD_SIZE` can be arbitrary, and in the current version it is 32 bytes. However, more comments have been added._

Notes & Additional Information
------------------------------

### Inconsistent Interface Between Sibling Repositories

The current [pull request #1359](https://github.com/matter-labs/era-contracts/pull/1359) in the `era-contracts` repository is linked to [pull request #3646](https://github.com/matter-labs/zksync-era/pull/3646) in the `zksync-era` repository through [pull request #1299](https://github.com/matter-labs/era-contracts/pull/1299) in the former. Both repositories include changes to the `INonceHolder` interface, but the modifications are not aligned:

*   The [pragma directive](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/interfaces/INonceHolder.sol#L3) is floating in both repositories but uses a [different version](https://github.com/matter-labs/zksync-era/blob/0c07301c387a86b878bb57304f18e583d562efd4/core/tests/ts-integration/contracts/custom-account/interfaces/INonceHolder.sol#L3) as the base.
*   The [`ValueSetUnderNonce` event](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/interfaces/INonceHolder.sol#L14) and the [`isNonceUsed` function](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/interfaces/INonceHolder.sol#L44) are not present in the [`zksync-era` version of the interface](https://github.com/matter-labs/zksync-era/blob/0c07301c387a86b878bb57304f18e583d562efd4/core/tests/ts-integration/contracts/custom-account/interfaces/INonceHolder.sol).
*   Conversely, the [`setValueUnderNonce` and `getValueUnderNonce` functions](https://github.com/matter-labs/zksync-era/blob/0c07301c387a86b878bb57304f18e583d562efd4/core/tests/ts-integration/contracts/custom-account/interfaces/INonceHolder.sol#L25-L28) exist only in the `zksync-era` repository and have been removed from the [`era-contracts` version](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/interfaces/INonceHolder.sol).

Although the `zksync-era` version is intended for testing purposes, maintaining consistency across both repositories is important to ensure correctness, reduce confusion, and preserve testing robustness.

Consider aligning the `INonceHolder` interface definitions in both repositories, or clearly documenting their divergence if intentional.

_**Update:** Resolved at commit [e911061](https://github.com/matter-labs/zksync-era/pull/3646/commits/e9110610796828e3849daefd0a4ed30dfc57294c) on the zksync-era repository. Now both repositories are consistent on the `INonceHolder` interface definition._

### Misleading Documentation

Throughout the codebase, there are instances where existing comments may be misleading or outdated. In particular:

*   The default ordering system has been updated from `Sequential` to `KeyedSequential`, but several comments still reference the previous default. This inconsistency appears in the [`ContractDeployer.sol`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/ContractDeployer.sol) contract on lines [312](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/ContractDeployer.sol#L312), [437](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/ContractDeployer.sol#L437), and [465](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/ContractDeployer.sol#L465).
*   On [line 26](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/ContractDeployer.sol#L26) of `ContractDeployer.sol`, the comment states that the `AccountInfo` value will be zero for EOAs and simple contracts. This could be clarified to specify that a zero value corresponds to the default `None` account abstraction version and the `KeyedSequential` nonce ordering.

Consider updating these inline comments to accurately reflect the current system behavior. Doing so will improve readability and reduce the risk of confusion during future development or review.

_**Update:** Resolved in [pull request #1399](https://github.com/matter-labs/era-contracts/pull/1399) at commit [ffcf289](https://github.com/matter-labs/era-contracts/pull/1399/commits/ffcf2892df66452ff65aa3d40fd5337f49465059)._

### Mismatch Between Interface and Implementation

Throughout the codebase, there are some mismatches between interfaces and their associated implementations.

The `updateNonceOrdering` function within the [`IContractDeployer` interface](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/interfaces/IContractDeployer.sol#L116-L117) and its implementation in the [`ContractDeployer` contract](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/ContractDeployer.sol#L77-L82) present the following differences:

*   The interface contains a named argument, while the implementation omits it to indicate that the function should not be used, as it will always revert.
*   The implementation docstring states that the nonce ordering system cannot be updated, while the interface suggests that it can.

The `NonceHolder` contract introduces a new [`getKeyedNonce` function](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L57-L68) that is not included in the associated [`INonceHolder` interface](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/interfaces/INonceHolder.sol). Additionally, the function ordering in the interface does not match the implementation.

Consider applying the following consistency improvements:

*   Remove the parameter name from the interface version of `updateNonceOrdering` to align with the implementation.
*   Update the interface docstring to reflect that the function is deprecated and will always revert.
*   Add the `getKeyedNonce` function to the `INonceHolder` interface.
*   Align function ordering in interfaces with the corresponding implementation contracts.

These changes would help reduce confusion and avoid unexpected usage patterns across the codebase.

_**Update:** Partially resolved in [pull request #1392](https://github.com/matter-labs/era-contracts/pull/1392) at commit [58acf0c](https://github.com/matter-labs/era-contracts/pull/1392/commits/58acf0c44518d70fde17aecba9275ec62d422189). The Matter Labs team stated:_

> _The bullet points 1-3 were fixed. Reordering function declarations introduces merge conflicts that are not worth the minor readability gain._

### Inconsistent Handling of Nonce Types

Throughout the codebase, there are instances where nonce values are handled inconsistently, leading to ambiguity in interpretation and usage. In particular:

*   The [`getKeyedNonce` function](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L62) from the `NonceHolder` contract returns data from the [`rawNonce` mapping](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L64) when the [key is zero](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L63), but returns data from the [`keyedNonces` mapping](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L67) when a non-zero key is provided. However, in the [`isNonceUsed`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L207-L215) function, this logic is not consistently applied—passing a zero key results in querying both the `keyedNonces` and `rawNonce` mappings, instead of only `rawNonce`.
*   The `incrementMinNonceIfEquals` function uses the `_expectedNonce` input as both a [combined keyed-type nonce](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L131) and a [`minNonce`\-type nonce](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L140), resulting in dual interpretation of the same value.

Although these inconsistencies do not currently introduce security vulnerabilities, having multiple ways to interpret or validate the same data increases the potential for future bugs, reduces clarity, and complicates maintenance.

Consider unifying the logic for handling nonce types across functions to improve consistency and code readability.

_**Update:** Resolved in [pull request #1395](https://github.com/matter-labs/era-contracts/pull/1395) at commit [e04af13](https://github.com/matter-labs/era-contracts/pull/1395/commits/e04af13ea377901d610ddb8f3e3e6fe846b215ad) and in [pull request #1403](https://github.com/matter-labs/era-contracts/pull/1403), at commit [6eb1fb2](https://github.com/matter-labs/era-contracts/pull/1403/commits/6eb1fb2bb21c7804dc989727b4be7a35ae47b391)._

### Function Visibility Overly Permissive

Throughout the codebase, there are various functions with visibility levels that are more permissive than necessary:

*   The [`getKeyedNonce`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L62-L68) function in `NonceHolder.sol` is marked `public` but could be limited to `external`.
*   The [`getRawNonce`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L74-L77) function in `NonceHolder.sol` is marked `public` but could be limited to `external`.
*   The [`increaseMinNonce`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L82-L101) function in `NonceHolder.sol` is marked `public` but could be limited to `external`.
*   The [`_splitRawNonce`](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L237-L240) function in `NonceHolder.sol` is marked `internal` but could be limited to `private`.

Consider restricting function visibility to the minimum necessary in order to better reflect intended usage and potentially reduce gas costs.

_**Update:** Resolved in [pull request #1391](https://github.com/matter-labs/era-contracts/pull/1391)._

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to report vulnerabilities. This practice allows the code owners to define a preferred communication channel for responsible disclosure, reducing the risk of miscommunication or missed reports. Additionally, in cases where third-party libraries are used, maintainers can easily reach out with mitigation guidance if needed.

Throughout the codebase, there are contracts that do not include a security contact:

*   The [`IContractDeployer` interface](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/interfaces/IContractDeployer.sol).
*   The [`INonceHolder` interface](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/interfaces/INonceHolder.sol).

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` tag is recommended, as it has been adopted by tools like [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and repositories such as [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in [pull request #1399](https://github.com/matter-labs/era-contracts/pull/1399) at commit [bfbe2a8](https://github.com/matter-labs/era-contracts/pull/1399/commits/bfbe2a8c26c9e66f8d7591ed720a5faeb33cc713)._

### Functions Updating State Without Event Emissions

Throughout the codebase, multiple instances of functions update contract state without emitting corresponding events. Examples include:

*   The [`increaseMinNonce` function](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L82-L101) in `NonceHolder.sol`
*   The [`incrementMinNonceIfEquals` function](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L130-L153) in `NonceHolder.sol`
*   The [`incrementMinNonceIfEqualsKeyed` function](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L159-L174) in `NonceHolder.sol`
*   The [`incrementDeploymentNonce` function](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L189-L201) in `NonceHolder.sol`

Consider emitting events for all state-changing operations to improve transparency, support off-chain indexing, and reduce the risk of silent state mutations that may be difficult to track or audit later.

_**Update:** Acknowledged, not resolved. The Matter Labs team stated:_

> _Since EVM does not emit events for nonce increments, it was decided to not emit them in `NonceHolder.sol` to not make developers rely on them. Custom AA accounts may still decide to emit them from their own contracts, if they should need them._

### Unused Event

In the `INonceHolder` interface, the [`ValueSetUnderNonce` event](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/interfaces/INonceHolder.sol#L14) is defined but is not used throughout the codebase.

Consider removing the unused event to improve code readability and reduce unnecessary interface clutter.

_**Update:** Resolved in [pull request #1390](https://github.com/matter-labs/era-contracts/pull/1390)._

### Redundant Return Statements

To improve the readability of the codebase, it is recommended to remove redundant return statements from functions that have named returns.

Throughout the codebase, there are multiple instances of redundant return statements. Some of them fall outside of the current audit scope; however, it is beneficial to highlight them as well:

*   [Line 41](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/ContractDeployer.sol#L41) from the `getAccountInfo` function in `ContractDeployer.sol` should assign to the `info` return variable.
    
*   [Line 217](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/ContractDeployer.sol#L217) from the `precreateEvmAccountFromEmulator` function in `ContractDeployer.sol` is redundant.
    
*   [Line 417](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/ContractDeployer.sol#L417) in function `_evmDeployOnAddress` in `ContractDeployer.sol` should assign the final value to the `constructorReturnEvmGas` return variable.
    
*   [Lines 473-480](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/ContractDeployer.sol#L473-L480) from the `_performDeployOnAddressEVM` function should assign the internal function output to the `constructorReturnEvmGas` return variable in `ContractDeployer.sol`.
    
*   [Line 180](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L183) from the `getDeploymentNonce` function in `NonceHolder.sol` is redundant.
    

Consider removing the redundant return statement in functions with named returns to improve the readability of the contract.

_**Update:** Resolved in [pull request #1394](https://github.com/matter-labs/era-contracts/pull/1394)._

### Implicit Casting

The lack of explicit casting hinders code readability and makes the codebase hard to maintain and error-prone.

The `nonceValue` parameter is implicitly [cast](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/contracts/NonceHolder.sol#L119) to `uint256` from `uint64` within the `_combineKeyedNonce` function.

Consider explicitly casting all integer values to their expected type to improve readability and reduce the risk of subtle bugs in future updates.

_**Update:** Resolved in [pull request #1393](https://github.com/matter-labs/era-contracts/pull/1393)._

### Inconsistent Variable Naming

Throughout the codebase, all variables follow the "camelCase" naming convention. However, when calculating the gas cost for the `Modexp` precompile, there are some instances where this convention is violated.

When [retrieving](https://github.com/matter-labs/era-contracts/blob/cc1619cfb03cc19adb21a2071c89415cab1479e8/system-contracts/evm-emulator/EvmEmulatorFunctions.template.yul#L999-L1001) the base, exponent, and modulus lengths in bytes, these variables are named `Bsize`, `Esize`, and `Msize`, respectively.

Consider enforcing consistency in the naming convention used across all variables by renaming these to `bSize`, `eSize`, and `mSize`.

_**Update:** Resolved in [pull request #1386](https://github.com/matter-labs/era-contracts/pull/1386)._

Conclusion
----------

This audit focused on the implementation of the `ModExp` precompile gas cost calculation, the adjustments in the Emulator to avoid unnecessary bytecode copying via pointer usage, and the introduction of semi-abstracted nonces in the system contracts in accordance to [EIP-4337](https://eips.ethereum.org/EIPS/eip-4337#semi-abstracted-nonce-support).

During the audit, one critical and one high-severity issue were identified. In addition, several issues related to optimization, insufficient checks, low test coverage and best practices were identified that, while not immediately threatening to system security, could impact performance, maintainability, and gas efficiency.

Despite these findings, communication with the team was notably fast and friendly, and the modular nature of the code indicates an overall organized approach. That said, there is considerable room for improvement in areas such as comprehensive documentation of recent changes and more robust testing strategies. Addressing these concerns will better position the project for future upgrades.