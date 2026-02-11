// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { stdJson } from '@std/StdJson.sol';
import { Vm, VmSafe } from '@std/Vm.sol';

import { WETH } from '@solady/tokens/WETH.sol';
import { LibString } from '@solady/utils/LibString.sol';

import '../Functions.sol';

library BranchImplT {
  using LibString for *;
  using stdJson for string;

  address private constant VM_ADDRESS = address(uint160(uint256(keccak256('hevm cheat code'))));
  Vm private constant vm = Vm(VM_ADDRESS);

  struct Governance {
    address timelock;
    address entrypoint;
  }

  struct StrategyManager {
    address withMerkleVerification;
  }

  struct Strategy {
    StrategyManager manager;
    address executor;
    address executorFactory;
  }

  struct Chain {
    Governance governance;
    Strategy strategy;
    WETH nativeWrappedToken;
    address mitosisVault;
    address mitosisVaultEntrypoint;
  }

  function stdPath(string memory name) internal pure returns (string memory) {
    return cat('./test/testdata/branch-', name, '.impl.json');
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

  function encode(Governance memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('timelock', v.timelock);
    o = k.serialize('entrypoint', v.entrypoint);
  }

  function encode(StrategyManager memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('withMerkleVerification', v.withMerkleVerification);
  }

  function encode(Strategy memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('manager', encode(v.manager));
    o = k.serialize('executor', v.executor);
    o = k.serialize('executorFactory', v.executorFactory);
  }

  function encode(Chain memory v) internal returns (string memory o) {
    string memory k = vm.randomBytes(32).toHexString();
    o = k.serialize('governance', encode(v.governance));
    o = k.serialize('strategy', encode(v.strategy));
    o = k.serialize('nativeWrappedToken', address(v.nativeWrappedToken));
    o = k.serialize('mitosisVault', v.mitosisVault);
    o = k.serialize('mitosisVaultEntrypoint', v.mitosisVaultEntrypoint);
  }

  // --- Decode Functions ---

  function decodeGovernance(string memory v, string memory base) internal pure returns (Governance memory o) {
    o.timelock = v.readAddress(cat(base, '.timelock'));
    o.entrypoint = v.readAddress(cat(base, '.entrypoint'));
  }

  function decodeStrategyManager(string memory v, string memory base) internal pure returns (StrategyManager memory o) {
    o.withMerkleVerification = v.readAddress(cat(base, '.withMerkleVerification'));
  }

  function decodeStrategy(string memory v, string memory base) internal pure returns (Strategy memory o) {
    o.manager = decodeStrategyManager(v, cat(base, '.manager'));
    o.executor = v.readAddress(cat(base, '.executor'));
    o.executorFactory = v.readAddress(cat(base, '.executorFactory'));
  }

  function decode(string memory v) internal pure returns (Chain memory o) {
    o.governance = decodeGovernance(v, '.governance');
    o.strategy = decodeStrategy(v, '.strategy');
    o.nativeWrappedToken = WETH(payable(v.readAddress('.nativeWrappedToken')));
    o.mitosisVault = v.readAddress('.mitosisVault');
    o.mitosisVaultEntrypoint = v.readAddress('.mitosisVaultEntrypoint');
  }
}
