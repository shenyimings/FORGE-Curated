// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mintable is ERC20 {
    constructor(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _totalSupply
    ) ERC20(_tokenName, _tokenSymbol) {
        if (_totalSupply != 0) {
            _mint(msg.sender, _totalSupply * (10 ** uint256(decimals())));
        }
    }
}
