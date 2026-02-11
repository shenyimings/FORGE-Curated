// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Test ERC token that may be deployed and minted to test contracts that support ERC-20 token interactions.
 */
contract TestToken is ERC20 {
    uint8 private immutable tokenDecimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol) {
        tokenDecimals = _decimals;
        _mint(msg.sender, 100 * 10 ** uint(_decimals));
    }

    function mint(address account, uint256 value) external {
        _mint(account, value);
    }

    function decimals() public view virtual override returns (uint8) {
        return tokenDecimals;
    }
}
