// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

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
import { VLFVaultFactory } from '../../../src/hub/vlf/VLFVaultFactory.sol';
import { WMITO } from '../../../src/hub/WMITO.sol';
import { IHubAsset } from '../../../src/interfaces/hub/core/IHubAsset.sol';
import { IValidatorStaking } from '../../../src/interfaces/hub/validator/IValidatorStaking.sol';
import { IVLFVault } from '../../../src/interfaces/hub/vlf/IVLFVault.sol';
import { Timelock } from '../../../src/lib/Timelock.sol';
import '../Functions.sol';

library HubProxyT {
  using LibString for *;
  using stdJson for string;

  address private constant VM_ADDRESS = address(uint160(uint256(keccak256('hevm cheat code'))));
  Vm private constant vm = Vm(VM_ADDRESS);

  struct HubAssetInfo {
    string name;
    string symbol;
    uint8 decimals;
    IHubAsset asset;
  }

  struct VLFVaultInfo {
    string name;
    string symbol;
    uint8 decimals;
    IHubAsset asset;
    IVLFVault vault;
  }

  struct ValidatorStakingInfo {
    address asset;
    uint256 minStakingAmount;
    uint256 minUnstakingAmount;
    uint48 unstakeCooldown;
    uint48 redelegationCooldown;
    IValidatorStaking staking;
  }

  struct ConsensusLayer {
    ConsensusGovernanceEntrypoint governanceEntrypoint;
    ConsensusValidatorEntrypoint validatorEntrypoint;
  }

  struct Core {
    AssetManager assetManager;
    AssetManagerEntrypoint assetManagerEntrypoint;
    HubAssetInfo[] hubAssets;
    HubAssetFactory hubAssetFactory;
    CrossChainRegistry crosschainRegistry;
  }

  struct vlf {
    VLFVaultInfo[] vaults;
    VLFVaultFactory vaultFactory;
  }

  struct Governance {
    BranchGovernanceEntrypoint branchEntrypoint;
    MITOGovernance mito;
    MITOGovernanceVP mitoVP;
    Timelock mitoTimelock;
  }

  struct Reward {
    MerkleRewardDistributor merkleDistributor;
    Treasury treasury;
  }

  struct Validator {
    EpochFeeder epochFeeder;
    ValidatorContributionFeed contributionFeed;
    ValidatorManager manager;
    ValidatorRewardDistributor rewardDistributor;
    ValidatorStakingInfo[] stakings;
    ValidatorStakingHub stakingHub;
  }

  struct Chain {
    //
    ConsensusLayer consensusLayer;
    Core core;
    vlf vlf;
    Governance governance;
    Reward reward;
    Validator validator;
    //
    GovMITO govMITO;
    GovMITOEmission govMITOEmission;
    ReclaimQueue reclaimQueue;
    WMITO wmito;
  }

  //=================================================================================================//
  // ------ FS HELPERS ------ //
  //=================================================================================================//

  function stdPath() internal pure returns (string memory) {
    // Use a different path for proxy data
    return './test/testdata/hub.proxy.json';
  }

  function readProxy(string memory path) internal view returns (Chain memory) {
    return decode(vm.readFile(path));
  }

  function write(Chain memory v, string memory path) internal {
    if (vm.exists(path)) vm.removeFile(path); // replace
    vm.writeJson(encode(v), path);
    vm.writeFile(path, string.concat(vm.readFile(path), '\n'));
  }

  //=================================================================================================//
  // ------ CODEC ------ //
  //=================================================================================================//

  // --- Encode Functions ---

  function extract(HubAssetInfo[] memory v) private pure returns (address[] memory o) {
    o = new address[](v.length);
    for (uint256 i = 0; i < v.length; i++) {
      o[i] = address(v[i].asset);
    }
  }

  function extract(VLFVaultInfo[] memory v) private pure returns (address[] memory o) {
    o = new address[](v.length);
    for (uint256 i = 0; i < v.length; i++) {
      o[i] = address(v[i].vault);
    }
  }

  function extract(ValidatorStakingInfo[] memory v) private pure returns (address[] memory o) {
    o = new address[](v.length);
    for (uint256 i = 0; i < v.length; i++) {
      o[i] = address(v[i].staking);
    }
  }

  function encode(ConsensusLayer memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('governanceEntrypoint', address(v.governanceEntrypoint));
    o = k.serialize('validatorEntrypoint', address(v.validatorEntrypoint));
  }

  function encode(Core memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('assetManager', address(v.assetManager));
    o = k.serialize('assetManagerEntrypoint', address(v.assetManagerEntrypoint));
    o = k.serialize('hubAssets', extract(v.hubAssets));
    o = k.serialize('hubAssetFactory', address(v.hubAssetFactory));
    o = k.serialize('crosschainRegistry', address(v.crosschainRegistry));
  }

  function encode(vlf memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('vaults', extract(v.vaults));
    o = k.serialize('vaultFactory', address(v.vaultFactory));
  }

  function encode(Governance memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('branchEntrypoint', address(v.branchEntrypoint));
    o = k.serialize('mito', address(v.mito));
    o = k.serialize('mitoVP', address(v.mitoVP));
    o = k.serialize('mitoTimelock', address(v.mitoTimelock));
  }

  function encode(Reward memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('merkleDistributor', address(v.merkleDistributor));
    o = k.serialize('treasury', address(v.treasury));
  }

  function encode(Validator memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('epochFeeder', address(v.epochFeeder));
    o = k.serialize('contributionFeed', address(v.contributionFeed));
    o = k.serialize('manager', address(v.manager));
    o = k.serialize('rewardDistributor', address(v.rewardDistributor));
    o = k.serialize('stakings', extract(v.stakings));
    o = k.serialize('stakingHub', address(v.stakingHub));
  }

  function encode(Chain memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('consensusLayer', encode(v.consensusLayer));
    o = k.serialize('core', encode(v.core));
    o = k.serialize('vlf', encode(v.vlf));
    o = k.serialize('governance', encode(v.governance));
    o = k.serialize('reward', encode(v.reward));
    o = k.serialize('validator', encode(v.validator));
    o = k.serialize('govMITO', address(v.govMITO));
    o = k.serialize('govMITOEmission', address(v.govMITOEmission));
    o = k.serialize('reclaimQueue', address(v.reclaimQueue));
    o = k.serialize('wmito', address(v.wmito));
  }

  // --- Decode Functions ---

  function decodeConsensusLayer(string memory v, string memory base) internal pure returns (ConsensusLayer memory o) {
    o.governanceEntrypoint = ConsensusGovernanceEntrypoint(_r(v, cat(base, '.governanceEntrypoint')));
    o.validatorEntrypoint = ConsensusValidatorEntrypoint(_r(v, cat(base, '.validatorEntrypoint')));
  }

  function decodeHubAssets(string memory v, string memory path) internal view returns (HubAssetInfo[] memory o) {
    address payable[] memory hubAssets = _ra(v, path);
    o = new HubAssetInfo[](hubAssets.length);

    for (uint256 i = 0; i < hubAssets.length; i++) {
      IHubAsset asset = IHubAsset(hubAssets[i]);

      o[i] = HubAssetInfo({
        name: asset.name(), //
        symbol: asset.symbol(),
        decimals: asset.decimals(),
        asset: asset
      });
    }
  }

  function decodeCore(string memory v, string memory base) internal view returns (Core memory o) {
    o.assetManager = AssetManager(_r(v, cat(base, '.assetManager')));
    o.assetManagerEntrypoint = AssetManagerEntrypoint(_r(v, cat(base, '.assetManagerEntrypoint')));
    o.hubAssets = decodeHubAssets(v, cat(base, '.hubAssets'));
    o.hubAssetFactory = HubAssetFactory(_r(v, cat(base, '.hubAssetFactory')));
    o.crosschainRegistry = CrossChainRegistry(_r(v, cat(base, '.crosschainRegistry')));
  }

  function decodeVLFVaults(string memory v, string memory path) internal view returns (VLFVaultInfo[] memory o) {
    address payable[] memory vaults = _ra(v, path);
    o = new VLFVaultInfo[](vaults.length);

    for (uint256 i = 0; i < vaults.length; i++) {
      IVLFVault vault = IVLFVault(vaults[i]);

      o[i] = VLFVaultInfo({
        name: vault.name(),
        symbol: vault.symbol(),
        decimals: vault.decimals(),
        asset: IHubAsset(vault.asset()),
        vault: vault
      });
    }
  }

  function decodevlf(string memory v, string memory base) internal view returns (vlf memory o) {
    o.vaults = decodeVLFVaults(v, cat(base, '.vaults'));
    o.vaultFactory = VLFVaultFactory(_r(v, cat(base, '.vaultFactory')));
  }

  function decodeGovernance(string memory v, string memory base) internal pure returns (Governance memory o) {
    o.branchEntrypoint = BranchGovernanceEntrypoint(_r(v, cat(base, '.branchEntrypoint')));
    o.mito = MITOGovernance(_r(v, cat(base, '.mito')));
    o.mitoVP = MITOGovernanceVP(_r(v, cat(base, '.mitoVP')));
  }

  function decodeReward(string memory v, string memory base) internal pure returns (Reward memory o) {
    o.merkleDistributor = MerkleRewardDistributor(_r(v, cat(base, '.merkleDistributor')));
    o.treasury = Treasury(_r(v, cat(base, '.treasury')));
  }

  function decodeValidatorStakings(string memory v, string memory path)
    internal
    view
    returns (ValidatorStakingInfo[] memory o)
  {
    address payable[] memory stakings = _ra(v, path);
    o = new ValidatorStakingInfo[](stakings.length);

    for (uint256 i = 0; i < stakings.length; i++) {
      IValidatorStaking staking = IValidatorStaking(stakings[i]);

      o[i] = ValidatorStakingInfo({
        asset: staking.baseAsset(),
        minStakingAmount: staking.minStakingAmount(),
        minUnstakingAmount: staking.minUnstakingAmount(),
        unstakeCooldown: staking.unstakeCooldown(),
        redelegationCooldown: staking.redelegationCooldown(),
        staking: staking
      });
    }
  }

  function decodeValidator(string memory v, string memory base) internal view returns (Validator memory o) {
    o.epochFeeder = EpochFeeder(_r(v, cat(base, '.epochFeeder')));
    o.contributionFeed = ValidatorContributionFeed(_r(v, cat(base, '.contributionFeed')));
    o.manager = ValidatorManager(_r(v, cat(base, '.manager')));
    o.rewardDistributor = ValidatorRewardDistributor(_r(v, cat(base, '.rewardDistributor')));
    o.stakings = decodeValidatorStakings(v, cat(base, '.stakings'));
    o.stakingHub = ValidatorStakingHub(_r(v, cat(base, '.stakingHub')));
  }

  function decode(string memory v) internal view returns (Chain memory o) {
    o.consensusLayer = decodeConsensusLayer(v, '.consensusLayer');
    o.core = decodeCore(v, '.core');
    o.vlf = decodevlf(v, '.vlf');
    o.governance = decodeGovernance(v, '.governance');
    o.reward = decodeReward(v, '.reward');
    o.validator = decodeValidator(v, '.validator');
    //
    o.govMITO = GovMITO(_r(v, '.govMITO'));
    o.govMITOEmission = GovMITOEmission(_r(v, '.govMITOEmission'));
    o.reclaimQueue = ReclaimQueue(_r(v, '.reclaimQueue'));
    o.wmito = WMITO(_r(v, '.wmito'));
  }

  function _r(string memory v, string memory path) internal pure returns (address payable) {
    return payable(v.readAddress(path));
  }

  function _ra(string memory v, string memory path) internal pure returns (address payable[] memory o) {
    address[] memory a = v.readAddressArray(path);
    o = new address payable[](a.length);
    for (uint256 i = 0; i < a.length; i++) {
      o[i] = payable(a[i]);
    }
  }
}
