// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import { MockERC20 } from "forge-std/mocks/MockERC20.sol";
import { MockERC721 } from "forge-std/mocks/MockERC721.sol";

// Small wrappers over forge-std mocks to expose mint helpers for tests
contract Token_ERC20 is MockERC20 {
    constructor() {
        initialize("MockERC20", "M20", 18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract Token_ERC721 is MockERC721 {
    constructor() {
        initialize("MockERC721", "M721");
    }

    function tokenURI(uint256) public pure override returns (string memory) {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}

/// @notice Mock contract that can receive ETH and self-destruct to force-send its balance
contract SelfDestructingMock {
    /// @notice Allows the contract to receive ETH
    receive() external payable {}

    /// @notice Self-destructs and sends this contract's entire ETH balance to target
    function selfDestruct(address payable target) external {
        selfdestruct(target);
    }
}

/// @notice Mock non-standard ERC20 token that returns false on transfer failure
/// @dev Simulates tokens like USDT, BNB that don't revert, just return false
contract NonStandardToken {
    mapping(address => uint256) public balanceOf;
    bool public shouldFail;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    /// @notice Returns false instead of reverting on failure (non-standard behavior)
    function transfer(address to, uint256 amount) external returns (bool) {
        if (shouldFail) {
            return false; // Silent failure - doesn't revert!
        }
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
