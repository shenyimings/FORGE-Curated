// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title ERC4626Handler
/// @notice Handler test contract for a set of actions
abstract contract ERC4626Handler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function deposit(uint256 assets, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        // Get one of the vaults randomly
        target = _getRandomEVault(j);

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeCall(IERC4626.deposit, (assets, receiver)));
        _after();

        if (success) {} else {
            revert("ERC4626Handler: deposit failed");
        }

        if (IERC20(target).totalSupply() > MAX_UNDERLYING_SUPPLY) {
            revert("ERC4626Handler: deposit overflow");
        }
    }

    function mint(uint256 shares, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        // Get one of the vaults randomly
        target = _getRandomEVault(j);

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeCall(IERC4626.mint, (shares, receiver)));
        _after();

        if (success) {} else {
            revert("ERC4626Handler: mint failed");
        }

        if (IERC20(target).totalSupply() > MAX_UNDERLYING_SUPPLY) {
            revert("ERC4626Handler: deposit overflow");
        }
    }

    function withdraw(uint256 assets, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        // Get one of the vaults randomly
        target = _getRandomEVault(j);

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeCall(IERC4626.withdraw, (assets, receiver, address(actor))));
        _after();

        if (success) {} else {
            revert("ERC4626Handler: withdraw failed");
        }
    }

    function redeem(uint256 shares, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        // Get one of the vaults randomly
        target = _getRandomEVault(j);

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeCall(IERC4626.redeem, (shares, receiver, address(actor))));
        _after();

        if (success) {} else {
            revert("ERC4626Handler: redeem failed");
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
