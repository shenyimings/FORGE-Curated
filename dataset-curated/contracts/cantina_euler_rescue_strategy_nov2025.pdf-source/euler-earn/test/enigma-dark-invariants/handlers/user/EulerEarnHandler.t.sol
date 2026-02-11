// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC4626, IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IEulerEarnHandler} from "../interfaces/IEulerEarnHandler.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title EulerEarnHandler
/// @notice Handler test contract for a set of actions
abstract contract EulerEarnHandler is IEulerEarnHandler, BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function depositEEV(uint256 _assets, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        target = _getRandomEulerEarnVault(j);

        uint256 previewedShares = IERC4626(target).previewDeposit(_assets);

        _setActionAssetDelta(int256(_assets));

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeCall(IERC4626.deposit, (_assets, receiver)));

        if (success) {
            _after();

            uint256 shares = abi.decode(returnData, (uint256));

            /* HSPOST */

            /// @dev ERC4626
            assertLe(previewedShares, shares, ERC4626_DEPOSIT_INVARIANT_B);

            /// @dev USER
            assertEq(
                defaultVarsBefore.eulerEarnVaults[target].users[receiver].eulerEarnBalance + shares,
                defaultVarsAfter.eulerEarnVaults[target].users[receiver].eulerEarnBalance,
                HSPOST_USER_E
            );

            /// @dev ACCOUNTING
            assertGe(
                defaultVarsAfter.eulerEarnVaults[target].totalAssets,
                defaultVarsBefore.eulerEarnVaults[target].totalAssets + _assets,
                HSPOST_ACCOUNTING_C
            );

            _resetActionAssetDelta();
        } else {
            revert("EulerEarnHandler: deposit failed");
        }
    }

    function mintEEV(uint256 _shares, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        target = _getRandomEulerEarnVault(j);

        uint256 previewedAssets = IERC4626(target).previewMint(_shares);

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeCall(IERC4626.mint, (_shares, receiver)));

        if (success) {
            uint256 _assets = abi.decode(returnData, (uint256));
            _setActionAssetDelta(int256(_assets));

            _after();

            /* HSPOST */

            /// @dev ERC4626
            assertGe(previewedAssets, _assets, ERC4626_MINT_INVARIANT_B);

            /// @dev USER
            assertEq(
                defaultVarsBefore.eulerEarnVaults[target].users[receiver].eulerEarnBalance + _shares,
                defaultVarsAfter.eulerEarnVaults[target].users[receiver].eulerEarnBalance,
                HSPOST_USER_E
            );

            /// @dev ACCOUNTING
            assertGe(
                defaultVarsAfter.eulerEarnVaults[target].totalAssets,
                defaultVarsBefore.eulerEarnVaults[target].totalAssets + _assets,
                HSPOST_ACCOUNTING_C
            );

            _resetActionAssetDelta();
        } else {
            revert("EulerEarnHandler: mint failed");
        }
    }

    function withdrawEEV(uint256 _assets, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        target = _getRandomEulerEarnVault(j);

        uint256 previewedShares = IERC4626(target).previewWithdraw(_assets);

        _setActionAssetDelta(-int256(_assets));

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeCall(IERC4626.withdraw, (_assets, receiver, address(actor))));

        if (success) {
            _after();

            uint256 _shares = abi.decode(returnData, (uint256));

            /* HSPOST */

            /// @dev ERC4626
            assertGe(previewedShares, _shares, ERC4626_WITHDRAW_INVARIANT_B);

            /// @dev USER
            assertEq(
                defaultVarsBefore.eulerEarnVaults[target].users[address(actor)].eulerEarnBalance - _shares,
                defaultVarsAfter.eulerEarnVaults[target].users[address(actor)].eulerEarnBalance,
                HSPOST_USER_F
            );

            /// @dev ACCOUNTING
            assertGe(
                defaultVarsBefore.eulerEarnVaults[target].totalAssets - _assets,
                defaultVarsAfter.eulerEarnVaults[target].totalAssets,
                HSPOST_ACCOUNTING_B
            );

            assertEq(
                defaultVarsBefore.eulerEarnVaults[target].totalAssets - _assets,
                defaultVarsAfter.eulerEarnVaults[target].totalAssets,
                HSPOST_ACCOUNTING_D
            );

            _resetActionAssetDelta();
        } else {
            revert("EulerEarnHandler: withdraw failed");
        }
    }

    function redeemEEV(uint256 _shares, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        target = _getRandomEulerEarnVault(j);

        uint256 previewedAssets = IERC4626(target).previewRedeem(_shares);

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeCall(IERC4626.redeem, (_shares, receiver, address(actor))));

        if (success) {
            uint256 _assets = abi.decode(returnData, (uint256));
            _setActionAssetDelta(-int256(_assets));

            _after();

            /* HSPOST */

            /// @dev ERC4626
            assertLe(previewedAssets, _assets, ERC4626_REDEEM_INVARIANT_B);

            /// @dev USER
            assertEq(
                defaultVarsBefore.eulerEarnVaults[target].users[address(actor)].eulerEarnBalance - _shares,
                defaultVarsAfter.eulerEarnVaults[target].users[address(actor)].eulerEarnBalance,
                HSPOST_USER_F
            );

            /// @dev ACCOUNTING
            assertGe(
                defaultVarsBefore.eulerEarnVaults[target].totalAssets - _assets,
                defaultVarsAfter.eulerEarnVaults[target].totalAssets,
                HSPOST_ACCOUNTING_B
            );
            assertEq(
                defaultVarsBefore.eulerEarnVaults[target].totalAssets - _assets,
                defaultVarsAfter.eulerEarnVaults[target].totalAssets,
                HSPOST_ACCOUNTING_D
            );

            _resetActionAssetDelta();
        } else {
            revert("EulerEarnHandler: redeem failed");
        }
    }
}
