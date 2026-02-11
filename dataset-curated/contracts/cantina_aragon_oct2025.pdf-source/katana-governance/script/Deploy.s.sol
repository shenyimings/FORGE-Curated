// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Script, console2 as console } from "forge-std/Script.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { PluginSetupProcessor } from "@aragon/osx/framework/dao/DAOFactory.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import { GaugeVoterSetupV1_4_0 as GaugeVoterSetup } from "@setup/GaugeVoterSetup_v1_4_0.sol";
import { AddressGaugeVoter } from "@voting/AddressGaugeVoter.sol";
import { LinearIncreasingCurve as Curve } from "@curve/LinearIncreasingCurve.sol";
import { DynamicExitQueue as ExitQueue } from "@queue/DynamicExitQueue.sol";
import { VotingEscrowV1_2_0 as VotingEscrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { ClockV1_2_0 as Clock } from "@clock/Clock_v1_2_0.sol";
import { LockV1_2_0 as Lock } from "@lock/Lock_v1_2_0.sol";
import { EscrowIVotesAdapter } from "@delegation/EscrowIVotesAdapter.sol";
import {
    GaugesDaoFactoryV1_4_0 as VeGovernanceFactory,
    Deployment,
    DeploymentParameters,
    TokenParameters
} from "@factory/GaugesDaoFactory_v1_4_0.sol";

import { VKatMetadata } from "src/VKatMetadata.sol";
import { AragonMerklAutoCompoundStrategy as AutoCompoundStrategy } from
    "src/strategies/AragonMerklAutoCompoundStrategy.sol";
import { AvKATVault } from "src/AvKATVault.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";

import {
    Factory as KatFactory,
    DeploymentParameters as KatDeploymentParams,
    Deployment as KatDeployment,
    BaseContracts
} from "src/Factory.sol";

import { DefaultStrategy } from "src/strategies/DefaultStrategy.sol";

contract Deploy is Script {
    using ProxyLib for address;
    using SafeCast for uint256;

    uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    address merkleDistributor = vm.envAddress("MERKL_DISTRIBUTOR");
    address executor = vm.envAddress("EXECUTOR");

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        BaseContracts memory bases = BaseContracts({
            vault: address(new AvKATVault()),
            defaultStrategy: address(new DefaultStrategy()),
            autoCompoundStrategy: address(new AutoCompoundStrategy()),
            vkatMetadata: address(new VKatMetadata())
        });

        // Deploy KatFactory first so that during ve deployment (which also deploys the DAO),
        // we can grant it EXECUTE_PERMISSION on the DAO. This ensures KatFactory has the
        // authority to assign new permissions for deploying Kat contracts through the DAO.
        KatFactory katFactory = new KatFactory(bases);

        // Deploy VE
        DeploymentParameters memory params = getDeploymentParameters(address(katFactory));
        VeGovernanceFactory veFactory = new VeGovernanceFactory(params);
        veFactory.deployOnce();

        // Get VE Deployment Addresses
        DeploymentParameters memory veDeploymentParameters = veFactory.getDeploymentParameters();
        Deployment memory veDeployment = veFactory.getDeployment();
        VotingEscrow escrow = veDeployment.gaugeVoterPluginSets[0].votingEscrow;

        // Prepare arguments for katana's factory contract.
        KatDeploymentParams memory katParams = KatDeploymentParams({
            merklDistributor: merkleDistributor,
            dao: address(veDeployment.dao),
            escrow: address(escrow),
            executor: executor
        });

        // Deploy all the katana contracts and grab their addresses.
        KatDeployment memory katDeployment = katFactory.deployOnce(katParams);

        // Print all necessary/useful deployment addresses.
        printDeploymentSummary(
            address(veFactory), address(katFactory), veDeployment, veDeploymentParameters, katDeployment
        );

        vm.stopBroadcast();
    }

    function getDeploymentParameters(address _daoExecutor) public returns (DeploymentParameters memory parameters) {
        TokenParameters[] memory tokenParameters = getTokenParameters(vm.envOr("MINT_TEST_TOKENS", false));
        GaugeVoterSetup gaugeVoterPluginSetup = deployGaugeVoterPluginSetup();

        parameters = DeploymentParameters({
            daoMetadataURI: "",
            daoSubdomain: "",
            daoExecutor: _daoExecutor,
            // Multisig settings
            minApprovals: vm.envUint("MIN_APPROVALS").toUint8(),
            multisigMembers: readMultisigMembers(),
            multisigMetadata: bytes(vm.envString("MULTISIG_METADATA_URI")),
            // Gauge Voter
            tokenParameters: tokenParameters,
            feePercent: vm.envUint("FEE_PERCENT").toUint16(),
            cooldownPeriod: vm.envUint("COOLDOWN_PERIOD").toUint48(),
            minLockDuration: vm.envUint("MIN_LOCK_DURATION").toUint48(),
            votingPaused: vm.envBool("VOTING_PAUSED"),
            minDeposit: vm.envUint("MIN_DEPOSIT"),
            // Standard multisig repo
            multisigPluginRepo: PluginRepo(vm.envAddress("MULTISIG_PLUGIN_REPO_ADDRESS")),
            multisigPluginRelease: vm.envUint("MULTISIG_PLUGIN_RELEASE").toUint8(),
            multisigPluginBuild: vm.envUint("MULTISIG_PLUGIN_BUILD").toUint16(),
            // Voter plugin setup and ENS
            voterPluginSetup: gaugeVoterPluginSetup,
            voterEnsSubdomain: vm.envString("SIMPLE_GAUGE_VOTER_REPO_ENS_SUBDOMAIN"),
            // OSx addresses
            osxDaoFactory: vm.envAddress("DAO_FACTORY"),
            pluginSetupProcessor: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR")),
            pluginRepoFactory: PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY"))
        });
    }

    function deployGaugeVoterPluginSetup() internal returns (GaugeVoterSetup result) {
        int256[3] memory coefficients;
        coefficients[0] = vm.envUint("CONSTANT_COEFFICIENT").toInt256();
        coefficients[1] = vm.envUint("LINEAR_COEFFICIENT").toInt256();
        coefficients[2] = 0;

        uint256 maxEpoch = vm.envUint("MAX_EPOCHS");

        result = new GaugeVoterSetup(
            address(new AddressGaugeVoter()),
            address(new Curve(coefficients, maxEpoch)),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock()),
            address(new EscrowIVotesAdapter(coefficients, maxEpoch))
        );
    }

    function readMultisigMembers() public view returns (address[] memory result) {
        // JSON list of members
        string memory membersFileName = "multisig-members.json";
        string memory path = string.concat(vm.projectRoot(), "/", membersFileName);
        string memory strJson = vm.readFile(path);

        bool exists = vm.keyExistsJson(strJson, "$.members");
        if (!exists) {
            revert("The file multisig-members.json does not contain any members or doesn't exist");
        }

        result = vm.parseJsonAddressArray(strJson, "$.members");

        if (result.length == 0) {
            revert("The file multisig-members.json needs to contain at least one member");
        }
    }

    function getTokenParameters(bool mintTestTokens) internal returns (TokenParameters[] memory tokenParameters) {
        if (mintTestTokens) {
            // MINT
            console.log("Deploying 2 token contracts (testing)");

            address[] memory multisigMembers = readMultisigMembers();
            tokenParameters = new TokenParameters[](1);
            tokenParameters[0] = TokenParameters({
                token: createTestToken(multisigMembers),
                veTokenName: "VE Token 1",
                veTokenSymbol: "veTK1"
            });
        } else {
            // USE TOKEN(s)
            bool hasTwoTokens = vm.envAddress("TOKEN2_ADDRESS") != address(0);
            tokenParameters = new TokenParameters[](hasTwoTokens ? 2 : 1);

            console.log("Using token", vm.envAddress("TOKEN1_ADDRESS"));
            tokenParameters[0] = TokenParameters({
                token: vm.envAddress("TOKEN1_ADDRESS"),
                veTokenName: vm.envString("VE_TOKEN1_NAME"),
                veTokenSymbol: vm.envString("VE_TOKEN1_SYMBOL")
            });

            if (hasTwoTokens) {
                console.log("Using token", vm.envAddress("TOKEN2_ADDRESS"));
                tokenParameters[1] = TokenParameters({
                    token: vm.envAddress("TOKEN2_ADDRESS"),
                    veTokenName: vm.envString("VE_TOKEN2_NAME"),
                    veTokenSymbol: vm.envString("VE_TOKEN2_SYMBOL")
                });
            }
        }
    }

    function createTestToken(address[] memory holders) internal returns (address) {
        MockERC20 newToken = new MockERC20();

        for (uint256 i = 0; i < holders.length;) {
            newToken.mint(holders[i], 5000 ether);

            unchecked {
                i++;
            }
        }

        return address(newToken);
    }

    function printDeploymentSummary(
        address _veFactory,
        address _katFactory,
        Deployment memory _veDeployment,
        DeploymentParameters memory _veDeploymentParams,
        KatDeployment memory _katDeployment
    )
        internal
        view
    {
        console.log("");
        console.log("Deployed from: ", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("VeFactory:", address(_veFactory));
        console.log("KatFactory:", address(_katFactory));
        console.log("");
        console.log("DAO:", address(_veDeployment.dao));
        console.log("");

        console.log("Plugins");
        console.log("- Multisig plugin:", address(_veDeployment.multisigPlugin));
        console.log("");

        for (uint256 i = 0; i < _veDeployment.gaugeVoterPluginSets.length;) {
            console.log("- Using token:", address(_veDeploymentParams.tokenParameters[i].token));
            console.log("  Gauge voter plugin:", address(_veDeployment.gaugeVoterPluginSets[i].plugin));
            console.log("  Curve:", address(_veDeployment.gaugeVoterPluginSets[i].curve));
            console.log("  Exit Queue:", address(_veDeployment.gaugeVoterPluginSets[i].exitQueue));
            console.log("  Voting Escrow:", address(_veDeployment.gaugeVoterPluginSets[i].votingEscrow));
            console.log("  Clock:", address(_veDeployment.gaugeVoterPluginSets[i].clock));
            console.log("  NFT Lock:", address(_veDeployment.gaugeVoterPluginSets[i].nftLock));
            console.log("  Escrow IVotes Adapter:", address(_veDeployment.gaugeVoterPluginSets[i].delegationAdapter));
            console.log("");

            unchecked {
                i++;
            }
        }

        console.log("Plugin repositories");
        console.log("- Multisig plugin repository (existing):", address(_veDeploymentParams.multisigPluginRepo));
        console.log("- Gauge voter plugin repository:", address(_veDeployment.gaugeVoterPluginRepo));

        console.log("========");
        console.log("  Vault", _katDeployment.vault);
        console.log("  Swapper", _katDeployment.swapper);
        console.log("  CompoundStrategy", _katDeployment.autoCompoundStrategy);
        console.log("  KatMetadata", _katDeployment.vkatMetadata);
    }
}
