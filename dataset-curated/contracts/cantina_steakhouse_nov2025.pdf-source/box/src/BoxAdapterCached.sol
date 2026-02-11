// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association, Steakhouse Financial
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IVaultV2} from "./../lib/vault-v2/src/interfaces/IVaultV2.sol";
import {MathLib} from "./../lib/vault-v2/src/libraries/MathLib.sol";
import {SafeERC20Lib} from "./../lib/vault-v2/src/libraries/SafeERC20Lib.sol";
import {IBox} from "./interfaces/IBox.sol";
import {IBoxAdapter} from "./interfaces/IBoxAdapter.sol";

contract BoxAdapterCached is IBoxAdapter {
    using MathLib for uint256;
    using SafeCast for uint256;

    /* EVENTS */
    event UpdateTotalAsset(uint256 oldTotalAssets, uint256 totalAssets);

    /* IMMUTABLES */

    address public immutable factory;
    address public immutable parentVault;
    IBox public immutable box;
    bytes32 public immutable adapterId;

    /* STORAGE */

    address public skimRecipient;
    uint256 public totalAssets;
    uint256 public totalAssetsTimestamp;

    /* FUNCTIONS */

    constructor(address _parentVault, IBox _box) {
        factory = msg.sender;
        parentVault = _parentVault;
        box = _box;
        adapterId = keccak256(abi.encode("this", address(this)));
        address asset = IVaultV2(_parentVault).asset();
        require(asset == _box.asset(), AssetMismatch());
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, address(_box), type(uint256).max);
    }

    function setSkimRecipient(address newSkimRecipient) external {
        require(msg.sender == IVaultV2(parentVault).owner(), NotAuthorized());
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    /// @dev Skims the adapter's balance of `token` and sends it to `skimRecipient`.
    /// @dev This is useful to handle rewards that the adapter has earned.
    function skim(address token) external {
        require(msg.sender == skimRecipient, NotAuthorized());
        require(token != address(box), CannotSkimBoxShares());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the allocation and the change in allocation.
    function allocate(bytes memory data, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        if (assets > 0) IERC4626(box).deposit(assets, address(this));
        // Safe casts because bounded by Vault V2 which requires totalAssets to stay below ~10^35
        _updateTotalAssets();
        int256 newAllocation = totalAssets.toInt256();
        int256 oldAllocation = allocation().toInt256();

        return (ids(), newAllocation - oldAllocation);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the deallocation and the change in allocation.
    function deallocate(bytes memory data, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        if (assets > 0) IERC4626(box).withdraw(assets, address(this), address(this));
        // Safe casts because bounded by Vault V2 which requires totalAssets to stay below ~10^35
        _updateTotalAssets();
        int256 newAllocation = totalAssets.toInt256();
        int256 oldAllocation = allocation().toInt256();

        return (ids(), newAllocation - oldAllocation);
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
        return allocation() != 0 ? totalAssets : 0;
    }

    /// @dev Updates the cached total assets of the adapter.
    /// @dev Allowed: Vault allocator, sentinel or anyone after 24 hours of inactivity
    function updateTotalAssets() external {
        require(
            IVaultV2(parentVault).isAllocator(msg.sender) ||
                IVaultV2(parentVault).isSentinel(msg.sender) ||
                totalAssetsTimestamp + 1 days < block.timestamp,
            NotAuthorized()
        );

        uint256 oldTotalAssets = totalAssets;
        _updateTotalAssets();
        emit UpdateTotalAsset(oldTotalAssets, totalAssets);
    }

    function _updateTotalAssets() internal {
        totalAssets = box.previewRedeem(box.balanceOf(address(this)));
        totalAssetsTimestamp = block.timestamp;
    }

    function adapterData() external view returns (bytes memory) {
        return abi.encode("this", address(this));
    }
}
