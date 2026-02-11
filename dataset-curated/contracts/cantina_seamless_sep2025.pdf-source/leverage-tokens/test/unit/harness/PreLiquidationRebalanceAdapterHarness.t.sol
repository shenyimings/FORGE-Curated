// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {PreLiquidationRebalanceAdapter} from "src/rebalance/PreLiquidationRebalanceAdapter.sol";

contract PreLiquidationRebalanceAdapterHarness is PreLiquidationRebalanceAdapter {
    ILeverageManager public leverageManager;

    function initialize(uint256 collateralRatioThreshold, uint256 rebalanceReward) external initializer {
        __PreLiquidationRebalanceAdapter_init(collateralRatioThreshold, rebalanceReward);
    }

    function exposed_getPreLiquidationRebalanceAdapterStorageSlot() external pure returns (bytes32 slot) {
        PreLiquidationRebalanceAdapterStorage storage $ = _getPreLiquidationRebalanceAdapterStorage();

        assembly {
            slot := $.slot
        }
    }

    function getLeverageManager() public view override returns (ILeverageManager) {
        return leverageManager;
    }

    function setLeverageManager(ILeverageManager _leverageManager) external {
        leverageManager = _leverageManager;
    }
}
