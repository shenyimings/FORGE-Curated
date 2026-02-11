// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IIAgentVaultFactory} from "../interfaces/IIAgentVaultFactory.sol";
import {AgentVault} from "./AgentVault.sol";
import {IIAssetManager} from "../../assetManager/interfaces/IIAssetManager.sol";
import {IIAgentVault} from "../../agentVault/interfaces/IIAgentVault.sol";

contract AgentVaultFactory is IIAgentVaultFactory, IERC165 {
    address public implementation;

    constructor(address _implementation) {
        implementation = _implementation;
    }

    /**
     * @notice Creates new agent vault
     */
    function create(
        IIAssetManager _assetManager
    ) external returns (IIAgentVault) {
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, new bytes(0));
        AgentVault agentVault = AgentVault(payable(address(proxy)));
        agentVault.initialize(_assetManager);
        return agentVault;
    }

    /**
     * Returns the encoded init call, to be used in ERC1967 upgradeToAndCall.
     */
    function upgradeInitCall(
        address /* _proxy */
    ) external pure override returns (bytes memory) {
        // This is the simplest upgrade implementation - no init method needed on upgrade.
        // Future versions of the factory might return a non-trivial call.
        return new bytes(0);
    }

    /**
     * Implementation of ERC-165 interface.
     */
    function supportsInterface(
        bytes4 _interfaceId
    ) external pure override returns (bool) {
        return
            _interfaceId == type(IERC165).interfaceId ||
            _interfaceId == type(IIAgentVaultFactory).interfaceId;
    }
}
