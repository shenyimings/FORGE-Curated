// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 [Byzantine Finance]
// The implementation of this contract was inspired by Morpho Vault V2, developed by the Morpho Association in 2025.
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IERC4626MerklAdapter} from "./interfaces/IERC4626MerklAdapter.sol";
import {IMerklDistributor} from "../interfaces/IMerklDistributor.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";

/// @dev Generic ERC4626 adapter with Merkl rewards claiming functionality
/// @dev Designed for integration with ERC4626-compliant vaults like Stata (AAVE wrapper)
/// @dev This adapter must be used with ERC4626 vaults that are protected against inflation attacks
/// @dev Must not be used with an ERC4626 vault which can re-enter the parent vault
contract ERC4626MerklAdapter is IERC4626MerklAdapter {
    /* IMMUTABLES */

    address public immutable factory;
    address public immutable parentVault;
    address public immutable erc4626Vault;
    bytes32 public immutable adapterId;

    /* CONSTANTS */

    /// @dev Merkl distributor address on the vast majority of chains
    address public constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    /* STORAGE */

    address public skimRecipient;
    address public claimer;

    /* FUNCTIONS */

    constructor(address _parentVault, address _erc4626Vault) {
        factory = msg.sender;
        parentVault = _parentVault;
        erc4626Vault = _erc4626Vault;
        adapterId = keccak256(abi.encode("this", address(this)));
        address asset = IVaultV2(_parentVault).asset();
        require(asset == IERC4626(_erc4626Vault).asset(), AssetMismatch());
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, _erc4626Vault, type(uint256).max);
    }

    function setClaimer(address newClaimer) external {
        if (msg.sender != IVaultV2(parentVault).curator()) revert NotAuthorized();
        claimer = newClaimer;
        emit SetClaimer(newClaimer);
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
        require(token != erc4626Vault, CannotSkimERC4626Shares());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the allocation and the change in allocation.
    function allocate(bytes memory data, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        if (assets > 0) IERC4626(erc4626Vault).deposit(assets, address(this));
        uint256 oldAllocation = allocation();
        uint256 newAllocation = IERC4626(erc4626Vault).previewRedeem(IERC4626(erc4626Vault).balanceOf(address(this)));

        // Safe casts because ERC4626 vaults bound the total supply, and allocation is less than the
        // max total assets of the vault.
        return (ids(), int256(newAllocation) - int256(oldAllocation));
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the deallocation and the change in allocation.
    function deallocate(bytes memory data, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory, int256)
    {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        if (assets > 0) IERC4626(erc4626Vault).withdraw(assets, address(this), address(this));
        uint256 oldAllocation = allocation();
        uint256 newAllocation = IERC4626(erc4626Vault).previewRedeem(IERC4626(erc4626Vault).balanceOf(address(this)));

        // Safe casts because ERC4626 vaults bound the total supply, and allocation is less than the
        // max total assets of the vault.
        return (ids(), int256(newAllocation) - int256(oldAllocation));
    }

    /// @dev Claims rewards from Merkl distributor contract and swap it to parent vault's asset
    /// @dev Only the claimer can call this function
    /// @param data Encoded ClaimParams struct containing merkl params and swap params
    function claim(bytes calldata data) external {
        require(msg.sender == claimer, NotAuthorized());

        // Decode the claim data
        ClaimParams memory claimParams = abi.decode(data, (ClaimParams));
        MerklParams memory merklParams = claimParams.merklParams;
        SwapParams[] memory swapParams = claimParams.swapParams;

        // Claim data checks
        require(swapParams.length == merklParams.tokens.length, InvalidData());

        // Call the Merkl distributor
        IMerklDistributor(MERKL_DISTRIBUTOR).claim(
            merklParams.users, merklParams.tokens, merklParams.amounts, merklParams.proofs
        );

        IERC20 parentVaultAsset = IERC20(IVaultV2(parentVault).asset());
        for (uint256 i; i < swapParams.length; ++i) {
            // Check the swapper contract isn't the erc4626Vault
            require(swapParams[i].swapper != erc4626Vault, SwapperCannotBeUnderlyingVault());

            // Snapshot for sanity check
            uint256 parentVaultBalanceBefore = parentVaultAsset.balanceOf(parentVault);
            uint256 rewardTokenBalanceBefore = IERC20(merklParams.tokens[i]).balanceOf(address(this));

            // Swap the rewards
            SafeERC20Lib.safeApprove(merklParams.tokens[i], swapParams[i].swapper, merklParams.amounts[i]);
            (bool success,) = swapParams[i].swapper.call(swapParams[i].swapData);
            require(success, SwapReverted());
            uint256 swappedAmount = rewardTokenBalanceBefore - IERC20(merklParams.tokens[i]).balanceOf(address(this));

            // Check if the parent vault received them
            uint256 parentVaultBalanceAfter = parentVaultAsset.balanceOf(parentVault);
            require(parentVaultBalanceAfter > parentVaultBalanceBefore, RewardsNotReceived());

            emit ClaimRewards(merklParams.tokens[i], merklParams.amounts[i]);
            emit SwapRewards(swapParams[i].swapper, merklParams.tokens[i], swappedAmount, swapParams[i].swapData);
        }
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
        return allocation() != 0
            ? IERC4626(erc4626Vault).previewRedeem(IERC4626(erc4626Vault).balanceOf(address(this)))
            : 0;
    }
}
