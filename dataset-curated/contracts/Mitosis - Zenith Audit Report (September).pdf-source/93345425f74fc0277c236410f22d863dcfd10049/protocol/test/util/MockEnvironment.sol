// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';

import { MockMailbox } from '@hpl/mock/MockMailbox.sol';
import { TestInterchainGasPaymaster } from '@hpl/test/TestInterchainGasPaymaster.sol';
import { TestIsm } from '@hpl/test/TestIsm.sol';

import { ISudoVotes } from '../../src/interfaces/lib/ISudoVotes.sol';
import { BranchConfigs } from '../util/types/BranchConfigs.sol';
import { BranchImplT } from '../util/types/BranchImplT.sol';
import { BranchProxyT } from '../util/types/BranchProxyT.sol';
import { HubConfigs } from '../util/types/HubConfigs.sol';
import { HubImplT } from '../util/types/HubImplT.sol';
import { HubProxyT } from '../util/types/HubProxyT.sol';
import { BranchDeployer } from './deployers/BranchDeployer.sol';
import { HubDeployer } from './deployers/HubDeployer.sol';
import './Functions.sol';

struct Hub {
  uint32 domain;
  MockMailbox mailbox;
  HubImplT.Chain impl;
  HubProxyT.Chain proxy;
}

struct Branch {
  string name;
  uint32 domain;
  MockMailbox mailbox;
  BranchImplT.Chain impl;
  BranchProxyT.Chain proxy;
}

contract Linker is Test {
  function link(address hubOwner, address, Hub memory hub, Branch[] memory branches) internal {
    for (uint256 i = 0; i < branches.length; i++) {
      Branch memory branch = branches[i];
      hub.mailbox.addRemoteMailbox(branch.domain, branch.mailbox);
    }

    vm.startPrank(hubOwner);

    for (uint256 i = 0; i < branches.length; i++) {
      Branch memory branch = branches[i];

      hub.proxy.core.crosschainRegistry.setChain(
        branch.domain,
        branch.name,
        branch.domain,
        address(branch.proxy.mitosisVault),
        address(branch.proxy.mitosisVaultEntrypoint),
        address(branch.proxy.governance.entrypoint)
      );
    }

    hub.proxy.core.crosschainRegistry.enrollGovernanceEntrypoint(address(hub.proxy.governance.branchEntrypoint));
    hub.proxy.core.crosschainRegistry.enrollMitosisVaultEntrypoint(address(hub.proxy.core.assetManagerEntrypoint));

    vm.stopPrank();
  }

  function linkHub(address owner, address govAdmin, HubProxyT.Chain memory hub, HubConfigs.DeployConfig memory config)
    internal
  {
    address govMITOStaking = address(hub.validator.stakings[1].staking);

    // ======= LINK CONTRACT EACH OTHER ======= //
    vm.deal(owner, config.govMITOEmission.total);
    vm.startPrank(owner);

    hub.core.assetManager.setReclaimQueue(address(hub.reclaimQueue));

    hub.govMITO.setModule(govMITOStaking, true);
    hub.govMITO.setMinter(address(hub.govMITOEmission));
    hub.govMITO.setWhitelistedSender(address(hub.govMITOEmission), true);

    hub.govMITOEmission.addValidatorRewardEmission{ value: config.govMITOEmission.total }();
    hub.govMITOEmission.setValidatorRewardRecipient(address(hub.validator.rewardDistributor));

    hub.govMITOEmission.grantRole(hub.govMITOEmission.VALIDATOR_REWARD_MANAGER_ROLE(), owner);

    hub.consensusLayer.governanceEntrypoint.setPermittedCaller(address(hub.governance.mitoTimelock), true);

    hub.consensusLayer.validatorEntrypoint.setPermittedCaller(address(hub.validator.manager), true);
    hub.consensusLayer.validatorEntrypoint.setPermittedCaller(address(hub.validator.stakingHub), true);

    for (uint256 i = 0; i < hub.validator.stakings.length; i++) {
      address staking = address(hub.validator.stakings[i].staking);
      hub.validator.stakingHub.addNotifier(staking);
    }

    hub.govMITO.setDelegationManager(address(hub.governance.mitoVP));
    ISudoVotes(govMITOStaking).setDelegationManager(address(hub.governance.mitoVP));

    hub.validator.contributionFeed.grantRole(hub.validator.contributionFeed.FEEDER_ROLE(), owner);

    hub.governance.mitoTimelock.grantRole(hub.governance.mitoTimelock.PROPOSER_ROLE(), address(hub.governance.mito));
    hub.governance.mitoTimelock.grantRole(hub.governance.mitoTimelock.PROPOSER_ROLE(), govAdmin);

    hub.governance.mitoTimelock.grantRole(hub.governance.mitoTimelock.EXECUTOR_ROLE(), address(hub.governance.mito));
    hub.governance.mitoTimelock.grantRole(hub.governance.mitoTimelock.EXECUTOR_ROLE(), govAdmin);

    vm.stopPrank();
  }

  function linkBranch(
    address owner,
    address govAdmin,
    BranchProxyT.Chain memory branch,
    BranchConfigs.DeployConfig memory // config
  ) internal {
    vm.startPrank(owner);

    branch.mitosisVault.setEntrypoint(address(branch.mitosisVaultEntrypoint));

    {
      bytes32 proposerRole = branch.governance.timelock.PROPOSER_ROLE();
      bytes32 executorRole = branch.governance.timelock.EXECUTOR_ROLE();
      address entrypoint = address(branch.governance.entrypoint);

      branch.governance.timelock.grantRole(proposerRole, entrypoint);
      branch.governance.timelock.grantRole(proposerRole, govAdmin);

      branch.governance.timelock.grantRole(executorRole, entrypoint);
      branch.governance.timelock.grantRole(executorRole, govAdmin);
    }

    vm.stopPrank();
  }
}

abstract contract MockEnvironment is Linker, HubDeployer, BranchDeployer {
  using HubProxyT for HubProxyT.Chain;
  using HubImplT for HubImplT.Chain;
  using BranchProxyT for BranchProxyT.Chain;
  using BranchImplT for BranchImplT.Chain;

  struct MockEnv {
    Hub hub;
    Branch[] branches;
  }

  uint32 private _nextDomain = 12345;

  function version() internal pure override returns (string memory) {
    return 'v1';
  }

  function setUpEnv(address owner, address govAdmin, string[] memory branchNames) internal returns (MockEnv memory env) {
    // deploy all
    env.hub = _deployHub(owner, govAdmin);
    env.branches = new Branch[](branchNames.length);
    for (uint256 i = 0; i < branchNames.length; i++) {
      env.branches[i] = _deployBranch(
        owner,
        govAdmin,
        branchNames[i],
        env.hub.domain,
        toBz32(address(env.hub.proxy.core.assetManagerEntrypoint)),
        toBz32(address(env.hub.proxy.governance.branchEntrypoint))
      );
    }

    link(owner, govAdmin, env.hub, env.branches);
  }

  function backUpEnv(MockEnv memory env) internal {
    for (uint256 i = 0; i < env.branches.length; i++) {
      env.branches[i].impl.write(BranchImplT.stdPath(env.branches[i].name));
      env.branches[i].proxy.write(BranchProxyT.stdPath(env.branches[i].name));
    }

    env.hub.impl.write(HubImplT.stdPath());
    env.hub.proxy.write(HubProxyT.stdPath());
  }

  function _setUpMailbox() private returns (uint32, MockMailbox) {
    uint32 domain = _nextDomain++;

    MockMailbox mailbox = new MockMailbox(domain);

    mailbox.setDefaultIsm(address(new TestIsm()));
    mailbox.setDefaultHook(address(new TestInterchainGasPaymaster()));

    return (domain, mailbox);
  }

  function _deployHub(address owner, address govAdmin) private returns (Hub memory hub) {
    HubConfigs.DeployConfig memory config = HubConfigs.read(_deployConfigPath('hub'));
    (hub.domain, hub.mailbox) = _setUpMailbox();
    (hub.impl, hub.proxy) = deployHub(address(hub.mailbox), owner, config);

    linkHub(owner, govAdmin, hub.proxy, config);
  }

  function _deployBranch(
    address owner,
    address govAdmin,
    string memory name,
    uint32 hubDomain,
    bytes32 hubMitosisVaultEntrypointAddress,
    bytes32 hubGovernanceEntrypointAddress
  ) private returns (Branch memory branch) {
    BranchConfigs.DeployConfig memory config = BranchConfigs.read(_deployConfigPath(cat('branch-', name)));

    branch.name = name;
    (branch.domain, branch.mailbox) = _setUpMailbox();
    (branch.impl, branch.proxy) = deployBranch(
      name, //
      address(branch.mailbox),
      owner,
      hubDomain,
      hubMitosisVaultEntrypointAddress,
      hubGovernanceEntrypointAddress,
      config
    );

    linkBranch(owner, govAdmin, branch.proxy, config);
  }

  function _mailboxes(MockEnv memory env) private pure returns (MockMailbox[] memory) {
    MockMailbox[] memory mailboxes = new MockMailbox[](env.branches.length + 1);
    mailboxes[0] = env.hub.mailbox;
    for (uint256 i = 0; i < env.branches.length; i++) {
      mailboxes[i + 1] = env.branches[i].mailbox;
    }
    return mailboxes;
  }

  function _deployConfigPath(string memory chain) private pure returns (string memory) {
    return cat('./test/testdata/deploy-', chain, '.config.json');
  }
}
