// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Base.t.sol";

contract TimeLockPenaltyERC20_Constructor_Integrations_Test is Base_Test {
    string constant name = "TimeLockPenaltyERC20";
    string constant symbol = "TLPERC20";

    function test_TimeLockPenaltyERC20_Constructor() external {
        timeLockPenaltyERC20 = new TimeLockPenaltyERC20Mock(
            name,
            symbol,
            address(par),
            users.daoTreasury.addr,
            address(accessManager),
            DEFAULT_PENALTY_PERCENTAGE,
            DEFAULT_TIME_LOCK_DURATION
        );
        assertEq(timeLockPenaltyERC20.authority(), address(accessManager));
        assertEq(address(timeLockPenaltyERC20.underlying()), address(par));
        assertEq(timeLockPenaltyERC20.timeLockDuration(), DEFAULT_TIME_LOCK_DURATION);
        assertEq(timeLockPenaltyERC20.startPenaltyPercentage(), DEFAULT_PENALTY_PERCENTAGE);
        assertEq(timeLockPenaltyERC20.unlockingAmount(), 0);
        assertEq(timeLockPenaltyERC20.feeReceiver(), users.daoTreasury.addr);
        assertEq(timeLockPenaltyERC20.name(), name);
        assertEq(timeLockPenaltyERC20.symbol(), symbol);
    }

    function test_TimeLockPenaltyERC20_Constructor_RevertWhen_TimelockDurationBelowMin() external {
        uint64 wrongTimeLockDuration = 1 days - 1;
        vm.expectRevert(
            abi.encodeWithSelector(TimeLockPenaltyERC20.TimelockOutOfRange.selector, wrongTimeLockDuration)
        );
        new TimeLockPenaltyERC20Mock(
            name,
            symbol,
            address(par),
            users.daoTreasury.addr,
            address(accessManager),
            DEFAULT_PENALTY_PERCENTAGE,
            wrongTimeLockDuration
        );
    }

    function test_TimeLockPenaltyERC20_Constructor_RevertWhen_TimelockDurationExceedMax() external {
        uint64 wrongTimeLockDuration = 365 days + 1;
        vm.expectRevert(
            abi.encodeWithSelector(TimeLockPenaltyERC20.TimelockOutOfRange.selector, wrongTimeLockDuration)
        );
        new TimeLockPenaltyERC20Mock(
            name,
            symbol,
            address(par),
            users.daoTreasury.addr,
            address(accessManager),
            DEFAULT_PENALTY_PERCENTAGE,
            wrongTimeLockDuration
        );
    }

    function test_TimeLockPenaltyERC20_Constructor_RevertWhen_StartPenaltyPercentageExceedOneHundredPercent()
        external
    {
        uint256 wrongMaxPenaltyPercentage = DEFAULT_PENALTY_PERCENTAGE + 1;
        vm.expectRevert(
            abi.encodeWithSelector(TimeLockPenaltyERC20.PercentageOutOfRange.selector, wrongMaxPenaltyPercentage)
        );
        new TimeLockPenaltyERC20Mock(
            name,
            symbol,
            address(par),
            users.daoTreasury.addr,
            address(accessManager),
            wrongMaxPenaltyPercentage,
            DEFAULT_TIME_LOCK_DURATION
        );
    }
}
