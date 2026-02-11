// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StvPool} from "src/StvPool.sol";

contract StvPoolFactory {
    function deploy(
        address _dashboard,
        bool _allowListEnabled,
        address _withdrawalQueue,
        address _distributor,
        bytes32 _poolType
    ) external returns (address impl) {
        impl = address(new StvPool(_dashboard, _allowListEnabled, _withdrawalQueue, _distributor, _poolType));
    }
}
