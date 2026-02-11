// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract TestnetToken is ERC20, Ownable {

    uint256 public maxMintAmount = type(uint256).max;

    error MaxMintAmountExceeded(uint256 amount);

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external {
        if (amount > maxMintAmount) revert MaxMintAmountExceeded(amount);

        _mint(to, amount);
    }

    function setMaxMintAmount(uint256 _maxMintAmount) external onlyOwner {
        maxMintAmount = _maxMintAmount;
    }
}
