// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { console } from '@std/console.sol';
import { Test } from '@std/Test.sol';
import { Vm } from '@std/Vm.sol';

import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { CrossChainRegistry } from '../../../src/hub/cross-chain/CrossChainRegistry.sol';

contract CrossChainRegistryTest is Test {
  CrossChainRegistry ccRegistry;
  address owner = makeAddr('owner');

  function setUp() public {
    ccRegistry = CrossChainRegistry(
      payable(
        new ERC1967Proxy(
          address(new CrossChainRegistry()), abi.encodeWithSelector(CrossChainRegistry.initialize.selector, owner)
        )
      )
    );
  }

  function test_auth() public {
    uint256 chainID = 1;
    string memory name = 'Ethereum';
    uint32 hplDomain = 1;
    address mitosisVaultEntrypoint = makeAddr('mitosisVaultEntrypoint');
    address governanceEntrypoint = makeAddr('governanceEntrypoint');

    vm.expectRevert(); // 'AccessControlUnauthorizedAccount'
    ccRegistry.setChain(chainID, name, hplDomain, mitosisVaultEntrypoint, governanceEntrypoint);

    vm.prank(owner);
    ccRegistry.transferOwnership(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496);

    ccRegistry.acceptOwnership();
    ccRegistry.setChain(chainID, name, hplDomain, mitosisVaultEntrypoint, governanceEntrypoint);
  }

  function test_setChain() public {
    uint256 chainID = 1;
    string memory name = 'Ethereum';
    uint32 hplDomain = 1;
    address mitosisVaultEntrypoint = makeAddr('mitosisVaultEntrypoint');
    address governanceEntrypoint = makeAddr('governanceEntrypoint');

    vm.startPrank(owner);
    ccRegistry.setChain(chainID, name, hplDomain, mitosisVaultEntrypoint, governanceEntrypoint);

    vm.expectRevert(); // 'already registered chain'
    ccRegistry.setChain(chainID, name, hplDomain, mitosisVaultEntrypoint, governanceEntrypoint);

    uint256[] memory chainIds = ccRegistry.chainIds();
    require(chainIds.length == 1, 'invalid chainIds');
    require(chainIds[0] == chainID, 'invalid chainIds');
    require(
      keccak256(abi.encodePacked(ccRegistry.chainName(1))) == keccak256(abi.encodePacked(name)), 'invalid chainName'
    );
    require(ccRegistry.hyperlaneDomain(chainID) == hplDomain, 'invalid hyperlaneDomain');
    require(ccRegistry.mitosisVaultEntrypoint(chainID) == mitosisVaultEntrypoint, 'invalid mitosisVaultEntrypoint');
    require(ccRegistry.governanceEntrypoint(chainID) == governanceEntrypoint, 'invalid governanceEntrypoint');
    require(ccRegistry.chainId(hplDomain) == chainID, 'invalid chainId');

    vm.stopPrank();
  }

  function test_setVault() public {
    uint256 chainID = 1;
    address vault = makeAddr('vault');
    address mitosisVaultEntrypoint = makeAddr('mitosisVaultEntrypoint');
    address governanceEntrypoint = makeAddr('governanceEntrypoint');

    vm.startPrank(owner);

    vm.expectRevert(); // 'not registered chain'
    ccRegistry.setVault(chainID, vault);

    string memory name = 'Ethereum';
    uint32 hplDomain = 1;
    ccRegistry.setChain(chainID, name, hplDomain, mitosisVaultEntrypoint, governanceEntrypoint);
    ccRegistry.setVault(chainID, vault);
    require(ccRegistry.mitosisVault(chainID) == vault, 'invalid mitosisVault');

    vm.stopPrank();
  }
}
