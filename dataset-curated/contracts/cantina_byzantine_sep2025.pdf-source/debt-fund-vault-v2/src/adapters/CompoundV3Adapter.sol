// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 [Byzantine Finance]
// The implementation of this contract was inspired by Morpho Vault V2, developed by the Morpho Association in 2025.
pragma solidity 0.8.28;

import {CometInterface} from "../interfaces/CometInterface.sol";
import {CometRewardsInterface} from "../interfaces/CometRewardsInterface.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ICompoundV3Adapter} from "./interfaces/ICompoundV3Adapter.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";

contract CompoundV3Adapter is ICompoundV3Adapter {
    /* IMMUTABLES */

    address public immutable factory;
    address public immutable parentVault;
    address public immutable asset;
    address public immutable comet;
    address public immutable cometRewards;
    bytes32 public immutable adapterId;

    /* STORAGE */

    address public skimRecipient;
    address public claimer;

    /* FUNCTIONS */

    constructor(address _parentVault, address _comet, address _cometRewards) {
        factory = msg.sender;
        parentVault = _parentVault;
        comet = _comet;
        cometRewards = _cometRewards;
        adapterId = keccak256(abi.encode("this", address(this)));
        asset = IVaultV2(_parentVault).asset();
        SafeERC20Lib.safeApprove(asset, _comet, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
    }

    function setClaimer(address newClaimer) external {
        if (msg.sender != IVaultV2(parentVault).curator()) revert NotAuthorized();
        claimer = newClaimer;
        emit SetClaimer(newClaimer);
    }

    function setSkimRecipient(address newSkimRecipient) external {
        if (msg.sender != IVaultV2(parentVault).owner()) revert NotAuthorized();
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    /// @dev Skims the adapter's balance of `token` and sends it to `skimRecipient`.
    /// @dev This is useful to handle rewards that the adapter has earned.
    function skim(address token) external {
        if (msg.sender != skimRecipient) revert NotAuthorized();
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the allocation and the change in allocation.
    function allocate(bytes memory data, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        if (data.length != 0) revert InvalidData();
        if (msg.sender != parentVault) revert NotAuthorized();

        if (assets > 0) CometInterface(comet).supply(asset, assets);
        uint256 oldAllocation = allocation();
        uint256 newAllocation = CometInterface(comet).balanceOf(address(this));

        return (ids(), int256(newAllocation) - int256(oldAllocation));
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the deallocation and the change in allocation.
    function deallocate(bytes memory data, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory, int256)
    {
        if (data.length != 0) revert InvalidData();
        if (msg.sender != parentVault) revert NotAuthorized();

        if (assets > 0) CometInterface(comet).withdraw(asset, assets);
        uint256 oldAllocation = allocation();
        uint256 newAllocation = CometInterface(comet).balanceOf(address(this));

        return (ids(), int256(newAllocation) - int256(oldAllocation));
    }

    /// @dev Claims COMP rewards accumulated by the adapter and swap it to parent vault's asset
    /// @dev Only the claimer can call this function
    /// @param data Encoded SwapParams struct containing swapper and swap data
    function claim(bytes calldata data) external {
        if (msg.sender != claimer) revert NotAuthorized();

        // Decode the data
        (address swapper, bytes memory swapData) = abi.decode(data, (address, bytes));

        // Check the swapper contract isn't the comet contract
        if (swapper == comet) revert SwapperCannotBeComet();

        // Get assets
        IERC20 rewardToken = IERC20(CometRewardsInterface(cometRewards).rewardConfig(comet).token);
        IERC20 parentVaultAsset = IERC20(IVaultV2(parentVault).asset());

        // Claim the rewards
        uint256 balanceBefore = rewardToken.balanceOf(address(this));
        CometRewardsInterface(cometRewards).claim(comet, address(this), true);
        uint256 balanceAfter = rewardToken.balanceOf(address(this));
        uint256 claimedAmount = balanceAfter - balanceBefore;

        // Snapshot for sanity check
        balanceBefore = parentVaultAsset.balanceOf(parentVault);

        // Swap the rewards
        SafeERC20Lib.safeApprove(address(rewardToken), swapper, claimedAmount);
        (bool success,) = swapper.call(swapData);
        require(success, SwapReverted());
        uint256 swappedAmount = balanceAfter - rewardToken.balanceOf(address(this));

        // Check if the parent vault received them
        balanceAfter = parentVaultAsset.balanceOf(parentVault);
        require(balanceAfter > balanceBefore, RewardsNotReceived());

        emit Claim(address(rewardToken), claimedAmount);
        emit SwapRewards(swapper, address(rewardToken), swappedAmount, swapData);
    }

    /// @dev Returns adapter's ids.
    function ids() public view returns (bytes32[] memory) {
        bytes32[] memory ids_ = new bytes32[](1);
        ids_[0] = adapterId;
        return ids_;
    }

    function allocation() public view returns (uint256) {
        return IVaultV2(parentVault).allocation(adapterId);
    }

    function realAssets() external view returns (uint256) {
        return allocation() != 0 ? CometInterface(comet).balanceOf(address(this)) : 0;
    }
}
