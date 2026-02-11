// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Dummy ERC20 token for testing
contract DummyERC20 is ERC20 {
    constructor(address[] memory _initialHolders) ERC20("Dummy Token", "TEST_USDS") {
        for (uint256 i = 0; i < _initialHolders.length; i++) {
            _mint(_initialHolders[i], 1000000 * 1e18);
        }
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // adding this to be excluded from coverage report
    function test() external {}
}
