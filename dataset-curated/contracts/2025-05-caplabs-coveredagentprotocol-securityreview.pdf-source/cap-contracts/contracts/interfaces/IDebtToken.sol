// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

interface IDebtToken is IERC20 {
    function initialize(address registry, address principalDebtToken, address asset) external;
    function burn(address from, uint256 amount) external returns (uint256 actualRepaid);
    function update(address agent) external;
}