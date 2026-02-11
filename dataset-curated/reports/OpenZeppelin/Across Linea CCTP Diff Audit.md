\- May 12, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary

**Type:** DeFi  
**Timeline:** March 13, 2025 → March 18, 2025**Languages:** Solidity**Findings**Total issues: 4 (3 resolved, 1 partially resolved)  
Critical: 0 (0 resolved) · High: 0 (0 resolved) · Medium: 0 (0 resolved) · Low: 2 (1 resolved, 1 partially resolved)

**Notes & Additional Information**2 notes raised (2 resolved)  
Client reported issues: 0 (0 resolved)

Scope
-----

We audited the [across-protocol/contracts](https://github.com/across-protocol/contracts) repository.

In scope were the changes made to the following files:

`contracts
├── Linea_SpokePool.sol
├── chain-adapters/
│   └── Linea_Adapter.sol
├── libraries/
│   └── CircleCCTPAdapter.sol
└── external/
    └── interfaces/
        └── CCTPInterfaces.sol` 

in the [pull request #921](https://github.com/across-protocol/contracts/pull/921) with the final commit [`0720878`](https://github.com/across-protocol/contracts/pull/921/commits/0720878762ebf99034aa62893c091237ef44fdf7).

We have additionally reviewed the [`e5310e0`](https://github.com/across-protocol/contracts/pull/921/commits/e5310e0c3771407686cd8e03956863e54b09697f) commit.

System Overview
---------------

The Across protocol is an intent-based bridging protocol which enables fast token transfers between different blockcahins. For more details on how the protocol works, please refer to [one of our previous audit reports](https://blog.openzeppelin.com/uma-across-v2-audit-2023).

### Summary of Changes

In order to bridge USDC tokens between Ethereum and another blockchains supporting the [Circle CCTP protocol](https://www.circle.com/cross-chain-transfer-protocol), both the HubPool and SpokePools were utilizing the `CircleCCTPAdapter` contract, which implements the USDC bridging logic using the first version (V1) of the CCTP protocol.

However, the Linea blockchain does not support the V1 version of CCTP and will only support [the V2 version](https://developers.circle.com/stablecoins/cctp-getting-started), which uses a different set of contracts and it results in a different API being exposed to the users. As a result, in order to support USDC transfers to and from the Linea blockchain, it has been necessary to adjust the existing contracts in Across so that they are able to interact with CCTP through the new API.

The changes involved small modifications of the `CircleCCTPAdapter`, `Linea_Adapter` and `Linea_SpokePool` contracts and an introduction of the new `ITokenMessengerV2` interface in order to facilitate communication with the second version of CCTP TokenMessenger contract.

Security Model and Trust Assumptions
------------------------------------

The audit has been focused on the specific changes made to the contracts in order to integrate with CCTP V2 on Linea. As such, it has been restricted only to a small part of the codebase and has been conducted under the following trust assumptions.

Throughout the audit we assumed that all on-chain and off-chain components the in-scope code integrates with behave correctly and as expected. In particular, that the CCTP protocol works correctly and reliably transfers desired USDC amounts between Ethereum and Linea blockchains according to its documentation.

Furthermore, we assumed that the in-scope contracts will be correctly deployed and initialized with the correct parameters, which is crucial for the entire protocol to operate correctly.

Finally, the Linea CCTP Domain ID has not been officially announced at the time of the audit, although it was very likely that it would be equal to 11. Hence, it has been assumed that the [constant reflecting it in the code](https://github.com/across-protocol/contracts/blob/e5310e0c3771407686cd8e03956863e54b09697f/contracts/libraries/CircleCCTPAdapter.sol#L17) is initialized correctly.

### Privileged Roles

There have not been any new privileged roles added to the protocol in the pull request being reviewed.

Throughout the audit we assumed that all privileged entities already existing in the Across protocol will behave honestly and in the best interest of the protocol and its users.

Low Severity
------------

### Check For CCTP Version Is Not Fully Reliable

In order to determine the CCTP version which will be used for bridging USDC, the constructor of the [`CircleCCTPAdapter` contract](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L28) performs a [low level call](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L83-L85) to the `feeRecipient` function of a CCTP TokenMessenger. The check relies on the fact that this function is not present in V1 contracts, but is present in V2 contracts and returns a non-zero address.

However, the check being performed is not fully reliable for the reasons enumerated below.

The values returned by the functions in Solidity are `abi.encode`d, which means that the address returned by the `feeRecipient` function will be padded to 32 bytes with 0s at the beginning. Furthermore, casting a `bytes` object to `bytes20` will return the first 20 bytes of that object, which will include 12 bytes of padding and as a result, only the first 8 bytes of the returned address will be taken into account in [this check](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L86C30-L86C74). In case when the first 8 bytes of the returned `feeRecipient` are equal to 0, the contract will incorrectly assume that it should use CCTP V1.

Furthermore, while it is checked that the call succeeded, there is no verification that the return data is of correct size. As a result, the [check](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L86C30-L86C74) can succeed in case when the return data is of a different size. In particular, for the return data of 0 length, the correctness of this check relies on the cast from an empty `bytes` object to `bytes20` always returning 0.

Finally, a contract to be called could still have a fallback function which returns 32 bytes of data. In case when at least 1 of the last 20 bytes of that data is nonzero, the check will still succeed even if the target contract does not implement the `feeRecipient` function.

Consider casting the `feeRecipient` to `uint160` before casting it to address in order to retrieve the full address. Moreover, consider validating the length of the data returned by the low level call in order to better handle the situations when data with unexpected size is returned. Furthermore, consider implementing a more robust mechanism of determining the CCTP version to be used.

_**Update:** Partially resolved in [pull request #921](https://github.com/across-protocol/contracts/pull/921) at commit [d9d4707](https://github.com/across-protocol/contracts/pull/921/commits/d9d4707d8b19d2d2bd80632ed411a22ef031b0dc). The casting of the data returned from a low level call has been fixed and additional verification has been added to the length of the returned data. It is still possible that the check for the CCTP version will not determine the correct version, but this scenario is very unlikely and the risk has been accepted by the Risk Labs team._

### Insufficient Documentation

The [`_transferUsdc` function](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L113) of the `CircleCCTPAdapter` contract is responsible for bridging USDC between different blockchains using the CCTP protocol. In order to do this, it [queries the `CCTPTokenMessenger` contract](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L118) for the TokenMinter's address, [determines the current burn limit per message](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L119) and [splits USDC deposits if necessary](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L120-L143).

However, the [`cctpTokenMessenger` variable](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L52) used to retrieve the minter's address, is of type `ITokenMessenger`, which represents the version 1 of the `TokenMessenger` contract, but it is possible that in reality it points to the `TokenMessengerV2` contract. Since both `TokenMessenger` and `TokenMessengerV2` contracts define the `localMinter` function being used, the [function call](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L118C54-L118C67) will succeed for both cases, but this implicit behaviour could be reflected in the comments. Furthermore, the `localMinter` being returned by this function is either of type [`ITokenMinter`](https://github.com/circlefin/evm-cctp-contracts/blob/6e7513cdb2bee6bb0cddf331fe972600fc5017c9/src/TokenMessenger.sol#L110) or [`ITokenMinterV2`](https://github.com/circlefin/evm-cctp-contracts/blob/6e7513cdb2bee6bb0cddf331fe972600fc5017c9/src/v2/BaseTokenMessenger.sol#L87), depending on the version of TokenMessenger which is called. While both versions of the `TokenMinter` contract expose the `burnLimitsPerMessage` function, this fact is not obvious and could be documented as well.

Consider improving the documentation inside the `_transferUsdc` function in order to improve readability and maintainability of the codebase.

_**Update:** Resolved in [pull request #921](https://github.com/across-protocol/contracts/pull/921) at commit [d9d4707](https://github.com/across-protocol/contracts/pull/921/commits/d9d4707d8b19d2d2bd80632ed411a22ef031b0dc)._

Notes & Additional Information
------------------------------

Throughout the codebase, several instances of misleading comments were identified: - The [comment](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L136) states that the `minFinalityThreshold` parameter can be set to `20 000` for a standard transfer, while the [correct value is `2 000`](https://github.com/circlefin/evm-cctp-contracts/blob/6e7513cdb2bee6bb0cddf331fe972600fc5017c9/src/v2/FinalityThresholds.sol#L21). - The [comment](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/Linea_SpokePool.sol#L151) refers to an `l1Token`, however the code checks whether `l2TokenAddress` is the address of `usdcToken`. Therefore, in the comment, `l1Token` should be changed to `l2Token`.

Consider correcting the aforementioned comments to improve the overall clarity and readability of the codebase.

_**Update:** Resolved in [pull request #921](https://github.com/across-protocol/contracts/pull/921) at commit [b135917](https://github.com/across-protocol/contracts/pull/921/commits/b1359172cfaf05e99e503b49a39be58b7f8331c0)._

### Typographical Errors

Throughout the codebase, several instances of typographical errors were identified:

In the [`CircleCCTPAdapter.sol`](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol) file: - In [line 70](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L70), "its" should be "it is". - In [line 116](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L116), "to bridged" should be "to bridge". - In [line 124](https://github.com/across-protocol/contracts/blob/0720878762ebf99034aa62893c091237ef44fdf7/contracts/libraries/CircleCCTPAdapter.sol#L124), there is an extra space that could be removed at the beginning of the line.

Consider fixing all instances of typographical errors in order to improve the readability of the codebase.

_**Update:** Resolved in [pull request #921](https://github.com/across-protocol/contracts/pull/921) at commit [63231d9](https://github.com/across-protocol/contracts/pull/921/commits/63231d9b609fcb3228806ccf310792aa72651701)._

Conclusion
----------

The changes added to the code enable the contracts to bridge USDC to and from the Linea blockchain utilizing the second version of the CCTP protocol, while still allowing to use the first version of the protocol for another blockchains.

Throughout the audit, there have not been any significant issues identified.

The Risk Labs team has been very helpful throughout the engagement, answering all our questions promptly and in a great detail.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kE8iESxBS8QnHu9vx4oYlX8ppm4FA&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=189745842734&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=3583c439-b07a-4042-8a97-71ebaa9b8135&redirect_url=APefjpFoSZlp-KqT2ijRgitWRkUWmxqrWszsijRmU2L7xfqvcd0sJFy80UBK5bqZmwxpTM9QY2jxFLmrzZhf3Mkz8fws9rjWpbtDXrU174IMtqE15KoNwFDA22WDNRVz9zpA6XF8ylivU1fJrm4ryxwChSb9Y7QXJfKoHSB87x5GPMO1rwLEvILimbnjarPsmJ3hKaVV8Lcf2FtNQBWt3GCFjqLaFz26q0aiiL3jJ6Do8XJv2jU80Yy00PppgZhW400trHI52qh8&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Facross-linea-cctp-diff-audit&ts=1770534037360&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.69.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")