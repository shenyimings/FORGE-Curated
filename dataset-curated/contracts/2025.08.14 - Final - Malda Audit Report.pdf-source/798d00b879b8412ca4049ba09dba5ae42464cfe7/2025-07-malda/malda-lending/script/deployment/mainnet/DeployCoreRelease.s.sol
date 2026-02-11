// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {Operator} from "src/Operator/Operator.sol";
import {BatchSubmitter} from "src/mToken/BatchSubmitter.sol";
import {RewardDistributor} from "src/rewards/RewardDistributor.sol";
import {Roles} from "src/Roles.sol";
import {Pauser} from "src/pauser/Pauser.sol";

import {
    DeployConfig,
    MarketRelease,
    Role,
    InterestConfig,
    OracleConfigRelease,
    OracleFeed
} from "../../deployers/Types.sol";

import {DeployBaseRelease} from "../../deployers/DeployBaseRelease.sol";
import {DeployDeployer} from "../../deployers/DeployDeployer.s.sol";
import {DeployRbac} from "../generic/DeployRbac.s.sol";
import {DeployZkVerifier} from "../generic/DeployZkVerifier.s.sol";
import {DeployTimelockController} from "../generic/DeployTimelockController.s.sol";
import {DeployGasHelper} from "../generic/DeployGasHelper.s.sol";
import {DeployPauser} from "../generic/DeployPauser.s.sol";
import {DeployOperator} from "../markets/DeployOperator.s.sol";
import {DeployJumpRateModelV4} from "../interest/DeployJumpRateModelV4.s.sol";
import {DeployRewardDistributor} from "../rewards/DeployRewardDistributor.s.sol";
import {DeployBatchSubmitter} from "../generic/DeployBatchSubmitter.s.sol";
import {DeployMixedPriceOracleV4} from "../oracles/DeployMixedPriceOracleV4.s.sol";
import {DeployRebalancer} from "script/deployment/rebalancer/DeployRebalancer.s.sol";
import {DeployAcrossBridge} from "script/deployment/rebalancer/DeployAcrossBridge.s.sol";
import {DeployEverclearBridge} from "script/deployment/rebalancer/DeployEverclearBridge.s.sol";

import {SetRole} from "../../configuration/SetRole.s.sol";
import {SetOperatorInRewardDistributor} from "../../configuration/SetOperatorInRewardDistributor.s.sol";

contract DeployCoreRelease is DeployBaseRelease {
    using stdJson for string;

    address owner;
    Deployer deployer;

    DeployDeployer deployDeployer;
    DeployRbac deployRbac;
    DeployBatchSubmitter deployBatchSubmitter;
    DeployJumpRateModelV4 deployInterest;
    DeployOperator deployOperator;
    DeployPauser deployPauser;
    DeployMixedPriceOracleV4 deployOracle;
    DeployRewardDistributor deployReward;
    DeployRebalancer deployRebalancer;
    DeployAcrossBridge deployAcrossBridge;
    DeployEverclearBridge deployEverclearBridge;
    DeployZkVerifier deployZkVerifier;
    DeployTimelockController deployTimelockController;
    DeployGasHelper deployGasHelper;
    SetRole setRole;
    SetOperatorInRewardDistributor setOperatorInRewardDistributor;

    function setUp() public override {
        configPath = "deployment-config-release.json";
        super.setUp();

        spokePoolAddresses[1] = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;
        spokePoolAddresses[10] = 0x6f26Bf09B1C792e3228e5467807a900A503c0281;
        spokePoolAddresses[8453] = 0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64;
        spokePoolAddresses[59144] = address(0);

        everclearAddresses[1] = 0xa05A3380889115bf313f1Db9d5f335157Be4D816;
        everclearAddresses[10] = 0xa05A3380889115bf313f1Db9d5f335157Be4D816;
        everclearAddresses[8453] = 0xa05A3380889115bf313f1Db9d5f335157Be4D816;
        everclearAddresses[59144] = 0xc24dC29774fD2c1c0c5FA31325Bb9cbC11D8b751;
    }

    function run() public {
        // Deploy to all networks
        for (uint256 i = 0; i < networks.length; i++) {
            string memory network = networks[i];
            console.log("\n=== Deploying to %s ===", network);

            // Create fork for this network
            forks[network] = vm.createSelectFork(network);

            deployDeployer = new DeployDeployer();
            deployRbac = new DeployRbac();
            deployZkVerifier = new DeployZkVerifier();
            deployTimelockController = new DeployTimelockController();
            deployBatchSubmitter = new DeployBatchSubmitter();
            deployOperator = new DeployOperator();
            deployOracle = new DeployMixedPriceOracleV4();
            deployReward = new DeployRewardDistributor();
            deployRebalancer = new DeployRebalancer();
            deployAcrossBridge = new DeployAcrossBridge();
            deployEverclearBridge = new DeployEverclearBridge();
            setOperatorInRewardDistributor = new SetOperatorInRewardDistributor();
            deployPauser = new DeployPauser();
            deployInterest = new DeployJumpRateModelV4();
            deployGasHelper = new DeployGasHelper();
            setRole = new SetRole();

            owner = configs[network].deployer.owner;
            deployer = Deployer(payable(_deployDeployer(network)));
            address rolesContract = _deployRoles(owner);
            address zkVerifier = _deployZkVerifier(
                owner, configs[network].zkVerifier.verifierAddress, configs[network].zkVerifier.imageId
            );
            address batchSubmitter = _deployBatchSubmitter(rolesContract, zkVerifier);
            address timelock = _deployTimelock(owner);
            address gasHelper = _deployGasHelper();
            (address rebalancer, address acrossBridge, address everclearBridge) =
                _deployAndConfigRebalancerAndBridges(network, rolesContract);
            address pauser;
            address rewardDistributor;
            address oracle;
            address operator;
            if (configs[network].isHost) {
                console.log("Deploying host chain");
                (pauser, rewardDistributor, oracle, operator) = _deployHostChain(network, rolesContract);
            } else {
                console.log("Deploying extension chain");
                pauser = _deployExtensionChain(rolesContract);
            }

            // Save addreses to `release-deployed-core-addresses.json`
            // {
            //   'Pauser': '0x1',
            //   'BatchSubmitter: '0x2'
            //   ...
            // }
            string memory json;
            json = vm.serializeAddress("core", "Pauser", pauser);
            json = vm.serializeAddress("core", "BatchSubmitter", batchSubmitter);
            json = vm.serializeAddress("core", "TimelockController", timelock);
            json = vm.serializeAddress("core", "ZkVerifier", zkVerifier);
            json = vm.serializeAddress("core", "Rebalancer", rebalancer);
            json = vm.serializeAddress("core", "AcrossBridge", acrossBridge);
            json = vm.serializeAddress("core", "EverclearBridge", everclearBridge);
            json = vm.serializeAddress("core", "Roles", rolesContract);
            if (configs[network].isHost) {
                json = vm.serializeAddress("core", "Oracle", oracle);
                json = vm.serializeAddress("core", "Operator", operator);
                json = vm.serializeAddress("core", "RewardDistributor", rewardDistributor);
            }
            json = vm.serializeAddress("core", "Deployer", address(deployer));
            json = vm.serializeAddress("core", "DefaultGasHelper", gasHelper);
            vm.writeJson(json, "script/deployment/mainnet/output/release-deployed-core-addresses.json");

            console.log("-------------------- DONE");
        }
    }

    function _deployAndConfigRebalancerAndBridges(string memory network, address rolesContract)
        internal
        returns (address rebalancer, address acrossBridge, address everclearBridge)
    {
        console.log(" --- Deploying rebalancer");
        rebalancer = deployRebalancer.run(rolesContract, owner, deployer);
        console.log(" --- Deployed rebalancer at ", rebalancer);

        if (spokePoolAddresses[configs[network].chainId] != address(0)) {
            console.log(" --- Deploying acrossBridge");
            acrossBridge = deployAcrossBridge.run(rolesContract, spokePoolAddresses[configs[network].chainId], deployer);
            console.log(" --- Deployed acrossBridge at ", acrossBridge);
        } else {
            console.log(
                "---- AcrossBridge cannot be deployed on current chain because SpokePool is address(0). Chain: ",
                configs[network].chainId
            );
        }

        console.log(" --- Deploying everclearBridge");
        everclearBridge =
            deployEverclearBridge.run(rolesContract, everclearAddresses[configs[network].chainId], deployer);
        console.log(" --- Deployed everclearBridge at ", everclearBridge);

        console.log(" ---- Setting REBALANCER role for the Rebalancer contract");
        setRole.run(rolesContract, address(rebalancer), keccak256(abi.encodePacked("REBALANCER")), true);

        console.log(" --- All rebalancer contracts deployed and configured for network", network);
    }

    function _deployHostChain(string memory network, address rolesContract)
        internal
        returns (address pauser, address rewardDistributor, address oracle, address operator)
    {
        rewardDistributor = _deployRewardDistributor();
        oracle = _deployOracle(configs[network].oracle, rolesContract);
        operator = _deployOperator(oracle, rewardDistributor, rolesContract);
        pauser = _deployPauser(rolesContract, operator);

        _setOperatorInRewardDistributor(operator, rewardDistributor);
    }

    function _deployExtensionChain(address rolesContract) internal returns (address pauser) {
        pauser = _deployPauser(rolesContract, address(0));
    }

    function _deployDeployer(string memory network) internal returns (address) {
        return deployDeployer.run(configs[network].chainId, owner, configs[network].deployer.salt);
    }

    function _deployRoles(address _owner) internal returns (address) {
        return deployRbac.run(deployer, _owner);
    }

    function _deployBatchSubmitter(address rolesContract, address zkVerifier) internal returns (address) {
        address created = deployBatchSubmitter.run(deployer, rolesContract, zkVerifier, owner);

        console.log(" ---- Setting PROOF_BATCH_FORWARDER role for the BatchSubmitter contract");
        setRole.run(rolesContract, address(created), keccak256(abi.encodePacked("PROOF_BATCH_FORWARDER")), true);

        return created;
    }

    function _deployRewardDistributor() internal returns (address) {
        return deployReward.run(deployer, owner);
    }

    function _deployOracle(OracleConfigRelease memory oracleConfig, address rolesContract) internal returns (address) {
        return deployOracle.runWithoutFeeds(deployer, rolesContract, oracleConfig.stalenessPeriod);
    }

    function _deployOperator(address oracle, address rewardDistributor, address rolesContract)
        internal
        returns (address)
    {
        return deployOperator.run(deployer, oracle, rewardDistributor, rolesContract, owner);
    }

    function _deployPauser(address rolesContract, address operator) internal returns (address) {
        return deployPauser.run(deployer, rolesContract, operator, owner);
    }

    function _deployGasHelper() internal returns (address) {
        return deployGasHelper.run(deployer, owner);
    }

    function _setOperatorInRewardDistributor(address operator, address rewardDistributor) internal {
        setOperatorInRewardDistributor.run(operator, rewardDistributor);
    }

    function _deployZkVerifier(address _owner, address _risc0Verifier, bytes32 _imageId) internal returns (address) {
        return deployZkVerifier.run(deployer, _owner, _risc0Verifier, _imageId);
    }

    function _deployTimelock(address _owner) internal returns (address) {
        return deployTimelockController.run(deployer, _owner);
    }
}
