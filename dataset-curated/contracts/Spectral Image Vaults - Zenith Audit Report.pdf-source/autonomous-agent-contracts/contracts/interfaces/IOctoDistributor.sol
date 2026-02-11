// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOctoDistributor {
    error AnsNodeMustResolveToAddress(bytes32 node);
    struct HiringDistribution {
        bytes32 recipientAnsNode;
        uint256 specAmount;
        uint256 agentTokenAmount;
        uint256 usdcAmount;
    }
    struct HiringDistributionByAddress {
        address recipient;
        uint256 specAmount;
        uint256 agentTokenAmount;
        uint256 usdcAmount;
    }

    struct TradingDistribution {
        bytes32 recipientAnsNode;
        uint256 amount;
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

    function agentCreators(address agentToken)
        external
        view
        returns (address);
}