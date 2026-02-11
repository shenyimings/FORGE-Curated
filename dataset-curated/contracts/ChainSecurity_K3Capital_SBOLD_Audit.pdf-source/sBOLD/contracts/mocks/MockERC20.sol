// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private overriddenDecimals;
    bool private doRevert;

    constructor() ERC20("ERC20Test", "ERCT") {
        overriddenDecimals = 18;
    }

    function mint(uint256 amt) external {
        _mint(msg.sender, amt);
    }

    function mintTo(address receiver, uint256 amt) external {
        _mint(receiver, amt);
    }

    function setRevert(bool _doRevert) external {
        doRevert = _doRevert;
    }

    function overrideDecimals(uint8 _overriddenDecimals) external {
        overriddenDecimals = _overriddenDecimals;
    }

    function decimals() public view override returns (uint8) {
        require(!doRevert, "MockERC20: staticcall failed");

        return overriddenDecimals;
    }
}
