// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

interface ISwapper {
    error ActionsFailed();
    error NoBalanceChange();
    error ZeroAddress();
    error LengthMismatch();
    error PctTooBig();

    event ClaimAndSwapped(address indexed user, address[] tokens, uint256[] claimAmounts, uint256 pct, Locked locked);

    struct Claim {
        address[] tokens;
        uint256[] amounts;
        bytes32[][] proofs;
    }

    struct Locked {
        uint256 tokenId;
        uint256 amount;
    }

    /// @notice Claims reward tokens and optionally swaps some/all to KAT, then locks a percentage.
    /// @dev Claims tokens from Merkle distributor, executes optional swaps to KAT, and locks % of
    ///      resulting KAT in escrow. Not all claimed tokens need to be swapped.
    /// @param _claim Tokens to claim with amounts and Merkle proofs
    /// @param _actions Swap actions to execute (optional, can be partial)
    /// @param _pct Percentage (0-100) of KAT to lock in escrow
    /// @return tokenAmountGained Total KAT gained from claims and swaps
    /// @return tokenId Escrow lock NFT ID if _pct > 0, else 0
    function claimAndSwap(
        Claim calldata _claim,
        Action[] calldata _actions,
        uint256 _pct
    )
        external
        returns (uint256 tokenAmountGained, uint256 tokenId);
}
