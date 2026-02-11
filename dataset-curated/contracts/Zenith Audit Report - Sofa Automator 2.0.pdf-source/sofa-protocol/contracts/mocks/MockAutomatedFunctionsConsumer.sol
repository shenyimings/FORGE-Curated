// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

contract  MockAutomatedFunctionsConsumer {
    bytes public s_lastResponse;
    uint256 public lastUpkeepTimeStamp;

    function setLatestResponse(bytes memory _latestResponse) external {
        s_lastResponse = _latestResponse;
        lastUpkeepTimeStamp = block.timestamp;
    }
}
