// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { console } from '@std/console.sol';
import { Test } from '@std/Test.sol';

import { LibString } from '@solady/utils/LibString.sol';

import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { Create3Deployer } from '../Create3Deployer.sol';
import '../Functions.sol';

abstract contract AbstractDeployer is Test {
  using LibString for *;

  address internal CREATE3_ADMIN = makeAddr('DEFAULT_CREATE3_ADMIN');
  Create3Deployer internal CREATE3;

  string private constant _IMPL_URL = 'mitosis.test.create3-deployer.impl';
  string private constant _PROXY_URL = 'mitosis.test.create3-deployer';

  function version() internal pure virtual returns (string memory);

  function setUp() public virtual {
    bytes memory initData = abi.encodeCall(Create3Deployer.initialize, (CREATE3_ADMIN));
    address impl = address(new Create3Deployer{ salt: salt(_IMPL_URL) }());
    address proxy = address(new ERC1967Proxy{ salt: salt(_PROXY_URL) }(impl, initData));
    CREATE3 = Create3Deployer(proxy);
  }

  function deploy(string memory url, bytes memory initCode) internal returns (address payable) {
    vm.prank(CREATE3_ADMIN);
    return payable(CREATE3.deploy(url, initCode));
  }

  function deployERC1967Proxy(string memory url, address impl, bytes memory data) internal returns (address payable) {
    vm.prank(CREATE3_ADMIN);
    return payable(CREATE3.deployERC1967Proxy(url, impl, data));
  }

  function deployTransparentProxy(string memory url, address impl, address admin, bytes memory data)
    internal
    returns (address payable)
  {
    vm.prank(CREATE3_ADMIN);
    return payable(CREATE3.deployTransparentProxy(url, impl, admin, data));
  }

  function deployImplAndProxy(
    string memory chain,
    string memory name,
    bytes memory creationCode,
    bytes memory initializeCallData
  ) internal returns (address, address payable) {
    address impl = deploy(_urlI(chain, name), creationCode);
    address proxy = deployERC1967Proxy(_urlP(chain, name), impl, initializeCallData);
    return (impl, payable(proxy));
  }

  function _urlI(string memory chain, string memory name) internal pure returns (string memory) {
    return cat('mitosis.test.', chain, '.impl', name, cat('.', version()));
  }

  function _urlP(string memory chain, string memory name) internal pure returns (string memory) {
    return cat('mitosis.test.', chain, '.proxy', name);
  }

  //===============================================================================================//

  // ----- Printer Functions -----
  //===============================================================================================//

  struct MaxLen {
    uint256 url;
    uint256 addr;
    uint256 kind;
    uint256 creator;
  }

  function _getCreate3Contracts() internal view returns (Create3Deployer.ContractInfo[] memory) {
    Create3Deployer.ContractInfo[] memory contracts = CREATE3.get();
    require(contracts.length > 0, 'nothing deployed');

    // Insertion sort based on URL
    for (uint256 i = 1; i < contracts.length; i++) {
      Create3Deployer.ContractInfo memory key = contracts[i];
      int256 j = int256(i - 1);

      while (j >= 0 && contracts[uint256(j)].url.cmp(key.url) > 0) {
        contracts[uint256(j + 1)] = contracts[uint256(j)];
        j--;
      }
      contracts[uint256(j + 1)] = key;
    }

    return contracts; // Return the sorted original array
  }

  function _printCreate3Contracts() internal view {
    Create3Deployer.ContractInfo[] memory contracts = _getCreate3Contracts();

    MaxLen memory maxLen = _calculateMaxLen(contracts);

    uint256 borderLen = maxLen.url + maxLen.addr + maxLen.kind + maxLen.creator + 11;
    string memory border = string.concat('|', '-'.repeat(borderLen), '|');

    console.log();
    console.log(border);

    _printHeader(maxLen);

    console.log(border);

    for (uint256 i = 0; i < contracts.length; i++) {
      _printRow(maxLen, contracts[i]);
    }

    console.log(border);
    console.log();
  }

  function _printHeader(MaxLen memory maxLen) internal pure {
    console.log(
      string.concat(
        '| URL',
        ' '.repeat(maxLen.url - 3), // Space for URL header
        ' | ADDR',
        ' '.repeat(maxLen.addr - 4), // Space for ADDR header
        ' | TYPE',
        ' '.repeat(maxLen.kind - 4), // Space for TYPE header
        ' | CREATOR',
        ' '.repeat(maxLen.creator - 7), // Space for CREATOR header
        ' |'
      )
    );
  }

  function _printRow(MaxLen memory maxLen, Create3Deployer.ContractInfo memory c) internal pure {
    string memory url = c.url;
    string memory addr = c.addr.toHexString();
    string memory kind = _convertProxyType(c.kind);
    string memory creator = c.creator.toHexString();

    MaxLen memory len =
      MaxLen({ url: url.runeCount(), addr: addr.runeCount(), kind: kind.runeCount(), creator: creator.runeCount() });

    string memory row = string.concat(
      '|',
      _pad(url, maxLen.url, len.url),
      '|',
      _pad(addr, maxLen.addr, len.addr),
      '|',
      _pad(kind, maxLen.kind, len.kind),
      '|',
      _pad(creator, maxLen.creator, len.creator),
      '|'
    );

    console.log(row);
  }

  function _pad(string memory str, uint256 maxLen, uint256 len) internal pure returns (string memory) {
    return string.concat(' ', str, ' '.repeat(maxLen - len + 1));
  }

  function _calculateMaxLen(Create3Deployer.ContractInfo[] memory contracts)
    private
    pure
    returns (MaxLen memory maxLen)
  {
    MaxLen memory maxLen_ = MaxLen({ url: 0, addr: 0, kind: 0, creator: 0 });

    for (uint256 i = 0; i < contracts.length; i++) {
      Create3Deployer.ContractInfo memory c = contracts[i];

      uint256 urlLen = c.url.runeCount();
      if (maxLen_.url < urlLen) maxLen_.url = urlLen;

      uint256 addrLen = c.addr.toHexString().runeCount();
      if (maxLen_.addr < addrLen) maxLen_.addr = addrLen;

      uint256 kindLen = _convertProxyType(c.kind).runeCount();
      if (maxLen_.kind < kindLen) maxLen_.kind = kindLen;

      uint256 creatorLen = c.creator.toHexString().runeCount();
      if (maxLen_.creator < creatorLen) maxLen_.creator = creatorLen;
    }

    return maxLen_;
  }

  function _convertProxyType(Create3Deployer.ProxyType kind) private pure returns (string memory) {
    if (kind == Create3Deployer.ProxyType.None) return 'None';
    if (kind == Create3Deployer.ProxyType.ERC1967) return 'ERC1967';
    if (kind == Create3Deployer.ProxyType.Transparent) return 'Transparent';
    revert('invalid proxy type');
  }
}
