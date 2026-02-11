// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { WETH } from '@solady/tokens/WETH.sol';
import { ERC1967Factory } from '@solady/utils/ERC1967Factory.sol';
import { UpgradeableBeacon } from '@solady/utils/UpgradeableBeacon.sol';

import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { VLFVaultBasic } from '../../../src/hub/vlf/VLFVaultBasic.sol';
import { VLFVaultCapped } from '../../../src/hub/vlf/VLFVaultCapped.sol';
import { VLFVaultFactory } from '../../../src/hub/vlf/VLFVaultFactory.sol';
import { IAssetManagerStorageV1 } from '../../../src/interfaces/hub/core/IAssetManager.sol';
import { IVLFVaultFactory } from '../../../src/interfaces/hub/vlf/IVLFVaultFactory.sol';
import { MockContract } from '../../util/MockContract.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract VLFVaultFactoryTest is Toolkit {
  address public owner = makeAddr('owner');
  MockContract public assetManager;
  MockContract public reclaimQueue;

  ERC1967Factory public proxyFactory;

  VLFVaultBasic public basicImpl;
  VLFVaultCapped public cappedImpl;
  VLFVaultFactory public factoryImpl;

  VLFVaultFactory public base;

  uint8 BasicVLFVaultType = uint8(IVLFVaultFactory.VLFVaultType.Basic);
  uint8 CappedVLFVaultType = uint8(IVLFVaultFactory.VLFVaultType.Capped);

  function setUp() public {
    assetManager = new MockContract();
    reclaimQueue = new MockContract();
    assetManager.setRet(
      abi.encodeCall(IAssetManagerStorageV1.reclaimQueue, ()), false, abi.encode(address(reclaimQueue))
    );

    proxyFactory = new ERC1967Factory();

    basicImpl = new VLFVaultBasic();
    cappedImpl = new VLFVaultCapped();
    factoryImpl = new VLFVaultFactory();

    base = VLFVaultFactory(
      payable(new ERC1967Proxy(address(factoryImpl), abi.encodeCall(VLFVaultFactory.initialize, (owner))))
    );
  }

  function test_init() public view {
    assertEq(base.owner(), owner);
    assertEq(_erc1967Impl(address(base)), address(factoryImpl));
  }

  function test_initVLFVaultType() public {
    vm.startPrank(owner);
    base.initVLFVaultType(BasicVLFVaultType, address(basicImpl));
    base.initVLFVaultType(CappedVLFVaultType, address(cappedImpl));
    vm.stopPrank();

    assertNotEq(base.beacon(BasicVLFVaultType), address(0));
    assertNotEq(base.beacon(CappedVLFVaultType), address(0));

    assertTrue(base.vlfVaultTypeInitialized(BasicVLFVaultType));
    assertTrue(base.vlfVaultTypeInitialized(CappedVLFVaultType));
  }

  function test_create_basic() public returns (address) {
    vm.prank(owner);
    base.initVLFVaultType(BasicVLFVaultType, address(basicImpl));

    address instance = _createBasic(owner, address(new WETH()), 'Basic VLFVault', 'BV');

    assertEq(address(0x0), _erc1967Admin(instance));
    assertEq(address(0x0), _erc1967Impl(instance));
    assertEq(base.beacon(BasicVLFVaultType), _erc1967Beacon(instance));

    assertEq(base.instancesLength(BasicVLFVaultType), 1);
    assertEq(base.instances(BasicVLFVaultType, 0), instance);

    return instance;
  }

  function test_create_capped() public returns (address) {
    vm.prank(owner);
    base.initVLFVaultType(CappedVLFVaultType, address(cappedImpl));

    address instance = _createCapped(owner, address(new WETH()), 'Capped VLFVault', 'CV');

    assertEq(address(0x0), _erc1967Admin(instance));
    assertEq(address(0x0), _erc1967Impl(instance));
    assertEq(base.beacon(CappedVLFVaultType), _erc1967Beacon(instance));

    assertEq(base.instancesLength(CappedVLFVaultType), 1);
    assertEq(base.instances(CappedVLFVaultType, 0), instance);

    return instance;
  }

  function test_migrate() public {
    vm.startPrank(owner);
    base.initVLFVaultType(BasicVLFVaultType, address(basicImpl));
    base.initVLFVaultType(CappedVLFVaultType, address(cappedImpl));
    vm.stopPrank();

    address basicI1 = _createBasic(owner, address(new WETH()), 'Basic VLFVault 1', 'BV1');
    address basicI2 = _createBasic(owner, address(new WETH()), 'Basic VLFVault 2', 'BV2');
    address cappedI1 = _createCapped(owner, address(new WETH()), 'Capped VLFVault 1', 'CV1');
    address cappedI2 = _createCapped(owner, address(new WETH()), 'Capped VLFVault 2', 'CV2');

    vm.prank(owner);
    base.migrate(BasicVLFVaultType, CappedVLFVaultType, basicI1, '');

    assertEq(base.instancesLength(BasicVLFVaultType), 1);
    assertEq(base.instancesLength(CappedVLFVaultType), 3);
    assertEq(base.instances(CappedVLFVaultType, 0), cappedI1);
    assertEq(base.instances(CappedVLFVaultType, 1), cappedI2);
    assertEq(base.instances(CappedVLFVaultType, 2), basicI1);

    assertEq(base.beacon(CappedVLFVaultType), _erc1967Beacon(basicI1));

    vm.prank(owner);
    base.migrate(CappedVLFVaultType, BasicVLFVaultType, basicI1, '');

    assertEq(base.instancesLength(BasicVLFVaultType), 2);
    assertEq(base.instancesLength(CappedVLFVaultType), 2);
    assertEq(base.instances(BasicVLFVaultType, 0), basicI2);
    assertEq(base.instances(BasicVLFVaultType, 1), basicI1);
    assertEq(base.instances(CappedVLFVaultType, 0), cappedI1);
    assertEq(base.instances(CappedVLFVaultType, 1), cappedI2);
  }

  function test_VLFVaultType_cast() public {
    vm.startPrank(owner);
    base.initVLFVaultType(BasicVLFVaultType, address(basicImpl));
    base.initVLFVaultType(CappedVLFVaultType, address(cappedImpl));
    vm.stopPrank();

    uint8 maxVLFVaultType = base.MAX_VLF_VAULT_TYPE();

    vm.expectRevert(_errEnumOutOfBounds(maxVLFVaultType, maxVLFVaultType + 1));
    base.beacon(maxVLFVaultType + 1);

    vm.expectRevert(_errEnumOutOfBounds(maxVLFVaultType, maxVLFVaultType + 1));
    base.isInstance(maxVLFVaultType + 1, address(0));

    vm.expectRevert(_errEnumOutOfBounds(maxVLFVaultType, maxVLFVaultType + 1));
    base.instances(maxVLFVaultType + 1, 0);

    uint256[] memory indexes;
    vm.expectRevert(_errEnumOutOfBounds(maxVLFVaultType, maxVLFVaultType + 1));
    base.instances(maxVLFVaultType + 1, indexes);

    vm.expectRevert(_errEnumOutOfBounds(maxVLFVaultType, maxVLFVaultType + 1));
    base.instancesLength(maxVLFVaultType + 1);

    vm.expectRevert(_errEnumOutOfBounds(maxVLFVaultType, maxVLFVaultType + 1));
    base.vlfVaultTypeInitialized(maxVLFVaultType + 1);

    vm.startPrank(owner);

    bytes memory data;
    vm.expectRevert(_errEnumOutOfBounds(maxVLFVaultType, maxVLFVaultType + 1));
    base.callBeacon(maxVLFVaultType + 1, data);

    vm.expectRevert(_errEnumOutOfBounds(maxVLFVaultType, maxVLFVaultType + 1));
    base.create(maxVLFVaultType + 1, data);

    vm.expectRevert(_errEnumOutOfBounds(maxVLFVaultType, maxVLFVaultType + 1));
    base.migrate(maxVLFVaultType + 1, maxVLFVaultType, address(0), data);

    vm.expectRevert(_errEnumOutOfBounds(maxVLFVaultType, maxVLFVaultType + 1));
    base.migrate(maxVLFVaultType, maxVLFVaultType + 1, address(0), data);

    vm.stopPrank();
  }

  function _createBasic(address caller, IVLFVaultFactory.BasicVLFVaultInitArgs memory args) internal returns (address) {
    vm.prank(caller);
    return base.create(BasicVLFVaultType, abi.encode(args));
  }

  function _createBasic(address caller, address asset, string memory name, string memory symbol)
    internal
    returns (address)
  {
    return _createBasic(
      caller,
      IVLFVaultFactory.BasicVLFVaultInitArgs({
        assetManager: address(assetManager),
        asset: IERC20Metadata(asset),
        name: name,
        symbol: symbol
      })
    );
  }

  function _createCapped(address caller, IVLFVaultFactory.CappedVLFVaultInitArgs memory args)
    internal
    returns (address)
  {
    vm.prank(caller);
    return base.create(CappedVLFVaultType, abi.encode(args));
  }

  function _createCapped(address caller, address asset, string memory name, string memory symbol)
    internal
    returns (address)
  {
    return _createCapped(
      caller,
      IVLFVaultFactory.CappedVLFVaultInitArgs({
        assetManager: address(assetManager),
        asset: IERC20Metadata(asset),
        name: name,
        symbol: symbol
      })
    );
  }
}
