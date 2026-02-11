// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../BaseTest.sol";
import "../mocks/MockSymbioticFarm.sol";

contract Unit is BaseTest {
    using RandomLib for RandomLib.Storage;

    function testSymbioticAdapter() external {
        MultiVault vault = new MultiVault("test", 1);
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );

        vm.expectRevert("SymbioticAdapter: delegate call only");
        symbioticAdapter.pushRewards(address(0), new bytes(0), new bytes(0));

        vm.expectRevert("SymbioticAdapter: delegate call only");
        symbioticAdapter.withdraw(address(0), address(0), address(0), 0, address(0));

        vm.expectRevert("SymbioticAdapter: delegate call only");
        symbioticAdapter.deposit(address(0), 0);

        vm.expectRevert("SymbioticAdapter: only vault");
        symbioticAdapter.handleVault(address(0));

        (address symbioticVault,,, address admin) =
            symbioticHelper.createDefaultSymbioticVault(Constants.WSTETH());
        vm.prank(admin);
        ISymbioticVault(symbioticVault).setDepositWhitelist(true);

        assertEq(0, symbioticAdapter.maxDeposit(symbioticVault));

        vm.prank(admin);
        ISymbioticVault(symbioticVault).setDepositorWhitelistStatus(address(vault), true);

        assertEq(type(uint256).max, symbioticAdapter.maxDeposit(symbioticVault));
    }
}
