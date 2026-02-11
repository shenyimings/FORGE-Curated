// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract PrincipalMigrationContract_MigrateToPRLAndBridge_Integrations_Test is Integrations_Test {
    using OptionsBuilder for bytes;

    bytes options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

    function test_MigrateToPRLAndBridge() external {
        uint256 amountToMigrate = DEFAULT_AMOUNT_MIGRATED;

        uint256 alicePrlBalanceBefore = prl.balanceOf(users.alice.addr);
        uint256 alicePeripheralPRLABalanceBefore = peripheralPRLA.balanceOf(users.alice.addr);
        uint256 migrationContractBalanceBefore = prl.balanceOf(address(principalMigrationContract));
        SendParam memory sendParam =
            SendParam(aEid, addressToBytes32(users.alice.addr), amountToMigrate, amountToMigrate, options, "", "");
        MessagingFee memory fees = lockBox.quoteSend(sendParam, false);

        vm.startPrank(users.alice.addr);

        mimo.approve(address(principalMigrationContract), amountToMigrate);

        vm.expectEmit(true, true, false, true);
        emit PrincipalMigrationContract.MIMOToPRLMigratedAndBridged(users.alice.addr, users.alice.addr, sendParam, fees);
        principalMigrationContract.migrateToPRLAndBridge{ value: fees.nativeFee }(sendParam, fees, users.alice.addr);

        verifyPackets(aEid, address(peripheralPRLA));

        assertEq(mimo.balanceOf(users.alice.addr), INITIAL_BALANCE - amountToMigrate);
        assertEq(prl.balanceOf(users.alice.addr), alicePrlBalanceBefore);
        assertEq(peripheralPRLA.balanceOf(users.alice.addr), alicePeripheralPRLABalanceBefore + amountToMigrate);
        assertEq(prl.balanceOf(address(principalMigrationContract)), migrationContractBalanceBefore - amountToMigrate);
    }

    function testFuzz_MigrateToPRLAndBridge(uint256 amountToMigrate) external {
        amountToMigrate = _bound(amountToMigrate, 10, INITIAL_BALANCE);

        uint256 alicePrlBalanceBefore = prl.balanceOf(users.alice.addr);
        uint256 alicePeripheralPRLABalanceBefore = peripheralPRLA.balanceOf(users.alice.addr);
        uint256 migrationContractBalanceBefore = prl.balanceOf(address(principalMigrationContract));
        SendParam memory sendParam =
            SendParam(aEid, addressToBytes32(users.alice.addr), amountToMigrate, amountToMigrate, options, "", "");
        MessagingFee memory fees = lockBox.quoteSend(sendParam, false);

        vm.startPrank(users.alice.addr);

        mimo.approve(address(principalMigrationContract), amountToMigrate);

        vm.expectEmit(true, true, false, true);
        emit PrincipalMigrationContract.MIMOToPRLMigratedAndBridged(users.alice.addr, users.alice.addr, sendParam, fees);
        principalMigrationContract.migrateToPRLAndBridge{ value: fees.nativeFee }(sendParam, fees, users.alice.addr);

        verifyPackets(aEid, address(peripheralPRLA));

        assertEq(mimo.balanceOf(users.alice.addr), INITIAL_BALANCE - amountToMigrate);
        assertEq(prl.balanceOf(users.alice.addr), alicePrlBalanceBefore);
        assertEq(peripheralPRLA.balanceOf(users.alice.addr), alicePeripheralPRLABalanceBefore + amountToMigrate);
        assertEq(prl.balanceOf(address(principalMigrationContract)), migrationContractBalanceBefore - amountToMigrate);
    }

    modifier PauseContract() {
        vm.startPrank(users.owner.addr);
        principalMigrationContract.pause();
        _;
    }

    function test_MigrateToPRLAndBridge_RevertWhen_Paused() external PauseContract {
        SendParam memory sendParam = SendParam(
            aEid, addressToBytes32(users.alice.addr), DEFAULT_AMOUNT_MIGRATED, DEFAULT_AMOUNT_MIGRATED, options, "", ""
        );
        MessagingFee memory fees = lockBox.quoteSend(sendParam, false);
        vm.startPrank(users.alice.addr);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        principalMigrationContract.migrateToPRLAndBridge{ value: fees.nativeFee }(sendParam, fees, users.alice.addr);
    }

    function test_MigrateToPRLAndBridge_RevertWhen_RefundAddressIsZero() external {
        SendParam memory sendParam = SendParam(
            aEid, addressToBytes32(users.alice.addr), DEFAULT_AMOUNT_MIGRATED, DEFAULT_AMOUNT_MIGRATED, options, "", ""
        );
        MessagingFee memory fees = lockBox.quoteSend(sendParam, false);
        vm.startPrank(users.alice.addr);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.AddressZero.selector));
        principalMigrationContract.migrateToPRLAndBridge{ value: fees.nativeFee }(sendParam, fees, address(0));
    }
}
