// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IBoringOnChainQueue {
    /**
     * @param allowWithdraws Whether or not withdraws are allowed for this asset.
     * @param secondsToMaturity The time in seconds it takes for the asset to mature.
     * @param minimumSecondsToDeadline The minimum time in seconds a withdraw request must be valid for before it is expired
     * @param minDiscount The minimum discount allowed for a withdraw request.
     * @param maxDiscount The maximum discount allowed for a withdraw request.
     * @param minimumShares The minimum amount of shares that can be withdrawn.
     * @param withdrawCapacity The maximum amount of total shares that can be withdrawn.
     *        - Can be set to type(uint256).max to allow unlimited withdraws.
     *        - Decremented when users make requests.
     *        - Incremented when users cancel requests.
     *        - Can be set by admin.
     */
    struct WithdrawAsset {
        bool allowWithdraws;
        uint24 secondsToMaturity;
        uint24 minimumSecondsToDeadline;
        uint16 minDiscount;
        uint16 maxDiscount;
        uint96 minimumShares;
        uint256 withdrawCapacity;
    }

    /**
     * @param nonce The nonce of the request, used to make it impossible for request Ids to be repeated.
     * @param user The user that made the request.
     * @param assetOut The asset that the user wants to withdraw.
     * @param amountOfShares The amount of shares the user wants to withdraw.
     * @param amountOfAssets The amount of assets the user will receive.
     * @param creationTime The time the request was made.
     * @param secondsToMaturity The time in seconds it takes for the asset to mature.
     * @param secondsToDeadline The time in seconds the request is valid for.
     */
    struct OnChainWithdraw {
        uint96 nonce; // read from state, used to make it impossible for request Ids to be repeated.
        address user; // msg.sender
        address assetOut; // input sanitized
        uint128 amountOfShares; // input transferred in
        uint128 amountOfAssets; // derived from amountOfShares and price
        uint40 creationTime; // time withdraw was made
        uint24 secondsToMaturity; // in contract, from withdrawAsset?
        uint24 secondsToDeadline; // in contract, from withdrawAsset? To get the deadline you take the creationTime add seconds to maturity, add the secondsToDeadline
    }

    function withdrawAssets(address assetOut) external view returns (WithdrawAsset memory);
    function setWithdrawCapacity(address assetOut, uint256 withdrawCapacity) external;
    function updateWithdrawAsset(
        address assetOut,
        uint24 secondsToMaturity,
        uint24 minimumSecondsToDeadline,
        uint16 minDiscount,
        uint16 maxDiscount,
        uint96 minimumShares
    ) external;

    function requestOnChainWithdraw(address assetOut, uint128 amountOfShares, uint16 discount, uint24 secondsToDeadline)
        external
        returns (bytes32 requestId);
    function cancelOnChainWithdraw(OnChainWithdraw memory request) external returns (bytes32 requestId);
    function replaceOnChainWithdraw(OnChainWithdraw memory oldRequest, uint16 discount, uint24 secondsToDeadline)
        external
        returns (bytes32 oldRequestId, bytes32 newRequestId);
    function owner() external view returns (address);
    function authority() external view returns (address);
    function boringVault() external view returns (address);
    function accountant() external view returns (address);

    function getRequestIds() external view returns (bytes32[] memory);
    function solveOnChainWithdraws(OnChainWithdraw[] calldata requests, bytes calldata solveData, address solver)
        external;

    function previewAssetsOut(address assetOut, uint128 amountOfShares, uint16 discount)
        external
        view
        returns (uint128 amountOfAssets);
    function nonce() external view returns (uint96);
}
