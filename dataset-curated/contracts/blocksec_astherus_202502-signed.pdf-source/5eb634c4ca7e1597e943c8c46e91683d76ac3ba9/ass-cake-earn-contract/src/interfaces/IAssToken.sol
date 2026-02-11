// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title AssToken interface
interface IAssToken is IERC20 {
    function initialize(string memory _name, string memory _symbol, address _owner, address _minter) external;

    function mint(address _account, uint256 _amount) external;

    function setMinter(address _address) external;
}
