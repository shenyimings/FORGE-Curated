\- August 5, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

**Type:** DeFi  
**Timeline:** May 14, 2025 → May 16, 2025**Languages:** Solidity

**Findings**Total issues: 19 (18 resolved)  
Critical: 0 (0 resolved) · High: 1 (1 resolved) · Medium: 2 (2 resolved) · Low: 4 (4 resolved)

**Notes & Additional Information**12 notes raised (11 resolved)

Scope
-----

OpenZeppelin audited the `src/BitVMBridge.sol` file in the [fiamma-chain/bitvm-bridge-contracts](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad) repository at commit [935e2cb](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad).

System Overview
---------------

The Fiamma Bridge is a Bitcoin bridge leveraging the BitVM2 framework to enable transfers of Bitcoin (BTC) to and from programmable sidechains like Ethereum. It aims to unlock Bitcoin’s potential in DeFi ecosystems by providing a solution for cross-chain asset transfers.

The Fiamma Bridge facilitates two primary operations: **PEG-IN** and **PEG-OUT**, which respectively stand for transferring BTC from Bitcoin to a sidechain and transferring tokenized BTC back to Bitcoin.

### PEG-IN Process

The following steps will be executed to successfully bridge BTC from the Bitcoin network to another chain:

1.  A user calls the bridge's server to initiate a PEG-IN request, including their Bitcoin public key and amount to transfer in the call.
2.  The server checks whether the user's amount is valid and returns a unique Bitcoin address (a multisig address generated using the user's public key and the committee's public key). This address is then shared with the Bridge Covenant Committee (BCC) using pre-signed transactions to define spending rules.
3.  The user constructs a PEG-IN transaction, transfers the amount to the address generated in step 2, and submits the raw PEG-IN transaction to the bridge's server.
4.  The server validates the PEG-IN transaction by enforcing that both the amount and recipient address are correct, and subsequently broadcasts the PEG-IN transaction to the Bitcoin blockchain.
5.  When the PEG-IN transaction is mined, the server calls the bridge contract to mint the wrapped BTC in a 1:1 ratio to the user's address on the receiving chain.

### PEG-OUT Process

To successfully withdraw the wrapped BTC to the Bitcoin chain, the following steps will be executed:

1.  A wrapped BTC holder calls the `burn` function on the `BitVMBridge` contract, passing in a custom Bitcoin address they want to transfer their BTC to.
2.  The operators' server will listen to the `Burn` event emitted in the first step. This event includes the sender, the Bitcoin address, and the value to send to the recipient address.
3.  Finally, based on the previous event, the operators will send the amount of BTC burnt in step 1 to the recipient BTC address.

Security Model and Trust Assumptions
------------------------------------

The operational integrity of the Fiamma bridge is dependent on various external components.

1.  The bridge's server is responsible for validating user's input to initiate a PEG-IN transaction, generate a corresponding multisig address shared with the BCC following proper spending rules, and populate the user's PEG-IN transaction accordingly.
    
    The bridge's server is also responsible for calling the `mint` function on the `BitVMBridge` contract using the correct `to` recipient value which is defined by the user off-chain. Currently, the `to` address can be arbitrarily set by the server and cannot be checked by the contract for its correctness.
    
2.  Operators are responsible for finalizing PEG-OUT transactions after a user calls the `burn` function on the `BitVMBridge` contract, and then transfer the amount of BTC to the recipient as defined in the `burn` function's parameters.
    
3.  The Fiamma bridge's incentivization and penalization models are implemented on Bitcoin. It is assumed that these components have been audited by a third party and work as expected.
    
4.  The `BtcTxVerifier` contract, alongside its dependencies such as the entire `btc-light-client` library, is expected to be reliably maintained and accurately validate Bitcoin transactions, ensuring correct outcomes.
    

It is important to note that, within the current design, users need to fully trust the bridge's server and the operators. For example, they cannot directly recover their BTC or replay transactions when they fail.

### Privileged Roles

The `BitVMBridge` contract is governed by an owner defined during deployment. The owner is able to execute the following functions:

*   `setParameters`: This function allows for setting the following sensitive parameters:
    *   `maxPegsPerMint`: The maximum number of pegs allowed to execute when calling `mint`.
    *   `maxBtcPerMint` and `minBtcPerMint`: The maximum and minimum amount of BTC allowed when minting.
    *   `maxBtcPerBurn` and `minBtcPerBurn`: The maximum and minimum amount allowed when burning.
*   `mint`: The function executed to finalize the PEG-IN process.
*   `setMinConfirmations`: The minimum amount of block confirmations for a PEG-IN transaction on Bitcoin.
*   `setBtcTxVerifier`: The contract that verifies Bitcoin transaction proofs.

The owner of this contract is assumed to act in the best interests of the users of the bridge. 

High Severity
-------------

### Malicious Owner Can Mint Wrapped BTC From Arbitrary Bitcoin Transactions

To submit a PEG-IN transaction, a user needs to call the bridge's off-chain component to create a PEG-IN request. For valid requests, the bridge server will return a unique Bitcoin address that represents a multisig address generated using the user's public key and the committee's public key. The user then constructs a PEG-IN transaction and transfers the amount to the aforementioned address, and, subsequently, submits a raw PEG-IN transaction to the bridge server.

The bridge server will check the validity of the constructed PEG-IN transaction, ensure that both the amount and address are correct, and finally broadcast the PEG-IN transaction to the Bitcoin blockchain. When the PEG-IN transaction is mined, the server will pick it up and call the [`mint` function](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L96) of the `BitVMBridge` contract to mint the wrapped BTC to the user's address. The check in [line 118](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L118) will validate the Bitcoin transaction by ensuring that the transaction is valid and was mined and passed a minimum amount of confirmation blocks.

However, the transaction's destination on Bitcoin is never checked. This means that the owner of the `BitVMBridge` contract can call the `mint` function at any time, using the data from any Bitcoin transaction that passed a minimum number of blocks, and mint its value to a random address. This allows the owner to virtually mint as many wrapped BTC as had been transferred in the past.

Consider implementing a mechanism which allows for verifying that the transaction's destination on Bitcoin is the correct address that represents the multisig address generated by the bridge's server. This also helps avoid catastrophic damage in case the owner gets compromised.

_**Update:** Resolved in [pull request #24](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/24) at commit [58dcf14](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/24/commits/58dcf141e587f132d4fe52c52a9e96f443a11aac). However, since the fix introduces a new BLS cryptographic library, we have assumed that the underlying cryptographic implementation is secure and functions as expected. Please note that this BLS library was not audited by OpenZeppelin._

Medium Severity
---------------

### Potential Loss of Wrapped BTC

In the `BitVMBridge` contract, the [`burn` function](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L137) is used to initiate the PEG-OUT process. This function is a permissionless function that allows a wrapped BTC holder to burn their tokens. The relayer will pick up this action and initiate a transaction on the Bitcoin chain to release the BTC to the `_btc_addr` defined in [line 138](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L138). However, the `_btc_addr` parameter is a random string that is not being validated. This allows for potential user error, which can result in the loss of funds. Furthermore, there is no revert mechanism that allows a user to retrieve their lost funds in case they pass an invalid address.

Consider validating the `_btc_addr` input value to prevent user input errors. Alternatively, if this check is performed by an off-chain component, consider adding a safe mechanism to allow a user to retrieve their assets and avoid losing their funds.

_**Update:** Resolved in [pull request #10](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/10) at commit [227a418](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/10/commits/227a4183b021fc2fb61780fe95c7df0fafdf7544)._

### Malicious Owner Can Mint to a Random Recipient

The [`mint` function](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L96) is used to finalize the PEG-IN process and mint wrapped BTC on the destination chain to a predefined recipient. However, the recipient's [`to` address](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L100) is not being verified to be tied to the initial PEG-IN transaction on Bitcoin. This allows a malicious owner to mint any valid Bitcoin transaction's value to a random address.

Consider implementing a mechanism that allows verifying that the `to` address is tied to the initial PEG-IN transaction in the `mint` function of the `BitVMBridge` contract. Additional text

_**Update:** Resolved in [pull request #8](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/8) at commit [923d3ff](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/8/commits/923d3fff27df9de9d940a8fbc5f741c97ae3c0a6). However, since the fix is being implemented within the `btc-light-client` library, we assumed that the library itself is safe and functioning as expected. The `btc-light-client` library was not audited by OpenZeppelin._

Low Severity
------------

### Functions Updating State Without Event Emissions

Within `BitVMBridge.sol`, multiple instances of functions updating the state without an event emission were identified:

*   The [`setParameters` function](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L63-L80)
*   The [`setMinConfirmations` function](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L149-L151)
*   The [`setBtcTxVerifier` function](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L153-L155)

Consider emitting events whenever state changes occur, especially for sensitive configurations, and ensure that the new value is actually different from the current one. This would improve code clarity and reduce the risk of errors.

_**Update:** Resolved in [pull request #5](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/5) at commit [d35e1ea](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/5/commits/d35e1ea417c910d92ecd9f2b2ed8c4535485231c)._

### Missing Docstrings

The `BitVMBridge.sol` file currently has very limited documentation. For instance, the [`BitVMBridge` contract](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L10-L156), its functions, state variables, and custom errors lack comprehensive documentation.

Consider thoroughly documenting all contracts and their functions (and their parameters) that are part of any contract's public API. Functions implementing sensitive functionality, even if not public, should be clearly documented as well. The same approach should be applied to custom errors and events, including their parameters. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in [pull request #6](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/6) at commit [6c52baa](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/6/commits/6c52baa053ba4332df926f9d9930d73160fdd6a0)._

### Potential Loss of Ownership During Transfers

The [`BitVMBridge` contract](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol) inherits the [`OwnableUpgradeable`](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L12) contract to handle its ownership logic. However, the `OwnableUpgradeable` transfers ownership in a single step. This could pose a risk, as setting an incorrect address would result in permanently losing ownership of the contract, with no way of recovering it.

Consider inheriting OpenZeppelin's `Ownable2StepUpgradeable` contract to leverage the safer two-step ownership transfer logic.

_**Update**: Resolved in [pull request #7](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/7) at commit [923d3ff](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/8/commits/923d3fff27df9de9d940a8fbc5f741c97ae3c0a6) and [pull request #27](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/27) at commit [b8ecdd7](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/27/commits/b8ecdd784bd23573aa3383ff1bff748a020d4aaf)._

### Missing `_disableInitializers`

The [`BitVMBridge` contract](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L10) is deployed behind a transparent proxy to enable upgrades and allow the proxy to initialize the contract by calling the `initialize` function from `Initializable`. However, the contract omits a call to `_disableInitializers()` in its constructor, which potentially allows attackers to directly initialize the logic contract.

Consider adding `_disableInitializers()` to the constructor of `BitVMBridge.sol` to prevent unauthorized direct initialization of the logic contract.

_**Update:** Resolved in [pull request #9](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/9) at commit [a4ab9da](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/9/commits/a4ab9da8086dbc3db979dfdee47df86079a11d21)._

Notes & Additional Information
------------------------------

### Superfluous Input Validation

In the `BitVMBridge` contract, the [`mint` function](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L96) is used in the last step of the PEG-IN process. This function will mint wrapped BTC to the user's address based on a valid transaction on the Bitcoin chain. This function takes in an array of `pegs` of type [`Peg` struct](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/interface/IBtcPeg.sol#L6-L14). The `mint` function then loops over the `pegs` array and subsequently validates each `peg`'s inputs. However, the `value` validation in [line 101](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L101) is superfluous since the transaction is already being validated by the `btcTxVerifier.verifyPayment` function in [line 118](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L118).

Consider removing the `value` validation since it is being performed by another function already. In addition, consider removing the [`value` field](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/interface/IBtcPeg.sol#L8) from the `Peg` struct to avoid leaving unused fields, making the code more readable and concise.

_**Update:** Resolved in [pull request #11](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/11) at commit [48f5290](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/11/commits/48f529013b4eccb67aab8a4c46aa116f7ae36cb3)._

### Unchecked State Variable Input

In the `BitVMBridge` contract, the [`initialize` function](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L47) is used to assign values to the contract's state variables. However, while some input parameters undergo validation, `_btcTxVerifierAddr` and `_minConfirmations` are not being validated.

Consider validating these input parameters as well to prevent the bridge from operating with unset or potentially erroneous parameters. The same validation logic could be incorporated into the [`setMinConfirmations`](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L149) and [`setBtcTxVerifier`](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L153) functions. Subsequently, these setter functions could then be employed within the `initialize` function to configure the contract's parameters, ensuring that the validation checks are applied consistently.

_**Update:** Resolved in [pull request #12](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/12) at commit [2e166f4](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/12/commits/2e166f42e81c98327c95f70c5c22d8fda1190a28) and in [pull request #25](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/25) at commit [5bc3464](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/25/commits/5bc34644590f1149738c142c8996cf1b9b8c5a1c)._

### Duplicated Input Validation

In the [`initialize` function](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L47), the `_owner` parameter is ensured to be different from `address(0)`. However, this check is already performed in the [`__Ownable_init_unchained` function](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/fa525310e45f91eb20a6d3baa2644be8e0adba31/contracts/access/OwnableUpgradeable.sol#L56) during initialization. Furthermore, the `InvalidPegAddress` error thrown in case the function reverts is the incorrect error.

Consider removing the check in [line 53](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L) to avoid code duplication.

_**Update:** Resolved in [pull request #13](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/13) at commit [fac96b7](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/13/commits/fac96b79571243282890bb085a5b4a5947075cbd)._

### Outdated and Unpinned Solidity Version

The `BitVMBridge.sol` file has the [`solidity ^0.8.13`](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L2) floating pragma directive. Pragma directives should be fixed to clearly identify the Solidity version with which the contract will be compiled. Moreover, this Solidity version is outdated. Using an outdated and unpinned version of Solidity can lead to vulnerabilities and unexpected behavior in contracts.

Consider taking advantage of the [latest Solidity version](https://github.com/ethereum/solidity/releases) to improve the overall readability and security of the codebase. Regardless of which Solidity version is used, consider pinning the version to prevent bugs due to incompatible future releases.

_**Update:** Resolved in [pull request #14](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/14) at commit [769b1ff](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/14/commits/769b1ff3124178a7cef1d94e768ec5e8485cd52a)._

### Custom Errors in `require` Statements

Since Solidity [version `0.8.26`](https://soliditylang.org/blog/2024/05/21/solidity-0.8.26-release-announcement/), custom error support has been added to `require` statements. Initially, this feature was only available through the IR pipeline, but Solidity [`0.8.27`](https://soliditylang.org/blog/2024/09/04/solidity-0.8.27-release-announcement/) extended its support to the legacy pipeline as well.

The `BitVMBridge.sol` contains multiple instances of `if-revert` statements that could be replaced with `require` statements. For instance, [line 54](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L54) can be replaced with:

`require(_btcPegAddr  !=  address(0),  InvalidPegAddress());` 

For conciseness and gas savings, consider replacing `if-revert` statements with `require` ones.

_**Update:** Resolved in [pull request #15](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/15) at commit [81817b7](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/15/commits/6e595800917235efe556ee3b7f7cb3a6eec072bc)._

### Unused Error

In `BitVMBridge.sol`, the [`InvalidBtcAddress` error](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L41) is unused.

To improve the overall clarity, intentionality, and readability of the codebase, consider either using or removing any currently unused errors.

_**Update**: Acknowledged, not resolved._

### State Variable Visibility Not Explicitly Declared

Within `BitVMBridge.sol`, the [`minted` state variable](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L25) lacks an explicitly declared visibility.

For improved code clarity, consider always explicitly declaring the visibility of state variables, even when the default visibility matches the intended visibility.

_**Update:** Resolved in [pull request #17](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/17) at commit [81817b7](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/17/commits/81817b702f7b7d668ad55191791ec76f6c72487d)._

### Non-explicit Imports Are Used

The use of non-explicit imports in the codebase can reduce clarity and may lead to naming conflicts between locally defined and imported variables. This becomes especially relevant when multiple contracts are present within the same Solidity file or when inheritance chains grow longer.

In `BitVMBridge.sol`, [global imports](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L4-L8) are currently being used. Following the principle that clearer code is better code, consider adopting the named import syntax (`import {A, B, C} from "X"`) to explicitly declare which contracts, interfaces, structs, or other elements are being imported.

_**Update:** Resolved in [pull request #18](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/18) at commit [c6a98c6](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/18/commits/c6a98c6ee823ec197a4f677243ffa216533cfb21)._

### Missing Named Parameters in Mapping

Since [Solidity 0.8.18](https://github.com/ethereum/solidity/releases/tag/v0.8.18), developers can utilize named parameters in mappings. This means that mappings can take the form of `mapping(KeyType KeyName? => ValueType ValueName?)`. This updated syntax provides a more transparent representation of a mapping's purpose.

In the [`minted`](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L25) state variable of the `BitVMBridge` contract, the mapping does not have any named parameters.

Consider adding at least one named parameter to the key type in the aforementioned mapping in order to improve the readability and maintainability of the codebase.

_**Update:** Resolved in [pull request #19](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/19) at commit [de6f68f](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/19/commits/de6f68fdb873c07c64fdb3ed1b42ea5092dcb57b)._

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

The [`BitVMBridge` contract](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol) does not have a security contact.

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in [pull request #20](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/20) at commit [5f7b386](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/20/commits/5f7b3869d1c207b8e54970795538693805d0bf4a)._

### Function Visibility Overly Permissive

Within `BitVMBridge.sol`, multiple instances of functions with unnecessarily permissive visibility were identified:

*   The [`getMinted`](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L89-L94) function in `BitVMBridge.sol` with `public` visibility could be limited to `external`.
*   The [`mint`](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L96-L135) function in `BitVMBridge.sol` with `public` visibility could be limited to `external`.
*   The [`burn`](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L137-L147) function in `BitVMBridge.sol` with `public` visibility could be limited to `external`.

To better convey the intended use of functions and to potentially realize some additional gas savings, consider changing a function's visibility to be only as permissive as required.

_**Update:** Resolved in [pull request #21](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/21) at commit [c76970e](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/21/commits/c76970eaf4a3270dbce72f118f50ac1ce4a18235)._

### Inconsistent Order of Functions

The [`BitVMBridge` contract](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol) has an inconsistent order of functions. For instance, the setter functions [\[1\]](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L63-L80) [\[2\]](https://github.com/fiamma-chain/bitvm-bridge-contracts/blob/935e2cbd1b5d1060439045b74ace6b2f506a25ad/src/BitVMBridge.sol#L149-L155) do not follow a consistent order and appear at different places in the contract.

To improve the project's overall legibility, consider standardizing ordering throughout the codebase. Alternatively, consider following the recommendations by the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-layout) ([Order of Functions](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-functions)).

_**Update:** Resolved in [pull request #22](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/22) at commit [2682536](https://github.com/fiamma-chain/bitvm-bridge-contracts/pull/22/commits/2682536ef38c86443993db96470046234c859f1e)._

Conclusion
----------

The Fiamma Bridge is a Bitcoin-to-sidechain protocol built on the BitVM2 framework, enabling secure transfers of BTC between the Bitcoin network and programmable sidechains. Our audit identified a high-severity vulnerability that could have allowed the minting of unbacked wrapped BTC due to the absence of a strict link between the original Bitcoin transaction and the recipient on Ethereum. This issue has since been addressed by enforcing a verifiable connection between the Bitcoin destination script and the corresponding Ethereum address.

In addition to the critical issue, several medium- and low-severity findings were addressed. These included concerns around input validation, potential asset loss due to user error, and inadequate restrictions on privileged operations. We also provided recommendations to improve code clarity, upgrade safety, and documentation standards.

Given the bridge’s reliance on off-chain components and privileged roles, we emphasize the importance of minimizing trust assumptions through stronger on-chain validation to enhance system resilience and scalability.

Finally, we found the current test suite to be insufficient for ensuring system reliability. We strongly recommend expanding test coverage to include common usage patterns, edge cases, and failure scenarios.

The Fiamma team was highly collaborative and responsive throughout the audit, and we appreciate their proactive approach to addressing the issues identified.