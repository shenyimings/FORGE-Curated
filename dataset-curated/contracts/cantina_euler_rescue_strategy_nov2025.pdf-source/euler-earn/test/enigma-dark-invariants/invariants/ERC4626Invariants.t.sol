// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries

// Interfaces
import {IEulerEarn} from "src/interfaces/IEulerEarn.sol";

// Contracts
import {HandlerAggregator} from "../HandlerAggregator.t.sol";

import "forge-std/console.sol";

/// @title ERC4626Invariants
/// @notice Implements Invariants for the protocol
/// @dev Inherits HandlerAggregator to check actions in assertion testing mode
abstract contract ERC4626Invariants is HandlerAggregator {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ASSET                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_ERC4626_ASSETS_INVARIANT_A(address eulerEarnAddress) internal {
        try IEulerEarn(eulerEarnAddress).asset() {}
        catch {
            fail(ERC4626_ASSETS_INVARIANT_A);
        }
    }

    function assert_ERC4626_ASSETS_INVARIANT_B(address eulerEarnAddress) internal {
        try IEulerEarn(eulerEarnAddress).totalAssets() returns (uint256 totalAssets) {
            totalAssets;
        } catch {
            fail(ERC4626_ASSETS_INVARIANT_B);
        }
    }

    function assert_ERC4626_ASSETS_INVARIANT_C(address eulerEarnAddress) internal {
        uint256 _assets = _getRandomValue(_maxAssets(eulerEarnAddress));
        uint256 shares;
        bool notFirstLoop;

        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            vm.prank(actorAddresses[i]);
            uint256 tempShares = IEulerEarn(eulerEarnAddress).convertToShares(_assets);

            // Compare the shares with the previous iteration expect the first one
            if (notFirstLoop) {
                assertEq(shares, tempShares, ERC4626_ASSETS_INVARIANT_C);
            } else {
                shares = tempShares;
                notFirstLoop = true;
            }
        }
    }

    function assert_ERC4626_ASSETS_INVARIANT_D(address eulerEarnAddress) internal {
        uint256 _shares = _getRandomValue(_maxShares(eulerEarnAddress));
        uint256 assets;
        bool notFirstLoop;

        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            vm.prank(actorAddresses[i]);
            uint256 tempAssets = IEulerEarn(eulerEarnAddress).convertToAssets(_shares);

            // Compare the shares with the previous iteration expect the first one
            if (notFirstLoop) {
                assertEq(assets, tempAssets, ERC4626_ASSETS_INVARIANT_D);
            } else {
                assets = tempAssets;
                notFirstLoop = true;
            }
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     ACTIONS: DEPOSIT                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_ERC4626_DEPOSIT_INVARIANT_A(address _account, address eulerEarnAddress) internal {
        try IEulerEarn(eulerEarnAddress).maxDeposit(_account) {}
        catch {
            fail(ERC4626_DEPOSIT_INVARIANT_A);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      ACTIONS: MINT                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_ERC4626_MINT_INVARIANT_A(address _account, address eulerEarnAddress) internal {
        try IEulerEarn(eulerEarnAddress).maxMint(_account) {}
        catch {
            fail(ERC4626_MINT_INVARIANT_A);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    ACTIONS: WITHDRAW                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_ERC4626_WITHDRAW_INVARIANT_A(address _account, address eulerEarnAddress) internal {
        try IEulerEarn(eulerEarnAddress).maxWithdraw(_account) {}
        catch {
            fail(ERC4626_WITHDRAW_INVARIANT_A);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    ACTIONS: REDEEM                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_ERC4626_REDEEM_INVARIANT_A(address _account, address eulerEarnAddress) internal {
        try IEulerEarn(eulerEarnAddress).maxRedeem(_account) {}
        catch {
            fail(ERC4626_REDEEM_INVARIANT_A);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         UTILS                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _maxShares(address eulerEarnAddress) internal view returns (uint256 shares) {
        shares = IEulerEarn(eulerEarnAddress).totalSupply();
        shares = shares == 0 ? 1 : shares;
    }

    function _maxAssets(address eulerEarnAddress) internal view returns (uint256 assets) {
        assets = IEulerEarn(eulerEarnAddress).totalAssets();
        assets = assets == 0 ? 1 : assets;
    }

    function _max_withdraw(address from, address eulerEarnAddress) internal view virtual returns (uint256) {
        return IEulerEarn(eulerEarnAddress).convertToAssets(IEulerEarn(eulerEarnAddress).balanceOf(from));
    }

    function _max_redeem(address from, address eulerEarnAddress) internal view virtual returns (uint256) {
        return IEulerEarn(eulerEarnAddress).balanceOf(from);
    }
}
