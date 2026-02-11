\- October 30, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

**Summary**

**Type:** Stablecoins  
**Timeline:** August 11, 2025 → August 13, 2025  
**Languages:** Solidity

**Findings**  
Total issues: 7 (5 resolved)  
Critical: 1 (1 resolved)  
High: 0 (0 resolved)  
Medium: 0 (0 resolved)  
Low: 1 (1 resolved)

**Notes & Additional Information**  
5 notes raised (3 resolved)

Scope
-----

OpenZeppelin audited the [bcp-markets/tGBPv2](https://github.com/bcp-markets/tGBPv2) repository at [commit 6a91650](https://github.com/bcp-markets/tGBPv2/tree/6a91650c2c5c5037718ff1e78e5a7a84873fddda).

In scope were the following files:

`contracts/
├── Bannable.sol
└── StableTokenV1OFT.sol` 

System Overview
---------------

This system implements tGBP, a cross-chain stablecoin with compliance controls, enabling token transfers across multiple blockchains while maintaining regulatory oversight through a ban list mechanism.

*   The **`StableTokenV1OFT`** contract is an upgradeable ERC-20 stablecoin that uses LayerZero's OFT standard for cross-chain transfers. It includes pausability for emergency stops, EIP-2612 permits for gasless approvals, and UUPS upgradeability. The owner can mint and burn tokens, and rescue accidentally sent tokens. All transfer operations check against the ban list before execution.
    
*   The **`Bannable`** contract is an abstract module that maintains an on-chain set of banned addresses. It allows the owner to ban/unban individual addresses or process batch bans, provides functions to query ban status and list all banned accounts, and enforces restrictions through the `notBanned` modifier that is used throughout the token contract.
    

This architecture establishes a compliant, cross-chain stablecoin system that upholds regulatory controls while enabling permissionless transfers, with LayerZero’s OFT integration facilitating native cross-chain token transfers.

Security Model and Trust Assumptions
------------------------------------

During the audit, the following trust assumptions were made:

*   The tGBP token is fully backed by at least one GBP per token, held in a bank account controlled by BCP Technologies.
*   Minting of new tokens may only occur once an equivalent GBP deposit has been received according to the team’s procedures.
*   For redemptions, users may deposit stablecoins to a designated address, after which the owner will burn the corresponding tokens and return the equivalent GBP amount. To ensure these processes remain functional, the owner role must never be renounced.
*   The owner can ban addresses, preventing them from transferring tokens, receiving tokens on the same chain, or granting and revoking approvals. This power is expected to be used sparingly, only in cases of legal violations or other serious and justified situations.
*   A banned address can still receive tokens from other chains, but any tokens in its possession—whether received locally or via cross-chain transfer—cannot be moved or bridged elsewhere.
*   The `StableTokenV1OFT` contract is upgradeable, allowing the owner to deploy updates when necessary to fix bugs or add approved features, provided that the core logic remains intact and user funds remain secure.
*   The owner will correctly configure LayerZero parameters, including setting the endpoint address and managing peer configurations, to maintain smooth cross-chain operation.

### Privileged Roles

The owner of the `StableTokenV1OFT` contract can:

*   ban and unban addresses
*   pause and unpause the contract (while paused, token transfers are disabled, but granting or revoking allowances remains possible)
*   mint and burn stablecoins to/from any address (burning requires prior approval from that address)
*   rescue and transfer tokens held by the contract to any non-banned address
*   configure the OFT contract

Critical Severity (Resolved)
----------------------------

### Banned Addresses Can Bypass Restrictions via Cross-Chain Transfers

The `StableTokenV1OFT` contract should enforce ban logic for cross-chain transfers to prevent banned addresses from bypassing restrictions. However, the `send` function of the `OFTUpgradeable` contract is not overridden. This allows a banned address on the source chain to perform a cross-chain token transfer and circumvent the ban.

Consider overriding the `send` function to include a ban check on the sender, preventing banned addresses from initiating cross-chain transfers.

_**Update:** Resolved in [pull request #1](https://github.com/bcp-markets/tGBPv2/pull/1) at [commit 99b3618](https://github.com/bcp-markets/tGBPv2/pull/1/commits/99b36189f284dfae49d2b7279d96c63ad527c825)._

_The `send` function was overridden by copying the implementation from the `OFTUpgradeable` contract and adding the `notBanned` modifier to ensure that `msg.sender` is not on the ban list._

_While the fix correctly resolves the issue, it is recommended to override the `send` function with the addition of the `notBanned` modifier. However, instead of copying the functionality of the contract, the `super` keyword should be used instead (`super.send`) to reduce redundancy. This would also help ensure that if the version of the OFT contracts dependency were to change, the functionality of the `send` function would align with this change._

Low Severity (Resolved)
-----------------------

### Non-Compliance with ERC-7201 in `Bannable`

In the `Bannable` contract, a [`banList`](https://github.com/bcp-markets/tGBPv2/blob/6a91650c2c5c5037718ff1e78e5a7a84873fddda/contracts/Bannable.sol#L17) variable of type [`EnumerableSet.AddressSet`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/99eda2225c0246c265c902475c47ec0c6321f119/contracts/utils/structs/EnumerableSet.sol#L307-L309) is defined. Since `Bannable` is an abstract contract, the storage position of this variable will depend on the inheritance order in the contract that extends it. Because `Bannable`, and any contract inheriting from it, is expected to be upgradeable (as indicated by its inheritance from [`OwnableUpgradeable`](https://github.com/bcp-markets/tGBPv2/blob/6a91650c2c5c5037718ff1e78e5a7a84873fddda/contracts/Bannable.sol#L10)), extra care must be taken to avoid storage collisions during upgrades.

Consider storing `banList` in a dedicated storage slot following the [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) standard. This will help improve the security posture of the contract and maintain consistency with parent contracts (such as `OwnableUpgradeable` that already follows ERC-7201).

_**Update:** Resolved in [pull request #1](https://github.com/bcp-markets/tGBPv2/pull/1) at [commit 99b3618](https://github.com/bcp-markets/tGBPv2/pull/1/commits/99b36189f284dfae49d2b7279d96c63ad527c825)._

_While namespaced storage has been implemented, the original `banList` variable still remains in the contract, although unused. It is recommended that this variable is either removed or renamed to clearly indicate that it should not be used._

Notes & Additional Information
------------------------------

### Unnecessary `return` Statement in `permit`

The [`permit`](https://github.com/bcp-markets/tGBPv2/blob/6a91650c2c5c5037718ff1e78e5a7a84873fddda/contracts/StableTokenV1OFT.sol#L153-L161) function of the `StableTokenV1OFT` contract overrides [`ERC20PermitUpgradeable::permit`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/d83fc65ee4b24aa50a6d42e4510cee1566067a98/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol#L47-L70). Neither function has a return value in its definition. However, in the body of `StableTokenV1OFT::permit`, there is a `return super.permit()` statement.

Consider removing the `return` keyword to simplify the code.

_**Update:** Resolved in [pull request #1](https://github.com/bcp-markets/tGBPv2/pull/1) at [commit 99b3618](https://github.com/bcp-markets/tGBPv2/pull/1/commits/99b36189f284dfae49d2b7279d96c63ad527c825)._

### Inconsistent Freeze Enforcement for Banned Addresses

Banned addresses should have their approval states and balances completely frozen, with no mechanism capable of modifying them. However, while the `StableTokenV1OFT` contract blocks banned addresses from calling the `approve` and `transfer` functions, the owner can still burn tokens from a banned address if prior approval had been given. This process internally calls `_spendAllowance()`, which modifies the banned address’s approval state and balance. This creates an inconsistency, as the approval and balance states of banned addresses are expected to remain unchanged.

Consider preventing burns from banned addresses.

_**Update:** Resolved in [pull request #1](https://github.com/bcp-markets/tGBPv2/pull/1) at [commit 99b3618](https://github.com/bcp-markets/tGBPv2/pull/1/commits/99b36189f284dfae49d2b7279d96c63ad527c825)._

### Enhance Ownership Transfers

The `StableTokenV1OFT` contract owner is responsible for minting and burning tokens. The tGBP token is intended to function as a GBP-backed stablecoin, and every minting or burning operation should always follow an actual GBP transfer to or from the user. This requires the contract to always have an active owner. The `StableTokenV1OFT` contract inherits `OwnableUpgradeable`, which includes a [`renounceOwnership`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/d83fc65ee4b24aa50a6d42e4510cee1566067a98/contracts/access/OwnableUpgradeable.sol#L94-L96) function. If ownership is renounced, the stablecoin will no longer be able to function. Extra care is also needed when the ownership is transferred to a new address.

Consider overriding and disabling the `renounceOwnership` function to ensure the `StableTokenV1OFT` contract always has an owner. Consider also using the [`Ownable2StepUpgradeable`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/master/contracts/access/Ownable2StepUpgradeable.sol) contract that prevents accidental ownership transfers.

_**Update:** Acknowledged, not resolved._

### Lack of User Association in Burn Events for GBP Redemptions

When a user redeems tGBP tokens for GBP, the process should be as follows:

1.  The user sends their tokens to a dedicated burn address. The `StableTokenV1OFT` contract has approval for this address.
2.  The owner of the `StableTokenV1OFT` contract detects this transfer and burns the token from the dedicated burn address.
3.  The corresponding GBP transfer to the user is performed (off-chain).

However, this entire process is hidden from the perspective of the `StableTokenV1OFT` contract. The [`burn`](https://github.com/bcp-markets/tGBPv2/blob/6a91650c2c5c5037718ff1e78e5a7a84873fddda/contracts/StableTokenV1OFT.sol#L81-L86) function simply emits a [`Transfer(from address(0), amount)` event](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/d83fc65ee4b24aa50a6d42e4510cee1566067a98/contracts/token/ERC20/ERC20Upgradeable.sol#L227), where `from` is always the dedicated burn address, with no link to the specific user initiating the redemption. This design is error-prone, as the on-chain records related to the `StableTokenV1OFT` contract do not indicate which user a burn corresponds to.

Consider allowing the owner to specify the user associated with each burn and include this information in the event emitted by the `burn` function.

_**Update:** Acknowledged, not resolved._

### Impossible for Holders to Revoke Allowance Granted to a Banned Spender

The [`approve`](https://github.com/bcp-markets/tGBPv2/blob/6a91650c2c5c5037718ff1e78e5a7a84873fddda/contracts/StableTokenV1OFT.sol#L133-L141) and [`permit`](https://github.com/bcp-markets/tGBPv2/blob/6a91650c2c5c5037718ff1e78e5a7a84873fddda/contracts/StableTokenV1OFT.sol#L153-L161) functions of the `StableTokenV1OFT` contract are guarded by a `notBanned(spender)` modifier. While this prevents granting new allowances to banned addresses, it also blocks users from reducing or setting to zero any allowance they had granted to an address before the ban.

Consider allowing users to revoke allowances given to addresses before they had been banned.

_**Update:** Resolved in [pull request #1](https://github.com/bcp-markets/tGBPv2/pull/1) at [commit 99b3618](https://github.com/bcp-markets/tGBPv2/pull/1/commits/99b36189f284dfae49d2b7279d96c63ad527c825)._ 

Conclusion
----------

The code under review implements tGBP (`StableTokenV1OFT`) — a GBP-backed stablecoin with minting and burning capabilities that are controlled by the token contract owner. It inherits from the LayerZero OFT contract to enable cross-chain transfers and allows the contract owner to ban addresses. One critical-severity issue was identified concerning the lack of checks for banned addresses during cross-chain transfers.

The BCP Technologies team is appreciated for being responsive and providing detailed answers to all the questions posed by the audit team, ensuring a smooth and efficient audit process.