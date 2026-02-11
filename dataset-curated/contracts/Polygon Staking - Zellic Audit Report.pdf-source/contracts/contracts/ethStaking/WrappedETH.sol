// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title WrappedETH
 * @dev Handles wrapping and unwrapping of ETH
 */
contract WrappedETH is ERC20 {
    event Wrap(address account, uint256 amount);
    event Unwrap(address account, uint256 amount);

    constructor() ERC20("Wrapped ETH", "WETH") {}

    function wrap() external payable {
        _mint(msg.sender, msg.value);
        emit Wrap(msg.sender, msg.value);
    }

    function unwrap(uint256 _amount) external {
        _burn(msg.sender, _amount);
        Address.sendValue(payable(msg.sender), _amount);
        emit Unwrap(msg.sender, _amount);
    }
}
