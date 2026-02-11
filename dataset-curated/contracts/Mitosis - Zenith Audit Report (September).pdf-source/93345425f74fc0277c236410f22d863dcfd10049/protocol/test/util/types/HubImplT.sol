// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { console } from '@std/console.sol';
import { stdJson } from '@std/StdJson.sol';
import { Vm, VmSafe } from '@std/Vm.sol';

import { LibString } from '@solady/utils/LibString.sol';

import '../Functions.sol';

library HubImplT {
  using LibString for *;
  using stdJson for string;

  address private constant VM_ADDRESS = address(uint160(uint256(keccak256('hevm cheat code'))));
  Vm private constant vm = Vm(VM_ADDRESS);

  struct ConsensusLayer {
    address governanceEntrypoint;
    address validatorEntrypoint;
  }

  struct Core {
    address assetManager;
    address assetManagerEntrypoint;
    address hubAsset;
    address hubAssetFactory;
    address crosschainRegistry;
  }

  struct VLF {
    address vaultBasic;
    address vaultCapped;
    address vaultFactory;
  }

  struct Governance {
    address branchEntrypoint;
    address mito;
    address mitoVP;
    address mitoTimelock;
  }

  struct Reward {
    address merkleDistributor;
    address treasury;
  }

  struct Validator {
    address epochFeeder;
    address contributionFeed;
    address manager;
    address rewardDistributor;
    address staking;
    address stakingGovMITO;
    address stakingHub;
  }

  struct Chain {
    //
    ConsensusLayer consensusLayer;
    Core core;
    VLF vlf;
    Governance governance;
    Reward reward;
    Validator validator;
    //
    address govMITO;
    address govMITOEmission;
    address reclaimQueue;
  }

  //=================================================================================================//
  // ------ FS HELPERS ------ //
  //=================================================================================================//

  function stdPath() internal pure returns (string memory) {
    return './test/testdata/hub.impl.json';
  }

  function readImpl(string memory path) internal view returns (Chain memory) {
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

  function encode(ConsensusLayer memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('governanceEntrypoint', v.governanceEntrypoint);
    o = k.serialize('validatorEntrypoint', v.validatorEntrypoint);
  }

  function encode(Core memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('assetManager', v.assetManager);
    o = k.serialize('assetManagerEntrypoint', v.assetManagerEntrypoint);
    o = k.serialize('hubAsset', v.hubAsset);
    o = k.serialize('hubAssetFactory', v.hubAssetFactory);
    o = k.serialize('crosschainRegistry', v.crosschainRegistry);
  }

  function encode(VLF memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('vaultBasic', v.vaultBasic);
    o = k.serialize('vaultCapped', v.vaultCapped);
    o = k.serialize('vaultFactory', v.vaultFactory);
  }

  function encode(Governance memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('branchEntrypoint', v.branchEntrypoint);
    o = k.serialize('mito', v.mito);
    o = k.serialize('mitoVP', v.mitoVP);
    o = k.serialize('mitoTimelock', v.mitoTimelock);
  }

  function encode(Reward memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('merkleDistributor', v.merkleDistributor);
    o = k.serialize('treasury', v.treasury);
  }

  function encode(Validator memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('epochFeeder', v.epochFeeder);
    o = k.serialize('contributionFeed', v.contributionFeed);
    o = k.serialize('manager', v.manager);
    o = k.serialize('rewardDistributor', v.rewardDistributor);
    o = k.serialize('staking', v.staking);
    o = k.serialize('stakingGovMITO', v.stakingGovMITO);
    o = k.serialize('stakingHub', v.stakingHub);
  }

  function encode(Chain memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('consensusLayer', encode(v.consensusLayer));
    o = k.serialize('core', encode(v.core));
    o = k.serialize('vlf', encode(v.vlf));
    o = k.serialize('governance', encode(v.governance));
    o = k.serialize('reward', encode(v.reward));
    o = k.serialize('validator', encode(v.validator));
    o = k.serialize('govMITO', v.govMITO);
    o = k.serialize('govMITOEmission', v.govMITOEmission);
    o = k.serialize('reclaimQueue', v.reclaimQueue);
  }

  function decodeConsensusLayer(string memory v, string memory base) internal pure returns (ConsensusLayer memory o) {
    o.governanceEntrypoint = v.readAddress(cat(base, '.governanceEntrypoint'));
    o.validatorEntrypoint = v.readAddress(cat(base, '.validatorEntrypoint'));
  }

  function decodeCore(string memory v, string memory base) internal pure returns (Core memory o) {
    o.assetManager = v.readAddress(cat(base, '.assetManager'));
    o.assetManagerEntrypoint = v.readAddress(cat(base, '.assetManagerEntrypoint'));
    o.hubAsset = v.readAddress(cat(base, '.hubAsset'));
    o.hubAssetFactory = v.readAddress(cat(base, '.hubAssetFactory'));
    o.crosschainRegistry = v.readAddress(cat(base, '.crosschainRegistry'));
  }

  function decodeVLF(string memory v, string memory base) internal pure returns (VLF memory o) {
    o.vaultBasic = v.readAddress(cat(base, '.vaultBasic'));
    o.vaultCapped = v.readAddress(cat(base, '.vaultCapped'));
    o.vaultFactory = v.readAddress(cat(base, '.vaultFactory'));
  }

  function decodeGovernance(string memory v, string memory base) internal pure returns (Governance memory o) {
    o.branchEntrypoint = v.readAddress(cat(base, '.branchEntrypoint'));
    o.mito = v.readAddress(cat(base, '.mito'));
    o.mitoVP = v.readAddress(cat(base, '.mitoVP'));
    o.mitoTimelock = v.readAddress(cat(base, '.mitoTimelock'));
  }

  function decodeReward(string memory v, string memory base) internal pure returns (Reward memory o) {
    o.merkleDistributor = v.readAddress(cat(base, '.merkleDistributor'));
    o.treasury = v.readAddress(cat(base, '.treasury'));
  }

  function decodeValidator(string memory v, string memory base) internal pure returns (Validator memory o) {
    o.epochFeeder = v.readAddress(cat(base, '.epochFeeder'));
    o.contributionFeed = v.readAddress(cat(base, '.contributionFeed'));
    o.manager = v.readAddress(cat(base, '.manager'));
    o.rewardDistributor = v.readAddress(cat(base, '.rewardDistributor'));
    o.staking = v.readAddress(cat(base, '.staking'));
    o.stakingGovMITO = v.readAddress(cat(base, '.stakingGovMITO'));
    o.stakingHub = v.readAddress(cat(base, '.stakingHub'));
  }

  function decode(string memory v) internal pure returns (Chain memory o) {
    o.consensusLayer = decodeConsensusLayer(v, '.consensusLayer');
    o.core = decodeCore(v, '.core');
    o.vlf = decodeVLF(v, '.vlf');
    o.governance = decodeGovernance(v, '.governance');
    o.reward = decodeReward(v, '.reward');
    o.validator = decodeValidator(v, '.validator');
    //
    o.govMITO = v.readAddress('.govMITO');
    o.govMITOEmission = v.readAddress('.govMITOEmission');
    o.reclaimQueue = v.readAddress('.reclaimQueue');
  }
}
