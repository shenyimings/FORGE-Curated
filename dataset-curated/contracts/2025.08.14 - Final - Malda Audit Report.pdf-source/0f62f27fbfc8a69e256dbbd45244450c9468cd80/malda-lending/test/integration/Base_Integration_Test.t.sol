// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|                           
*/

//contracts
import {Roles} from "src/Roles.sol";

import {Types} from "../utils/Types.sol";
import {Events} from "../utils/Events.sol";
import {Helpers} from "../utils/Helpers.sol";

abstract contract Base_Integration_Test is Events, Helpers, Types {
    address public alice;


    // ----------- FORKS ------------
    uint256 public lineaFork;
    string public lineaUrl = vm.envString("LINEA_RPC_URL");

    // ----------- MALDA ------------
    Roles public roles;

    function setUp() public virtual {
        lineaFork = vm.createSelectFork(lineaUrl);

        roles = new Roles(address(this));
        vm.label(address(roles), "Roles");

        alice = _spawnAccount(ALICE_KEY, "Alice");
    }
}
