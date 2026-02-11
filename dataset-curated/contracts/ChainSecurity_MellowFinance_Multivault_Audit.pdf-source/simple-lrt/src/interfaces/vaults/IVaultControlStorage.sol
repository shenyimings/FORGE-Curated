// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

/**
 * @title IVaultControlStorage
 * @notice Interface for interacting with the storage and control states of a vault.
 * @dev Provides functions to manage deposit and withdrawal controls, limits, and whitelisting of depositors.
 */
interface IVaultControlStorage {
    /**
     * @notice Storage structure for vault control data.
     * @dev Used to manage vault settings such as deposit and withdrawal states, limits, and whitelist functionality.
     * @param depositPause Indicates if deposits are currently paused.
     * @param withdrawalPause Indicates if withdrawals are currently paused.
     * @param limit The current limit on deposits.
     * @param depositWhitelist Indicates if the deposit whitelist is enabled.
     * @param isDepositorWhitelisted Mapping to track the whitelist status of each depositor by address.
     */
    struct Storage {
        bool depositPause;
        bool withdrawalPause;
        uint256 limit;
        bool depositWhitelist;
        mapping(address => bool) isDepositorWhitelisted;
    }

    /**
     * @notice Returns the current value of the `depositPause` state.
     * @dev When `true`, deposits into the vault are paused.
     * @return paused The current state of the deposit pause.
     */
    function depositPause() external view returns (bool);

    /**
     * @notice Returns the current value of the `withdrawalPause` state.
     * @dev When `true`, withdrawals from the vault are paused.
     * @return paused The current state of the withdrawal pause.
     */
    function withdrawalPause() external view returns (bool);

    /**
     * @notice Returns the current deposit limit.
     * @dev This limit can be applied to control the maximum allowed deposits.
     * @return limit The current limit value.
     */
    function limit() external view returns (uint256);

    /**
     * @notice Returns the current value of the `depositWhitelist` state.
     * @dev When `true`, only whitelisted addresses are allowed to deposit into the vault.
     * @return whitelistEnabled The current state of the deposit whitelist.
     */
    function depositWhitelist() external view returns (bool);

    /**
     * @notice Checks whether a given account is whitelisted for deposits.
     * @param account The address of the account to check.
     * @return isWhitelisted `true` if the account is whitelisted, `false` otherwise.
     */
    function isDepositorWhitelisted(address account) external view returns (bool);

    /**
     * @notice Emitted when the vault's deposit limit is updated.
     * @param limit The new limit value.
     * @param timestamp The time at which the limit was set.
     * @param sender The address of the account that set the new limit.
     */
    event LimitSet(uint256 limit, uint256 timestamp, address sender);

    /**
     * @notice Emitted when the deposit pause state is updated.
     * @param paused The new state of the deposit pause (`true` for paused, `false` for unpaused).
     * @param timestamp The time at which the pause state was set.
     * @param sender The address of the account that set the new state.
     */
    event DepositPauseSet(bool paused, uint256 timestamp, address sender);

    /**
     * @notice Emitted when the withdrawal pause state is updated.
     * @param paused The new state of the withdrawal pause (`true` for paused, `false` for unpaused).
     * @param timestamp The time at which the pause state was set.
     * @param sender The address of the account that set the new state.
     */
    event WithdrawalPauseSet(bool paused, uint256 timestamp, address sender);

    /**
     * @notice Emitted when the deposit whitelist state is updated.
     * @param status The new state of the deposit whitelist (`true` for enabled, `false` for disabled).
     * @param timestamp The time at which the whitelist state was set.
     * @param sender The address of the account that set the new state.
     */
    event DepositWhitelistSet(bool status, uint256 timestamp, address sender);

    /**
     * @notice Emitted when a depositor's whitelist status is updated.
     * @param account The address of the account whose whitelist status was updated.
     * @param status The new whitelist status (`true` for whitelisted, `false` for not whitelisted).
     * @param timestamp The time at which the whitelist status was set.
     * @param sender The address of the account that set the new status.
     */
    event DepositorWhitelistStatusSet(
        address account, bool status, uint256 timestamp, address sender
    );
}
