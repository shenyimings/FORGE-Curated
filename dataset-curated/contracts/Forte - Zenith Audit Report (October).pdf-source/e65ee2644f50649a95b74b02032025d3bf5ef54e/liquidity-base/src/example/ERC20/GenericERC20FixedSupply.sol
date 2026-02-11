// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Capped.sol";

/**
 * @title Example ERC20 ApplicationERC20
 * @notice This is an example implementation to facilitate testing
 * @dev During deployment _tokenName and _tokenSymbol are set in constructor
 */
contract GenericERC20FixedSupply is ERC20Capped {
    /**
     * @dev Constructor sets params
     * @param _name Name of the token
     * @param _symbol Symbol of the token
     * @param _supply The total supply of the token.
     * @notice The total supply of the token is minted to the deployer at construction time.
     */
    // slither-disable-next-line shadowing-local
    constructor(string memory _name, string memory _symbol, uint256 _supply) ERC20(_name, _symbol) ERC20Capped(_supply) {
        _mint(_msgSender(), _supply);
    }
}
