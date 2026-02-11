// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { stdJson } from '@std/StdJson.sol';
import { Vm, VmSafe } from '@std/Vm.sol';

import { SafeCast } from '@oz/utils/math/SafeCast.sol';

import { LibString } from '@solady/utils/LibString.sol';

import '../Functions.sol';

library BranchConfigs {
  using LibString for *;
  using stdJson for string;
  using SafeCast for uint256;

  address private constant VM_ADDRESS = address(uint160(uint256(keccak256('hevm cheat code'))));
  Vm private constant vm = Vm(VM_ADDRESS);

  struct TimelockConfig {
    uint256 minDelay;
    address[] proposers;
    address[] executors;
  }

  struct DeployConfig {
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
  // ----- Codec Helpers -----
  // =================================================================================== //

  // ----- Encoder ----- //

  function encode(TimelockConfig memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('minDelay', v.minDelay);
    o = o.serialize('proposers', v.proposers);
    o = o.serialize('executors', v.executors);
  }

  function encode(DeployConfig memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('timelock', encode(v.timelock));
  }

  // ----- Decoder ----- //

  function decodeTimelockConfig(string memory v, string memory base) internal pure returns (TimelockConfig memory o) {
    o.minDelay = v.readUint(cat(base, '.minDelay'));
    o.proposers = v.readAddressArray(cat(base, '.proposers'));
    o.executors = v.readAddressArray(cat(base, '.executors'));
  }

  function decodeDeployConfig(string memory v) internal pure returns (DeployConfig memory o) {
    o.timelock = decodeTimelockConfig(v, '.timelock');
  }
}
