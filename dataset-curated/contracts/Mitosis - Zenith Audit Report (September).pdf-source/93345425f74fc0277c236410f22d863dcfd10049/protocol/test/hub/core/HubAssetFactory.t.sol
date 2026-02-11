// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { ERC1967Factory } from '@solady/utils/ERC1967Factory.sol';
import { UpgradeableBeacon } from '@solady/utils/UpgradeableBeacon.sol';

import { HubAsset } from '../../../src/hub/core/HubAsset.sol';
import { HubAssetFactory } from '../../../src/hub/core/HubAssetFactory.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract HubAssetFactoryTest is Toolkit {
  address public contractOwner = makeAddr('owner');
  address public supplyManager = makeAddr('supplyManager');

  ERC1967Factory public proxyFactory;

  HubAsset public hubAssetImpl;
  HubAssetFactory public hubAssetFactoryImpl;
  HubAssetFactory public base;

  function setUp() public {
    proxyFactory = new ERC1967Factory();

    hubAssetImpl = new HubAsset();
    hubAssetFactoryImpl = new HubAssetFactory();
    base = HubAssetFactory(
      payable(
        new ERC1967Proxy(
          address(hubAssetFactoryImpl),
          abi.encodeCall(HubAssetFactory.initialize, (contractOwner, address(hubAssetImpl)))
        )
      )
    );
  }

  function test_init() public view {
    assertEq(address(hubAssetFactoryImpl), _erc1967Impl(address(base)));
    assertEq(address(0x0), _erc1967Beacon(address(base)));

    assertEq(base.owner(), contractOwner);
    assertEq(UpgradeableBeacon(base.beacon()).owner(), address(base));
    assertEq(UpgradeableBeacon(base.beacon()).implementation(), address(hubAssetImpl));
  }

  function test_create() public {
    vm.prank(contractOwner);
    address hubAsset = base.create(contractOwner, supplyManager, 'Test', 'TST', 18);

    assertEq(address(0x0), _erc1967Admin(hubAsset));
    assertEq(address(0x0), _erc1967Impl(hubAsset));
    assertEq(address(base.beacon()), _erc1967Beacon(hubAsset));

    assertEq(base.instancesLength(), 1);
    assertEq(base.instances(0), hubAsset);
  }

  function test_create_ownable() public {
    address nonOwner = makeAddr('nonOwner');

    vm.expectRevert(_errOwnableUnauthorizedAccount(nonOwner));
    vm.prank(nonOwner);
    base.create(nonOwner, supplyManager, 'Test', 'TST', 18);
  }
}
