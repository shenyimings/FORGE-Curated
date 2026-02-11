// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { console } from '@std/console.sol';

import { Merkle } from '@murky/Merkle.sol';

import { WETH } from '@solady/tokens/WETH.sol';

import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { MerkleRewardDistributor } from '../../../src/hub/reward/MerkleRewardDistributor.sol';
import { Treasury } from '../../../src/hub/reward/Treasury.sol';
import { IMerkleRewardDistributor } from '../../../src/interfaces/hub/reward/IMerkleRewardDistributor.sol';
import { MockERC20Snapshots } from '../../mock/MockERC20Snapshots.t.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract MerkleRewardDistributorTest is Toolkit {
  Treasury internal _treasury;
  MerkleRewardDistributor internal _distributor;
  MockERC20Snapshots internal _token;

  address immutable owner = makeAddr('owner');
  address immutable matrixVault = makeAddr('matrixVault');
  address immutable rewarder = makeAddr('rewarder');

  function setUp() public {
    _treasury =
      Treasury(payable(new ERC1967Proxy(address(new Treasury()), abi.encodeCall(Treasury.initialize, (owner)))));

    _distributor = MerkleRewardDistributor(
      payable(
        new ERC1967Proxy(
          address(new MerkleRewardDistributor()),
          abi.encodeCall(MerkleRewardDistributor.initialize, (owner, address(_treasury)))
        )
      )
    );

    _token = new MockERC20Snapshots();
    _token.initialize('Token', 'TKN');

    bytes32 distributorManagerRole = _distributor.MANAGER_ROLE();

    bytes32 treasuryManagerRole = _treasury.TREASURY_MANAGER_ROLE();
    bytes32 dispatcherRole = _treasury.DISPATCHER_ROLE();

    vm.startPrank(owner);
    _distributor.grantRole(distributorManagerRole, owner);
    _treasury.grantRole(treasuryManagerRole, rewarder);
    _treasury.grantRole(dispatcherRole, address(_distributor));
    vm.stopPrank();
  }

  function test_fetchRewards() public {
    _token.mint(rewarder, 100 ether);

    vm.startPrank(rewarder);
    _token.approve(address(_treasury), 100 ether);
    _treasury.storeRewards(matrixVault, address(_token), 100 ether);
    vm.stopPrank();

    vm.prank(owner);
    _distributor.fetchRewards(0, 0, matrixVault, address(_token), 100 ether);

    assertEq(_token.balanceOf(address(_treasury)), 0);
    assertEq(_token.balanceOf(address(_distributor)), 100 ether);
  }
}
