// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IVotes } from '@oz/governance/utils/IVotes.sol';
import { Time } from '@oz/utils/types/Time.sol';

import { console } from '@std/console.sol';
import { stdJson } from '@std/StdJson.sol';
import { Vm, VmSafe } from '@std/Vm.sol';

import { LibString } from '@solady/utils/LibString.sol';

import { ConsensusGovernanceEntrypoint } from '../../../src/hub/consensus-layer/ConsensusGovernanceEntrypoint.sol';
import { ConsensusValidatorEntrypoint } from '../../../src/hub/consensus-layer/ConsensusValidatorEntrypoint.sol';
import { AssetManager } from '../../../src/hub/core/AssetManager.sol';
import { AssetManagerEntrypoint } from '../../../src/hub/core/AssetManagerEntrypoint.sol';
import { HubAsset } from '../../../src/hub/core/HubAsset.sol';
import { HubAssetFactory } from '../../../src/hub/core/HubAssetFactory.sol';
import { CrossChainRegistry } from '../../../src/hub/cross-chain/CrossChainRegistry.sol';
import { BranchGovernanceEntrypoint } from '../../../src/hub/governance/BranchGovernanceEntrypoint.sol';
import { MITOGovernance } from '../../../src/hub/governance/MITOGovernance.sol';
import { MITOGovernanceVP } from '../../../src/hub/governance/MITOGovernanceVP.sol';
import { GovMITO } from '../../../src/hub/GovMITO.sol';
import { GovMITOEmission } from '../../../src/hub/GovMITOEmission.sol';
import { ReclaimQueue } from '../../../src/hub/ReclaimQueue.sol';
import { MerkleRewardDistributor } from '../../../src/hub/reward/MerkleRewardDistributor.sol';
import { Treasury } from '../../../src/hub/reward/Treasury.sol';
import { EpochFeeder } from '../../../src/hub/validator/EpochFeeder.sol';
import { ValidatorContributionFeed } from '../../../src/hub/validator/ValidatorContributionFeed.sol';
import { ValidatorManager } from '../../../src/hub/validator/ValidatorManager.sol';
import { ValidatorRewardDistributor } from '../../../src/hub/validator/ValidatorRewardDistributor.sol';
import { ValidatorStaking } from '../../../src/hub/validator/ValidatorStaking.sol';
import { ValidatorStakingGovMITO } from '../../../src/hub/validator/ValidatorStakingGovMITO.sol';
import { ValidatorStakingHub } from '../../../src/hub/validator/ValidatorStakingHub.sol';
import { VLFVaultBasic } from '../../../src/hub/vlf/VLFVaultBasic.sol';
import { VLFVaultCapped } from '../../../src/hub/vlf/VLFVaultCapped.sol';
import { VLFVaultFactory } from '../../../src/hub/vlf/VLFVaultFactory.sol';
import { WMITO } from '../../../src/hub/WMITO.sol';
import { IConsensusValidatorEntrypoint } from
  '../../../src/interfaces/hub/consensus-layer/IConsensusValidatorEntrypoint.sol';
import { IGovMITO } from '../../../src/interfaces/hub/IGovMITO.sol';
import { IGovMITOEmission } from '../../../src/interfaces/hub/IGovMITOEmission.sol';
import { IEpochFeeder } from '../../../src/interfaces/hub/validator/IEpochFeeder.sol';
import { IValidatorManager } from '../../../src/interfaces/hub/validator/IValidatorManager.sol';
import { IValidatorStaking } from '../../../src/interfaces/hub/validator/IValidatorStaking.sol';
import { IValidatorStakingHub } from '../../../src/interfaces/hub/validator/IValidatorStakingHub.sol';
import { ISudoVotes } from '../../../src/interfaces/lib/ISudoVotes.sol';
import { Timelock } from '../../../src/lib/Timelock.sol';
import '../Functions.sol';
import { HubConfigs } from '../types/HubConfigs.sol';
import { HubImplT } from '../types/HubImplT.sol';
import { HubProxyT } from '../types/HubProxyT.sol';
import { AbstractDeployer } from './AbstractDeployer.sol';

abstract contract HubDeployer is AbstractDeployer {
  using stdJson for string;
  using LibString for *;

  string private constant _IMPL_BASE = 'mitosis.test.hub.impl';
  string private constant _PROXY_BASE = 'mitosis.test.hub.proxy';

  // =================================================================================== //
  // ----- Main Deployment Logic -----
  // =================================================================================== //

  function deployHub(address mailbox_, address owner_, HubConfigs.DeployConfig memory config)
    internal
    returns (HubImplT.Chain memory impl, HubProxyT.Chain memory proxy)
  {
    //====================================================================================//
    // ----- Base Contracts -----
    //====================================================================================//

    proxy.wmito = WMITO(deploy(_urlHP('.wmito'), type(WMITO).creationCode));

    (
      impl.validator.epochFeeder, //
      proxy.validator.epochFeeder
    ) = _dphEpochFeeder(owner_, config.epochFeeder);

    (
      impl.govMITO, //
      proxy.govMITO
    ) = _dphGovMITO(owner_, config.govMITO);

    (
      impl.govMITOEmission, //
      proxy.govMITOEmission
    ) = _dphGovMITOEmission(
      proxy.govMITO, //
      proxy.validator.epochFeeder,
      owner_,
      config.govMITOEmission
    );

    //====================================================================================//
    // ----- Consensus Layer -----
    //====================================================================================//

    (
      impl.consensusLayer.governanceEntrypoint, //
      proxy.consensusLayer.governanceEntrypoint
    ) = _dphConsensusGovernanceEntrypoint(owner_);

    (
      impl.consensusLayer.validatorEntrypoint, //
      proxy.consensusLayer.validatorEntrypoint
    ) = _dphConsensusValidatorEntrypoint(owner_);

    //====================================================================================//
    // ----- Reward + Core -----
    //====================================================================================//

    (
      impl.reward.treasury, //
      proxy.reward.treasury
    ) = _dphTreasury(owner_);

    (
      impl.reward.merkleDistributor, //
      proxy.reward.merkleDistributor
    ) = _dphMerkleDistributor(owner_, address(proxy.reward.treasury));

    (
      impl.core.crosschainRegistry, //
      proxy.core.crosschainRegistry
    ) = _dphCrossChainRegistry(owner_);

    (
      impl.core.assetManager, //
      proxy.core.assetManager
    ) = _dphAssetManager(owner_, address(proxy.reward.treasury));

    (
      impl.core.assetManagerEntrypoint, //
      proxy.core.assetManagerEntrypoint
    ) = _dphAssetManagerEntrypoint(
      owner_, //
      mailbox_,
      address(proxy.core.assetManager),
      address(proxy.core.crosschainRegistry)
    );

    //====================================================================================//
    // ----- Hub / VLf -----
    //====================================================================================//

    impl.core.hubAsset = deploy(_urlHI('.core.hub-asset'), type(HubAsset).creationCode);
    (
      impl.core.hubAssetFactory, //
      proxy.core.hubAssetFactory
    ) = _dphHubAssetFactory(owner_, impl.core.hubAsset);

    // TODO: we need to register the impl.vlf.vaultBasic and impl.vlf.vaultCapped on "link" phase
    impl.vlf.vaultBasic = deploy(_urlHI('.vlf.vault-basic'), type(VLFVaultBasic).creationCode);
    impl.vlf.vaultCapped = deploy(_urlHI('.vlf.vault-capped'), type(VLFVaultCapped).creationCode);
    (
      impl.vlf.vaultFactory, //
      proxy.vlf.vaultFactory
    ) = _dphVLFVaultFactory(owner_);

    // Reclaim Queue for  VLf
    (
      impl.reclaimQueue, //
      proxy.reclaimQueue
    ) = _dphReclaimQueue(owner_, address(proxy.core.assetManager));

    //====================================================================================//
    // ----- Validator Contracts -----
    //====================================================================================//

    (
      impl.validator.manager, //
      proxy.validator.manager
    ) = _dphValidatorManager(
      proxy.validator.epochFeeder, //
      proxy.consensusLayer.validatorEntrypoint,
      owner_,
      config.validatorManager
    );

    (
      impl.validator.contributionFeed, //
      proxy.validator.contributionFeed
    ) = _dphValidatorContributionFeed(owner_, address(proxy.validator.epochFeeder));

    (
      impl.validator.rewardDistributor, //
      proxy.validator.rewardDistributor
    ) = _dphValidatorRewardDistributor(
      owner_,
      address(proxy.validator.epochFeeder),
      address(proxy.validator.manager),
      address(proxy.validator.stakingHub),
      address(proxy.validator.contributionFeed),
      address(proxy.govMITOEmission),
      config.validatorRewardDistributor
    );

    //====================================================================================//
    // ----- Staking Contracts -----
    //====================================================================================//

    (
      impl.validator.stakingHub, //
      proxy.validator.stakingHub
    ) = _dphValidatorStakingHub(owner_, address(proxy.consensusLayer.validatorEntrypoint));

    impl.validator.staking = deploy(
      _urlHI('.validator.staking'),
      pack(
        type(ValidatorStaking).creationCode,
        abi.encode(address(proxy.validator.manager), address(proxy.validator.stakingHub))
      )
    );
    impl.validator.stakingGovMITO = deploy(
      _urlHI('.validator.staking-gov-mito'),
      pack(
        type(ValidatorStakingGovMITO).creationCode,
        abi.encode(
          address(proxy.govMITO), //
          address(proxy.validator.manager),
          address(proxy.validator.stakingHub)
        )
      )
    );

    // Deploy ValidatorStaking for MITO and GovMITO
    proxy.validator.stakings = new HubProxyT.ValidatorStakingInfo[](2);
    proxy.validator.stakings[0] = _dphValidatorStaking(
      'MITO', //
      impl.validator.staking,
      address(0),
      owner_,
      config.mitoStakingConfig
    );
    proxy.validator.stakings[1] = _dphValidatorStaking(
      'GovMITO', //
      impl.validator.stakingGovMITO,
      address(proxy.govMITO),
      owner_,
      config.govMITOStakingConfig
    );

    // Voting Power = GovMITO + ValidatorStakingGovMITO
    {
      ISudoVotes[] memory mitoVps = new ISudoVotes[](2);
      mitoVps[0] = proxy.govMITO;
      mitoVps[1] = ISudoVotes(address(proxy.validator.stakings[1].staking));

      (
        impl.governance.mitoVP, //
        proxy.governance.mitoVP
      ) = _dphMITOGovernanceVP(owner_, mitoVps);
    }

    //====================================================================================//
    // ----- Governance Contracts -----
    //====================================================================================//

    (
      impl.governance.mitoTimelock, //
      proxy.governance.mitoTimelock
    ) = _dphTimelock(owner_, config.timelock);

    (
      impl.governance.mito, //
      proxy.governance.mito
    ) = _dphMITOGovernance(
      address(proxy.governance.mitoVP), //
      proxy.governance.mitoTimelock,
      config.mitoGovernance
    );

    (
      impl.governance.branchEntrypoint, //
      proxy.governance.branchEntrypoint
    ) = _dphBranchGovernanceEntrypoint(
      owner_, //
      mailbox_,
      address(proxy.core.crosschainRegistry),
      config.branchGovernance.managers
    );
  }

  // =================================================================================== //
  // ----- Deployment Helpers ----- (dph = deployHub to avoid function conflicts)
  // =================================================================================== //

  function _dphEpochFeeder(address owner_, HubConfigs.EpochFeederConfig memory config)
    private
    returns (address, EpochFeeder)
  {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.validator.epoch-feeder',
      type(EpochFeeder).creationCode,
      abi.encodeCall(EpochFeeder.initialize, (owner_, config.initialEpochTime, config.interval))
    );
    return (impl, EpochFeeder(proxy));
  }

  function _dphGovMITO(address owner_, HubConfigs.GovMITOConfig memory config) private returns (address, GovMITO) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.gov-mito', //
      type(GovMITO).creationCode,
      abi.encodeCall(GovMITO.initialize, (owner_, config.withdrawalPeriod))
    );
    return (impl, GovMITO(proxy));
  }

  function _dphGovMITOEmission(
    IGovMITO govMITO_,
    IEpochFeeder epochFeeder_,
    address initialOwner,
    HubConfigs.GovMITOEmissionConfig memory config
  ) private returns (address, GovMITOEmission) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.gov-mito-emission',
      pack(type(GovMITOEmission).creationCode, abi.encode(govMITO_, epochFeeder_)),
      abi.encodeCall(
        GovMITOEmission.initialize,
        (
          initialOwner,
          IGovMITOEmission.ValidatorRewardConfig({
            rps: config.rps,
            rateMultiplier: config.rateMultiplier,
            renewalPeriod: config.renewalPeriod,
            startsFrom: config.startsFrom,
            recipient: initialOwner
          })
        )
      )
    );
    return (impl, GovMITOEmission(proxy));
  }

  function _dphConsensusGovernanceEntrypoint(address owner) private returns (address, ConsensusGovernanceEntrypoint) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.consensus.governance-entrypoint',
      type(ConsensusGovernanceEntrypoint).creationCode,
      abi.encodeCall(ConsensusGovernanceEntrypoint.initialize, (owner))
    );
    return (impl, ConsensusGovernanceEntrypoint(proxy));
  }

  function _dphConsensusValidatorEntrypoint(address owner) private returns (address, ConsensusValidatorEntrypoint) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.consensus.validator-entrypoint',
      type(ConsensusValidatorEntrypoint).creationCode,
      abi.encodeCall(ConsensusValidatorEntrypoint.initialize, (owner))
    );
    return (impl, ConsensusValidatorEntrypoint(proxy));
  }

  function _dphTreasury(address owner) private returns (address, Treasury) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.reward.treasury', //
      type(Treasury).creationCode,
      abi.encodeCall(Treasury.initialize, (owner))
    );
    return (impl, Treasury(proxy));
  }

  function _dphMerkleDistributor(address owner, address treasury) private returns (address, MerkleRewardDistributor) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.reward.merkle-distributor',
      type(MerkleRewardDistributor).creationCode,
      abi.encodeCall(MerkleRewardDistributor.initialize, (owner, treasury))
    );
    return (impl, MerkleRewardDistributor(proxy));
  }

  function _dphCrossChainRegistry(address owner) private returns (address, CrossChainRegistry) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.core.crosschain-registry',
      type(CrossChainRegistry).creationCode,
      abi.encodeCall(CrossChainRegistry.initialize, (owner))
    );
    return (impl, CrossChainRegistry(proxy));
  }

  function _dphAssetManager(address owner, address treasury) private returns (address, AssetManager) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.core.asset-manager', //
      type(AssetManager).creationCode,
      abi.encodeCall(AssetManager.initialize, (owner, treasury))
    );
    return (impl, AssetManager(proxy));
  }

  function _dphAssetManagerEntrypoint(address owner, address mailbox, address assetManager, address crossChainRegistry)
    private
    returns (address, AssetManagerEntrypoint)
  {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.core.asset-manager-entrypoint',
      pack(type(AssetManagerEntrypoint).creationCode, abi.encode(mailbox, assetManager, crossChainRegistry)),
      abi.encodeCall(AssetManagerEntrypoint.initialize, (owner, address(0), address(0)))
    );
    return (impl, AssetManagerEntrypoint(proxy));
  }

  function _dphHubAssetFactory(address owner, address hubAsset) private returns (address, HubAssetFactory) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.core.hub-asset-factory', //
      type(HubAssetFactory).creationCode,
      abi.encodeCall(HubAssetFactory.initialize, (owner, hubAsset))
    );
    return (impl, HubAssetFactory(proxy));
  }

  function _dphVLFVaultFactory(address owner) private returns (address, VLFVaultFactory) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.vlf.vault-factory', //
      type(VLFVaultFactory).creationCode,
      abi.encodeCall(VLFVaultFactory.initialize, (owner))
    );
    return (impl, VLFVaultFactory(proxy));
  }

  function _dphReclaimQueue(address owner, address assetManager) private returns (address, ReclaimQueue) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.reclaim-queue', //
      type(ReclaimQueue).creationCode,
      abi.encodeCall(ReclaimQueue.initialize, (owner, assetManager, address(0)))
    );
    return (impl, ReclaimQueue(proxy));
  }

  function _dphValidatorManager(
    IEpochFeeder epochFeeder_,
    IConsensusValidatorEntrypoint entrypoint_,
    address initialOwner,
    HubConfigs.ValidatorManagerConfig memory config
  ) private returns (address, ValidatorManager) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.validator.manager',
      pack(type(ValidatorManager).creationCode, abi.encode(epochFeeder_, entrypoint_)),
      abi.encodeCall(
        ValidatorManager.initialize, //
        (initialOwner, config.fee, config.globalConfig, config.genesisValidatorSet)
      )
    );
    return (impl, ValidatorManager(proxy));
  }

  function _dphValidatorContributionFeed(address owner, address epochFeeder)
    private
    returns (address, ValidatorContributionFeed)
  {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.validator.contribution-feed', //
      pack(type(ValidatorContributionFeed).creationCode, abi.encode(epochFeeder)),
      abi.encodeCall(ValidatorContributionFeed.initialize, (owner))
    );
    return (impl, ValidatorContributionFeed(proxy));
  }

  function _dphValidatorRewardDistributor(
    address owner,
    address epochFeeder_,
    address validatorManager_,
    address validatorStakingHub_,
    address validatorContributionFeed_,
    address govMITOEmission_,
    HubConfigs.ValidatorRewardDistributorConfig memory config
  ) private returns (address, ValidatorRewardDistributor) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.validator.reward-distributor',
      pack(
        type(ValidatorRewardDistributor).creationCode,
        abi.encode(
          epochFeeder_, //
          validatorManager_,
          validatorStakingHub_,
          validatorContributionFeed_,
          govMITOEmission_
        )
      ),
      abi.encodeCall(
        ValidatorRewardDistributor.initialize,
        (owner, config.maxClaimEpochs, config.maxStakerBatchSize, config.maxOperatorBatchSize)
      )
    );
    return (impl, ValidatorRewardDistributor(proxy));
  }

  function _dphValidatorStakingHub(address owner, address validatorEntrypoint)
    private
    returns (address, ValidatorStakingHub)
  {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.validator.staking-hub', //
      pack(type(ValidatorStakingHub).creationCode, abi.encode(validatorEntrypoint)),
      abi.encodeCall(ValidatorStakingHub.initialize, (owner))
    );
    return (impl, ValidatorStakingHub(proxy));
  }

  // Note: _dphValidatorStaking deploys proxy only, doesn't fit general pattern
  function _dphValidatorStaking(
    string memory label,
    address impl,
    address asset,
    address initialOwner,
    HubConfigs.ValidatorStakingConfig memory config
  ) private returns (HubProxyT.ValidatorStakingInfo memory) {
    string memory _url = cat('.validator.staking[', label, ']');
    bytes memory init = abi.encodeCall(
      ValidatorStaking.initialize,
      (
        asset,
        initialOwner,
        config.minStakingAmount,
        config.minUnstakingAmount,
        config.unstakeCooldown,
        config.redelegationCooldown
      )
    );

    // This function deploys only a proxy, not an implementation, so it doesn't use deployImplAndProxy
    address proxyAddr = deployERC1967Proxy(_urlHP(_url), impl, init);

    return HubProxyT.ValidatorStakingInfo({
      asset: asset,
      minStakingAmount: config.minStakingAmount,
      minUnstakingAmount: config.minUnstakingAmount,
      unstakeCooldown: config.unstakeCooldown,
      redelegationCooldown: config.redelegationCooldown,
      staking: IValidatorStaking(proxyAddr) // Use proxyAddr here
     });
  }

  function _dphMITOGovernanceVP(address owner, ISudoVotes[] memory tokens) private returns (address, MITOGovernanceVP) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.governance.mito-vp', //
      type(MITOGovernanceVP).creationCode,
      abi.encodeCall(MITOGovernanceVP.initialize, (owner, tokens))
    );
    return (impl, MITOGovernanceVP(proxy));
  }

  function _dphTimelock(address owner, HubConfigs.TimelockConfig memory config) private returns (address, Timelock) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.governance.timelock', //
      type(Timelock).creationCode,
      abi.encodeCall(Timelock.initialize, (config.minDelay, config.proposers, config.executors, owner))
    );
    return (impl, Timelock(proxy));
  }

  function _dphMITOGovernance(address mitoVP, Timelock timelock, HubConfigs.MITOGovernanceConfig memory config)
    private
    returns (address, MITOGovernance)
  {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.governance.mito', //
      type(MITOGovernance).creationCode,
      abi.encodeCall(
        MITOGovernance.initialize,
        (
          IVotes(mitoVP),
          timelock,
          config.votingDelay,
          config.votingPeriod,
          config.quorumFraction,
          config.proposalThreshold
        )
      )
    );
    return (impl, MITOGovernance(proxy));
  }

  function _dphBranchGovernanceEntrypoint(
    address owner,
    address mailbox,
    address crossChainRegistry,
    address[] memory managers
  ) private returns (address, BranchGovernanceEntrypoint) {
    (address impl, address payable proxy) = deployImplAndProxy(
      'hub',
      '.governance.branch-entrypoint', //
      pack(type(BranchGovernanceEntrypoint).creationCode, abi.encode(mailbox, crossChainRegistry)),
      abi.encodeCall(BranchGovernanceEntrypoint.initialize, (owner, managers, address(0), address(0)))
    );
    return (impl, BranchGovernanceEntrypoint(proxy));
  }

  // =================================================================================== //
  // ----- Utility Helpers -----
  // =================================================================================== //

  function _urlHI(string memory name) private pure returns (string memory) {
    return _urlI('hub', name);
  }

  function _urlHP(string memory name) private pure returns (string memory) {
    return _urlP('hub', name);
  }
}
