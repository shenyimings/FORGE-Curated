// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {IBeaconProxyFactory} from "src/interfaces/IBeaconProxyFactory.sol";
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {IFeeManager} from "src/interfaces/IFeeManager.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {LeverageManager} from "src/LeverageManager.sol";
import {LeverageManagerHarness} from "test/unit/harness/LeverageManagerHarness.t.sol";
import {FeeManagerTest} from "test/unit/FeeManager/FeeManager.t.sol";
import {FeeManagerHarness} from "test/unit/harness/FeeManagerHarness.sol";
import {BeaconProxyFactory} from "src/BeaconProxyFactory.sol";
import {LeverageToken} from "src/LeverageToken.sol";
import {MockERC20} from "test/unit/mock/MockERC20.sol";
import {MockLendingAdapter} from "test/unit/mock/MockLendingAdapter.sol";
import {ExternalAction, LeverageTokenConfig} from "src/types/DataTypes.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {MockRebalanceAdapter} from "test/unit/mock/MockRebalanceAdapter.sol";

contract LeverageManagerTest is FeeManagerTest {
    struct MockLeverageManagerStateForAction {
        uint256 collateral;
        uint256 debt;
        uint256 sharesTotalSupply;
    }

    address public defaultAdmin = makeAddr("defaultAdmin");
    address public manager = makeAddr("manager");

    MockERC20 public collateralToken = new MockERC20();
    MockERC20 public debtToken = new MockERC20();

    MockLendingAdapter public lendingAdapter;
    MockRebalanceAdapter public rebalanceAdapter;
    address public leverageTokenImplementation;
    BeaconProxyFactory public leverageTokenFactory;
    LeverageManagerHarness public leverageManager;

    function setUp() public virtual override {
        leverageTokenImplementation = address(new LeverageToken());
        leverageTokenFactory = new BeaconProxyFactory(leverageTokenImplementation, address(this));
        lendingAdapter = new MockLendingAdapter(address(collateralToken), address(debtToken), address(this));
        rebalanceAdapter = new MockRebalanceAdapter();
        address leverageManagerImplementation = address(new LeverageManagerHarness());

        vm.expectEmit(true, true, true, true);
        emit ILeverageManager.LeverageManagerInitialized(IBeaconProxyFactory(address(leverageTokenFactory)));

        address leverageManagerProxy = UnsafeUpgrades.deployUUPSProxy(
            leverageManagerImplementation,
            abi.encodeWithSelector(LeverageManager.initialize.selector, defaultAdmin, treasury, leverageTokenFactory)
        );
        leverageManager = LeverageManagerHarness(leverageManagerProxy);

        vm.startPrank(defaultAdmin);
        leverageManager.grantRole(leverageManager.FEE_MANAGER_ROLE(), feeManagerRole);

        feeManager = FeeManagerHarness(address(leverageManager));
        vm.stopPrank();
    }

    function test_setUp() public view virtual override {
        bytes32 expectedSlot = keccak256(
            abi.encode(uint256(keccak256("seamless.contracts.storage.LeverageManager")) - 1)
        ) & ~bytes32(uint256(0xff));

        assertTrue(leverageManager.hasRole(leverageManager.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertEq(leverageManager.exposed_getLeverageManagerStorageSlot(), expectedSlot);
        assertEq(address(leverageManager.getLeverageTokenFactory()), address(leverageTokenFactory));
    }

    function _BASE_RATIO() internal view returns (uint256) {
        return leverageManager.BASE_RATIO();
    }

    function _burnShares(address recipient, uint256 amount) internal {
        vm.prank(address(leverageManager));
        leverageToken.burn(recipient, amount);
    }

    function _convertToAssets(uint256 shares, ExternalAction action) internal view returns (uint256) {
        return Math.mulDiv(
            shares,
            lendingAdapter.getEquityInCollateralAsset() + 1,
            leverageToken.totalSupply() + 1,
            action == ExternalAction.Mint ? Math.Rounding.Ceil : Math.Rounding.Floor
        );
    }

    function _getLendingAdapter() internal view returns (ILendingAdapter) {
        return leverageManager.getLeverageTokenLendingAdapter(leverageToken);
    }

    function _createDummyLeverageToken() internal {
        leverageToken = ILeverageToken(
            _createNewLeverageToken(
                manager,
                1e18,
                LeverageTokenConfig({
                    lendingAdapter: ILendingAdapter(address(lendingAdapter)),
                    rebalanceAdapter: IRebalanceAdapter(address(rebalanceAdapter)),
                    mintTokenFee: 0,
                    redeemTokenFee: 0
                }),
                address(collateralToken),
                address(debtToken),
                "dummy name",
                "dummy symbol"
            )
        );
    }

    function _createNewLeverageToken(
        address caller,
        uint256 targetCollateralRatio,
        LeverageTokenConfig memory config,
        address collateralAsset,
        address debtAsset,
        string memory name,
        string memory symbol
    ) internal returns (ILeverageToken) {
        // Mock getCollateralAsset to return the collateral asset
        vm.mockCall(
            address(config.lendingAdapter),
            abi.encodeWithSelector(ILendingAdapter.getCollateralAsset.selector),
            abi.encode(IERC20(collateralAsset))
        );

        // Mock getDebtAsset to return the debt asset
        vm.mockCall(
            address(config.lendingAdapter),
            abi.encodeWithSelector(ILendingAdapter.getDebtAsset.selector),
            abi.encode(IERC20(debtAsset))
        );

        // Mock postLeverageTokenCreation to return true
        vm.mockCall(
            address(config.lendingAdapter),
            abi.encodeWithSelector(ILendingAdapter.postLeverageTokenCreation.selector),
            abi.encode()
        );

        // Mock postLeverageTokenCreation to return true
        vm.mockCall(
            address(config.rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.postLeverageTokenCreation.selector),
            abi.encode()
        );

        // Mock initial collateral ratio
        vm.mockCall(
            address(config.rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(targetCollateralRatio)
        );

        vm.prank(caller);
        leverageToken = leverageManager.createNewLeverageToken(config, name, symbol);

        return leverageToken;
    }

    function _mintShares(address recipient, uint256 amount) internal {
        vm.prank(address(leverageManager));
        leverageToken.mint(recipient, amount);
    }

    struct ConvertToSharesState {
        uint256 totalEquity;
        uint256 sharesTotalSupply;
    }

    function _mockState_ConvertToShares(ConvertToSharesState memory state) internal {
        _mintShares(address(1), state.sharesTotalSupply);
        _mockLeverageTokenTotalEquityInCollateralAsset(state.totalEquity);
    }

    function _mockLeverageTokenTotalEquityInCollateralAsset(uint256 equity) internal {
        vm.mockCall(
            address(leverageManager.getLeverageTokenLendingAdapter(leverageToken)),
            abi.encodeWithSelector(ILendingAdapter.getEquityInCollateralAsset.selector),
            abi.encode(equity)
        );
    }

    function _computeLeverageTokenCRAfterAction(
        uint256 initialCollateral,
        uint256 initialDebtInCollateralAsset,
        uint256 collateralChange,
        uint256 debtChange,
        ExternalAction action
    ) internal view returns (uint256 newCollateralRatio) {
        debtChange = lendingAdapter.convertDebtToCollateralAsset(debtChange);

        uint256 newCollateral =
            action == ExternalAction.Mint ? initialCollateral + collateralChange : initialCollateral - collateralChange;

        uint256 newDebt = action == ExternalAction.Mint
            ? initialDebtInCollateralAsset + debtChange
            : initialDebtInCollateralAsset - debtChange;

        newCollateralRatio =
            newDebt != 0 ? Math.mulDiv(newCollateral, _BASE_RATIO(), newDebt, Math.Rounding.Floor) : type(uint256).max;

        return newCollateralRatio;
    }

    /// @dev The allowed slippage in collateral ratio of the strategy after a mint should scale with the size of the
    /// min(initial debt in the strategy, initial collateral in the strategy, initial shares total supply), as smaller
    /// strategies may incur a higher collateral ratio delta after the mint due to precision loss during calculations.
    ///
    /// For example, if the initial collateral is 3 and the initial debt is 1 (with collateral and debt normalized) then the
    /// collateral ratio is 300000000, with 2 shares total supply. If a mint of 1 equity is made, then the required collateral
    /// is 2 and the required debt is 0, so the resulting collateral is 5 and the debt is 1:
    ///
    ///    sharesMinted = convertToShares(1) = equityToAdd * (existingSharesTotalSupply) / (existingEquity) = 1 * 2 / 2 = 1
    ///    collateralToAdd = existingCollateral * sharesMinted / sharesTotalSupply = 3 * 1 / 2 = 2 (1.5 rounded up)
    ///    debtToBorrow = existingDebt * sharesMinted / sharesTotalSupply = 1 * 1 / 2 = 0 (0.5 rounded down)
    ///
    /// The resulting collateral ratio is 500000000, which is a ~+66.67% change from the initial collateral ratio.
    ///
    /// As the intial debt scales up in size, the allowed slippage should scale down as more precision can be achieved
    /// for the collateral ratio which is on 18 decimals:
    ///    initialDebt < 100: 1e18 (100% slippage)
    ///    initialDebt < 1000: 0.1e18 (10% slippage)
    ///    initialDebt < 10000: 0.01e18 (1% slippage)
    ///    initialDebt < 100000: 0.001e18 (0.1% slippage)
    ///    initialDebt < 1000000: 0.0001e18 (0.01% slippage)
    ///    initialDebt < 10000000: 0.00001e18 (0.001% slippage)
    ///    ...
    ///    initialDebt < 10000000000000000000: 0.00000000000000001e18 (0.000000000000001% slippage)
    ///    initialDebt >= 100000000000000000000: 0.000000000000000001e18 (0.0000000000000001% slippage)
    ///
    /// Note: We can at minimum support up to 0.000000000000000001e18 (0.0000000000000001% slippage) due to the base collateral ratio
    ///       being 1e18
    function _getAllowedCollateralRatioSlippage(uint256 amount)
        internal
        pure
        returns (uint256 allowedSlippagePercentage)
    {
        if (amount == 0) {
            return 1e18;
        }

        uint256 i = Math.log10(amount);

        // This is the minimum slippage that we can support due to the precision of the collateral ratio being
        // 1e18 (1e18 / 1e18 = 1 (0.000000000000000001e18))
        if (i > 18) return 0.000000000000000001e18;

        // If i <= 1, that means amount < 100, thus slippage = 1e18
        // Otherwise slippage = 1e18 / (10^(i - 1))
        return (i <= 1) ? 1e18 : (1e18 / (10 ** (i - 1)));
    }

    function _setTreasuryActionFee(ExternalAction action, uint256 fee) internal {
        vm.prank(feeManagerRole);
        leverageManager.setTreasuryActionFee(action, fee);
    }

    function _mockLeverageTokenDebt(uint256 debt) internal {
        vm.mockCall(
            address(leverageManager.getLeverageTokenLendingAdapter(leverageToken)),
            abi.encodeWithSelector(ILendingAdapter.getDebt.selector),
            abi.encode(debt)
        );
    }

    function _mockLeverageTokenCollateralInDebtAsset(uint256 collateral) internal {
        vm.mockCall(
            address(leverageManager.getLeverageTokenLendingAdapter(leverageToken)),
            abi.encodeWithSelector(ILendingAdapter.getCollateralInDebtAsset.selector),
            abi.encode(collateral)
        );
    }

    function _prepareLeverageManagerStateForAction(MockLeverageManagerStateForAction memory state) internal {
        lendingAdapter.mockDebt(state.debt);
        lendingAdapter.mockCollateral(state.collateral);

        uint256 debtInCollateralAsset = lendingAdapter.convertDebtToCollateralAsset(state.debt);
        _mockState_ConvertToShares(
            ConvertToSharesState({
                totalEquity: state.collateral > debtInCollateralAsset ? state.collateral - debtInCollateralAsset : 0,
                sharesTotalSupply: state.sharesTotalSupply
            })
        );
    }
}
