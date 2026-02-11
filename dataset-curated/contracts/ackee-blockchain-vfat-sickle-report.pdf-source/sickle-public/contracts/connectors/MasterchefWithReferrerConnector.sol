// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from
    "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import {
    MasterchefConnector,
    IMasterchef,
    Farm
} from "contracts/connectors/MasterchefConnector.sol";

struct MasterchefExtraData {
    address referrer;
}

contract MasterchefWithReferrerConnector is MasterchefConnector {
    constructor() { }

    function deposit(
        Farm calldata farm,
        address token,
        bytes memory extraData
    ) external payable override {
        uint256 amount = IERC20(token).balanceOf(address(this));
        SafeTransferLib.safeApprove(token, farm.stakingContract, amount);
        MasterchefExtraData memory masterChefExtraData =
            abi.decode(extraData, (MasterchefExtraData));
        IMasterchef(farm.stakingContract).deposit(
            farm.poolIndex, amount, masterChefExtraData.referrer
        );
    }
}
