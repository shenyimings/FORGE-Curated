// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";
import {IMorpho, Position, Market} from "@morpho-blue/interfaces/IMorpho.sol";
import {Id, MarketParams} from "@morpho-blue/interfaces/IMorpho.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MorphoBalancesLib} from "@morpho-blue/libraries/periphery/MorphoBalancesLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Internal imports
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {IMorphoLendingAdapter} from "src/interfaces/IMorphoLendingAdapter.sol";
import {BeaconProxyFactory} from "src/BeaconProxyFactory.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IntegrationTestBase} from "./IntegrationTestBase.t.sol";
import {LeverageTokenConfig} from "src/types/DataTypes.sol";

contract MorphoLendingAdapterTest is IntegrationTestBase {
    function testFork_getLiquidationPenalty() public {
        // cbBTC/USDC market from Morpho UI
        IMorphoLendingAdapter lendingAdapter = morphoLendingAdapterFactory.deployAdapter(
            Id.wrap(0x9103c3b4e834476c9a62ea009ba2c884ee42e94e6e314a26f04d312434191836),
            address(this),
            bytes32(uint256(1))
        );

        assertEq(lendingAdapter.getLiquidationPenalty(), 0.043841336116910229e18);

        // PT-LBTC-29MAY2025/LBTC market from Morpho UI
        lendingAdapter = morphoLendingAdapterFactory.deployAdapter(
            Id.wrap(0x12c37bd01e0050e15e85e37b6bfd9a9bc357e7881a4589b6873f94512af1ce66),
            address(this),
            bytes32(uint256(2))
        );
        assertEq(lendingAdapter.getLiquidationPenalty(), 0.01677681748856126e18);
    }

    function testFork_createNewLeverageToken_RevertIf_LendingAdapterIsAlreadyInUse() public {
        vm.expectRevert(abi.encodeWithSelector(IMorphoLendingAdapter.LendingAdapterAlreadyInUse.selector));
        leverageManager.createNewLeverageToken(
            LeverageTokenConfig({
                lendingAdapter: morphoLendingAdapter,
                rebalanceAdapter: IRebalanceAdapterBase(address(0)),
                mintTokenFee: 0,
                redeemTokenFee: 0
            }),
            "LT",
            "LT"
        );
    }

    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_convertCollateralToDebtAsset() public view {
        uint256 result = morphoLendingAdapter.convertCollateralToDebtAsset(1 ether);
        assertEq(result, 3392_292471);

        result = morphoLendingAdapter.convertCollateralToDebtAsset(5 ether);
        assertEq(result, 16961462357);

        result = morphoLendingAdapter.convertCollateralToDebtAsset(10 ether);
        assertEq(result, 33922924715);

        result = morphoLendingAdapter.convertCollateralToDebtAsset(0.5 ether);
        assertEq(result, 1696146235);
    }

    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_convertDebtToCollateralAsset() public view {
        uint256 result = morphoLendingAdapter.convertDebtToCollateralAsset(1000_000000);
        assertEq(result, 294785903153823706);

        result = morphoLendingAdapter.convertDebtToCollateralAsset(80_000_000000);
        assertEq(result, 23582872252305896433);
    }

    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_getEquityInDebtAsset() public {
        uint256 collateral = 1e18;
        uint256 debt = 2000e6;

        _addCollateral(address(this), collateral);
        _borrow(address(leverageManager), debt);

        assertEq(morphoLendingAdapter.getEquityInDebtAsset(), 1392292470);
    }

    /// forge-config: default.fuzz.runs = 1
    function testForkFuzz_addCollateral(address sender, uint128 amount) public {
        amount = uint128(bound(amount, 1, type(uint128).max));

        Market memory marketBefore = MORPHO.market(WETH_USDC_MARKET_ID);
        _addCollateral(sender, amount);
        Market memory marketAfter = MORPHO.market(WETH_USDC_MARKET_ID);

        assertEq(marketAfter.totalBorrowAssets, marketBefore.totalBorrowAssets);

        Position memory position = MORPHO.position(WETH_USDC_MARKET_ID, address(morphoLendingAdapter));
        assertEq(position.collateral, amount);

        assertEq(morphoLendingAdapter.getCollateral(), amount);
        assertEq(morphoLendingAdapter.getDebt(), 0);
        assertEq(morphoLendingAdapter.getEquityInCollateralAsset(), amount);

        assertEq(WETH.balanceOf(sender), 0);
    }

    /// forge-config: default.fuzz.runs = 1
    function testForkFuzz_removeCollateral(uint128 collateralBefore, uint128 collateralToRemove) public {
        // Bound collateralToRemove to be less than or equal to collateralBefore
        collateralBefore = uint128(bound(collateralBefore, 1, type(uint128).max));
        collateralToRemove = uint128(bound(collateralToRemove, 1, collateralBefore));

        _addCollateral(address(this), collateralBefore);
        _removeCollateral(address(leverageManager), collateralToRemove);

        Position memory position = MORPHO.position(WETH_USDC_MARKET_ID, address(morphoLendingAdapter));
        assertEq(position.collateral, collateralBefore - collateralToRemove);

        assertEq(morphoLendingAdapter.getCollateral(), collateralBefore - collateralToRemove);
        assertEq(morphoLendingAdapter.getDebt(), 0);
        assertEq(morphoLendingAdapter.getEquityInCollateralAsset(), collateralBefore - collateralToRemove);

        assertEq(WETH.balanceOf(address(leverageManager)), collateralToRemove);
    }

    /// forge-config: default.fuzz.runs = 1
    function testForkFuzz_removeCollateral_RevertIf_CallerIsNotLeverageManager(address caller, uint256 amount) public {
        vm.assume(caller != address(leverageManager));
        vm.expectRevert(ILendingAdapter.Unauthorized.selector);
        vm.prank(caller);
        morphoLendingAdapter.removeCollateral(amount);
    }

    /// forge-config: default.fuzz.runs = 1
    function testForkFuzz_borrow(uint32 amount) public {
        uint256 totalSupplyAssetsBefore =
            MorphoBalancesLib.expectedTotalSupplyAssets(MORPHO, MORPHO.idToMarketParams(WETH_USDC_MARKET_ID));
        uint256 totalBorrowAssetsBefore =
            MorphoBalancesLib.expectedTotalBorrowAssets(MORPHO, MORPHO.idToMarketParams(WETH_USDC_MARKET_ID));

        uint256 maxBorrow = totalSupplyAssetsBefore - totalBorrowAssetsBefore;

        // Bound amount to max borrow available in the morpho market
        amount = uint32(bound(amount, 1, maxBorrow));

        // Put max collateral so borrow tx does not revert due to insufficient collateral
        _addCollateral(address(this), type(uint128).max);

        _borrow(address(leverageManager), amount);

        // Check if borrow actually increased total borrow assets
        // Total borrow assets can be even bigger because of accrue interest call in Morpho during borrow function call
        Market memory marketAfter = MORPHO.market(WETH_USDC_MARKET_ID);
        assertEq(marketAfter.totalBorrowAssets, totalBorrowAssetsBefore + amount);

        // Validate that borrow assets are correctly calculated
        // Allow for 1 wei difference in favour of Morpho due to rounding on their end
        uint256 expectedBorrowAssets = MorphoBalancesLib.expectedBorrowAssets(
            MORPHO, MORPHO.idToMarketParams(WETH_USDC_MARKET_ID), address(morphoLendingAdapter)
        );
        assertGe(expectedBorrowAssets, amount);
        assertLe(expectedBorrowAssets, uint256(amount) + 1);

        assertEq(morphoLendingAdapter.getCollateral(), type(uint128).max);
        assertEq(morphoLendingAdapter.getDebt(), expectedBorrowAssets);

        // Validate that debt is correctly transferred to leverage manager
        assertEq(USDC.balanceOf(address(leverageManager)), amount);
    }

    /// forge-config: default.fuzz.runs = 1
    function testForkFuzz_borrow_RevertIf_CallerIsNotLeverageManager(address caller, uint256 amount) public {
        vm.assume(caller != address(leverageManager));
        vm.expectRevert(ILendingAdapter.Unauthorized.selector);
        vm.prank(caller);
        morphoLendingAdapter.borrow(amount);
    }

    /// forge-config: default.fuzz.runs = 1
    function testForkFuzz_repay(address caller, uint128 debtBefore, uint128 debtToRepay) public {
        vm.assume(caller != address(0));

        uint256 totalSupplyAssetsBefore =
            MorphoBalancesLib.expectedTotalSupplyAssets(MORPHO, MORPHO.idToMarketParams(WETH_USDC_MARKET_ID));
        uint256 totalBorrowAssetsBefore =
            MorphoBalancesLib.expectedTotalBorrowAssets(MORPHO, MORPHO.idToMarketParams(WETH_USDC_MARKET_ID));

        uint256 maxBorrow = totalSupplyAssetsBefore - totalBorrowAssetsBefore;

        // Bound amount to max borrow available in the morpho market
        debtBefore = uint32(bound(debtBefore, 1, maxBorrow));
        debtToRepay = uint32(bound(debtToRepay, 1, debtBefore));

        _addCollateral(caller, type(uint128).max);
        _borrow(address(leverageManager), debtBefore);
        _repay(caller, debtToRepay);

        Market memory marketAfter = MORPHO.market(WETH_USDC_MARKET_ID);
        assertEq(marketAfter.totalBorrowAssets, totalBorrowAssetsBefore + debtBefore - debtToRepay);

        // Validate that borrow assets are correctly calculated
        // Allow for 1 wei difference in favour of Morpho due to rounding on their end
        uint256 expectedBorrowAssets = MorphoBalancesLib.expectedBorrowAssets(
            MORPHO, MORPHO.idToMarketParams(WETH_USDC_MARKET_ID), address(morphoLendingAdapter)
        );
        assertGe(expectedBorrowAssets, debtBefore - debtToRepay);
        assertLe(expectedBorrowAssets, debtBefore - debtToRepay + 1);

        assertEq(morphoLendingAdapter.getCollateral(), type(uint128).max);
        assertEq(morphoLendingAdapter.getDebt(), expectedBorrowAssets);

        assertEq(USDC.balanceOf(caller), 0);
    }

    function _addCollateral(address caller, uint256 amount) internal {
        deal(address(WETH), caller, amount);

        vm.startPrank(caller);
        WETH.approve(address(morphoLendingAdapter), amount);
        morphoLendingAdapter.addCollateral(amount);
        vm.stopPrank();
    }

    function _removeCollateral(address caller, uint256 amount) internal {
        vm.prank(caller);
        morphoLendingAdapter.removeCollateral(amount);
    }

    function _borrow(address caller, uint256 amount) internal {
        vm.prank(caller);
        morphoLendingAdapter.borrow(amount);
    }

    function _repay(address caller, uint256 amount) internal {
        deal(address(USDC), caller, amount);

        vm.startPrank(caller);
        USDC.approve(address(morphoLendingAdapter), amount);
        morphoLendingAdapter.repay(amount);
        vm.stopPrank();
    }
}
