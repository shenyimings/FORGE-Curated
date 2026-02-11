// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FlowCapsConfig} from "../interfaces/IPublicAllocator.sol";

import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";

import {PendingAddress} from "./PendingLib.sol";

/// @title EventsLib
/// @author Forked with gratitude from Morpho Labs. Inspired by Silo Labs.
/// @custom:contact security@morpho.org
/// @custom:contact security@euler.xyz
/// @notice Library exposing events.
library EventsLib {
    /// @notice Emitted when the perspective is set.
    event SetPerspective(address);

    /// @notice Emitted when the name of the Earn vault is set.
    event SetName(string name);

    /// @notice Emitted when the symbol of the Earn vault is set.
    event SetSymbol(string symbol);

    /// @notice Emitted when a pending `newTimelock` is submitted.
    event SubmitTimelock(uint256 newTimelock);

    /// @notice Emitted when `timelock` is set to `newTimelock`.
    event SetTimelock(address indexed caller, uint256 newTimelock);

    /// @notice Emitted `fee` is set to `newFee`.
    event SetFee(address indexed caller, uint256 newFee);

    /// @notice Emitted when a new `newFeeRecipient` is set.
    event SetFeeRecipient(address indexed newFeeRecipient);

    /// @notice Emitted when a pending `newGuardian` is submitted.
    event SubmitGuardian(address indexed newGuardian);

    /// @notice Emitted when `guardian` is set to `newGuardian`.
    event SetGuardian(address indexed caller, address indexed guardian);

    /// @notice Emitted when a pending `cap` is submitted for a vault.
    event SubmitCap(address indexed caller, IERC4626 indexed id, uint256 cap);

    /// @notice Emitted when a new `cap` is set for a vault.
    event SetCap(address indexed caller, IERC4626 indexed id, uint256 cap);

    /// @notice Emitted when the vault's last total assets is updated to `updatedTotalAssets`.
    event UpdateLastTotalAssets(uint256 updatedTotalAssets);

    /// @notice Emitted when the vault's lostAssets is updated to `newLostAssets`.
    event UpdateLostAssets(uint256 newLostAssets);

    /// @notice Emitted when the vault is submitted for removal.
    event SubmitMarketRemoval(address indexed caller, IERC4626 indexed id);

    /// @notice Emitted when `curator` is set to `newCurator`.
    event SetCurator(address indexed newCurator);

    /// @notice Emitted when an `allocator` is set to `isAllocator`.
    event SetIsAllocator(address indexed allocator, bool isAllocator);

    /// @notice Emitted when a `pendingTimelock` is revoked.
    event RevokePendingTimelock(address indexed caller);

    /// @notice Emitted when a `pendingCap` for the vault is revoked.
    event RevokePendingCap(address indexed caller, IERC4626 indexed id);

    /// @notice Emitted when a `pendingGuardian` is revoked.
    event RevokePendingGuardian(address indexed caller);

    /// @notice Emitted when a pending vault removal is revoked.
    event RevokePendingMarketRemoval(address indexed caller, IERC4626 indexed id);

    /// @notice Emitted when the `supplyQueue` is set to `newSupplyQueue`.
    event SetSupplyQueue(address indexed caller, IERC4626[] newSupplyQueue);

    /// @notice Emitted when the `withdrawQueue` is set to `newWithdrawQueue`.
    event SetWithdrawQueue(address indexed caller, IERC4626[] newWithdrawQueue);

    /// @notice Emitted when a reallocation supplies assets to the vault.
    /// @param id The address of the vault.
    /// @param suppliedAssets The amount of assets supplied to the vault.
    /// @param suppliedShares The amount of shares minted.
    event ReallocateSupply(address indexed caller, IERC4626 indexed id, uint256 suppliedAssets, uint256 suppliedShares);

    /// @notice Emitted when a reallocation withdraws assets from the vault.
    /// @param id The address of the vault.
    /// @param withdrawnAssets The amount of assets withdrawn from the vault.
    /// @param withdrawnShares The amount of shares burned.
    event ReallocateWithdraw(
        address indexed caller, IERC4626 indexed id, uint256 withdrawnAssets, uint256 withdrawnShares
    );

    /// @notice Emitted when interest are accrued.
    /// @param newTotalAssets The assets of the vault after accruing the interest but before the interaction.
    /// @param feeShares The shares minted to the fee recipient.
    event AccrueInterest(uint256 newTotalAssets, uint256 feeShares);

    /// @notice Emitted when a new EulerEarn vault is created.
    /// @param eulerEarn The address of the EulerEarn vault.
    /// @param caller The caller of the function.
    /// @param initialOwner The initial owner of the EulerEarn vault.
    /// @param initialTimelock The initial timelock of the EulerEarn vault.
    /// @param asset The address of the underlying asset.
    /// @param name The name of the EulerEarn vault.
    /// @param symbol The symbol of the EulerEarn vault.
    /// @param salt The salt used for the EulerEarn vault's CREATE2 address.
    event CreateEulerEarn(
        address indexed eulerEarn,
        address indexed caller,
        address initialOwner,
        uint256 initialTimelock,
        address indexed asset,
        string name,
        string symbol,
        bytes32 salt
    );

    /// @notice Emitted during a public reallocation for each withdrawn-from vault.
    event PublicWithdrawal(address indexed sender, address indexed vault, IERC4626 indexed id, uint256 withdrawnAssets);

    /// @notice Emitted at the end of a public reallocation.
    event PublicReallocateTo(
        address indexed sender, address indexed vault, IERC4626 indexed supplyId, uint256 suppliedAssets
    );

    /// @notice Emitted when the admin is set for a vault.
    event SetAdmin(address indexed sender, address indexed vault, address admin);

    /// @notice Emitted when the fee is set for a vault.
    event SetAllocationFee(address indexed sender, address indexed vault, uint256 fee);

    /// @notice Emitted when the fee is transfered for a vault.
    event TransferAllocationFee(
        address indexed sender, address indexed vault, uint256 amount, address indexed feeRecipient
    );

    /// @notice Emitted when the flow caps are set for a vault.
    event SetFlowCaps(address indexed sender, address indexed vault, FlowCapsConfig[] config);
}
