// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";

/// @title ErrorsLib
/// @author Forked with gratitude from Morpho Labs. Inspired by Silo Labs.
/// @custom:contact security@morpho.org
/// @custom:contact security@euler.xyz
/// @notice Library exposing error messages.
library ErrorsLib {
    /// @notice Thrown when the query is invalid.
    error BadQuery();

    /// @notice Thrown when the address passed is the zero address.
    error ZeroAddress();

    /// @notice Thrown when the caller doesn't have the curator role.
    error NotCuratorRole();

    /// @notice Thrown when the caller doesn't have the allocator role.
    error NotAllocatorRole();

    /// @notice Thrown when the caller doesn't have the guardian role.
    error NotGuardianRole();

    /// @notice Thrown when the caller doesn't have the curator nor the guardian role.
    error NotCuratorNorGuardianRole();

    /// @notice Thrown when the vault cannot be set in the supply queue.
    error UnauthorizedMarket(IERC4626 id);

    /// @notice Thrown when submitting a cap for a vault whose underlying asset does not correspond to the underlying
    /// asset of the Earn vault.
    error InconsistentAsset(IERC4626 id);

    /// @notice Thrown when the supply cap has been exceeded on vault during a reallocation of funds.
    error SupplyCapExceeded(IERC4626 id);

    /// @notice Thrown when the fee to set exceeds the maximum fee.
    error MaxFeeExceeded();

    /// @notice Thrown when the value is already set.
    error AlreadySet();

    /// @notice Thrown when a value is already pending.
    error AlreadyPending();

    /// @notice Thrown when submitting the removal of a vault when there is a cap already pending on that vault.
    error PendingCap(IERC4626 id);

    /// @notice Thrown when submitting a cap for a vault with a pending removal.
    error PendingRemoval();

    /// @notice Thrown when submitting a vault removal for a vault with a non zero cap.
    error NonZeroCap();

    /// @notice Thrown when vault is a duplicate in the new withdraw queue to set.
    error DuplicateMarket(IERC4626 id);

    /// @notice Thrown when vault is missing in the updated withdraw queue and the vault has a non-zero cap set.
    error InvalidMarketRemovalNonZeroCap(IERC4626 id);

    /// @notice Thrown when vault is missing in the updated withdraw queue and the vault has a non-zero supply.
    error InvalidMarketRemovalNonZeroSupply(IERC4626 id);

    /// @notice Thrown when vault is missing in the updated withdraw queue and the vault is not yet disabled.
    error InvalidMarketRemovalTimelockNotElapsed(IERC4626 id);

    /// @notice Thrown when there's no pending value to set.
    error NoPendingValue();

    /// @notice Thrown when the requested liquidity cannot be withdrawn from EulerEarn.
    error NotEnoughLiquidity();

    /// @notice Thrown when interacting with a non previously enabled vault.
    error MarketNotEnabled(IERC4626 id);

    /// @notice Thrown when the submitted timelock is above the max timelock.
    error AboveMaxTimelock();

    /// @notice Thrown when the submitted timelock is below the min timelock.
    error BelowMinTimelock();

    /// @notice Thrown when the timelock is not elapsed.
    error TimelockNotElapsed();

    /// @notice Thrown when too many vaults are in the withdraw queue.
    error MaxQueueLengthExceeded();

    /// @notice Thrown when setting the fee to a non zero value while the fee recipient is the zero address.
    error ZeroFeeRecipient();

    /// @notice Thrown when the amount withdrawn is not exactly the amount supplied.
    error InconsistentReallocation();

    /// @notice Thrown when all caps have been reached.
    error AllCapsReached();

    /// @notice Thrown when the `msg.sender` is not the admin nor the owner of the vault.
    error NotAdminNorVaultOwner();

    /// @notice Thrown when the reallocation fee given is wrong.
    error IncorrectFee();

    /// @notice Thrown when `withdrawals` is empty.
    error EmptyWithdrawals();

    /// @notice Thrown when `withdrawals` contains a duplicate or is not sorted.
    error InconsistentWithdrawals();

    /// @notice Thrown when the deposit vault is in `withdrawals`.
    error DepositMarketInWithdrawals();

    /// @notice Thrown when attempting to deposit amount of assets corresponding to zero shares.
    error ZeroShares();

    /// @notice Thrown when attempting to withdraw zero from a vault.
    error WithdrawZero(IERC4626 id);

    /// @notice Thrown when attempting to set max inflow/outflow above the MAX_SETTABLE_FLOW_CAP.
    error MaxSettableFlowCapExceeded();

    /// @notice Thrown when the fee transfer fails.
    error FeeTransferFailed(address feeRecipient);

    /// @notice Thrown when attempting to withdraw more than the available supply of a vault.
    error NotEnoughSupply(IERC4626 id);

    /// @notice Thrown when attempting to withdraw more than the max outflow of a vault.
    error MaxOutflowExceeded(IERC4626 id);

    /// @notice Thrown when attempting to supply more than the max inflow of a vault.
    error MaxInflowExceeded(IERC4626 id);

    /// @notice Thrown when the maximum uint128 is exceeded.
    error MaxUint128Exceeded();

    /// @notice Thrown when withdrawal is attempted to an address known to be an EVC sub-account
    error BadAssetReceiver();
}
