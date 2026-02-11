// SPDX-License-Identifier: MIT
// solhint-disable gas-custom-errors

pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract ERC20Mock is ERC20 {
    mapping(address => bool) public sanctionedAddresses;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
    }

    function addToSanctionList(address _address) public {
        sanctionedAddresses[_address] = true;
    }

    function mintAmount(address _target, uint256 amount) public {
        _mint(_target, amount);
    }

    function burnAmount(address _target, uint256 _amount) public {
        _burn(_target, _amount);
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function depositTo(address _recipient) public payable {
        _mint(_recipient, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal virtual override {
        require(!sanctionedAddresses[from] && !sanctionedAddresses[to], "sanctioned address");
    }
}
