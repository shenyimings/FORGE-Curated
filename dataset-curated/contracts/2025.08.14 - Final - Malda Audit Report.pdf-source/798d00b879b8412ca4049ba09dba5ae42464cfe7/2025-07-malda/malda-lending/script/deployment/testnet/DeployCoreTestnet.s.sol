// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {Operator} from "src/Operator/Operator.sol";
import {BatchSubmitter} from "src/mToken/BatchSubmitter.sol";
import {RewardDistributor} from "src/rewards/RewardDistributor.sol";
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
import {DeployPauser} from "../generic/DeployPauser.s.sol";
import {DeployGasHelper} from "../generic/DeployGasHelper.s.sol";
import {DeployOperator} from "../markets/DeployOperator.s.sol";
import {DeployJumpRateModelV4} from "../interest/DeployJumpRateModelV4.s.sol";
import {DeployRewardDistributor} from "../rewards/DeployRewardDistributor.s.sol";
import {DeployBatchSubmitter} from "../generic/DeployBatchSubmitter.s.sol";
import {DeployMixedPriceOracleV4} from "../oracles/DeployMixedPriceOracleV4.s.sol";

import {SetRole} from "../../configuration/SetRole.s.sol";
import {SetOperatorInRewardDistributor} from "../../configuration/SetOperatorInRewardDistributor.s.sol";

// forge script DeployCoreTestnet --slow
// forge script DeployCoreTestnet --slow  --multi --verify --broadcast
contract DeployCoreTestnet is DeployBaseRelease {
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
    DeployZkVerifier deployZkVerifier;
    DeployGasHelper deployGasHelper;
    SetRole setRole;

    function setUp() public override {
        configPath = "deployment-config-testnet.json";
        super.setUp();
    }

    function run() public {
        // Deploy to all networks
        for (uint256 i = 0; i < networks.length; i++) {
            string memory network = networks[i];
            console.log("\n=== Deploying to %s ===", network);

            // Create fork for this network
            forks[network] = vm.createSelectFork(network);

            // deploys or fetches the existing one
            deployDeployer = new DeployDeployer();

            deployGasHelper = new DeployGasHelper();

            // deploys or fetches the existing one
            deployRbac = new DeployRbac();
            deployZkVerifier = new DeployZkVerifier();

            deployBatchSubmitter = new DeployBatchSubmitter();
            setRole = new SetRole();

            owner = configs[network].deployer.owner;
            deployer = Deployer(payable(_deployDeployer(network)));
            address rolesContract = _deployRoles(owner);
            address zkVerifier = _deployZkVerifier(
                owner, configs[network].zkVerifier.verifierAddress, configs[network].zkVerifier.imageId
            );
            _deployBatchSubmitter(rolesContract, zkVerifier);

            deployPauser = new DeployPauser();

            _deployGasHelper();

            address pauser;
            if (configs[network].isHost) {
                deployInterest = new DeployJumpRateModelV4();
                deployOperator = new DeployOperator();
                deployOracle = new DeployMixedPriceOracleV4();
                deployReward = new DeployRewardDistributor();

                address rewardDistributor = _deployRewardDistributor();
                address oracle = _deployOracle(configs[network].oracle, rolesContract);
                address operator = _deployOperator(oracle, rewardDistributor, rolesContract);

                console.log("Deploying Pauser on host chain");
                pauser = _deployPauser(rolesContract, operator);
                console.log("Pauser deployed on host chain", pauser);
            } else {
                console.log("Deploying Pauser on host chain");
                pauser = _deployPauser(rolesContract, address(0));
                console.log("Pauser deployed on host chain", pauser);
            }
            console.log("-------------------- DONE");
        }
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
        console.log("--- owner", owner);
        return deployReward.run(deployer, owner);
    }

    function _deployOracle(OracleConfigRelease memory oracleConfig, address rolesContract) internal returns (address) {
        return deployOracle.runTestnet(deployer, rolesContract, oracleConfig.stalenessPeriod);
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

    function _deployInterestModel(InterestConfig memory modelConfig) internal returns (address) {
        return deployInterest.run(
            deployer,
            DeployJumpRateModelV4.InterestData({
                kink: modelConfig.kink,
                name: modelConfig.name,
                blocksPerYear: modelConfig.blocksPerYear,
                baseRatePerYear: modelConfig.baseRate,
                multiplierPerYear: modelConfig.multiplier,
                jumpMultiplierPerYear: modelConfig.jumpMultiplier
            }),
            owner
        );
    }

    function _deployZkVerifier(address _owner, address _risc0Verifier, bytes32 _imageId) internal returns (address) {
        return deployZkVerifier.run(deployer, _owner, _risc0Verifier, _imageId);
    }
}
