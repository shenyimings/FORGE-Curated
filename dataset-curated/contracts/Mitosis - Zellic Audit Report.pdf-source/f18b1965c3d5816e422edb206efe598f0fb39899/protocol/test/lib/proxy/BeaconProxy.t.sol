// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Initializable } from '@oz/proxy/utils/Initializable.sol';

import { UpgradeableBeacon } from '@solady/utils/UpgradeableBeacon.sol';

import { IBeaconProxy, BeaconProxy } from '../../../src/lib/proxy/BeaconProxy.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract BeaconInstanceV1 is Initializable {
  string public buffer;

  constructor() {
    _disableInitializers();
  }

  function initialize(string memory buffer_) external initializer {
    buffer = buffer_;
  }
}

contract BeaconInstanceV2 is BeaconInstanceV1 {
  function echo(string memory message) external pure returns (string memory) {
    return message;
  }
}

contract BeaconProxyTest is Toolkit {
  address public admin = makeAddr('admin');

  BeaconInstanceV1 public instanceImplV1;
  BeaconInstanceV2 public instanceImplV2;
  UpgradeableBeacon public beaconV1;
  UpgradeableBeacon public beaconV2;
  address public base;

  function setUp() public {
    instanceImplV1 = new BeaconInstanceV1();
    instanceImplV2 = new BeaconInstanceV2();
    beaconV1 = new UpgradeableBeacon(admin, address(instanceImplV1));
    beaconV2 = new UpgradeableBeacon(admin, address(instanceImplV2));
    base = address(new BeaconProxy(address(beaconV1), abi.encodeCall(BeaconInstanceV1.initialize, 'hello')));
  }

  function test_init() public {
    assertEq(address(0x0), _erc1967Impl(base));
    assertEq(address(beaconV1), _erc1967Beacon(base));
    assertEq(address(0x0), _erc1967Admin(base));

    assertEq(BeaconInstanceV1(base).buffer(), 'hello');

    vm.expectRevert();
    BeaconInstanceV2(base).echo('yo');
  }

  function test_upgrade_impl() public {
    vm.prank(admin);
    beaconV1.upgradeTo(address(instanceImplV2));

    assertEq(BeaconInstanceV2(base).buffer(), 'hello');
    assertEq(BeaconInstanceV2(base).echo('yo'), 'yo');
  }

  function test_upgrade_beacon() public {
    vm.prank(admin);
    IBeaconProxy(base).upgradeBeaconToAndCall(address(beaconV2), bytes(''));

    assertEq(address(0x0), _erc1967Impl(base));
    assertEq(address(beaconV2), _erc1967Beacon(base));
    assertEq(address(0x0), _erc1967Admin(base));

    assertEq(BeaconInstanceV2(base).buffer(), 'hello');
    assertEq(BeaconInstanceV2(base).echo('yo'), 'yo');
  }
}
