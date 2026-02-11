// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';

import { WETH } from '@solady/tokens/WETH.sol';

import { IAccessControl } from '@oz/access/IAccessControl.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { IERC20Metadata } from '@oz/token/ERC20/extensions/IERC20Metadata.sol';

import { ReclaimQueueCollector } from '../../src/hub/ReclaimQueueCollector.sol';
import { IReclaimQueueCollector } from '../../src/interfaces/hub/IReclaimQueueCollector.sol';
import { StdError } from '../../src/lib/StdError.sol';

contract ReclaimQueueCollectorTest is Test {
  address admin = makeAddr('admin');
  address queue = makeAddr('reclaimQueue');

  WETH public asset1;
  WETH public asset2;

  ReclaimQueueCollector public collectorImpl;
  ReclaimQueueCollector public collector;

  function setUp() public {
    asset1 = new WETH();
    asset2 = new WETH();

    collectorImpl = new ReclaimQueueCollector(queue);
    collector = ReclaimQueueCollector(
      address(
        new ERC1967Proxy(
          address(collectorImpl), //
          abi.encodeCall(ReclaimQueueCollector.initialize, (admin))
        )
      )
    );
  }

  function test_init() public view {
    assertEq(collector.getRoleMemberCount(collector.DEFAULT_ADMIN_ROLE()), 1);
    assertEq(collector.getRoleMemberCount(collector.ASSET_MAANGER()), 1);
    assertEq(collector.getRoleMemberCount(collector.ROUTE_MANAGER()), 1);
    assertEq(collector.getRoleMember(collector.DEFAULT_ADMIN_ROLE(), 0), admin);
    assertEq(collector.getRoleMember(collector.ASSET_MAANGER(), 0), admin);
    assertEq(collector.getRoleMember(collector.ROUTE_MANAGER(), 0), admin);

    assertEq(collector.reclaimQueue(), queue);
    assertEq(collector.getDefaultRoute(), address(collector));
  }

  function test_collect_default(address vault) public {
    _fund(asset1, queue, 1 ether);

    vm.prank(queue);
    asset1.approve(address(collector), 1 ether);

    vm.expectEmit();
    emit IReclaimQueueCollector.Collected(vault, address(collector), address(asset1), 1 ether);

    vm.prank(queue);
    collector.collect(vault, address(asset1), 1 ether);

    assertEq(asset1.balanceOf(address(collector)), 1 ether);
    assertEq(asset1.balanceOf(queue), 0);
  }

  function test_collect_customRoute(address vault, address route) public {
    _fund(asset1, queue, 1 ether);

    vm.prank(queue);
    asset1.approve(address(collector), 1 ether);

    test_setRoute(vault, route);

    vm.expectEmit();
    emit IReclaimQueueCollector.Collected(vault, route, address(asset1), 1 ether);

    vm.prank(queue);
    collector.collect(vault, address(asset1), 1 ether);

    assertEq(asset1.balanceOf(route), 1 ether);
    assertEq(asset1.balanceOf(queue), 0);
  }

  function test_collect_unauthorized(address vault) public {
    vm.prank(makeAddr('fake_sender'));
    vm.expectRevert(abi.encodeWithSelector(StdError.Unauthorized.selector, makeAddr('fake_sender')));
    collector.collect(vault, address(asset1), 1 ether);
  }

  function test_withdraw(address vault, address receiver, uint256 amount) public {
    vm.assume(receiver != address(0));
    vm.assume(address(collector) != receiver);
    vm.assume(amount <= 1 ether && amount > 0);

    test_collect_default(vault);

    vm.expectEmit();
    emit IReclaimQueueCollector.Withdrawn(address(asset1), receiver, amount);

    vm.prank(admin);
    collector.withdraw(address(asset1), receiver, amount);

    assertEq(asset1.balanceOf(receiver), amount);
    assertEq(asset1.balanceOf(address(collector)), 1 ether - amount);
  }

  function test_withdraw_unauthorized(address vault, address receiver, uint256 amount) public {
    vm.assume(receiver != address(0));
    vm.assume(amount <= 1 ether);

    test_collect_default(vault);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, //
        makeAddr('fake_sender'),
        collector.ASSET_MAANGER()
      )
    );
    vm.prank(makeAddr('fake_sender'));
    collector.withdraw(address(asset1), receiver, amount);
  }

  function test_setRoute(address vault, address route) public {
    vm.assume(vault != address(0) && route != address(0));

    vm.expectEmit();
    emit IReclaimQueueCollector.RouteSet(vault, route);

    vm.prank(admin);
    collector.setRoute(vault, route);

    assertEq(collector.getRoute(vault), route);
  }

  function test_setRoute_unauthorized(address vault, address route) public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, //
        makeAddr('fake_sender'),
        collector.ROUTE_MANAGER()
      )
    );
    vm.prank(makeAddr('fake_sender'));
    collector.setRoute(vault, route);
  }

  function test_setDefaultRoute(address route) public {
    vm.expectEmit();
    emit IReclaimQueueCollector.DefaultRouteSet(route);

    vm.prank(admin);
    collector.setDefaultRoute(route);

    assertEq(collector.getDefaultRoute(), route);
  }

  function test_setDefaultRoute_unauthorized(address route) public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, //
        makeAddr('fake_sender'),
        collector.ROUTE_MANAGER()
      )
    );
    vm.prank(makeAddr('fake_sender'));
    collector.setDefaultRoute(route);
  }

  function _fund(WETH asset, address to, uint256 amount) internal {
    vm.deal(to, amount);
    vm.prank(to);
    asset.deposit{ value: amount }();
  }
}
