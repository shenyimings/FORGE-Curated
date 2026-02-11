// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IBoringOnChainQueue} from "./IBoringOnChainQueue.sol";

interface IBoringSolver {
    enum SolveType {
        BORING_REDEEM, // Fill multiple user requests with a single transaction.
        BORING_REDEEM_MINT // Fill multiple user requests to redeem shares and mint new shares.
    }

    function boringSolve(
        address initiator,
        address boringVault,
        address solveAsset,
        uint256 totalShares,
        uint256 requiredAssets,
        bytes calldata solveData
    ) external;

    function boringRedeemSolve(
        IBoringOnChainQueue.OnChainWithdraw[] calldata requests,
        address teller,
        bool coverDeficit
    ) external;
}
