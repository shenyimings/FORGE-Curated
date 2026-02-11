// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {CollateralRatiosRebalanceAdapter} from "src/rebalance/CollateralRatiosRebalanceAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";

/// @notice Wrapper contract that exposes all internal functions of CollateralRatiosRebalanceAdapter
contract CollateralRatiosRebalanceAdapterHarness is CollateralRatiosRebalanceAdapter {
    ILeverageManager public leverageManager;

    function initialize(uint256 minCollateralRatio, uint256 targetCollateralRatio, uint256 maxCollateralRatio)
        external
        initializer
    {
        __CollateralRatiosRebalanceAdapter_init(minCollateralRatio, targetCollateralRatio, maxCollateralRatio);
    }

    function exposed_getCollateralRatiosRebalanceAdapterStorage() external pure returns (bytes32 slot) {
        CollateralRatiosRebalanceAdapterStorage storage $ = _getCollateralRatiosRebalanceAdapterStorage();

        assembly {
            slot := $.slot
        }
    }

    function getLeverageManager() public view override returns (ILeverageManager) {
        return leverageManager;
    }

    function mock_setLeverageManager(ILeverageManager _leverageManager) external {
        leverageManager = _leverageManager;
    }
}
