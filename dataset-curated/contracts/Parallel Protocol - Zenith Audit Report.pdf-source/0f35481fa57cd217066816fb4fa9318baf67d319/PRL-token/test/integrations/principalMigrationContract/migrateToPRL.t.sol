// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract PrincipalMigrationContract_MigrateToPRL_Integrations_Test is Integrations_Test {
    function test_MigrateToPRL() external {
        uint256 amountToMigrate = DEFAULT_AMOUNT_MIGRATED;

        uint256 alicePrlBalanceBefore = prl.balanceOf(users.alice.addr);
        uint256 migrationContractBalanceBefore = prl.balanceOf(address(principalMigrationContract));

        vm.startPrank(users.alice.addr);

        mimo.approve(address(principalMigrationContract), amountToMigrate);

        vm.expectEmit(true, true, false, true);
        emit PrincipalMigrationContract.MIMOToPRLMigrated(users.alice.addr, users.alice.addr, amountToMigrate);
        principalMigrationContract.migrateToPRL(amountToMigrate, users.alice.addr);

        assertEq(mimo.balanceOf(users.alice.addr), INITIAL_BALANCE - amountToMigrate);
        assertEq(prl.balanceOf(users.alice.addr), alicePrlBalanceBefore + amountToMigrate);
        assertEq(prl.balanceOf(address(principalMigrationContract)), migrationContractBalanceBefore - amountToMigrate);
    }

    function testFuzz_MigrateToPRL(uint256 amountToMigrate) external {
        amountToMigrate = _bound(amountToMigrate, 10, INITIAL_BALANCE);

        uint256 alicePrlBalanceBefore = prl.balanceOf(users.alice.addr);
        uint256 migrationContractBalanceBefore = prl.balanceOf(address(principalMigrationContract));

        vm.startPrank(users.alice.addr);

        mimo.approve(address(principalMigrationContract), amountToMigrate);

        vm.expectEmit(true, true, false, true);
        emit PrincipalMigrationContract.MIMOToPRLMigrated(users.alice.addr, users.alice.addr, amountToMigrate);
        principalMigrationContract.migrateToPRL(amountToMigrate, users.alice.addr);

        assertEq(mimo.balanceOf(users.alice.addr), INITIAL_BALANCE - amountToMigrate);
        assertEq(prl.balanceOf(users.alice.addr), alicePrlBalanceBefore + amountToMigrate);
        assertEq(prl.balanceOf(address(principalMigrationContract)), migrationContractBalanceBefore - amountToMigrate);
    }

    modifier PauseContract() {
        vm.startPrank(users.owner.addr);
        principalMigrationContract.pause();
        _;
    }

    function test_MigrateToPRL_RevertWhen_Paused() external PauseContract {
        vm.startPrank(users.alice.addr);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        principalMigrationContract.migrateToPRL(DEFAULT_AMOUNT_MIGRATED, users.alice.addr);
    }
}
