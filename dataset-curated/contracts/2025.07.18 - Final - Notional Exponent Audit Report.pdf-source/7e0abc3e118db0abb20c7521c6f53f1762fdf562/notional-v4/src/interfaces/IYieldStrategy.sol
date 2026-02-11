// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IOracle} from "./Morpho/IOracle.sol";
import {MarketParams} from "./Morpho/IMorpho.sol";
import {IMorphoLiquidateCallback, IMorphoFlashLoanCallback} from "./Morpho/IMorphoCallbacks.sol";

/**
 * @notice A strategy vault that is specifically designed for leveraged yield
 * strategies. Minting and burning shares are restricted to the `enterPosition`
 * and `exitPosition` functions respectively. This means that shares will be
 * exclusively held on lending markets as collateral unless the LendingMarket is
 * set to NONE. In this case, the user will just be holding the yield token without
 * any leverage.
 *
 * The `transfer` function is non-standard in that transfers off of a lending market
 * are restricted to ensure that liquidation conditions are met.
 *
 * This contract also serves as its own oracle.
 */
interface IYieldStrategy is IERC20, IERC20Metadata, IOracle {
    event VaultCreated(address indexed vault);

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function asset() external view returns (address assetTokenAddress);

    /**
     * @dev Returns the address of the yield token held by the vault. Does not equal the share token,
     * which represents each user's share of the yield tokens held by the vault.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function yieldToken() external view returns (address yieldTokenAddress);

    /**
     * @dev Returns the total amount of the underlying asset that is “managed” by Vault.
     *
     * - SHOULD include any compounding that occurs from yield.
     * - MUST be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT revert.
     */
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /**
     * @dev Returns the effective supply which excludes any escrowed shares.
     */
    function effectiveSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     *
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     * - MUST NOT revert.
     *
     * NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /**
     * @dev Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     *
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /**
     * @dev Returns the amount of yield tokens that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     */
    function convertSharesToYieldToken(uint256 shares) external view returns (uint256 yieldTokens);

    /**
     * @dev Returns the amount of yield tokens that the account would receive for the amount of shares provided.
     */
    function convertYieldTokenToShares(uint256 shares) external view returns (uint256 yieldTokens);

    /**
     * @dev Returns the oracle price of a yield token in terms of the asset token.
     */
    function convertYieldTokenToAsset() external view returns (uint256 price);

    /**
     * @dev Returns the fee rate of the vault where 100% = 1e18.
     */
    function feeRate() external view returns (uint256 feeRate);

    /**
     * @dev Returns the balance of yield tokens accrued by the vault.
     */
    function feesAccrued() external view returns (uint256 feesAccruedInYieldToken);

    /**
     * @dev Collects the fees accrued by the vault. Only callable by the owner.
     */
    function collectFees() external;

    /**
     * @dev Returns the price of a yield token in terms of the asset token for the
     * given borrower taking into account withdrawals.
     */
    function price(address borrower) external returns (uint256 price);

    /**
     * @notice Mints shares for a given number of assets.
     *
     * @param assets The amount of assets to mint shares for.
     * @param receiver The address to mint the shares to.
     * @param depositData calldata used to deposit the assets.
     */
    function mintShares(uint256 assets, address receiver, bytes memory depositData) external returns (uint256 sharesMinted);

    /** 
     * @notice Burns shares for a given number of shares.
     *
     * @param sharesOwner The address of the account to burn the shares for.
     * @param sharesToBurn The amount of shares to burn.
     * @param redeemData calldata used to redeem the yield token.
     */
    function burnShares(
        address sharesOwner,
        uint256 sharesToBurn,
        uint256 sharesHeld,
        bytes memory redeemData
    ) external returns (uint256 assetsWithdrawn);

    /**
     * @notice Allows the lending market to transfer shares on exit position
     * or liquidation.
     *
     * @param to The address to allow the transfer to.
     * @param amount The amount of shares to allow the transfer of.
     * @param currentAccount The address of the current account.
     */
    function allowTransfer(address to, uint256 amount, address currentAccount) external;

    /**
     * @notice Pre-liquidation function.
     *
     * @param liquidator The address of the liquidator.
     * @param liquidateAccount The address of the account to liquidate.
     * @param sharesToLiquidate The amount of shares to liquidate.
     * @param accountSharesHeld The amount of shares the account holds.
     */
    function preLiquidation(
        address liquidator,
        address liquidateAccount,
        uint256 sharesToLiquidate,
        uint256 accountSharesHeld
    ) external;

    /**
     * @notice Post-liquidation function.
     *
     * @param liquidator The address of the liquidator.
     * @param liquidateAccount The address of the account to liquidate.
     * @param sharesToLiquidator The amount of shares to liquidate.
     */
    function postLiquidation(
        address liquidator,
        address liquidateAccount,
        uint256 sharesToLiquidator
    ) external;

    /**
     * @notice Redeems shares for assets for a native token.
     *
     * @param sharesToRedeem The amount of shares to redeem.
     * @param redeemData calldata used to redeem the yield token.
     */
    function redeemNative(uint256 sharesToRedeem, bytes memory redeemData) external returns (uint256 assetsWithdrawn);

    /**
     * @notice Initiates a withdraw for a given number of shares.
     *
     * @param account The address of the account to initiate the withdraw for.
     * @param sharesHeld The number of shares the account holds.
     * @param data calldata used to initiate the withdraw.
     */
    function initiateWithdraw(
        address account,
        uint256 sharesHeld,
        bytes calldata data
    ) external returns (uint256 requestId);

    /**
     * @notice Initiates a withdraw for the native balance of the account.
     *
     * @param data calldata used to initiate the withdraw.
     */
    function initiateWithdrawNative(bytes calldata data) external returns (uint256 requestId);

    /**
     * @notice Clears the current account.
     */
    function clearCurrentAccount() external;
}
