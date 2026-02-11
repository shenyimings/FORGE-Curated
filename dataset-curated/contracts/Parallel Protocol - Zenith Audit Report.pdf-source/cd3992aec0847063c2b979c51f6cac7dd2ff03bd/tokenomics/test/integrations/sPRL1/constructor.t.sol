// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Base.t.sol";

contract SPRL1_Constructor_Integrations_Test is Base_Test {
    function test_SPRL1_Constructor() external {
        sprl1 = new sPRL1(
            address(prl),
            users.daoTreasury.addr,
            address(accessManager),
            DEFAULT_PENALTY_PERCENTAGE,
            DEFAULT_TIME_LOCK_DURATION
        );
        assertEq(sprl1.authority(), address(accessManager));
        assertEq(address(sprl1.underlying()), address(prl));
        assertEq(sprl1.timeLockDuration(), DEFAULT_TIME_LOCK_DURATION);
        assertEq(sprl1.startPenaltyPercentage(), DEFAULT_PENALTY_PERCENTAGE);
        assertEq(sprl1.unlockingAmount(), 0);
        assertEq(sprl1.feeReceiver(), users.daoTreasury.addr);
        assertEq(sprl1.name(), "Stake PRL");
        assertEq(sprl1.symbol(), "sPRL1");
    }
}
