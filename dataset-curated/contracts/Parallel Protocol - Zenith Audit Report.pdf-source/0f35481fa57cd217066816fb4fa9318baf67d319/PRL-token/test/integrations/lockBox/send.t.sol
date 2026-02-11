// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract LockBox_Send_Integrations_Test is Integrations_Test {
    using OptionsBuilder for bytes;

    function testFuzz_LockBox_Send(uint256 amountToMigrate) external {
        amountToMigrate = _bound(amountToMigrate, 10, INITIAL_BALANCE);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        deal(address(prl), users.alice.addr, amountToMigrate);

        SendParam memory sendParam =
            SendParam(aEid, addressToBytes32(users.alice.addr), amountToMigrate, amountToMigrate, options, "", "");
        MessagingFee memory fees = lockBox.quoteSend(sendParam, false);

        vm.startPrank(users.alice.addr);
        prl.approve(address(lockBox), amountToMigrate);
        lockBox.send{ value: fees.nativeFee }(sendParam, fees, users.alice.addr);

        verifyPackets(aEid, address(peripheralPRLA));

        assertEq(prl.balanceOf(users.alice.addr), 0);
        assertEq(peripheralPRLA.balanceOf(users.alice.addr), amountToMigrate);
    }

    modifier PauseContract() {
        vm.startPrank(users.owner.addr);
        lockBox.pause();
        _;
    }

    function test_LockBox_Send_RevertWhen_Paused() external PauseContract {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        deal(address(prl), users.alice.addr, DEFAULT_AMOUNT_MIGRATED);

        SendParam memory sendParam = SendParam(
            aEid, addressToBytes32(users.alice.addr), DEFAULT_AMOUNT_MIGRATED, DEFAULT_AMOUNT_MIGRATED, options, "", ""
        );
        MessagingFee memory fees = lockBox.quoteSend(sendParam, false);

        vm.startPrank(users.alice.addr);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        lockBox.send{ value: fees.nativeFee }(sendParam, fees, users.alice.addr);
    }
}
