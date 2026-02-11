\- May 12, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

**Type:** DeFi  
**Timeline:** December 12, 2024 → December 20, 2024**Languages:** Solidity

**Findings**Total issues: 11 (10 resolved)  
Critical: 1 (1 resolved) · High: 0 (0 resolved) · Medium: 0 (0 resolved) · Low: 5 (4 resolved)

**Notes & Additional Information**3 notes raised (3 resolved)

Scope
-----

We targeted the `across-protocol/contracts` repository with three different goals:

1) At [commit 7f0cedb](https://github.com/across-protocol/contracts/tree/7f0cedb5a88aefeecbf9c640447263d87a6a7693) in the `master` branch, we reviewed the ERC-7683 implementation with a focus on the predictable relay hashes feature that was first introduced in [pull request #639](https://github.com/across-protocol/contracts/pull/639).

2) At [commit 401e24c](https://github.com/across-protocol/contracts/tree/401e24ccca1b3af919dd521e58acd445297b65b6) of the `svm-dev` branch, we audited the changes made to the following files:

`contracts/
├── SpokePool.sol
├── SpokePoolVerifier.sol
├── SwapAndBridge.sol
├── erc7683/
│   ├── ERC7683OrderDepositor.sol
│   ├── ERC7683OrderDepositorExternal.sol
│   ├── ERC7683Permit2Lib.sol
├── external/interfaces/
│   ├── CCTPInterfaces.sol
├── interfaces/
│   ├── V3SpokePoolInterface.sol
├── libraries/
│   ├── AddressConverters.sol
│   ├── CircleCCTPAdapter.sol
├── permit2-order/
│   ├── Permit2Depositor.sol` 

3) At [pull request #805](https://github.com/-protocol/contracts/pull/805) we reviewed the changes as part of the fix review process of this audit.

System Overview
---------------

The Protocol enables instant token transfers multiple blockchain networks. At the core of the protocol is the `HubPool` contract on the Ethereum mainnet, which serves as the central liquidity hub and cross-chain administrator for all contracts within the system. This pool governs the `SpokePool` contracts deployed on various networks that either initiate token deposits or serve as the final destination for transfers. A more detailed overview of the Protocol and its various components can be found in our previous reports.

The audited changes mainly center around the added compatibility with the Solana network. To achieve this, the following changes have been made:

*   Many `address` data types have been converted to `bytes32` to make them more general and compatible with Solana.
*   A `repaymentAddress` parameter has been added to the `fill` functions so that relayers can specify different addresses.
*   There was an edge case in which tokens with blacklists might prevent refund-related transfers from being executed. For this reason, transfers within a bundle that revert are now accounted into a new mapping which allows relayers to retrieve refunds that could not be transferred as part of a normal relayer refund call.

Adding compatibility for the Solana network also comprises other pull requests and files. However, for this audit, we exclusively focused on the changes required to the existing Solidity files mentioned in the scope above.

Critical Severity
-----------------

### Anyone Can Lock Relayer Refunds and Contract Can Be Drained

The `claimRelayerRefund` [function](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/SpokePool.sol#L1265) is meant to give relayers the option to claim outstanding repayments. This can happen in different edge cases, like blacklists not allowing token transfers. In such cases, the relayer can call this function and specify a different `refundAddress` to claim their funds.

The function [first](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/SpokePool.sol#L1266) reads the current outstanding refund from the `relayerRefund` mapping using the `l2TokenAddress` and `msg.sender` keys. If this value is greater than 0 then it is [transferred](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/SpokePool.sol#L1269) to the `refundAddress` and the appropriate event is emitted.

Before transferring out the tokens, the mapping value is [set](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/SpokePool.sol#L1268) to 0 for correct accounting. However, the key used to reset the mapping value is `refundAddress` and not `msg.sender`. This opens the door for any relayer with a small refund amount to zero out any other relayer's refund by specifying their `refundAddress`, effectively making the relayers lose their refunds. In addition, since the original mapping value is never reset, a malicious relayer can exploit this by repeatedly calling the function to drain the entire balance of the `l2TokenAddress` contract.

Consider using the proper `msg.sender` key instead of `refundAddress` to correctly set the refund amount to zero.

_**Update:** Resolved in [pull request #826](https://github.com/across-protocol/contracts/pull/826). The code correctly resets the mapping value now._

Low Severity
------------

### Function Can Be Declared `external`

The `claimRelayerRefund` [function](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/SpokePool.sol#L1265) of the `SpokePool` contract is declared as `public` but can be defined as `external` instead.

In order to improve overall code quality and to improve gas consumption, consider changing the function visibility to `external`.

_**Update:** Resolved in [pull request #827](https://github.com/across-protocol/contracts/pull/827)._

### `_destinationSettler` Can Return Zero Address

In the `_resolveFor` function of the `ERC7683OrderDepositor` contract, the value returned from the `internal` `_destinationSettler` function is [not validated](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/erc7683/ERC7683OrderDepositor.sol#L245) to be non-zero. The `_destinationSettler` function returns the settler contract for the destination chain. If this value has not been set, the default value will be returned and passed to the [`fillInstructions`](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/erc7683/ERC7683OrderDepositor.sol#L245) field of the `resolvedOrder` parameter.

Consider adding the requirement that the `_destinationSettler` value used in the `FillInstruction` struct of the resolved order cannot be the zero address.

_**Update:** Resolved in [pull request #834](https://github.com/across-protocol/contracts/pull/834)._

### Incorrect Right Shift in `AddressConverters` Library

The `toAddress` function of the `AddressConverters` library shifts right [by 192](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/libraries/AddressConverters.sol#L11) bits. However, it should shift right by 160 bits instead to correctly check that the upper 96 bits of `_bytes32` are actually empty.

Consider updating the `toAddress` function so that it shifts right by 160 bits instead.

_**Update:** Resolved in [pull request #828](https://github.com/across-protocol/contracts/pull/828)._

### Repeated Function

The `_toBytes32` [`internal` function](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/erc7683/ERC7683OrderDepositor.sol#L355) of the `ERC7683OrderDepositor` contract has the same logic as the imported `toBytes32` [function](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/libraries/AddressConverters.sol#L23) of the `AddressConverters` library. Both the `_toBytes32` and `toBytes32` functions are [used](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/erc7683/ERC7683OrderDepositor.sol#L229-L247) throughout the `ERC7683OrderDepositor` contract, which lessens code clarity.

In order to improve the overall code quality and avoid having duplicated code, consider removing the `_toBytes32` function and using the library function instead.

_**Update:** Resolved in [pull request #829](https://github.com/across-protocol/contracts/pull/829). The team also removed the internal `_toAddress` function in favour of the equivalent function present in the same library file._

### Lack of Unit Tests for ERC-7683

As the protocol expands, it is crucial to maintain a comprehensive testing suite that covers all the new features. Presently, the repository does not contain any unit tests for the [`ERC7683OrderDepositor`](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/erc7683/ERC7683OrderDepositor.sol#L20) and [`ERC7683OrderDepositorExternal`](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/erc7683/ERC7683OrderDepositorExternal.sol#L16) contracts.

In order to improve the robustness and security of the codebase, consider implementing a comprehensive testing suite for the EIP-7683 implementation with a high degree of coverage.

_**Update:** Acknowledged, will resolve. The team is planning to integrate changes into the testing and coverage and the issue will be resolved with them._

Notes & Additional Information
------------------------------

### Missing Docstrings

Missing docstrings can negatively affect code clarity and maintainability. The `repaymentAddress` parameter is not documented in the docstrings of the [`fillV3RelayWithUpdatedDeposit`](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/SpokePool.sol#L1043) and [`fillV3Relay`](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/SpokePool.sol#L1000) functions of the `SpokePool` contract.

Consider having docstrings for all input parameters.

_**Update:** Resolved in [pull request #830](https://github.com/across-protocol/contracts/pull/830)._

### Typographical Errors

Throughout the `SpokePool` contract, multiple instances of typographical errors were identified:

*   In [line 616](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/SpokePool.sol#L616), there is an unnecessary trailing `*`.
*   In [line 1297](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/SpokePool.sol#L1297), "msgSenderand" should be "msgSender and".
*   In [line 1502](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/SpokePool.sol#L1502), "revered" should be "reverted".

Consider fixing all typographical errors in order to improve the overall code clarity.

_**Update:** Resolved in [pull request #831](https://github.com/across-protocol/contracts/pull/831)._

### Review of Pull Request #805

As discussed in the scope section, while performing the fix review of the current audit we also reviewed pull request #805. The pull request introduces changes in naming of event and functions among other small changes.

Our highlighted notes from such review were the following:

*   The `SpokePool` contract's `fill` function reverted from using `abi.encodeCall` to using `abi.encode` which is not type safe. We encourage keeping the type safety in place and use `encodeCall` instead.
*   In the `SpokePool` contract, the [natspec](https://github.com/across-protocol/contracts/blob/ff5fcbceb1ba637f43002700e63b02167a96a399/contracts/SpokePool.sol#L282) for `pauseDeposits` should include `speedUpDeposit()` and not `speedUpV3Deposit()`.
*   In the new `fillV3Relay`, the `msg.sender` is taken, while on `fillRelay` it is a specified `repaymentAddress`. Consider having consistent behaviour across these functions.
*   Given the conversation spiked in the pull request comments, we encourage also the team to increase test coverage focusing on backwards compatibility.

_**Update:** Resolved, the team fixed the first two points in [commit a28eb83](https://github.com/across-protocol/contracts/pull/805/commits/a28eb830cea25f7807408f0673912da07f06ffa2) in the same pull request. The team also informed us that they are in the process of expanding the test suite. About the third item, the team stated:_

> The reason of not adding this prop is to keep the interface equivalent to the current fillV3Relay method, as defined here. in the current implementation, this method defaults to setting the filler (msg.sender) as the repayment address. this ensures this method remains backwards compatible with the previous fillV3Relay method.

Client Reported
---------------

### Duplicate Fill Execution

The client reported a critical-severity issue that would allow valid duplicate fills to be executed and could lead to loss of funds from the protocol.

Deposits in Across are uniquely identified using the hash of a `V3RelayData` struct. The proposed changes to the codebase introduced a change to the [`_getV3RelayHash`](https://github.com/across-protocol/contracts/blob/401e24ccca1b3af919dd521e58acd445297b65b6/contracts/SpokePool.sol#L1641-L1660) function. The change modified the method of calculating the hash by only including the hash of the `message` field contained inside the `V3RelayData` struct, instead of hashing the struct in its entirety.

The issue is that upgrades to the `SpokePool` contracts can in practice only happen asynchronously. The `filledStatuses` mapping uses the hash of the relay data to record the status of the order. As the method of hash derivation differs between versions this means that there will exist two valid hashes for the same order, one pre-upgrade and another post-upgrade, which means the [check](https://github.com/across-protocol/contracts/blob/98b940a2501cbdd3adbfeca0ac3a07720be89cb2/contracts/SpokePool.sol#L1702) to see if an order has been filled already will reference a different hash and thus fail to revert for an already filled order.

This has a critical interaction with off-chain components integrated with the protocol. If the relayers or bundlers use the hashed value of the relay data as a unique identifier to keep track of deposits (instead of using the `depositId` of each deposit), then these actors would not be able to recognize that an order has been filled already due to the different hash values. Consequently, the protocol and/or the relayers may lose funds if an order is filled twice, as only a single deposit would have been received.

_**Update**: Resolved. The client has fixed this issue by reverting the proposed change to hash derivation._

### Missing Valid Address Check

In the [`deposit`](https://github.com/across-protocol/contracts/blob/dd88c3c4af6396c83759e0f3f9063ead8d3fd699/contracts/SpokePool.sol#L512) function of the `SpokePool` contract there is no check that the value provided for the `bytes32` parameters are valid EVM addresses. For example, an accidental submission of an incorrectly formatted depositor address would be impossible to refund in the event of no fill.

_**Update:** Resolved. The client [resolved](https://github.com/across-protocol/contracts/pull/874) the issue by introducing a valid address check on the depositor parameter. We encourage the team to repeat the same on all instances where a bytes32 value is intended to be used as an address._

Conclusion
----------

The Across protocol enables rapid token transfers between Ethereum L1 and L2 chains. Users deposit funds, relayers transfer the funds to the destination, and depositors receive the amount minus a fee. The `HubPool` contract on L1 manages liquidity, coordinating with the `SpokePool` contracts on each supported chain.

The Across protocol's Solidity contracts have now been updated to support Solana, as well as providing support for ERC-7683 orders. The changes reviewed in this diff audit show thoughtful consideration for the codebase architecture in a context where demand for support of additional chains is likely to increase. We encourage the team to expand the test suite to include specific tests for the finalized ERC-7683 implementation.

We would like to thank the Risk Labs team for their willingness to answer questions and for providing helpful context throughout the audit.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kGUP-KBktRPD7EzjTprKIRWrBAJHw&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=189745843073&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=47c4f58c-171f-4953-a8f2-fc2d58508063&redirect_url=APefjpFyPeGm2Ke3m1ZJXmrdVc8QKPvC_wC4sF1YlJG1YwYqvz5OEdbUx09EGH9-0ZxpIMKDPnlFRucgNu2Ptu2OYwxsdHnsQANcahtn5RdQXjBinhZOPQFHgEEkDqnHlbV4-XTHSxoSwZpJde2ziNZ0jahwLz5LWQWswLdMXhZDEHxTIfQEGeclo__VXHnAgLXxsgu-xz4GduDmLXlvpwsDMurD3QWXGELOsyXxEG8FEo9ZftdN6_FF8SpKmC0KA2xlVgcNWh1o&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Facross-protocol-svm-solidity-audit&ts=1770534101309&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.71.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")