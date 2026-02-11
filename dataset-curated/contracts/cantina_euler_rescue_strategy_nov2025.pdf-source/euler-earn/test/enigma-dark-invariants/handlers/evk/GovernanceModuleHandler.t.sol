// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import "lib/euler-vault-kit/src/EVault/shared/Constants.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

// Interfaces
import {IEVault, IGovernance} from "lib/euler-vault-kit/src/EVault/IEVault.sol";

/// @title GovernanceModuleHandler
/// @notice Handler test contract for the governance module actions
contract GovernanceModuleHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function convertFees(uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        target = _getRandomLoanVault(i);

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeCall(IGovernance.convertFees, ()));

        if (success) {
            _after();
        } else {
            revert("GovernanceModuleHandler: convertFees failed");
        }
    }

    function setLTV(uint16 borrowLTV, uint16 liquidationLTV, uint24 rampDuration, uint8 i) external directCallCleanup {
        address collateral = address(eTST);
        target = _getRandomLoanVault(i);

        borrowLTV = uint16(clampBetween(borrowLTV, 0.8e4, 0.95e4));
        liquidationLTV = uint16(clampBetween(liquidationLTV, 0.85e4, 0.95e4));

        _before();
        IEVault(target).setLTV(collateral, borrowLTV, liquidationLTV, rampDuration);
        _after();
    }

    function setInterestFee(uint16 interestFee, uint8 i) external directCallCleanup {
        target = _getRandomLoanVault(i);

        _before();
        IEVault(target).setInterestFee(interestFee);
        _after();
    }

    function setDebtSocialization(bool status, uint8 i) external directCallCleanup {
        target = _getRandomLoanVault(i);

        uint32 bitmask = IEVault(target).configFlags();
        if (status) bitmask = _removeConfiguration(bitmask, CFG_DONT_SOCIALIZE_DEBT);
        else bitmask = _addConfiguration(bitmask, CFG_DONT_SOCIALIZE_DEBT);

        _before();
        IEVault(target).setConfigFlags(bitmask);
        _after();
    }

    function setCaps(uint16 supplyCap, uint16 borrowCap, uint8 i) external directCallCleanup {
        target = _getRandomEVault(i);

        _before();
        IEVault(target).setCaps(supplyCap, borrowCap);
        _after();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HELPERS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Function to add a configuration to the bitmask
    function _addConfiguration(uint32 bitmask, uint32 configToAdd) internal pure returns (uint32) {
        return bitmask |= configToAdd;
    }

    // Function to remove a configuration from the bitmask
    function _removeConfiguration(uint32 bitmask, uint32 configToRemove) internal pure returns (uint32) {
        return bitmask &= ~configToRemove;
    }
}
