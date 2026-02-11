// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {Id, MarketParams, IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {ILeverageRouter} from "src/interfaces/periphery/ILeverageRouter.sol";
import {LeverageRouter} from "src/periphery/LeverageRouter.sol";
import {ActionData} from "src/types/DataTypes.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockLendingAdapter} from "../mock/MockLendingAdapter.sol";
import {MockLeverageManager} from "../mock/MockLeverageManager.sol";
import {MockMorpho} from "../mock/MockMorpho.sol";
import {MockSwapper} from "../mock/MockSwapper.sol";
import {MockVeloraAdapter} from "../mock/MockVeloraAdapter.sol";

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

    MockVeloraAdapter public veloraAdapter;

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
        veloraAdapter = new MockVeloraAdapter();

        // Setup the leverage router
        leverageRouter = new LeverageRouter(ILeverageManager(address(leverageManager)), IMorpho(address(morpho)));

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
    }

    function _BASE_RATIO() internal view returns (uint256) {
        return leverageManager.BASE_RATIO();
    }

    function _mockLeverageManagerDeposit(
        uint256 collateral,
        uint256 debt,
        uint256 collateralReceivedFromDebtSwap,
        uint256 shares
    ) internal {
        // Mock the swap of the debt asset to the collateral asset
        swapper.mockNextExactInputSwap(debtToken, collateralToken, collateralReceivedFromDebtSwap);

        // Mock the deposit preview
        leverageManager.setMockPreviewDepositData(
            MockLeverageManager.PreviewDepositParams({leverageToken: leverageToken, collateral: collateral}),
            MockLeverageManager.MockPreviewDepositData({
                collateral: collateral,
                debt: debt,
                shares: shares,
                tokenFee: 0,
                treasuryFee: 0
            })
        );

        // Mock the LeverageManager deposit
        leverageManager.setMockDepositData(
            MockLeverageManager.DepositParams({leverageToken: leverageToken, collateral: collateral, minShares: shares}),
            MockLeverageManager.MockDepositData({collateral: collateral, debt: debt, shares: shares, isExecuted: false})
        );
    }

    function _mockLeverageManagerRedeem(
        uint256 requiredCollateral,
        uint256 requiredDebt,
        uint256 shares,
        uint256 minCollateral
    ) internal {
        vm.mockCall(
            address(leverageManager),
            abi.encodeWithSelector(ILeverageManager.previewRedeem.selector, leverageToken, shares),
            abi.encode(
                ActionData({
                    collateral: requiredCollateral,
                    debt: requiredDebt,
                    shares: shares,
                    tokenFee: 0,
                    treasuryFee: 0
                })
            )
        );

        leverageManager.setMockRedeemData(
            MockLeverageManager.RedeemParams({
                leverageToken: leverageToken,
                shares: shares,
                minCollateral: minCollateral
            }),
            MockLeverageManager.MockRedeemData({
                collateral: requiredCollateral,
                debt: requiredDebt,
                shares: shares,
                isExecuted: false
            })
        );
    }

    function _deposit(
        uint256 collateralFromSender,
        uint256 requiredCollateral,
        uint256 requiredDebt,
        uint256 collateralReceivedFromDebtSwap,
        uint256 shares
    ) internal {
        _mockLeverageManagerDeposit(requiredCollateral, requiredDebt, collateralReceivedFromDebtSwap, shares);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
        calls[0] = ILeverageRouter.Call({
            target: address(debtToken),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(swapper), requiredDebt),
            value: 0
        });
        calls[1] = ILeverageRouter.Call({
            target: address(swapper),
            data: abi.encodeWithSelector(MockSwapper.swapExactInput.selector, debtToken, requiredDebt),
            value: 0
        });

        bytes memory depositData = abi.encode(
            ILeverageRouter.DepositParams({
                sender: address(this),
                leverageToken: leverageToken,
                collateralFromSender: collateralFromSender,
                minShares: shares,
                swapCalls: calls
            })
        );

        deal(address(collateralToken), address(this), collateralFromSender);
        collateralToken.approve(address(leverageRouter), collateralFromSender);

        // Also mock morpho flash loaning the required debt amount
        deal(address(debtToken), address(leverageRouter), requiredDebt);
        debtToken.approve(address(leverageRouter), requiredDebt);

        vm.prank(address(morpho));
        leverageRouter.onMorphoFlashLoan(
            requiredDebt,
            abi.encode(
                ILeverageRouter.MorphoCallbackData({
                    action: ILeverageRouter.LeverageRouterAction.Deposit,
                    data: depositData
                })
            )
        );

        // Repayment of flash loan
        vm.prank(address(morpho));
        debtToken.transferFrom(address(leverageRouter), address(morpho), requiredDebt);
    }
}
