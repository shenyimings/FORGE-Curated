// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../core/interfaces/IPriorityPool.sol";
import "./interfaces/IFundFlowController.sol";

/**
 * @title Priority Pool Keeper
 * @notice Proxies keeper calls to the priority pool so deposit data can be fetched beforehand
 */
contract PPKeeper {
    IPriorityPool public priorityPool;
    IFundFlowController public fundFlowController;

    /**
     * @notice Initializes contract
     * @param _priorityPool address of priority pool
     * @param _fundFlowController address of fund flow controller
     */
    constructor(address _priorityPool, address _fundFlowController) {
        priorityPool = IPriorityPool(_priorityPool);
        fundFlowController = IFundFlowController(_fundFlowController);
    }

    /**
     * @notice Returns whether a deposit should be executed through the priority pool
     * @return true if deposit needed, false otherwise
     * @return encoded vault deposit data
     */
    function checkUpkeep(bytes calldata) external view returns (bool, bytes memory) {
        (bool upkeepNeeded, bytes memory data) = priorityPool.checkUpkeep("");

        if (!upkeepNeeded) return (false, "");

        uint256 amountToDeposit = abi.decode(data, (uint256));
        bytes[] memory depositData = fundFlowController.getDepositData(amountToDeposit);

        return (true, abi.encode(depositData));
    }

    /**
     * @notice Executes a deposit through the priority pool
     * @param _performData encoded vault deposit data
     */
    function performUpkeep(bytes calldata _performData) external {
        priorityPool.performUpkeep(_performData);
    }
}
