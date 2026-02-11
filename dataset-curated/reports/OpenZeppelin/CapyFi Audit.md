\- July 24, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

**Type:** DeFi  
**Timeline:** June 25, 2025 → July 7, 2025**Languages:** Solidity

**Findings**Total issues: 11 (9 resolved)  
Critical: 0 (0 resolved) · High: 0 (0 resolved) · Medium: 0 (0 resolved) · Low: 4 (4 resolved)

**Notes & Additional Information**7 notes raised (5 resolved)

Scope
-----

OpenZeppelin audited the [LaChain/capyfi-sc](https://github.com/LaChain/capyfi-sc/) repository at commit [cf47234](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf).

In scope were the following files:

`src
├── contracts
│   ├── BaseJumpRateModelV2.sol
│   ├── CDaiDelegate.sol
│   ├── CErc20.sol
│   ├── CErc20Delegator.sol
│   ├── CErc20Immutable.sol
│   ├── CEther.sol
│   ├── CToken.sol
│   ├── CTokenInterfaces.sol
│   ├── Comptroller.sol
│   ├── ComptrollerG7.sol
│   ├── Governance
│   │   ├── Comp.sol
│   │   ├── GovernorAlpha.sol
│   │   ├── GovernorBravoDelegate.sol
│   │   ├── GovernorBravoDelegateG1.sol
│   │   ├── GovernorBravoDelegator.sol
│   │   └── GovernorBravoInterfaces.sol
│   ├── Lens
│   │   └── CompoundLens.sol
│   └── PriceOracle
│       └── CapyfiAggregatorV3.sol
└── script
    ├── DeployCapyfiProtocolAll.s.sol
    └── capyfi
        ├── DeployInterestRateModels.s.sol
        ├── DeployWhitelist.s.sol
        └── UpgradeWhitelist.s.sol` 

System Overview
---------------

Capyfi is a lending protocol that has been designed to operate on both Ethereum and LaChain with a whitelist-based access control system that enables the enforcement of KYC/AML policies. The protocol employs a market-based lending architecture whereby users can supply assets to earn interest and borrow against their collateral. The system utilizes interest-bearing tokens (cTokens) to represent user positions and uses a custom oracle to determine prices.

The `Whitelist` contract, implemented as an upgradeable UUPS proxy, introduces role-based access control to markets. Two roles are defined: `ADMIN_ROLE` and `WHITELISTED_ROLE`. The admin holds elevated privileges including granting and revoking both roles and upgrading the proxy implementation. Whitelisted users can mint `cTokens` in designated markets where the whitelist contract is used, while non-whitelisted users can still transfer, redeem, and liquidate assets. The `CapyfiAggregatorV3` contract allows CapyFi to support tokens that do not have active Chainlink price feeds. While inspired by Chainlink's model, the CapyFi price feed is updated by a permissioned owner instead of aggregating from different node operators.

The security review covered deployment scripts in addition to the smart contracts to ensure that contracts are deployed in the correct sequence and configuration.

Security Model and Privileged Roles
-----------------------------------

This section goes over the security model of the reviewed system and any privileged roles in it, along with the relevant trust assumptions.

### Deployment

*   The system is designed to be deployed on both Ethereum mainnet and LaChain. The configuration for Ethereum correctly assumes a 12-second block time, but LaChain uses a 5-second block time. As such, any assumptions by the interest rate model or timing-dependent logic must account for this difference.
    
*   Deployment scripts lack protections against launching empty markets. Although the whitelist could provide a layer of access control for minting, the initializer does not set up the whitelist contract by default. This introduces a window where malicious actors could act as first minters unless additional protections are enforced externally. The audited scope does not cover the deployment of new markets to pre-existing deployments. However, it is recommended to some cTokens and burning them within the deployment transaction to ensure that the total supply never goes to zero. It is crucial that the market deployment and burning happen in the same transaction.
    
*   The storage layout is incompatible with legacy contracts. The introduction of the `Whitelist` functionality modifies the storage layout compared to the legacy `CErc20Delegate` contract. As a result, attempting to upgrade existing proxies to this new implementation would lead to storage collisions, potentially breaking core functionality or exposing vulnerabilities. However, as per the CapyFi team’s deployment plan, this implementation is only intended for new market deployments and not as an upgrade path for existing markets.
    

### Price Feed

*   The `CapyfiAggregatorV3` contract relies on a centralized mechanism to update prices. As such, users and integrators must trust the designated price submitter to behave honestly and maintain accurate pricing.
    
*   The `CapyFiAggregatorV3` contract adheres to the Chainlink interface but does not necessarily behave like a Chainlink oracle. Integrators should verify the specific behavior of the CapyFi oracle when using the oracle.
    

### Privileged Roles

The access control mechanism implemented in the `Whitelist` contract grants significant authority to accounts holding the `ADMIN_ROLE`. A single malicious or compromised admin can revoke roles from all other users and unilaterally assume control of the system, including upgrading the contract. As such, proper operational security is assumed for `ADMIN_ROLE` holders. In addition, only whitelisted users can mint `cTokens`. Non-whitelisted users can still redeem, transfer, and liquidate `cTokens`.

Low Severity
------------

### Unlimited `DEFAULT_ADMIN_ROLE` Power Over `ADMIN_ROLE` and `WHITELISTED_ROLE`

The intended hierarchy in the [`Whitelist`](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L13-L170) contract is that only users with `ADMIN_ROLE` can grant and revoke both `ADMIN_ROLE` and `WHITELISTED_ROLE` by using the [`addAdmin`](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L109-L111), [`removeAdmin`](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L117-L119), [`addWhitelisted`](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L125-L127), and [`removeWhitelisted`](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L133-L135) functions. However, the `AccessControlUpgradeable` contract also exposes the [`grantRole`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.5/contracts/access/AccessControlUpgradeable.sol#L136-L138) and [`revokeRole`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.5/contracts/access/AccessControlUpgradeable.sol#L149-L151) `public` functions that allow the `DEFAULT_ADMIN_ROLE` to manage both roles freely. This is because the admin role for both is set by default to `DEFAULT_ADMIN_ROLE`. Hence, they can manage these 2 roles without any restriction even without having `ADMIN_ROLE` assigned.

Consider implementing one of the following solutions:

1.  Remove the `addAdmin`, `removeAdmin`, `addWhitelisted`, and `removeWhitelisted` functions to rely on the inherited `grantRole` and `revokeRole` functions. This solution would require [properly setting up the role admin](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.5/contracts/access/AccessControlUpgradeable.sol#L200-L204) for both `ADMIN_ROLE` and `WHITELISTED_ROLE` such that only the role admin of the specific role can manage them.
2.  Utilize the custom functions to manage roles and disable the inherited `grantRole` and `revokeRole` functions by overriding them and making them inaccessible.

_**Update:** Resolved in [pull request #5](https://github.com/LaChain/capyfi-sc/pull/5) at [commit d4abd3](https://github.com/LaChain/capyfi-sc/pull/5/commits/d4abd32490a9b7a9b68d9eaba7d391766bab158a)._

### Unsafe Casting in `getAnswer` Function

The [`getAnswer`](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/CapyfiAggregatorV3.sol#L148) function of the [`CapyFiAggreatorV3`](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/CapyfiAggregatorV3.sol) contract accepts any `uint256` value for the `roundId`. When the `roundId` is greater than `uint80`, the function will always revert but the returned error will incorrectly cast the value returned to `uint80`.

Consider either not casting `roundId` to `uint80` in the `RoundNotFound` error or returning different data when the input parameter is greater than `uint80`.

_**Update:** Resolved in [pull request #6](https://github.com/LaChain/capyfi-sc/pull/6) at [commit 5ac968](https://github.com/LaChain/capyfi-sc/pull/6/commits/5ac96823f9ce838ad035e6c3f9c5451818c03b93)._

### Differences Between CapyFi And Chainlink Oracles

There are some implementation differences between Chainlink's and Capyfi's aggregators:

*   In Chainlink price feeds, the [`roundId` is composed of `phaseId` and `originalId`](https://docs.chain.link/data-feeds/historical-data#roundid-in-proxy). The `phaseId` is a counter that gets incremented each time a new aggregator is referenced and the `originalId` is a counter to track each submitted price in the data feed. These two IDs are packed into the same `uint80` shifted by `uint80((phaseId << 64) + originalId)`. Both counters start at 1, hence, the first valid `roundId` should be `18446744073709551617`. However, in Capyfi's implementation, it [starts at 1](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/CapyfiAggregatorV3.sol#L61) and gets [incremented](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/CapyfiAggregatorV3.sol#L116) each time a new price is submitted. If an external integrator wants to fetch historical data from the very beginning and they try to fetch the first valid round from a Chainlink aggregator into Capyfi's implementation, it will revert.
*   When someone wants to fetch data from a round that has not yet been filled, Chainlink's implementation returns empty data. For `getAnswer(uint256 roundId)` and `getTimestamp(uint256 roundId)`, it returns 0 and for `getRoundData(uint80 roundId)`, it returns 0 for `answer`, `startedAt`, and `updatedAt`. However, in Capyfi's implementation, it reverts the execution. This can also break external integrations.
*   There are no minimum and maximum price bound checks in the CapyFi oracle.
*   For the CapyFi oracle, `startedAt` is always the same value as `updatedAt`. This is because when `updateAnswer` is called, that price is immediately the price of the oracle, whereas Chainlink aggregates multiple oracle sources which requires a time delay.

Consider documenting the above-listed differences in the codebase so that integrators can be aware of them.

_**Update:** Resolved in [pull request #7](https://github.com/LaChain/capyfi-sc/pull/7) at [commit fb173f](https://github.com/LaChain/capyfi-sc/pull/7/commits/fb173f1fe2b0b994d5329613ad8b380f8f902e63)._

### Missing State Change Validation

Throughout the codebase, multiple instances of functions that do not verify whether the new value actually differs from the existing one before updating were identified:

*   The [`activate`](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L89) function in `Whitelist.sol`
*   The [`deactivate`](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L98) function in `Whitelist.sol`
*   The [`addAuthorizedAddress`](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/CapyfiAggregatorV3.sol#L70) function in `CapyfiAggregatorV3.sol`
*   The [`removeAuthorizedAddress`](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/CapyfiAggregatorV3.sol#L80) function in `CapyfiAggregatorV3.sol`

Consider adding validation checks that revert the transaction if the input value matches the existing value.

_**Update:** Resolved in [pull request #8](https://github.com/LaChain/capyfi-sc/pull/8) at [commit 3c63ae](https://github.com/LaChain/capyfi-sc/pull/8/commits/3c63ae9d67870ca52a2d2ed0423cd7a49d002a83)._

Notes & Additional Information
------------------------------

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

The contracts in the audit scope do not have a security contact.

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Acknowledged not resolved._

### Missing Named Parameters in Mappings

Since [Solidity 0.8.18](https://github.com/ethereum/solidity/releases/tag/v0.8.18), mappings can include named parameters to provide more clarity about their purpose. Named parameters allow mappings to be declared in the form `mapping(KeyType KeyName? => ValueType ValueName?)`. This feature enhances code readability and maintainability.

Within `CapyfiAggregatorV3.sol`, multiple instances of mappings without named parameters were identified:

*   The [`rounds` state variable](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/CapyfiAggregatorV3.sol#L22)
*   The [`authorizedAddresses` state variable](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/CapyfiAggregatorV3.sol#L25)

Consider adding named parameters to mappings in order to improve the readability and maintainability of the codebase.

_**Update:** Resolved in [pull request #9](https://github.com/LaChain/capyfi-sc/pull/9) at [commit d2c855](https://github.com/LaChain/capyfi-sc/pull/9/commits/d2c855b6b3b9014b9e7220f2798de181c736a979)._

### Lack of Indexed Event Parameters

Within `Whitelist.sol`, multiple instances of events missing indexed parameters were identified:

*   The [`WhitelistActivated` event](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L27)
*   The [`WhitelistDeactivated` event](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L28)
*   The [`WhitelistUpgraded` event](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L29)

To improve the ability of off-chain services to search and filter for specific events, consider [indexing event parameters](https://solidity.readthedocs.io/en/latest/contracts.html#events).

_**Update:** Resolved in [pull request #10](https://github.com/LaChain/capyfi-sc/pull/10) at [commit fb7ad5](https://github.com/LaChain/capyfi-sc/pull/10/commits/fb7ad50f2939607715b1e77025fcf091bedc8abf)._

### Lack of Oracle Staleness Check

The protocol relies on Chainlink price feeds for asset valuation. When using Chainlink's [`latestRoundData`](https://docs.chain.link/data-feeds/api-reference#latestrounddata), it is crucial to thoroughly validate all the returned data to prevent the use of stale or incorrect prices.

The [`priceFeed.latestRoundData`](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/ChainlinkPriceOracle.sol#L161) call within `ChainlinkPriceOracle.sol` does not check whether the price is stale.

Consider fully validating the result of the `latestRoundData()` output to ensure that the data feed has returned a recent and correct price. Failure to do so can introduce material risks such as undercollateralized loans due to tokens being borrowed against assets with outdated prices.

_**Update:** Acknowledged, not resolved._

### Missing Docstrings

Throughout the codebase, multiple instances of missing docstrings were identified:

*   In `Whitelist.sol`, the [`ADMIN_ROLE` state variable](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L20), [`WHITELISTED_ROLE` state variable](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L21), [`WhitelistActivated` event](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L27), [`WhitelistDeactivated` event](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L28), and the [`WhitelistUpgraded` event](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/Access/Whitelist.sol#L29).
*   All functions and events in [`AggregatorV3Interface.sol`](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/AggregatorV3Interface.sol)
*   In `CapyfiAggregatorV3.sol`, the [`authorizedAddresses` state variable](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/CapyfiAggregatorV3.sol#L25), [`AuthorizedAddressAdded` event](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/CapyfiAggregatorV3.sol#L28), and the [`AuthorizedAddressRemoved` event](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/CapyfiAggregatorV3.sol#L29)

Consider thoroughly documenting all functions (and their parameters) that are part of any contract's public API. Functions implementing sensitive functionality, even if not public, should be clearly documented as well. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in [pull request #11](https://github.com/LaChain/capyfi-sc/pull/11) at [commit 4ca9de](https://github.com/LaChain/capyfi-sc/pull/11/commits/4ca9de9d48c32b8b60d39b53df62f1c9b73cbf3d)._

### Variables Could Be `immutable`

If a variable is only ever assigned a value from within the `constructor` of a contract, it could be declared `immutable`.

Within `CapyfiAggregatorV3.sol`, multiple instances of variables that could be made `immutable` were identified:

*   The [`_decimals` state variable](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/CapyfiAggregatorV3.sol#L17)
*   The [`_version` state variable](https://github.com/LaChain/capyfi-sc/blob/cf47234ecffe0747f894dc73c4df15b78469b0bf/src/contracts/PriceOracle/CapyfiAggregatorV3.sol#L19)

To better convey the intended use of variables and to potentially save gas, consider adding the `immutable` keyword to variables that are only set in the constructor.

_**Update:** Resolved in [pull request #12](https://github.com/LaChain/capyfi-sc/pull/12) at [commit 0dfc1e](https://github.com/LaChain/capyfi-sc/pull/12/commits/0dfc1e917274483be87428d8f0dc917687f4f829)._

### Silent Failure During Protocol Configuration

When interacting with the underlying Compound V2 contracts, most functions return values to indicate errors instead of reverting. This behavior must be carefully considered during protocol configuration, especially during deployment. If a specific operation such as [`_supportMarket`](https://github.com/LaChain/capyfi-sc/blob/main/src/contracts/Comptroller.sol#L932-L955) or [`_setCollateralFactor`](https://github.com/LaChain/capyfi-sc/blob/main/src/contracts/Comptroller.sol#L867-L900) fails and returns an error code, the deployment script will still succeed, but the intended configuration will not be applied.

To avoid silent failures, consider storing the returned value from these function calls and explicitly checking that it equals zero ([`NO_ERROR`](https://github.com/LaChain/capyfi-sc/blob/main/src/contracts/ErrorReporter.sol#L6)). This ensures that the deployment script fails immediately if any of these internal calls encounters an error.

_**Update:** Resolved in [pull request #14](https://github.com/LaChain/capyfi-sc/pull/14) at [commit 0acfdf](https://github.com/LaChain/capyfi-sc/pull/14/commits/0acfdfe9afed12a172f9e49e3fd16b28b739bbee) and [commit 244cd4](https://github.com/LaChain/capyfi-sc/pull/14/commits/244cd4e94c1f67ec1bbf193cef032dfc6e015523)._

Conclusion
----------

The audited scope encompasses the deployment of the CapyFi lending protocol, with particular emphasis on the addition of the whitelist mechanism, the implementation of the CapyFi oracle, and the safety of deployment scripts. This codebase implements changes to a protocol that has undergone multiple audits, and minimizing the modifications made to the original codebase allows it to benefit from the security of the original architecture. The deployment script covers the launch of the lending protocol, oracle, and whitelist. While the deployment of new markets to an already deployed contract was not part of the scope of this audit, the importance of adding initial assets to empty markets upon launch to prevent inflation attacks must be emphasized.

No critical-, high-, or medium-severity issues were identified, which is a testament to the robustness of the codebase. Nonetheless, some low-severity issues were reported, and various code improvements were suggested. The CapyFi team is appreciated for their exceptional collaboration throughout this engagement. The team clearly explained the contracts and provided relevant documentation outlining the protocol's functionality and their specific areas of concern.