// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.10;

import "./MockERC20Mintable.sol";

contract MockATokenMintable is MockERC20Mintable {
  address public immutable underlyingAssetAddress;

  constructor(
    address _underlyingAssetAddress,
    string memory _name,
    string memory _symbol,
    uint8 decimals_
  ) MockERC20Mintable(_name, _symbol, decimals_) {
    underlyingAssetAddress = _underlyingAssetAddress;
  }

  /* solhint-disable func-name-mixedcase */
  function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
    return underlyingAssetAddress;
  }
}
