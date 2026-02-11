// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {VeloraAdapterTest} from "./VeloraAdapter.t.sol";
import {IVeloraAdapter} from "src/interfaces/periphery/IVeloraAdapter.sol";

contract BuyTest is VeloraAdapterTest {
    function test_buy_RevertIf_InvalidAugustus(address _augustus) public {
        augustusRegistry.setValid(_augustus, false);

        vm.expectRevert(abi.encodeWithSelector(IVeloraAdapter.InvalidAugustus.selector, _augustus));
        veloraAdapter.buy(
            _augustus,
            new bytes(32),
            address(collateralToken),
            address(debtToken),
            0,
            IVeloraAdapter.Offsets(0, 0, 0),
            address(0)
        );
    }

    function test_buy_RevertIf_InvalidReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IVeloraAdapter.InvalidReceiver.selector, address(0)));
        veloraAdapter.buy(
            address(augustus),
            new bytes(32),
            address(collateralToken),
            address(debtToken),
            1,
            IVeloraAdapter.Offsets(0, 0, 0),
            address(0)
        );

        vm.expectRevert(abi.encodeWithSelector(IVeloraAdapter.InvalidReceiver.selector, address(veloraAdapter)));
        veloraAdapter.buy(
            address(augustus),
            new bytes(32),
            address(collateralToken),
            address(debtToken),
            1,
            IVeloraAdapter.Offsets(0, 0, 0),
            address(veloraAdapter)
        );
    }

    function test_buy_UpdateAmountsBuyWithQuoteUpdate(
        address _augustus,
        uint256 initialExact,
        uint256 initialLimit,
        uint256 initialQuoted,
        uint256 adjustedExact,
        uint256 newLimit,
        uint256 offset
    ) public {
        deal(address(collateralToken), address(veloraAdapter), newLimit); // The new limit is the balance of the adapter
        _updateAmountsBuy(_augustus, initialExact, initialLimit, initialQuoted, adjustedExact, newLimit, offset, true);
    }

    function test_buy_UpdateAmountsBuyNoQuoteUpdate(
        address _augustus,
        uint256 initialExact,
        uint256 initialLimit,
        uint256 initialQuoted,
        uint256 adjustedExact,
        uint256 newLimit,
        uint256 offset
    ) public {
        deal(address(collateralToken), address(veloraAdapter), newLimit); // The new limit is the balance of the adapter
        _updateAmountsBuy(_augustus, initialExact, initialLimit, initialQuoted, adjustedExact, newLimit, offset, false);
    }

    function test_buy_NoAdjustment(uint256 amount, uint256 extra, address receiver) public {
        _receiver(receiver);

        amount = bound(amount, 1, type(uint128).max);
        extra = bound(extra, 0, type(uint128).max);

        deal(address(collateralToken), address(veloraAdapter), amount + extra);
        _buy(address(collateralToken), address(debtToken), amount, amount, 0, receiver, receiver);

        assertEq(collateralToken.balanceOf(receiver), extra, "receiver received excess input token");
        assertEq(debtToken.balanceOf(receiver), amount, "receiver received output token");
        assertEq(collateralToken.balanceOf(address(veloraAdapter)), 0, "velora adapter has no input token");
        assertEq(debtToken.balanceOf(address(veloraAdapter)), 0, "velora adapter has no output token");
    }

    function test_buy_WithAdjustment(uint256 outputAmount, uint256 percent, address receiver) public {
        _receiver(receiver);

        percent = bound(percent, 1, 1000);
        outputAmount = bound(outputAmount, 1, type(uint64).max);
        uint256 actualOutputAmount = Math.mulDiv(outputAmount, percent, 100, Math.Rounding.Ceil);

        deal(address(collateralToken), address(veloraAdapter), actualOutputAmount);
        _buy(
            address(collateralToken),
            address(debtToken),
            outputAmount,
            outputAmount,
            actualOutputAmount,
            receiver,
            receiver
        );

        assertEq(collateralToken.balanceOf(address(this)), 0, "sender received excess input token");
        assertEq(debtToken.balanceOf(receiver), actualOutputAmount, "receiver received output token");
        assertEq(collateralToken.balanceOf(address(veloraAdapter)), 0, "velora adapter has no input token");
        assertEq(debtToken.balanceOf(address(veloraAdapter)), 0, "velora adapter has no output token");
    }

    // Case where the receiver on the calldata is the VeloraAdapter
    function test_buy_AugustusReceiverAsVeloraAdapter(uint256 amount, uint256 extra, address receiver) public {
        _receiver(receiver);

        amount = bound(amount, 1, type(uint128).max);
        extra = bound(extra, 0, type(uint128).max);

        deal(address(collateralToken), address(veloraAdapter), amount + extra);

        // Expect the transfer of the output token to the receiver from the VeloraAdapter
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(veloraAdapter), receiver, amount);
        _buy(address(collateralToken), address(debtToken), amount, amount, 0, address(veloraAdapter), receiver);

        assertEq(collateralToken.balanceOf(receiver), extra, "receiver received excess input token");
        assertEq(debtToken.balanceOf(receiver), amount, "receiver received output token");
        assertEq(collateralToken.balanceOf(address(veloraAdapter)), 0, "velora adapter has no input token");
        assertEq(debtToken.balanceOf(address(veloraAdapter)), 0, "velora adapter has no output token");
    }

    function _buy(
        address inputToken,
        address outputToken,
        uint256 maxInputAmount,
        uint256 outputAmount,
        uint256 newOutputAmount,
        address augustusReceiver,
        address receiver
    ) internal {
        uint256 fromAmountOffset = 4 + 32 + 32;
        uint256 toAmountOffset = fromAmountOffset + 32;

        veloraAdapter.buy(
            address(augustus),
            abi.encodeCall(augustus.mockBuy, (inputToken, outputToken, maxInputAmount, outputAmount, augustusReceiver)),
            inputToken,
            outputToken,
            newOutputAmount,
            IVeloraAdapter.Offsets({exactAmount: toAmountOffset, limitAmount: fromAmountOffset, quotedAmount: 0}),
            receiver
        );
    }

    // Checks that the adapter correctly adjusts amounts sent to augustus.
    // Expects a revert since the augustus address will not swap the tokens.
    function _updateAmountsBuy(
        address _augustus,
        uint256 initialExact,
        uint256 initialLimit,
        uint256 initialQuoted,
        uint256 adjustedExact,
        uint256 newLimit,
        uint256 offset,
        bool adjustQuoted
    ) internal {
        _makeEmptyAccountCallable(_augustus);
        augustusRegistry.setValid(_augustus, true);

        offset = _boundOffset(offset);

        initialExact = bound(initialExact, 1, type(uint64).max);
        initialLimit = bound(initialLimit, 0, type(uint64).max);
        initialQuoted = bound(initialQuoted, 0, type(uint64).max);
        adjustedExact = bound(adjustedExact, 1, type(uint64).max);

        uint256 adjustedLimit = newLimit;

        uint256 adjustedQuoted;
        uint256 quotedOffset;
        if (adjustQuoted) {
            adjustedQuoted = Math.mulDiv(initialQuoted, adjustedExact, initialExact, Math.Rounding.Floor);
            quotedOffset = offset + 64;
        } else {
            adjustedQuoted = initialQuoted;
            quotedOffset = 0;
        }

        vm.expectCall(address(_augustus), _swapCalldata(offset, adjustedExact, adjustedLimit, adjustedQuoted));
        veloraAdapter.buy(
            _augustus,
            _swapCalldata(offset, initialExact, initialLimit, initialQuoted),
            address(collateralToken),
            address(debtToken),
            adjustedExact,
            IVeloraAdapter.Offsets(offset, offset + 32, quotedOffset),
            address(1)
        );
    }
}
