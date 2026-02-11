// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IOctoDistributor.sol";

contract MockOctoDistributor is IOctoDistributor {
    mapping(address => address) private _agentCreators;

    function setAgentCreator(address agentToken, address creator) external {
        _agentCreators[agentToken] = creator;
    }

    function agentCreators(address agentToken) external view override returns (address) {
        return _agentCreators[agentToken];
    }

    function transferHiringDistributions(
        HiringDistribution[] calldata /* distributions */,
        address /* agentToken */,
        uint256 /* totalSpec */,
        uint256 /* totalAgentToken */,
        uint256 /* totalUsdc */
    ) external override {}
} 