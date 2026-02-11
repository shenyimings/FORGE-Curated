// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IWhitelabeledUnit } from "../../src/interfaces/IWhitelabeledUnit.sol";

contract MockWhitelabeledUnit is IWhitelabeledUnit, ERC20 {
    address public immutable genericUnit;

    bool public revertNextCall;

    constructor(address _genericUnit) ERC20("Mock USD", "M-USD") {
        genericUnit = _genericUnit;
    }

    function wrap(address owner, uint256 amount) external {
        require(!revertNextCall, "MockWhitelabeledUnit: revertNextCall is set");
        require(
            IERC20(genericUnit).transferFrom(msg.sender, address(this), amount),
            "MockWhitelabeledUnit: transferFrom failed"
        );
        _mint(owner, amount);
        emit Wrapped(owner, amount);
    }

    function unwrap(address owner, address recipient, uint256 amount) external {
        require(!revertNextCall, "MockWhitelabeledUnit: revertNextCall is set");
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, amount);
        _burn(owner, amount);
        require(IERC20(genericUnit).transfer(recipient, amount), "MockWhitelabeledUnit: transfer failed");
        emit Unwrapped(owner, recipient, amount);
    }

    function setRevertNextCall(bool _revert) external {
        revertNextCall = _revert;
    }
}
