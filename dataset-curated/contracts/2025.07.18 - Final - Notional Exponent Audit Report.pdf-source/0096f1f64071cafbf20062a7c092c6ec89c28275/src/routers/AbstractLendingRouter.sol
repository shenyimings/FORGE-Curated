// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {ILendingRouter, VaultPosition} from "../interfaces/ILendingRouter.sol";
import {
    NotAuthorized,
    CannotExitPositionWithinCooldownPeriod,
    CannotInitiateWithdraw,
    CannotForceWithdraw,
    InvalidLendingRouter,
    NoExistingPosition,
    LiquidatorHasPosition,
    CannotEnterPosition,
    CannotLiquidateZeroShares,
    InsufficientSharesHeld
} from "../interfaces/Errors.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldStrategy} from "../interfaces/IYieldStrategy.sol";
import {RewardManagerMixin} from "../rewards/RewardManagerMixin.sol";
import {ILendingRouter} from "../interfaces/ILendingRouter.sol";
import {ADDRESS_REGISTRY, COOLDOWN_PERIOD} from "../utils/Constants.sol";

abstract contract AbstractLendingRouter is ILendingRouter {
    using SafeERC20 for ERC20;
    using TokenUtils for ERC20;

    mapping(address user => mapping(address operator => bool approved)) private s_isApproved;

    /*** Authorization Methods ***/
    modifier isAuthorized(address onBehalf, address vault) {
        // In this case msg.sender is the operator
        if (msg.sender != onBehalf && !isApproved(onBehalf, msg.sender)) {
            revert NotAuthorized(msg.sender, onBehalf);
        }

        _;

        // Clear the current account after the transaction is finished
        IYieldStrategy(vault).clearCurrentAccount();
    }

    /// @inheritdoc ILendingRouter
    function setApproval(address operator, bool approved) external override {
        if (operator == msg.sender) revert NotAuthorized(msg.sender, operator);
        s_isApproved[msg.sender][operator] = approved;
    }

    /// @inheritdoc ILendingRouter
    function isApproved(address user, address operator) public view override returns (bool) {
        return s_isApproved[user][operator];
    }

    /// @inheritdoc ILendingRouter
    function enterPosition(
        address onBehalf,
        address vault,
        uint256 depositAssetAmount,
        uint256 borrowAmount,
        bytes calldata depositData
    ) public override isAuthorized(onBehalf, vault) {
        _enterPosition(onBehalf, vault, depositAssetAmount, borrowAmount, depositData, address(0));
    }

    /// @inheritdoc ILendingRouter
    function migratePosition(
        address onBehalf,
        address vault,
        address migrateFrom
    ) public override isAuthorized(onBehalf, vault) {
        if (!ADDRESS_REGISTRY.isLendingRouter(migrateFrom)) revert InvalidLendingRouter();
        // Borrow amount is set to the amount of debt owed to the previous lending router
        (uint256 borrowAmount, /* */, /* */) = ILendingRouter(migrateFrom).healthFactor(onBehalf, vault);

        _enterPosition(onBehalf, vault, 0, borrowAmount, bytes(""), migrateFrom);
    }

    function _enterPosition(
        address onBehalf,
        address vault,
        uint256 depositAssetAmount,
        uint256 borrowAmount,
        bytes memory depositData,
        address migrateFrom
    ) internal {
        address asset = IYieldStrategy(vault).asset();
        // Cannot enter a position if the account already has a native share balance
        if (IYieldStrategy(vault).balanceOf(onBehalf) > 0) revert CannotEnterPosition();

        if (depositAssetAmount > 0) {
            // Take any margin deposit from the sender initially
            ERC20(asset).safeTransferFrom(msg.sender, address(this), depositAssetAmount);
        }

        if (borrowAmount > 0) {
            _flashBorrowAndEnter(
                onBehalf, vault, asset, depositAssetAmount, borrowAmount, depositData, migrateFrom
            );
        } else {
            _enterOrMigrate(onBehalf, vault, asset, depositAssetAmount, depositData, migrateFrom);
        }

        ADDRESS_REGISTRY.setPosition(onBehalf, vault);
    }

    /// @inheritdoc ILendingRouter
    function exitPosition(
        address onBehalf,
        address vault,
        address receiver,
        uint256 sharesToRedeem,
        uint256 assetToRepay,
        bytes calldata redeemData
    ) external override isAuthorized(onBehalf, vault) {
        _checkExit(onBehalf, vault);

        address asset = IYieldStrategy(vault).asset();
        if (0 < assetToRepay) {
            _exitWithRepay(onBehalf, vault, asset, receiver, sharesToRedeem, assetToRepay, redeemData);
        } else {
            address migrateTo = _isMigrate(receiver) ? receiver : address(0);
            uint256 assetsWithdrawn = _redeemShares(onBehalf, vault, asset, migrateTo, sharesToRedeem, redeemData);
            if (0 < assetsWithdrawn) ERC20(asset).safeTransfer(receiver, assetsWithdrawn);
        }

        if (balanceOfCollateral(onBehalf, vault) == 0) {
            ADDRESS_REGISTRY.clearPosition(onBehalf, vault);
        }
    }

    /// @inheritdoc ILendingRouter
    function liquidate(
        address liquidateAccount,
        address vault,
        uint256 sharesToLiquidate,
        uint256 debtToRepay
    ) external override returns (uint256 sharesToLiquidator) {
        if (sharesToLiquidate == 0) revert CannotLiquidateZeroShares();

        address liquidator = msg.sender;
        VaultPosition memory position = ADDRESS_REGISTRY.getVaultPosition(liquidator, vault);
        // If the liquidator has a position then they cannot liquidate or they will have
        // a native balance and a balance on the lending market.
        if (position.lendingRouter != address(0)) revert LiquidatorHasPosition();

        uint256 balanceBefore = balanceOfCollateral(liquidateAccount, vault);
        if (balanceBefore == 0) revert InsufficientSharesHeld();

        // Runs any checks on the vault to ensure that the liquidation can proceed, whitelists the lending platform
        // to transfer collateral to the lending router. The current account is set in this method.
        IYieldStrategy(vault).preLiquidation(liquidator, liquidateAccount, sharesToLiquidate, balanceBefore);

        // After this call, address(this) will have the liquidated shares
        sharesToLiquidator = _liquidate(liquidator, vault, liquidateAccount, sharesToLiquidate, debtToRepay);

        // Transfers the shares to the liquidator from the lending router and does any post liquidation logic. The
        // current account is cleared in this method.
        IYieldStrategy(vault).postLiquidation(liquidator, liquidateAccount, sharesToLiquidator);

        // The liquidator will receive shares in their native balance and then they can call redeem
        // on the yield strategy to get the assets.

        // Clear the position if the liquidator has taken all the shares, in the case of an insolvency,
        // the account's position will just be left on the lending market with zero collateral. The account
        // would be able to create a new position on this lending router or a new position on a different
        // lending router. If they do create a new position on an insolvent account their old debt may
        // be applied to their new position.
        if (sharesToLiquidator == balanceBefore) ADDRESS_REGISTRY.clearPosition(liquidateAccount, vault);
    }

    /// @inheritdoc ILendingRouter
    function initiateWithdraw(
        address onBehalf,
        address vault,
        bytes calldata data
    ) external override isAuthorized(onBehalf, vault) returns (uint256 requestId) {
        requestId = _initiateWithdraw(vault, onBehalf, data);
    }

    /// @inheritdoc ILendingRouter
    function forceWithdraw(address account, address vault, bytes calldata data) external returns (uint256 requestId) {
        // Can only force a withdraw if health factor is negative, this allows a liquidator to
        // force a withdraw and liquidate a position at a later time.
        (uint256 borrowed, /* */, uint256 maxBorrow) = healthFactor(account, vault);
        if (borrowed <= maxBorrow) revert CannotForceWithdraw(account);

        requestId = _initiateWithdraw(vault, account, data);

        // Clear the current account since this method is not called using isAuthorized
        IYieldStrategy(vault).clearCurrentAccount();
    }

    /// @inheritdoc ILendingRouter
    function claimRewards(address vault) external returns (uint256[] memory rewards) {
        return RewardManagerMixin(vault).claimAccountRewards(msg.sender, balanceOfCollateral(msg.sender, vault));
    }

    /// @inheritdoc ILendingRouter
    function healthFactor(address borrower, address vault) public override virtual returns (uint256 borrowed, uint256 collateralValue, uint256 maxBorrow);

    /// @inheritdoc ILendingRouter
    function balanceOfCollateral(address account, address vault) public override view virtual returns (uint256 collateralBalance);


    /*** Internal Methods ***/

    function _checkExit(address onBehalf, address vault) internal view  {
        VaultPosition memory position = ADDRESS_REGISTRY.getVaultPosition(onBehalf, vault);
        if (position.lendingRouter != address(this)) revert NoExistingPosition();
        if (block.timestamp - position.lastEntryTime < COOLDOWN_PERIOD) {
            revert CannotExitPositionWithinCooldownPeriod();
        }
    }

    /// @dev Checks if an exitPosition call is a migration, this would be called via a lending router
    function _isMigrate(address receiver) internal view returns (bool) {
        return receiver == msg.sender && ADDRESS_REGISTRY.isLendingRouter(msg.sender);
    }

    /// @dev Enters a position or migrates shares from a previous lending router
    function _enterOrMigrate(
        address onBehalf,
        address vault,
        address asset,
        uint256 assetAmount,
        bytes memory depositData,
        address migrateFrom
    ) internal returns (uint256 sharesReceived) {
        if (migrateFrom != address(0)) {
            // Allow the previous lending router to repay the debt from assets held here.
            ERC20(asset).checkApprove(migrateFrom, assetAmount);
            sharesReceived = ILendingRouter(migrateFrom).balanceOfCollateral(onBehalf, vault);

            // Must migrate the entire position
            ILendingRouter(migrateFrom).exitPosition(
                onBehalf, vault, address(this), sharesReceived, type(uint256).max, bytes("")
            );
        } else {
            ERC20(asset).approve(vault, assetAmount);
            sharesReceived = IYieldStrategy(vault).mintShares(assetAmount, onBehalf, depositData);
        }

        _supplyCollateral(onBehalf, vault, asset, sharesReceived);
    }

    /// @dev Redeems or withdraws shares from the lending market, handles migration
    function _redeemShares(
        address sharesOwner,
        address vault,
        address asset,
        address migrateTo,
        uint256 sharesToRedeem,
        bytes memory redeemData
    ) internal returns (uint256 assetsWithdrawn) {
        address receiver = migrateTo == address(0) ? sharesOwner : migrateTo;
        uint256 sharesHeld = balanceOfCollateral(sharesOwner, vault);

        // Allows the transfer from the lending market to the sharesOwner
        IYieldStrategy(vault).allowTransfer(receiver, sharesToRedeem, sharesOwner);
        _withdrawCollateral(vault, asset, sharesToRedeem, sharesOwner, receiver);

        // If we are not migrating then burn the shares
        if (migrateTo == address(0)) {
            assetsWithdrawn = IYieldStrategy(vault).burnShares(
                sharesOwner, sharesToRedeem, sharesHeld, redeemData
            );
        }
    }

    /// @dev Initiates a withdraw request for the vault shares held by the account
    function _initiateWithdraw(
        address vault,
        address account,
        bytes calldata data
    ) internal returns (uint256 requestId) {
        uint256 sharesHeld = balanceOfCollateral(account, vault);
        if (sharesHeld == 0) revert InsufficientSharesHeld();
        return IYieldStrategy(vault).initiateWithdraw(account, sharesHeld, data);
    }

    /*** Virtual Methods (lending market specific) ***/

    /// @dev Flash borrows the assets and enters a position
    function _flashBorrowAndEnter(
        address onBehalf,
        address vault,
        address asset,
        uint256 depositAssetAmount,
        uint256 borrowAmount,
        bytes memory depositData,
        address migrateFrom
    ) internal virtual;

    /// @dev Supplies collateral in the amount of shares received to the lending market
    function _supplyCollateral(
        address onBehalf, address vault, address asset, uint256 sharesReceived
    ) internal virtual;

    /// @dev Withdraws collateral from the lending market
    function _withdrawCollateral(
        address vault,
        address asset,
        uint256 sharesToRedeem,
        address sharesOwner,
        address receiver
    ) internal virtual;

    /// @dev Liquidates a position on the lending market
    function _liquidate(
        address liquidator,
        address vault,
        address liquidateAccount,
        uint256 sharesToLiquidate,
        uint256 debtToRepay
    ) internal virtual returns (uint256 sharesToLiquidator);

    /// @dev Exits a position with a debt repayment
    function _exitWithRepay(
        address onBehalf,
        address vault,
        address asset,
        address receiver,
        uint256 sharesToRedeem,
        uint256 assetToRepay,
        bytes calldata redeemData
    ) internal virtual;

}