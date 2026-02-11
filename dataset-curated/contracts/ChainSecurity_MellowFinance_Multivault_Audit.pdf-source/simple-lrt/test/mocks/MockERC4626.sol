// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract MockERC4626 is ERC4626 {
    constructor(address asset_) ERC4626(IERC20(asset_)) ERC20("MockERC4626", "MockERC4626") {}

    function testMockERC4626() internal pure {}
}
