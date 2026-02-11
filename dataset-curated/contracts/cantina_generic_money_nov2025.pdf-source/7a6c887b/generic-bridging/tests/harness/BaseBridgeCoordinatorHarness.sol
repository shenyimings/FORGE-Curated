// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { BridgeCoordinator, IBridgeAdapter } from "../../src/coordinator/BridgeCoordinator.sol";

abstract contract BaseBridgeCoordinatorHarness is BridgeCoordinator {
    function exposed_restrictUnits(address whitelabel, address owner, uint256 amount) external {
        _restrictUnits(whitelabel, owner, amount);
    }

    function exposed_releaseUnits(address whitelabel, address receiver, uint256 amount) external {
        _releaseUnits(whitelabel, receiver, amount);
    }

    function exposed_initializableStorageSlot() external pure returns (bytes32) {
        return _initializableStorageSlot();
    }

    function workaround_setOutboundLocalBridgeAdapter(uint16 bridgeType, address adapter) external {
        bridgeTypes[bridgeType].local.outbound = IBridgeAdapter(adapter);
    }

    function workaround_setOutboundRemoteBridgeAdapter(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 adapter
    )
        external
    {
        bridgeTypes[bridgeType].remote[chainId].outbound = adapter;
    }

    function workaround_setIsLocalBridgeAdapter(uint16 bridgeType, address adapter, bool isAdapter) external {
        bridgeTypes[bridgeType].local.isAdapter[adapter] = isAdapter;
    }

    function workaround_setIsRemoteBridgeAdapter(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 adapter,
        bool isAdapter
    )
        external
    {
        bridgeTypes[bridgeType].remote[chainId].isAdapter[adapter] = isAdapter;
    }

    function workaround_setFailedMessageExecution(bytes32 messageId, bytes32 messageHash) external {
        failedMessageExecutions[messageId] = messageHash;
    }
}
