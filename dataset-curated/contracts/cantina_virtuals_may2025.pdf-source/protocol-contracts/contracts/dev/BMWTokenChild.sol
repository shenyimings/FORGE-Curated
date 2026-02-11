// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract BMWTokenChild is ERC20 {
    address internal _fxManager;

    constructor(
        address fxManager
    )
        ERC20("BeemerToken", "BMW")
    {
        _fxManager = fxManager;
    }

    function setFxManager(address fxManager) public {
        _fxManager = fxManager;
    }

    function mint(address user, uint256 amount) public {
        require(msg.sender == _fxManager, "Invalid sender");
        _mint(user, amount);
    }

    function burn(address user, uint256 amount) public {
        require(msg.sender == _fxManager, "Invalid sender");
        _burn(user, amount);
    }
}
