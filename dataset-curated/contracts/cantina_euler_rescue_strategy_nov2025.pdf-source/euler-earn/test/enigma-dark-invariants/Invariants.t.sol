// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC4626, IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

// Invariant Contracts
import {BaseInvariants} from "./invariants/BaseInvariants.t.sol";
import {ERC4626Invariants} from "./invariants/ERC4626Invariants.t.sol";

/// @title Invariants
/// @notice Wrappers for the protocol invariants implemented in each invariants contract
/// @dev recognised by Echidna when property mode is activated
/// @dev Inherits BaseInvariants
abstract contract Invariants is BaseInvariants, ERC4626Invariants {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     BASE INVARIANTS                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function echidna_INV_BASE() public returns (bool) {
        for (uint256 i; i < eulerEarnVaults.length; i++) {
            address eulerEarn_ = eulerEarnVaults[i];
            for (uint256 j; j < allMarkets[eulerEarn_].length; j++) {
                IERC4626 market = allMarkets[eulerEarn_][j];
                assert_INV_BASE_A(market, eulerEarn_);
                assert_INV_BASE_C(market, eulerEarn_);
                assert_INV_BASE_D(market, eulerEarn_);
                assert_INV_BASE_E(market, eulerEarn_);
            }

            assert_INV_BASE_F(eulerEarn_);
        }

        return true;
    }

    function echidna_INV_QUEUES() public returns (bool) {
        for (uint256 i; i < eulerEarnVaults.length; i++) {
            address eulerEarn_ = eulerEarnVaults[i];
            assert_INV_QUEUES_AE(eulerEarn_);
            assert_INV_QUEUES_B(eulerEarn_);
        }

        return true;
    }

    function echidna_INV_TIMELOCK() public returns (bool) {
        for (uint256 i; i < eulerEarnVaults.length; i++) {
            address eulerEarn_ = eulerEarnVaults[i];
            assert_INV_TIMELOCK_A(eulerEarn_);
            assert_INV_TIMELOCK_D(eulerEarn_);
            assert_INV_TIMELOCK_E(eulerEarn_);
            assert_INV_TIMELOCK_F(eulerEarn_);
        }

        return true;
    }

    function echidna_INV_MARKETS() public returns (bool) {
        for (uint256 i; i < eulerEarnVaults.length; i++) {
            address eulerEarn_ = eulerEarnVaults[i];
            for (uint256 j; j < allMarkets[eulerEarn_].length; j++) {
                assert_INV_MARKETS_AB(allMarkets[eulerEarn_][j], eulerEarn_);
            }
        }

        return true;
    }

    function echidna_INV_FEES() public returns (bool) {
        for (uint256 i; i < eulerEarnVaults.length; i++) {
            assert_INV_FEES_A(eulerEarnVaults[i]);
        }

        return true;
    }

    function echidna_INV_ACCOUNTING() public returns (bool) {
        for (uint256 i; i < eulerEarnVaults.length; i++) {
            address eulerEarn_ = eulerEarnVaults[i];
            assert_INV_ACCOUNTING_A(eulerEarn_);
        }

        return true;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    ERC4626 INVARIANTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function echidna_ERC4626_ASSETS_INVARIANTS() public returns (bool) {
        for (uint256 i; i < eulerEarnVaults.length; i++) {
            address eulerEarn_ = eulerEarnVaults[i];
            assert_ERC4626_ASSETS_INVARIANT_A(eulerEarn_);
            assert_ERC4626_ASSETS_INVARIANT_B(eulerEarn_);
            assert_ERC4626_ASSETS_INVARIANT_C(eulerEarn_);
            assert_ERC4626_ASSETS_INVARIANT_D(eulerEarn_);
        }

        return true;
    }

    function echidna_ERC4626_USERS() public returns (bool) {
        for (uint256 i; i < eulerEarnVaults.length; i++) {
            address eulerEarn_ = eulerEarnVaults[i];
            for (uint256 j; j < actorAddresses.length; j++) {
                assert_ERC4626_DEPOSIT_INVARIANT_A(actorAddresses[j], eulerEarn_);
                assert_ERC4626_MINT_INVARIANT_A(actorAddresses[j], eulerEarn_);
                assert_ERC4626_WITHDRAW_INVARIANT_A(actorAddresses[j], eulerEarn_);
                assert_ERC4626_REDEEM_INVARIANT_A(actorAddresses[j], eulerEarn_);
            }
        }

        return true;
    }
}
