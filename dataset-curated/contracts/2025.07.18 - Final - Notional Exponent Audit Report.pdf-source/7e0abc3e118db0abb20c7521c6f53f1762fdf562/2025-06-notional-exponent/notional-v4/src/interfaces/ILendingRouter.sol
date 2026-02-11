// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

struct VaultPosition {
    address lendingRouter;
    uint32 lastEntryTime;
}

interface ILendingRouter {

    /**
     * @dev Authorizes an address to manage a user's position.
     *
     * @param operator The address to authorize.
     * @param approved The authorization status.
     */
    function setApproval(address operator, bool approved) external;

    /**
     * @dev Returns the authorization status of an address.
     *
     * @param user The address to check the authorization status of.
     * @param operator The address to check the authorization status of.
     *
     * @return The authorization status.
     */
    function isApproved(address user, address operator) external view returns (bool);

    /**
     * @dev Enters a position in the lending market.
     *
     * @param onBehalf The address of the user to enter the position on behalf of.
     * @param vault The address of the vault.
     * @param depositAssetAmount The amount of margin to deposit.
     * @param borrowAmount The amount of assets to borrow.
     * @param depositData The data to pass to the deposit function.
     */
    function enterPosition(
        address onBehalf,
        address vault,
        uint256 depositAssetAmount,
        uint256 borrowAmount,
        bytes calldata depositData
    ) external;

    /**
     * @dev Migrates a position to the lending market.
     *
     * @param onBehalf The address of the user to migrate the position on behalf of.
     * @param vault The address of the vault.
     * @param migrateFrom The address of the lending router to migrate the position from.
     */
    function migratePosition(
        address onBehalf,
        address vault,
        address migrateFrom
    ) external;

    /**
     * @dev Exits a position in the lending market. Can be called by the user or another lending router
     * to migrate a position.
     *
     * @param onBehalf The address of the user to exit the position on behalf of.
     * @param vault The address of the vault.
     * @param receiver The address of the receiver.
     * @param sharesToRedeem The amount of shares to redeem.
     * @param assetToRepay The amount of assets to repay, if set to uint256.max the full debt will be repaid.
     * @param redeemData Vault specific instructions for the exit.
     */
    function exitPosition(
        address onBehalf,
        address vault,
        address receiver,
        uint256 sharesToRedeem,
        uint256 assetToRepay,
        bytes calldata redeemData
    ) external;

    /**
     * @dev Liquidates a position in the lending market.
     *
     * @param liquidateAccount The address of the account to liquidate.
     * @param vault The address of the vault.
     * @param seizedAssets The amount of assets to seize.
     * @param repaidShares The amount of shares to repay.
     *
     * @return sharesToLiquidator The amount of shares to liquidator.
     */
    function liquidate(
        address liquidateAccount,
        address vault,
        uint256 seizedAssets,
        uint256 repaidShares
    ) external returns (uint256 sharesToLiquidator);


    /**
     * @dev Returns the health factor of a user for a given vault.
     *
     * @param borrower The address of the borrower.
     * @param vault The address of the vault.
     *
     * @return borrowed The borrowed amount.
     * @return collateralValue The collateral value.
     * @return maxBorrow The max borrow amount.
     */
    function healthFactor(address borrower, address vault) external returns (uint256 borrowed, uint256 collateralValue, uint256 maxBorrow);

    /**
     * @dev Returns the balance of collateral of a user for a given vault.
     *
     * @param account The address of the account.
     * @param vault The address of the vault.
     *
     * @return collateralBalance The balance of collateral.
     */
    function balanceOfCollateral(address account, address vault) external view returns (uint256 collateralBalance);

    /**
     * @dev Initiates a withdraw request for a user for a given vault.
     *
     * @param onBehalf The address of the user to initiate the withdraw on behalf of.
     * @param vault The address of the vault.
     * @param data Vault specific instructions for the withdraw.
     *
     * @return requestId The request id.
     */
    function initiateWithdraw(address onBehalf, address vault, bytes calldata data) external returns (uint256 requestId);

    /**
     * @dev Forces a withdraw for a user for a given vault, only allowed if the health factor is negative.
     *
     * @param vault The address of the vault.
     * @param account The address of the account.
     * @param data Vault specific instructions for the withdraw.
     *
     * @return requestId The request id.
     */
    function forceWithdraw(address account, address vault, bytes calldata data) external returns (uint256 requestId);

    /**
     * @dev Claims rewards for a user for a given vault.
     *
     * @param vault The address of the vault.
     *
     * @return rewards The rewards.
     */
    function claimRewards(address vault) external returns (uint256[] memory rewards);
}

