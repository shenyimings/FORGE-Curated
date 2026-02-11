// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {Factory} from "src/Factory.sol";
import {DistributorFactory} from "src/factories/DistributorFactory.sol";
import {StvPoolFactory} from "src/factories/StvPoolFactory.sol";
import {StvStETHPoolFactory} from "src/factories/StvStETHPoolFactory.sol";
import {TimelockFactory} from "src/factories/TimelockFactory.sol";
import {WithdrawalQueueFactory} from "src/factories/WithdrawalQueueFactory.sol";

contract DeployFactory is Script {
    function _deployImplFactories() internal returns (Factory.SubFactories memory f) {
        f.stvPoolFactory = address(new StvPoolFactory());
        f.stvStETHPoolFactory = address(new StvStETHPoolFactory());
        f.withdrawalQueueFactory = address(new WithdrawalQueueFactory());
        f.distributorFactory = address(new DistributorFactory());
        f.timelockFactory = address(new TimelockFactory());
    }

    function _writeArtifacts(
        Factory.SubFactories memory _subFactories,
        address _factoryAddr,
        string memory _outputJsonPath
    ) internal {
        string memory factoriesSection = "";
        factoriesSection = vm.serializeAddress("factories", "stvPoolFactory", _subFactories.stvPoolFactory);
        factoriesSection = vm.serializeAddress("factories", "stvStETHPoolFactory", _subFactories.stvStETHPoolFactory);
        factoriesSection =
            vm.serializeAddress("factories", "withdrawalQueueFactory", _subFactories.withdrawalQueueFactory);
        factoriesSection = vm.serializeAddress("factories", "distributorFactory", _subFactories.distributorFactory);
        factoriesSection = vm.serializeAddress("factories", "timelockFactory", _subFactories.timelockFactory);

        string memory out = "";
        out = vm.serializeAddress("deployment", "factory", _factoryAddr);
        out = vm.serializeString("deployment", "network", vm.toString(block.chainid));

        string memory json = vm.serializeString("_root", "factories", factoriesSection);
        json = vm.serializeString("_root", "deployment", out);

        vm.writeJson(json, _outputJsonPath);
        vm.writeJson(json, "deployments/pool-factory-latest.json");
    }

    function _readFactoryConfig(string memory _paramsPath) internal view returns (address locator) {
        require(
            vm.isFile(_paramsPath),
            string(abi.encodePacked("FACTORY_PARAMS_JSON file does not exist at: ", _paramsPath))
        );
        string memory json = vm.readFile(_paramsPath);

        locator = vm.parseJsonAddress(json, "$.lidoLocator");

        require(locator != address(0), "lidoLocator missing");
    }

    function run() external {
        // Expect environment variable for non-interactive deploys
        // REQUIRED: FACTORY_PARAMS_JSON (path to config with factory deployment params)
        string memory paramsJsonPath = vm.envString("FACTORY_PARAMS_JSON");
        require(bytes(paramsJsonPath).length != 0, "FACTORY_PARAMS_JSON env var must be set and non-empty");

        string memory outputJsonPath = string(
            abi.encodePacked(
                "deployments/pool-factory-", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".json"
            )
        );

        // Read all factory configuration from JSON file
        (address locatorAddress) = _readFactoryConfig(paramsJsonPath);

        vm.startBroadcast();

        // Deploy implementation factories and proxy stub
        Factory.SubFactories memory subFactories = _deployImplFactories();

        Factory factory = new Factory(locatorAddress, subFactories);

        vm.stopBroadcast();

        // Write artifacts
        _writeArtifacts(subFactories, address(factory), outputJsonPath);

        console2.log("Deployed Factory at", address(factory));
        console2.log("Output written to", outputJsonPath);
        console2.log("Also updated", "deployments/pool-factory-latest.json");
    }
}
