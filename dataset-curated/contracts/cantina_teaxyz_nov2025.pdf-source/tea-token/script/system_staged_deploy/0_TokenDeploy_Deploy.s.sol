// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseScript } from "../Base.s.sol";
import { DeterministicDeployer } from "../../src/utils/DeterministicDeployer.sol";
import { TokenDeploy } from "../../src/TeaToken/TokenDeploy.sol";

contract TeaTokenDeployScript is BaseScript {
    function run() public broadcaster {
        string memory seed = vm.readFile("script/system_staged_deploy/data/seed.json");

        address teaTreasuryMultisig = abi.decode(vm.parseJson(seed, ".teaTreasuryMultisig"), (address));
        bytes32 salt = abi.decode(vm.parseJson(seed, ".teaSalt"), (bytes32));

        address tokenDeploy =
            DeterministicDeployer._deploy(salt, type(TokenDeploy).creationCode, abi.encode(teaTreasuryMultisig));

        string memory deployments = "deployments";
        deployments = vm.serializeAddress(deployments, "tokenDeployAddress", tokenDeploy);

        vm.writeJson(deployments, string.concat("script/system_staged_deploy/data/TokenDeploy.json"));
    }
}
