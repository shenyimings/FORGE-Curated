// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title Example ERC20 ApplicationERC20
 * @notice This is an example implementation to facilitate testing
 * @dev During deployment _tokenName and _tokenSymbol are set in constructor
 */
contract NoZeroTransferERC20 is ERC20 {
    /**
     * @dev Constructor sets params
     * @param _name Name of the token
     * @param _symbol Symbol of the token
     */
    // slither-disable-next-line shadowing-local
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    /**
     * @dev Function that mints new tokens. Allows for free and open minting of tokens.
     * @param to recipient address
     * @param amount number of tokens to mint
     */
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        require(amount != 0, "cannot send 0 amount");
        return super.transfer(to, amount);
    }
}
