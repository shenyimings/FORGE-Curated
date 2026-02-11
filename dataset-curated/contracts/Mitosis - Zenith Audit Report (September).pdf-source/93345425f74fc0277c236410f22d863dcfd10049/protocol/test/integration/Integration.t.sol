// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import '../util/Functions.sol';
import { MockEnvironment } from '../util/MockEnvironment.sol';
import { BranchConfigs } from '../util/types/BranchConfigs.sol';
import { BranchImplT } from '../util/types/BranchImplT.sol';
import { BranchProxyT } from '../util/types/BranchProxyT.sol';
import { HubConfigs } from '../util/types/HubConfigs.sol';
import { HubImplT } from '../util/types/HubImplT.sol';
import { HubProxyT } from '../util/types/HubProxyT.sol';

contract IntegrationTest is MockEnvironment {
  address internal owner = makeAddr('owner');
  address internal govAdmin = makeAddr('govAdmin');

  string[] internal branchNames;

  function setUp() public override {
    super.setUp();
    branchNames.push('a');
    branchNames.push('b');
  }

  function test_init() public {
    MockEnv memory env = setUpEnv(owner, govAdmin, branchNames);

    backUpEnv(env);

    _printCreate3Contracts();
  }
}
