// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IVault } from "../../interfaces/IVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title Vault for storing the backing for cTokens
/// @author kexley, @capLabs
/// @notice Tokens are supplied by cToken minters and borrowed by covered agents
/// @dev Supplies, borrows and utilization rates are tracked. Interest rates should be computed and
/// charged on the external contracts, only the principle amount is counted on this contract.
library VaultLogic {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Timestamp is past the deadline
    error PastDeadline();

    /// @dev Amount out is less than required
    error Slippage(address asset, uint256 amountOut, uint256 minAmountOut);

    /// @dev Amount out is 0
    error InvalidAmount();

    /// @dev Paused assets cannot be supplied or borrowed
    error AssetPaused(address asset);

    /// @dev Only whitelisted assets can be supplied or borrowed
    error AssetNotSupported(address asset);

    /// @dev Asset is already listed
    error AssetAlreadySupported(address asset);

    /// @dev Asset has supplies
    error AssetHasSupplies(address asset);

    /// @dev Only non-supported assets can be rescued
    error AssetNotRescuable(address asset);

    /// @dev Invalid min amounts out as they dont match the number of assets
    error InvalidMinAmountsOut();

    /// @dev Insufficient reserves
    error InsufficientReserves(address asset, uint256 balanceBefore, uint256 amount);

    /// @dev Cap token minted
    event Mint(
        address indexed minter,
        address receiver,
        address indexed asset,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee
    );

    /// @dev Cap token burned
    event Burn(
        address indexed burner,
        address receiver,
        address indexed asset,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee
    );

    /// @dev Cap token redeemed
    event Redeem(address indexed redeemer, address receiver, uint256 amountIn, uint256[] amountsOut, uint256[] fees);

    /// @dev Borrow made
    event Borrow(address indexed borrower, address indexed asset, uint256 amount);

    /// @dev Repayment made
    event Repay(address indexed repayer, address indexed asset, uint256 amount);

    /// @dev Add asset
    event AddAsset(address asset);

    /// @dev Remove asset
    event RemoveAsset(address asset);

    /// @dev Asset paused
    event PauseAsset(address asset);

    /// @dev Asset unpaused
    event UnpauseAsset(address asset);

    /// @dev Rescue unsupported ERC20 tokens
    event RescueERC20(address asset, address receiver);

    /// @dev Modifier to only allow supplies and borrows when not paused
    /// @param $ Vault storage pointer
    /// @param _asset Asset address
    modifier whenNotPaused(IVault.VaultStorage storage $, address _asset) {
        _whenNotPaused($, _asset);
        _;
    }

    /// @dev Modifier to update the utilization index
    /// @param $ Vault storage pointer
    /// @param _asset Asset address
    modifier updateIndex(IVault.VaultStorage storage $, address _asset) {
        _updateIndex($, _asset);
        _;
    }

    /// @notice Mint the cap token using an asset
    /// @dev This contract must have approval to move asset from msg.sender
    /// @param $ Vault storage pointer
    /// @param params Mint parameters
    function mint(IVault.VaultStorage storage $, IVault.MintBurnParams memory params)
        external
        whenNotPaused($, params.asset)
        updateIndex($, params.asset)
    {
        if (params.deadline < block.timestamp) revert PastDeadline();
        if (params.amountOut < params.minAmountOut) {
            revert Slippage(address(this), params.amountOut, params.minAmountOut);
        }
        if (params.amountOut == 0) revert InvalidAmount();

        $.totalSupplies[params.asset] += params.amountIn;

        IERC20(params.asset).safeTransferFrom(msg.sender, address(this), params.amountIn);

        emit Mint(msg.sender, params.receiver, params.asset, params.amountIn, params.amountOut, params.fee);
    }

    /// @notice Burn the cap token for an asset
    /// @dev Can only withdraw up to the amount remaining on this contract
    /// @param $ Vault storage pointer
    /// @param params Burn parameters
    function burn(IVault.VaultStorage storage $, IVault.MintBurnParams memory params)
        external
        updateIndex($, params.asset)
    {
        if (params.deadline < block.timestamp) revert PastDeadline();
        if (params.amountOut < params.minAmountOut) {
            revert Slippage(params.asset, params.amountOut, params.minAmountOut);
        }
        if (params.amountOut == 0) revert InvalidAmount();

        _verifyBalance($, params.asset, params.amountOut);

        $.totalSupplies[params.asset] -= params.amountOut + params.fee;

        IERC20(params.asset).safeTransfer(params.receiver, params.amountOut);
        IERC20(params.asset).safeTransfer($.insuranceFund, params.fee);

        emit Burn(msg.sender, params.receiver, params.asset, params.amountIn, params.amountOut, params.fee);
    }

    /// @notice Redeem the Cap token for a bundle of assets
    /// @dev Can only withdraw up to the amount remaining on this contract
    /// @param $ Vault storage pointer
    /// @param params Redeem parameters
    function redeem(IVault.VaultStorage storage $, IVault.RedeemParams memory params) external {
        if (params.amountsOut.length != params.minAmountsOut.length) revert InvalidMinAmountsOut();
        if (params.deadline < block.timestamp) revert PastDeadline();

        uint256 length = $.assets.length();
        for (uint256 i; i < length; ++i) {
            address asset = $.assets.at(i);
            if (params.amountsOut[i] < params.minAmountsOut[i]) {
                revert Slippage(asset, params.amountsOut[i], params.minAmountsOut[i]);
            }
            if (params.amountsOut[i] == 0) revert InvalidAmount();
            _verifyBalance($, asset, params.amountsOut[i]);
            _updateIndex($, asset);
            $.totalSupplies[asset] -= params.amountsOut[i] + params.fees[i];
            IERC20(asset).safeTransfer(params.receiver, params.amountsOut[i]);
            IERC20(asset).safeTransfer($.insuranceFund, params.fees[i]);
        }

        emit Redeem(msg.sender, params.receiver, params.amountIn, params.amountsOut, params.fees);
    }

    /// @notice Borrow an asset
    /// @dev Whitelisted agents can borrow any amount, LTV is handled by Agent contracts
    /// @param $ Vault storage pointer
    /// @param params Borrow parameters
    function borrow(IVault.VaultStorage storage $, IVault.BorrowParams memory params)
        external
        whenNotPaused($, params.asset)
        updateIndex($, params.asset)
    {
        _verifyBalance($, params.asset, params.amount);

        $.totalBorrows[params.asset] += params.amount;
        IERC20(params.asset).safeTransfer(params.receiver, params.amount);

        emit Borrow(msg.sender, params.asset, params.amount);
    }

    /// @notice Repay an asset
    /// @param $ Vault storage pointer
    /// @param params Repay parameters
    function repay(IVault.VaultStorage storage $, IVault.RepayParams memory params)
        external
        updateIndex($, params.asset)
    {
        $.totalBorrows[params.asset] -= params.amount;
        IERC20(params.asset).safeTransferFrom(msg.sender, address(this), params.amount);

        emit Repay(msg.sender, params.asset, params.amount);
    }

    /// @notice Add an asset to the vault list
    /// @param $ Vault storage pointer
    /// @param _asset Asset address
    function addAsset(IVault.VaultStorage storage $, address _asset) external {
        if (!$.assets.add(_asset)) revert AssetNotSupported(_asset);
        emit AddAsset(_asset);
    }

    /// @notice Remove an asset from the vault list
    /// @param $ Vault storage pointer
    /// @param _asset Asset address
    function removeAsset(IVault.VaultStorage storage $, address _asset) external {
        if ($.totalSupplies[_asset] > 0) revert AssetHasSupplies(_asset);
        if (!$.assets.remove(_asset)) revert AssetNotSupported(_asset);
        emit RemoveAsset(_asset);
    }

    /// @notice Pause an asset
    /// @param $ Vault storage pointer
    /// @param _asset Asset address
    function pause(IVault.VaultStorage storage $, address _asset) external {
        $.paused[_asset] = true;
        emit PauseAsset(_asset);
    }

    /// @notice Unpause an asset
    /// @param $ Vault storage pointer
    /// @param _asset Asset address
    function unpause(IVault.VaultStorage storage $, address _asset) external {
        $.paused[_asset] = false;
        emit UnpauseAsset(_asset);
    }

    /// @notice Rescue an unsupported asset
    /// @param $ Vault storage pointer
    /// @param _asset Asset to rescue
    /// @param _receiver Receiver of the rescue
    function rescueERC20(IVault.VaultStorage storage $, address _asset, address _receiver) external {
        if (_listed($, _asset)) revert AssetNotRescuable(_asset);
        IERC20(_asset).safeTransfer(_receiver, IERC20(_asset).balanceOf(address(this)));
        emit RescueERC20(_asset, _receiver);
    }

    /// @notice Calculate the available balance of an asset
    /// @param $ Vault storage pointer
    /// @param _asset Asset address
    /// @return balance Available balance
    function availableBalance(IVault.VaultStorage storage $, address _asset) public view returns (uint256 balance) {
        balance = $.totalSupplies[_asset] - $.totalBorrows[_asset];
    }

    /// @notice Calculate the utilization ratio of an asset
    /// @dev Returns the ratio of borrowed assets to total supply, scaled to ray (1e27)
    /// @param $ Vault storage pointer
    /// @param _asset Asset address
    /// @return ratio Utilization ratio in ray (1e27)
    function utilization(IVault.VaultStorage storage $, address _asset) public view returns (uint256 ratio) {
        ratio = $.totalSupplies[_asset] != 0 ? $.totalBorrows[_asset] * 1e27 / $.totalSupplies[_asset] : 0;
    }

    /// @notice Up to date cumulative utilization index of an asset
    /// @dev Utilization and index are both scaled in ray (1e27)
    /// @param $ Vault storage pointer
    /// @param _asset Utilized asset
    /// @return index Utilization ratio index in ray (1e27)
    function currentUtilizationIndex(IVault.VaultStorage storage $, address _asset)
        external
        view
        returns (uint256 index)
    {
        index = $.utilizationIndex[_asset] + (utilization($, _asset) * (block.timestamp - $.lastUpdate[_asset]));
    }

    /// @notice Validate that an asset is listed
    /// @param $ Vault storage pointer
    /// @param _asset Asset to check
    /// @return isListed Asset is listed or not
    function _listed(IVault.VaultStorage storage $, address _asset) internal view returns (bool isListed) {
        isListed = $.assets.contains(_asset);
    }

    /// @notice Verify that an asset has enough balance
    /// @param $ Vault storage pointer
    /// @param _asset Asset address
    /// @param _amount Amount to verify
    function _verifyBalance(IVault.VaultStorage storage $, address _asset, uint256 _amount) internal view {
        uint256 balance = availableBalance($, _asset);
        if (balance < _amount) {
            revert InsufficientReserves(_asset, balance, _amount);
        }
    }

    /// @dev Only allow supplies and borrows when not paused
    /// @param $ Vault storage pointer
    /// @param _asset Asset address
    function _whenNotPaused(IVault.VaultStorage storage $, address _asset) private view {
        if ($.paused[_asset]) revert AssetPaused(_asset);
    }

    /// @dev Update the cumulative utilization index of an asset
    /// @param $ Vault storage pointer
    /// @param _asset Utilized asset
    function _updateIndex(IVault.VaultStorage storage $, address _asset) internal {
        if (!_listed($, _asset)) revert AssetNotSupported(_asset);
        $.utilizationIndex[_asset] += utilization($, _asset) * (block.timestamp - $.lastUpdate[_asset]);
        $.lastUpdate[_asset] = block.timestamp;
    }
}
