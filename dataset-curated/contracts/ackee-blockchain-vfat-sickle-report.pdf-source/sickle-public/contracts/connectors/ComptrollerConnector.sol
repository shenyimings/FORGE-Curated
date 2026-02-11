// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IFarmConnector, Farm } from "contracts/interfaces/IFarmConnector.sol";
import {
    CTokenInterface,
    ComptrollerInterface
} from "contracts/interfaces/external/compound-v2/CTokenInterfaces.sol";

struct ComptrollerExtraData {
    address[] cTokens;
}

contract ComptrollerConnector is IFarmConnector {
    error NotImplemented();

    function deposit(
        Farm memory, // target
        address, // token
        bytes memory // extraData
    ) external payable override {
        revert NotImplemented();
    }

    function withdraw(
        Farm memory, // target
        uint256, // amount
        bytes memory // extraData
    ) external pure override {
        revert NotImplemented();
    }

    function claim(
        Farm memory farm,
        bytes memory extraData
    ) external override {
        ComptrollerExtraData memory comptrollerExtraData =
            abi.decode(extraData, (ComptrollerExtraData));
        ComptrollerInterface(farm.stakingContract).claimComp(
            address(this), comptrollerExtraData.cTokens
        );
    }
}
