// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';

import { BeaconProxy } from '@oz/proxy/beacon/BeaconProxy.sol';
import { Initializable } from '@oz/proxy/utils/Initializable.sol';

import { ERC1967Factory } from '@solady/utils/ERC1967Factory.sol';
import { UpgradeableBeacon } from '@solady/utils/UpgradeableBeacon.sol';

import { IBeaconBase, BeaconBase } from '../../../src/lib/proxy/BeaconBase.sol';
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

contract BeaconBaseImpl is BeaconBase {
  constructor() {
    _disableInitializers();
  }

  function initialize(UpgradeableBeacon beacon_) external initializer {
    __BeaconBase_init(beacon_);
  }

  function callBeacon(bytes calldata data) external returns (bytes memory) {
    return _callBeacon(data);
  }

  function create(string memory buffer) external returns (address) {
    address instance = address(new BeaconProxy(address(beacon()), abi.encodeCall(BeaconInstanceV1.initialize, buffer)));
    _pushInstance(instance);
    return instance;
  }
}

contract BeaconBaseTest is Toolkit {
  address public admin = makeAddr('admin');

  ERC1967Factory public proxyFactory;
  UpgradeableBeacon public beacon;

  BeaconInstanceV1 public instanceImplV1;
  BeaconInstanceV2 public instanceImplV2;
  BeaconBaseImpl public baseImpl;
  BeaconBaseImpl public base;

  function setUp() public {
    instanceImplV1 = new BeaconInstanceV1();
    instanceImplV2 = new BeaconInstanceV2();
    baseImpl = new BeaconBaseImpl();
    beacon = new UpgradeableBeacon(admin, address(instanceImplV1));

    proxyFactory = new ERC1967Factory();
    base =
      BeaconBaseImpl(proxyFactory.deployAndCall(address(baseImpl), admin, abi.encodeCall(baseImpl.initialize, beacon)));

    vm.prank(admin);
    beacon.transferOwnership(address(base));
  }

  function test_init() public view {
    assertEq(address(beacon), base.beacon());
    assertEq(beacon.owner(), address(base));
  }

  function test_create() public {
    address instance = _create('hello');

    assertEq(BeaconInstanceV1(instance).buffer(), 'hello');

    assertEq(address(0x0), _erc1967Impl(instance));
    assertEq(address(beacon), _erc1967Beacon(instance));
    assertEq(address(0x0), _erc1967Admin(instance));

    assertEq(base.instancesLength(), 1);
    assertEq(base.isInstance(instance), true);
    assertEq(base.instances(0), instance);
  }

  function test_migrate() public {
    address instance = _create('hello');

    vm.expectRevert();
    BeaconInstanceV2(instance).echo('hello');

    base.callBeacon(abi.encodeCall(UpgradeableBeacon.upgradeTo, address(instanceImplV2)));

    assertEq(BeaconInstanceV2(instance).buffer(), 'hello');
    assertEq(BeaconInstanceV2(instance).echo('yo'), 'yo');
  }

  function _create(string memory buffer) internal returns (address) {
    return base.create(buffer);
  }
}
