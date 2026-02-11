// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "src/general/AntiSandwichHook.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

contract AntiSandwichMock is AntiSandwichHook {
    constructor(IPoolManager _poolManager) AntiSandwichHook(_poolManager) {}

    function withdrawFees(Currency[] calldata currencies) public {
        for (uint256 i = 0; i < currencies.length; i++) {
            uint256 balance = poolManager.balanceOf(address(this), currencies[i].toId());
            poolManager.transfer(msg.sender, currencies[i].toId(), balance);
        }
    }

    function _handleCollectedFees(PoolKey calldata key, Currency currency, uint256 feeAmount) internal override {
        // empty
    }

    // Exclude from coverage report
    function test() public {}
}
