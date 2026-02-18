// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {ILendingRouter} from "../interfaces/ILendingRouter.sol";
import {InsufficientAssetsForRepayment} from "../interfaces/Errors.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldStrategy} from "../interfaces/IYieldStrategy.sol";
import {IMorphoLiquidateCallback, IMorphoFlashLoanCallback, IMorphoRepayCallback} from "../interfaces/Morpho/IMorphoCallbacks.sol";
import {ADDRESS_REGISTRY} from "../utils/Constants.sol";
import {AbstractLendingRouter} from "./AbstractLendingRouter.sol";
import {
    MORPHO,
    MarketParams,
    Id,
    Position,
    Market,
    Withdrawal,
    PUBLIC_ALLOCATOR
} from "../interfaces/Morpho/IMorpho.sol";

struct MorphoParams {
    address irm;
    uint256 lltv;
}

struct MorphoAllocation {
    address vault;
    uint256 feeAmount;
    Withdrawal[] withdrawals;
}

contract MorphoLendingRouter is AbstractLendingRouter, IMorphoLiquidateCallback, IMorphoFlashLoanCallback, IMorphoRepayCallback {
    using SafeERC20 for ERC20;
    using TokenUtils for ERC20;

    mapping(address vault => MorphoParams params) private s_morphoParams;

    function initializeMarket(address vault, address irm, uint256 lltv) external {
        require(ADDRESS_REGISTRY.upgradeAdmin() == msg.sender);
        // Cannot override parameters once they are set
        require(s_morphoParams[vault].irm == address(0));
        require(s_morphoParams[vault].lltv == 0);

        s_morphoParams[vault] = MorphoParams({
            irm: irm,
            lltv: lltv
        });

        MORPHO.createMarket(marketParams(vault));
    }

    function marketParams(address vault) public view returns (MarketParams memory) {
        return marketParams(vault, IYieldStrategy(vault).asset());
    }

    function marketParams(address vault, address asset) internal view returns (MarketParams memory) {
        MorphoParams memory params = s_morphoParams[vault];

        return MarketParams({
            loanToken: asset,
            collateralToken: vault,
            oracle: vault,
            irm: params.irm,
            lltv: params.lltv
        });
    }

    function morphoId(MarketParams memory m) internal pure returns (Id) {
        return Id.wrap(keccak256(abi.encode(m)));
    }

    /// @dev Allows integration with the public allocator so that accounts can
    /// ensure there is sufficient liquidity in the lending market before entering
    function _allocate(address vault, MorphoAllocation[] calldata allocationData) internal {
        MarketParams memory m = marketParams(vault);

        uint256 totalFeeAmount;
        for (uint256 i = 0; i < allocationData.length; i++) {
            PUBLIC_ALLOCATOR.reallocateTo{value: allocationData[i].feeAmount}(
                allocationData[i].vault, allocationData[i].withdrawals, m
            );
            totalFeeAmount += allocationData[i].feeAmount;
        }
        require(msg.value == totalFeeAmount, "Insufficient fee amount");
    }

    function allocateAndEnterPosition(
        address onBehalf,
        address vault,
        uint256 depositAssetAmount,
        uint256 borrowAmount,
        bytes calldata depositData,
        MorphoAllocation[] calldata allocationData
    ) external payable isAuthorized(onBehalf, vault) {
        _allocate(vault, allocationData);
        enterPosition(onBehalf, vault, depositAssetAmount, borrowAmount, depositData);
    }

    function allocateAndMigratePosition(
        address onBehalf,
        address vault,
        address migrateFrom,
        MorphoAllocation[] calldata allocationData
    ) external payable isAuthorized(onBehalf, vault) {
        _allocate(vault, allocationData);
        migratePosition(onBehalf, vault, migrateFrom);
    }

    function _flashBorrowAndEnter(
        address onBehalf,
        address vault,
        address asset,
        uint256 depositAssetAmount,
        uint256 borrowAmount,
        bytes memory depositData,
        address migrateFrom
    ) internal override {
        // At this point we will flash borrow funds from the lending market and then
        // receive control in a different function on a callback.
        bytes memory flashLoanData = abi.encode(
            onBehalf, vault, asset, depositAssetAmount, depositData, migrateFrom
        );
        MORPHO.flashLoan(asset, borrowAmount, flashLoanData);
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external override {
        require(msg.sender == address(MORPHO));

        (
            address onBehalf,
            address vault,
            address asset,
            uint256 depositAssetAmount,
            bytes memory depositData,
            address migrateFrom
        ) = abi.decode(data, (address, address, address, uint256, bytes, address));

        _enterOrMigrate(onBehalf, vault, asset, assets + depositAssetAmount, depositData, migrateFrom);

        MarketParams memory m = marketParams(vault, asset);
        // Borrow the assets in order to repay the flash loan
        MORPHO.borrow(m, assets, 0, onBehalf, address(this));

        // Allow for flash loan to be repaid
        ERC20(asset).checkApprove(address(MORPHO), assets);
    }

    function _supplyCollateral(
        address onBehalf,
        address vault,
        address asset,
        uint256 sharesReceived
    ) internal override {
        MarketParams memory m = marketParams(vault, asset);

        // Allows the transfer from the lending market to the Morpho contract
        IYieldStrategy(vault).allowTransfer(address(MORPHO), sharesReceived, onBehalf);

        // We should receive shares in return
        ERC20(vault).approve(address(MORPHO), sharesReceived);
        MORPHO.supplyCollateral(m, sharesReceived, onBehalf, "");
    }

    function _withdrawCollateral(
        address vault,
        address asset,
        uint256 sharesToRedeem,
        address sharesOwner,
        address receiver
    ) internal override {
        MarketParams memory m = marketParams(vault, asset);
        MORPHO.withdrawCollateral(m, sharesToRedeem, sharesOwner, receiver);
    }

    function _exitWithRepay(
        address onBehalf,
        address vault,
        address asset,
        address receiver,
        uint256 sharesToRedeem,
        uint256 assetToRepay,
        bytes calldata redeemData
    ) internal override {
        MarketParams memory m = marketParams(vault, asset);

        uint256 sharesToRepay;
        if (assetToRepay == type(uint256).max) {
            // If assetToRepay is uint256.max then get the morpho borrow shares amount to
            // get a full exit.
            sharesToRepay = MORPHO.position(morphoId(m), onBehalf).borrowShares;
            assetToRepay = 0;
        }

        bytes memory repayData = abi.encode(
            onBehalf, vault, asset, receiver, sharesToRedeem, redeemData, _isMigrate(receiver)
        );

        // Will trigger a callback to onMorphoRepay
        MORPHO.repay(m, assetToRepay, sharesToRepay, onBehalf, repayData);
    }

    function onMorphoRepay(uint256 assetToRepay, bytes calldata data) external override {
        require(msg.sender == address(MORPHO));

        (
            address sharesOwner,
            address vault,
            address asset,
            address receiver,
            uint256 sharesToRedeem,
            bytes memory redeemData,
            bool isMigrate
        ) = abi.decode(data, (address, address, address, address, uint256, bytes, bool));

        uint256 assetsWithdrawn = _redeemShares(
            sharesOwner, vault, asset, isMigrate ? receiver : address(0), sharesToRedeem, redeemData
        );

        if (isMigrate) {
            // When migrating we do not withdraw any assets and we must repay the entire debt
            // from the previous lending router.
            ERC20(asset).safeTransferFrom(receiver, address(this), assetToRepay);
            assetsWithdrawn = assetToRepay;
        }

        // Transfer any profits to the receiver
        if (assetsWithdrawn < assetToRepay) {
            // We have to revert in this case because we've already redeemed the yield tokens
            revert InsufficientAssetsForRepayment(assetToRepay, assetsWithdrawn);
        }

        uint256 profitsWithdrawn;
        unchecked {
            profitsWithdrawn = assetsWithdrawn - assetToRepay;
        }
        ERC20(asset).safeTransfer(receiver, profitsWithdrawn);

        // Allow morpho to repay the debt
        ERC20(asset).checkApprove(address(MORPHO), assetToRepay);
    }

    function _liquidate(
        address liquidator,
        address vault,
        address liquidateAccount,
        uint256 sharesToLiquidate,
        uint256 debtToRepay
    ) internal override returns (uint256 sharesToLiquidator) {
        MarketParams memory m = marketParams(vault);
        (sharesToLiquidator, /* */) = MORPHO.liquidate(
            m, liquidateAccount, sharesToLiquidate, debtToRepay, abi.encode(m.loanToken, liquidator)
        );
    }

    function onMorphoLiquidate(uint256 repaidAssets, bytes calldata data) external override {
        require(msg.sender == address(MORPHO));
        (address asset, address liquidator) = abi.decode(data, (address, address));

        ERC20(asset).safeTransferFrom(liquidator, address(this), repaidAssets);
        ERC20(asset).checkApprove(address(MORPHO), repaidAssets);
    }

    function balanceOfCollateral(address account, address vault) public view override returns (uint256 collateralBalance) {
        MarketParams memory m = marketParams(vault);
        collateralBalance = MORPHO.position(morphoId(m), account).collateral;
    }

    function healthFactor(address borrower, address vault) public override returns (uint256 borrowed, uint256 collateralValue, uint256 maxBorrow) {
        MarketParams memory m = marketParams(vault);
        Id id = morphoId(m);
        // Ensure interest is accrued before calculating health factor
        MORPHO.accrueInterest(m);
        Position memory position = MORPHO.position(id, borrower);
        Market memory market = MORPHO.market(id);

        if (position.borrowShares > 0) {
            borrowed = (uint256(position.borrowShares) * uint256(market.totalBorrowAssets)) / uint256(market.totalBorrowShares);
        } else {
            borrowed = 0;
        }
        collateralValue = (uint256(position.collateral) * IYieldStrategy(vault).price(borrower)) / 1e36;
        maxBorrow = collateralValue * m.lltv / 1e18;
    }

}
