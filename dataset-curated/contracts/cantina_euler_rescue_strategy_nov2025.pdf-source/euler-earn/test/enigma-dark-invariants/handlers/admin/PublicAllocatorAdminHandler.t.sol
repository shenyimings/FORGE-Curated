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

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title PublicAllocatorAdminHandler
/// @notice Handler test contract for a set of actions
abstract contract PublicAllocatorAdminHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function setFee(uint256 newFee) external {
        publicAllocator.setFee(address(eulerEarn), newFee);
    }

    function setFlowCaps(FlowCaps[MAX_NUM_MARKETS] memory _flowCaps) external {
        FlowCapsConfig[] memory flowCapsConfig = _getFlowCaps(_flowCaps);

        publicAllocator.setFlowCaps(address(eulerEarn), flowCapsConfig);
    }

    function transferFee() external {
        publicAllocator.transferFee(address(eulerEarn), FEE_RECIPIENT);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HELPERS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _getFlowCaps(FlowCaps[MAX_NUM_MARKETS] memory _flowcaps) internal view returns (FlowCapsConfig[] memory) {
        // Create a memory array of FlowCapsConfig structs
        FlowCapsConfig[] memory flowCapsConfigs = new FlowCapsConfig[](MAX_NUM_MARKETS);

        uint256 enabledMarkets;
        for (uint256 i; i < MAX_NUM_MARKETS; i++) {
            if (_isMarketEnabled(allMarkets[address(eulerEarn)][i], address(eulerEarn))) {
                flowCapsConfigs[enabledMarkets++] =
                    FlowCapsConfig({id: IERC4626(allMarkets[address(eulerEarn)][i]), caps: _flowcaps[i]});
            }
        }

        if (flowCapsConfigs.length != enabledMarkets) {
            assembly {
                mstore(flowCapsConfigs, enabledMarkets)
            }
        }

        return flowCapsConfigs;
    }
}
