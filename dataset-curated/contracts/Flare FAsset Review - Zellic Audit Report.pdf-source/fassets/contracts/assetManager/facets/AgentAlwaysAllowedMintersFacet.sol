// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {Agent} from "../../assetManager/library/data/Agent.sol";


contract AgentAlwaysAllowedMintersFacet is AssetManagerBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    function addAlwaysAllowedMinterForAgent(
        address _agentVault,
        address _minter
    )
        external
        onlyAgentVaultOwner(_agentVault)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        agent.alwaysAllowedMinters.add(_minter);
    }

    function removeAlwaysAllowedMinterForAgent(
        address _agentVault,
        address _minter
    )
        external
        onlyAgentVaultOwner(_agentVault)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        agent.alwaysAllowedMinters.remove(_minter);
    }

    function alwaysAllowedMintersForAgent(
        address _agentVault
    )
        external view
        returns (address[] memory)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        return agent.alwaysAllowedMinters.values();
    }
}
