// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract SideChainFeeCollector_Release_Integrations_Test is Integrations_Test {
    using OptionsBuilder for bytes;

    function test_SideChainFeeCollector_Release() external {
        vm.startPrank(users.admin.addr);
        par.mint(address(sideChainFeeCollector), INITIAL_BALANCE);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        sideChainFeeCollector.release(options);

        assertEq(par.balanceOf(address(sideChainFeeCollector)), 0);
    }

    function test_SideChainFeeCollector_Release_RevertWhen_NotCallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        sideChainFeeCollector.release(options);
    }

    function test_SideChainFeeCollector_Release_RevertWhen_AmountIsZero() external {
        vm.startPrank(users.admin.addr);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        vm.expectRevert(abi.encodeWithSelector(FeeCollectorCore.NothingToRelease.selector));
        sideChainFeeCollector.release(options);
    }
}
