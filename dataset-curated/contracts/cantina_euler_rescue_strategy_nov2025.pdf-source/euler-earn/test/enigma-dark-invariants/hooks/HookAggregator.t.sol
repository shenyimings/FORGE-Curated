// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC4626, IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

// Hook Contracts
import {DefaultBeforeAfterHooks} from "./DefaultBeforeAfterHooks.t.sol";

import {console} from "forge-std/console.sol";

/// @title HookAggregator
/// @notice Helper contract to aggregate all before / after hook contracts, inherited on each handler
abstract contract HookAggregator is DefaultBeforeAfterHooks {
    /// @notice Initializer for the hooks
    function _setUpHooks() internal {
        _setUpDefaultHooks();
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                         HOOKS                                             //
    /////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Modular hook selector, per module
    function _before() internal {
        _defaultHooksBefore();
    }

    /// @notice Modular hook selector, per module
    function _after() internal {
        _defaultHooksAfter();

        // POST-CONDITIONS
        for (uint256 i; i < eulerEarnVaults.length; i++) {
            _checkPostConditions(eulerEarnVaults[i]);
        }

        // Reset the state
        _resetState();
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                   POSTCONDITION CHECKS                                    //
    /////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice General postconditions for each euler earn vault
    function _checkPostConditions(address eulerEarnAddress) internal {
        // Base
        assert_GPOST_BASE_C(eulerEarnAddress);

        // Fees
        assert_GPOST_FEES_A(eulerEarnAddress);

        // Accounting
        assert_GPOST_ACCOUNTING_A();
        assert_GPOST_ACCOUNTING_B();
        assert_GPOST_ACCOUNTING_C(eulerEarnAddress);
        assert_GPOST_ACCOUNTING_D();
        assert_GPOST_ACCOUNTING_F(eulerEarnAddress);
        assert_GPOST_ACCOUNTING_G(eulerEarnAddress);
        assert_GPOST_ACCOUNTING_H(eulerEarnAddress);
        assert_GPOST_ACCOUNTING_I(eulerEarnAddress);

        // Markets
        for (uint256 i; i < allMarkets[eulerEarnAddress].length; i++) {
            _checkMarketPostConditions(eulerEarnAddress, allMarkets[eulerEarnAddress][i]);
        }
    }

    /// @notice Postconditions for each market
    function _checkMarketPostConditions(address eulerEarnAddress, IERC4626 market) internal {
        assert_GPOST_BASE_B(eulerEarnAddress, market);
        assert_GPOST_BASE_D(eulerEarnAddress, market);
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    /////////////////////////////////////////////////////////////////////////////////////////////*/

    function _resetState() internal {}
}
