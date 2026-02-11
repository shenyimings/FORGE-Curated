// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Distributor} from "src/Distributor.sol";

contract DistributorFactory {
    function deploy(address _owner, address _manager) external returns (address impl) {
        impl = address(new Distributor(_owner, _manager));
    }
}

