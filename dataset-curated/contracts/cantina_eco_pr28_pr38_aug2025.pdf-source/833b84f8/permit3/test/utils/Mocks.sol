// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockToken
 * @notice Simple ERC20 token for testing
 */
contract MockToken is ERC20 {
    bool public shouldFailApproval = false;
    bool public shouldFailTransfer = false;

    constructor() ERC20("Mock Token", "MOCK") { }

    function approve(address spender, uint256 amount) public override returns (bool) {
        if (shouldFailApproval) {
            return false;
        }
        return super.approve(spender, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (shouldFailTransfer) {
            return false;
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (shouldFailTransfer) {
            return false;
        }
        return super.transferFrom(from, to, amount);
    }

    function setShouldFailApproval(
        bool _shouldFail
    ) external {
        shouldFailApproval = _shouldFail;
    }

    function setShouldFailTransfer(
        bool _shouldFail
    ) external {
        shouldFailTransfer = _shouldFail;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
