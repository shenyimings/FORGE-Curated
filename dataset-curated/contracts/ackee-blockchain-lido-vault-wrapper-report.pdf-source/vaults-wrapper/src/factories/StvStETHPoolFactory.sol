// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StvStETHPool} from "src/StvStETHPool.sol";

contract StvStETHPoolFactory {
    function deploy(
        address _dashboard,
        bool _allowListEnabled,
        uint256 _reserveRatioGapBP,
        address _withdrawalQueue,
        address _distributor,
        bytes32 _poolType
    ) external returns (address impl) {
        impl = address(
            new StvStETHPool(
                _dashboard, _allowListEnabled, _reserveRatioGapBP, _withdrawalQueue, _distributor, _poolType
            )
        );
    }
}
