// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IWithdrawalQueue} from "./IWithdrawalQueue.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVault as ISymbioticVault} from "@symbiotic/core/interfaces/vault/IVault.sol";

/**
 * @title ISymbioticWithdrawalQueue
 * @notice Interface to handle the withdrawal process from the Symbiotic Vault.
 * @dev This interface is an extension of IWithdrawalQueue for interacting specifically with the Symbiotic Vault.
 */
interface ISymbioticWithdrawalQueue is IWithdrawalQueue {
    /**
     * @notice Struct to hold epoch-related data.
     * @param isClaimed Indicates whether the epoch has been claimed.
     * @param sharesToClaim The amount of shares to be claimed.
     * @param claimableAssets The amount of assets that can be claimed.
     */
    struct EpochData {
        bool isClaimed;
        uint256 sharesToClaim;
        uint256 claimableAssets;
    }

    /**
     * @notice Struct to store account-related data for withdrawals.
     * @param sharesToClaim A mapping of epochs to shares to be claimed for a given epoch.
     * @param claimableAssets The total amount of assets that can be claimed.
     * @param claimEpoch The most recent epoch requested for withdrawal.
     */
    struct AccountData {
        mapping(uint256 => uint256) sharesToClaim;
        uint256 claimableAssets;
        uint256 claimEpoch;
    }

    /**
     * @notice Returns the address of the associated MellowSymbioticVault.
     * @return vault The address of the MellowSymbioticVault.
     */
    function vault() external view returns (address);

    /**
     * @notice Returns the address of the associated Symbiotic Vault.
     * @return symbioticVault The address of the Symbiotic Vault.
     */
    function symbioticVault() external view returns (ISymbioticVault);

    /**
     * @notice Returns the address of the collateral token used by the vault.
     * @dev The collateral token is the same as the vault's asset.
     * @return collateralAddress The address of the collateral token.
     */
    function collateral() external view returns (address);

    /**
     * @notice Returns the current epoch of the Symbiotic Vault.
     * @return currentEpoch The current epoch of the Symbiotic Vault.
     */
    function getCurrentEpoch() external view returns (uint256);

    /**
     * @notice Returns the data for a specific account.
     * @param account The address of the account to retrieve data for.
     * @return sharesToClaimPrev The amount of shares to claim for the epoch before the last requested epoch.
     * @return sharesToClaim The amount of shares to claim for the last requested epoch.
     * @return claimableAssets The total amount of assets that can be claimed.
     * @return claimEpoch The most recent epoch requested for withdrawal.
     */
    function getAccountData(address account)
        external
        view
        returns (
            uint256 sharesToClaimPrev,
            uint256 sharesToClaim,
            uint256 claimableAssets,
            uint256 claimEpoch
        );

    /**
     * @notice Returns the data for a specific epoch.
     * @param epoch The epoch number to retrieve data for.
     * @return epochData The data for the specified epoch.
     */
    function getEpochData(uint256 epoch) external view returns (EpochData memory);

    /**
     * @notice Returns the total amount of pending assets awaiting withdrawal.
     * @dev This amount may decrease due to slashing events in the Symbiotic Vault.
     * @return assets The total amount of assets pending withdrawal.
     */
    function pendingAssets() external view returns (uint256);

    /**
     * @notice Returns the amount of assets in the withdrawal queue for a specific account that cannot be claimed yet.
     * @param account The address of the account.
     * @return assets The amount of pending assets in the withdrawal queue for the account.
     */
    function pendingAssetsOf(address account) external view returns (uint256 assets);

    /**
     * @notice Returns the amount of assets that can be claimed by an account.
     * @param account The address of the account.
     * @return assets The amount of assets claimable by the account.
     */
    function claimableAssetsOf(address account) external view returns (uint256 assets);

    /**
     * @notice Requests the withdrawal of a specified amount of collateral for a given account.
     * @param account The address of the account requesting the withdrawal.
     * @param amount The amount of collateral to withdraw.
     *
     * @custom:requirements
     * - `msg.sender` MUST be the vault.
     * - `amount` MUST be greater than zero.
     *
     * @custom:effects
     * - Emits a `WithdrawalRequested` event.
     */
    function request(address account, uint256 amount) external;

    /**
     * @notice Claims assets from the Symbiotic Vault for a specified epoch to the Withdrawal Queue address.
     * @param epoch The epoch number.
     * @dev Emits an EpochClaimed event.
     */
    function pull(uint256 epoch) external;

    /**
     * @notice Finalizes the withdrawal process for a specific account and transfers assets to the recipient.
     * @param account The address of the account requesting the withdrawal.
     * @param recipient The address of the recipient receiving the withdrawn assets.
     * @param maxAmount The maximum amount of assets to withdraw.
     * @return amount The actual amount of assets withdrawn.
     */
    function claim(address account, address recipient, uint256 maxAmount)
        external
        returns (uint256 amount);

    /**
     * @notice Handles the pending epochs for a specific account and makes assets claimable for recent epochs.
     * @param account The address of the account.
     * @dev Emits an EpochClaimed event.
     */
    function handlePendingEpochs(address account) external;

    /// @notice Emitted when a withdrawal request is created.
    event WithdrawalRequested(address indexed account, uint256 indexed epoch, uint256 amount);

    /// @notice Emitted when assets are successfully claimed for a specific epoch.
    event EpochClaimed(uint256 indexed epoch, uint256 claimedAssets);

    /// @notice Emitted when assets are successfully withdrawn and transferred to a recipient.
    event Claimed(address indexed account, address indexed recipient, uint256 amount);

    /// @notice Emitted when pending assets are successfully transferred from one account to another.
    event Transfer(address indexed from, address indexed to, uint256 indexed epoch, uint256 amount);
}
