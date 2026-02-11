\- November 10, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

### Summary

**Type:** DeFi  
**Timeline:** June 6, 2025 → June 17, 2025  
**Languages:** Solidity

**Findings**  
Total issues: 4 (4 resolved)  
Critical: 0 (0 resolved)  
High: 0 (0 resolved)  
Medium: 0 (0 resolved)  
Low: 1 (1 resolved)

**Notes & Additional Information**  
3 (3 resolved)

Scope
-----

OpenZeppelin audited the [Liquid-Bitcoin/BARD](https://github.com/Liquid-Bitcoin/BARD) repository at commit [9406679](https://github.com/Liquid-Bitcoin/BARD/commit/94066790393758eb817e50be318f1fb427c5d3c0).

In scope were the following files:

`contracts
└──  BARD
     ├── BARD.sol
     └── IBARD.sol` 

System Overview
---------------

The `BARD` contract implements an ERC-20-compliant token with extended functionalities, leveraging multiple ERC-20 extensions from the OpenZeppelin library. Specifically, `BARD` inherits from [`ERC20Votes`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Votes.sol), enabling the on-chain tracking of historical voting power for each account. Each BARD token represents one vote. However, by default, token balances do not count toward voting power. Users must explicitly delegate voting rights to themselves or another account for their voting power to be tracked. For more details on this behavior, refer to the `ERC20Votes` documentation.

The `BARD` contract also inherits the following contracts:

*   [**`ERC20Permit`**](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Permit.sol): Allows token holders to authorize allowances via off-chain signatures, enabling gasless approvals.
*   [**`ERC20Burnable`**](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Burnable.sol): Enables holders to burn their own tokens or tokens they have been approved to spend.
*   [**`Ownable2Step`**](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable2Step.sol): Introduces a two-step ownership transfer process. The current owner can set a new owner, who must then explicitly accept the role. In addition, the `BARD` contract overrides the `renounceOwnership` function, making it revert on each call, which ensures that the contract always has an owner.

Granting the approval of BARD tokens via off-chain signing or signing a delegation message for voting requires including a nonce in the message and incrementing it after the action is executed. A single [`_nonces`](https://github.com/Liquid-Bitcoin/BARD/blob/94066790393758eb817e50be318f1fb427c5d3c0/contracts/BARD/BARD.sol#L71-L76) mapping is used for both actions. Therefore, the nonce associated with an address will increase after either action is performed.

### Privileged Roles

The `owner` address is the only privileged role in the system. It is the only address that can mint new BARD tokens to a specified address with the following constraints:

*   **Frequency**: Minting is limited to at most once per year.
*   **Cap**: Each minting event cannot increase the total token supply at the time of the minting by more than 10%.

On deployment, an [initial supply of 1 billion BARD tokens](https://github.com/Liquid-Bitcoin/BARD/blob/94066790393758eb817e50be318f1fb427c5d3c0/contracts/BARD/BARD.sol#L30) will be minted to an address specified by the deployer. The `BARD` contract does not specify how the initial supply or any other minted tokens will be distributed.

Low Severity
------------

### Duplicate Event Emission in `mint`

The `mint` function [emits a custom `Mint(to, amount)` event](https://github.com/Liquid-Bitcoin/BARD/blob/94066790393758eb817e50be318f1fb427c5d3c0/contracts/BARD/BARD.sol#L49). However, the `ERC20._mint` function that is called also emits a `Transfer(address(0), to, amount)` event, which conveys the same information. As a result, two events with the same content are emitted for a single minting action, which may cause confusion for the users. In addition, the constructor also mints BARD tokens but does not emit a `Mint` event.

Consider removing the redundant `Mint` event to simplify the code and maintain consistency.

_**Update:** Resolved at commits [2159d25](https://github.com/Liquid-Bitcoin/BARD/commit/2159d256650055e05d8190675fb378e936a85f1d) and [cb57a21](https://github.com/Liquid-Bitcoin/BARD/commit/cb57a210d73f41cc466396251445b470d033fcd3)._

Notes & Additional Information
------------------------------

Throughout the codebase, multiple instances of misleading or inaccurate comments were identified:

*   A comment in the constructor states:

> first mint not allowed until 1 year after deployment

However, the constructor will mint 1 billion tokens on contract deployment. Thus, it should be clarified that it is not the first mint, but the next mint after initialization.

*   The [comment above `mint`](https://github.com/Liquid-Bitcoin/BARD/blob/94066790393758eb817e50be318f1fb427c5d3c0/contracts/BARD/BARD.sol#L37) states:

> Only callable by the owner once per year and amount must be less than max inflation rate

This description is slightly inaccurate. The `amount` must be less than the product of the maximum inflation rate and the current total supply, not just the maximum inflation rate.

*   The comment above `nonces` states:

> Override of the nonces function to satisfy both IERC20Permit and Nonces

However, it should correctly state that it overrides `ERC20Permit`. Furthermore, it would be beneficial for the users to explicitly mention that these nonces are used for both token permits and voting delegation.

Consider updating the comments to accurately reflect the logic and intention of the code.

_**Update:** Resolved at commits [2159d25](https://github.com/Liquid-Bitcoin/BARD/commit/2159d256650055e05d8190675fb378e936a85f1d) and [cb57a21](https://github.com/Liquid-Bitcoin/BARD/commit/cb57a210d73f41cc466396251445b470d033fcd3)._

### Inconsistent Variable Types May Hinder Optimization and Readability

The [`BARD` contract](https://github.com/Liquid-Bitcoin/BARD/blob/94066790393758eb817e50be318f1fb427c5d3c0/contracts/BARD/BARD.sol#L12) currently defines constants and variables using integer types such as `uint8` for [`MAX_INFLATION`](https://github.com/Liquid-Bitcoin/BARD/blob/94066790393758eb817e50be318f1fb427c5d3c0/contracts/BARD/BARD.sol#L14), `uint32` for [`MINT_WAIT_PERIOD`](https://github.com/Liquid-Bitcoin/BARD/blob/94066790393758eb817e50be318f1fb427c5d3c0/contracts/BARD/BARD.sol#L17), and `uint40` for [`lastMintTimestamp`](https://github.com/Liquid-Bitcoin/BARD/blob/94066790393758eb817e50be318f1fb427c5d3c0/contracts/BARD/BARD.sol#L20). While these sizes suffice for the values involved, since `MAX_INFLATION` and `MINT_WAIT_PERIOD` are constants, they are embedded in the bytecode and not written into a storage slot, meaning there is no benefit from storage packing. Furthermore, the `lastMintTimestamp` will have to be masked to `uint256` every time the function `mint` is called, which will have a slight extra gas cost.

Consider standardizing by using `uint256` for `MAX_INFLATION` and `MINT_WAIT_PERIOD` for improved clarity, and for `lastMintTimestamp` as well in order to slightly reduce gas usage on every `mint` call.

_**Update:** Resolved at commits [2159d25](https://github.com/Liquid-Bitcoin/BARD/commit/2159d256650055e05d8190675fb378e936a85f1d) and [cb57a21](https://github.com/Liquid-Bitcoin/BARD/commit/cb57a210d73f41cc466396251445b470d033fcd3)._

### Redundant Zero-Address Check in Constructor

In the constructor of the `BARD` contract, a [`check`](https://github.com/Liquid-Bitcoin/BARD/blob/94066790393758eb817e50be318f1fb427c5d3c0/contracts/BARD/BARD.sol#L28) is performed to ensure that `_treasury` is not the zero address before minting tokens to it. This check is intended to prevent accidentally not setting it during deployment. However, this validation is redundant, as the [`ERC20._mint`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/f27019d48eee32551e5c9d31849afcaa99944545/contracts/token/ERC20/ERC20.sol#L214-L219) function already includes a check which ensures that the recipient is not `address(0)`and reverts with an appropriate message otherwise.

Consider removing the redundant check from the constructor to simplify the code and make it consistent with the [`mint`](https://github.com/Liquid-Bitcoin/BARD/blob/94066790393758eb817e50be318f1fb427c5d3c0/contracts/BARD/BARD.sol#L39-L50) function, which does not include this extra check.

_**Update:** Resolved at commits [2159d25](https://github.com/Liquid-Bitcoin/BARD/commit/2159d256650055e05d8190675fb378e936a85f1d) and [cb57a21](https://github.com/Liquid-Bitcoin/BARD/commit/cb57a210d73f41cc466396251445b470d033fcd3)._ 

Conclusion
----------

The `BARD` contract implements a standard ERC-20 token with some extra features, leveraging OpenZeppelin's contracts.

The audit did not reveal any security concerns. Overall, the code is well structured and adheres to best practices. The Liquid Bitcoin Foundation team was cooperative and provided all necessary context, enabling a smooth and effective audit process.