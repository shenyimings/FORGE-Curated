// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries

// Interfaces
import {IERC4626, IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {MarketConfig, PendingUint136} from "src/interfaces/IEulerEarn.sol";
import {IEulerEarn} from "src/interfaces/IEulerEarn.sol";

// Contracts
import {HandlerAggregator} from "../HandlerAggregator.t.sol";

import "forge-std/console.sol";

/// @title BaseInvariants
/// @notice Implements Invariants for the protocol
/// @dev Inherits HandlerAggregator to check actions in assertion testing mode
abstract contract BaseInvariants is HandlerAggregator {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          BASE                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_INV_BASE_A(IERC4626 market, address eulerEarnAddress) internal {
        MarketConfig memory config = IEulerEarn(eulerEarnAddress).config(market);
        if (config.cap > 0) assertTrue(config.enabled, INV_BASE_A);
    }

    function assert_INV_BASE_C(IERC4626 market, address eulerEarnAddress) internal {
        MarketConfig memory config = IEulerEarn(eulerEarnAddress).config(market);
        if (config.cap > 0) assertEq(config.removableAt, 0, INV_BASE_C);
    }

    function assert_INV_BASE_D(IERC4626 market, address eulerEarnAddress) internal {
        MarketConfig memory config = IEulerEarn(eulerEarnAddress).config(market);
        if (!config.enabled) assertEq(config.removableAt, 0, INV_BASE_D);
    }

    function assert_INV_BASE_E(IERC4626 market, address eulerEarnAddress) internal {
        PendingUint136 memory pendingCap = IEulerEarn(eulerEarnAddress).pendingCap(market);
        if (pendingCap.value != 0 || pendingCap.validAt != 0) {
            assertEq(IEulerEarn(eulerEarnAddress).config(market).removableAt, 0, INV_BASE_E);
        }
    }

    function assert_INV_BASE_F(address eulerEarnAddress) internal {
        assertLe(IEulerEarn(eulerEarnAddress).fee(), MAX_FEE, INV_BASE_F);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         QUEUES                                            //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    mapping(IERC4626 => bool) withdrawQueueCache;

    function assert_INV_QUEUES_AE(address eulerEarnAddress) internal {
        uint256 len = IEulerEarn(eulerEarnAddress).withdrawQueueLength();

        for (uint256 i; i < len; i++) {
            IERC4626 market = IEulerEarn(eulerEarnAddress).withdrawQueue(i);
            assertFalse(withdrawQueueCache[market], INV_QUEUES_A);

            withdrawQueueCache[market] = true;
        }

        uint256 allMarketsLength = allMarkets[eulerEarnAddress].length;

        for (uint256 i; i < allMarketsLength; i++) {
            IERC4626 market = allMarkets[eulerEarnAddress][i];
            if (IEulerEarn(eulerEarnAddress).config(market).enabled) {
                assertTrue(withdrawQueueCache[market], INV_QUEUES_E);
            }
        }

        for (uint256 i; i < allMarketsLength; i++) {
            IERC4626 market = allMarkets[eulerEarnAddress][i];
            delete withdrawQueueCache[market];
        }
    }

    function assert_INV_QUEUES_B(address eulerEarnAddress) internal {
        uint256 len = IEulerEarn(eulerEarnAddress).withdrawQueueLength();

        for (uint256 i; i < len; i++) {
            assertTrue(
                IEulerEarn(eulerEarnAddress).config(IEulerEarn(eulerEarnAddress).withdrawQueue(i)).enabled, INV_QUEUES_B
            );
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        TIMELOCK                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_INV_TIMELOCK_A(address eulerEarnAddress) internal {
        assertLt(
            IEulerEarn(eulerEarnAddress).pendingTimelock().value,
            IEulerEarn(eulerEarnAddress).timelock(),
            INV_TIMELOCK_A
        );
    }

    function assert_INV_TIMELOCK_D(address eulerEarnAddress) internal {
        address pendingGuardian = IEulerEarn(eulerEarnAddress).pendingGuardian().value;

        if (pendingGuardian != address(0)) {
            assertTrue(pendingGuardian != IEulerEarn(eulerEarnAddress).guardian(), INV_TIMELOCK_D);
        }
    }

    function assert_INV_TIMELOCK_E(address eulerEarnAddress) internal {
        uint256 pendingTimelock = IEulerEarn(eulerEarnAddress).pendingTimelock().value;
        if (pendingTimelock != 0) {
            assertLe(pendingTimelock, MAX_TIMELOCK, INV_TIMELOCK_E);
            assertGe(pendingTimelock, MIN_TIMELOCK, INV_TIMELOCK_E);
        }
    }

    function assert_INV_TIMELOCK_F(address eulerEarnAddress) internal {
        uint256 timelock = IEulerEarn(eulerEarnAddress).timelock();
        assertLe(timelock, MAX_TIMELOCK, INV_TIMELOCK_F);
        assertGe(timelock, MIN_TIMELOCK, INV_TIMELOCK_F);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        MARKETS                                            //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_INV_MARKETS_AB(IERC4626 market, address eulerEarnAddress) internal {
        uint256 pendingCap = IEulerEarn(eulerEarnAddress).pendingCap(market).value;
        uint256 cap = IEulerEarn(eulerEarnAddress).config(market).cap;
        uint256 validAt = IEulerEarn(eulerEarnAddress).pendingCap(market).validAt;

        if (pendingCap == 0) {
            assertEq(pendingCap, validAt, INV_MARKETS_A);
        } else {
            assertGt(pendingCap, cap, INV_MARKETS_B);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          FEES                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_INV_FEES_A(address eulerEarnAddress) internal {
        uint256 fee = IEulerEarn(eulerEarnAddress).fee();
        address feeRecipient = IEulerEarn(eulerEarnAddress).feeRecipient();

        if (feeRecipient == address(0)) {
            assertEq(fee, 0, INV_FEES_A);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         ACCOUNTING                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_INV_ACCOUNTING_A(address eulerEarnAddress) internal {
        assertGe(
            IEulerEarn(eulerEarnAddress).totalAssets(), IEulerEarn(eulerEarnAddress).lastTotalAssets(), INV_ACCOUNTING_A
        );
    }

    function assert_INV_ACCOUNTING_C(address eulerEarnAddress) internal {
        assertEq(loanToken.balanceOf(address(eulerEarnAddress)), underlyingAmountDonatedToVault, INV_ACCOUNTING_C);
    }
}
