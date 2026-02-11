// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { WETH } from '@solady/tokens/WETH.sol';
import { ERC1967Factory } from '@solady/utils/ERC1967Factory.sol';
import { UpgradeableBeacon } from '@solady/utils/UpgradeableBeacon.sol';

import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { MatrixVaultBasic } from '../../../src/hub/matrix/MatrixVaultBasic.sol';
import { MatrixVaultCapped } from '../../../src/hub/matrix/MatrixVaultCapped.sol';
import { MatrixVaultFactory } from '../../../src/hub/matrix/MatrixVaultFactory.sol';
import { IAssetManagerStorageV1 } from '../../../src/interfaces/hub/core/IAssetManager.sol';
import { IMatrixVaultFactory } from '../../../src/interfaces/hub/matrix/IMatrixVaultFactory.sol';
import { MockContract } from '../../util/MockContract.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract MatrixVaultFactoryTest is Toolkit {
  address public contractOwner = makeAddr('owner');
  MockContract public assetManager;
  MockContract public reclaimQueue;

  ERC1967Factory public proxyFactory;

  MatrixVaultBasic public basicImpl;
  MatrixVaultCapped public cappedImpl;
  MatrixVaultFactory public factoryImpl;

  MatrixVaultFactory public base;

  function setUp() public {
    assetManager = new MockContract();
    reclaimQueue = new MockContract();
    assetManager.setRet(
      abi.encodeCall(IAssetManagerStorageV1.reclaimQueue, ()), false, abi.encode(address(reclaimQueue))
    );

    proxyFactory = new ERC1967Factory();

    basicImpl = new MatrixVaultBasic();
    cappedImpl = new MatrixVaultCapped();
    factoryImpl = new MatrixVaultFactory();

    base = MatrixVaultFactory(
      payable(new ERC1967Proxy(address(factoryImpl), abi.encodeCall(MatrixVaultFactory.initialize, (contractOwner))))
    );
  }

  function test_init() public view {
    assertEq(base.owner(), contractOwner);
    assertEq(_erc1967Impl(address(base)), address(factoryImpl));
  }

  function test_initVaultType() public {
    vm.startPrank(contractOwner);
    base.initVaultType(IMatrixVaultFactory.VaultType.Basic, address(basicImpl));
    base.initVaultType(IMatrixVaultFactory.VaultType.Capped, address(cappedImpl));
    vm.stopPrank();

    assertNotEq(base.beacon(IMatrixVaultFactory.VaultType.Basic), address(0));
    assertNotEq(base.beacon(IMatrixVaultFactory.VaultType.Capped), address(0));

    assertTrue(base.vaultTypeInitialized(IMatrixVaultFactory.VaultType.Basic));
    assertTrue(base.vaultTypeInitialized(IMatrixVaultFactory.VaultType.Capped));
  }

  function test_create_basic() public returns (address) {
    vm.prank(contractOwner);
    base.initVaultType(IMatrixVaultFactory.VaultType.Basic, address(basicImpl));

    address instance = _createBasic(
      contractOwner,
      IMatrixVaultFactory.BasicVaultInitArgs({
        owner: contractOwner,
        assetManager: address(assetManager),
        asset: IERC20Metadata(address(new WETH())),
        name: 'Basic Vault',
        symbol: 'BV'
      })
    );

    assertEq(address(0x0), _erc1967Admin(instance));
    assertEq(address(0x0), _erc1967Impl(instance));
    assertEq(base.beacon(IMatrixVaultFactory.VaultType.Basic), _erc1967Beacon(instance));

    assertEq(base.instancesLength(IMatrixVaultFactory.VaultType.Basic), 1);
    assertEq(base.instances(IMatrixVaultFactory.VaultType.Basic, 0), instance);

    return instance;
  }

  function test_create_capped() public returns (address) {
    vm.prank(contractOwner);
    base.initVaultType(IMatrixVaultFactory.VaultType.Capped, address(cappedImpl));

    address instance = _createCapped(
      contractOwner,
      IMatrixVaultFactory.CappedVaultInitArgs({
        owner: contractOwner,
        assetManager: address(assetManager),
        asset: IERC20Metadata(address(new WETH())),
        name: 'Capped Vault',
        symbol: 'CV'
      })
    );

    assertEq(address(0x0), _erc1967Admin(instance));
    assertEq(address(0x0), _erc1967Impl(instance));
    assertEq(base.beacon(IMatrixVaultFactory.VaultType.Capped), _erc1967Beacon(instance));

    assertEq(base.instancesLength(IMatrixVaultFactory.VaultType.Capped), 1);
    assertEq(base.instances(IMatrixVaultFactory.VaultType.Capped, 0), instance);

    return instance;
  }

  function test_migrate() public {
    address basic = test_create_basic();
    address capped = test_create_capped();

    vm.prank(contractOwner);
    base.migrate(IMatrixVaultFactory.VaultType.Basic, IMatrixVaultFactory.VaultType.Capped, basic, '');

    assertEq(base.instancesLength(IMatrixVaultFactory.VaultType.Basic), 0);
    assertEq(base.instancesLength(IMatrixVaultFactory.VaultType.Capped), 2);
    assertEq(base.instances(IMatrixVaultFactory.VaultType.Capped, 0), capped);
    assertEq(base.instances(IMatrixVaultFactory.VaultType.Capped, 1), basic);

    assertEq(base.beacon(IMatrixVaultFactory.VaultType.Capped), _erc1967Beacon(basic));
  }

  function _createBasic(address caller, MatrixVaultFactory.BasicVaultInitArgs memory args) internal returns (address) {
    vm.prank(caller);
    return base.create(IMatrixVaultFactory.VaultType.Basic, abi.encode(args));
  }

  function _createCapped(address caller, MatrixVaultFactory.CappedVaultInitArgs memory args) internal returns (address) {
    vm.prank(caller);
    return base.create(IMatrixVaultFactory.VaultType.Capped, abi.encode(args));
  }
}
