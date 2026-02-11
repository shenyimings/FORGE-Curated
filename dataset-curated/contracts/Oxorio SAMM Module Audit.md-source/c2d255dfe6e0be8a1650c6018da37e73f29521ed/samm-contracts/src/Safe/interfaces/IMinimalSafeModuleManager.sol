// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.23;

interface IMinimalSafeModuleManager {
    enum Operation {
        Call,
        DelegateCall
    }

    function execTransactionFromModule(address to, uint256 value, bytes memory data, Operation operation)
        external
        returns (bool success);

    /**
     * @notice Execute `operation` (0: Call, 1: DelegateCall) to `to` with `value` (Native Token) and return data
     * @param to Destination address of module transaction.
     * @param value Ether value of module transaction.
     * @param data Data payload of module transaction.
     * @param operation Operation type of module transaction.
     * @return success Boolean flag indicating if the call succeeded.
     * @return returnData Data returned by the call.
     */
    function execTransactionFromModuleReturnData(address to, uint256 value, bytes memory data, Operation operation)
        external
        returns (bool success, bytes memory returnData);

    function enableModule(address module) external;

    function isModuleEnabled(address module) external view returns (bool);

    /**
     * @dev Set a module guard that checks transactions initiated by the module before execution
     *      This can only be done via a Safe transaction.
     *      ⚠️ IMPORTANT: Since a module guard has full power to block Safe transaction execution initiatied via a module,
     *        a broken module guard can cause a denial of service for the Safe modules. Make sure to carefully
     *        audit the module guard code and design recovery mechanisms.
     * @notice Set Module Guard `moduleGuard` for the Safe. Make sure you trust the module guard.
     * @param moduleGuard The address of the module guard to be used or the zero address to disable the module guard.
     */
    function setModuleGuard(address moduleGuard) external;
}
