// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../LinearTokenVesting.sol";

/// @title ERC20Mock
/// @notice This contract is used to test the LinearTokenVesting
///   
contract ERC20Mock is ERC20 {

    constructor() ERC20("TEST", "TTT") {}

    function mockStartVesting(address vesting, uint256 amount) public {
         _mint(vesting, amount);
         LinearTokenVesting(vesting).startVesting();
    }
}