// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract PeripheralPRL_Send_Integrations_Test is Integrations_Test {
    using OptionsBuilder for bytes;

    function testFuzz_PeripheralPRL_Send_ToMainChain(uint256 amountToMigrate) external {
        amountToMigrate = _bound(amountToMigrate, 10, INITIAL_BALANCE);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        deal(address(peripheralPRLA), users.alice.addr, amountToMigrate);
        deal(address(prl), address(lockBox), amountToMigrate);

        SendParam memory sendParam =
            SendParam(mainEid, addressToBytes32(users.alice.addr), amountToMigrate, amountToMigrate, options, "", "");

        MessagingFee memory fees = peripheralPRLA.quoteSend(sendParam, false);

        vm.startPrank(users.alice.addr);
        peripheralPRLA.send{ value: fees.nativeFee }(sendParam, fees, users.alice.addr);

        verifyPackets(mainEid, address(lockBox));

        assertEq(peripheralPRLA.balanceOf(users.alice.addr), 0);
        assertEq(prl.balanceOf(users.alice.addr), amountToMigrate);
        assertEq(prl.balanceOf(address(lockBox)), 0);
    }

    function testFuzz_PeripheralPRL_Send_ToAnotherChain(uint256 amountToMigrate) external {
        amountToMigrate = _bound(amountToMigrate, 10, INITIAL_BALANCE);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        deal(address(peripheralPRLA), users.alice.addr, amountToMigrate);

        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(users.alice.addr), amountToMigrate, amountToMigrate, options, "", "");

        MessagingFee memory fees = peripheralPRLA.quoteSend(sendParam, false);

        vm.startPrank(users.alice.addr);
        peripheralPRLA.approve(address(peripheralPRLA), amountToMigrate);
        peripheralPRLA.send{ value: fees.nativeFee }(sendParam, fees, users.alice.addr);

        verifyPackets(bEid, address(peripheralPRLB));

        assertEq(peripheralPRLA.balanceOf(users.alice.addr), 0);
        assertEq(peripheralPRLB.balanceOf(users.alice.addr), amountToMigrate);
    }

    modifier PauseContract() {
        vm.startPrank(users.owner.addr);
        peripheralPRLA.pause();
        _;
    }

    function test_PeripheralPRL_Send_RevertWhen_Paused() external PauseContract {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        deal(address(peripheralPRLA), users.alice.addr, DEFAULT_AMOUNT_MIGRATED);

        SendParam memory sendParam = SendParam(
            mainEid,
            addressToBytes32(users.alice.addr),
            DEFAULT_AMOUNT_MIGRATED,
            DEFAULT_AMOUNT_MIGRATED,
            options,
            "",
            ""
        );
        MessagingFee memory fees = peripheralPRLA.quoteSend(sendParam, false);

        vm.startPrank(users.alice.addr);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        peripheralPRLA.send{ value: fees.nativeFee }(sendParam, fees, users.alice.addr);
    }
}
