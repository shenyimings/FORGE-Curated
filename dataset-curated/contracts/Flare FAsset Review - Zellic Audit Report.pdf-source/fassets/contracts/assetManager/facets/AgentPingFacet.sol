// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IAgentPing} from "../../userInterfaces/IAgentPing.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {Agent} from "../../assetManager/library/data/Agent.sol";


contract AgentPingFacet is AssetManagerBase, IAgentPing {
    /**
     * @inheritdoc IAgentPing
     */
    function agentPing(address _agentVault, uint256 _query) external {
        emit AgentPing(_agentVault, msg.sender, _query);
    }

    /**
     * @inheritdoc IAgentPing
     */
    function agentPingResponse(address _agentVault, uint256 _query, string memory _response)
        external
        onlyAgentVaultOwner(_agentVault)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        emit AgentPingResponse(_agentVault, agent.ownerManagementAddress, _query, _response);
    }
}
