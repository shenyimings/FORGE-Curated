// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {Id, MarketParams, IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";

// Internal imports
import {IFeeManager} from "src/interfaces/IFeeManager.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILeverageRouter} from "src/interfaces/periphery/ILeverageRouter.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {ISwapAdapter} from "src/interfaces/periphery/ISwapAdapter.sol";
import {LeverageRouter} from "src/periphery/LeverageRouter.sol";
import {ExternalAction} from "src/types/DataTypes.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockLendingAdapter} from "../mock/MockLendingAdapter.sol";
import {MockLeverageManager} from "../mock/MockLeverageManager.sol";
import {MockMorpho} from "../mock/MockMorpho.sol";
import {MockSwapper} from "../mock/MockSwapper.sol";

contract LeverageRouterTest is Test {
    MockERC20 public collateralToken = new MockERC20();
    MockERC20 public debtToken = new MockERC20();
    ILeverageToken public leverageToken = ILeverageToken(address(new MockERC20()));

    MockMorpho public morpho;

    // Mocked Morpho protocol is setup with a market with some default market params
    Id public defaultMarketId;
    MarketParams public defaultMarketParams = MarketParams({
        loanToken: address(debtToken),
        collateralToken: address(collateralToken),
        oracle: makeAddr("mockMorphoMarketOracle"), // doesn't matter for these tests as calls to morpho should be mocked
        irm: makeAddr("mockMorphoIRM"), // doesn't matter for these tests as calls to morpho should be mocked
        lltv: 1e18 // 100%, doesn't matter for these tests as calls to morpho should be mocked
    });

    MockSwapper public swapper;

    MockLendingAdapter public lendingAdapter;

    MockLeverageManager public leverageManager;

    LeverageRouter public leverageRouter;

    function setUp() public virtual {
        // Setup mocked contracts
        defaultMarketId = MarketParamsLib.id(defaultMarketParams);
        morpho = new MockMorpho(defaultMarketId, defaultMarketParams);
        lendingAdapter = new MockLendingAdapter(address(collateralToken), address(debtToken), address(this));
        leverageManager = new MockLeverageManager();
        leverageManager.setLeverageTokenData(
            leverageToken,
            MockLeverageManager.LeverageTokenData({
                leverageToken: leverageToken,
                lendingAdapter: ILendingAdapter(address(lendingAdapter)),
                collateralAsset: collateralToken,
                debtAsset: debtToken
            })
        );
        swapper = new MockSwapper();

        // Setup the leverage router
        leverageRouter = new LeverageRouter(
            ILeverageManager(address(leverageManager)), IMorpho(address(morpho)), ISwapAdapter(address(swapper))
        );

        // Setup the mock tokens
        collateralToken.mockSetDecimals(18);
        debtToken.mockSetDecimals(6);

        vm.label(address(collateralToken), "CollateralToken");
        vm.label(address(debtToken), "DebtToken");
        vm.label(address(leverageToken), "LeverageTokenToken");
    }

    function test_setUp() public view {
        assertEq(address(leverageRouter.leverageManager()), address(leverageManager));
        assertEq(address(leverageRouter.morpho()), address(morpho));
        assertEq(address(leverageRouter.swapper()), address(swapper));
    }

    function _BASE_RATIO() internal view returns (uint256) {
        return leverageManager.BASE_RATIO();
    }

    function _mockLeverageManagerDeposit(
        uint256 requiredCollateral,
        uint256 equityInCollateralAsset,
        uint256 requiredDebt,
        uint256 collateralReceivedFromDebtSwap,
        uint256 shares
    ) internal {
        // Mock the swap of the debt asset to the collateral asset
        swapper.mockNextExactInputSwap(debtToken, collateralToken, collateralReceivedFromDebtSwap);

        // Mock the deposit preview
        leverageManager.setMockPreviewDepositData(
            MockLeverageManager.PreviewParams({
                leverageToken: leverageToken,
                equityInCollateralAsset: equityInCollateralAsset
            }),
            MockLeverageManager.MockPreviewDepositData({
                collateralToAdd: requiredCollateral,
                debtToBorrow: requiredDebt,
                shares: shares,
                tokenFee: 0,
                treasuryFee: 0
            })
        );

        // Mock the LeverageManager deposit
        leverageManager.setMockDepositData(
            MockLeverageManager.DepositParams({
                leverageToken: leverageToken,
                equityInCollateralAsset: equityInCollateralAsset,
                minShares: shares
            }),
            MockLeverageManager.MockDepositData({
                collateral: requiredCollateral,
                debt: requiredDebt,
                shares: shares,
                isExecuted: false
            })
        );
    }

    function _mockLeverageManagerWithdraw(
        uint256 requiredCollateral,
        uint256 equityInCollateralAsset,
        uint256 requiredDebt,
        uint256 requiredCollateralForSwap,
        uint256 shares
    ) internal {
        swapper.mockNextExactOutputSwap(collateralToken, debtToken, requiredCollateralForSwap);

        // Mock the withdraw preview
        leverageManager.setMockPreviewWithdrawData(
            MockLeverageManager.PreviewParams({
                leverageToken: leverageToken,
                equityInCollateralAsset: equityInCollateralAsset
            }),
            MockLeverageManager.MockPreviewWithdrawData({
                collateralToRemove: requiredCollateral,
                debtToRepay: requiredDebt,
                shares: shares,
                tokenFee: 0,
                treasuryFee: 0
            })
        );

        // Mock the LeverageManager withdraw
        leverageManager.setMockWithdrawData(
            MockLeverageManager.WithdrawParams({
                leverageToken: leverageToken,
                equityInCollateralAsset: equityInCollateralAsset,
                maxShares: shares
            }),
            MockLeverageManager.MockWithdrawData({
                collateral: requiredCollateral,
                debt: requiredDebt,
                shares: shares,
                isExecuted: false
            })
        );
    }

    function _deposit(
        uint256 equityInCollateralAsset,
        uint256 requiredCollateral,
        uint256 requiredDebt,
        uint256 collateralReceivedFromDebtSwap,
        uint256 shares
    ) internal {
        _mockLeverageManagerDeposit(
            requiredCollateral, equityInCollateralAsset, requiredDebt, collateralReceivedFromDebtSwap, shares
        );

        bytes memory depositData = abi.encode(
            LeverageRouter.DepositParams({
                token: leverageToken,
                equityInCollateralAsset: equityInCollateralAsset,
                minShares: shares,
                maxSwapCostInCollateralAsset: 0,
                sender: address(this),
                swapContext: ISwapAdapter.SwapContext({
                    path: new address[](0),
                    encodedPath: new bytes(0),
                    fees: new uint24[](0),
                    tickSpacing: new int24[](0),
                    exchange: ISwapAdapter.Exchange.AERODROME,
                    exchangeAddresses: ISwapAdapter.ExchangeAddresses({
                        aerodromeRouter: address(0),
                        aerodromePoolFactory: address(0),
                        aerodromeSlipstreamRouter: address(0),
                        uniswapSwapRouter02: address(0),
                        uniswapV2Router02: address(0)
                    })
                })
            })
        );

        deal(address(collateralToken), address(this), equityInCollateralAsset);
        collateralToken.approve(address(leverageRouter), equityInCollateralAsset);

        // Also mock morpho flash loaning the additional collateral required for the deposit
        uint256 flashLoanAmount = requiredCollateral - equityInCollateralAsset;
        deal(address(collateralToken), address(leverageRouter), flashLoanAmount);

        vm.prank(address(morpho));
        leverageRouter.onMorphoFlashLoan(
            flashLoanAmount,
            abi.encode(LeverageRouter.MorphoCallbackData({action: ExternalAction.Deposit, data: depositData}))
        );
    }
}
