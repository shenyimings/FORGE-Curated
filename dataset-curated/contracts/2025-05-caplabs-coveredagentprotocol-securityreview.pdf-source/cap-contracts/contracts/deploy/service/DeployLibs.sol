// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { BorrowLogic } from "../../lendingPool/libraries/BorrowLogic.sol";
import { LiquidationLogic } from "../../lendingPool/libraries/LiquidationLogic.sol";
import { ReserveLogic } from "../../lendingPool/libraries/ReserveLogic.sol";
import { ValidationLogic } from "../../lendingPool/libraries/ValidationLogic.sol";
import { ViewLogic } from "../../lendingPool/libraries/ViewLogic.sol";
import { AaveAdapter } from "../../oracle/libraries/AaveAdapter.sol";
import { CapTokenAdapter } from "../../oracle/libraries/CapTokenAdapter.sol";
import { ChainlinkAdapter } from "../../oracle/libraries/ChainlinkAdapter.sol";
import { StakedCapAdapter } from "../../oracle/libraries/StakedCapAdapter.sol";
import { LibsConfig } from "../interfaces/DeployConfigs.sol";

contract DeployLibs {
    function _deployLibs() public pure returns (LibsConfig memory d) {
        // grab libraries addresses
        // TODO: use deploy2 to avoid re-deploying already deployed libraries
        d.aaveAdapter = address(AaveAdapter);
        d.chainlinkAdapter = address(ChainlinkAdapter);
        d.capTokenAdapter = address(CapTokenAdapter);
        d.stakedCapAdapter = address(StakedCapAdapter);
    }
}
