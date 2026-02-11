// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

interface IFeeOnTransferERC20 {
    function totalTransferFee() external returns (uint256);
}

/**
 * @title Example ERC20 ApplicationERC20
 * @notice This is an example implementation to facilitate testing
 * @dev During deployment _tokenName and _tokenSymbol are set in constructor
 */
contract FeeOnTransferERC20 is ERC20 {
    uint256 immutable transferFee;
    uint256 public totalTransferFee;

    /**
     * @dev Constructor sets params
     * @param _name Name of the token
     * @param _symbol Symbol of the token
     */
    // slither-disable-next-line shadowing-local
    constructor(string memory _name, string memory _symbol, uint16 _fee) ERC20(_name, _symbol) {
        transferFee = _fee;
    }

    /**
     * @dev Function that mints new tokens. Allows for free and open minting of tokens.
     * @param to recipient address
     * @param amount number of tokens to mint
     */
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        uint feeAmount = (amount * transferFee) / 10000;
        totalTransferFee += feeAmount;
        uint transferAmount = amount - feeAmount;
        super.transfer(0x000000000000000000000000000000000000dEaD, feeAmount);

        return super.transfer(to, transferAmount);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        uint feeAmount = (amount * transferFee) / 10000;
        totalTransferFee += feeAmount;
        uint transferAmount = amount - feeAmount;
        super.transferFrom(from, 0x000000000000000000000000000000000000dEaD, feeAmount);

        return super.transferFrom(from, to, transferAmount);
    }
}
