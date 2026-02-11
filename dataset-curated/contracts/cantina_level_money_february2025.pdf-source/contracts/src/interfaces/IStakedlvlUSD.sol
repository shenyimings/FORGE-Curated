// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IStakedlvlUSD {
    // Events //
    /// @notice Event emitted when the rewards are received
    event RewardsReceived(uint256 indexed amount);
    /// @notice Event emitted when frozen funds are received
    event FrozenFundsReceived(uint256 indexed amount);
    /// @notice Event emitted when the balance from an FULL_RESTRICTED_STAKER_ROLE user are redistributed
    event LockedAmountRedistributed(
        address indexed from,
        address indexed to,
        uint256 amount
    );
    /// @notice Event emitted when a FREEZER_ROLE user freezes an amount of the reserve
    event FrozenAmountUpdated(uint256 amount);

    event FrozenAmountWithdrawn(address indexed frozenReceiver, uint256 amount);
    event FrozenReceiverSet(
        address indexed oldReceiver,
        address indexed newReceiver
    );
    event FrozenReceiverSettingRenounced();

    event FreezablePercentageUpdated(
        uint16 oldFreezablePercentage,
        uint16 newFreezablePercentage
    );

    // Errors //
    /// @notice Error emitted shares or assets equal zero.
    error InvalidAmount();
    /// @notice Error emitted when owner attempts to rescue lvlUSD tokens.
    error InvalidToken();
    /// @notice Error emitted when slippage is exceeded on a deposit or withdrawal
    error SlippageExceeded();
    /// @notice Error emitted when a small non-zero share amount remains, which risks donations attack
    error MinSharesViolation();
    /// @notice Error emitted when owner is not allowed to perform an operation
    error OperationNotAllowed();
    /// @notice Error emitted when there is still unvested amount
    error StillVesting();
    /// @notice Error emitted when owner or denylist manager attempts to denylist owner
    error CantDenylistOwner();
    /// @notice Error emitted when the zero address is given
    error InvalidZeroAddress();
    /// @notice Error emitted when there is not enough balance
    error InsufficientBalance();
    /// @notice Error emitted when the caller cannot set a freezer
    error SettingFrozenReceiverDisabled();
    /// @notice Error emitted when trying to freeze more than max freezable
    error ExceedsFreezable();

    function transferInRewards(uint256 amount) external;

    function rescueTokens(address token, uint256 amount, address to) external;

    function getUnvestedAmount() external view returns (uint256);
}
