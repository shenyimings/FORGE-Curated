// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IAutomatedFunctionsConsumer {
    function s_lastResponse() external view returns (bytes memory);
    function lastUpkeepTimeStamp() external view returns (uint256);
}
