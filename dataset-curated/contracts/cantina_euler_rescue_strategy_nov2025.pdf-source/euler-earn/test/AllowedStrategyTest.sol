// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {IntegrationTest, IERC4626, ErrorsLib, TIMELOCK} from "./helpers/IntegrationTest.sol";

import "forge-std/Test.sol";

contract AllowedStrategyTest is IntegrationTest {
    IERC4626 strategy;

    function setUp() public virtual override {
        super.setUp();

        strategy = IERC4626(
            factory.createProxy(address(0), true, abi.encodePacked(address(loanToken), address(oracle), unitOfAccount))
        );
    }

    function testSetCapStrategyNotAllowed() public {
        vm.prank(CURATOR);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.UnauthorizedMarket.selector, (address(strategy))));
        vault.submitCap(strategy, 1e18);
    }

    function testSetCapNestedEEVault() public {
        IERC4626 otherVault = IERC4626(
            address(
                eeFactory.createEulerEarn(
                    OWNER, TIMELOCK, address(loanToken), "EulerEarn Vault", "EEV", bytes32(uint256(2))
                )
            )
        );
        vm.prank(CURATOR);
        vault.submitCap(otherVault, 1e18);
        vm.warp(block.timestamp + vault.timelock());

        vault.acceptCap(otherVault);

        assertEq(address(vault.withdrawQueue(vault.withdrawQueueLength() - 1)), address(otherVault));
    }

    function testSetCapStrategyUnverifiedDuringTimelock() public {
        perspective.perspectiveVerify(address(strategy));

        vm.startPrank(CURATOR);
        vault.submitCap(strategy, 1e18);

        vm.warp(block.timestamp + vault.timelock() - 1);

        // unverify during timelock
        perspective.perspectiveUnverify(address(strategy));

        // doesn't accept the new cap
        vm.warp(block.timestamp + 1);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.UnauthorizedMarket.selector, (address(strategy))));
        vault.acceptCap(strategy);

        // can't set another cap because pending
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.AlreadyPending.selector, (address(strategy))));
        vault.submitCap(strategy, 2e18);

        // can revoke pending
        vault.revokePendingCap(strategy);

        // still can't set new cap
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.UnauthorizedMarket.selector, (address(strategy))));
        vault.submitCap(strategy, 2e18);
    }

    function testSetCapStrategyUnverifiedCanSetLowerCap() public {
        perspective.perspectiveVerify(address(strategy));

        vm.startPrank(CURATOR);
        vault.submitCap(strategy, 1e18);

        vm.warp(block.timestamp + vault.timelock());
        vault.acceptCap(strategy);

        perspective.perspectiveUnverify(address(strategy));

        // can't increase cap
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.UnauthorizedMarket.selector, (address(strategy))));
        vault.submitCap(strategy, 2e18);

        // but can decrease it
        vault.submitCap(strategy, 0.5e18);
        assertEq(vault.config(strategy).cap, 0.5e18);
    }
}
