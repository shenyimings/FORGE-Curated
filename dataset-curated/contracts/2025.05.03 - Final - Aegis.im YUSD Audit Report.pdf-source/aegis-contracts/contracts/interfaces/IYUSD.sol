// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IYUSD is IERC20Permit, IERC20Metadata {
  function mint(address account, uint256 value) external;

  function mint(address account, uint256 value, bytes calldata data) external;

  function burn(uint256 _amount) external;

  function burnFrom(address account, uint256 amount) external;

  function setMinter(address newMinter) external;
}

interface IYUSDErrors {
  error ZeroAddress();
  error OnlyMinter();
  error Blacklisted(address _user);
}
