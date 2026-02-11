// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC4626, IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {
    FlowCaps,
    FlowCapsConfig,
    Withdrawal,
    MAX_SETTABLE_FLOW_CAP,
    IPublicAllocatorStaticTyping,
    IPublicAllocatorBase
} from "src/interfaces/IPublicAllocator.sol";
import {IPublicAllocatorHandler} from "../interfaces/IPublicAllocatorHandler.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title PublicAllocatorHandler
/// @notice Handler test contract for a set of actions
abstract contract PublicAllocatorHandler is IPublicAllocatorHandler, BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function reallocateTo(uint8 i, uint8 j, uint128[MAX_NUM_MARKETS] memory amounts) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three markets randomly
        address supplyMarket = address(_getRandomMarket(address(eulerEarn), i));

        Withdrawal[] memory _withdrawals = _generateWithdrawalsArray(amounts, supplyMarket, j);

        target = address(publicAllocator);

        _before();
        (success, returnData) = actor.proxy(
            target,
            abi.encodeCall(
                IPublicAllocatorBase.reallocateTo, (address(eulerEarn), _withdrawals, IERC4626(supplyMarket))
            )
        );

        if (success) {
            _after();

            /// @dev BALANCES
            assertTrue(_balanceHasNotChanged(address(eulerEarn)), HSPOST_BALANCES_A);
        } else {
            revert("PublicAllocatorHandler: reallocateTo failed");
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HELPERS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _generateWithdrawalsArray(
        uint128[MAX_NUM_MARKETS] memory amounts,
        address excludedAddress,
        uint256 numWithdrawalsSeed
    ) internal returns (Withdrawal[] memory withdrawals) {
        uint256 withdrawalQueueLength = eulerEarn.withdrawQueueLength();
        assertLe(
            withdrawalQueueLength,
            MAX_NUM_MARKETS,
            "PublicAllocatorHandler: withdrawalQueueLength exceeds MAX_NUM_MARKETS"
        );

        uint256 numWithdrawals = clampGe(numWithdrawalsSeed % (withdrawalQueueLength - 1), 1);

        // Initialize the withdrawals array
        withdrawals = new Withdrawal[](numWithdrawals);

        uint256 withdrawalIndex;

        // Iterate through the storage array and populate the struct array
        for (uint256 i; i < withdrawalQueueLength; i++) {
            IERC4626 market = eulerEarn.withdrawQueue(i);

            if (address(market) != excludedAddress && _isMarketEnabled(market, address(eulerEarn))) {
                withdrawals[withdrawalIndex] = Withdrawal({
                    id: market,
                    amount: uint128(clampBetween(amounts[i], 1, _expectedSupplyAssets(market, address(eulerEarn))))
                });
                withdrawalIndex++;
            }
            if (withdrawalIndex == numWithdrawals) break;
        }

        if (withdrawalIndex != withdrawals.length) {
            assembly {
                mstore(withdrawals, withdrawalIndex)
            }
        }
    }
}
