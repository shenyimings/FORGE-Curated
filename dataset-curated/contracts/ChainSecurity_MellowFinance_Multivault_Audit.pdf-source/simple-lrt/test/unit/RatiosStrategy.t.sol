// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../BaseTest.sol";
import "../mocks/MockMultiVault.sol";

contract Unit is BaseTest {
    using RandomLib for RandomLib.Storage;

    uint256 ITERATIONS = 100;

    function testConstructor() external {
        RatiosStrategy c = new RatiosStrategy();
        assertNotEq(address(c), address(0));
    }

    function testSetRatios() external {
        RatiosStrategy c = new RatiosStrategy();
        assertNotEq(address(c), address(0));

        MockMultiVault vault = new MockMultiVault();

        vm.expectRevert("RatiosStrategy: forbidden");
        c.setRatios(address(vault), new address[](0), new IRatiosStrategy.Ratio[](0));
        vault.setFlag(true);

        vm.expectRevert("RatiosStrategy: subvaults and ratios length mismatch");
        c.setRatios(address(vault), new address[](10), new IRatiosStrategy.Ratio[](9));

        {
            (uint64 minRatioD18, uint64 maxRatioD18) = c.ratios(address(vault), address(0));
            assertEq(minRatioD18, 0);
            assertEq(maxRatioD18, 0);
        }

        {
            address[] memory subvaults = new address[](1);
            subvaults[0] = rnd.randAddress();
            MockMultiVault.Data[] memory data = new MockMultiVault.Data[](1);
            data[0].vault = subvaults[0];
            vault.setSubvaults(data);
            IRatiosStrategy.Ratio[] memory ratios = new IRatiosStrategy.Ratio[](1);
            ratios[0] = IRatiosStrategy.Ratio(uint64(1 ether) / 3, uint64(1 ether) / 2);
            c.setRatios(address(vault), subvaults, ratios);
        }

        {
            address[] memory subvaults = new address[](1);
            subvaults[0] = rnd.randAddress();
            MockMultiVault.Data[] memory data = new MockMultiVault.Data[](1);
            data[0].vault = subvaults[0];
            vault.setSubvaults(data);
            IRatiosStrategy.Ratio[] memory ratios = new IRatiosStrategy.Ratio[](1);
            ratios[0] = IRatiosStrategy.Ratio(uint64(1 ether) / 3, uint64(1 ether) / 2);
            vm.expectRevert("RatiosStrategy: invalid subvault");
            c.setRatios(address(vault), new address[](1), ratios);
        }

        {
            address[] memory subvaults = new address[](1);
            subvaults[0] = rnd.randAddress();
            MockMultiVault.Data[] memory data = new MockMultiVault.Data[](1);
            data[0].vault = subvaults[0];
            vault.setSubvaults(data);
            IRatiosStrategy.Ratio[] memory ratios = new IRatiosStrategy.Ratio[](1);
            ratios[0] = IRatiosStrategy.Ratio(uint64(1 ether) / 3, uint64(1 ether) + 1);
            vm.expectRevert("RatiosStrategy: invalid ratios");
            c.setRatios(address(vault), subvaults, ratios);
            ratios[0] = IRatiosStrategy.Ratio(uint64(1 ether) / 3, uint64(1 ether) / 5);
            vm.expectRevert("RatiosStrategy: invalid ratios");
            c.setRatios(address(vault), subvaults, ratios);
            vm.expectRevert("RatiosStrategy: invalid subvault");
            c.setRatios(address(vault), new address[](1), ratios);
            ratios[0].minRatioD18 = 0;
            vm.expectRevert("RatiosStrategy: invalid subvault");
            c.setRatios(address(vault), new address[](1), ratios);
            ratios[0].maxRatioD18 = 0;
            c.setRatios(address(vault), new address[](1), ratios);
        }
    }

    function testCalculateState() external {
        RatiosStrategy c = new RatiosStrategy();
        assertNotEq(address(c), address(0));

        MockMultiVault vault = new MockMultiVault();
        vault.setAsset(Constants.WSTETH());
        vault.setDefaultCollateral(Constants.WSTETH_SYMBIOTIC_COLLATERAL());
        vault.setFlag(true);

        for (uint256 i = 0; i < ITERATIONS; i++) {
            uint256 n = rnd.randInt(1, 20);
            MockMultiVault.Data[] memory data = new MockMultiVault.Data[](n);
            IRatiosStrategy.Ratio[] memory ratios = new IRatiosStrategy.Ratio[](n);
            address[] memory subvaults = new address[](n);
            uint256 totalAssets = 0;
            for (uint256 j = 0; j < n; j++) {
                data[j].vault = rnd.randAddress();
                subvaults[j] = data[j].vault;
                data[j].deposit = rnd.randInt(1 ether);
                data[j].pending = rnd.randInt(1 ether);
                data[j].claimable = rnd.randInt(1 ether);
                data[j].staked = rnd.randInt(1 ether);
                ratios[j] = IRatiosStrategy.Ratio(
                    uint64(rnd.randInt(1 ether)), uint64(rnd.randInt(1 ether))
                );
                totalAssets += data[j].claimable + data[j].pending + data[j].staked;
                if (ratios[j].maxRatioD18 < ratios[j].minRatioD18) {
                    uint64 tmp = ratios[j].maxRatioD18;
                    ratios[j].maxRatioD18 = ratios[j].minRatioD18;
                    ratios[j].minRatioD18 = tmp;
                }
            }
            vault.setSubvaults(data);
            c.setRatios(address(vault), subvaults, ratios);

            uint256 liquidAssets = rnd.randInt(1 ether);
            uint256 liquidCollaterals = rnd.randInt(1 ether);
            deal(Constants.WSTETH(), address(vault), liquidAssets);
            deal(Constants.WSTETH_SYMBIOTIC_COLLATERAL(), address(vault), liquidCollaterals);
            totalAssets += liquidAssets + liquidCollaterals;
            bool isDeposit = rnd.randBool();
            uint256 actionValue = rnd.randInt(isDeposit ? totalAssets * 2 : totalAssets);
            (IRatiosStrategy.Amounts[] memory state, uint256 liquid) =
                c.calculateState(address(vault), isDeposit, actionValue);
            assertEq(
                liquidAssets + liquidCollaterals,
                liquid,
                "liquidAssets + liquidCollaterals == liquid"
            );
            assertEq(state.length, n, "state.length == n");
            totalAssets = isDeposit ? totalAssets + actionValue : totalAssets - actionValue;
            for (uint256 j = 0; j < state.length; j++) {
                assertEq(
                    state[j].claimable, data[j].claimable, "state[j].claimable == data[j].claimable"
                );
                assertEq(state[j].pending, data[j].pending, "state[j].pending == data[j].pending");
                assertEq(state[j].staked, data[j].staked, "state[j].staked == data[j].staked");
                uint256 maxAssets = data[j].staked + data[j].deposit;
                assertEq(
                    state[j].min,
                    Math.min(Math.mulDiv(totalAssets, ratios[j].minRatioD18, 1 ether), maxAssets),
                    "state[j].min"
                );
                assertEq(
                    state[j].max,
                    Math.min(Math.mulDiv(totalAssets, ratios[j].maxRatioD18, 1 ether), maxAssets),
                    "state[j].max"
                );
            }
        }
    }

    function testCalculateDepositAmounts() external {
        RatiosStrategy c = new RatiosStrategy();
        assertNotEq(address(c), address(0));

        MockMultiVault vault = new MockMultiVault();
        vault.setAsset(Constants.WSTETH());
        vault.setDefaultCollateral(Constants.WSTETH_SYMBIOTIC_COLLATERAL());
        vault.setFlag(true);

        for (uint256 i = 0; i < ITERATIONS; i++) {
            uint256 n = rnd.randInt(1, 20);
            MockMultiVault.Data[] memory data = new MockMultiVault.Data[](n);
            IRatiosStrategy.Ratio[] memory ratios = new IRatiosStrategy.Ratio[](n);
            address[] memory subvaults = new address[](n);
            uint256 totalAssets = 0;
            for (uint256 j = 0; j < n; j++) {
                data[j].vault = rnd.randAddress();
                subvaults[j] = data[j].vault;
                data[j].deposit = rnd.randBool() ? 0 : rnd.randInt(1 ether);
                data[j].pending = rnd.randInt(1 ether);
                data[j].claimable = rnd.randInt(1 ether);
                data[j].staked = rnd.randInt(1 ether);
                ratios[j] = IRatiosStrategy.Ratio(
                    uint64(rnd.randInt(1 ether)), uint64(rnd.randInt(1 ether))
                );
                totalAssets += data[j].claimable + data[j].pending + data[j].staked;
                if (ratios[j].maxRatioD18 < ratios[j].minRatioD18) {
                    uint64 tmp = ratios[j].maxRatioD18;
                    ratios[j].maxRatioD18 = ratios[j].minRatioD18;
                    ratios[j].minRatioD18 = tmp;
                }
            }
            vault.setSubvaults(data);
            c.setRatios(address(vault), subvaults, ratios);

            uint256 liquidAssets = rnd.randInt(1 ether);
            uint256 liquidCollaterals = rnd.randInt(1 ether);
            deal(Constants.WSTETH(), address(vault), liquidAssets);
            deal(Constants.WSTETH_SYMBIOTIC_COLLATERAL(), address(vault), liquidCollaterals);
            totalAssets += liquidAssets + liquidCollaterals;
            uint256 actionValue = rnd.randInt(totalAssets * 2);
            (IDepositStrategy.DepositData[] memory depositData) =
                c.calculateDepositAmounts(address(vault), actionValue);
            assertLe(depositData.length, n, "state.length <= n");
            totalAssets += actionValue;
            uint256 subvaultsState = 0;
            for (uint256 j = 0; j < depositData.length; j++) {
                if (j > 0) {
                    assertLt(depositData[j - 1].subvaultIndex, depositData[j].subvaultIndex);
                }
                uint256 maxAssets = data[j].staked + data[j].deposit;
                uint256 min_ =
                    Math.min(Math.mulDiv(totalAssets, ratios[j].minRatioD18, 1 ether), maxAssets);
                uint256 max_ =
                    Math.min(Math.mulDiv(totalAssets, ratios[j].maxRatioD18, 1 ether), maxAssets);
            }
        }
    }

    function testCalculateWithdrawalAmounts() external {
        RatiosStrategy c = new RatiosStrategy();
        assertNotEq(address(c), address(0));

        MockMultiVault vault = new MockMultiVault();
        vault.setAsset(Constants.WSTETH());
        vault.setDefaultCollateral(Constants.WSTETH_SYMBIOTIC_COLLATERAL());
        vault.setFlag(true);

        for (uint256 i = 0; i < ITERATIONS; i++) {
            uint256 n = rnd.randInt(1, 20);
            MockMultiVault.Data[] memory data = new MockMultiVault.Data[](n);
            IRatiosStrategy.Ratio[] memory ratios = new IRatiosStrategy.Ratio[](n);
            address[] memory subvaults = new address[](n);
            uint256 totalAssets = 0;
            for (uint256 j = 0; j < n; j++) {
                data[j].vault = rnd.randAddress();
                subvaults[j] = data[j].vault;
                data[j].deposit = rnd.randInt(1 ether);
                data[j].pending = rnd.randInt(1 ether);
                data[j].claimable = rnd.randInt(1 ether);
                data[j].staked = rnd.randInt(1 ether);
                ratios[j] = IRatiosStrategy.Ratio(
                    uint64(rnd.randInt(1 ether)), uint64(rnd.randInt(1 ether))
                );
                totalAssets += data[j].claimable + data[j].pending + data[j].staked;
                if (ratios[j].maxRatioD18 < ratios[j].minRatioD18) {
                    uint64 tmp = ratios[j].maxRatioD18;
                    ratios[j].maxRatioD18 = ratios[j].minRatioD18;
                    ratios[j].minRatioD18 = tmp;
                }
            }
            vault.setSubvaults(data);
            c.setRatios(address(vault), subvaults, ratios);

            uint256 liquidAssets = rnd.randInt(1 ether);
            uint256 liquidCollaterals = rnd.randInt(1 ether);
            deal(Constants.WSTETH(), address(vault), liquidAssets);
            deal(Constants.WSTETH_SYMBIOTIC_COLLATERAL(), address(vault), liquidCollaterals);
            totalAssets += liquidAssets + liquidCollaterals;
            uint256 actionValue = rnd.randInt(totalAssets);
            (IWithdrawalStrategy.WithdrawalData[] memory withdrawalData) =
                c.calculateWithdrawalAmounts(address(vault), actionValue);
            assertLe(withdrawalData.length, n, "state.length <= n");
            totalAssets -= actionValue;
            uint256 subvaultsState = 0;
            for (uint256 j = 0; j < withdrawalData.length; j++) {
                if (j > 0) {
                    assertLt(withdrawalData[j - 1].subvaultIndex, withdrawalData[j].subvaultIndex);
                }
                // uint256 maxAssets = data[j].staked + data[j].deposit;
                // uint256 min_ =
                //     Math.min(Math.mulDiv(totalAssets, ratios[j].minRatioD18, 1 ether), maxAssets);
                // uint256 max_ =
                //     Math.min(Math.mulDiv(totalAssets, ratios[j].maxRatioD18, 1 ether), maxAssets);
            }
        }

        vm.expectRevert();
        c.calculateWithdrawalAmounts(address(vault), type(uint128).max);
    }

    function testCalculateRebalanceAmounts() external {
        RatiosStrategy c = new RatiosStrategy();
        assertNotEq(address(c), address(0));

        MockMultiVault vault = new MockMultiVault();
        vault.setAsset(Constants.WSTETH());
        vault.setDefaultCollateral(Constants.WSTETH_SYMBIOTIC_COLLATERAL());
        vault.setFlag(true);

        for (uint256 i = 0; i < ITERATIONS; i++) {
            uint256 n = rnd.randInt(1, 20);
            MockMultiVault.Data[] memory data = new MockMultiVault.Data[](n);
            IRatiosStrategy.Ratio[] memory ratios = new IRatiosStrategy.Ratio[](n);
            address[] memory subvaults = new address[](n);
            uint256 totalAssets = 0;
            for (uint256 j = 0; j < n; j++) {
                data[j].vault = rnd.randAddress();
                subvaults[j] = data[j].vault;
                data[j].deposit = rnd.randInt(1 ether);
                data[j].pending = rnd.randInt(1 ether);
                data[j].claimable = rnd.randInt(1 ether);
                data[j].staked = rnd.randInt(1 ether);
                ratios[j] = IRatiosStrategy.Ratio(
                    uint64(rnd.randInt(1 ether)), uint64(rnd.randInt(1 ether))
                );
                totalAssets += data[j].claimable + data[j].pending + data[j].staked;
                if (ratios[j].maxRatioD18 < ratios[j].minRatioD18) {
                    uint64 tmp = ratios[j].maxRatioD18;
                    ratios[j].maxRatioD18 = ratios[j].minRatioD18;
                    ratios[j].minRatioD18 = tmp;
                }
            }
            vault.setSubvaults(data);
            c.setRatios(address(vault), subvaults, ratios);

            uint256 liquidAssets = rnd.randInt(1 ether);
            uint256 liquidCollaterals = rnd.randInt(1 ether);
            deal(Constants.WSTETH(), address(vault), liquidAssets);
            deal(Constants.WSTETH_SYMBIOTIC_COLLATERAL(), address(vault), liquidCollaterals);
            totalAssets += liquidAssets + liquidCollaterals;
            (IRebalanceStrategy.RebalanceData[] memory rebalanceData) =
                c.calculateRebalanceAmounts(address(vault));
            assertLe(rebalanceData.length, n, "state.length <= n");
            uint256 subvaultsState = 0;
            for (uint256 j = 0; j < rebalanceData.length; j++) {
                if (j > 0) {
                    assertLt(rebalanceData[j - 1].subvaultIndex, rebalanceData[j].subvaultIndex);
                }
                // uint256 maxAssets = data[j].staked + data[j].deposit;
                // uint256 min_ =
                //     Math.min(Math.mulDiv(totalAssets, ratios[j].minRatioD18, 1 ether), maxAssets);
                // uint256 max_ =
                //     Math.min(Math.mulDiv(totalAssets, ratios[j].maxRatioD18, 1 ether), maxAssets);
            }
        }
    }

    function testCalculateRebalanceAmountsCustomCase() external {
        RatiosStrategy c = new RatiosStrategy();
        assertNotEq(address(c), address(0));

        MockMultiVault vault = new MockMultiVault();
        vault.setAsset(Constants.WSTETH());
        vault.setDefaultCollateral(Constants.WSTETH_SYMBIOTIC_COLLATERAL());
        vault.setFlag(true);

        uint256 n = 2;
        MockMultiVault.Data[] memory data = new MockMultiVault.Data[](n);
        IRatiosStrategy.Ratio[] memory ratios = new IRatiosStrategy.Ratio[](n);
        address[] memory subvaults = new address[](n);
        uint256 totalAssets = 0;

        data[0] = MockMultiVault.Data(rnd.randAddress(), type(uint256).max, 0, 0, 1 ether);
        subvaults[0] = data[0].vault;
        ratios[0] = IRatiosStrategy.Ratio(0 ether, 1 ether);
        totalAssets += data[0].claimable + data[0].pending + data[0].staked;

        data[1] = MockMultiVault.Data(rnd.randAddress(), type(uint256).max, 0, 0, 1 ether);
        subvaults[1] = data[1].vault;
        ratios[1] = IRatiosStrategy.Ratio(0.95 ether, 1 ether);
        totalAssets += data[1].claimable + data[1].pending + data[1].staked;

        vault.setSubvaults(data);
        c.setRatios(address(vault), subvaults, ratios);
        (IRebalanceStrategy.RebalanceData[] memory rebalanceData) =
            c.calculateRebalanceAmounts(address(vault));
        assertLe(rebalanceData.length, n, "state.length <= n");
        uint256 subvaultsState = 0;
        for (uint256 j = 0; j < rebalanceData.length; j++) {
            if (j > 0) {
                assertLt(rebalanceData[j - 1].subvaultIndex, rebalanceData[j].subvaultIndex);
            }
            // uint256 maxAssets = data[j].staked + data[j].deposit;
            // uint256 min_ =
            //     Math.min(Math.mulDiv(totalAssets, ratios[j].minRatioD18, 1 ether), maxAssets);
            // uint256 max_ =
            //     Math.min(Math.mulDiv(totalAssets, ratios[j].maxRatioD18, 1 ether), maxAssets);
        }
    }

    function testCalculateRebalanceAmountsCustomCase2() external {
        RatiosStrategy c = new RatiosStrategy();
        assertNotEq(address(c), address(0));

        MockMultiVault vault = new MockMultiVault();
        vault.setAsset(Constants.WSTETH());
        vault.setDefaultCollateral(Constants.WSTETH_SYMBIOTIC_COLLATERAL());
        vault.setFlag(true);

        uint256 n = 2;
        MockMultiVault.Data[] memory data = new MockMultiVault.Data[](n);
        IRatiosStrategy.Ratio[] memory ratios = new IRatiosStrategy.Ratio[](n);
        address[] memory subvaults = new address[](n);
        uint256 totalAssets = 0;

        data[0] = MockMultiVault.Data(rnd.randAddress(), type(uint256).max, 0, 0, 1 ether);
        subvaults[0] = data[0].vault;
        ratios[0] = IRatiosStrategy.Ratio(0.1 ether, 1 ether);
        totalAssets += data[0].claimable + data[0].pending + data[0].staked;

        data[1] = MockMultiVault.Data(rnd.randAddress(), type(uint256).max, 0, 0, 1 ether);
        subvaults[1] = data[1].vault;
        ratios[1] = IRatiosStrategy.Ratio(0.95 ether, 1 ether);
        totalAssets += data[1].claimable + data[1].pending + data[1].staked;

        vault.setSubvaults(data);
        c.setRatios(address(vault), subvaults, ratios);
        (IRebalanceStrategy.RebalanceData[] memory rebalanceData) =
            c.calculateRebalanceAmounts(address(vault));
        assertLe(rebalanceData.length, n, "state.length <= n");
        uint256 subvaultsState = 0;
        for (uint256 j = 0; j < rebalanceData.length; j++) {
            if (j > 0) {
                assertLt(rebalanceData[j - 1].subvaultIndex, rebalanceData[j].subvaultIndex);
            }
            // uint256 maxAssets = data[j].staked + data[j].deposit;
            // uint256 min_ =
            //     Math.min(Math.mulDiv(totalAssets, ratios[j].minRatioD18, 1 ether), maxAssets);
            // uint256 max_ =
            //     Math.min(Math.mulDiv(totalAssets, ratios[j].maxRatioD18, 1 ether), maxAssets);
        }
    }
}
