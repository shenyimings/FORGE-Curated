// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Id} from "@morpho-blue/interfaces/IMorpho.sol";

// Internal imports
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {RebalanceAdapter} from "src/rebalance/RebalanceAdapter.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageRouter} from "src/interfaces/periphery/ILeverageRouter.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {IWETH9} from "src/interfaces/periphery/IWETH9.sol";
import {IEtherFiL2ModeSyncPool} from "src/interfaces/periphery/IEtherFiL2ModeSyncPool.sol";
import {IEtherFiL2ExchangeRateProvider} from "src/interfaces/periphery/IEtherFiL2ExchangeRateProvider.sol";
import {ActionData, LeverageTokenConfig} from "src/types/DataTypes.sol";
import {LeverageRouterTest} from "../LeverageRouter.t.sol";

contract LeverageRouterDepositEtherFiTest is LeverageRouterTest {
    /// @notice The ETH address per the EtherFi L2 Mode Sync Pool contract
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IERC20 public constant WEETH = IERC20(0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A);

    IEtherFiL2ModeSyncPool public constant etherFiL2ModeSyncPool =
        IEtherFiL2ModeSyncPool(0xc38e046dFDAdf15f7F56853674242888301208a5);

    IEtherFiL2ExchangeRateProvider public constant etherFiL2ExchangeRateProvider =
        IEtherFiL2ExchangeRateProvider(0xF2c5519c634796B73dE90c7Dc27B4fEd560fC3ca);

    Id public constant WEETH_WETH_MARKET_ID =
        Id.wrap(0x78d11c03944e0dc298398f0545dc8195ad201a18b0388cb8058b1bcb89440971);

    function setUp() public override {
        super.setUp();

        morphoLendingAdapter = MorphoLendingAdapter(
            address(morphoLendingAdapterFactory.deployAdapter(WEETH_WETH_MARKET_ID, address(this), bytes32("1")))
        );

        rebalanceAdapterImplementation = new RebalanceAdapter();
        rebalanceAdapter = _deployRebalanceAdapter(1.5e18, 2e18, 2.5e18, 7 minutes, 1.2e18, 0.9e18, 1.2e18, 40_00);

        leverageToken = leverageManager.createNewLeverageToken(
            LeverageTokenConfig({
                lendingAdapter: ILendingAdapter(address(morphoLendingAdapter)),
                rebalanceAdapter: IRebalanceAdapter(address(rebalanceAdapter)),
                mintTokenFee: 0,
                redeemTokenFee: 0
            }),
            "Seamless WEETH/WETH 2x leverage token",
            "ltWEETH/WETH-2x"
        );
    }

    function testFork_setUp() public view virtual override {
        assertEq(address(leverageManager.getLeverageTokenCollateralAsset(leverageToken)), address(WEETH));
        assertEq(address(leverageManager.getLeverageTokenDebtAsset(leverageToken)), address(WETH));

        assertEq(address(leverageRouter.leverageManager()), address(leverageManager));
        assertEq(address(leverageRouter.morpho()), address(MORPHO));
    }

    function testFork_Deposit() public {
        uint256 collateralFromSender = 1 ether;
        uint256 collateralToAdd = 2 * collateralFromSender;
        uint256 userBalanceOfCollateralAsset = 4 ether; // User has more than enough assets for the mint of equity
        uint256 debt = leverageRouter.previewDeposit(leverageToken, collateralFromSender).debt;

        deal(address(WEETH), user, userBalanceOfCollateralAsset);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);

        // Withdraw WETH to get ETH in the LeverageRouter
        calls[0] = ILeverageRouter.Call({
            target: address(WETH),
            data: abi.encodeWithSelector(IWETH9.withdraw.selector, debt),
            value: 0
        });
        // Deposit ETH into the EtherFi L2 Mode Sync Pool to get WEETH
        calls[1] = ILeverageRouter.Call({
            target: address(etherFiL2ModeSyncPool),
            data: abi.encodeWithSelector(IEtherFiL2ModeSyncPool.deposit.selector, ETH_ADDRESS, debt, 0, address(0)),
            value: debt
        });

        vm.startPrank(user);
        WEETH.approve(address(leverageRouter), collateralFromSender);
        leverageRouter.deposit(leverageToken, collateralFromSender, debt, 0, calls);
        vm.stopPrank();

        // Initial mint results in 1:1 shares to equity
        assertEq(leverageToken.balanceOf(user), collateralFromSender);
        // Collateral is taken from the user for the mint
        assertEq(WEETH.balanceOf(user), userBalanceOfCollateralAsset - collateralFromSender);

        assertEq(morphoLendingAdapter.getCollateral(), collateralToAdd);
        // 1.058332450654038384 WETH (WEETH to WETH is not 1:1)
        assertEq(morphoLendingAdapter.getDebt(), 1_058332450654038384);

        // No leftover assets in the LeverageRouter
        assertEq(WEETH.balanceOf(address(leverageRouter)), 0);
        assertEq(WETH.balanceOf(address(leverageRouter)), 0);
        assertEq(address(leverageRouter).balance, 0);
    }

    function testFuzzFork_Deposit(uint256 collateralFromSender) public {
        collateralFromSender = bound(collateralFromSender, 1 ether, 500 ether);

        ActionData memory previewData = leverageRouter.previewDeposit(leverageToken, collateralFromSender);

        uint256 expectedWeEthFromDebtSwap =
            etherFiL2ExchangeRateProvider.getConversionAmount(ETH_ADDRESS, previewData.debt);

        if (expectedWeEthFromDebtSwap + collateralFromSender < previewData.collateral) {
            collateralFromSender += 100;
        }

        ActionData memory previewDataFullDeposit =
            leverageManager.previewDeposit(leverageToken, collateralFromSender + expectedWeEthFromDebtSwap);

        _dealAndDeposit(WEETH, collateralFromSender, collateralFromSender, previewData.debt);

        // All collateral is used for the deposit
        assertEq(WEETH.balanceOf(user), 0);
        assertEq(WEETH.balanceOf(address(leverageRouter)), 0);

        // User receives shares and surplus debt
        assertEq(leverageToken.balanceOf(user), previewDataFullDeposit.shares);
        assertEq(WETH.balanceOf(user), previewDataFullDeposit.debt - previewData.debt);
        assertEq(WETH.balanceOf(address(leverageRouter)), 0);
    }

    function _dealAndDeposit(IERC20 collateralAsset, uint256 dealAmount, uint256 collateralFromSender, uint256 debt)
        internal
    {
        deal(address(collateralAsset), user, dealAmount);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
        // Withdraw WETH to get ETH in the LeverageRouter
        calls[0] = ILeverageRouter.Call({
            target: address(WETH),
            data: abi.encodeWithSelector(IWETH9.withdraw.selector, debt),
            value: 0
        });
        // Deposit ETH into the EtherFi L2 Mode Sync Pool to get WEETH
        calls[1] = ILeverageRouter.Call({
            target: address(etherFiL2ModeSyncPool),
            data: abi.encodeWithSelector(IEtherFiL2ModeSyncPool.deposit.selector, ETH_ADDRESS, debt, 0, address(0)),
            value: debt
        });

        vm.startPrank(user);
        collateralAsset.approve(address(leverageRouter), collateralFromSender);
        leverageRouter.deposit(leverageToken, collateralFromSender, debt, 0, calls);
        vm.stopPrank();

        // No leftover assets in the LeverageRouter
        assertEq(collateralAsset.balanceOf(address(leverageRouter)), 0);
    }
}
