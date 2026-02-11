// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { stdJson } from '@std/StdJson.sol';
import { Vm, VmSafe } from '@std/Vm.sol';

import { LibString } from '@solady/utils/LibString.sol';

import { GovernanceEntrypoint } from '../../../src/branch/governance/GovernanceEntrypoint.sol';
import { MitosisVault } from '../../../src/branch/MitosisVault.sol';
import { MitosisVaultEntrypoint } from '../../../src/branch/MitosisVaultEntrypoint.sol';
import { BaseDecoderAndSanitizer } from
  '../../../src/branch/strategy/manager/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol';
import { TheoDepositVaultDecoderAndSanitizer } from
  '../../../src/branch/strategy/manager/DecodersAndSanitizers/TheoDepositVaultDecoderAndSanitizer.sol';
import { ManagerWithMerkleVerification } from '../../../src/branch/strategy/manager/ManagerWithMerkleVerification.sol';
import { TheoTally } from '../../../src/branch/strategy/tally/TheoTally.sol';
import { VLFStrategyExecutor } from '../../../src/branch/strategy/VLFStrategyExecutor.sol';
import { VLFStrategyExecutorFactory } from '../../../src/branch/strategy/VLFStrategyExecutorFactory.sol';
import { Timelock } from '../../../src/lib/Timelock.sol';
import '../Functions.sol';

library BranchProxyT {
  using LibString for *;
  using stdJson for string;

  address private constant VM_ADDRESS = address(uint160(uint256(keccak256('hevm cheat code'))));
  Vm private constant vm = Vm(VM_ADDRESS);

  struct VLFStrategyExecutorInfo {
    address owner;
    address branchAsset;
    address branchVault;
    address hubVLFVault;
    VLFStrategyExecutor executor;
  }

  struct Governance {
    Timelock timelock;
    GovernanceEntrypoint entrypoint;
  }

  struct StrategyDecoderAndSanitizer {
    BaseDecoderAndSanitizer base;
    TheoDepositVaultDecoderAndSanitizer theoDepositVault;
  }

  struct StrategyManager {
    StrategyDecoderAndSanitizer das;
    ManagerWithMerkleVerification withMerkleVerification;
  }

  struct Strategy {
    StrategyManager manager;
    VLFStrategyExecutorInfo[] executors;
    VLFStrategyExecutorFactory executorFactory;
  }

  struct Chain {
    Governance governance;
    Strategy strategy;
    MitosisVault mitosisVault;
    MitosisVaultEntrypoint mitosisVaultEntrypoint;
  }

  function stdPath(string memory name) internal pure returns (string memory) {
    return cat('./test/testdata/branch-', name, '.proxy.json');
  }

  function read(string memory path) internal view returns (Chain memory o) {
    string memory json = vm.readFile(path);
    return decode(json);
  }

  function write(Chain memory v, string memory path) internal {
    if (vm.exists(path)) vm.removeFile(path); // replace
    string memory json = encode(v);
    vm.writeJson(json, path);
    vm.writeFile(path, cat(vm.readFile(path), '\n'));
  }

  //=================================================================================================//
  // ------ CODEC ------ //
  //=================================================================================================//

  // --- Encode Functions ---

  function extract(VLFStrategyExecutorInfo[] memory v) private pure returns (address[] memory o) {
    o = new address[](v.length);
    for (uint256 i = 0; i < v.length; i++) {
      o[i] = address(v[i].executor);
    }
  }

  function encode(Governance memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('timelock', address(v.timelock));
    o = k.serialize('entrypoint', address(v.entrypoint));
  }

  function encode(StrategyDecoderAndSanitizer memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('base', address(v.base));
    o = k.serialize('theoDepositVault', address(v.theoDepositVault));
  }

  function encode(StrategyManager memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('das', encode(v.das));
    o = k.serialize('withMerkleVerification', address(v.withMerkleVerification));
  }

  function encode(Strategy memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('manager', encode(v.manager));
    o = k.serialize('executors', extract(v.executors));
    o = k.serialize('executorFactory', address(v.executorFactory));
  }

  function encode(Chain memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('governance', encode(v.governance));
    o = k.serialize('strategy', encode(v.strategy));
    o = k.serialize('mitosisVault', address(v.mitosisVault));
    o = k.serialize('mitosisVaultEntrypoint', address(v.mitosisVaultEntrypoint));
  }

  // --- Decode Functions ---

  function decodeGovernance(string memory v, string memory base) internal pure returns (Governance memory o) {
    o.timelock = Timelock(_r(v, cat(base, '.timelock')));
    o.entrypoint = GovernanceEntrypoint(_r(v, cat(base, '.entrypoint')));
  }

  function decodeStrategyDecoderAndSanitizer(string memory v, string memory base)
    internal
    pure
    returns (StrategyDecoderAndSanitizer memory o)
  {
    o.base = BaseDecoderAndSanitizer(_r(v, cat(base, '.base')));
    o.theoDepositVault = TheoDepositVaultDecoderAndSanitizer(_r(v, cat(base, '.theoDepositVault')));
  }

  function decodeStrategyManager(string memory v, string memory base) internal pure returns (StrategyManager memory o) {
    o.withMerkleVerification = ManagerWithMerkleVerification(_r(v, cat(base, '.withMerkleVerification')));
    o.das = decodeStrategyDecoderAndSanitizer(v, cat(base, '.das'));
  }

  function decodeVLFStrategyExecutors(string memory v, string memory path)
    internal
    view
    returns (VLFStrategyExecutorInfo[] memory o)
  {
    address payable[] memory executors = _ra(v, path);
    o = new VLFStrategyExecutorInfo[](executors.length);

    for (uint256 i = 0; i < executors.length; i++) {
      VLFStrategyExecutor executor = VLFStrategyExecutor(executors[i]);

      o[i] = VLFStrategyExecutorInfo({
        owner: executor.owner(),
        branchAsset: address(executor.asset()),
        branchVault: address(executor.vault()),
        hubVLFVault: executor.hubVLFVault(),
        executor: executor
      });
    }
  }

  function decodeStrategy(string memory v, string memory base) internal view returns (Strategy memory o) {
    o.manager = decodeStrategyManager(v, cat(base, '.manager'));
    o.executors = decodeVLFStrategyExecutors(v, cat(base, '.executors'));
    o.executorFactory = VLFStrategyExecutorFactory(_r(v, cat(base, '.executorFactory')));
  }

  function decode(string memory v) internal view returns (Chain memory o) {
    o.governance = decodeGovernance(v, '.governance');
    o.strategy = decodeStrategy(v, '.strategy');
    o.mitosisVault = MitosisVault(_r(v, '.mitosisVault'));
    o.mitosisVaultEntrypoint = MitosisVaultEntrypoint(_r(v, '.mitosisVaultEntrypoint'));
  }

  function _r(string memory v, string memory path) internal pure returns (address payable) {
    return payable(v.readAddress(path));
  }

  function _ra(string memory v, string memory path) internal pure returns (address payable[] memory o) {
    address[] memory a = v.readAddressArray(path); // Changed from readAddressPayableArray
    o = new address payable[](a.length);
    for (uint256 i = 0; i < a.length; i++) {
      o[i] = payable(a[i]);
    }
  }
}
