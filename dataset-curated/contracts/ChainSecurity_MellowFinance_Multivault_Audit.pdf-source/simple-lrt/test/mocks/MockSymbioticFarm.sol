// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../Imports.sol";

contract MockSymbioticFarm {
    function claimRewards(address recipient, address token, bytes calldata /* data */ ) external {
        IERC20(token).transfer(recipient, IERC20(token).balanceOf(address(this)));
    }

    function test() private pure {}
}
