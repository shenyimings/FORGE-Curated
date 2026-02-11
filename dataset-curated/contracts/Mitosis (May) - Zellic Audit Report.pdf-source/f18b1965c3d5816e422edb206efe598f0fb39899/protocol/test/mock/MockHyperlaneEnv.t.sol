// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { CommonBase } from '@std/Base.sol';
import { Vm } from '@std/Vm.sol';

import { Ownable } from '@oz/access/Ownable.sol';

import { MockMailbox } from '@hpl/mock/MockMailbox.sol';
import { TestInterchainGasPaymaster } from '@hpl/test/TestInterchainGasPaymaster.sol';

import { LibString } from '@solady/utils/LibString.sol';

/// @dev this contract should be persistent (use vm.makePersistent)
contract MockHyperlaneEnv is CommonBase, Ownable {
  using LibString for string;

  struct Env {
    uint256 forkId;
    uint256 chainId;
    MockMailbox mailbox;
    string domainAlias;
  }

  event MockHyperlaneEnv__Established(uint32 domain, string domainAlias);

  error MockHyperlaneEnv__DomainAlreadyEstablished(uint32 domain);
  error MockHyperlaneEnv__EnvNotFoundForDomain(uint32 domain);
  error MockHyperlaneEnv__EnvNotFoundForDomainAlias(string domainAlias);

  uint32[] public domains;
  mapping(uint32 domain => Env env) public envs;

  string[] public domainAliases;
  mapping(uint256 domainAliasIndex => uint32 domain) public domainAliasToDomain;

  constructor(address owner_) Ownable(owner_) { }

  function envOf(uint32 domain) external view returns (Env memory env) {
    env = envs[domain];
    require(env.forkId != 0, MockHyperlaneEnv__EnvNotFoundForDomain(domain));
    return env;
  }

  function envOf(string memory domainAlias) external view returns (Env memory) {
    for (uint256 i = 0; i < domainAliases.length; i++) {
      if (domainAliases[i].eq(domainAlias)) return envs[domainAliasToDomain[i]];
    }

    revert MockHyperlaneEnv__EnvNotFoundForDomainAlias(domainAlias);
  }

  function establish(uint32 domain, string memory domainAlias) external onlyOwner returns (Env memory) {
    require(envs[domain].forkId == 0, MockHyperlaneEnv__DomainAlreadyEstablished(domain));

    uint256 currentForkId = vm.activeFork();
    uint256 forkId = vm.createSelectFork(domainAlias);
    uint256 chainId = block.chainid; // in general, it's the same as Hyperlane domain.

    // deployment
    MockMailbox mailbox = new MockMailbox(domain);
    TestInterchainGasPaymaster defaultHook = new TestInterchainGasPaymaster();

    // set default hook to igp
    mailbox.setDefaultHook(address(defaultHook));

    // connect each other
    for (uint256 i = 0; i < domains.length; i++) {
      mailbox.addRemoteMailbox(domains[i], envs[domains[i]].mailbox);
    }

    envs[domain] = Env({
      forkId: forkId,
      chainId: chainId,
      mailbox: mailbox,
      domainAlias: domainAlias //
     });
    domains.push(domain);
    domainAliases.push(domainAlias);

    vm.selectFork(currentForkId); // return to the original fork

    emit MockHyperlaneEnv__Established(domain, domainAlias);

    return envs[domain];
  }
}
