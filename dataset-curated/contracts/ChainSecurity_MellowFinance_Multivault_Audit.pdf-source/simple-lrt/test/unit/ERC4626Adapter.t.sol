// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../BaseTest.sol";
import "../mocks/MockSymbioticFarm.sol";

contract Unit is BaseTest {
    using RandomLib for RandomLib.Storage;

    function testERC4626AdapterAdapter() external {
        MultiVault vault = new MultiVault("test", 1);
        ERC4626Adapter adapter = new ERC4626Adapter(address(vault));

        vm.expectRevert("ERC4626Adapter: not implemented");
        adapter.pushRewards(address(0), new bytes(0), new bytes(0));
        vm.expectRevert("ERC4626Adapter: not implemented");
        adapter.validateRewardData(new bytes(0));

        for (uint256 i = 0; i < 10; i++) {
            assertEq(
                adapter.handleVault(
                    i == 0 ? address(0) : i == 9 ? address(type(uint160).max) : rnd.randAddress()
                ),
                address(0)
            );
        }

        vm.expectRevert();
        Address.functionStaticCall(
            address(adapter),
            abi.encodeWithSelector(adapter.handleVault.selector, type(uint256).max)
        );

        vm.expectRevert("ERC4626Adapter: delegate call only");
        adapter.withdraw(address(0), address(0), address(0), 0, address(0));

        vm.expectRevert("ERC4626Adapter: delegate call only");
        adapter.deposit(address(0), 0);
    }
}
