// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ILeverageRouter} from "src/interfaces/periphery/ILeverageRouter.sol";
import {IUniswapV2Router02} from "src/interfaces/periphery/IUniswapV2Router02.sol";
import {IVeloraAdapter} from "src/interfaces/periphery/IVeloraAdapter.sol";
import {ActionData} from "src/types/DataTypes.sol";
import {LeverageRouterTest} from "./LeverageRouter.t.sol";

contract LeverageRouterRedeemWithVeloraTest is LeverageRouterTest {
    // Receiver on calldata is the VeloraAdapter
    bytes buyCalldata =
        hex"7f4576750000000000000000000000000e5891850bb3f03090f03010000806f0800401000000000000000000000000004200000000000000000000000000000000000006000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000000000000000000000000000000f444eb515574a3f000000000000000000000000000000000000000000000000000000012a05f2000000000000000000000000000000000000000000000000000f444eb515574a3fa57d3b88a3424bea891a5a34e2de84b90000000000000000000000000211d2ba000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ac000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000ae00000016000000000000000000000008c000000000000006c000000000000019076578ecf9a141296ec657847fb45b0585bcda3a601400064012500440000000b0000000000000000000000000000000000000000000000000000000094e86ef8000000000000000000000000f3362ff1d2568455885e7735392276b6ca3aae650000000000000000000000004200000000000000000000000000000000000006000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda02913000000000000000000000000000000000000000000000000000000000bebc200ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000016000000000000000000000008c000000000000006c000000000000019076578ecf9a141296ec657847fb45b0585bcda3a601400064012500440000000b0000000000000000000000000000000000000000000000000000000094e86ef800000000000000000000000083817734f5b62b68985d994b9d8e9364c6c35f600000000000000000000000004200000000000000000000000000000000000006000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda02913000000000000000000000000000000000000000000000000000000000bebc200ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000016000000000000000000000008c000000000000006c00000000000000c876578ecf9a141296ec657847fb45b0585bcda3a601400064012500440000000b0000000000000000000000000000000000000000000000000000000094e86ef8000000000000000000000000a3f21dd38a0e734cb079a42340c2598f63225b040000000000000000000000004200000000000000000000000000000000000006000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000000000000000000000000000000000000005f5e100ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000016000000000000000000000008c000000000000006c00000000000000c876578ecf9a141296ec657847fb45b0585bcda3a601400064012500440000000b0000000000000000000000000000000000000000000000000000000094e86ef8000000000000000000000000b4d2d1f24064f21531eee256c42a1dfa98214e740000000000000000000000004200000000000000000000000000000000000006000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000000000000000000000000000000000000005f5e100ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000160000000000000000000000120000000000000013700000000000017701b2b6ce813b99b840fe632c63bca5394938ef01e0140008400a400d80000000b00000000000000000000000000000000000000000000000000000000f28c0498000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000e5891850bb3f03090f03010000806f0800401000000000000000000000000000000000000000000000000000000000068b73cd700000000000000000000000000000000000000000000000000000000b2d05e00000000000000000000000000000000000000000000000000092914ef75a88cf4000000000000000000000000000000000000000000000000000000000000002b833589fcd6edb6e08f4c7c32d4f71b54bda02913000064420000000000000000000000000000000000000600000000000000000000000000000000000000000000000160000000000000000000000120000000000000013700000000000009601b81d678ffb9c0263b24a97847620c99d213eb140140008400a400d80000000b00000000000000000000000000000000000000000000000000000000f28c0498000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000e5891850bb3f03090f03010000806f0800401000000000000000000000000000000000000000000000000000000000068b73cd70000000000000000000000000000000000000000000000000000000047868c0000000000000000000000000000000000000000000000000003aa050cba9caf08000000000000000000000000000000000000000000000000000000000000002b833589fcd6edb6e08f4c7c32d4f71b54bda0291300006442000000000000000000000000000000000000060000000000000000000000000000000000000000000000016000000000000000000000012000000000000001370000000000000190aee2b8d4a154e36f479daece3fb3e6c3c03d396e0140008400a400d80000000b00000000000000000000000000000000000000000000000000000000f28c0498000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000e5891850bb3f03090f03010000806f0800401000000000000000000000000000000000000000000000000000000000068b73cd7000000000000000000000000000000000000000000000000000000000bebc200000000000000000000000000000000000000000000000000009c545e6726a8e4000000000000000000000000000000000000000000000000000000000000002b833589fcd6edb6e08f4c7c32d4f71b54bda029130000644200000000000000000000000000000000000006000000000000000000000000000000000000000000";
    uint256 outputAmount = 5000e6;
    uint256 outputAmountOffset = 132;
    uint256 maxInputAmountOffset = 100;
    uint256 quotedInputAmountOffset = 164;
    uint256 expectedInputAmount = 1.100090748639332927 ether;

    function setUp() public override {
        super.setUp();

        // Update the forked block to 34722490
        vm.rollFork(34722490);
    }

    function testFork_redeemWithVelora_FullRedeem() public {
        uint256 shares = _deposit();

        // Preview the redemption of shares
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, shares);
        assertEq(previewData.debt, 4549.699882e6);
        assertEq(previewData.collateral, 2 ether);

        // Calculate the share value in collateral asset
        uint256 shareValueInCollateralAsset = shares
            * leverageManager.getLeverageTokenLendingAdapter(leverageToken).getEquityInCollateralAsset()
            / leverageManager.getFeeAdjustedTotalSupply(leverageToken);

        uint256 collateralUsedForDebtSwap = 1.001016549854732935 ether; // Result of the swap of 4549.699882 USDC to WETH on this block using the Velora calldata
        uint256 expectedCollateralForSender = previewData.collateral - collateralUsedForDebtSwap;
        assertEq(expectedCollateralForSender, 0.998983450145267065 ether);

        uint256 diffSlippage = 1e18 - (expectedCollateralForSender * 1e18 / shareValueInCollateralAsset);
        assertLt(diffSlippage, 0.01e18);
        assertEq(diffSlippage, 0.001016549752516905e18); // ~0.1% slippage using Velora for the swap

        _redeemAndAssertBalances(
            shares,
            expectedCollateralForSender,
            IVeloraAdapter.Offsets(outputAmountOffset, maxInputAmountOffset, quotedInputAmountOffset),
            buyCalldata
        );
    }

    function testFork_redeemWithVelora_PartialRedeem() public {
        uint256 shares = _deposit();

        uint256 sharesToRedeem = shares / 2;

        // Preview the redemption of shares
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, sharesToRedeem);
        assertEq(previewData.debt, 2274.849941e6);
        assertEq(previewData.collateral, 1 ether);

        uint256 shareValueInCollateralAsset = sharesToRedeem
            * leverageManager.getLeverageTokenLendingAdapter(leverageToken).getEquityInCollateralAsset()
            / leverageManager.getFeeAdjustedTotalSupply(leverageToken);

        uint256 collateralUsedForDebtSwap = 0.500508274927366467 ether; // Result of the swap of 2274.849941 USDC to WETH on this block using the Velora calldata
        uint256 expectedCollateralForSender = previewData.collateral - collateralUsedForDebtSwap;
        assertEq(expectedCollateralForSender, 0.499491725072633533 ether);

        uint256 diffSlippage = 1e18 - (expectedCollateralForSender * 1e18 / shareValueInCollateralAsset);
        assertLt(diffSlippage, 0.01e18);
        assertEq(diffSlippage, 0.001016549752516904e18); // ~0.01% slippage using Velora for the swap

        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(USDC);

        _redeemAndAssertBalances(
            shares / 2,
            expectedCollateralForSender,
            IVeloraAdapter.Offsets(outputAmountOffset, maxInputAmountOffset, quotedInputAmountOffset),
            buyCalldata
        );
    }

    function _deposit() internal returns (uint256 shares) {
        uint256 collateralFromSender = 1 ether;
        uint256 collateralToAdd = 2 * collateralFromSender;
        uint256 debt = 4549.699881e6;
        uint256 userBalanceOfCollateralAssetBefore = 4 ether; // User has more than enough assets for the mint of equity
        uint256 collateralReceivedFromDebtSwap = 0.994842225191851085 ether; // Swap of 4549.699881 USDC results in 0.994842225191851085 WETH

        // The swap results in less collateral than required to repay the flash loan, so the user needs to approve more collateral than `equityInCollateralAsset`
        uint256 additionalCollateralRequired = collateralToAdd - (collateralFromSender + collateralReceivedFromDebtSwap);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        uint256 sharesBefore = leverageToken.balanceOf(user);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);

        // Approve UniswapV2 to spend the USDC for the swap
        calls[0] = ILeverageRouter.Call({
            target: address(USDC),
            data: abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V2_ROUTER02, debt),
            value: 0
        });
        // Swap USDC to WETH
        calls[1] = ILeverageRouter.Call({
            target: UNISWAP_V2_ROUTER02,
            data: abi.encodeWithSelector(
                IUniswapV2Router02.swapExactTokensForTokens.selector,
                debt,
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
            userBalanceOfCollateralAssetBefore,
            collateralFromSender + additionalCollateralRequired,
            debt,
            0,
            calls
        );

        uint256 sharesAfter = leverageToken.balanceOf(user) - sharesBefore;

        return sharesAfter;
    }

    function _redeemAndAssertBalances(
        uint256 shares,
        uint256 minCollateralForSender,
        IVeloraAdapter.Offsets memory offsets,
        bytes memory swapData
    ) internal {
        uint256 collateralBeforeRedeem = morphoLendingAdapter.getCollateral();
        uint256 debtBeforeRedeem = morphoLendingAdapter.getDebt();
        uint256 userBalanceOfCollateralAssetBeforeRedeem = WETH.balanceOf(user);

        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, shares);

        vm.startPrank(user);
        leverageToken.approve(address(leverageRouter), shares);
        leverageRouter.redeemWithVelora(
            leverageToken, shares, minCollateralForSender, veloraAdapter, AUGUSTUS_V6_2, offsets, swapData
        );
        vm.stopPrank();

        // Check that the periphery contracts don't hold any assets
        assertEq(WETH.balanceOf(address(veloraAdapter)), 0);
        assertEq(USDC.balanceOf(address(veloraAdapter)), 0);
        assertEq(WETH.balanceOf(address(leverageRouter)), 0);
        assertEq(USDC.balanceOf(address(leverageRouter)), 0);

        // Collateral and debt are removed from the leverage token
        assertEq(morphoLendingAdapter.getCollateral(), collateralBeforeRedeem - previewData.collateral);
        assertEq(morphoLendingAdapter.getDebt(), debtBeforeRedeem - previewData.debt);

        // The user receives back at least the min collateral and debt
        assertGe(WETH.balanceOf(user), userBalanceOfCollateralAssetBeforeRedeem + minCollateralForSender);
    }
}
