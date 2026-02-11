\- October 1, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

**Summary**

**Type:** Governance  
**Timeline:** September 22, 2025 → September 23, 2025  
**Languages:** Solidity

**Findings**  
Total issues: 4 (3 resolved)  
Critical: 0 (0 resolved) · High: 0 (0 resolved) · Medium: 0 (0 resolved) · Low: 0 (0 resolved)

**Notes & Additional Information**  
4 notes raised (3 resolved)

Scope
-----

OpenZeppelin audited [pull request #10](https://github.com/AcronymFoundation/anvil-contracts/pull/10) of the [AcronymFoundation/anvil-contracts](https://github.com/AcronymFoundation/anvil-contracts) repository at commit [606d5de](https://github.com/AcronymFoundation/anvil-contracts/tree/606d5deb988be3b97c587e88e5f74d63964eeaf1). As part of this audit, the implementation of the new Anvil governance token and its integration with the governance system were reviewed. Previously, in May 2024, an audit of the [AcronymFoundation/anvil-contracts](https://github.com/AcronymFoundation/anvil-contracts) repository was performed at commit [be6bd02](https://github.com/AcronymFoundation/anvil-contracts/commit/be6bd026831f0b0a83f5354b396426877b4c2371).

In scope were the following files:

`contracts
└── governance
    ├── Anvil.sol
    └── AnvilGovernorDelegate.sol` 

System Overview
---------------

The new [Anvil](https://github.com/AcronymFoundation/anvil-contracts/blob/606d5deb988be3b97c587e88e5f74d63964eeaf1/contracts/governance/Anvil.sol#L14) (ANVL) token has been designed to follow the standard `ERC20Votes` pattern, providing a more streamlined and broadly compatible voting mechanism. This is in contrast to the legacy Anvil token, which had custom logic to account for the delegated voting power of unclaimed airdropped tokens. By adopting the conventional `ERC20Votes` approach, the new design aligns the token with established governance standards. The total supply of the new Anvil token is capped at 100 billion, and all tokens are minted during deployment to a specified `destinationAddress` provided in the constructor.

In parallel, the [`AnvilGovernorDelegate`](https://github.com/AcronymFoundation/anvil-contracts/blob/606d5deb988be3b97c587e88e5f74d63964eeaf1/contracts/governance/AnvilGovernorDelegate.sol) contract will be upgraded, to introduce the [`reinitializeGovernanceToken`](https://github.com/AcronymFoundation/anvil-contracts/blob/606d5deb988be3b97c587e88e5f74d63964eeaf1/contracts/governance/AnvilGovernorDelegate.sol#L112) function, which allows the governor contract to be connected to the new Anvil token. Protected by the `onlyGovernance` modifier, this function can only be invoked through a governance proposal.

### Trust Assumptions

During the audit, the following trust assumptions were made:

*   During the [construction](https://github.com/AcronymFoundation/anvil-contracts/blob/606d5deb988be3b97c587e88e5f74d63964eeaf1/contracts/governance/Anvil.sol#L21) of the Anvil governance token, the token's total supply is immediately minted to a specified `destinationAddress`. It is assumed that this amount will be fairly distributed to the existing token holders during the funds migration process.
    
*   The migration from the legacy `ANVL` token contract to the new token contract will be carried out through an airdrop, based on a snapshot of current token holder balances. The migration logic itself was not part of this audit. It is assumed that the airdrop mechanism will be correctly implemented and executed, and that it will accurately reflect the intended balances of existing token holders. Both the legacy and new Anvil tokens will remain active in circulation. However, only the new token will be recognized by the governor contract for voting purposes.
    
*   As a result of token migration, token holders will need to re-delegate their new tokens in order for their voting power to be reflected, even if they had already delegated in the legacy system. This redelegation requirement represents a functional change in governance behavior and is assumed to be clearly communicated to token holders as part of the migration process to avoid confusion or unintended gaps in voting power.
    
*   It is assumed that users will be properly informed about the existence of two tokens in circulation. While both the legacy and new tokens may continue to be held or traded, only the new token will be valid for governance.
    

Notes & Additional Information
------------------------------

### Non-Explicit Imports

The use of non-explicit imports in the codebase can decrease code clarity and may create naming conflicts between locally defined and imported variables. This is particularly relevant when multiple contracts exist within the same Solidity file or when inheritance chains are long.

In the `Anvil` and `AnvilGovernorDelegate` contracts, global imports are being used. For example, `import "@openzeppelin/contracts/token/ERC20/ERC20.sol"` is used in [line 4](https://github.com/AcronymFoundation/anvil-contracts/blob/606d5deb988be3b97c587e88e5f74d63964eeaf1/contracts/governance/Anvil.sol#L4) of the `Anvil` contract.

Following the principle that clearer code is better code, consider using the named import syntax _(`import {A, B, C} from "X"`)_ to explicitly declare which contracts are being imported, such as, `import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol"`.

_**Update:** Resolved in [pull request #11](https://github.com/AcronymFoundation/anvil-contracts/pull/11) at commit [ed882f4](https://github.com/AcronymFoundation/anvil-contracts/pull/11/commits/ed882f49fd0d2f8ed1f4d4adad3d816447d38ccf)._

### Use Custom Errors

Since Solidity version 0.8.4, custom errors provide a cleaner and more cost-efficient way to explain to users why an operation failed.

The `AnvilGovernorDelegate` contract currently contains one [`revert("Cannot upgrade the timelock")`](https://github.com/AcronymFoundation/anvil-contracts/blob/606d5deb988be3b97c587e88e5f74d63964eeaf1/contracts/governance/AnvilGovernorDelegate.sol#L125) statement.

For conciseness, consider replacing `revert` message with custom errors.

_**Update:** Resoved in [pull request #12](https://github.com/AcronymFoundation/anvil-contracts/pull/12) at commit [d5bcd0b](https://github.com/AcronymFoundation/anvil-contracts/pull/12/commits/d5bcd0b1493b412de93f1969938a99781f0b041a)._

### EIP-712 Version Consistency in New `ANVL` Token Deployment

A new version of the ANVL token is planned for deployment at a new contract address. Since the [`verifyingContract`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/EIP712.sol#L38) field in the EIP-712 domain separator will change, signature replay from the previous deployment is not possible. However, keeping the [same EIP-712 version](https://github.com/AcronymFoundation/anvil-contracts/blob/606d5deb988be3b97c587e88e5f74d63964eeaf1/contracts/governance/Anvil.sol#L20) value may cause confusion when distinguishing between the legacy and the new contract. For clarity and stronger semantic versioning, it is advisable to increment the EIP-712 version in the new deployment.

Consider updating the EIP-712 version field in the newly deployed ANVL token to explicitly indicate the new release and avoid ambiguity in off-chain integrations.

_**Update:** Resolved in [pull request #13](https://github.com/AcronymFoundation/anvil-contracts/pull/13) at commit [172522a](https://github.com/AcronymFoundation/anvil-contracts/pull/13/commits/172522a649663c0c8ab2d7f221d78bc5ea3af698)._

### Incomplete Docstring

Within `AnvilGovernorDelegate.sol`, the [`initialize`](https://github.com/AcronymFoundation/anvil-contracts/blob/606d5deb988be3b97c587e88e5f74d63964eeaf1/contracts/governance/AnvilGovernorDelegate.sol#L87-L102) function has an incomplete docstring. For example, the `timelock_`, `governanceToken_`, `votingPeriod_`, `votingDelay_`, `proposalThreshold_` parameters are not documented.

Consider thoroughly documenting all functions/events (and their parameters or return values) that are part of a contract's public API. When writing docstrings, consider following the [Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html) (NatSpec).

_**Update:** Resolved in [pull request #14](https://github.com/AcronymFoundation/anvil-contracts/pull/14) at commit [a0661e7](https://github.com/AcronymFoundation/anvil-contracts/pull/14/commits/a0661e7b9a70400dcc02395c99ed0946a6c2cfab)._

Conclusion
----------

The audited code changes introduce a new version of the Anvil (ANVL) governance token. The legacy implementation relied on custom extensions to OpenZeppelin’s `ERC20Votes` contract to support airdrop claims and delegated voting during vesting. In contrast, the new version is a simplified implementation that directly extends the `ERC20Votes` contract, with all existing funds to be migrated to token holders, treating all tokens as fully vested.

Throughout the engagement, the Anvil Team has been highly responsive and cooperative, providing the audit team with clear explanations and valuable context regarding the planned migration process.