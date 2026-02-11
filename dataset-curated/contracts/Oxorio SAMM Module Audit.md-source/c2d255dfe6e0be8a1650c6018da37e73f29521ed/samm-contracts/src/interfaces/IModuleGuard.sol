// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.23;

import {IERC165} from "./IERC165.sol";
import {Enum} from "./../libraries/Enum.sol";
import {IModuleGuardErrors} from "./IModuleGuardErrors.sol";
import {IModuleGuardEvents} from "./IModuleGuardEvents.sol";
import {IModuleGuardGetters} from "./IModuleGuardGetters.sol";

/**
 * @title IModuleGuard Interface
 */
interface IModuleGuard is IERC165, IModuleGuardEvents, IModuleGuardErrors, IModuleGuardGetters {
    function setup(address _safe) external;
    
    function setTxAllowed(address module, address to, bytes4 selector, bool isAllowed) external;
    
    function setAllowance(address module, address to, uint256 amount) external;

    function checkModuleTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        address module
    ) external returns (bytes32 moduleTxHash);

    function checkAfterModuleExecution(bytes32 txHash, bool success) external;
}
