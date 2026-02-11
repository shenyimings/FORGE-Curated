// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "forge-std/Script.sol";
import {AlphaProVault, VaultParams} from "../contracts/AlphaProVault.sol";
import {AlphaProVaultFactory} from "../contracts/AlphaProVaultFactory.sol";
import {Constants} from "../test/Constants.sol";

contract DeployCharmScript is Script, Test {
    function run() external {
        uint256 deployerPK = vm.envUint("PK_DEPLOYER");
        address deployerAddr = vm.addr(deployerPK);

        vm.startBroadcast(deployerPK);

        AlphaProVault alphaProVault = new AlphaProVault();

        AlphaProVaultFactory alphaProVaultFactory =
            new AlphaProVaultFactory(address(alphaProVault), deployerAddr, uint24(Constants.PROTOCOL_FEE));

        vm.stopBroadcast();

        emit log_string("Successfully deployed");
        emit log_named_address("alphaProVault", address(alphaProVault));
        emit log_named_address("alphaProVaultFactory", address(alphaProVaultFactory));
    }
}
