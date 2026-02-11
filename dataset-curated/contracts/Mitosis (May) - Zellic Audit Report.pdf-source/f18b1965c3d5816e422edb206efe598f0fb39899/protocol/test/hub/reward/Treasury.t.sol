// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { Treasury } from '../../../src/hub/reward/Treasury.sol';
import { MockERC20Snapshots } from '../../mock/MockERC20Snapshots.t.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract TreasuryTest is Toolkit {
  MockERC20Snapshots internal _token;
  Treasury internal _treasury;

  address immutable owner = makeAddr('owner');
  address immutable rewarder = makeAddr('rewarder');
  address immutable matrixVault = makeAddr('matrixVault');

  function setUp() public {
    _token = new MockERC20Snapshots();
    _token.initialize('Token', 'TKN');

    _treasury =
      Treasury(payable(new ERC1967Proxy(address(new Treasury()), abi.encodeCall(Treasury.initialize, (owner)))));

    bytes32 treasuryManagerRole = _treasury.TREASURY_MANAGER_ROLE();
    vm.prank(owner);
    _treasury.grantRole(treasuryManagerRole, rewarder);
  }

  function test_storeReward() public {
    _token.mint(rewarder, 100 ether);

    vm.startPrank(rewarder);
    _token.approve(address(_treasury), 100 ether);
    _treasury.storeRewards(matrixVault, address(_token), 100 ether);
    vm.stopPrank();

    assertEq(_token.balanceOf(address(_treasury)), 100 ether);
  }

  function test_dispatch() public {
    test_storeReward();

    address distributor = makeAddr('distributor');

    address dispatcher = makeAddr('dispatcher');
    bytes32 dispatcherRole = _treasury.DISPATCHER_ROLE();
    vm.prank(owner);
    _treasury.grantRole(dispatcherRole, dispatcher);

    vm.prank(dispatcher);
    _treasury.dispatch(matrixVault, address(_token), 100 ether, distributor);

    assertEq(_token.balanceOf(address(_treasury)), 0);
    assertEq(_token.balanceOf(distributor), 100 ether);
  }
}
