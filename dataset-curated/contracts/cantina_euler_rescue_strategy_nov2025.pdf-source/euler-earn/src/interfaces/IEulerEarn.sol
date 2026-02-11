// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IEulerEarnFactory} from "./IEulerEarnFactory.sol";

import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";

import {MarketConfig, PendingUint136, PendingAddress} from "../libraries/PendingLib.sol";

struct MarketAllocation {
    /// @notice The vault to allocate.
    IERC4626 id;
    /// @notice The amount of assets to allocate.
    uint256 assets;
}

interface IOwnable {
    function owner() external view returns (address);
    function transferOwnership(address) external;
    function renounceOwnership() external;
    function acceptOwnership() external;
    function pendingOwner() external view returns (address);
}

/// @dev This interface is used for factorizing IEulerEarnStaticTyping and IEulerEarn.
/// @dev Consider using the IEulerEarn interface instead of this one.
interface IEulerEarnBase {
    /// @notice The address of the Permit2 contract.
    function permit2Address() external view returns (address);

    /// @notice The address of the creator.
    function creator() external view returns (address);

    /// @notice The address of the curator.
    function curator() external view returns (address);

    /// @notice Stores whether an address is an allocator or not.
    function isAllocator(address target) external view returns (bool);

    /// @notice The current guardian. Can be set even without the timelock set.
    function guardian() external view returns (address);

    /// @notice The current fee.
    function fee() external view returns (uint96);

    /// @notice The fee recipient.
    function feeRecipient() external view returns (address);

    /// @notice The current timelock.
    function timelock() external view returns (uint256);

    /// @dev Stores the order of vaults in which liquidity is supplied upon deposit.
    /// @dev Can contain any vault. A vault is skipped as soon as its supply cap is reached.
    function supplyQueue(uint256) external view returns (IERC4626);

    /// @notice Returns the length of the supply queue.
    function supplyQueueLength() external view returns (uint256);

    /// @dev Stores the order of vault from which liquidity is withdrawn upon withdrawal.
    /// @dev Always contain all non-zero cap vault as well as all vault on which the Earn vault supplies liquidity,
    /// without duplicate.
    function withdrawQueue(uint256) external view returns (IERC4626);

    /// @notice Returns the length of the withdraw queue.
    function withdrawQueueLength() external view returns (uint256);

    /// @notice Returns the amount of assets that can be withdrawn from given strategy vault.
    /// @dev Accounts for internally tracked balance, ignoring direct shares transfer and for assets available in the strategy.
    function maxWithdrawFromStrategy(IERC4626 id) external view returns (uint256);

    /// @notice Returns the amount of assets expected to be supplied to the strategy vault.
    /// @dev Accounts for internally tracked balance, ignoring direct shares transfer.
    function expectedSupplyAssets(IERC4626 id) external view returns (uint256);

    /// @notice Stores the total assets managed by this vault when the fee was last accrued.
    function lastTotalAssets() external view returns (uint256);

    /// @notice Stores the missing assets due to realized bad debt or forced vault removal.
    /// @dev In order to cover those lost assets, it is advised to supply on behalf of address(1) on the vault
    /// (canonical method).
    function lostAssets() external view returns (uint256);

    /// @notice Submits a `newTimelock`.
    /// @dev Warning: Reverts if a timelock is already pending. Revoke the pending timelock to overwrite it.
    /// @dev In case the new timelock is higher than the current one, the timelock is set immediately.
    function submitTimelock(uint256 newTimelock) external;

    /// @notice Accepts the pending timelock.
    function acceptTimelock() external;

    /// @notice Revokes the pending timelock.
    /// @dev Does not revert if there is no pending timelock.
    function revokePendingTimelock() external;

    /// @notice Submits a `newSupplyCap` for the vault.
    /// @dev Warning: Reverts if a cap is already pending. Revoke the pending cap to overwrite it.
    /// @dev Warning: Reverts if a vault removal is pending.
    /// @dev In case the new cap is lower than the current one, the cap is set immediately.
    /// @dev For the sake of backwards compatibility, the max allowed cap can either be set to type(uint184).max or type(uint136).max.
    function submitCap(IERC4626 id, uint256 newSupplyCap) external;

    /// @notice Accepts the pending cap of the vault.
    function acceptCap(IERC4626 id) external;

    /// @notice Revokes the pending cap of the vault.
    /// @dev Does not revert if there is no pending cap.
    function revokePendingCap(IERC4626 id) external;

    /// @notice Submits a forced vault removal from the Earn vault, eventually losing all funds supplied to the vault.
    /// @notice This forced removal is expected to be used as an emergency process in case a vault constantly reverts.
    /// To softly remove a sane vault, the curator role is expected to bundle a reallocation that empties the vault
    /// first (using `reallocate`), followed by the removal of the vault (using `updateWithdrawQueue`).
    /// @dev Warning: Reverts for non-zero cap or if there is a pending cap. Successfully submitting a zero cap will
    /// prevent such reverts.
    function submitMarketRemoval(IERC4626 id) external;

    /// @notice Revokes the pending removal of the vault.
    /// @dev Does not revert if there is no pending vault removal.
    function revokePendingMarketRemoval(IERC4626 id) external;

    /// @notice Sets the name of the Earn vault.
    function setName(string memory newName) external;

    /// @notice Sets the symbol of the Earn vault.
    function setSymbol(string memory newSymbol) external;

    /// @notice Submits a `newGuardian`.
    /// @notice Warning: a malicious guardian could disrupt the Earn vault's operation, and would have the power to revoke
    /// any pending guardian.
    /// @dev In case there is no guardian, the guardian is set immediately.
    /// @dev Warning: Submitting a guardian will overwrite the current pending guardian.
    function submitGuardian(address newGuardian) external;

    /// @notice Accepts the pending guardian.
    function acceptGuardian() external;

    /// @notice Revokes the pending guardian.
    function revokePendingGuardian() external;

    /// @notice Sets `newAllocator` as an allocator or not (`newIsAllocator`).
    function setIsAllocator(address newAllocator, bool newIsAllocator) external;

    /// @notice Sets `curator` to `newCurator`.
    function setCurator(address newCurator) external;

    /// @notice Sets the `fee` to `newFee`.
    function setFee(uint256 newFee) external;

    /// @notice Sets `feeRecipient` to `newFeeRecipient`.
    function setFeeRecipient(address newFeeRecipient) external;

    /// @notice Sets `supplyQueue` to `newSupplyQueue`.
    /// @param newSupplyQueue is an array of enabled vaults, and can contain duplicate vaults, but it would only
    /// increase the cost of depositing to the vault.
    function setSupplyQueue(IERC4626[] calldata newSupplyQueue) external;

    /// @notice Updates the withdraw queue. Some vaults can be removed, but no vault can be added.
    /// @notice Removing a vault requires the vault to have 0 supply on it, or to have previously submitted a removal
    /// for this vault (with the function `submitMarketRemoval`).
    /// @notice Warning: Anyone can supply on behalf of the vault so the call to `updateWithdrawQueue` that expects a
    /// vault to be empty can be griefed by a front-run. To circumvent this, the allocator can simply bundle a
    /// reallocation that withdraws max from this vault with a call to `updateWithdrawQueue`.
    /// @dev Warning: Removing a vault with supply will decrease the fee accrued until one of the functions updating
    /// `lastTotalAssets` is triggered (deposit/mint/withdraw/redeem/setFee/setFeeRecipient).
    /// @dev Warning: `updateWithdrawQueue` is not idempotent. Submitting twice the same tx will change the queue twice.
    /// @param indexes The indexes of each vault in the previous withdraw queue, in the new withdraw queue's order.
    function updateWithdrawQueue(uint256[] calldata indexes) external;

    /// @notice Reallocates the vault's liquidity so as to reach a given allocation of assets on each given vault.
    /// @dev The behavior of the reallocation can be altered by state changes, including:
    /// - Deposits on the Earn vault that supplies to vaults that are expected to be supplied to during reallocation.
    /// - Withdrawals from the Earn vault that withdraws from vaults that are expected to be withdrawn from during
    /// reallocation.
    /// - Donations to the vault on vaults that are expected to be supplied to during reallocation.
    /// - Withdrawals from vaults that are expected to be withdrawn from during reallocation.
    /// @dev Sender is expected to pass `assets = type(uint256).max` with the last MarketAllocation of `allocations` to
    /// supply all the remaining withdrawn liquidity, which would ensure that `totalWithdrawn` = `totalSupplied`.
    /// @dev A supply in a reallocation step will make the reallocation revert if the amount is greater than the net
    /// amount from previous steps (i.e. total withdrawn minus total supplied).
    function reallocate(MarketAllocation[] calldata allocations) external;
}

/// @dev This interface is inherited by IEulerEarn so that function signatures are checked by the compiler.
/// @dev Consider using the IEulerEarn interface instead of this one.
interface IEulerEarnStaticTyping is IEulerEarnBase {
    /// @notice Returns the current configuration of each vault.
    function config(IERC4626) external view returns (uint112 balance, uint136 cap, bool enabled, uint64 removableAt);

    /// @notice Returns the pending guardian.
    function pendingGuardian() external view returns (address guardian, uint64 validAt);

    /// @notice Returns the pending cap for each vault.
    function pendingCap(IERC4626) external view returns (uint136 value, uint64 validAt);

    /// @notice Returns the pending timelock.
    function pendingTimelock() external view returns (uint136 value, uint64 validAt);
}

/// @title IEulerEarn
/// @author Forked with gratitude from Morpho Labs. Inspired by Silo Labs.
/// @custom:contact security@morpho.org
/// @custom:contact security@euler.xyz
/// @dev Use this interface for IEulerEarn to have access to all the functions with the appropriate function
/// signatures.
interface IEulerEarn is IEulerEarnBase, IERC4626, IERC20Permit, IOwnable {
    /// @notice Returns the address of the Ethereum Vault Connector (EVC) used by this contract.
    function EVC() external view returns (address);

    /// @notice Returns the current configuration of each vault.
    function config(IERC4626) external view returns (MarketConfig memory);

    /// @notice Returns the pending guardian.
    function pendingGuardian() external view returns (PendingAddress memory);

    /// @notice Returns the pending cap for each vault.
    function pendingCap(IERC4626) external view returns (PendingUint136 memory);

    /// @notice Returns the pending timelock.
    function pendingTimelock() external view returns (PendingUint136 memory);
}
