// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../BaseTest.sol";
import "../mocks/MockMultiVaultStorage.sol";

contract Unit is BaseTest {
    function testConstructor() external {
        MockMultiVaultStorage c = new MockMultiVaultStorage("test", 1);
        assertNotEq(address(c), address(0));

        assertEq(c.subvaultsCount(), 0);

        vm.expectRevert();
        c.subvaultAt(0);
        assertEq(c.indexOfSubvault(address(0)), 0);
        assertEq(address(c.defaultCollateral()), address(0));
        assertEq(address(c.depositStrategy()), address(0));
        assertEq(address(c.withdrawalStrategy()), address(0));
        assertEq(address(c.rebalanceStrategy()), address(0));
        assertEq(address(c.symbioticAdapter()), address(0));
        assertEq(address(c.eigenLayerAdapter()), address(0));
        assertEq(address(c.erc4626Adapter()), address(0));
        assertEq(address(c.rewardData(0).token), address(0));
        assertEq(c.farmIds().length, 0);
        assertEq(c.farmCount(), 0);
        vm.expectRevert();
        c.farmIdAt(0);
        assertFalse(c.farmIdsContains(0));
        vm.expectRevert();
        c.adapterOf(IMultiVaultStorage.Protocol.SYMBIOTIC);
        vm.expectRevert();
        c.adapterOf(IMultiVaultStorage.Protocol.EIGEN_LAYER);
        vm.expectRevert();
        c.adapterOf(IMultiVaultStorage.Protocol.ERC4626);
    }

    function testInitializer() external {
        MockMultiVaultStorage c = new MockMultiVaultStorage("test", 1);
        assertNotEq(address(c), address(0));

        c.initializeMultiVaultStorage(
            address(1), address(2), address(3), address(4), address(5), address(6), address(7)
        );

        assertEq(address(c.depositStrategy()), address(1));
        assertEq(address(c.withdrawalStrategy()), address(2));
        assertEq(address(c.rebalanceStrategy()), address(3));
        assertEq(address(c.defaultCollateral()), address(4));
        assertEq(address(c.symbioticAdapter()), address(5));
        assertEq(address(c.eigenLayerAdapter()), address(6));
        assertEq(address(c.erc4626Adapter()), address(7));
    }

    function testAddSubvault() external {
        MockMultiVaultStorage c = new MockMultiVaultStorage("test", 1);
        assertNotEq(address(c), address(0));

        c.initializeMultiVaultStorage(
            address(1), address(2), address(3), address(4), address(5), address(6), address(7)
        );
        c.addSubvault(address(8), address(9), IMultiVaultStorage.Protocol.ERC4626);

        assertEq(c.subvaultsCount(), 1);
        IMultiVaultStorage.Subvault memory subvault = c.subvaultAt(0);
        assertEq(uint256(subvault.protocol), uint256(IMultiVaultStorage.Protocol.ERC4626));
        assertEq(subvault.vault, address(8));
        assertEq(subvault.withdrawalQueue, address(9));
        assertEq(c.indexOfSubvault(address(8)), 1);

        vm.expectRevert("MultiVaultStorage: subvault already exists");
        c.addSubvault(address(8), address(9), IMultiVaultStorage.Protocol.ERC4626);
    }

    function testRemoveSubvault() external {
        MockMultiVaultStorage c = new MockMultiVaultStorage("test", 1);
        assertNotEq(address(c), address(0));

        c.initializeMultiVaultStorage(
            address(1), address(2), address(3), address(4), address(5), address(6), address(7)
        );
        c.addSubvault(address(8), address(9), IMultiVaultStorage.Protocol.ERC4626);
        c.addSubvault(address(10), address(11), IMultiVaultStorage.Protocol.EIGEN_LAYER);

        assertEq(c.subvaultsCount(), 2);

        vm.expectRevert("MultiVaultStorage: subvault already exists");
        c.addSubvault(address(8), address(9), IMultiVaultStorage.Protocol.ERC4626);

        c.removeSubvault(address(8));
        assertEq(c.subvaultsCount(), 1);
        assertEq(c.indexOfSubvault(address(8)), 0);
        assertEq(c.indexOfSubvault(address(10)), 1);

        vm.expectRevert("MultiVaultStorage: subvault not found");
        c.removeSubvault(address(8));

        c.removeSubvault(address(10));
        assertEq(c.subvaultsCount(), 0);
    }

    function testSetRewardsData() external {
        MockMultiVaultStorage c = new MockMultiVaultStorage("test", 1);
        assertNotEq(address(c), address(0));

        c.initializeMultiVaultStorage(
            address(1), address(2), address(3), address(4), address(5), address(6), address(7)
        );

        IMultiVaultStorage.RewardData memory rewardData;

        c.setRewardData(0, rewardData);
        assertEq(c.farmCount(), 0);

        rewardData.token = address(12);
        c.setRewardData(0, rewardData);
        assertEq(c.farmCount(), 1);
        assertEq(c.farmIdAt(0), 0);
        vm.expectRevert();
        c.farmIdAt(1);

        rewardData.token = address(13);
        c.setRewardData(0, rewardData);
        assertEq(c.farmCount(), 1);
        assertEq(c.farmIdAt(0), 0);
        vm.expectRevert();
        c.farmIdAt(1);

        rewardData.token = address(12);
        c.setRewardData(1, rewardData);
        assertEq(c.farmCount(), 2);
        assertEq(c.farmIdAt(0), 0);
        assertEq(c.farmIdAt(1), 1);
        vm.expectRevert();
        c.farmIdAt(2);

        rewardData.token = address(0);
        c.setRewardData(0, rewardData);
        assertEq(c.farmCount(), 1);
        assertEq(c.farmIdAt(0), 1);
        vm.expectRevert();
        c.farmIdAt(1);

        c.setRewardData(1, rewardData);
        assertEq(c.farmCount(), 0);
        vm.expectRevert();
        c.farmIdAt(0);
    }
}
