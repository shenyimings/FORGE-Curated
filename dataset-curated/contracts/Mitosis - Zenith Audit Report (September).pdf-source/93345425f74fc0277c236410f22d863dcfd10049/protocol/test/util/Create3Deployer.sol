// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.23 <0.9.0;

import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { ProxyAdmin } from '@oz/proxy/transparent/ProxyAdmin.sol';
import { TransparentUpgradeableProxy } from '@oz/proxy/transparent/TransparentUpgradeableProxy.sol';
import { AccessControlEnumerableUpgradeable } from '@ozu/access/extensions/AccessControlEnumerableUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { CREATE3 } from '@solady/utils/CREATE3.sol';
import { LibString } from '@solady/utils/LibString.sol';

import { ERC7201Utils } from '../../src/lib/ERC7201Utils.sol';

contract Create3Deployer is AccessControlEnumerableUpgradeable, UUPSUpgradeable {
  using LibString for string;
  using ERC7201Utils for string;

  enum ProxyType {
    None,
    ERC1967,
    Transparent
  }

  struct ContractInfo {
    string url;
    address addr;
    ProxyType kind;
    address creator;
  }

  struct StorageV1 {
    ContractInfo[] contracts;
    mapping(string url => uint256) urls;
    mapping(address addr => uint256) addrs;
    mapping(ProxyType kind => uint256[]) kinds;
  }

  string private constant _NAMESPACE = 'mitosis.storage.ops.create3-deployer.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() private view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  error InvalidURL(string url);
  error AlreadyDeployed(string url);

  /// @dev keccak256('mitosis.role.Create3Deployer.admin');
  bytes32 public constant ADMIN_ROLE = 0xde4dadfa2594a8e53263e6035d51303652535c24194c403fff54d6fc1145c128;

  /// @dev keccak256('mitosis.role.Create3Deployer.deployer');
  bytes32 public constant DEPLOYER_ROLE = 0x1c8efb049a690a8d7d3750bea15b425d91cf4e5ae4eb3ae0857980e521b28ef9;

  constructor() {
    _disableInitializers();
  }

  function initialize(address admin) external initializer {
    __AccessControlEnumerable_init();
    __UUPSUpgradeable_init();

    _grantRole(ADMIN_ROLE, admin);
    _grantRole(DEPLOYER_ROLE, admin);
    _setRoleAdmin(DEPLOYER_ROLE, ADMIN_ROLE);
  }

  function size() external view returns (uint256) {
    return _getStorageV1().contracts.length;
  }

  function size(ProxyType kind) external view returns (uint256) {
    return _getStorageV1().kinds[kind].length;
  }

  function get() external view returns (ContractInfo[] memory) {
    return _getStorageV1().contracts;
  }

  function get(uint256 index) external view returns (ContractInfo memory) {
    return _getStorageV1().contracts[index];
  }

  function get(ProxyType kind, uint256 index) external view returns (ContractInfo memory) {
    return _getStorageV1().contracts[_getStorageV1().kinds[kind][index]];
  }

  function getByURL(string calldata url) external view returns (ContractInfo memory) {
    return _getStorageV1().contracts[_getStorageV1().urls[url]];
  }

  function getByAddress(address addr) external view returns (ContractInfo memory) {
    return _getStorageV1().contracts[_getStorageV1().addrs[addr]];
  }

  function predict(string calldata url) external view returns (address) {
    return CREATE3.predictDeterministicAddress(keccak256(abi.encodePacked(url)));
  }

  function deploy(string calldata url, bytes calldata initCode) external onlyRole(DEPLOYER_ROLE) returns (address) {
    require(!url.eq(''), InvalidURL(url));

    address addr = _deploy(url, initCode);

    StorageV1 storage $ = _getStorageV1();
    require($.urls[url] == 0, AlreadyDeployed(url));

    _save($, ContractInfo(url, addr, ProxyType.None, _msgSender()));

    return addr;
  }

  function deployERC1967Proxy(string calldata url, address impl, bytes calldata data)
    external
    onlyRole(DEPLOYER_ROLE)
    returns (address)
  {
    require(!url.eq(''), InvalidURL(url));

    address addr = _deploy(
      url,
      abi.encodePacked(
        type(ERC1967Proxy).creationCode, //
        abi.encode(impl, data)
      )
    );

    StorageV1 storage $ = _getStorageV1();
    require($.urls[url] == 0, AlreadyDeployed(url));

    _save($, ContractInfo(url, addr, ProxyType.ERC1967, _msgSender()));

    return addr;
  }

  function deployTransparentProxy(string calldata url, address impl, address admin, bytes calldata data)
    external
    onlyRole(DEPLOYER_ROLE)
    returns (address)
  {
    require(!url.eq(''), InvalidURL(url));

    address addr = _deploy(
      url,
      abi.encodePacked(
        type(TransparentUpgradeableProxy).creationCode, //
        abi.encode(impl, admin, data)
      )
    );

    StorageV1 storage $ = _getStorageV1();
    require($.urls[url] == 0, AlreadyDeployed(url));

    _save($, ContractInfo(url, addr, ProxyType.Transparent, _msgSender()));

    return addr;
  }

  function _deploy(string calldata url, bytes memory initCode) internal returns (address) {
    bytes32 salt = keccak256(abi.encodePacked(url));
    address addr = CREATE3.deployDeterministic(initCode, salt);
    return addr;
  }

  function _save(StorageV1 storage $, ContractInfo memory info) internal {
    uint256 index = $.contracts.length;
    $.contracts.push(info);
    $.urls[info.url] = index;
    $.addrs[info.addr] = index;
    $.kinds[info.kind].push(index);
  }

  function _authorizeUpgrade(address) internal override onlyRole(ADMIN_ROLE) { }
}
