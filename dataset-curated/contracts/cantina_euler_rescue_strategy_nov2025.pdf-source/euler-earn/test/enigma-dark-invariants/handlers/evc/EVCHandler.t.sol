// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IEVC} from "lib/ethereum-vault-connector/src/interfaces/IEthereumVaultConnector.sol";

// Testing contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler, EnumerableSet} from "../../base/BaseHandler.t.sol";

/// @title EVCHandler
/// @notice Handler test contract for the EVC actions
abstract contract EVCHandler is BaseHandler {
    using EnumerableSet for EnumerableSet.AddressSet;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // COLLATERAL

    function enableCollateral(uint256 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        address vaultAddress = address(eTST);

        (success, returnData) =
            actor.proxy(address(evc), abi.encodeCall(IEVC.enableCollateral, (account, vaultAddress)));

        if (success) {} else {
            revert("EVCHandler: enableCollateral failed");
        }
    }

    function disableCollateral(uint256 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        address vaultAddress = address(eTST);

        (success, returnData) =
            actor.proxy(address(evc), abi.encodeCall(IEVC.disableCollateral, (account, vaultAddress)));

        if (success) {} else {
            revert("EVCHandler: disableCollateral failed");
        }
    }

    // CONTROLLER

    function enableController(uint256 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        address controller = _getRandomLoanVault(j);

        (success, returnData) = actor.proxy(address(evc), abi.encodeCall(IEVC.enableController, (account, controller)));

        if (success) {} else {
            revert("EVCHandler: enableController failed");
        }
    }

    function disableController(uint256 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        (success, returnData) = actor.proxy(address(evc), abi.encodeCall(IEVC.disableController, (account)));

        if (success) {} else {
            revert("EVCHandler: disableController failed");
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
