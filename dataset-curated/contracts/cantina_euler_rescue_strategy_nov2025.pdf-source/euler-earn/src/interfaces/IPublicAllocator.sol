// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {MarketAllocation} from "./IEulerEarn.sol";

import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";

/// @dev Max settable flow cap, such that caps can always be stored on 128 bits.
/// @dev The actual max possible flow cap is type(uint128).max-1.
/// @dev Equals to 170141183460469231731687303715884105727;
uint128 constant MAX_SETTABLE_FLOW_CAP = type(uint128).max / 2;

struct FlowCaps {
    /// @notice The maximum allowed inflow in a vault.
    uint128 maxIn;
    /// @notice The maximum allowed outflow in a vault.
    uint128 maxOut;
}

struct FlowCapsConfig {
    /// @notice Vault for which to change flow caps.
    IERC4626 id;
    /// @notice New flow caps for this vault.
    FlowCaps caps;
}

struct Withdrawal {
    /// @notice The vault from which to withdraw.
    IERC4626 id;
    /// @notice The amount to withdraw.
    uint128 amount;
}

/// @dev This interface is used for factorizing IPublicAllocatorStaticTyping and IPublicAllocator.
/// @dev Consider using the IPublicAllocator interface instead of this one.
interface IPublicAllocatorBase {
    /// @notice The admin for a given vault.
    function admin(address vault) external view returns (address);

    /// @notice The current ETH fee for a given vault.
    function fee(address vault) external view returns (uint256);

    /// @notice The accrued ETH fee for a given vault.
    function accruedFee(address vault) external view returns (uint256);

    /// @notice Reallocates from a list of vaults to one vault.
    /// @param vault The EulerEarn vault to reallocate.
    /// @param withdrawals The vaults to withdraw from, and the amounts to withdraw.
    /// @param supplyId The vault receiving total withdrawn to.
    /// @dev Will call EulerEarn's `reallocate`.
    /// @dev Checks that the flow caps are respected.
    /// @dev Will revert when `withdrawals` contains a duplicate or is not sorted.
    /// @dev Will revert if `withdrawals` contains the supply vault.
    /// @dev Will revert if a withdrawal amount is larger than available liquidity.
    function reallocateTo(address vault, Withdrawal[] calldata withdrawals, IERC4626 supplyId) external payable;

    /// @notice Sets the admin for a given vault.
    function setAdmin(address vault, address newAdmin) external;

    /// @notice Sets the fee for a given vault.
    function setFee(address vault, uint256 newFee) external;

    /// @notice Transfers the current balance to `feeRecipient` for a given vault.
    function transferFee(address vault, address payable feeRecipient) external;

    /// @notice Sets the maximum inflow and outflow through public allocation for some vaults for a given Earn vault.
    /// @dev Max allowed inflow/outflow is MAX_SETTABLE_FLOW_CAP.
    /// @dev Doesn't revert if it doesn't change the storage at all.
    function setFlowCaps(address vault, FlowCapsConfig[] calldata config) external;
}

/// @dev This interface is inherited by PublicAllocator so that function signatures are checked by the compiler.
/// @dev Consider using the IPublicAllocator interface instead of this one.
interface IPublicAllocatorStaticTyping is IPublicAllocatorBase {
    /// @notice Returns (maximum inflow, maximum outflow) through public allocation of a given vault for a given Earn vault.
    function flowCaps(address vault, IERC4626) external view returns (uint128, uint128);
}

/// @title IPublicAllocator
/// @author Forked with gratitude from Morpho Labs. Inspired by Silo Labs.
/// @custom:contact security@morpho.org
/// @custom:contact security@euler.xyz
/// @dev Use this interface for PublicAllocator to have access to all the functions with the appropriate function
/// signatures.
interface IPublicAllocator is IPublicAllocatorBase {
    /// @notice Returns the maximum inflow and maximum outflow through public allocation of a given vault for a given
    /// Earn vault.
    function flowCaps(address vault, IERC4626) external view returns (FlowCaps memory);
}
