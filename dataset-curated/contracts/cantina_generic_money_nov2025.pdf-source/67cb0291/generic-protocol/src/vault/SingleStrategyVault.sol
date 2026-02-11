// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ControlledERC7575Vault, SafeERC20, IERC20, IController } from "./ControlledERC7575Vault.sol";

/**
 * @title SingleStrategyVault
 * @notice A vault implementation that manages assets by depositing into a single ERC4626 vault
 * @dev Extends ControlledERC7575Vault to provide automated allocation/deallocation functionality
 * The vault automatically allocates assets to the strategy when deposits exceed the threshold
 * and deallocates assets when withdrawals require more than the available unallocated balance
 */
contract SingleStrategyVault is ControlledERC7575Vault {
    /**
     * @notice The ERC4626 vault used for yield generation
     */
    IERC4626 private immutable _strategy;
    /**
     * @notice The address authorized to manage allocations and vault parameters
     */
    address private immutable _manager;

    /**
     * @notice The minimum amount of assets that triggers automatic allocation to the strategy
     */
    uint256 public autoAllocationThreshold;

    /**
     * @notice Emitted when assets are allocated to the strategy
     */
    event Allocate(address strategy, uint256 assets);
    /**
     * @notice Emitted when assets are deallocated from the strategy
     */
    event Deallocate(address strategy, uint256 assets);
    /**
     * @notice Emitted when the auto-allocation threshold is updated
     */
    event SetAutoAllocationThreshold(uint256 threshold);

    /**
     * @notice Thrown when the strategy address is zero
     */
    error ZeroStrategy();
    /**
     * @notice Thrown when the strategy's asset does not match the vault's asset
     */
    error MismatchedAsset();
    /**
     * @notice Thrown when caller is not the authorized manager
     */
    error CallerNotManager();

    /**
     * @notice Constructs a new SingleStrategyVault
     * @dev Approves the strategy to spend unlimited vault assets for efficient deposits.
     * Manager can be zero address, in which case manual allocation/deallocation and threshold setting are disabled.
     * All deposits are automatically deployed to the strategy as default autoAllocationThreshold is zero.
     *
     * Requirements:
     * - `strategy_` must not be the zero address
     * - `asset_` and `controller_` must satisfy ControlledERC7575Vault requirements
     *
     * @param asset_ The underlying ERC20 asset that the vault accepts
     * @param controller_ The controller contract that governs this vault
     * @param strategy_ The ERC4626 vault for yield generation (cannot be zero address)
     * @param manager_ The address authorized to manage vault operations.
     */
    constructor(
        IERC20 asset_,
        IController controller_,
        IERC4626 strategy_,
        address manager_
    )
        ControlledERC7575Vault(asset_, controller_)
    {
        require(address(strategy_) != address(0), ZeroStrategy());
        require(strategy_.asset() == address(asset_), MismatchedAsset());

        _strategy = strategy_;
        _manager = manager_;

        SafeERC20.forceApprove(_asset, address(_strategy), type(uint256).max);
    }

    /**
     * @notice Returns the address of the underlying ERC4626 vault
     * @return The address of the strategy contract
     */
    function strategy() external view returns (address) {
        return address(_strategy);
    }

    /**
     * @notice Returns the address of the vault manager
     * @return The address authorized to manage vault operations
     */
    function manager() external view returns (address) {
        return _manager;
    }

    /**
     * @notice Manually allocates vault assets to the underlying strategy
     * @dev Only callable by the manager. Deposits assets into the strategy and receives strategy shares
     * @param assets The amount of assets to allocate to the strategy
     * @return shares The number of strategy shares received in return
     */
    function allocate(uint256 assets) external returns (uint256 shares) {
        require(msg.sender == _manager, CallerNotManager());
        return _allocate(assets);
    }

    /**
     * @notice Manually deallocates assets from the underlying strategy
     * @dev Only callable by the manager. Withdraws assets from the strategy back to the vault
     * @param assets The amount of assets to withdraw from the strategy
     * @return shares The number of strategy shares burned in the process
     */
    function deallocate(uint256 assets) external returns (uint256 shares) {
        require(msg.sender == _manager, CallerNotManager());
        return _deallocate(assets);
    }

    /**
     * @notice Sets the threshold for automatic allocation of deposited assets
     * @dev Only callable by the manager. When deposits exceed this threshold,
     * assets are automatically allocated to the strategy
     * @param threshold The minimum deposit amount that triggers automatic allocation
     */
    function setAutoAllocationThreshold(uint256 threshold) external {
        require(msg.sender == _manager, CallerNotManager());
        autoAllocationThreshold = threshold;
        emit SetAutoAllocationThreshold(threshold);
    }

    /**
     * @notice Internal function to allocate assets to the strategy
     * @dev Deposits assets into the strategy and emits an Allocate event
     * @param assets The amount of assets to deposit into the strategy
     * @return shares The number of strategy shares received
     */
    function _allocate(uint256 assets) private returns (uint256 shares) {
        shares = _strategy.deposit(assets, address(this));
        emit Allocate(address(_strategy), assets);
    }

    /**
     * @notice Internal function to deallocate assets from the strategy
     * @dev Withdraws assets from the strategy to this vault and emits a Deallocate event
     * @param assets The amount of assets to withdraw from the strategy
     * @return shares The number of strategy shares burned
     */
    function _deallocate(uint256 assets) private returns (uint256 shares) {
        shares = _strategy.withdraw(assets, address(this), address(this));
        emit Deallocate(address(_strategy), assets);
    }

    /**
     * @notice Calculates assets owned by the vault but not held directly in the vault
     * @dev Override from ControlledERC7575Vault. Returns only assets allocated to strategies,
     * not including assets held directly in the vault. Converts strategy shares to underlying asset value.
     * @return The amount of underlying assets owned through strategy allocation (excluding vault balance)
     */
    function _additionalOwnedAssets() internal view override returns (uint256) {
        return _strategy.convertToAssets(_strategy.balanceOf(address(this)));
    }

    /**
     * @notice Calculates the maximum assets immediately available for withdrawal
     * @dev Override from ControlledERC7575Vault to include strategy liquidity
     * @return The amount of assets that can be withdrawn without waiting
     */
    function _additionalAvailableAssets() internal view override returns (uint256) {
        return _strategy.maxWithdraw(address(this));
    }

    /**
     * @notice Hook executed before processing withdrawals to ensure sufficient liquidity
     * @dev Override from ControlledERC7575Vault. Automatically deallocates from strategy if needed
     * @param assets The amount of assets being withdrawn
     */
    function _beforeWithdraw(uint256 assets) internal override {
        uint256 unallocated = _asset.balanceOf(address(this));
        if (assets > unallocated) {
            _deallocate(assets - unallocated);
        }
    }

    /**
     * @notice Hook executed after processing deposits to potentially auto-allocate assets
     * @dev Override from ControlledERC7575Vault. Automatically allocates to strategy if deposit exceeds threshold
     * @param assets The amount of assets that were deposited
     */
    function _afterDeposit(uint256 assets) internal override {
        if (assets >= autoAllocationThreshold) {
            _allocate(assets);
        }
    }
}
