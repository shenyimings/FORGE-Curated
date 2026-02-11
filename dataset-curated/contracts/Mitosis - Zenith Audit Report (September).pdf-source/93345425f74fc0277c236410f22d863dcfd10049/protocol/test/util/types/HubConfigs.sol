// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { stdJson } from '@std/StdJson.sol';
import { Vm, VmSafe } from '@std/Vm.sol';

import { SafeCast } from '@oz/utils/math/SafeCast.sol';

import { LibString } from '@solady/utils/LibString.sol';

import { IGovMITOEmission } from '../../../src/interfaces/hub/IGovMITOEmission.sol';
import { IValidatorManager } from '../../../src/interfaces/hub/validator/IValidatorManager.sol';
import '../Functions.sol';

library HubConfigs {
  using LibString for *;
  using stdJson for string;
  using SafeCast for uint256;

  address private constant VM_ADDRESS = address(uint160(uint256(keccak256('hevm cheat code'))));
  Vm private constant vm = Vm(VM_ADDRESS);

  struct ValidatorStakingConfig {
    uint256 minStakingAmount;
    uint256 minUnstakingAmount;
    uint48 unstakeCooldown;
    uint48 redelegationCooldown;
  }

  struct ValidatorManagerConfig {
    uint256 fee;
    IValidatorManager.SetGlobalValidatorConfigRequest globalConfig;
    IValidatorManager.GenesisValidatorSet[] genesisValidatorSet;
  }

  struct ValidatorRewardDistributorConfig {
    uint32 maxClaimEpochs;
    uint32 maxStakerBatchSize;
    uint32 maxOperatorBatchSize;
  }

  struct GovMITOConfig {
    uint256 withdrawalPeriod;
  }

  struct GovMITOEmissionConfig {
    uint256 rps;
    uint160 rateMultiplier;
    uint48 renewalPeriod;
    uint48 startsFrom;
    uint256 total;
  }

  struct MITOGovernanceConfig {
    uint48 votingDelay;
    uint32 votingPeriod;
    uint256 quorumFraction;
    uint256 proposalThreshold;
  }

  struct BranchGovernanceConfig {
    address[] managers;
  }

  struct TimelockConfig {
    uint256 minDelay;
    address[] proposers;
    address[] executors;
  }

  struct EpochFeederConfig {
    uint48 initialEpochTime;
    uint48 interval;
  }

  struct DeployConfig {
    EpochFeederConfig epochFeeder;
    ValidatorManagerConfig validatorManager;
    ValidatorStakingConfig mitoStakingConfig;
    ValidatorStakingConfig govMITOStakingConfig;
    ValidatorRewardDistributorConfig validatorRewardDistributor;
    GovMITOConfig govMITO;
    GovMITOEmissionConfig govMITOEmission;
    MITOGovernanceConfig mitoGovernance;
    BranchGovernanceConfig branchGovernance;
    TimelockConfig timelock;
  }

  // =================================================================================== //
  // ----- FS Helpers -----
  // =================================================================================== //

  function read(string memory path) internal view returns (DeployConfig memory) {
    string memory json = vm.readFile(path);
    return decodeDeployConfig(json);
  }

  function write(DeployConfig memory v, string memory path) internal {
    if (vm.exists(path)) vm.removeFile(path); // replace
    string memory json = encode(v);
    vm.writeJson(json, path);
    vm.writeFile(path, cat(vm.readFile(path), '\n'));
  }

  // =================================================================================== //
  // ----- Type Helpers -----
  // =================================================================================== //

  function append(IValidatorManager.GenesisValidatorSet[] memory arr, IValidatorManager.GenesisValidatorSet memory val)
    internal
    pure
    returns (IValidatorManager.GenesisValidatorSet[] memory o)
  {
    o = new IValidatorManager.GenesisValidatorSet[](arr.length + 1);
    for (uint256 i = 0; i < arr.length; i++) {
      o[i] = arr[i];
    }
    o[arr.length] = val;
  }

  // =================================================================================== //
  // ----- Codec Helpers -----
  // =================================================================================== //

  // --- Encoding ---

  function encode(ValidatorStakingConfig memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('minStakingAmount', v.minStakingAmount);
    o = k.serialize('minUnstakingAmount', v.minUnstakingAmount);
    o = k.serialize('unstakeCooldown', v.unstakeCooldown);
    o = k.serialize('redelegationCooldown', v.redelegationCooldown);
  }

  function encode(IValidatorManager.SetGlobalValidatorConfigRequest memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('initialValidatorDeposit', v.initialValidatorDeposit);
    o = k.serialize('collateralWithdrawalDelaySeconds', v.collateralWithdrawalDelaySeconds);
    o = k.serialize('minimumCommissionRate', v.minimumCommissionRate);
    o = k.serialize('commissionRateUpdateDelayEpoch', v.commissionRateUpdateDelayEpoch);
  }

  function encode(IValidatorManager.GenesisValidatorSet[] memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();

    string[] memory arr = new string[](v.length);

    for (uint256 i = 0; i < v.length; i++) {
      string memory nk = vm.randomBytes(32).toHexString();

      o = nk.serialize('pubKey', v[i].pubKey);
      o = nk.serialize('operator', v[i].operator);
      o = nk.serialize('rewardManager', v[i].rewardManager);
      o = nk.serialize('commissionRate', v[i].commissionRate);
      o = nk.serialize('metadata', v[i].metadata);
      o = nk.serialize('signature', v[i].signature);
      o = nk.serialize('value', v[i].value);

      arr[i] = o;
    }

    o = k.serialize('genesisValidatorSet', arr);
  }

  function encode(ValidatorManagerConfig memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('fee', v.fee);
    o = k.serialize('globalConfig', encode(v.globalConfig));
    o = k.serialize('genesisValidatorSet', encode(v.genesisValidatorSet));
  }

  function encode(ValidatorRewardDistributorConfig memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('maxClaimEpochs', v.maxClaimEpochs);
    o = k.serialize('maxStakerBatchSize', v.maxStakerBatchSize);
    o = k.serialize('maxOperatorBatchSize', v.maxOperatorBatchSize);
  }

  function encode(GovMITOConfig memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('withdrawalPeriod', v.withdrawalPeriod);
  }

  function encode(GovMITOEmissionConfig memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('rps', v.rps);
    o = k.serialize('rateMultiplier', v.rateMultiplier);
    o = k.serialize('renewalPeriod', v.renewalPeriod);
    o = k.serialize('startsFrom', v.startsFrom);
    o = k.serialize('total', v.total);
  }

  function encode(MITOGovernanceConfig memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('votingDelay', v.votingDelay);
    o = k.serialize('votingPeriod', v.votingPeriod);
    o = k.serialize('quorumFraction', v.quorumFraction);
    o = k.serialize('proposalThreshold', v.proposalThreshold);
  }

  function encode(BranchGovernanceConfig memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('managers', v.managers);
  }

  function encode(TimelockConfig memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('minDelay', v.minDelay);
    o = k.serialize('proposers', v.proposers);
    o = k.serialize('executors', v.executors);
  }

  function encode(EpochFeederConfig memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('initialEpochTime', v.initialEpochTime);
    o = k.serialize('interval', v.interval);
  }

  function encode(DeployConfig memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('epochFeeder', encode(v.epochFeeder));
    o = k.serialize('validatorManager', encode(v.validatorManager));
    o = k.serialize('mitoStakingConfig', encode(v.mitoStakingConfig));
    o = k.serialize('govMITOStakingConfig', encode(v.govMITOStakingConfig));
    o = k.serialize('validatorRewardDistributor', encode(v.validatorRewardDistributor));
    o = k.serialize('govMITO', encode(v.govMITO));
    o = k.serialize('govMITOEmission', encode(v.govMITOEmission));
    o = k.serialize('mitoGovernance', encode(v.mitoGovernance));
    o = k.serialize('branchGovernance', encode(v.branchGovernance));
    o = k.serialize('timelock', encode(v.timelock));
  }

  // --- Decoding ---

  function decodeValidatorStakingConfig(string memory v, string memory base)
    internal
    pure
    returns (ValidatorStakingConfig memory o)
  {
    o.minStakingAmount = v.readUint(cat(base, '.minStakingAmount'));
    o.minUnstakingAmount = v.readUint(cat(base, '.minUnstakingAmount'));
    o.unstakeCooldown = v.readUint(cat(base, '.unstakeCooldown')).toUint48();
    o.redelegationCooldown = v.readUint(cat(base, '.redelegationCooldown')).toUint48();
  }

  function decodeGlobalValidatorConfig(string memory v, string memory base)
    internal
    pure
    returns (IValidatorManager.SetGlobalValidatorConfigRequest memory o)
  {
    o.initialValidatorDeposit = v.readUint(cat(base, '.initialValidatorDeposit'));
    o.collateralWithdrawalDelaySeconds = v.readUint(cat(base, '.collateralWithdrawalDelaySeconds'));
    o.minimumCommissionRate = v.readUint(cat(base, '.minimumCommissionRate'));
    o.commissionRateUpdateDelayEpoch = v.readUint(cat(base, '.commissionRateUpdateDelayEpoch')).toUint96();
  }

  function decodeValidatorManagerConfig(string memory v, string memory base)
    internal
    view
    returns (ValidatorManagerConfig memory o)
  {
    o.fee = v.readUint(cat(base, '.fee'));
    o.globalConfig = decodeGlobalValidatorConfig(v, cat(base, '.globalConfig'));

    {
      uint256 i = 0;
      string memory b = cat(base, '.genesisValidatorSet');
      string memory nk = cat(b, '[', (i++).toString(), ']');
      while (vm.keyExistsJson(v, nk)) {
        IValidatorManager.GenesisValidatorSet memory val;

        val.pubKey = v.readBytes(cat(nk, '.pubKey'));
        val.operator = v.readAddress(cat(nk, '.operator'));
        val.rewardManager = v.readAddress(cat(nk, '.rewardManager'));
        val.commissionRate = v.readUint(cat(nk, '.commissionRate'));
        val.metadata = v.readBytes(cat(nk, '.metadata'));
        val.signature = v.readBytes(cat(nk, '.signature'));
        val.value = v.readUint(cat(nk, '.value'));

        o.genesisValidatorSet = append(o.genesisValidatorSet, val);
        nk = cat(b, '[', (i++).toString(), ']');
      }
    }
  }

  function decodeValidatorRewardDistributorConfig(string memory v, string memory base)
    internal
    pure
    returns (ValidatorRewardDistributorConfig memory o)
  {
    o.maxClaimEpochs = v.readUint(cat(base, '.maxClaimEpochs')).toUint32();
    o.maxStakerBatchSize = v.readUint(cat(base, '.maxStakerBatchSize')).toUint32();
    o.maxOperatorBatchSize = v.readUint(cat(base, '.maxOperatorBatchSize')).toUint32();
  }

  function decodeGovMITOConfig(string memory v, string memory base) internal pure returns (GovMITOConfig memory o) {
    o.withdrawalPeriod = v.readUint(cat(base, '.withdrawalPeriod'));
  }

  function decodeGovMITOEmissionConfig(string memory v, string memory base)
    internal
    pure
    returns (GovMITOEmissionConfig memory o)
  {
    o.rps = v.readUint(cat(base, '.rps'));
    o.rateMultiplier = v.readUint(cat(base, '.rateMultiplier')).toUint160();
    o.renewalPeriod = v.readUint(cat(base, '.renewalPeriod')).toUint48();
    o.startsFrom = v.readUint(cat(base, '.startsFrom')).toUint48();
    o.total = v.readUint(cat(base, '.total'));
  }

  function decodeMITOGovernanceConfig(string memory v, string memory base)
    internal
    pure
    returns (MITOGovernanceConfig memory o)
  {
    o.votingDelay = v.readUint(cat(base, '.votingDelay')).toUint48();
    o.votingPeriod = v.readUint(cat(base, '.votingPeriod')).toUint32();
    o.quorumFraction = v.readUint(cat(base, '.quorumFraction'));
    o.proposalThreshold = v.readUint(cat(base, '.proposalThreshold'));
  }

  function decodeBranchGovernanceConfig(string memory v, string memory base)
    internal
    pure
    returns (BranchGovernanceConfig memory o)
  {
    o.managers = v.readAddressArray(cat(base, '.managers'));
  }

  function decodeTimelockConfig(string memory v, string memory base) internal pure returns (TimelockConfig memory o) {
    o.minDelay = v.readUint(cat(base, '.minDelay'));
    o.proposers = v.readAddressArray(cat(base, '.proposers'));
    o.executors = v.readAddressArray(cat(base, '.executors'));
  }

  function decodeEpochFeederConfig(string memory v, string memory base)
    internal
    pure
    returns (EpochFeederConfig memory o)
  {
    o.initialEpochTime = v.readUint(cat(base, '.initialEpochTime')).toUint48();
    o.interval = v.readUint(cat(base, '.interval')).toUint48();
  }

  function decodeDeployConfig(string memory v) internal view returns (DeployConfig memory o) {
    o.epochFeeder = decodeEpochFeederConfig(v, '.epochFeeder');
    o.validatorManager = decodeValidatorManagerConfig(v, '.validatorManager');
    o.mitoStakingConfig = decodeValidatorStakingConfig(v, '.mitoStakingConfig');
    o.govMITOStakingConfig = decodeValidatorStakingConfig(v, '.govMITOStakingConfig');
    o.validatorRewardDistributor = decodeValidatorRewardDistributorConfig(v, '.validatorRewardDistributor');
    o.govMITO = decodeGovMITOConfig(v, '.govMITO');
    o.govMITOEmission = decodeGovMITOEmissionConfig(v, '.govMITOEmission');
    o.mitoGovernance = decodeMITOGovernanceConfig(v, '.mitoGovernance');
    o.branchGovernance = decodeBranchGovernanceConfig(v, '.branchGovernance');
    o.timelock = decodeTimelockConfig(v, '.timelock');
  }
}
