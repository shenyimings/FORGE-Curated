\- March 12, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

Type

DeFi

Timeline

From 2023-11-13

To 2023-11-17

Languages

Solidity

Total Issues

14 (10 resolved)

Critical Severity Issues

0 (0 resolved)

High Severity Issues

1 (1 resolved)

Medium Severity Issues

1 (1 resolved)

Low Severity Issues

2 (1 resolved, 1 partially)

Notes & Additional Information

10 (7 resolved)

Scope
-----

We audited the [Fireblocks](https://github.com/fireblocks/reference-protocols) repository at commit [e7003dfb](https://github.com/fireblocks/reference-protocols/tree/e7003dfb9d89aa4b314a7428cbc59d07f178fd76).

Following the conclusion of the audit, Fireblocks has updated the license to `AGPL-3.0-or-later` in [pull request #1](https://github.com/fireblocks/reference-protocols/pull/1) at commit [6d8327b](https://github.com/fireblocks/reference-protocols/pull/1/commits/6d8327b9687229543cd4f372adccc61d58b82e47). This update has had no impact on the security of the source code logic.

In scope were the following contracts:

`contracts
├── ERC721F.sol
└── library
    ├── AccessRegistry
    │   ├── AccessListUpgradeable.sol
    │   ├── AccessRegistrySubscriptionUpgradeable.sol
    │   ├── AllowList.sol
    │   ├── DenyList.sol
    │   └── interface
    │       └── IAccessRegistry.sol
    ├── Errors
    │   ├── LibErrors.sol
    │   └── interface
    │       └── IERC721Errors.sol
    └── Utils
        ├── ContractUriUpgradeable.sol
        ├── MarketplaceOperatorUpgradeable.sol
        ├── PauseUpgradeable.sol
        ├── RoleAccessUpgradeable.sol
        ├── SalvageUpgradeable.sol
        └── TokenUriUpgradeable.sol` 

__Update:_ This codebase was migrated to a new repository at [https://github.com/fireblocks/fireblocks-smart-contracts](https://github.com/fireblocks/fireblocks-smart-contracts), which was audited until commit [a8942e9](https://github.com/fireblocks/fireblocks-smart-contracts/pull/3/commits/a8942e9b732a25cb491640889edb0479b544e431) in PR[#3](https://github.com/fireblocks/fireblocks-smart-contracts/pull/3). This PR was later merged into the `main` branch at commit [108a92f](https://github.com/fireblocks/fireblocks-smart-contracts/commit/108a92ff18dd41209a49a2c6e2d9ba8d91e81d15)._

System Overview
---------------

The Fireblocks Upgradeable Tokens project implements three upgradeable token contracts, namely, `ERC721F`. This is a compliant with the ERC-721 token standard and additional functionality has been integrated for managing access control. The token facilitate the configuration of an access list for token transfers, providing the flexibility of implementing either an allowlist, where only addresses on the list can utilize the tokens, or a denylist, which restricts addresses on the list from interacting with the contract.

### Privileged Roles

The protocol implements multiple privileged roles that are tied to the `ERC721F` contract.

The holder of `DEFAULT_ADMIN_ROLE` can:

*   Grant roles to other addresses.

The holder of `UPGRADER_ROLE` can:

*   Upgrade the implementation contracts to a new version.

The holder of `PAUSER_ROLE` can:

*   Pause and unpause a contract.

The holder of `CONTRACT_ADMIN_ROLE` can:

*   Change the used access list address.
*   Update the contract URI.
*   Update the token URI address.
*   Update the marketplace operator address.

The holder of `MINTER_ROLE` can:

*   Mint tokens.

The holder of `BURNER_ROLE` can:

*   Burn tokens.

The holder of `RECOVERY_ROLE` can:

*   Recover tokens from an account that is missing access.

The holder of `SALVAGE_ROLE` can:

*   Recover ETH and ERC-20 tokens that were sent to a token contract itself.

### Trust Assumptions

*   The holders of the `DEFAULT_ROLE_ADMIN` role are expected to be non-malicious and to act in the project's best interest.

High Severity
-------------

### `ERC721F` Transfer Access List Can Be Bypassed

The [`ERC721F`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/ERC721F.sol) contract implements logic to verify whether the sender and recipient have access. This functionality is introduced by overriding the [`transferFrom`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/ERC721F.sol#L279-283) function and including the necessary access checks. However, an issue arises because the contract inherits from the [`ERC721Upgradeable`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/ERC721Upgradeable.sol) contract, which includes two additional functions, both named [`safeTransferFrom`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/5bc59992591b84bba18dc1ac46942f1886b30ccd/contracts/token/ERC721/ERC721Upgradeable.sol#L162-L175) but having different parameters. These functions do not internally utilize the overridden `transferFrom` function but instead rely on the [`_safeTransfer`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/5bc59992591b84bba18dc1ac46942f1886b30ccd/contracts/token/ERC721/ERC721Upgradeable.sol#L195-L198) function. Consequently, a user without the appropriate access can use the `safeTransferFrom` functionality to circumvent the access list checks and successfully transfer the tokens.

Consider introducing additional checks to ensure that proper handling of transfers is conducted through the `safeTransferFrom` functionality.

_**Update:** Acknowledged, resolved in commit [7710940](https://github.com/fireblocks/reference-protocols/commit/7710940451037471b1ae9bd03ddce4c946afbc38)._

Medium Severity
---------------

### Burner Can Burn Any `ERC721F` Token

The [`ERC721F`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/ERC721F.sol) contract implements a [`burn`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/ERC721F.sol#L222-225) function designed to be executed exclusively by the address with the `BURNER_ROLE` role. The function is intended to allow the burning of only those tokens owned by the caller, as indicated by the function's [NatSpec description](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/ERC721F.sol#L210). However, the function directly calls the [`_burn`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/ERC721F.sol#L224) function without performing any essential checks to verify whether the caller is the owner of the token being burned or has the approval to burn it.

Consider incorporating a check using the [`_isApprovedOrOwner`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/5bc59992591b84bba18dc1ac46942f1886b30ccd/contracts/token/ERC721/ERC721Upgradeable.sol#L226-L229) function to ensure that `_msgSender()` is either the approved party or the owner of the specified token.

_**Update:** Acknowledged, resolved in commit [a5e2488](https://github.com/fireblocks/reference-protocols/commit/a5e24887b32e1751afcba5b38b281128d89fcba4)._

Low Severity
------------

### Follow Checks-Effects-Interactions (CEI) Pattern

The `ERC721F` contract implements a [`mint` function](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/ERC721F.sol#L202) that does not follow the CEI pattern. The function mints a token using [`_safeMint`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/ERC721F.sol#L204), which ensures that the recipient is a contract using the `onERC721Received` hook. This allows a recipient to hijack the execution and then set the token URI through the [`_tokenUriUpdate` function](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/ERC721F.sol#L205).

Consider first updating the token URI and then calling `_safeMint`.

_**Update:** Acknowledged, resolved in commit [db999c8](https://github.com/fireblocks/reference-protocols/commit/db999c8032f1d23847703d0946e502637d2d1708)._

### Retrieving the Whole Access List Might Revert

The [`AccessListUpgradeable`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/AccessRegistry/AccessListUpgradeable.sol#L152) contract includes a [`getAccessList`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/AccessRegistry/AccessListUpgradeable.sol#L203-205) function which retrieves all values from the access list. This function utilizes the [`values`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/5bc59992591b84bba18dc1ac46942f1886b30ccd/contracts/utils/structs/EnumerableSetUpgradeable.sol#L211-L229) function of `EnumerableSetUpgradeable.AddressSet`, copying the entire storage into memory. This might lead to problems when the access list is excessively large as the function execution remains susceptible to the block gas limit, resulting in the call getting reverted.

Consider implementing an additional function that can be used when the value set gets too large. This function should return only a subset or slice of the values from the entire set.

_**Update:** Acknowledged, partially resolved in commit [130dbb5](https://github.com/fireblocks/reference-protocols/commit/130dbb55351142f6382b97d175018fa6780d6134). The Fireblocks team stated:_

> _To address this issue, we've tackled it by incorporating additional documentation into the function. This decision was prompted by the fact that the purpose of getAccessList() is to serve as a support function tailored for fetching compact access lists in smaller projects. In the case of larger projects equipped with more extensive access lists, it is advisable to devise custom indexing logic to efficiently retrieve all addresses from the access list._

Notes & Additional Information
------------------------------

### Lack of Security Contact

Providing a specific security contact (e.g., an email address or ENS name) within a smart contract greatly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. Additionally, if the contract incorporates third-party libraries and a bug surfaces in them, it becomes easier for the maintainers of those libraries to contact the appropriate person about the problem and provide mitigation instructions.

Consider adding a NatSpec comment containing a security contact on top of the contract definitions. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Acknowledged, not resolved. The Fireblocks team stated:_

> _Because these contracts are crafted as templates for other companies and entities to deploy on a larger scale. There cannot be a single security contact. Therefore, when a company deploys one of these contracts, they are are welcome to provide their own security contact independently through the contract URI._

### Missing Named Parameters in Mapping

Since [Solidity 0.8.18](https://github.com/ethereum/solidity/releases/tag/v0.8.18), developers can utilize named parameters in mappings. This means mappings can take the form of `mapping(KeyType KeyName? => ValueType ValueName?)`. This updated syntax provides a more transparent representation of a mapping's purpose.

For instance, the [`_tokenUri`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/TokenUriUpgradeable.sol#L21) mapping in the [`TokenUriUpgradeable` contract](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/TokenUriUpgradeable.sol) does not utilize named parameters.

Consider adding named parameters to the mappings in order to improve readability and maintainability of the codebase.

_**Update:** Acknowledged, resolved in commit [967c097](https://github.com/fireblocks/reference-protocols/commit/967c09743a7dedd07c1524463064c7c6747c99b8)._

### Unnecessary Variable Cast

In the [`AccessRegistrySubscriptionUpgradeable` contract](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/AccessRegistry/AccessRegistrySubscriptionUpgradeable.sol), the `_accessRegistry` variable in the [`_accessRegistryUpdate` function](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/AccessRegistry/AccessRegistrySubscriptionUpgradeable.sol#L78) is unnecessarily casted.

To improve the overall clarity, intent, and readability of the codebase, consider removing any unnecessary casts.

_**Update:** Acknowledged, resolved in commit [69c5add](https://github.com/fireblocks/reference-protocols/commit/69c5addb6b95b72bd695318c6a65f91d205aaecc)._

### Unused Imports

Throughout the [codebase](https://github.com/fireblocks/reference-protocols/tree/e7003dfb9d89aa4b314a7428cbc59d07f178fd76), there are multiple imports that are unused and could be removed:

*   [`import {LibErrors} from "../Errors/LibErrors.sol";`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/ContractUriUpgradeable.sol#L7) imports unused alias `LibErrors` in [`ContractUriUpgradeable.sol`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/ContractUriUpgradeable.sol)
*   [`import {LibErrors} from "../Errors/LibErrors.sol";`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/MarketplaceOperatorUpgradeable.sol#L7) imports unused alias `LibErrors` in [`MarketplaceOperatorUpgradeable.sol`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/MarketplaceOperatorUpgradeable.sol)
*   [`import {LibErrors} from "../Errors/LibErrors.sol";`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/PauseUpgradeable.sol#L7) imports unused alias `LibErrors` in [`PauseUpgradeable.sol`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/PauseUpgradeable.sol)
*   [`import {LibErrors} from "../Errors/LibErrors.sol";`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/TokenUriUpgradeable.sol#L7) imports unused alias `LibErrors` in [`TokenUriUpgradeable.sol`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/TokenUriUpgradeable.sol)

Consider removing unused imports to improve the overall clarity and readability of the codebase.

_**Update:** Acknowledged, resolved in commit [4243399](https://github.com/fireblocks/reference-protocols/commit/4243399b59372a963f5ef1de8bfd7a682bad3092)._

### Lack of `__gap` Variables

Throughout the [codebase](https://github.com/fireblocks/reference-protocols/tree/e7003dfb9d89aa4b314a7428cbc59d07f178fd76), there are multiple upgradeable contracts that do not have a `__gap` variable. For instance:

*   The [`AllowList`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/AccessRegistry/AllowList.sol) contract
*   The [`DenyList`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/AccessRegistry/DenyList.sol) contract
*   The [`ERC721F`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/ERC721F.sol) contract

Note that the current implementation does not require the implementation of the `__gap` storage variable, as the listed contracts are not being inherited. However, it is still recommended to include it as it implies that the contract implementations might be upgraded and additional storage variables might be introduced in the future.

Consider adding a `__gap` storage variable to avoid future storage clashes in upgradeable contracts.

_**Update:** Acknowledged, not resolved. The Fireblocks team stated:_

> _Contracts lacking `__gap` variables are not needed for our use case since upgrades are intended to occur through contract inheritance. In this process, the initial implementation, `V1`, is inherited by `V2`, where the new logic resides. This enables the addition of storage slots without any conflict with existing slots._

### Incorrect Storage Gap Size in `AccessListUpgradeable`

The [`AccessListUpgradeable`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/AccessRegistry/AccessListUpgradeable.sol) contract uses a [`__gap`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/AccessRegistry/AccessListUpgradeable.sol#L305) storage variable of size `49`. It assumes that the `_accessList` storage variable occupies one storage slot, whereas in reality, it takes two storage slots. The `_accessList` is of type [`EnumerableSetUpgradeable.AddressSet`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/5bc59992591b84bba18dc1ac46942f1886b30ccd/contracts/utils/structs/EnumerableSetUpgradeable.sol#L233-L235) which is a struct that uses [2 storage slots](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/5bc59992591b84bba18dc1ac46942f1886b30ccd/contracts/utils/structs/EnumerableSetUpgradeable.sol#L51-L57).

Consider changing the size of the `__gap` storage variable in the `AccessListUpgradeable` contract from `49` to `48`.

_**Update:** Acknowledged, resolved in commit [519e415](https://github.com/fireblocks/reference-protocols/commit/519e4156513b940a410e3647be1c11c272ee1863)._

### Confusing Error Used

The [`ERC721F`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/ERC721F.sol) contract features a `recoverTokens` function designed to recover tokens from accounts lacking access. The problem arises when the account already has access to the tokens, resulting in transactions reverting with a potentially confusing error such as `ERC721InvalidReceiver`. In this context, since the account is not the receiver, the error should not imply receiver-related issues.

Consider adding a new error which indicates that the account has access to the tokens.

_**Update:** Acknowledged, resolved in commit [6b3f311](https://github.com/fireblocks/reference-protocols/commit/6b3f31143aa54a3fc4a6faeef462e7292bbb621b)._

### Typographical Errors and Incorrect Comments

Consider addressing the following typographical errors and incorrect comments:

*   The [`AccessRegistrySubscriptionUpgradeable`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/AccessRegistry/AccessRegistrySubscriptionUpgradeable.sol) contract implements the [`__AccessRegsitrySubscription_init`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/AccessRegistry/AccessRegistrySubscriptionUpgradeable.sol#L50-52) function that has a typo in its name. It should be `__AccessRegistrySubscription_init`.
*   The NatSpec comments that describe the `hasAccess` functions implemented in the [`AccessListUpgradeable`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/AccessRegistry/AccessListUpgradeable.sol#L211-212), [`AllowList`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/AccessRegistry/AllowList.sol#L63-64), and [`DenyList`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/AccessRegistry/DenyList.sol#L63-64) contracts are using the name of the parameter `claim` instead of `data`.

_**Update:** Acknowledged, resolved in commit [7a5e68e](https://github.com/fireblocks/reference-protocols/commit/7a5e68effb42048cc7e623e8178f636361174b41)._

### Gas Optimization

In the codebase, there are several instances of potential gas optimizations:

*   The `_requireHasAccess` function, present in the [`ERC721F`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/ERC721F.sol#L499-508) contract, redundantly checks the `isSender` value twice. It would be more efficient to initially verify if the account has access through the `accessRegistry` contract. If it does not have access, then based on the `isSender` value, either revert with an invalid sender or invalid receiver error.
*   The codebase follows a common pattern of checking access after updating state variables. For instance, in the [`RoleAccessUpgradeable`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/RoleAccessUpgradeable.sol) contract, the [`revokeRole`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/RoleAccessUpgradeable.sol#L42-49) function calls the [`_authorizeRoleAccess`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/RoleAccessUpgradeable.sol#L48) function after updating the role. To prioritize failing early and conserving gas, consider performing the access check before updating the state variables.

To improve gas consumption, readability and code quality, consider refactoring wherever possible.

_**Update:** Acknowledged, resolved in commit [f84408b](https://github.com/fireblocks/reference-protocols/commit/f84408b2dd3b2a79a125bd7b28c769e6bb46eb22)._

### Missing Functionality For Rescuing ERC-721 and ERC-1155 Tokens

The [`SalvageUpgradeable`](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/SalvageUpgradeable.sol) abstract contract, inherited by the `ERC721F` contract, implements the logic for [rescuing ETH](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/SalvageUpgradeable.sol#L80-90) and [ERC-20 tokens](https://github.com/fireblocks/reference-protocols/blob/e7003dfb9d89aa4b314a7428cbc59d07f178fd76/protocols/contracts/library/Utils/SalvageUpgradeable.sol#L61-68). This is useful for when tokens are accidentally sent to the token contract itself instead of a valid recipient. However, the rescue logic only works for rescuing ETH and ERC-20 tokens, not ERC-721 or ERC-1155 tokens. As such, while the ERC-20 tokens accidentally sent to any of the three token contracts can be rescued, ERC-721 or ERC-1155 tokens cannot be.

Consider adding the functionality for rescuing ERC-721 and ERC-1155 tokens accidentally sent to the `ERC721F` contract.

_**Update:** Acknowledged, not resolved. The Fireblocks team stated:_

> _Currently, there is no observed customer demand for salvaging an ERC-721 or ERC-1155 token. While this functionality could potentially be incorporated later through an upgrade, we are cautious about subjecting users to additional bytecode and gas fees for a feature that may not be utilized at the present moment._

Conclusion
----------

The Fireblocks Upgradeable Tokens project introduces upgradeable token contract adhering to ERC-721 standard, with added features for access control. These tokens allow the creation of an access list for transfers, enabling the implementation of either an allow list, restricting usage to specified addresses, or a deny list, preventing interactions with addresses on the list.

One high and one medium-severity vulnerability was identified, along with multiple lower-severity issues. In addition, various recommendations have been made to enhance the quality and documentation of the codebase. The Fireblocks team was responsive and timely answered any questions we had about the codebase.

[Request Audit](https://www.openzeppelin.com/cs/c/?cta_guid=dd34a2f8-61fa-4427-8382-ae576a88942a&signature=AAH58kEZxxE-oxNZLqF1KOPeR4qJC_ZimQ&utm_referrer=https%3A%2F%2Fwww.openzeppelin.com%2Fresearch&portal_id=7795250&pageId=186815616688&placement_guid=7809b604-3f30-4cd5-be58-36982828e327&click=f7693c31-2a3b-4ecb-90c4-b43ae0c31c23&redirect_url=APefjpF7eYD_Ijg7FDvnb2fyeVfPcT2uhoH6zBXFTSQNruYb3jwCGLUplJIlyvOPuXGI7rc6dlCSFBvnVrOO27F0NxaPdUdALXBiPxrj3dR4Rx_fVTYulo4cuRic9aAn-pn-1YKc5PUIGFzhw7IxC5__fMVUqbbUvBO_Ajybyon9ZAllJWL70Zxb6pZgIy2o-CHvgkueYoBKQAV8CYL2Okz8sxRlgdkySbJUfEcAr0MKcUeuMBNCjETP7_q4BmuzojvL7huyUO_N&hsutk=351cc181285977e4c1135a3559acf4f5&canon=https%3A%2F%2Fwww.openzeppelin.com%2Fnews%2Ffireblocks-upgradeable-tokens-audit-erc721f&ts=1770534169415&__hstc=214186568.351cc181285977e4c1135a3559acf4f5.1767592763816.1767595160995.1770533354098.3&__hssc=214186568.85.1770533354098&__hsfp=a36f2c5bd6c17376b30cddc39d50e7e0&contentType=blog-post "Request Audit")