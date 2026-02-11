// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMorpho, Id, MarketParams} from "@morpho-blue/interfaces/IMorpho.sol";
import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";

// Internal imports
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {LeverageManagerHarness} from "test/unit/harness/LeverageManagerHarness.t.sol";
import {
    LeverageTokenState,
    RebalanceAction,
    ActionType,
    LeverageTokenConfig,
    TokenTransfer
} from "src/types/DataTypes.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {LeverageManagerTest} from "test/integration/LeverageManager/LeverageManager.t.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {RebalanceAdapter} from "src/rebalance/RebalanceAdapter.sol";

contract RebalanceTest is LeverageManagerTest {
    int256 public constant MAX_PERCENTAGE = 100_00; // 100%

    Id public constant USDC_WETH_MARKET_ID = Id.wrap(0x3b3769cfca57be2eaed03fcc5299c25691b77781a1e124e7a8d520eb9a7eabb5);

    ILeverageToken ethLong2x;
    ILeverageToken ethShort2x;

    MorphoLendingAdapter ethLong2xAdapter;
    MorphoLendingAdapter ethShort2xAdapter;

    RebalanceAdapter ethLong2xRebalanceAdapter;
    RebalanceAdapter ethShort2xRebalanceAdapter;

    function setUp() public virtual override {
        super.setUp();

        rebalanceAdapterImplementation = new RebalanceAdapter();
        ethLong2xRebalanceAdapter =
            _deployRebalanceAdapter(1.8e18, 2e18, 2.2e18, 7 minutes, 1.2e18, 0.98e18, 1.3e18, 45_66);
        ethShort2xRebalanceAdapter =
            _deployRebalanceAdapter(1.3e18, 1.5e18, 2e18, 7 minutes, 1.2e18, 0.9e18, 1.3e18, 45_66);

        ethLong2xAdapter = MorphoLendingAdapter(
            address(morphoLendingAdapterFactory.deployAdapter(WETH_USDC_MARKET_ID, address(this), bytes32(uint256(1))))
        );

        ethShort2xAdapter = MorphoLendingAdapter(
            address(morphoLendingAdapterFactory.deployAdapter(USDC_WETH_MARKET_ID, address(this), bytes32(uint256(2))))
        );

        ethLong2x = leverageManager.createNewLeverageToken(
            LeverageTokenConfig({
                lendingAdapter: ILendingAdapter(address(ethLong2xAdapter)),
                rebalanceAdapter: IRebalanceAdapter(ethLong2xRebalanceAdapter),
                depositTokenFee: 0,
                withdrawTokenFee: 0
            }),
            "Seamless ETH/USDC 2x leverage token",
            "ltETH/USDC-2x"
        );

        ethShort2x = leverageManager.createNewLeverageToken(
            LeverageTokenConfig({
                lendingAdapter: ILendingAdapter(address(ethShort2xAdapter)),
                rebalanceAdapter: IRebalanceAdapter(ethShort2xRebalanceAdapter),
                depositTokenFee: 0,
                withdrawTokenFee: 0
            }),
            "Seamless USDC/ETH 2x leverage token",
            "ltUSDC/ETH-2x"
        );
    }

    /// @dev In this block price on oracle 3392.292471591441746049801068
    function test_rebalance_SingleLeverageToken_OverCollateralized() public {
        _depositEthLong2x();

        // After previous action we expect leverage token to have 20 ETH collateral
        // We need to mock price change so leverage token goes off balance
        // Price should change for 20% which means that collateral ratio is now going to be ~2.4x
        // Price of ETH after this change should be 4070.750000000000000000000000
        _moveEthPrice(20_00);

        LeverageTokenState memory stateBefore = getLeverageTokenState(ethLong2x);
        assertEq(stateBefore.collateralRatio, 2399999999988208563);

        uint256 collateralBefore = ethLong2xAdapter.getCollateral();
        uint256 debtBefore = ethLong2xAdapter.getDebt();

        // At the moment we have the following state:
        // 20 ETH collateral = 81414.999999999999999999999992 USDC debt
        // 33922.92471591441746049801068 USDC debt is owed to the Morpho protocol

        // User rebalances the leverage token but still leaves it out of bounds
        // User adds 1 ETH collateral and borrows 4100 USDC
        _rebalance(ethLong2x, 1e18, 0, 4100 * 1e6, 0);

        // Validate that ratio is better (leans towards 2x)
        LeverageTokenState memory stateAfter = getLeverageTokenState(ethLong2x);
        assertLe(stateAfter.collateralRatio, stateBefore.collateralRatio);
        assertGe(stateAfter.collateralRatio, 2 * BASE_RATIO);

        uint256 collateralAfter = ethLong2xAdapter.getCollateral();
        uint256 debtAfter = ethLong2xAdapter.getDebt();

        // Check that collateral and debt are changed properly
        assertEq(collateralAfter, collateralBefore + 1e18);
        assertEq(debtAfter, debtBefore + 4100 * 1e6);

        // Check that USDC is sent to rebalancer and that WETH is taken from him
        assertEq(USDC.balanceOf(address(ethLong2xRebalanceAdapter)), 4100 * 1e6);
        assertEq(WETH.balanceOf(address(ethLong2xRebalanceAdapter)), 0);
    }

    function test_rebalance_SingleLeverageToken_UnderCollateralized() public {
        _depositEthLong2x();

        // After previous action we expect leverage token to have 20 ETH collateral
        // We need to mock price change so leverage token goes off balance
        // Price should change for 20% downwards which means that collateral ratio is now going to be ~1.6x
        // Price of ETH after this change should be 2728.194981060953630732673600
        _moveEthPrice(-20_00);

        LeverageTokenState memory stateBefore = getLeverageTokenState(ethLong2x);
        assertEq(stateBefore.collateralRatio, 1599999999982312845);

        uint256 collateralBefore = ethLong2xAdapter.getCollateral();
        uint256 debtBefore = ethLong2xAdapter.getDebt();

        // User repays 2800 USDC and removes 1 ETH collateral
        _rebalance(ethLong2x, 0, 1e18, 0, 2800 * 1e6);

        // Validate that ratio is better (leans towards 2x)
        LeverageTokenState memory stateAfter = getLeverageTokenState(ethLong2x);
        assertGe(stateAfter.collateralRatio, stateBefore.collateralRatio);
        assertLe(stateAfter.collateralRatio, 2 * BASE_RATIO);

        uint256 collateralAfter = ethLong2xAdapter.getCollateral();
        uint256 debtAfter = ethLong2xAdapter.getDebt();

        // Check that collateral and debt are changed properly
        assertEq(collateralAfter, collateralBefore - 1e18);
        assertEq(debtAfter, debtBefore - 2800 * 1e6);

        // Check that USDC is sent to rebalancer and that WETH is taken from him
        assertEq(USDC.balanceOf(address(ethLong2xRebalanceAdapter)), 0);
        assertEq(WETH.balanceOf(address(ethLong2xRebalanceAdapter)), 1e18);
    }

    /// @dev In this block price on oracle 3392.292471591441746049801068
    function test_rebalance_RevertIf_ExposureDirectionChanged() public {
        _depositEthLong2x();

        // Move price of ETH 20% downwards
        _moveEthPrice(-20_00);

        // User comes and rebalances it in a way that he only adds collateral so leverage token becomes over-collateralized
        (RebalanceAction[] memory actions, TokenTransfer[] memory transfersIn, TokenTransfer[] memory transfersOut) =
            _prepareForRebalance(ethLong2x, 10 * 1e18, 0, 0, 0);

        vm.prank(address(ethLong2xRebalanceAdapter));
        vm.expectRevert(
            abi.encodeWithSelector(ILeverageManager.InvalidLeverageTokenStateAfterRebalance.selector, ethLong2x)
        );
        leverageManager.rebalance(actions, transfersIn, transfersOut);
    }

    struct RebalanceData {
        uint256 collateralToAdd;
        uint256 collateralToRemove;
        uint256 debtToBorrow;
        uint256 debtToRepay;
    }

    /// @notice Prepares rebalance parameters and executes rebalance
    /// @param leverageToken LeverageToken to rebalance
    /// @param collToAdd Amount of collateral to add
    /// @param collToTake Amount of collateral to remove
    /// @param debtToBorrow Amount of debt to borrow
    /// @param debtToRepay Amount of debt to repay
    function _rebalance(
        ILeverageToken leverageToken,
        uint256 collToAdd,
        uint256 collToTake,
        uint256 debtToBorrow,
        uint256 debtToRepay
    ) internal {
        (RebalanceAction[] memory actions, TokenTransfer[] memory transfersIn, TokenTransfer[] memory transfersOut) =
            _prepareForRebalance(leverageToken, collToAdd, collToTake, debtToBorrow, debtToRepay);

        vm.prank(
            address(leverageToken) == address(ethLong2x)
                ? address(ethLong2xRebalanceAdapter)
                : address(ethShort2xRebalanceAdapter)
        );
        leverageManager.rebalance(actions, transfersIn, transfersOut);
    }

    /// @notice Prepares the state for the rebalance which means prepares the parameters for function call but also mint tokens to rebalancer
    /// @param leverageToken LeverageToken to rebalance
    /// @param collToAdd Amount of collateral to add
    /// @param collToTake Amount of collateral to remove
    /// @param debtToBorrow Amount of debt to borrow
    /// @param debtToRepay Amount of debt to repay
    /// @return actions Actions to execute
    /// @return transfersIn Transfers in tokens parameters for function call
    /// @return transfersOut Transfers out tokens parameters for function call
    function _prepareForRebalance(
        ILeverageToken leverageToken,
        uint256 collToAdd,
        uint256 collToTake,
        uint256 debtToBorrow,
        uint256 debtToRepay
    )
        internal
        returns (
            RebalanceAction[] memory actions,
            TokenTransfer[] memory transfersIn,
            TokenTransfer[] memory transfersOut
        )
    {
        address rebalancer = address(leverageToken) == address(ethLong2x)
            ? address(ethLong2xRebalanceAdapter)
            : address(ethShort2xRebalanceAdapter);

        actions = new RebalanceAction[](4);
        actions[0] =
            RebalanceAction({leverageToken: leverageToken, actionType: ActionType.AddCollateral, amount: collToAdd});
        actions[1] = RebalanceAction({leverageToken: leverageToken, actionType: ActionType.Repay, amount: debtToRepay});
        actions[2] =
            RebalanceAction({leverageToken: leverageToken, actionType: ActionType.RemoveCollateral, amount: collToTake});
        actions[3] =
            RebalanceAction({leverageToken: leverageToken, actionType: ActionType.Borrow, amount: debtToBorrow});

        address collateralToken = address(leverageManager.getLeverageTokenCollateralAsset(leverageToken));
        address debtToken = address(leverageManager.getLeverageTokenDebtAsset(leverageToken));

        // Give collateral token to add collateral and give debt token to repay debt
        transfersIn = new TokenTransfer[](2);
        transfersIn[0] = TokenTransfer({token: collateralToken, amount: collToAdd});
        transfersIn[1] = TokenTransfer({token: debtToken, amount: debtToRepay});

        transfersOut = new TokenTransfer[](2);
        transfersOut[0] = TokenTransfer({token: collateralToken, amount: collToTake});
        transfersOut[1] = TokenTransfer({token: debtToken, amount: debtToBorrow});

        // Mint collateral token to add collateral and debt token to repay debt
        deal(address(collateralToken), rebalancer, collToAdd);
        deal(address(debtToken), rebalancer, debtToRepay);

        vm.startPrank(rebalancer);

        // Approve collateral token to add collateral and debt token to repay debt
        IERC20(collateralToken).approve(address(leverageManager), collToAdd);
        IERC20(debtToken).approve(address(leverageManager), debtToRepay);

        vm.stopPrank();

        return (actions, transfersIn, transfersOut);
    }

    function _supplyWETHForETHShortLeverageToken() internal {
        deal(address(WETH), address(this), 1000 * 1e18);
        IMorpho morpho = IMorpho(ethShort2xAdapter.morpho());

        (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) =
            ethShort2xAdapter.marketParams();
        MarketParams memory marketParams =
            MarketParams({loanToken: loanToken, collateralToken: collateralToken, oracle: oracle, irm: irm, lltv: lltv});

        WETH.approve(address(morpho), 1000 * 1e18);
        morpho.supply(marketParams, 1000 * 1e18, 0, address(this), new bytes(0));
    }

    function _giftUSDCToETHShortLeverageToken() internal {
        deal(address(USDC), address(this), 150_000 * 1e6);
        IMorpho morpho = IMorpho(ethShort2xAdapter.morpho());

        (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) =
            ethShort2xAdapter.marketParams();
        MarketParams memory marketParams =
            MarketParams({loanToken: loanToken, collateralToken: collateralToken, oracle: oracle, irm: irm, lltv: lltv});

        USDC.approve(address(morpho), 150_000 * 1e6);
        morpho.supplyCollateral(marketParams, 150_000 * 1e6, address(ethShort2xAdapter), new bytes(0));
    }

    /// @dev Performs initial deposit into ETH long leverage token, amount is not important but it is important to gain some collateral and debt
    function _depositEthLong2x() internal {
        uint256 equityToDeposit = 10 ether;
        uint256 collateralToAdd = leverageManager.previewDeposit(ethLong2x, equityToDeposit).collateral;
        _deposit(ethLong2x, user, equityToDeposit, collateralToAdd);
    }

    /// @dev Performs initial deposit into ETH short leverage token, amount is not important but it is important to gain some collateral and debt
    function _depositEthShort2x() internal {
        uint256 equityToDeposit = 30_000 * 1e6;
        uint256 collateralToAdd = leverageManager.previewDeposit(ethShort2x, equityToDeposit).collateral;
        _deposit(ethShort2x, user, equityToDeposit, collateralToAdd);
    }

    function _deposit(
        ILeverageToken _leverageToken,
        address _caller,
        uint256 _equityInCollateralAsset,
        uint256 _collateralToAdd
    ) internal returns (uint256) {
        IERC20 collateralAsset = leverageManager.getLeverageTokenCollateralAsset(_leverageToken);
        deal(address(collateralAsset), _caller, _collateralToAdd);

        vm.startPrank(_caller);
        collateralAsset.approve(address(leverageManager), _collateralToAdd);
        uint256 shares = leverageManager.deposit(_leverageToken, _equityInCollateralAsset, 0).shares;
        vm.stopPrank();

        return shares;
    }

    /// @dev Moves price of ETH for given percentage, if percentage is negative it moves price of ETH down
    function _moveEthPrice(int256 percentage) internal {
        // Move price on ETH long
        (,, address ethLongOracle,,) = ethLong2xAdapter.marketParams();
        uint256 currentPrice = IOracle(ethLongOracle).price();
        int256 priceChange = int256(currentPrice) * percentage / MAX_PERCENTAGE;
        uint256 newPrice = uint256(int256(currentPrice) + priceChange);
        vm.mockCall(address(ethLongOracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(newPrice));

        // Move price in different direction on ETH short
        (,, address ethShortOracle,,) = ethShort2xAdapter.marketParams();
        currentPrice = IOracle(ethShortOracle).price();
        priceChange = int256(currentPrice) * percentage / MAX_PERCENTAGE;
        newPrice = uint256(int256(currentPrice) - priceChange);
        vm.mockCall(address(ethShortOracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(newPrice));
    }

    function getLeverageTokenState(ILeverageToken leverageToken) internal view returns (LeverageTokenState memory) {
        return LeverageManagerHarness(address(leverageManager)).getLeverageTokenState(leverageToken);
    }
}
