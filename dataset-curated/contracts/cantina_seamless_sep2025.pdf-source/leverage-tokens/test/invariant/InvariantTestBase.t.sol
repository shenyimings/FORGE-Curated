// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";
import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MarketParams, Id, IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {BeaconProxyFactory} from "src/BeaconProxyFactory.sol";
import {LeverageManager} from "src/LeverageManager.sol";
import {LeverageToken} from "src/LeverageToken.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {RebalanceAdapter} from "src/rebalance/RebalanceAdapter.sol";
import {ExternalAction, LeverageTokenConfig, LeverageTokenState} from "src/types/DataTypes.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {AdaptiveCurveIrm} from "test/invariant/morpho/AdaptiveCurveIrm.sol";
import {MORPHO_BYTECODE} from "test/invariant/morpho/Morpho.sol";
import {LeverageManagerHandler} from "test/invariant/handlers/LeverageManagerHandler.t.sol";
import {LeverageManagerHarness} from "test/unit/harness/LeverageManagerHarness.t.sol";
import {MockERC20} from "test/unit/mock/MockERC20.sol";
import {MockMorphoOracle} from "test/unit/mock/MockMorphoOracle.sol";

abstract contract InvariantTestBase is Test {
    struct MorphoInitMarketParams {
        address collateralAsset;
        address debtAsset;
        uint256 initOraclePrice;
        uint256 lltv;
        uint256 initMarketSupply;
        uint256 initMarketCollateral;
        uint256 initMarketDebt;
    }

    uint256 public constant MAX_FEE = 1e4;

    uint256 public BASE_RATIO;

    address public defaultAdmin = makeAddr("defaultAdmin");
    address public manager = makeAddr("manager");
    address public feeManagerRole = makeAddr("feeManagerRole");
    address public treasury = makeAddr("treasury");
    IMorpho public morpho;
    address public irm;

    LeverageManagerHarness public leverageManager;
    LeverageManagerHandler public leverageManagerHandler;

    RebalanceAdapter public rebalanceAdapterImplementation;

    function setUp() public {
        address leverageTokenImplementation = address(new LeverageToken());

        BeaconProxyFactory leverageTokenFactory = new BeaconProxyFactory(leverageTokenImplementation, address(this));
        address leverageManagerImplementation = address(new LeverageManagerHarness());
        address leverageManagerProxy = UnsafeUpgrades.deployUUPSProxy(
            leverageManagerImplementation,
            abi.encodeWithSelector(
                LeverageManager.initialize.selector, defaultAdmin, treasury, address(leverageTokenFactory)
            )
        );
        leverageManager = LeverageManagerHarness(leverageManagerProxy);

        rebalanceAdapterImplementation = new RebalanceAdapter();

        vm.startPrank(defaultAdmin);
        leverageManager.grantRole(leverageManager.FEE_MANAGER_ROLE(), feeManagerRole);
        vm.stopPrank();

        // TODO: Set treasury action and management fees

        BASE_RATIO = leverageManager.BASE_RATIO();

        // Deploy Morpho
        morpho = _deployMorpho();
        irm = _deployAdaptiveCurveIrm();

        _initLeverageManagerHandler(leverageManager);

        targetContract(address(leverageManagerHandler));
        targetSelector(FuzzSelector({addr: address(leverageManagerHandler), selectors: _fuzzedSelectors()}));
    }

    function test_invariantSetup_Morpho() public view {
        assertEq(morpho.owner(), defaultAdmin);
        assertTrue(morpho.isIrmEnabled(irm));
    }

    function _deployRebalanceAdapter(RebalanceAdapter.RebalanceAdapterInitParams memory initParams)
        internal
        returns (RebalanceAdapter)
    {
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(rebalanceAdapterImplementation),
            abi.encodeWithSelector(RebalanceAdapter.initialize.selector, initParams)
        );

        return RebalanceAdapter(address(proxy));
    }

    function _createActors(uint256 numActors) internal returns (address[] memory) {
        address[] memory actors = new address[](numActors);
        for (uint256 i = 0; i < numActors; i++) {
            actors[i] = makeAddr(string.concat("actor-", Strings.toString(i)));
        }
        return actors;
    }

    function _fuzzedSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = LeverageManagerHandler.mint.selector;
        selectors[1] = LeverageManagerHandler.redeem.selector;
        selectors[2] = LeverageManagerHandler.addCollateral.selector;
        selectors[3] = LeverageManagerHandler.repayDebt.selector;
        selectors[4] = LeverageManagerHandler.updateOraclePrice.selector;
        // TODO: Add selectors for fuzzing over fees (token action, treasury action, and management fees)
        return selectors;
    }

    function _initLeverageManagerHandler(LeverageManagerHarness _leverageManager) internal {
        ILeverageToken[] memory leverageTokens = new ILeverageToken[](1);

        MockERC20 collateralAsset = new MockERC20();
        MockERC20 debtAsset = new MockERC20();
        debtAsset.mockSetDecimals(6);

        leverageTokens[0] = _initLeverageToken(
            "Strategy A",
            "STRAT-A",
            MorphoInitMarketParams({
                collateralAsset: address(collateralAsset),
                debtAsset: address(debtAsset),
                initOraclePrice: 1e27, // 1 ETH = 1000 USDC
                lltv: 0.86e18, // 86% LLTV
                // Half of the maximum amount allowed by Morpho (uint128.max). 1e6 for the virtual offset they use.
                initMarketSupply: type(uint128).max / 1e6 / 2,
                initMarketCollateral: 20000e18, // 20000 ETH initial collateral (== 20m USDC)
                initMarketDebt: 10000000e6 // 10m USDC initial debt
            }),
            100, // 1% mint token fee
            100, // 1% redeem token fee
            RebalanceAdapter.RebalanceAdapterInitParams({
                owner: address(this),
                authorizedCreator: address(this),
                leverageManager: leverageManager,
                minCollateralRatio: 1 * BASE_RATIO,
                targetCollateralRatio: 2 * BASE_RATIO,
                maxCollateralRatio: 3 * BASE_RATIO,
                auctionDuration: 10 minutes,
                initialPriceMultiplier: 1.05e18, // 105%
                minPriceMultiplier: 0.9e18, // 90%
                preLiquidationCollateralRatioThreshold: 102e18, // 102%
                rebalanceReward: 5_00 // 5%
            })
        );

        // TODO: Add minimum fees leverage token config (e.g. 0.01% fee, 1 wei).
        // If issues arise, then we may need to ensure fee is set to at least 10 wei.

        address[] memory actors = _createActors(10);

        leverageManagerHandler = new LeverageManagerHandler(_leverageManager, leverageTokens, actors);

        vm.label(address(leverageManagerHandler), "leverageManagerHandler");
    }

    function _initLeverageToken(
        string memory name,
        string memory symbol,
        MorphoInitMarketParams memory marketParams,
        uint256 mintTokenFee,
        uint256 redeemTokenFee,
        RebalanceAdapter.RebalanceAdapterInitParams memory initParams
    ) internal returns (ILeverageToken leverageToken) {
        Id morphoMarketId = _initMorphoMarket(marketParams);

        ILendingAdapter lendingAdapter = new MorphoLendingAdapter(leverageManager, morpho);
        MorphoLendingAdapter(address(lendingAdapter)).initialize(morphoMarketId, address(this));

        IRebalanceAdapterBase rebalanceAdapter = _deployRebalanceAdapter(initParams);

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.postLeverageTokenCreation.selector),
            abi.encode()
        );

        LeverageTokenConfig memory config = LeverageTokenConfig({
            lendingAdapter: lendingAdapter,
            rebalanceAdapter: rebalanceAdapter,
            mintTokenFee: mintTokenFee,
            redeemTokenFee: redeemTokenFee
        });

        return leverageManager.createNewLeverageToken(config, name, symbol);
    }

    function _initMorphoMarket(MorphoInitMarketParams memory marketInitParams) internal returns (Id) {
        vm.prank(defaultAdmin);
        morpho.enableLltv(marketInitParams.lltv);

        MockMorphoOracle oracle = new MockMorphoOracle(marketInitParams.initOraclePrice);

        MarketParams memory marketParams = MarketParams({
            loanToken: marketInitParams.debtAsset,
            collateralToken: marketInitParams.collateralAsset,
            oracle: address(oracle),
            irm: irm,
            lltv: marketInitParams.lltv
        });

        // Note: This will revert if a market has already been created with the same params.
        morpho.createMarket(marketParams);

        // Add supply to the market.
        deal(address(marketInitParams.debtAsset), address(this), marketInitParams.initMarketSupply);
        IERC20(marketInitParams.debtAsset).approve(address(morpho), marketInitParams.initMarketSupply);
        morpho.supply(marketParams, marketInitParams.initMarketSupply, 0, address(this), bytes(""));

        // Add collateral to the market.
        deal(address(marketInitParams.collateralAsset), address(this), marketInitParams.initMarketCollateral);
        IERC20(marketInitParams.collateralAsset).approve(address(morpho), marketInitParams.initMarketCollateral);
        morpho.supplyCollateral(marketParams, marketInitParams.initMarketCollateral, address(this), bytes(""));

        // Add debt to the market.
        deal(address(marketInitParams.debtAsset), address(this), marketInitParams.initMarketDebt);
        IERC20(marketInitParams.debtAsset).approve(address(morpho), marketInitParams.initMarketDebt);
        morpho.borrow(marketParams, marketInitParams.initMarketDebt, 0, address(this), address(this));

        return MarketParamsLib.id(marketParams);
    }

    function _setTreasuryActionFee(ExternalAction action, uint128 newTreasuryFee) internal {
        vm.prank(feeManagerRole);
        leverageManager.setTreasuryActionFee(action, newTreasuryFee);
    }

    function _setManagementFee(ILeverageToken leverageToken, uint256 newManagementFee) internal {
        vm.prank(feeManagerRole);
        leverageManager.setManagementFee(leverageToken, newManagementFee);
    }

    function _deployAdaptiveCurveIrm() internal returns (address) {
        address _irm = address(new AdaptiveCurveIrm(address(morpho)));

        vm.prank(defaultAdmin);
        morpho.enableIrm(_irm);

        return _irm;
    }

    function _deployMorpho() internal returns (IMorpho) {
        IMorpho _morpho = IMorpho(makeAddr("morpho"));

        // Code obtained using `cast code` from the Morpho deployment on Base.
        vm.etch(address(_morpho), MORPHO_BYTECODE);

        vm.prank(address(0));
        _morpho.setOwner(defaultAdmin);

        return _morpho;
    }

    function _convertToAssets(ILeverageToken leverageToken, uint256 shares, Math.Rounding rounding)
        public
        view
        returns (uint256)
    {
        return Math.mulDiv(
            shares,
            leverageManager.getLeverageTokenLendingAdapter(leverageToken).getEquityInCollateralAsset(),
            leverageToken.totalSupply(),
            rounding
        );
    }

    function _getInvariantDescriptionString(
        string memory invariantDescription,
        LeverageManagerHandler.LeverageTokenStateData memory stateBefore,
        LeverageTokenState memory stateAfter
    ) internal pure returns (string memory) {
        return string.concat(
            "Invariant Violated: ",
            invariantDescription,
            " ",
            _getStateBeforeDebugString(stateBefore),
            " ",
            _getStateAfterDebugString(stateAfter)
        );
    }

    function _getStateBeforeDebugString(LeverageManagerHandler.LeverageTokenStateData memory stateBefore)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            " stateBefore.leverageToken: ",
            Strings.toHexString(address(stateBefore.leverageToken)),
            " stateBefore.collateral: ",
            Strings.toString(stateBefore.collateral),
            " stateBefore.collateralInDebtAsset: ",
            Strings.toString(stateBefore.collateralInDebtAsset),
            " stateBefore.debt: ",
            Strings.toString(stateBefore.debt),
            " stateBefore.equityInCollateralAsset: ",
            Strings.toString(stateBefore.equityInCollateralAsset),
            " stateBefore.equityInDebtAsset: ",
            Strings.toString(stateBefore.equityInDebtAsset),
            " stateBefore.collateralRatio: ",
            Strings.toString(stateBefore.collateralRatio),
            " stateBefore.collateralRatioUsingDebtNormalized: ",
            Strings.toString(stateBefore.collateralRatioUsingDebtNormalized),
            " stateBefore.totalSupply: ",
            Strings.toString(stateBefore.totalSupply)
        );
    }

    function _getStateAfterDebugString(LeverageTokenState memory stateAfter) internal pure returns (string memory) {
        return string.concat(
            " stateAfter.collateralInDebtAsset: ",
            Strings.toString(stateAfter.collateralInDebtAsset),
            " stateAfter.debt: ",
            Strings.toString(stateAfter.debt),
            " stateAfter.equity: ",
            Strings.toString(stateAfter.equity),
            " stateAfter.collateralRatio: ",
            Strings.toString(stateAfter.collateralRatio)
        );
    }

    /// @dev The allowed slippage in collateral ratio of the strategy after a mint should scale with the size of the
    /// min(initial debt in the strategy, initial collateral in the strategy), or equity being added in cases where the
    /// target ratio should be used, as smaller strategies may incur a higher collateral ratio delta after the mint due to
    /// precision loss.
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
}
