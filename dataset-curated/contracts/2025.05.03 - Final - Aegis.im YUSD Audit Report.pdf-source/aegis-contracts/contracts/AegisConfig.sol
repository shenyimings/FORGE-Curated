// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { IYUSD } from "./interfaces/IYUSD.sol";
import { IAegisConfig, IAegisConfigEvents, IAegisConfigErrors } from "./interfaces/IAegisConfig.sol";

contract AegisConfig is ERC165, Ownable2Step, IAegisConfigEvents, IAegisConfigErrors {
  /// @dev Address that can sign order
  address public trustedSigner;

  bool public whitelistEnabled = true;

  mapping(address => bool) private _operators;
  mapping(address => bool) private _whitelist;

  modifier onlyOperator() {
    if (!_operators[_msgSender()]) {
      revert AccessForbidden();
    }
    _;
  }

  constructor(address _trustedSigner, address[] memory _ops, address _initialOwner) Ownable(_initialOwner) {
    if (_trustedSigner == address(0)) revert ZeroAddress();

    _setTrustedSigner(_trustedSigner);

    for (uint256 i = 0; i < _ops.length; i++) {
      _setOperator(_ops[i], true);
    }
  }

  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
    return interfaceId == type(IAegisConfig).interfaceId || super.supportsInterface(interfaceId);
  }

  function isWhitelisted(address addr) public view returns (bool) {
    if (!whitelistEnabled) return true;
    return _whitelist[addr];
  }

  function whitelistAddress(address addr, bool whitelisted) external onlyOperator {
    _whitelist[addr] = whitelisted;

    emit WhitelistAddress(addr, whitelisted);
  }

  function whitelistAddress(address[] memory addrs, bool[] memory whitelisted) external onlyOperator {
    if (addrs.length != whitelisted.length) {
      revert InvalidArguments();
    }

    for (uint256 i = 0; i < addrs.length; i++) {
      _whitelist[addrs[i]] = whitelisted[i];
    }

    emit WhitelistAddressBatch(addrs, whitelisted);
  }

  function enableWhitelist() external onlyOwner {
    whitelistEnabled = true;
    emit WhitelistEnabled();
  }

  function disableWhitelist() external onlyOwner {
    whitelistEnabled = false;
    emit WhitelistDisabled();
  }

  /// @dev Sets new trusted signer
  function setTrustedSigner(address signer) external onlyOwner {
    if (signer == address(0)) revert ZeroAddress();
    _setTrustedSigner(signer);
  }

  /// @dev Adds/removes operator
  function setOperator(address operator, bool allowed) external onlyOwner {
    _setOperator(operator, allowed);
  }

  function _setTrustedSigner(address _signer) internal {
    trustedSigner = _signer;
    emit SetTrustedSigner(_signer);
  }

  function _setOperator(address operator, bool allowed) internal {
    _operators[operator] = allowed;
    emit SetOperator(operator, allowed);
  }
}
