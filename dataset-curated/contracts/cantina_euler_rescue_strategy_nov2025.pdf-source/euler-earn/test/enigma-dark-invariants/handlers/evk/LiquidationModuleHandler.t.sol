// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

// Interfaces
import {IEVault, ILiquidation} from "lib/euler-vault-kit/src/EVault/IEVault.sol";
import {IEVC} from "lib/ethereum-vault-connector/src/interfaces/IEthereumVaultConnector.sol";

/// @title LiquidationModuleHandler
/// @notice Handler test contract for the VaultRegularBorrowable actions
contract LiquidationModuleHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Liquidates an actor's debt on the target vault: eTST
    function liquidate(uint256 repayAssets, uint256 minYieldBalance, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address violator = _getRandomActor(i);

        target = _getRandomLoanVault(j);

        if (repayAssets != 0) {
            (success, returnData) = actor.proxy(address(evc), abi.encodeCall(IEVC.enableController, (violator, target)));
        }

        (success, returnData) = _liquidate(violator, IEVault(target), repayAssets, minYieldBalance);

        if (success) {} else {
            revert("LiquidationModuleHandler: liquidateActor failed");
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _liquidate(address violator, IEVault targetVault, uint256 repayAssets, uint256 minYieldBalance)
        internal
        returns (bool liquidationSuccess, bytes memory returnData)
    {
        bool success;

        (uint256 maxRepay, uint256 maxYield) = targetVault.checkLiquidation(address(actor), violator, address(eTST));

        {
            (, uint256 liabilityValue) = targetVault.accountLiquidity(violator, true);
            require(liabilityValue > 0, "LiquidationModuleHandler: debtViolator is 0");

            minYieldBalance = clampLe(minYieldBalance, maxYield);
        }

        // Set the target to the target vault
        target = address(targetVault);

        _before();
        (success, returnData) = actor.proxy(
            target, abi.encodeCall(ILiquidation.liquidate, (violator, address(eTST), repayAssets, minYieldBalance))
        );

        if (success && (maxRepay != 0 && minYieldBalance != 0)) {
            liquidationSuccess = true;
            _after();
        }
    }
}
