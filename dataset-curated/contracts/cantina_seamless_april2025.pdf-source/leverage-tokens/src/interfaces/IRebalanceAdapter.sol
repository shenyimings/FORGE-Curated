// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";

interface IRebalanceAdapter is IRebalanceAdapterBase {
    /// @notice Error thrown when the caller is not the authorized creator of the RebalanceAdapter
    error Unauthorized();

    /// @notice Event emitted when the rebalance adapter is initialized
    /// @param authorizedCreator The authorized creator of the RebalanceAdapter, allowed to create LeverageTokens using this adapter
    /// @param leverageManager The LeverageManager of the RebalanceAdapter
    event RebalanceAdapterInitialized(address indexed authorizedCreator, ILeverageManager indexed leverageManager);

    /// @notice Returns the authorized creator of the RebalanceAdapter
    /// @return authorizedCreator The authorized creator of the RebalanceAdapter
    function getAuthorizedCreator() external view returns (address authorizedCreator);

    /// @notice Returns the LeverageManager of the RebalanceAdapter
    /// @return leverageManager The LeverageManager of the RebalanceAdapter
    function getLeverageManager() external view returns (ILeverageManager leverageManager);
}
