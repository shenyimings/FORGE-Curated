// SPDX-License-Identifier: MIT
// solhint-disable no-empty-blocks
// solhint-disable gas-custom-errors

pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Permit} from "../token/ERC20Permit.sol";

contract ERC20PermitMock is ERC20, UUPSUpgradeable, ERC20Permit {
    string private _name;
    string private _symbol;
    bool private _initialized;
    uint16 private _version;

    constructor(string memory name_, string memory symbol_)
        ERC20("", "")
    {
        initialize(name_, symbol_);
        initializeV1r1();
    }

    function initialize(string memory name_, string memory symbol_) public {
        require(!_initialized, "already initialized");
        _initialized = true;
        _name = name_;
        _symbol = symbol_;
    }

    function initializeV1r1() public {
        require(_version == 0, "already upgraded");
        _version = 1;
        initializeEIP712(_name, "1");
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function mint(address account, uint256 amount) external virtual {
        _mint(account, amount);
    }

    // support for ERC20Permit
    function _approve(address _owner, address _spender, uint256 _amount)
        internal virtual override (ERC20, ERC20Permit)
    {
        ERC20._approve(_owner, _spender, _amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override {
        // allow always
    }
}
