// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import "../src/SecurityValidator.sol";
import "../test/helpers/DummyVault.sol";
import {EthereumVaultConnector} from "evc/EthereumVaultConnector.sol";

contract DeployerScript is Script {
    function run() public {
        string memory deployerPrivateKeyStr = vm.envString("DEPLOY_KEY");
        uint256 deployer = vm.parseUint(deployerPrivateKeyStr);
        vm.startBroadcast(deployer);

        // 0x875A57917E46A440c71d9EC6F6B5c8B772D6C895 - dev attester
        uint256 attesterPrivateKey = vm.parseUint("0x14e000d8d8aaad9595be9d90b2c35097f00a3bb3882183035788fdf5acf7192e");
        address attester = vm.addr(attesterPrivateKey);

        SecurityValidator validator = new SecurityValidator(address(0));
        EthereumVaultConnector evc = new EthereumVaultConnector();
        DummyVault vault = new DummyVault(ISecurityValidator(address(validator)));
        console.log("validator contract:", address(validator));
        console.log("evc contract:", address(evc));
        console.log("vault contract:", address(vault));

        vm.stopBroadcast();
    }
}
