// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Lender } from "../../contracts/lendingPool/Lender.sol";

import { DebtToken } from "../../contracts/lendingPool/tokens/DebtToken.sol";
import { TestDeployer } from "../deploy/TestDeployer.sol";

import { MockNetworkMiddleware } from "../mocks/MockNetworkMiddleware.sol";
import { console } from "forge-std/console.sol";

contract LenderBorrowTest is TestDeployer {
    address user_agent;

    /*function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);
        _initSymbioticVaultsLiquidity(env);

        user_agent = _getRandomAgent();

        vm.startPrank(env.symbiotic.users.vault_admin);
        _symbioticVaultDelegateToAgent(symbioticWethVault, env.symbiotic.networkAdapter, user_agent, 2_000e18);
        _symbioticVaultDelegateToAgent(symbioticUsdtVault, env.symbiotic.networkAdapter, user_agent, 1_000_000e6);

        // have something to repay
        vm.startPrank(user_agent);
        lender.borrow(address(usdc), 100e6, user_agent);
        usdc.approve(address(lender), 100e6);
        vm.stopPrank();
    }

    function test_gas_lender_borrow() public {
        vm.startPrank(user_agent);

        lender.borrow(address(usdc), 100e6, user_agent);
        vm.snapshotGasLastCall("Lender.gas.t", "simple_borrow");
    }

    function test_gas_lender_repay() public {
        vm.startPrank(user_agent);

        lender.repay(address(usdc), 10e6, user_agent);
        vm.snapshotGasLastCall("Lender.gas.t", "simple_repay");
    }*/
}
