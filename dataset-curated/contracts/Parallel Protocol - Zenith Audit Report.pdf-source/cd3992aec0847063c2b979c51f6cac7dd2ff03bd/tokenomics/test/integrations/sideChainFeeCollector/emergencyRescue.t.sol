// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract SideChainFeeCollector_EmergencyRescue_Integrations_Test is Integrations_Test {
    address internal receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        par.mint(address(sideChainFeeCollector), INITIAL_BALANCE);
    }

    modifier pauseContract() {
        vm.startPrank(users.admin.addr);
        sideChainFeeCollector.pause();
        _;
    }

    function test_SideChainFeeCollector_EmergencyRescue() external pauseContract {
        vm.expectEmit(true, true, true, true);
        emit FeeCollectorCore.EmergencyRescued(address(par), receiver, INITIAL_BALANCE);
        sideChainFeeCollector.emergencyRescue(address(par), receiver, INITIAL_BALANCE);

        assertEq(par.balanceOf(address(sideChainFeeCollector)), 0);
        assertEq(par.balanceOf(receiver), INITIAL_BALANCE);
    }

    function test_SideChainFeeCollector_EmergencyRescue_RevertWhen_CallerNotAuthorized() external pauseContract {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        sideChainFeeCollector.emergencyRescue(address(par), users.hacker.addr, INITIAL_BALANCE);
    }

    function test_SideChainFeeCollector_EmergencyRescue_RevertWhen_NotPaused() external {
        vm.startPrank(users.admin.addr);
        vm.expectRevert(abi.encodeWithSelector(Pausable.ExpectedPause.selector));
        sideChainFeeCollector.emergencyRescue(address(par), users.hacker.addr, INITIAL_BALANCE);
    }
}
