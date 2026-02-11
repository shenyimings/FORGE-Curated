// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseBridgeCoordinator } from "./BaseBridgeCoordinator.sol";

abstract contract EmergencyManager is BaseBridgeCoordinator {
    /**
     * @notice The role that manages emergency actions
     */
    bytes32 public constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");

    /**
     * @notice Emergency function to forcefully remove a local bridge adapter
     * @dev Only callable by EMERGENCY_MANAGER_ROLE. Use with extreme caution as this will prevent any pending inbound
     * operations from this adapter
     * @param bridgeType The identifier for the bridge protocol
     * @param adapter The local bridge adapter address to remove
     */
    function forceRemoveLocalBridgeAdapter(
        uint16 bridgeType,
        address adapter
    )
        external
        onlyRole(EMERGENCY_MANAGER_ROLE)
    {
        LocalConfig storage config = bridgeTypes[bridgeType].local;
        delete config.isAdapter[adapter];
        if (address(config.outbound) == adapter) {
            delete config.outbound;
        }
    }

    /**
     * @notice Emergency function to forcefully remove a remote bridge adapter
     * @dev Only callable by EMERGENCY_MANAGER_ROLE. Use with extreme caution as this will prevent any pending inbound
     * operations from this adapter
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The remote chain ID
     * @param adapter The remote bridge adapter address to remove
     */
    function forceRemoveRemoteBridgeAdapter(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 adapter
    )
        external
        onlyRole(EMERGENCY_MANAGER_ROLE)
    {
        RemoteConfig storage config = bridgeTypes[bridgeType].remote[chainId];
        delete config.isAdapter[adapter];
        if (config.outbound == adapter) {
            delete config.outbound;
        }
    }
}
