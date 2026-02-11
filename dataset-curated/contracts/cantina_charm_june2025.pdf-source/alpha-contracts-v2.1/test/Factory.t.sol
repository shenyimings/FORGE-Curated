// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AlphaProVault, VaultParams} from "../contracts/AlphaProVault.sol";
import {AlphaProVaultFactory} from "../contracts/AlphaProVaultFactory.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {VaultTestUtils} from "./VaultTestUtils.sol";

contract FactoryTest is Test, VaultTestUtils {
    function setUp() public {
        vm.createSelectFork(vm.envString("ALCHEMY_RPC"), 17073835);
    }

    function test_constructor_checks() internal {
        AlphaProVault templateVault = new AlphaProVault();
        vaultFactory = new AlphaProVaultFactory(address(templateVault), owner, PROTOCOL_FEE);

        address pool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(WETH, USDC, POOL_FEE);

        VaultParams memory vaultParams =
            VaultParams(pool, owner, 0, 100, 2400, 1200, 300000, 72000, 86400, 100, 200, 60, "N", "S");

        vm.startPrank(owner);

        {
            vm.expectRevert("allowedFactories");
            vaultFactory.createVault(vaultParams);

            vaultFactory.setAllowedFactory(UNISWAP_V3_FACTORY, true);
            vaultFactory.createVault(vaultParams);
        }

        {
            VaultParams memory vaultParamsInvalid = vaultParams;
            vaultParamsInvalid.baseThreshold = 0;

            vm.expectRevert("threshold must be > 0");
            vaultFactory.createVault(vaultParamsInvalid);
        }

        {
            VaultParams memory vaultParamsInvalid = vaultParams;
            vaultParamsInvalid.limitThreshold = 0;

            vm.expectRevert("threshold must be > 0");
            vaultFactory.createVault(vaultParamsInvalid);
        }

        {
            VaultParams memory vaultParamsInvalid = vaultParams;
            vaultParamsInvalid.wideRangeWeight = 1e6 + 1;

            vm.expectRevert("wideRangeWeight must be <= 1e6");
            vaultFactory.createVault(vaultParamsInvalid);
        }

        {
            VaultParams memory vaultParamsInvalid = vaultParams;
            vaultParamsInvalid.minTickMove = -1;

            // NOTE: You can ensure this just by making minTickMove uint24
            vm.expectRevert("minTickMove must be <= 1e6");
            vaultFactory.createVault(vaultParamsInvalid);
        }

        {
            VaultParams memory vaultParamsInvalid = vaultParams;
            vaultParamsInvalid.maxTwapDeviation = 1e6 + 1;

            vm.expectRevert("minTickMove must be <= 1e6");
            vaultFactory.createVault(vaultParamsInvalid);
        }

        {
            VaultParams memory vaultParamsInvalid = vaultParams;
            vaultParamsInvalid.twapDuration = 0;

            vm.expectRevert("twapDuration must be > 0");
            vaultFactory.createVault(vaultParamsInvalid);
        }

        vm.stopPrank();
    }
}
