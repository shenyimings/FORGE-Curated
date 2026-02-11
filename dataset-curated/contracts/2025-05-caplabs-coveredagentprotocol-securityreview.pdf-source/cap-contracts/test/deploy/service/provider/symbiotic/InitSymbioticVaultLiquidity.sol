// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { SymbioticUtils } from "../../../../../contracts/deploy/utils/SymbioticUtils.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { TestEnvConfig, TestUsersConfig } from "../../../interfaces/TestDeployConfig.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { InfraConfig } from "../../../interfaces/TestDeployConfig.sol";
import { TimeUtils } from "../../../utils/TimeUtils.sol";
import { IVault } from "@symbioticfi/core/src/interfaces/vault/IVault.sol";

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

contract InitSymbioticVaultLiquidity is Test, SymbioticUtils, TimeUtils {
    function _initSymbioticVaultsLiquidity(TestEnvConfig memory env) internal {
        for (uint256 i = 0; i < env.symbiotic.vaults.length; i++) {
            address vault = env.symbiotic.vaults[i];
            _initSymbioticVaultLiquidityForAgent(env.testUsers, vault, 30_000);
        }

        _timeTravel(28 days);
    }

    function _initSymbioticVaultLiquidityForAgent(
        TestUsersConfig memory testUsers,
        address vault,
        uint256 amountNoDecimals
    ) internal returns (uint256 depositedAmount, uint256 mintedShares) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        address collateral = IVault(vault).collateral();
        uint256 amount = amountNoDecimals * 10 ** MockERC20(collateral).decimals();

        for (uint256 i = 0; i < testUsers.restakers.length; i++) {
            address restaker = testUsers.restakers[i];
            vm.startPrank(restaker);
            MockERC20(collateral).mint(restaker, amount);
            MockERC20(collateral).approve(address(vault), amount);
            (depositedAmount, mintedShares) = IVault(vault).deposit(restaker, amount);
        }
    }
}
