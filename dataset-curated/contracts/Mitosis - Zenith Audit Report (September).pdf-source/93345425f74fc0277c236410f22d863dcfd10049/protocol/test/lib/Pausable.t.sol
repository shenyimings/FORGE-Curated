// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';

import { Pausable } from '../../src/lib/Pausable.sol';

contract PausableContract is Pausable {
  constructor() {
    __Pausable_init();
  }

  function _authorizePause(address) internal view override { }

  function assertNotPaused() external view {
    require(!_isPaused(msg.sig), Pausable__Paused(msg.sig));
  }

  function assertNotPaused(bytes4 sig) external view {
    require(!_isPaused(sig), Pausable__Paused(sig));
  }

  function assertPaused() external view {
    require(_isPaused(msg.sig), Pausable__NotPaused(msg.sig));
  }

  function assertPaused(bytes4 sig) external view {
    require(_isPaused(sig), Pausable__NotPaused(sig));
  }
}

contract PausableTest is Test {
  PausableContract internal _tester;

  function setUp() public {
    _tester = new PausableContract();
  }

  function test_normal() public {
    bytes4 sig = _sig('foo()');

    assertFalse(_tester.isPaused(sig));
    assertFalse(_tester.isPausedGlobally());

    _tester.pause();

    assertTrue(_tester.isPaused(sig));
    assertTrue(_tester.isPausedGlobally());

    _tester.pause(sig);

    assertTrue(_tester.isPaused(sig));
    assertTrue(_tester.isPausedGlobally());

    _tester.unpause();

    assertTrue(_tester.isPaused(sig));
    assertFalse(_tester.isPausedGlobally());

    _tester.unpause(sig);

    assertFalse(_tester.isPaused(sig));
    assertFalse(_tester.isPausedGlobally());
  }

  function _sig(string memory func) private pure returns (bytes4) {
    return bytes4(keccak256(bytes(func)));
  }
}
