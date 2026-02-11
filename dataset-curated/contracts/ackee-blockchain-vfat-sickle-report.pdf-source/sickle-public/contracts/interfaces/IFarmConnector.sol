// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Farm } from "contracts/structs/FarmStrategyStructs.sol";

interface IFarmConnector {
    function deposit(
        Farm calldata farm,
        address token,
        bytes memory extraData
    ) external payable;

    function withdraw(
        Farm calldata farm,
        uint256 amount,
        bytes memory extraData
    ) external;

    function claim(Farm calldata farm, bytes memory extraData) external;
}
