// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title Anvil Token
 * @notice Anvil governance token, using OZ ERC20Votes.
 *
 * @custom:security-contact security@af.xyz
 */
contract Anvil is ERC20Votes {
    /**
     * @notice Deploys the Anvil token, allocating the provided amount of tokens to the deployer.
     *
     * @param destinationAddress The address to which the tokens will be minted.
     */
    constructor(address destinationAddress) ERC20("Anvil", "ANVL") EIP712("Anvil", "1") {
        _mint(destinationAddress, _maxSupply());
    }

    /**
     * @dev Maximum token supply. Hardcoded because it cannot change.
     */
    function _maxSupply() internal view virtual override(ERC20Votes) returns (uint256) {
        // NB: This is updated to return the constant supply
        return 100_000_000_000 * 10 ** uint256(decimals());
    }
}
