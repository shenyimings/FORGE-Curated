// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOctoDistributor {
    struct HiringDistribution {
        bytes32 recipientAnsNode;
        uint256 specAmount;
        uint256 agentTokenAmount;
        uint256 usdcAmount;
    }

    function setAgentCreator(address agentToken, address creator)
        external;

    function transferHiringDistributions(
        HiringDistribution[] calldata distributions,
        address agentToken,
        uint256 totalSpec,
        uint256 totalAgentToken,
        uint256 totalUsdc
    ) external;
}