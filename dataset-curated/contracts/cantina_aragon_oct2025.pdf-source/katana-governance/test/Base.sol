// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";

import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { Multisig } from "@aragon/multisig/src/MultisigSetup.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { ProtocolFactoryBuilder } from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";
import { ProtocolFactory } from "@aragon/protocol-factory/src/ProtocolFactory.sol";

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
    Deployment as VeDeployment,
    DeploymentParameters,
    TokenParameters
} from "@factory/GaugesDaoFactory_v1_4_0.sol";

import { Distributor as MerklDistributor } from "@merkl/Distributor.sol";

import {
    Factory as KatFactory,
    DeploymentParameters as KatDeploymentParams,
    Deployment as KatDeployment,
    BaseContracts
} from "src/Factory.sol";

import { AvKATVault } from "src/AvKATVault.sol";
import { VKatMetadata } from "src/VKatMetadata.sol";
import { AragonMerklAutoCompoundStrategy as AutoCompoundStrategy } from
    "src/strategies/AragonMerklAutoCompoundStrategy.sol";
import { deployMerklDistributor } from "src/utils/Deployers.sol";
import { Swapper } from "src/Swapper.sol";

import { MerkleTreeHelper } from "./utils/merkle/MerkleTreeHelper.sol";
import { SwapActionsBuilder } from "./utils/SwapActionsBuilder.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";
import { MockSwap } from "./mocks/MockSwap.sol";
import { DefaultStrategy } from "src/strategies/DefaultStrategy.sol";

contract Base is ERC721Holder, Test {
    // ve contracts
    DAO internal dao;
    EscrowIVotesAdapter internal ivotesAdapter;
    VotingEscrow internal escrow;
    Multisig internal multisig;
    Lock internal lockNft;
    AddressGaugeVoter internal voter;
    MockERC20 internal escrowToken;

    // kat contracts
    uint256 internal masterTokenId;
    AvKATVault public vault;
    Swapper internal swapper;
    AutoCompoundStrategy internal acStrategy;
    DefaultStrategy internal defaultStrategy;
    MerklDistributor internal merklDistributor;
    uint8 internal decimals;

    KatDeployment internal katDeployment;
    ProtocolFactory.Deployment internal osxDeployment;

    // Helper contracts
    MerkleTreeHelper internal merkleTreeHelper;
    SwapActionsBuilder internal swapActionsBuilder;
    address internal tokenA = address(new MockERC20());
    address internal tokenB = address(new MockERC20());
    address internal tokenC = address(new MockERC20());

    // some user addresses
    address internal alice = address(3);
    address internal bob = address(4);
    address internal charlie = address(5);
    address internal john = address(6);

    function setUp() public virtual {
        _deployOSx();

        // Deploy Kat Factory
        BaseContracts memory bases = BaseContracts({
            vault: address(new AvKATVault()),
            defaultStrategy: address(new DefaultStrategy()),
            autoCompoundStrategy: address(new AutoCompoundStrategy()),
            vkatMetadata: address(new VKatMetadata())
        });

        KatFactory katFactory = new KatFactory(bases);

        // Deploy VE
        _deployVe(address(katFactory));

        // Deploy Kat Contracts
        _deployKat(address(katFactory));

        // Grant below permissions to address(this) for easier testing.
        vm.startPrank(address(dao));
        dao.grant(address(vault), address(this), vault.VAULT_ADMIN_ROLE());
        dao.grant(address(vault), address(this), vault.SWEEPER_ROLE());
        dao.grant(address(lockNft), address(this), lockNft.LOCK_ADMIN_ROLE());
        dao.grant(address(escrow), address(this), escrow.ESCROW_ADMIN_ROLE());
        dao.grant(address(voter), address(this), voter.GAUGE_ADMIN_ROLE());
        dao.grant(address(acStrategy), address(this), acStrategy.AUTOCOMPOUND_STRATEGY_ADMIN_ROLE());
        dao.grant(address(acStrategy), address(this), acStrategy.AUTOCOMPOUND_STRATEGY_VOTE_ROLE());
        dao.grant(address(acStrategy), address(this), acStrategy.AUTOCOMPOUND_STRATEGY_CLAIM_COMPOUND_ROLE());
        vm.stopPrank();

        vm.warp(voter.epochVoteStart() + 1);

        // set a masterTokenId on vault.
        escrowToken.approve(address(escrow), vault.minMasterTokenInitAmount());
        masterTokenId = escrow.createLock(vault.minMasterTokenInitAmount());
        lockNft.approve(address(vault), masterTokenId);
        vault.initializeMasterTokenAndStrategy(masterTokenId, address(acStrategy));
        vault.unpause();
        // Deploy merkle tree helper
        address mockSwap = address(new MockSwap());
        merkleTreeHelper = new MerkleTreeHelper(address(merklDistributor), address(this), address(swapper), mockSwap);
        swapActionsBuilder = new SwapActionsBuilder(mockSwap);
    }

    function _deployOSx() internal {
        ProtocolFactoryBuilder builder = new ProtocolFactoryBuilder();
        builder.withMultisigPlugin(1, 1, "ipfs://", "ipfs://", "multisig-subdomain");
        ProtocolFactory protocolFactory = builder.build();
        protocolFactory.deployOnce();
        osxDeployment = protocolFactory.getDeployment();
    }

    function _deployKat(address _katFactory) internal {
        (, address _merklDistributor) = deployMerklDistributor(address(this), address(1));
        merklDistributor = MerklDistributor(_merklDistributor);

        KatDeploymentParams memory katParams = KatDeploymentParams({
            merklDistributor: _merklDistributor,
            dao: address(dao),
            escrow: address(escrow),
            executor: osxDeployment.globalExecutor
        });

        katDeployment = KatFactory(_katFactory).deployOnce(katParams);

        vault = AvKATVault(katDeployment.vault);
        swapper = Swapper(katDeployment.swapper);
        acStrategy = AutoCompoundStrategy(katDeployment.autoCompoundStrategy);
        defaultStrategy = DefaultStrategy(katDeployment.defaultStrategy);
    }

    function _deployVe(address _daoExecutor) internal {
        int256[3] memory coefficients;
        coefficients[0] = 1000000000000000000;
        coefficients[1] = 0;
        coefficients[2] = 0;

        uint256 maxEpoch = 0;

        GaugeVoterSetup gaugeVoterPluginSetup = new GaugeVoterSetup(
            address(new AddressGaugeVoter()),
            address(new Curve(coefficients, maxEpoch)),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock()),
            address(new EscrowIVotesAdapter(coefficients, maxEpoch))
        );

        address[] memory members = new address[](1);
        members[0] = address(this);

        TokenParameters[] memory tokenParameters = new TokenParameters[](1);
        tokenParameters[0] =
            TokenParameters({ token: createTestToken(members), veTokenName: "VE Token 1", veTokenSymbol: "veTK1" });

        DeploymentParameters memory parameters = DeploymentParameters({
            daoMetadataURI: "",
            daoSubdomain: "",
            daoExecutor: _daoExecutor,
            // Multisig settings
            minApprovals: 1,
            multisigMembers: members,
            multisigMetadata: "ipfs://",
            // Gauge Voter
            tokenParameters: tokenParameters,
            feePercent: 1,
            cooldownPeriod: 1,
            minLockDuration: 1,
            votingPaused: false,
            minDeposit: 1,
            multisigPluginRepo: PluginRepo(osxDeployment.multisigPluginRepo),
            multisigPluginRelease: 1,
            multisigPluginBuild: 1,
            voterPluginSetup: GaugeVoterSetup(gaugeVoterPluginSetup),
            voterEnsSubdomain: "voter-sub-domain",
            osxDaoFactory: osxDeployment.daoFactory,
            pluginSetupProcessor: PluginSetupProcessor(osxDeployment.pluginSetupProcessor),
            pluginRepoFactory: PluginRepoFactory(osxDeployment.pluginRepoFactory)
        });

        VeGovernanceFactory veFactory = new VeGovernanceFactory(parameters);
        veFactory.deployOnce();

        VeDeployment memory deps = veFactory.getDeployment();
        dao = deps.dao;
        ivotesAdapter = deps.gaugeVoterPluginSets[0].delegationAdapter;
        escrow = deps.gaugeVoterPluginSets[0].votingEscrow;
        lockNft = deps.gaugeVoterPluginSets[0].nftLock;
        multisig = Multisig(address(deps.multisigPlugin));
        voter = deps.gaugeVoterPluginSets[0].plugin;
        escrowToken = MockERC20(tokenParameters[0].token);
    }

    function createTestToken(address[] memory holders) internal returns (address) {
        MockERC20 newToken = new MockERC20();

        for (uint256 i = 0; i < holders.length; i++) {
            newToken.mint(holders[i], 5000 ether);
        }

        decimals = newToken.decimals();

        return address(newToken);
    }

    function _parseToken(uint256 _amount) internal view returns (uint256) {
        return _amount * 10 ** decimals;
    }

    function _increaseTotalAsset(uint256 _amount) internal {
        _mintAndApprove(address(this), address(escrow), _amount);
        uint256 tokenId = escrow.createLockFor(_amount, address(acStrategy));
        vm.startPrank(address(acStrategy));
        escrow.merge(tokenId, vault.masterTokenId());
        vm.stopPrank();
    }

    function _mintAndApprove(address _account, address _who, uint256 _amount) internal {
        escrowToken.mint(_account, _amount);
        uint256 currentAllowance = escrowToken.allowance(_account, _who);

        vm.prank(_account);
        escrowToken.approve(_who, currentAllowance + _amount);
    }
}
