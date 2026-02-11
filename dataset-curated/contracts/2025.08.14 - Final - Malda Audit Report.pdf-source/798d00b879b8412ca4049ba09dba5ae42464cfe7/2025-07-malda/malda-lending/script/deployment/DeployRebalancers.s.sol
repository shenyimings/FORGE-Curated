// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {Roles} from "src/Roles.sol";
import {Rebalancer} from "src/rebalancer/Rebalancer.sol";
import {DeployRebalancer} from "script/deployment/rebalancer/DeployRebalancer.s.sol";
import {DeployEverclearBridge} from "script/deployment/rebalancer/DeployEverclearBridge.s.sol";
import {RebalancersDeployConfig} from "../deployers/Types.sol";

contract DeployRebalancers is Script {
    using stdJson for string;

    DeployRebalancer deployRebalancer;
    DeployEverclearBridge deployEverclearBridge;

    string[] public networks;
    string public configPath = "deployment-rebalancer-config.json";
    mapping(string => RebalancersDeployConfig) public configs;

    function setUp() public {
        networks = vm.parseJsonKeys(vm.readFile(configPath), ".networks");
        for (uint256 i; i < networks.length;) {
            string memory network = networks[i];
            _parseConfig(network);

            unchecked {
                ++i;
            }
        }
    }

    function run() public {
        string memory json = vm.readFile(configPath);
        string[] memory _networks = vm.parseJsonKeys(json, ".networks");

        // Deploy to all networks
        for (uint256 i; i < _networks.length;) {
            string memory network = _networks[i];
            console.log("\n=== Deploying to %s ===", network);

            RebalancersDeployConfig memory config = configs[network];

            vm.createSelectFork(network);

            _initializeDeployers();

            address deployedRebalancer = _deployRebalancer(config.roles, config.deployer);
            address deployedBridge =
                _deployEverclearBridge(config.roles, config.bridges.everclear.spoke, config.deployer);

            Roles roleContract = Roles(config.roles);

            // set REBALANCER_EOA role
            address rebalancerEOA = vm.envAddress("DEPLOYER_ADMIN_ADDRESS");
            bool hasEOARole = roleContract.isAllowedFor(rebalancerEOA, roleContract.REBALANCER_EOA());
            if (!hasEOARole) {
                vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
                roleContract.allowFor(vm.envAddress("DEPLOYER_ADMIN_ADDRESS"), roleContract.REBALANCER_EOA(), true);
                vm.stopBroadcast();
            }

            // set GUARDIAN_BRIDGE role
            address guardianBridge = vm.envAddress("DEPLOYER_ADMIN_ADDRESS");
            bool hasGuardianBridge = roleContract.isAllowedFor(guardianBridge, roleContract.GUARDIAN_BRIDGE());
            if (!hasGuardianBridge) {
                vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
                roleContract.allowFor(vm.envAddress("DEPLOYER_ADMIN_ADDRESS"), roleContract.GUARDIAN_BRIDGE(), true);
                vm.stopBroadcast();
            }

            // set GUARDIAN_BRIDGE
            // -- add bridge to whitelist
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            Rebalancer(deployedRebalancer).setWhitelistedBridgeStatus(deployedBridge, true);
            vm.stopBroadcast();

            // -- add role for rebalancer
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            roleContract.allowFor(address(deployedRebalancer), roleContract.REBALANCER(), true);
            vm.stopBroadcast();

            unchecked {
                ++i;
            }
        }
    }

    function _initializeDeployers() private {
        deployRebalancer = new DeployRebalancer();
        deployEverclearBridge = new DeployEverclearBridge();
    }

    function _deployRebalancer(address roles, address deployer) private returns (address) {
        console.log("Deploying Rebalancer");
        address result = deployRebalancer.run(roles, vm.envAddress("PUBLIC_KEY"), Deployer(payable(deployer)));
        console.log("Rebalancer deployed at:", result);
        return result;
    }

    function _deployEverclearBridge(address roles, address spoke, address deployer) private returns (address) {
        console.log("Deploying Everclear bridge");
        address result = deployEverclearBridge.run(roles, spoke, Deployer(payable(deployer)));
        console.log("Everclear bridge deployed at: ");
        return result;
    }

    function _parseConfig(string memory network) private returns (RebalancersDeployConfig memory) {
        RebalancersDeployConfig memory config;
        string memory json = vm.readFile(configPath);
        string memory networkPath = string.concat(".networks.", network);

        config.chainId = uint32(abi.decode(json.parseRaw(string.concat(networkPath, ".chainId")), (uint256)));
        config.deployer = abi.decode(json.parseRaw(string.concat(networkPath, ".deployer")), (address));
        config.roles = abi.decode(json.parseRaw(string.concat(networkPath, ".roles")), (address));
        config.bridges.everclear.spoke =
            abi.decode(json.parseRaw(string.concat(networkPath, ".bridges.everclear.spoke")), (address));

        configs[network] = config;
        return config;
    }
}
