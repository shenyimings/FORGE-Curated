// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {AgentCollateral} from "../library/AgentCollateral.sol";
import {Agents} from "../library/Agents.sol";
import {Globals} from "../library/Globals.sol";
import {Agent} from "../library/data/Agent.sol";
import {AssetManagerState} from "../library/data/AssetManagerState.sol";
import {Collateral} from "../library/data/Collateral.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {AvailableAgentInfo} from "../../userInterfaces/data/AvailableAgentInfo.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";


contract AvailableAgentsFacet is AssetManagerBase {
    using SafeCast for uint256;
    using AgentCollateral for Collateral.CombinedData;

    error ExitTooLate();
    error ExitTooSoon();
    error ExitNotAnnounced();
    error AgentNotAvailable();
    error NotEnoughFreeCollateral();
    error AgentAlreadyAvailable();
    error InvalidAgentStatus();

    /**
     * Add the agent to the list of publicly available agents.
     * Other agents can only self-mint.
     * NOTE: may only be called by the agent vault owner.
     * @param _agentVault agent vault address
     */
    function makeAgentAvailable(
        address _agentVault
    )
        external
        notEmergencyPaused
        onlyAgentVaultOwner(_agentVault)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        Agent.State storage agent = Agent.get(_agentVault);
        require(agent.status == Agent.Status.NORMAL, InvalidAgentStatus());
        require(agent.availableAgentsPos == 0, AgentAlreadyAvailable());
        // check that there is enough free collateral for at least one lot
        Collateral.CombinedData memory collateralData = AgentCollateral.combinedData(agent);
        uint256 freeCollateralLots = collateralData.freeCollateralLots(agent);
        require(freeCollateralLots >= 1, NotEnoughFreeCollateral());
        // add to queue
        state.availableAgents.push(_agentVault);
        agent.availableAgentsPos = state.availableAgents.length.toUint32();     // index+1 (0=not in list)
        emit IAssetManagerEvents.AgentAvailable(_agentVault, agent.feeBIPS,
            agent.mintingVaultCollateralRatioBIPS, agent.mintingPoolCollateralRatioBIPS, freeCollateralLots);
    }

    /**
     * Announce exit from the publicly available agents list.
     * NOTE: may only be called by the agent vault owner.
     * @param _agentVault agent vault address
     * @return _exitAllowedAt the timestamp when the agent can exit
     */
    function announceExitAvailableAgentList(
        address _agentVault
    )
        external
        notEmergencyPaused
        onlyAgentVaultOwner(_agentVault)
        returns (uint256 _exitAllowedAt)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        require(agent.availableAgentsPos != 0, AgentNotAvailable());
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        _exitAllowedAt = block.timestamp + settings.agentExitAvailableTimelockSeconds;
        agent.exitAvailableAfterTs = _exitAllowedAt.toUint64();
        emit IAssetManagerEvents.AvailableAgentExitAnnounced(_agentVault, _exitAllowedAt);
    }

    /**
     * Exit the publicly available agents list.
     * NOTE: may only be called by the agent vault owner and after announcement.
     * @param _agentVault agent vault address
     */
    function exitAvailableAgentList(
        address _agentVault
    )
        external
        notFullyEmergencyPaused
        onlyAgentVaultOwner(_agentVault)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        Agent.State storage agent = Agent.get(_agentVault);
        require(agent.availableAgentsPos != 0, AgentNotAvailable());
        require(agent.exitAvailableAfterTs != 0, ExitNotAnnounced());
        require(block.timestamp >= agent.exitAvailableAfterTs, ExitTooSoon());
        require(block.timestamp <= agent.exitAvailableAfterTs + settings.agentTimelockedOperationWindowSeconds,
            ExitTooLate());
        uint256 ind = agent.availableAgentsPos - 1;
        if (ind + 1 < state.availableAgents.length) {
            state.availableAgents[ind] = state.availableAgents[state.availableAgents.length - 1];
            Agent.State storage movedAgent = Agent.get(state.availableAgents[ind]);
            movedAgent.availableAgentsPos = uint32(ind + 1);
        }
        agent.availableAgentsPos = 0;
        state.availableAgents.pop();
        agent.exitAvailableAfterTs = 0;
        emit IAssetManagerEvents.AvailableAgentExited(_agentVault);
    }

    /**
     * Get (a part of) the list of available agents.
     * The list must be retrieved in parts since retrieving the whole list can consume too much gas for one block.
     * @param _start first index to return from the available agent's list
     * @param _end end index (one above last) to return from the available agent's list
     */
    function getAvailableAgentsList(
        uint256 _start,
        uint256 _end
    )
        external view
        returns (address[] memory _agents, uint256 _totalLength)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        _totalLength = state.availableAgents.length;
        _end = Math.min(_end, _totalLength);
        _start = Math.min(_start, _end);
        _agents = new address[](_end - _start);
        for (uint256 i = _start; i < _end; i++) {
            _agents[i - _start] = state.availableAgents[i];
        }
    }

    /**
     * Get (a part of) the list of available agents with extra information about agents' fee, min collateral ratio
     * and available collateral (in lots).
     * The list must be retrieved in parts since retrieving the whole list can consume too much gas for one block.
     * NOTE: agent's available collateral can change anytime due to price changes, minting, or changes
     * in agent's min collateral ratio, so it is only to be used as estimate.
     * @param _start first index to return from the available agent's list
     * @param _end end index (one above last) to return from the available agent's list
     */
    function getAvailableAgentsDetailedList(
        uint256 _start,
        uint256 _end
    )
        external view
        returns (AvailableAgentInfo.Data[] memory _agents, uint256 _totalLength)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        _totalLength = state.availableAgents.length;
        _end = Math.min(_end, _totalLength);
        _start = Math.min(_start, _end);
        _agents = new AvailableAgentInfo.Data[](_end - _start);
        for (uint256 i = _start; i < _end; i++) {
            address agentVault = state.availableAgents[i];
            Agent.State storage agent = Agent.getWithoutCheck(agentVault);
            Collateral.CombinedData memory collateralData = AgentCollateral.combinedData(agent);
            (uint256 agentCR,) = AgentCollateral.mintingMinCollateralRatio(agent, Collateral.Kind.VAULT);
            (uint256 poolCR,) = AgentCollateral.mintingMinCollateralRatio(agent, Collateral.Kind.POOL);
            _agents[i - _start] = AvailableAgentInfo.Data({
                agentVault: agentVault,
                ownerManagementAddress: agent.ownerManagementAddress,
                feeBIPS: agent.feeBIPS,
                mintingVaultCollateralRatioBIPS: agentCR,
                mintingPoolCollateralRatioBIPS: poolCR,
                freeCollateralLots: collateralData.freeCollateralLots(agent),
                status: Agents.getAgentStatus(agent)
            });
        }
    }
}