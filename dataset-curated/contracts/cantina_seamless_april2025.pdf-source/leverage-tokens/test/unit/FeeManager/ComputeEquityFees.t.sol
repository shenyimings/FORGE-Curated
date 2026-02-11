// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// External imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {ExternalAction} from "src/types/DataTypes.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {FeeManagerTest} from "test/unit/FeeManager/FeeManager.t.sol";

contract ComputeEquityFeesTest is FeeManagerTest {
    address public treasury = makeAddr("treasury");
    ILeverageToken public leverageToken = ILeverageToken(makeAddr("leverageToken"));

    function setUp() public override {
        super.setUp();

        _setTreasury(feeManagerRole, treasury);
    }

    function test_computeEquityFees_Deposit() public {
        ExternalAction action = ExternalAction.Deposit;
        uint256 equity = 1 ether;
        uint256 depositTreasuryFee = 100;
        uint256 depositTokenFee = 200;
        uint256 withdrawTreasuryFee = 300;
        uint256 withdrawTokenFee = 400;
        _setFees(depositTreasuryFee, depositTokenFee, withdrawTreasuryFee, withdrawTokenFee);

        (
            uint256 equityForLeverageTokenAfterFees,
            uint256 equityForSharesAfterFees,
            uint256 tokenFee,
            uint256 treasuryFee
        ) = feeManager.exposed_computeEquityFees(leverageToken, equity, action);

        uint256 expectedTokenFee = Math.mulDiv(equity, depositTokenFee, feeManager.MAX_FEE(), Math.Rounding.Ceil);
        uint256 expectedTreasuryFee = Math.mulDiv(equity, depositTreasuryFee, feeManager.MAX_FEE(), Math.Rounding.Ceil);
        assertEq(tokenFee, expectedTokenFee);
        assertEq(treasuryFee, expectedTreasuryFee);

        assertEq(equityForLeverageTokenAfterFees, equity - expectedTreasuryFee);
        assertEq(equityForSharesAfterFees, equity - (expectedTreasuryFee + expectedTokenFee));
    }

    function test_computeEquityFees_Withdraw() public {
        ExternalAction action = ExternalAction.Withdraw;
        uint256 equity = 1 ether;
        uint256 depositTreasuryFee = 100;
        uint256 depositTokenFee = 200;
        uint256 withdrawTreasuryFee = 300;
        uint256 withdrawTokenFee = 400;
        _setFees(depositTreasuryFee, depositTokenFee, withdrawTreasuryFee, withdrawTokenFee);

        (
            uint256 equityForLeverageTokenAfterFees,
            uint256 equityForSharesAfterFees,
            uint256 tokenFee,
            uint256 treasuryFee
        ) = feeManager.exposed_computeEquityFees(leverageToken, equity, action);

        uint256 expectedTokenFee = Math.mulDiv(equity, withdrawTokenFee, feeManager.MAX_FEE(), Math.Rounding.Ceil);
        uint256 expectedTreasuryFee = Math.mulDiv(equity, withdrawTreasuryFee, feeManager.MAX_FEE(), Math.Rounding.Ceil);
        assertEq(tokenFee, expectedTokenFee);
        assertEq(treasuryFee, expectedTreasuryFee);

        assertEq(equityForLeverageTokenAfterFees, equity);
        assertEq(equityForSharesAfterFees, equity + expectedTokenFee);
    }

    function test_computeEquityFees_SumOfFeesGreaterThanEquity() public {
        ExternalAction action = ExternalAction.Deposit;
        uint256 equity = 1 ether;
        uint256 depositTreasuryFee = 6000;
        uint256 depositTokenFee = 5000;
        _setFees(depositTreasuryFee, depositTokenFee, 0, 0);

        (
            uint256 equityForLeverageTokenAfterFees,
            uint256 equityForSharesAfterFees,
            uint256 tokenFee,
            uint256 treasuryFee
        ) = feeManager.exposed_computeEquityFees(leverageToken, equity, action);

        uint256 expectedTreasuryFee = Math.mulDiv(equity, depositTreasuryFee, feeManager.MAX_FEE(), Math.Rounding.Ceil);
        assertEq(treasuryFee, expectedTreasuryFee);

        uint256 expectedTokenFee = equity - expectedTreasuryFee;
        assertEq(tokenFee, expectedTokenFee);

        assertEq(equityForLeverageTokenAfterFees, equity - expectedTreasuryFee);
        assertEq(equityForSharesAfterFees, equity - (expectedTreasuryFee + expectedTokenFee));
    }

    function test_computeEquityFees_TreasuryNotSet() public {
        // Mocked values that don't matter for this test
        ExternalAction action = ExternalAction.Deposit;
        uint256 equity = 1 ether;
        uint256 depositTreasuryFee = 100;
        uint256 depositTokenFee = 200;
        uint256 withdrawTreasuryFee = 300;
        uint256 withdrawTokenFee = 400;
        _setFees(depositTreasuryFee, depositTokenFee, withdrawTreasuryFee, withdrawTokenFee);

        _setTreasury(feeManagerRole, address(0));

        (uint256 equityForLeverageTokenAfterFees,,, uint256 treasuryFee) =
            feeManager.exposed_computeEquityFees(leverageToken, equity, action);
        assertEq(equityForLeverageTokenAfterFees, equity);
        assertEq(treasuryFee, 0);
    }

    function testFuzz_computeEquityFees(
        uint128 equity,
        uint256 depositTreasuryFee,
        uint256 depositTokenFee,
        uint256 withdrawTreasuryFee,
        uint256 withdrawTokenFee
    ) public {
        ExternalAction action = ExternalAction.Deposit;
        depositTreasuryFee = bound(depositTreasuryFee, 0, feeManager.MAX_FEE());
        depositTokenFee = bound(depositTokenFee, 0, feeManager.MAX_FEE());
        withdrawTreasuryFee = bound(withdrawTreasuryFee, 0, feeManager.MAX_FEE());
        withdrawTokenFee = bound(withdrawTokenFee, 0, feeManager.MAX_FEE());
        _setFees(depositTreasuryFee, depositTokenFee, withdrawTreasuryFee, withdrawTokenFee);

        (
            uint256 equityForLeverageTokenAfterFees,
            uint256 equityForSharesAfterFees,
            uint256 tokenFee,
            uint256 treasuryFee
        ) = feeManager.exposed_computeEquityFees(leverageToken, equity, action);

        uint256 expectedTreasuryFee = Math.mulDiv(
            equity,
            action == ExternalAction.Deposit ? depositTreasuryFee : withdrawTreasuryFee,
            feeManager.MAX_FEE(),
            Math.Rounding.Ceil
        );
        assertEq(treasuryFee, expectedTreasuryFee);

        uint256 expectedTokenFee = Math.mulDiv(
            equity,
            action == ExternalAction.Deposit ? depositTokenFee : withdrawTokenFee,
            feeManager.MAX_FEE(),
            Math.Rounding.Ceil
        );
        if (expectedTokenFee + expectedTreasuryFee > equity) {
            expectedTokenFee = equity - expectedTreasuryFee;
        }
        assertEq(tokenFee, expectedTokenFee);

        uint256 expectedEquityForLeverageTokenAfterFees =
            action == ExternalAction.Deposit ? equity - expectedTreasuryFee : equity;
        assertEq(equityForLeverageTokenAfterFees, expectedEquityForLeverageTokenAfterFees);

        uint256 expectedEquityForSharesAfterFees = action == ExternalAction.Deposit
            ? expectedEquityForLeverageTokenAfterFees - expectedTokenFee
            : expectedEquityForLeverageTokenAfterFees + expectedTokenFee;
        assertEq(equityForSharesAfterFees, expectedEquityForSharesAfterFees);

        assertLe(tokenFee + treasuryFee, equity);
        assertLe(expectedEquityForSharesAfterFees, equity);
        assertLe(expectedEquityForLeverageTokenAfterFees, equity);
    }

    function _setFees(
        uint256 depositTreasuryFee,
        uint256 depositTokenFee,
        uint256 withdrawTreasuryFee,
        uint256 withdrawTokenFee
    ) internal {
        vm.startPrank(feeManagerRole);
        feeManager.setTreasuryActionFee(ExternalAction.Deposit, depositTreasuryFee);
        feeManager.setTreasuryActionFee(ExternalAction.Withdraw, withdrawTreasuryFee);
        feeManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Deposit, depositTokenFee);
        feeManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Withdraw, withdrawTokenFee);
        vm.stopPrank();
    }
}
