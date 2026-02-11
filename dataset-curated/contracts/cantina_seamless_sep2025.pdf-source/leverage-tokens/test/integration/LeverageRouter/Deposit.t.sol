// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMorpho, MarketParams} from "@morpho-blue/interfaces/IMorpho.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {LeverageRouter} from "src/periphery/LeverageRouter.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {RebalanceAdapter} from "src/rebalance/RebalanceAdapter.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILeverageRouter} from "src/interfaces/periphery/ILeverageRouter.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {IUniswapV2Router02} from "src/interfaces/periphery/IUniswapV2Router02.sol";
import {IUniswapSwapRouter02} from "src/interfaces/periphery/IUniswapSwapRouter02.sol";
import {ActionData, LeverageTokenConfig} from "src/types/DataTypes.sol";
import {LeverageRouterTest} from "./LeverageRouter.t.sol";
import {MockSwapper} from "../../unit/mock/MockSwapper.sol";

contract LeverageRouterDepositTest is LeverageRouterTest {
    struct DepositWithMockedSwapParams {
        ILeverageToken leverageToken;
        IERC20 collateralAsset;
        IERC20 debtAsset;
        uint256 userBalanceOfCollateralAsset;
        uint256 collateralFromSender;
        uint256 flashLoanAmount;
        uint256 minShares;
        uint256 collateralRequired;
        uint256 collateralReceivedFromDebtSwap;
    }

    MockSwapper public mockSwapper;

    MorphoLendingAdapter ethShortLendingAdapter;
    RebalanceAdapter ethShortRebalanceAdapter;

    ILeverageToken ethShortLeverageToken;

    function setUp() public override {
        super.setUp();

        mockSwapper = new MockSwapper();

        ethShortRebalanceAdapter =
            _deployRebalanceAdapter(1.3e18, 1.5e18, 2e18, 7 minutes, 1.2e18, 0.9e18, 1.3e18, 45_66);

        ethShortLendingAdapter = MorphoLendingAdapter(
            address(morphoLendingAdapterFactory.deployAdapter(USDC_WETH_MARKET_ID, address(this), bytes32(uint256(1))))
        );

        ethShortLeverageToken = leverageManager.createNewLeverageToken(
            LeverageTokenConfig({
                lendingAdapter: ILendingAdapter(address(ethShortLendingAdapter)),
                rebalanceAdapter: IRebalanceAdapter(address(ethShortRebalanceAdapter)),
                mintTokenFee: 0,
                redeemTokenFee: 0
            }),
            "Seamless USDC/ETH 2x leverage token",
            "ltUSDC/ETH-2x"
        );
    }

    function testFork_deposit_Velora() public {
        // Approximate block this test was written. Velora calldata needs to be generated near this block.
        vm.createSelectFork(vm.envString("BASE_RPC_URL"), 34806450);
        _deployLeverageRouterIntegrationTestContracts();

        uint256 collateralFromSender = 1 ether;
        uint256 collateralToAdd = 2 * collateralFromSender;
        uint256 userBalanceOfCollateralAsset = 4 ether; // User has more than enough assets for the mint of equity
        uint256 flashLoanAmount = 4485.353894e6;
        uint256 minShares = 1 ether * 0.99e18 / 1e18; // 1% slippage

        {
            // Sanity check that LR preview deposit matches test params
            ActionData memory leverageRouterPreview = leverageRouter.previewDeposit(leverageToken, collateralFromSender);
            assertEq(leverageRouterPreview.debt, flashLoanAmount);
            assertEq(leverageRouterPreview.shares, 1 ether);
            assertEq(leverageRouterPreview.collateral, collateralToAdd);
            assertEq(leverageRouterPreview.tokenFee, 0);
            assertEq(leverageRouterPreview.treasuryFee, 0);
        }

        // Results in 0.994467364480142211 ether
        bytes memory sellCalldata =
            hex"e3ead59e00000000000000000000000000c600b30fb0400701010f4b080409018b9006e0000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000004200000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000010b5911a60000000000000000000000000000000000000000000000000dbdb135648e1a610000000000000000000000000000000000000000000000000de13976941dc2bac6f3df094c814e6d808445a1bf810fa200000000000000000000000002131b940000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000016c0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000016c000000000000000000000000000000160000000000000012000000000000001901b2b6ce813b99b840fe632c63bca5394938ef01e00000140008400000000000300000000000000000000000000000000000000000000000000000000c04b8d59000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000006a000f20005980200259b80c51020030400010680000000000000000000000000000000000000000000000000000000068b9ce8c000000000000000000000000000000000000000000000000000000000ab1a48b0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002b833589fcd6edb6e08f4c7c32d4f71b54bda029130000014200000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000001e0000000000000006c00000000000003e876578ecf9a141296ec657847fb45b0585bcda3a600000140006400440000000b00000000000000000000000000000000000000000000000000000000750283bc00000000000000000000000088c044fb203b58b12252be7242926b1eeb113b4a000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000004200000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000001abc1b5d0000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000060000006000240000ff00000300000000000000000000000000000000000000000000000000000000a9059cbb0000000000000000000000006a000f20005980200259b80c5102003040001068000000000000000000000000000000000000000000000000016355a3643c10bb000000000000000000000000000001e0000000000000006c00000000000000c876578ecf9a141296ec657847fb45b0585bcda3a600000140006400440000000b00000000000000000000000000000000000000000000000000000000750283bc0000000000000000000000000a32b743316b9ffb44f6da2e26b497e197066f28000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000004200000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000558d2460000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000060000006000240000ff00000300000000000000000000000000000000000000000000000000000000a9059cbb0000000000000000000000006a000f20005980200259b80c510200304000106800000000000000000000000000000000000000000000000000471060eec4e2cd000000000000000000000000000001e0000000000000006c000000000000019076578ecf9a141296ec657847fb45b0585bcda3a600000140006400440000000b00000000000000000000000000000000000000000000000000000000750283bc0000000000000000000000003b3ef4a7c1ac118848777bbe6d7413f41775c5a7000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000004200000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000ab1a48c0000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000060000006000240000ff00000300000000000000000000000000000000000000000000000000000000a9059cbb0000000000000000000000006a000f20005980200259b80c5102003040001068000000000000000000000000000000000000000000000000008e2131839e188d000000000000000000000000000001e0000000000000006c00000000000000c876578ecf9a141296ec657847fb45b0585bcda3a600000140006400440000000b00000000000000000000000000000000000000000000000000000000750283bc0000000000000000000000007f0852cd8380e6cb88e91f817ebc8dc9ac163d93000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000004200000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000558d2460000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000060000006000240000ff00000300000000000000000000000000000000000000000000000000000000a9059cbb0000000000000000000000006a000f20005980200259b80c5102003040001068000000000000000000000000000000000000000000000000004710978c377f0b000000000000000000000000000001e0000000000000006c00000000000000c876578ecf9a141296ec657847fb45b0585bcda3a600000140006400440000000b00000000000000000000000000000000000000000000000000000000750283bc00000000000000000000000083817734f5b62b68985d994b9d8e9364c6c35f60000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000004200000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000558d2460000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000060000006000240000ff00000300000000000000000000000000000000000000000000000000000000a9059cbb0000000000000000000000006a000f20005980200259b80c5102003040001068000000000000000000000000000000000000000000000000004710394b96f114000000000000000000000000000001e0000000000000006c000000000000019076578ecf9a141296ec657847fb45b0585bcda3a600000140006400440000000b00000000000000000000000000000000000000000000000000000000750283bc000000000000000000000000a3f21dd38a0e734cb079a42340c2598f63225b04000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000004200000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000ab1a48c0000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000060000006000240000ff00000300000000000000000000000000000000000000000000000000000000a9059cbb0000000000000000000000006a000f20005980200259b80c5102003040001068000000000000000000000000000000000000000000000000008e2151f810a1a3000000000000000000000000000001e0000000000000006c000000000000019076578ecf9a141296ec657847fb45b0585bcda3a600000140006400440000000b00000000000000000000000000000000000000000000000000000000750283bc00000000000000000000000048bee101ebbd0cdf9ab398e464eae4677317a149000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000004200000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000ab1a48c0000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000060000006000240000ff00000300000000000000000000000000000000000000000000000000000000a9059cbb0000000000000000000000006a000f20005980200259b80c5102003040001068000000000000000000000000000000000000000000000000008e21277768ecf5000000000000000000000000000001e0000000000000006c00000000000000c876578ecf9a141296ec657847fb45b0585bcda3a600000140006400440000000b00000000000000000000000000000000000000000000000000000000750283bc0000000000000000000000008bde8e5e873cd74a3779fc3922a4de4d1f50d0e9000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000004200000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000558d2460000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000060000006000240000ff00000300000000000000000000000000000000000000000000000000000000a9059cbb0000000000000000000000006a000f20005980200259b80c51020030400010680000000000000000000000000000000000000000000000000047116e6feee51a000000000000000000000000000001e0000000000000006c00000000000000c876578ecf9a141296ec657847fb45b0585bcda3a600000140006400440000000b00000000000000000000000000000000000000000000000000000000750283bc0000000000000000000000008c644e586252fc0f77bf933bb3e2ca3a59a24a4e000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000004200000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000558d2460000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000060000006000240000ff00000300000000000000000000000000000000000000000000000000000000a9059cbb0000000000000000000000006a000f20005980200259b80c5102003040001068000000000000000000000000000000000000000000000000004710c0c54b650500000000000000000000000000000160000000000000012000000000000018381b81d678ffb9c0263b24a97847620c99d213eb1400000140008400000000000300000000000000000000000000000000000000000000000000000000c04b8d59000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000006a000f20005980200259b80c51020030400010680000000000000000000000000000000000000000000000000000000068b9ce8c00000000000000000000000000000000000000000000000000000000a5c176760000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002b833589fcd6edb6e08f4c7c32d4f71b54bda02913000064420000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000000000160000000000000012000000000000000c8aee2b8d4a154e36f479daece3fb3e6c3c03d396e00000140008400000000000300000000000000000000000000000000000000000000000000000000c04b8d59000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000006a000f20005980200259b80c51020030400010680000000000000000000000000000000000000000000000000000000068b9ce8c000000000000000000000000000000000000000000000000000000000558d2460000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002b833589fcd6edb6e08f4c7c32d4f71b54bda029130000644200000000000000000000000000000000000006000000000000000000000000000000000000000000";
        uint256 collateralReceivedFromDebtSwap = 0.994467364480142211 ether;

        // The swap results in less collateral than required to get the flash loaned debt amount from a LM deposit, so the debt amount flash loaned
        // needs to be reduced. We reduce it by the percentage delta between the required collateral and the collateral received from the swap
        uint256 deltaPercentage = collateralReceivedFromDebtSwap * 1e18 / (collateralToAdd - collateralFromSender);
        assertEq(deltaPercentage, 0.994467364480142211e18);
        uint256 flashLoanAmountReduced = flashLoanAmount * deltaPercentage / 1e18;
        assertEq(flashLoanAmountReduced, 4460.538065e6);

        // New calldata for swap of ~4460 USDC
        sellCalldata =
            hex"e3ead59e00000000000000000000000000c600b30fb0400701010f4b080409018b9006e0000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000042000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000109de68d10000000000000000000000000000000000000000000000000da5db3ee42aa8790000000000000000000000000000000000000000000000000dc925dd438fefff2e78ee926cf54002af55e40f3119775300000000000000000000000002131d490000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000074000000000000000000000000000000160000000000000012000000000000000c81b2b6ce813b99b840fe632c63bca5394938ef01e00000140008400000000000300000000000000000000000000000000000000000000000000000000c04b8d59000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000006a000f20005980200259b80c51020030400010680000000000000000000000000000000000000000000000000000000068b9d1f60000000000000000000000000000000000000000000000000000000005513f8a0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002b833589fcd6edb6e08f4c7c32d4f71b54bda029130000014200000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000001e0000000000000006c00000000000000c876578ecf9a141296ec657847fb45b0585bcda3a600000140006400440000000b00000000000000000000000000000000000000000000000000000000750283bc0000000000000000000000003b3ef4a7c1ac118848777bbe6d7413f41775c5a7000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000042000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000005513f890000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000060000006000240000ff00000300000000000000000000000000000000000000000000000000000000a9059cbb0000000000000000000000006a000f20005980200259b80c51020030400010680000000000000000000000000000000000000000000000000046953b1a01c15d000000000000000000000000000001e0000000000000006c00000000000000c876578ecf9a141296ec657847fb45b0585bcda3a600000140006400440000000b00000000000000000000000000000000000000000000000000000000750283bc0000000000000000000000007f0852cd8380e6cb88e91f817ebc8dc9ac163d93000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000042000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000005513f890000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000060000006000240000ff00000300000000000000000000000000000000000000000000000000000000a9059cbb0000000000000000000000006a000f20005980200259b80c5102003040001068000000000000000000000000000000000000000000000000004694ec3558f39100000000000000000000000000000160000000000000012000000000000024b81b81d678ffb9c0263b24a97847620c99d213eb1400000140008400000000000300000000000000000000000000000000000000000000000000000000c04b8d59000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000006a000f20005980200259b80c51020030400010680000000000000000000000000000000000000000000000000000000068b9d1f600000000000000000000000000000000000000000000000000000000f9eaaa350000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002b833589fcd6edb6e08f4c7c32d4f71b54bda029130000644200000000000000000000000000000000000006000000000000000000000000000000000000000000";
        // Updated collateral received from the debt swap for lower debt amount
        collateralReceivedFromDebtSwap = 0.99336682506341171 ether;

        // Preview again using the total collateral. This is used by the LM deposit logic
        uint256 totalCollateral = collateralFromSender + collateralReceivedFromDebtSwap;
        ActionData memory previewData = leverageManager.previewDeposit(leverageToken, totalCollateral);
        assertGe(previewData.debt, flashLoanAmountReduced);
        assertEq(previewData.debt, 4470.477825e6);

        // More than minShares (1% slippage) will be minted
        assertGe(previewData.shares, minShares);
        assertEq(previewData.shares, 0.996683412531705855 ether);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
        // Approve Velora to spend the USDC for the swap
        calls[0] = ILeverageRouter.Call({
            target: address(USDC),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(AUGUSTUS_V6_2), flashLoanAmountReduced),
            value: 0
        });
        // Swap USDC to WETH
        calls[1] = ILeverageRouter.Call({target: AUGUSTUS_V6_2, data: sellCalldata, value: 0});

        _dealAndDeposit(
            WETH, USDC, userBalanceOfCollateralAsset, collateralFromSender, flashLoanAmountReduced, minShares, calls
        );

        // Collateral is taken from the user for the deposit. All of the collateral should be used
        assertEq(WETH.balanceOf(user), userBalanceOfCollateralAsset - collateralFromSender);

        // Any additional debt that is not used to repay the flash loan is given to the user
        uint256 excessDebt = previewData.debt - flashLoanAmountReduced;
        assertEq(USDC.balanceOf(user), excessDebt);
        assertEq(USDC.balanceOf(user), 9.93976e6);

        assertGe(leverageToken.balanceOf(user), minShares);

        assertEq(morphoLendingAdapter.getCollateral(), totalCollateral);
        assertEq(morphoLendingAdapter.getDebt(), previewData.debt + 1); // + 1 because of rounding up by MorphoBalancesLib.expectedBorrowAssets
    }

    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_deposit_UniswapV2_FirstDeposit() public {
        uint256 collateralFromSender = 1 ether;
        uint256 collateralToAdd = 2 * collateralFromSender;
        uint256 userBalanceOfCollateralAsset = 4 ether; // User has more than enough assets for the mint of equity
        uint256 flashLoanAmount = 3392.292471e6; // 3392.292471 USDC
        uint256 minShares = 1 ether * 0.99e18 / 1e18; // 1% slippage
        uint256 collateralReceivedFromDebtSwap = 0.997140594716559346 ether; // Swap of 3392.292471 USDC

        {
            // Sanity check that LR preview deposit matches test params
            ActionData memory leverageRouterPreview = leverageRouter.previewDeposit(leverageToken, collateralFromSender);
            assertEq(leverageRouterPreview.debt, flashLoanAmount);
            assertEq(leverageRouterPreview.shares, 1 ether);
            assertEq(leverageRouterPreview.collateral, collateralToAdd);
            assertEq(leverageRouterPreview.tokenFee, 0);
            assertEq(leverageRouterPreview.treasuryFee, 0);
        }

        // The swap results in less collateral than required to get the flash loaned debt amount from a LM deposit, so the debt amount flash loaned
        // needs to be reduced. We reduce it by the percentage delta between the required collateral and the collateral received from the swap
        uint256 deltaPercentage = collateralReceivedFromDebtSwap * 1e18 / (collateralToAdd - collateralFromSender);
        assertEq(deltaPercentage, 0.997140594716559346e18);
        uint256 flashLoanAmountReduced = flashLoanAmount * deltaPercentage / 1e18;
        assertEq(flashLoanAmountReduced, 3382.592531e6);

        // Updated collateral received from the debt swap for lower debt amount
        collateralReceivedFromDebtSwap = 0.994290732650270211 ether;

        // Preview again using the total collateral. This is used by the LM deposit logic
        uint256 totalCollateral = collateralFromSender + collateralReceivedFromDebtSwap;
        assertEq(totalCollateral, 1.994290732650270211 ether);
        ActionData memory previewData = leverageManager.previewDeposit(leverageToken, totalCollateral);
        assertGe(previewData.debt, flashLoanAmountReduced);
        assertEq(previewData.debt, 3382.608719e6);

        // More than minShares (1% slippage) will be minted
        assertGe(previewData.shares, minShares);
        assertEq(previewData.shares, 0.997145366325135105 ether);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
        // Approve UniswapV2 to spend the USDC for the swap
        calls[0] = ILeverageRouter.Call({
            target: address(USDC),
            data: abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V2_ROUTER02, flashLoanAmountReduced),
            value: 0
        });
        // Swap USDC to WETH
        calls[1] = ILeverageRouter.Call({
            target: UNISWAP_V2_ROUTER02,
            data: abi.encodeWithSelector(
                IUniswapV2Router02.swapExactTokensForTokens.selector,
                flashLoanAmountReduced,
                0,
                path,
                address(leverageRouter),
                block.timestamp
            ),
            value: 0
        });

        _dealAndDeposit(
            WETH, USDC, userBalanceOfCollateralAsset, collateralFromSender, flashLoanAmountReduced, minShares, calls
        );

        // Collateral is taken from the user for the deposit. All of the collateral should be used
        assertEq(WETH.balanceOf(user), userBalanceOfCollateralAsset - collateralFromSender);

        // Any additional debt that is not used to repay the flash loan is given to the user
        uint256 excessDebt = previewData.debt - flashLoanAmountReduced;
        assertEq(USDC.balanceOf(user), excessDebt);
        assertEq(USDC.balanceOf(user), 0.016188e6);

        assertGe(leverageToken.balanceOf(user), minShares);

        assertEq(morphoLendingAdapter.getCollateral(), totalCollateral);
        assertEq(morphoLendingAdapter.getDebt(), previewData.debt + 1); // + 1 because of rounding up by MorphoBalancesLib.expectedBorrowAssets
    }

    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_deposit_UniswapV2_MultipleDeposits() public {
        // Params from testFork_deposit_UniswapV2_FirstDeposit
        uint256 userBalanceOfCollateralAsset = 4 ether;
        uint256 collateralFromSender = 1 ether;
        uint256 flashLoanAmount = 3382.592531e6;
        uint256 minShares = 0.99 ether;

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
        // Approve UniswapV2 to spend the USDC for the swap
        calls[0] = ILeverageRouter.Call({
            target: address(USDC),
            data: abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V2_ROUTER02, flashLoanAmount),
            value: 0
        });
        // Swap USDC to WETH
        calls[1] = ILeverageRouter.Call({
            target: UNISWAP_V2_ROUTER02,
            data: abi.encodeWithSelector(
                IUniswapV2Router02.swapExactTokensForTokens.selector,
                flashLoanAmount,
                0,
                path,
                address(leverageRouter),
                block.timestamp
            ),
            value: 0
        });

        _dealAndDeposit(
            WETH, USDC, userBalanceOfCollateralAsset, collateralFromSender, flashLoanAmount, minShares, calls
        );

        uint256 expectedUserDebtBalance = 0.016188e6;
        assertEq(USDC.balanceOf(user), expectedUserDebtBalance);

        {
            ActionData memory previewDataFullDeposit =
                leverageRouter.previewDeposit(leverageToken, collateralFromSender);
            uint256 collateralReceivedFromDebtSwap = 0.993336131989824069 ether;

            // The swap results in less collateral than required to get the flash loaned debt amount from a LM deposit, so the debt amount flash loaned
            // needs to be reduced. We reduce it by the percentage delta between the required collateral and the collateral received from the swap
            uint256 deltaPercentage =
                collateralReceivedFromDebtSwap * 1e18 / (previewDataFullDeposit.collateral - collateralFromSender);
            assertEq(deltaPercentage, 0.993336131402504508e18);
            uint256 flashLoanAmountReduced = previewDataFullDeposit.debt * deltaPercentage / 1e18;
            assertEq(flashLoanAmountReduced, 3369.686681e6);

            // Update for debtReduced
            collateralReceivedFromDebtSwap = 0.989547994451029601 ether;

            // Preview again using the total collateral. This is used by the LR deposit logic
            uint256 totalCollateral = collateralFromSender + collateralReceivedFromDebtSwap;
            assertEq(totalCollateral, 1.989547994451029601 ether);
            ActionData memory previewDataReducedDeposit = leverageManager.previewDeposit(leverageToken, totalCollateral);
            assertGe(previewDataReducedDeposit.debt, flashLoanAmountReduced);
            assertEq(previewDataReducedDeposit.debt, 3374.564342e6);

            // More than minShares (1% slippage) will be minted
            assertGe(previewDataReducedDeposit.shares, minShares);
            assertEq(previewDataReducedDeposit.shares, 0.9947739972255148 ether);

            calls[0] = ILeverageRouter.Call({
                target: address(USDC),
                data: abi.encodeWithSelector(IERC20.approve.selector, address(UNISWAP_V2_ROUTER02), flashLoanAmountReduced),
                value: 0
            });
            calls[1] = ILeverageRouter.Call({
                target: UNISWAP_V2_ROUTER02,
                data: abi.encodeWithSelector(
                    IUniswapV2Router02.swapExactTokensForTokens.selector,
                    flashLoanAmountReduced,
                    0,
                    path,
                    address(leverageRouter),
                    block.timestamp
                ),
                value: 0
            });

            // Reverts due to 1 debt asset left over in the LR.
            _dealAndDeposit(
                WETH,
                USDC,
                userBalanceOfCollateralAsset,
                collateralFromSender,
                flashLoanAmountReduced,
                previewDataReducedDeposit.shares,
                calls
            );

            // Any additional debt that is not used to repay the flash loan is given to the user
            uint256 surplusDebtFromDeposit = previewDataReducedDeposit.debt - flashLoanAmountReduced;
            assertEq(surplusDebtFromDeposit, 4.877661e6);
            expectedUserDebtBalance += surplusDebtFromDeposit;
            assertEq(USDC.balanceOf(user), expectedUserDebtBalance);
        }

        {
            ActionData memory previewDataFullDeposit =
                leverageRouter.previewDeposit(leverageToken, collateralFromSender);
            uint256 collateralReceivedFromDebtSwap = 0.995230946229750636 ether;

            // The swap results in less collateral than required to get the flash loaned debt amount from a LM deposit, so the debt amount flash loaned
            // needs to be reduced. We reduce it by the percentage delta between the required collateral and the collateral received from the swap
            uint256 deltaPercentage =
                collateralReceivedFromDebtSwap * 1e18 / (previewDataFullDeposit.collateral - collateralFromSender);
            assertEq(deltaPercentage, 0.995230945787895318e18);
            uint256 flashLoanAmountReduced = previewDataFullDeposit.debt * deltaPercentage / 1e18;
            assertEq(flashLoanAmountReduced, 3376.114445e6);

            // Update for debtReduced
            collateralReceivedFromDebtSwap = 0.9904869053653832 ether;

            // Preview again using the total collateral. This is used by the LR deposit logic
            uint256 totalCollateral = collateralFromSender + collateralReceivedFromDebtSwap;
            assertEq(totalCollateral, 1.9904869053653832 ether);
            ActionData memory previewDataReducedDeposit = leverageManager.previewDeposit(leverageToken, totalCollateral);
            assertGe(previewDataReducedDeposit.debt, flashLoanAmountReduced);
            assertEq(previewDataReducedDeposit.debt, 3376.156872e6);

            // More than minShares (1% slippage) will be minted
            assertGe(previewDataReducedDeposit.shares, minShares);
            assertEq(previewDataReducedDeposit.shares, 0.995243452682691599 ether);

            calls[0] = ILeverageRouter.Call({
                target: address(USDC),
                data: abi.encodeWithSelector(IERC20.approve.selector, address(UNISWAP_V2_ROUTER02), flashLoanAmountReduced),
                value: 0
            });
            calls[1] = ILeverageRouter.Call({
                target: UNISWAP_V2_ROUTER02,
                data: abi.encodeWithSelector(
                    IUniswapV2Router02.swapExactTokensForTokens.selector,
                    flashLoanAmountReduced,
                    0,
                    path,
                    address(leverageRouter),
                    block.timestamp
                ),
                value: 0
            });

            _dealAndDeposit(
                WETH,
                USDC,
                userBalanceOfCollateralAsset,
                collateralFromSender,
                flashLoanAmountReduced,
                previewDataReducedDeposit.shares,
                calls
            );

            // Any additional debt that is not used to repay the flash loan is given to the user
            uint256 surplusDebtFromDeposit = previewDataReducedDeposit.debt - flashLoanAmountReduced;
            assertEq(surplusDebtFromDeposit, 0.042427e6);
            expectedUserDebtBalance += surplusDebtFromDeposit;
            assertEq(USDC.balanceOf(user), expectedUserDebtBalance);
        }

        {
            ActionData memory previewDataFullDeposit =
                leverageRouter.previewDeposit(leverageToken, collateralFromSender);
            uint256 collateralReceivedFromDebtSwap = 0.9942781864904543 ether;

            // The swap results in less collateral than required to get the flash loaned debt amount from a LM deposit, so the debt amount flash loaned
            // needs to be reduced. We reduce it by the percentage delta between the required collateral and the collateral received from the swap
            uint256 deltaPercentage =
                collateralReceivedFromDebtSwap * 1e18 / (previewDataFullDeposit.collateral - collateralFromSender);
            assertEq(deltaPercentage, 0.994278186196095526e18);
            uint256 flashLoanAmountReduced = previewDataFullDeposit.debt * deltaPercentage / 1e18;
            assertEq(flashLoanAmountReduced, 3372.882406e6);

            // Update for debtReduced
            collateralReceivedFromDebtSwap = 0.988591828264731799 ether;

            // Preview again using the total collateral. This is used by the LR deposit logic
            uint256 totalCollateral = collateralFromSender + collateralReceivedFromDebtSwap;
            assertEq(totalCollateral, 1.988591828264731799 ether);
            ActionData memory previewDataReducedDeposit = leverageManager.previewDeposit(leverageToken, totalCollateral);
            assertGe(previewDataReducedDeposit.debt, flashLoanAmountReduced);
            assertEq(previewDataReducedDeposit.debt, 3372.942544e6);

            // More than minShares (1% slippage) will be minted
            assertGe(previewDataReducedDeposit.shares, minShares);
            assertEq(previewDataReducedDeposit.shares, 0.994295914132365898 ether);

            calls[0] = ILeverageRouter.Call({
                target: address(USDC),
                data: abi.encodeWithSelector(IERC20.approve.selector, address(UNISWAP_V2_ROUTER02), flashLoanAmountReduced),
                value: 0
            });
            calls[1] = ILeverageRouter.Call({
                target: UNISWAP_V2_ROUTER02,
                data: abi.encodeWithSelector(
                    IUniswapV2Router02.swapExactTokensForTokens.selector,
                    flashLoanAmountReduced,
                    0,
                    path,
                    address(leverageRouter),
                    block.timestamp
                ),
                value: 0
            });

            _dealAndDeposit(
                WETH,
                USDC,
                userBalanceOfCollateralAsset,
                collateralFromSender,
                flashLoanAmountReduced,
                previewDataReducedDeposit.shares,
                calls
            );

            // Any additional debt that is not used to repay the flash loan is given to the user
            uint256 surplusDebtFromDeposit = previewDataReducedDeposit.debt - flashLoanAmountReduced;
            assertEq(surplusDebtFromDeposit, 0.060138e6);
            expectedUserDebtBalance += surplusDebtFromDeposit;
            assertEq(USDC.balanceOf(user), expectedUserDebtBalance);
        }
    }

    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testForkFuzz_deposit_MultipleDeposits_MockedSwap_CollateralDecimalsGtDebtDecimals(
        uint256 collateralFromSenderA,
        uint256 collateralReceivedFromDebtSwapA,
        uint256 collateralFromSenderB,
        uint256 collateralReceivedFromDebtSwapB,
        uint256 collateralFromSenderC,
        uint256 collateralReceivedFromDebtSwapC
    ) public {
        collateralFromSenderA = bound(collateralFromSenderA, 1, 1000 ether);
        collateralFromSenderB = bound(collateralFromSenderB, 1, 1000 ether);
        collateralFromSenderC = bound(collateralFromSenderC, 1, 1000 ether);

        _supplyUSDCForETHLongLeverageToken(15000000e6);

        ActionData memory previewData = leverageRouter.previewDeposit(leverageToken, collateralFromSenderA);

        collateralReceivedFromDebtSwapA =
            bound(collateralReceivedFromDebtSwapA, 1, previewData.collateral - collateralFromSenderA);

        _depositWithMockedSwap(
            DepositWithMockedSwapParams({
                leverageToken: leverageToken,
                collateralAsset: WETH,
                debtAsset: USDC,
                userBalanceOfCollateralAsset: collateralFromSenderA,
                collateralFromSender: collateralFromSenderA,
                flashLoanAmount: previewData.debt,
                minShares: 0,
                collateralRequired: previewData.collateral,
                collateralReceivedFromDebtSwap: collateralReceivedFromDebtSwapA
            })
        );

        previewData = leverageRouter.previewDeposit(leverageToken, collateralFromSenderB);

        collateralReceivedFromDebtSwapB =
            bound(collateralReceivedFromDebtSwapB, 1, previewData.collateral - collateralFromSenderB);

        _depositWithMockedSwap(
            DepositWithMockedSwapParams({
                leverageToken: leverageToken,
                collateralAsset: WETH,
                debtAsset: USDC,
                userBalanceOfCollateralAsset: collateralFromSenderB,
                collateralFromSender: collateralFromSenderB,
                flashLoanAmount: previewData.debt,
                minShares: 0,
                collateralRequired: previewData.collateral,
                collateralReceivedFromDebtSwap: collateralReceivedFromDebtSwapB
            })
        );

        previewData = leverageRouter.previewDeposit(leverageToken, collateralFromSenderC);

        collateralReceivedFromDebtSwapC =
            bound(collateralReceivedFromDebtSwapC, 1, previewData.collateral - collateralFromSenderC);

        _depositWithMockedSwap(
            DepositWithMockedSwapParams({
                leverageToken: leverageToken,
                collateralAsset: WETH,
                debtAsset: USDC,
                userBalanceOfCollateralAsset: collateralFromSenderC,
                collateralFromSender: collateralFromSenderC,
                flashLoanAmount: previewData.debt,
                minShares: 0,
                collateralRequired: previewData.collateral,
                collateralReceivedFromDebtSwap: collateralReceivedFromDebtSwapC
            })
        );
    }

    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testForkFuzz_deposit_MultipleDeposits_MockedSwap_DebtDecimalsGtCollateralDecimals(
        uint256 collateralFromSenderA,
        uint256 collateralReceivedFromDebtSwapA,
        uint256 collateralFromSenderB,
        uint256 collateralReceivedFromDebtSwapB,
        uint256 collateralFromSenderC,
        uint256 collateralReceivedFromDebtSwapC
    ) public {
        collateralFromSenderA = bound(collateralFromSenderA, 1, 3000000e6);
        collateralFromSenderB = bound(collateralFromSenderB, 1, 3000000e6);
        collateralFromSenderC = bound(collateralFromSenderC, 1, 3000000e6);

        _supplyWETHForETHShortLeverageToken(6000 ether);

        ActionData memory previewData = leverageRouter.previewDeposit(ethShortLeverageToken, collateralFromSenderA);

        collateralReceivedFromDebtSwapA =
            bound(collateralReceivedFromDebtSwapA, 1, previewData.collateral - collateralFromSenderA);

        _depositWithMockedSwap(
            DepositWithMockedSwapParams({
                leverageToken: ethShortLeverageToken,
                collateralAsset: USDC,
                debtAsset: WETH,
                userBalanceOfCollateralAsset: collateralFromSenderA,
                collateralFromSender: collateralFromSenderA,
                flashLoanAmount: previewData.debt,
                minShares: 0,
                collateralRequired: previewData.collateral,
                collateralReceivedFromDebtSwap: collateralReceivedFromDebtSwapA
            })
        );

        previewData = leverageRouter.previewDeposit(ethShortLeverageToken, collateralFromSenderB);

        collateralReceivedFromDebtSwapB =
            bound(collateralReceivedFromDebtSwapB, 1, previewData.collateral - collateralFromSenderB);

        _depositWithMockedSwap(
            DepositWithMockedSwapParams({
                leverageToken: ethShortLeverageToken,
                collateralAsset: USDC,
                debtAsset: WETH,
                userBalanceOfCollateralAsset: collateralFromSenderB,
                collateralFromSender: collateralFromSenderB,
                flashLoanAmount: previewData.debt,
                minShares: 0,
                collateralRequired: previewData.collateral,
                collateralReceivedFromDebtSwap: collateralReceivedFromDebtSwapB
            })
        );

        previewData = leverageRouter.previewDeposit(ethShortLeverageToken, collateralFromSenderC);

        collateralReceivedFromDebtSwapC =
            bound(collateralReceivedFromDebtSwapC, 1, previewData.collateral - collateralFromSenderC);

        _depositWithMockedSwap(
            DepositWithMockedSwapParams({
                leverageToken: ethShortLeverageToken,
                collateralAsset: USDC,
                debtAsset: WETH,
                userBalanceOfCollateralAsset: collateralFromSenderC,
                collateralFromSender: collateralFromSenderC,
                flashLoanAmount: previewData.debt,
                minShares: 0,
                collateralRequired: previewData.collateral,
                collateralReceivedFromDebtSwap: collateralReceivedFromDebtSwapC
            })
        );
    }

    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_deposit_ExceedsSlippage() public {
        uint256 collateralFromSender = 1 ether;
        uint256 collateralToAdd = 2 * collateralFromSender;
        uint256 userBalanceOfCollateralAsset = 4 ether; // User has more than enough assets for the mint of equity
        uint256 flashLoanAmount = 3392.292471e6; // 3392.292471 USDC
        uint256 sharesFromDeposit = 1 ether;
        uint256 minShares = sharesFromDeposit * 0.99715e18 / 1e18; // 0.285% slippage
        uint256 collateralReceivedFromDebtSwap = 0.997140594716559346 ether; // Swap of 3392.292471 USDC

        {
            // Sanity check that LR preview deposit matches test params
            ActionData memory previewDataFullDeposit =
                leverageRouter.previewDeposit(leverageToken, collateralFromSender);
            assertEq(previewDataFullDeposit.debt, flashLoanAmount);
            assertEq(previewDataFullDeposit.shares, sharesFromDeposit);
            assertEq(previewDataFullDeposit.collateral, collateralToAdd);
            assertEq(previewDataFullDeposit.tokenFee, 0);
            assertEq(previewDataFullDeposit.treasuryFee, 0);
        }

        // The swap results in less collateral than required to get the flash loaned debt amount from a LM deposit, so the debt amount flash loaned
        // needs to be reduced. We reduce it by the percentage delta between the required collateral and the collateral received from the swap
        uint256 deltaPercentage = collateralReceivedFromDebtSwap * 1e18 / (collateralToAdd - collateralFromSender);
        assertEq(deltaPercentage, 0.997140594716559346e18);
        uint256 flashLoanAmountReduced = flashLoanAmount * deltaPercentage / 1e18;
        assertEq(flashLoanAmountReduced, 3382.592531e6);

        // Updated collateral received from the debt swap for lower debt amount
        collateralReceivedFromDebtSwap = 0.994290732650270211 ether;

        // Preview again using the total collateral. This is used by the LM deposit logic
        uint256 totalCollateral = collateralFromSender + collateralReceivedFromDebtSwap;
        assertEq(totalCollateral, 1.994290732650270211 ether);
        ActionData memory previewData = leverageManager.previewDeposit(leverageToken, totalCollateral);
        assertGe(previewData.debt, flashLoanAmountReduced);
        assertEq(previewData.debt, 3382.608719e6);

        // More than minShares (0.285% slippage) will be minted
        assertLt(previewData.shares, minShares);
        assertEq(previewData.shares, 0.997145366325135105 ether);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
        calls[0] = ILeverageRouter.Call({
            target: address(USDC),
            data: abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V2_ROUTER02, flashLoanAmountReduced),
            value: 0
        });
        calls[1] = ILeverageRouter.Call({
            target: UNISWAP_V2_ROUTER02,
            data: abi.encodeWithSelector(
                IUniswapV2Router02.swapExactTokensForTokens.selector,
                flashLoanAmountReduced,
                0,
                path,
                address(leverageRouter),
                block.timestamp
            ),
            value: 0
        });

        deal(address(WETH), user, userBalanceOfCollateralAsset);
        vm.startPrank(user);
        WETH.approve(address(leverageRouter), collateralFromSender);

        vm.expectRevert(
            abi.encodeWithSelector(ILeverageManager.SlippageTooHigh.selector, 0.997145366325135105 ether, 0.99715 ether)
        );
        leverageRouter.deposit(leverageToken, collateralFromSender, flashLoanAmountReduced, minShares, calls);
        vm.stopPrank();
    }

    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_deposit_InsufficientDebtFromDepositToRepayFlashLoan() public {
        uint256 collateralFromSender = 0.01 ether;

        // 2x collateral ratio
        ActionData memory previewData = leverageRouter.previewDeposit(leverageToken, collateralFromSender);
        assertEq(previewData.collateral, collateralFromSender * 2);
        assertEq(previewData.debt, 33.922924e6);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
        calls[0] = ILeverageRouter.Call({
            target: address(USDC),
            data: abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V2_ROUTER02, previewData.debt),
            value: 0
        });
        calls[1] = ILeverageRouter.Call({
            target: UNISWAP_V2_ROUTER02,
            data: abi.encodeWithSelector(
                IUniswapV2Router02.swapExactTokensForTokens.selector,
                previewData.debt,
                0,
                path,
                address(leverageRouter),
                block.timestamp
            ),
            value: 0
        });

        // The collateral received from swapping 33.922924e6 USDC is 0.009976155542446272 WETH in this block using Uniswap V2
        uint256 collateralReceivedFromDebtSwap = 0.009976155542446272 ether;

        // The collateral from the swap + the collateral from the sender is less than the collateral required
        uint256 totalCollateral = collateralReceivedFromDebtSwap + collateralFromSender;
        assertLt(totalCollateral, previewData.collateral);

        deal(address(WETH), user, collateralFromSender);
        vm.startPrank(user);
        WETH.approve(address(leverageRouter), collateralFromSender);

        // Reverts when morpho attempts to pull assets to repay the flash loan. The debt amount returned from the deposit is too
        // low because the collateral from the swap + the collateral from the sender is less than the collateral required.
        vm.expectRevert("transferFrom reverted"); // Thrown by morpho
        leverageRouter.deposit(leverageToken, collateralFromSender, previewData.debt, 0, calls);
        vm.stopPrank();
    }

    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_deposit_UniswapV3() public {
        uint256 collateralFromSender = 1 ether;
        uint256 collateralToAdd = 2 * collateralFromSender;
        uint256 flashLoanAmount = 3392.292471e6; // 3392.292471 USDC
        uint256 minShares = 1 ether * 0.99e18 / 1e18; // 1% slippage
        uint256 collateralReceivedFromDebtSwap = 0.999899417781964728 ether; // Swap of 3392.292471 USDC

        {
            // Sanity check that LR preview deposit matches test params
            ActionData memory previewDataFullDeposit =
                leverageRouter.previewDeposit(leverageToken, collateralFromSender);
            assertEq(previewDataFullDeposit.debt, flashLoanAmount);
            assertEq(previewDataFullDeposit.shares, 1 ether);
            assertEq(previewDataFullDeposit.collateral, collateralToAdd);
            assertEq(previewDataFullDeposit.tokenFee, 0);
            assertEq(previewDataFullDeposit.treasuryFee, 0);
        }

        // The swap results in less collateral than required to get the flash loaned debt amount from a LM deposit, so the debt amount flash loaned
        // needs to be reduced. We reduce it by the percentage delta between the required collateral and the collateral received from the swap
        uint256 deltaPercentage = collateralReceivedFromDebtSwap * 1e18 / (collateralToAdd - collateralFromSender);
        assertEq(deltaPercentage, 0.999899417781964728e18);
        uint256 flashLoanAmountReduced = flashLoanAmount * deltaPercentage / 1e18;
        assertEq(flashLoanAmountReduced, 3391.951266e6);

        // Updated collateral received from the debt swap for lower debt amount
        collateralReceivedFromDebtSwap = 0.999798847238411671 ether;

        // Preview again using the total collateral. This is used by the LM deposit logic
        uint256 totalCollateral = collateralFromSender + collateralReceivedFromDebtSwap;
        assertEq(totalCollateral, 1.999798847238411671 ether);
        ActionData memory previewData = leverageManager.previewDeposit(leverageToken, totalCollateral);
        assertGe(previewData.debt, flashLoanAmountReduced);
        assertEq(previewData.debt, 3391.951287e6);

        // More than minShares (1% slippage) will be minted
        assertGe(previewData.shares, minShares);
        assertEq(previewData.shares, 0.999899423619205835 ether);

        IUniswapSwapRouter02.ExactInputSingleParams memory params = IUniswapSwapRouter02.ExactInputSingleParams({
            tokenIn: address(USDC),
            tokenOut: address(WETH),
            fee: 500,
            recipient: address(leverageRouter),
            amountIn: flashLoanAmountReduced,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);

        calls[0] = ILeverageRouter.Call({
            target: address(USDC),
            data: abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_SWAP_ROUTER02, flashLoanAmountReduced),
            value: 0
        });
        calls[1] = ILeverageRouter.Call({
            target: UNISWAP_SWAP_ROUTER02,
            data: abi.encodeWithSelector(IUniswapSwapRouter02.exactInputSingle.selector, params),
            value: 0
        });

        _dealAndDeposit(
            WETH, USDC, collateralFromSender, collateralFromSender, flashLoanAmountReduced, minShares, calls
        );

        // Collateral is taken from the user for the deposit. All of the collateral should be used
        assertEq(WETH.balanceOf(user), 0);

        // Any additional debt that is not used to repay the flash loan is given to the user
        uint256 excessDebt = previewData.debt - flashLoanAmountReduced;
        assertEq(USDC.balanceOf(user), excessDebt);
        assertEq(USDC.balanceOf(user), 0.000021e6);

        assertGe(leverageToken.balanceOf(user), minShares);

        assertEq(morphoLendingAdapter.getCollateral(), totalCollateral);
        assertEq(morphoLendingAdapter.getDebt(), previewData.debt + 1); // + 1 because of rounding up by MorphoBalancesLib.expectedBorrowAssets
    }

    function _depositWithMockedSwap(DepositWithMockedSwapParams memory params) internal {
        uint256 collateralToAdd =
            leverageRouter.previewDeposit(params.leverageToken, params.collateralFromSender).collateral;

        uint256 flashLoanAmountReduced = params.flashLoanAmount;
        if (params.collateralReceivedFromDebtSwap < collateralToAdd - params.collateralFromSender) {
            // The swap results in less collateral than required to get the flash loaned debt amount from a LM deposit, so the debt amount flash loaned
            // needs to be reduced. We reduce it by the percentage delta between the required collateral and the collateral received from the swap
            uint256 deltaPercentage =
                params.collateralReceivedFromDebtSwap * 1e18 / (collateralToAdd - params.collateralFromSender);
            flashLoanAmountReduced = params.flashLoanAmount * deltaPercentage / 1e18;
        }

        if (flashLoanAmountReduced == 0) {
            return;
        }

        // Mock the swap of the debt asset to the collateral asset to be the required amount
        uint256 collateralReceivedFromReducedDebtSwap = params.collateralRequired > params.collateralFromSender
            ? params.collateralRequired - params.collateralFromSender
            : 0;

        // The entire amount of collateral is used for the deposit
        uint256 collateralUsedForDeposit = params.collateralFromSender + collateralReceivedFromReducedDebtSwap;
        uint256 debtFromDeposit = leverageManager.previewDeposit(params.leverageToken, collateralUsedForDeposit).debt;

        mockSwapper.mockNextExactInputSwap(
            params.debtAsset, params.collateralAsset, collateralReceivedFromReducedDebtSwap
        );

        {
            ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
            calls[0] = ILeverageRouter.Call({
                target: address(params.debtAsset),
                data: abi.encodeWithSelector(IERC20.approve.selector, address(mockSwapper), flashLoanAmountReduced),
                value: 0
            });
            calls[1] = ILeverageRouter.Call({
                target: address(mockSwapper),
                data: abi.encodeWithSelector(MockSwapper.swapExactInput.selector, params.debtAsset, flashLoanAmountReduced),
                value: 0
            });

            deal(address(params.collateralAsset), user, params.userBalanceOfCollateralAsset);

            vm.startPrank(user);
            params.collateralAsset.approve(address(leverageRouter), params.collateralFromSender);
            leverageRouter.deposit(
                params.leverageToken, params.collateralFromSender, flashLoanAmountReduced, params.minShares, calls
            );
            vm.stopPrank();
        }

        // No leftover assets in the LR
        assertEq(params.collateralAsset.balanceOf(address(leverageRouter)), 0);
        assertEq(params.debtAsset.balanceOf(address(leverageRouter)), 0);

        // Collateral is taken from the user for the deposit. All of the collateral should be used
        assertEq(params.collateralAsset.balanceOf(user), 0);

        // Any additional debt that is not used to repay the flash loan is given to the user
        uint256 excessDebt = debtFromDeposit - flashLoanAmountReduced;
        assertEq(params.debtAsset.balanceOf(user), excessDebt);
        // Transfer any excess debt away for multiple uses/iterations of the user debt balance assertion above within a single test
        if (excessDebt > 0) {
            vm.prank(user);
            params.debtAsset.transfer(address(this), excessDebt);
        }
    }

    function _supplyWETHForETHShortLeverageToken(uint256 amount) internal {
        deal(address(WETH), address(this), amount);
        IMorpho morpho = IMorpho(ethShortLendingAdapter.morpho());

        (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) =
            ethShortLendingAdapter.marketParams();
        MarketParams memory marketParams =
            MarketParams({loanToken: loanToken, collateralToken: collateralToken, oracle: oracle, irm: irm, lltv: lltv});

        WETH.approve(address(morpho), amount);
        morpho.supply(marketParams, amount, 0, address(this), new bytes(0));
    }

    function _supplyUSDCForETHLongLeverageToken(uint256 amount) internal {
        deal(address(USDC), address(this), amount);
        IMorpho morpho = IMorpho(morphoLendingAdapter.morpho());

        (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) =
            morphoLendingAdapter.marketParams();
        MarketParams memory marketParams =
            MarketParams({loanToken: loanToken, collateralToken: collateralToken, oracle: oracle, irm: irm, lltv: lltv});

        USDC.approve(address(morpho), amount);
        morpho.supply(marketParams, amount, 0, address(morphoLendingAdapter), new bytes(0));
    }
}
