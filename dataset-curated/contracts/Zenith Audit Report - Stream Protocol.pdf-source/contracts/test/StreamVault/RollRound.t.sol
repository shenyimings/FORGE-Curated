// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Base} from "./Base.t.sol";
import {Vault} from "../../src/lib/Vault.sol";
import {StreamVault} from "../../src/StreamVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/************************************************
 *  ROLL ROUND TESTS
 ***********************************************/
contract StreamVaultRollRoundTest is Base {
    function test_RevertIfOwnerDoesNotRollRound(
        uint104 _amount,
        address _caller
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.assume(_caller != owner);
        vm.assume(_caller != address(0));
        stakeAndRollRound(depositor1, depositor1, _amount);
        vm.startPrank(_caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                _caller
            )
        );
        streamVault.rollToNextRound(0, true);
        vm.stopPrank();
    }
    function test_SuccessfullFirstRollNoYield(uint104 _amount) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAndRollRound(depositor1, depositor1, _amount);
        assertOneRollBaseState(_amount, 2);
        assertPricePerShare(1, 10 ** decimals);

        assertEq(stableWrapper.balanceOf(address(streamVault)), _amount);
        assertEq(stableWrapper.totalSupply(), _amount);
    }

    function test_SuccessfullMultiRollWithPositiveYield_SingleDepositor_OneDeposit(
        uint104 _amount,
        uint104 _yield
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        stakeAndRollRound(depositor1, depositor1, _amount);
        rollRound(uint256(_yield), true);

        assertOneRollBaseState(_amount, 3);
        uint256 expectedPricePerShare = ((10 ** uint256(decimals)) *
            (uint256(_amount) + uint256(_yield))) / uint256(_amount);
        assertPricePerShare(2, expectedPricePerShare);

        assertEq(
            stableWrapper.balanceOf(address(streamVault)),
            _amount + uint256(_yield)
        );
        assertEq(stableWrapper.totalSupply(), _amount + uint256(_yield));
    }

    function test_SuccessfullMultiRollWithPositiveYield_MultiDepositor_OneDeposit(
        uint104 _amount1,
        uint104 _amount2,
        uint104 _yield
    ) public {
        vm.assume(_amount1 >= minSupply && _amount1 <= startingBal);
        vm.assume(_amount2 >= minSupply && _amount2 <= startingBal);
        vm.assume(_amount1 + _amount2 <= startingBal);
        vm.assume(_amount1 + _amount2 <= cap);
        stakeAssets(depositor1, depositor1, _amount1);
        stakeAndRollRound(depositor2, depositor2, _amount2);
        rollRound(uint256(_yield), true);

        assertOneRollBaseState(_amount1 + _amount2, 3);
        uint256 expectedPricePerShare = ((10 ** uint256(decimals)) *
            (uint256(_amount1) + uint256(_amount2) + uint256(_yield))) /
            (uint256(_amount1) + uint256(_amount2));
        assertPricePerShare(2, expectedPricePerShare);

        assertEq(
            stableWrapper.balanceOf(address(streamVault)),
            _amount1 + _amount2 + uint256(_yield)
        );
        assertEq(
            stableWrapper.totalSupply(),
            _amount1 + _amount2 + uint256(_yield)
        );
    }

    function test_SuccessfullMultiRollWithPositiveYield_SingleDepositor_MultiDeposit(
        uint104 _amount,
        uint104 _yield
    ) public {
        vm.assume(_yield < _amount * (10 ** decimals));
        vm.assume(_amount >= minSupply && _amount <= (startingBal / 2) - 1);
        stakeAndRollRound(depositor1, depositor1, _amount);
        stakeAssets(depositor1, depositor1, _amount);
        assertVaultState(2, _amount);
        rollRound(uint256(_yield), true);

        uint256 expectedPricePerShare = ((10 ** uint256(decimals)) *
            (uint256(_amount) + uint256(_yield))) / uint256(_amount);
        assertPricePerShare(2, expectedPricePerShare);

        uint256 secondRoundAmount = (_amount * (10 ** decimals)) /
            expectedPricePerShare;

        assertOneRollBaseState(_amount + uint104(secondRoundAmount), 3);

        assertEq(
            stableWrapper.balanceOf(address(streamVault)),
            (_amount * 2) + uint256(_yield)
        );
        assertEq(stableWrapper.totalSupply(), (_amount * 2) + uint256(_yield));
    }

    function test_SuccessfullMultiRollWithNegativeYield_SingleDepositor_OneDeposit(
        uint104 _amount,
        uint104 _yield
    ) public {
        vm.assume(_amount >= minSupply && _amount <= startingBal);
        vm.assume(_yield < _amount - minSupply);
        stakeAndRollRound(depositor1, depositor1, _amount);
        rollRound(uint256(_yield), false);

        assertOneRollBaseState(_amount, 3);
        uint256 expectedPricePerShare = ((10 ** uint256(decimals)) *
            (uint256(_amount) - uint256(_yield))) / uint256(_amount);
        assertPricePerShare(2, expectedPricePerShare);

        assertEq(
            stableWrapper.balanceOf(address(streamVault)),
            _amount - uint256(_yield)
        );
        assertEq(stableWrapper.totalSupply(), _amount - uint256(_yield));
    }

    function test_SuccessfullMultiRollWithNegative_MultiDepositor_OneDeposit(
        uint104 _amount1,
        uint104 _amount2,
        uint104 _yield
    ) public {
        vm.assume(_amount1 >= minSupply && _amount1 <= startingBal);
        vm.assume(_amount2 >= minSupply && _amount2 <= startingBal);
        vm.assume(_amount1 + _amount2 <= startingBal);
        vm.assume(_amount1 + _amount2 <= cap);
        vm.assume(_yield < _amount1 + _amount2 - minSupply);
        stakeAssets(depositor1, depositor1, _amount1);
        stakeAndRollRound(depositor2, depositor2, _amount2);
        rollRound(uint256(_yield), false);

        assertOneRollBaseState(_amount1 + _amount2, 3);
        uint256 expectedPricePerShare = ((10 ** uint256(decimals)) *
            (uint256(_amount1) + uint256(_amount2) - uint256(_yield))) /
            (uint256(_amount1) + uint256(_amount2));
        assertPricePerShare(2, expectedPricePerShare);

        assertEq(
            stableWrapper.balanceOf(address(streamVault)),
            _amount1 + _amount2 - uint256(_yield)
        );
        assertEq(
            stableWrapper.totalSupply(),
            _amount1 + _amount2 - uint256(_yield)
        );
    }

    function test_SuccessfullMultiRollWithNegativeYield_SingleDepositor_MultiDeposit(
        uint104 _amount,
        uint104 _yield
    ) public {
        vm.assume(_amount >= minSupply && _amount <= (startingBal / 2) - 1);
        vm.assume(_yield < _amount - minSupply);
        stakeAndRollRound(depositor1, depositor1, _amount);
        stakeAssets(depositor1, depositor1, _amount);
        assertVaultState(2, _amount);
        rollRound(uint256(_yield), false);

        uint256 expectedPricePerShare = ((10 ** uint256(decimals)) *
            (uint256(_amount) - uint256(_yield))) / uint256(_amount);
        assertPricePerShare(2, expectedPricePerShare);

        uint256 secondRoundAmount = (_amount * (10 ** decimals)) /
            expectedPricePerShare;

        assertOneRollBaseState(_amount + uint104(secondRoundAmount), 3);

        assertEq(
            stableWrapper.balanceOf(address(streamVault)),
            (_amount * 2) - uint256(_yield)
        );
        assertEq(stableWrapper.totalSupply(), (_amount * 2) - uint256(_yield));
    }
}
