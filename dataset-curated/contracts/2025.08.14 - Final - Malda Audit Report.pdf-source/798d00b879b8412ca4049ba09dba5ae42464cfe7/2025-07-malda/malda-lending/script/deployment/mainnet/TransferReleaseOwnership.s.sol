// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Operator} from "src/Operator/Operator.sol";
import {BatchSubmitter} from "src/mToken/BatchSubmitter.sol";
import {Roles} from "src/Roles.sol";
import {Pauser} from "src/pauser/Pauser.sol";
import {IOwnable} from "src/interfaces/IOwnable.sol";

import {
    DeployConfig,
    MarketRelease,
    Role,
    InterestConfig,
    OracleConfigRelease,
    OracleFeed
} from "../../deployers/Types.sol";

import {DeployBaseRelease} from "../../deployers/DeployBaseRelease.sol";

interface IAdmin {
    function setPendingAdmin(address newAdmin) external;
}

contract TransferReleaseOwnership is DeployBaseRelease {
    using stdJson for string;

    address[] marketList;
    address pauser;
    address batchSubmitter;
    address timelockController;
    address rewardDistributor;
    address zkVerifier;
    address rebalancer;
    address acrossBridge;
    address everclearBridge;
    address rolesContract;
    address oracle;
    address operator;
    address deployer;
    address gasHelper;

    function setUp() public override {
        configPath = "deployment-config-release.json";
        super.setUp();

        string memory marketsOutputPath = "script/output/release-deployed-market-addresses.json";
        string memory rawMarketJson = vm.readFile(marketsOutputPath);
        uint256 length = vm.parseJson(rawMarketJson, "").length;
        marketList = new address[](length);
        for (uint256 i; i < length; ++i) {
            string memory base = string.concat("[", vm.toString(i), "]");

            address marketAddr = vm.parseJsonAddress(rawMarketJson, string.concat(base, ".address"));
            marketList.push(marketAddr);
        }

        string memory corePath = "script/output/release-deployed-core-addresses.json";
        pauser = vm.parseJsonAddress(corePath, ".Pauser");
        batchSubmitter = vm.parseJsonAddress(corePath, ".BatchSubmitter");
        rewardDistributor = vm.parseJsonAddress(corePath, ".RewardDistributor");
        zkVerifier = vm.parseJsonAddress(corePath, ".ZkVerifier");
        rolesContract = vm.parseJsonAddress(corePath, ".Roles");
        operator = vm.parseJsonAddress(corePath, ".Operator");
        deployer = vm.parseJsonAddress(corePath, ".Deployer");
        gasHelper = vm.parseJsonAddress(corePath, ".DefaultGasHelper");
    }

    function run() public {
        // Deploy to all networks
        for (uint256 i = 0; i < networks.length; i++) {
            string memory network = networks[i];
            console.log("\n=== Configuring %s ===", network);

            // Create fork for this network
            forks[network] = vm.createSelectFork(network);

            uint256 key = vm.envUint("PRIVATE_KEY");
            vm.startBroadcast(key);

            // Transfer ownerhip
            console.log("Transfer ownership to", configs[network].ownership);

            console.log(" -- for Deployer");
            IAdmin(deployer).setPendingAdmin(configs[network].ownership);
            console.log(" -- for Pauser");
            IOwnable(pauser).transferOwnership(configs[network].ownership);
            console.log(" -- for BatchSubmitter");
            IOwnable(batchSubmitter).transferOwnership(configs[network].ownership);
            console.log(" -- for RewardDistributor");
            IOwnable(rewardDistributor).transferOwnership(configs[network].ownership);
            console.log(" -- for ZkVerifier");
            IOwnable(zkVerifier).transferOwnership(configs[network].ownership);
            console.log(" -- for Roles");
            IOwnable(rolesContract).transferOwnership(configs[network].ownership);
            if (configs[network].isHost) {
                console.log(" HOST");
                console.log(" -- for Operator");
                IOwnable(operator).transferOwnership(configs[network].ownership);
                console.log(" -- for DefaultGasHelper");
                IOwnable(gasHelper).transferOwnership(configs[network].ownership);
                for (uint256 j; j < marketList.length; ++j) {
                    console.log(" -- for market: ", marketList[i]);
                    IAdmin(marketList[j]).setPendingAdmin(configs[network].ownership);
                }
            } else {
                console.log(" EXTENSION");
                for (uint256 j; j < marketList.length; ++j) {
                    console.log(" -- for market: ", marketList[j]);
                    IOwnable(marketList[j]).transferOwnership(configs[network].ownership);
                }
            }

            vm.stopBroadcast();
            console.log("-------------------- DONE");
        }
    }
}
