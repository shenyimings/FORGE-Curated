\- April 30, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

Type

DeFi

Timeline

From 2025-04-03

To 2025-04-04

Languages

Solidity

TS/JS

Total Issues

4 (4 resolved)

Critical Severity Issues

0 (0 resolved)

High Severity Issues

0 (0 resolved)

Medium Severity Issues

0 (0 resolved)

Low Severity Issues

1 (1 resolved)

Notes & Additional Information

3 (3 resolved)

Client Reported Issues

0 (0 resolved)

Scope
-----

We reviewed [Pull Request #4816](https://github.com/UMAprotocol/protocol/pull/4816) of the `UMAprotocol/protocol` repository. The scope includes the Solidity contract changes for `OracleBaseTunnel` (from which `OracleRootTunnel` inherits), `OracleChildTunnel`, and `OracleSpoke`, scripts within `packages/scripts/src/admin-proposals`, and changes to tests in `packages/core/test/hardhat`.

Additionally, we reviewed the plan outlined in the [proposal (UMIP-185)](https://github.com/UMAprotocol/UMIPs/pull/620) intended to be used to perform the upgrade across Ethereum, Polygon, Optimism, Arbitrum, Base, and Blast networks.

Overview
--------

When handling Oracle requests on chains other than Ethereum mainnet, additional ancillary data is appended to the bridged data. This data is intended to be resolved by off-chain components and relayed to Ethereum mainnet. The proposed change involves compressing ancillary data for Oracle requests when bridged to Ethereum mainnet by sending only a hash of the data along with metadata (`childBlockNumber`, `childOracle`, `childRequester`, `childChainId`), as detailed in proposal. This aims to reduce gas costs for both off-chain components and users (voters). The upgrade involves deploying new versions of the `OracleRootTunnel`, `OracleChildTunnel`, and `OracleSpoke` contracts and updating relevant system parameters via governance.

Low Severity
------------

### Oracle Upgrades Can Make Prices Inaccessible

New request IDs are calculated using the `requester` address. Similarly, `hasPrice` and `getPrice` use `msg.sender` as the `requester` to retrieve a price. As a result, if the `OptimisticOracleV2` implementation is upgraded in the future, the new contract instance will not be able to access prices submitted through the previous implementation.

Since this issue only occurs if the `OptimisticOracleV2` contract is replaced, consider whether this scenario is possible and if changes are needed in `OracleSpoke` or `OracleChildTunnel`.

_**Update:** Resolved in commit [3b1a2b4](https://github.com/UMAprotocol/protocol/pull/4816/commits/3b1a2b4d9ca16b6bef74cee3f02caddbb663f314) of pull request #4816 by removing the `requester` from the child request ID derivation. The team stated:_

> _As we see it, the only theoretical drawback is someone could frontrun OOv2 dispute by requesting/proposing/disputing the same id/time/ancillary data from OOv1 which would make it ambiguous for DVM voters to figure out the true origin of the request. But one can argue its not absolutely necessary as answer should not depend on who's asking. And this attack is not possible in practice as our OO implementations append `ooRequester` field, so you cannot spoof the ancillary data. Hence, we opted to simplify by using the same inherited `_encodePriceRequest` method and potentially making it easier to handle future OO upgrades._

Notes & Additional Information
------------------------------

### Misleading or Incorrect Docstrings

There are several comments that could be updated to enhance clarity:

*   "its" could be changed to "it is" [here](https://github.com/UMAprotocol/protocol/tree/a005938dc43b0496608b5d1212abd4026f7490d8/packages/core/contracts/cross-chain-oracle/AncillaryDataCompression.sol#L17).
    
*   "ancillary data" could be changed to "compressed ancillary data" [here](https://github.com/UMAprotocol/protocol/tree/a005938dc43b0496608b5d1212abd4026f7490d8/packages/core/contracts/cross-chain-oracle/AncillaryDataCompression.sol#L19), as `parentRequestId` is [calculated based on compressed data](https://github.com/UMAprotocol/protocol/tree/a005938dc43b0496608b5d1212abd4026f7490d8/packages/core/contracts/cross-chain-oracle/OracleSpoke.sol#L107-L108).
    
*   [This](https://github.com/UMAprotocol/protocol/tree/a005938dc43b0496608b5d1212abd4026f7490d8/packages/core/contracts/cross-chain-oracle/OracleSpoke.sol#L252) and [this](https://github.com/UMAprotocol/protocol/tree/a005938dc43b0496608b5d1212abd4026f7490d8/packages/core/contracts/polygon-cross-chain-oracle/OracleChildTunnel.sol#L196) comment state that compressed data is only returned when the original data exceeds a threshold, but in the current implementation, ancillary data is always compressed.
    

_**Update:** Resolved at commit [8e05fe6](https://github.com/UMAprotocol/protocol/pull/4816/commits/8e05fe6696721e145daa8b6c1bab3956c4d5a42a) of the same pull request._

### Repeated Event Emissions

The [`resolveLegacyRequest` function](https://github.com/UMAprotocol/protocol/tree/a005938dc43b0496608b5d1212abd4026f7490d8/packages/core/contracts/cross-chain-oracle/OracleSpoke.sol#L157) of the `OracleSpoke` contract allows setting a price for any `childRequester` as long as the legacy request has been resolved. As a result, the `ResolvedLegacyRequest` event may be emitted multiple times. It is also possible to set new price entries this way, but they are indexed by a `keccak256` hash, avoiding potential collisions.

Consider whether repeated event emissions might be problematic for off-chain components.

_**Update:** Resolved. The team stated:_

> _Previous `OracleSpoke` did not include requester in its stamped ancillary data, so we cannot limit the `resolveLegacyRequest` to any single one requester. Only maybe hardcoding known requester addresses and checking them, but even that still could have more than `ResolvedLegacyRequest` events emitted. This though should not impact the functioning of OO as the main reason for this event was to check if a particular legacy child request has been resolved to new format. Off-chain one can recalculate `priceRequestId` for a known valid requester and filter events accordingly._

### Verification Script is Missing One Check

The verification [script](https://github.com/UMAprotocol/protocol/blob/63f05e70c78efee366dc9926bdcc76238ad95b33/packages/scripts/src/admin-proposals/upgrade-oo-request-bridging/4_Verify.ts) is missing a check on whether the `CONTRACT_CREATOR` [role](https://github.com/UMAprotocol/protocol/blob/63f05e70c78efee366dc9926bdcc76238ad95b33/packages/scripts/src/admin-proposals/upgrade-oo-request-bridging/2_Propose.ts#L102-L113) has not been retained after the upgrade has been performed.

Consider adding a validation step to ensure that no unneeded roles are retained.

_**Update:** Resolved in commit [e452d64](https://github.com/UMAprotocol/protocol/pull/4816/commits/e452d642e18de84d63a24bb8f154c2aa1adf00cc)._

Recommendations
---------------

### Fork Testing

Consider running the DAO proposal simulation on a forked environment and evaluating the correctness of the state after the upgrade.

_**Update:** Scripts to simulate the upgrade on a forked environment have been included, along with verifications._

### E2E Testing

Currently, the only end-to-end test available for Oracle requests and resolving is the one performed for the Polygon network. However, corresponding end-to-end tests for rollup chains are not present. Even though the existing unit tests cover the codebase extensively, we recommend also adding end-to-end tests to improve cross-chain mechanics coverage, configuration validation, and regression testing for new changes.

_**Update:** The team stated:_

> _We acknowledge the recommendation and will create an end-to-end test for the Oracle request/resolving flow for rollup networks that utilize the hub and spoke mechanism._

Conclusion
----------

The reviewed pull request and proposal introduce changes to compress ancillary data in Oracle requests, aiming to reduce gas consumption. Only minor issues were found, all of which have been addressed. The DAO proposal was also reviewed and confirmed to include all necessary steps, as outlined in the UMIP, to upgrade the required components with the new contract implementations.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kHAN3bLMIN-mELQ7Qf-GhjkrCMFaw&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=188913726024&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=63b33216-7eba-4f3e-9f04-5227b2bd92a1&redirect_url=APefjpFtVZ746RNHKfkXtnTC1ty6H7D7erFgk94za-54NRbn4C_Sn9jYk1HwJKdCOh8kd0Omid2pEqMtjyMzvzPbgHNo9-H5hpu1UaP7OXWaMY-83LbAL9InGUbaJ7VXGTOATWq8ufTViUvRxVgxXXdWjqCl46QP6tO4t_F7FuqydiUmsdpGgxGpxRGb9iN7HTgFfpZ7aedWv8m2BIrxhJdzqAZCUsUN1eSoMbaeSS7JqYkBrYUqynsJ9pGlecDfAtOBCEcz64zp&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Fuma-oracle-bridging-contracts-upgrade-audit&ts=1770534160946&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.77.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")