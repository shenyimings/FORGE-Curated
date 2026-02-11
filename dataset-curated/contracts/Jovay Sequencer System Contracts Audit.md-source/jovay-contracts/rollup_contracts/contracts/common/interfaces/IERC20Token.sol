// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IERC20Token is IERC20Upgradeable{
    /**
     * @dev mint
     * @param account address
     * @param amount count
     */
    function mint(address account, uint256 amount) external;

    /**
     * @dev burn token
     * @param account burn address
     * @param amount count
     */
    function burn(address account, uint256 amount) external;
}
