// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/Context.sol";

interface IERC20Burnable {
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
}

contract  AutomatorBurner is Context {
    IERC20Burnable public immutable rch;

    event Burned(address indexed account, uint256 amount, uint256 chainId, address collateral);

    constructor(
        address rch_
    ) {
        rch = IERC20Burnable(rch_);
    }

    function _burnFrom(address account, uint256 amount) internal {
        rch.burnFrom(account, amount);
    }

    function burn(uint256 amount, uint256 chainId, address collateral) external {
        _burnFrom(_msgSender(), amount);
        emit Burned(_msgSender(), amount, chainId, collateral);
    }
}
