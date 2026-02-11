// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title AsBNB interface
interface IAsBNB is IERC20 {
  function mint(address _account, uint256 _amount) external;
  function burn(address _account, uint256 _amount) external;
  function setMinter(address _address) external;
}
