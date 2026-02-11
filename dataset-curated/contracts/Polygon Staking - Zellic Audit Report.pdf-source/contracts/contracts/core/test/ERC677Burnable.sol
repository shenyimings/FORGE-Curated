// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../tokens/base/ERC677.sol";

contract ERC677Burnable is ERC677 {
    constructor(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _totalSupply
    ) ERC677(_tokenName, _tokenSymbol, _totalSupply) {}

    function burn(address _from, uint256 _amount) external {
        _burn(_from, _amount);
    }
}
