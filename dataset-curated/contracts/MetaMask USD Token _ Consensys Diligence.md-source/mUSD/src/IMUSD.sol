// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/**
 * @title  MUSD Interface
 * @author M0 Labs
 *
 */
interface IMUSD {
    /* ============ Events ============ */

    /**
     * @notice Emitted when tokens are forcefully transferred from a frozen account.
     * @param  frozenAccount The address of the frozen account.
     * @param  recipient The address of the recipient.
     * @param  forcedTransferManager The address of the force transfer manager that triggered the event.
     * @param  amount The amount of tokens transferred.
     */
    event ForcedTransfer(
        address indexed frozenAccount,
        address indexed recipient,
        address indexed forcedTransferManager,
        uint256 amount
    );

    /* ============ Custom Errors ============ */

    /// @notice Emitted in constructor if Pauser is 0x0.
    error ZeroPauser();

    /// @notice Emitted in constructor if Force Transfer Manager is 0x0.
    error ZeroForcedTransferManager();

    /// @notice Emitted when the length of the input arrays do not match in `forceTransfer` method.
    error ArrayLengthMismatch();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Pauses the contract.
     * @dev    Can only be called by an account with the PAUSER_ROLE.
     */
    function pause() external;

    /**
     * @notice Unpauses the contract.
     * @dev    Can only be called by an account with the PAUSER_ROLE.
     */
    function unpause() external;

    /**
     * @notice Forcefully transfers tokens from frozen accounts to recipients.
     * @dev    Can only be called by an account with the FORCED_TRANSFER_MANAGER_ROLE.
     * @param  frozenAccounts The addresses of the frozen accounts.
     * @param  recipients The addresses of the recipients.
     * @param  amounts The amounts of tokens to transfer.
     */
    function forceTransfers(
        address[] calldata frozenAccounts,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external;

    /**
     * @notice Forcefully transfers tokens from a frozen account to a recipient.
     * @dev    Can only be called by an account with the FORCED_TRANSFER_MANAGER_ROLE.
     * @param  frozenAccount The address of the frozen account.
     * @param  recipient The address of the recipient.
     * @param  amount The amount of tokens to transfer.
     */
    function forceTransfer(address frozenAccount, address recipient, uint256 amount) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can pause and unpause the contract.
    function PAUSER_ROLE() external view returns (bytes32);

    /// @notice The role that can force transfer tokens from frozen accounts.
    function FORCED_TRANSFER_MANAGER_ROLE() external view returns (bytes32);
}
