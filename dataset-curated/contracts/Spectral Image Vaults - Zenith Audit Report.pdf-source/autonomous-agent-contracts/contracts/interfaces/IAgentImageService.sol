// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IAgentImageService {
    struct ImageRequest {
        address user;
        uint256 amount;
        uint256 timestamp;
        bool fulfilled;
        bool refunded;
        string prompt;
    }

    struct AgentConfig {
        uint256 pricePerImage;
        string imageDescription;
        uint256 refundTimeLimit;
        bool isConfigured;
    }

    event AgentConfigured(address indexed agentToken, uint256 price, string description, uint256 refundTimeLimit);
    event ImageRequested(address indexed agentToken, address indexed user, bytes32 indexed requestId, uint256 amount);
    event ImageFulfilled(address indexed agentToken, bytes32 indexed requestId);
    event FeesWithdrawn(address indexed agentToken, uint256 amount);
    event RefundIssued(address indexed agentToken, bytes32 indexed requestId, uint256 amount);

    function configureAgent(
        address agentToken,
        uint256 pricePerImage,
        string memory imageDescription,
        uint256 refundTimeLimit
    ) external;

    function requestImage(address agentToken, string calldata prompt) external;

    function fulfillImage(address agentToken, bytes32 requestId) external;

    function requestRefund(address agentToken, bytes32 requestId) external;

    function withdrawFees(address agentToken) external;

    function getRequestDetails(
        address agentToken,
        bytes32 requestId
    ) external view returns (
        address user,
        uint256 amount,
        uint256 timestamp,
        bool fulfilled,
        bool refunded,
        string memory prompt
    );

    function agentConfigs(address agentToken) external view returns (AgentConfig memory);
    
    function accumulatedFees(address agentToken) external view returns (uint256);
} 