// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IAutonomousAgentDeployer.sol";
import "./interfaces/IOctoDistributor.sol";

contract AgentImageService is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct ImageRequest {
        address user;
        uint256 amount;
        uint256 width;
        uint256 height;
        uint256 timestamp;
        uint256 fulfilled;
        uint256 refunded;
        string prompt;
    }
    struct Agent {
        string agentName;
        string agentTicker;
        string agentDescription;
    }

    struct AgentConfig {
        uint256 pricePerImage;
        string imageDescription;
        uint256 refundTimeLimit; // Time in seconds after which refund is possible
        bool isConfigured;
    }

    enum Parameter {
        TREASURY_CUT
    }

    mapping(address => Agent) public agents;
    // Agent token address => Agent configuration
    mapping(address => AgentConfig) public agentConfigs;
    
    // Agent token address => accumulated fees ready for withdrawal
    mapping(address => uint256) public accumulatedFees;
    
    // Agent token address => amount locked in pending requests
    mapping(address => uint256) public pendingFees;
    
    // Agent token address => request hash => ImageRequest
    mapping(address => mapping(bytes32 => ImageRequest)) public imageRequests;
    
    // Agent token address => all request IDs for that agent
    mapping(address => bytes32[]) private agentRequestIds;
    
    // Agent token address => index => whether request has been processed (fulfilled or refunded)
    mapping(address => mapping(bytes32 => bool)) private requestProcessed;

    mapping(Parameter => uint256) public parameters;
    
    IAutonomousAgentDeployer public deployer;
    address public spectralTreasury;

    uint16 public version;

    uint256[50] __gap; // Reserved space

    event AgentConfigured(address indexed agentToken, uint256 price, string description, uint256 refundTimeLimit);
    event ImageRequested(address indexed agentToken, address indexed user, bytes32 indexed requestId, uint256 amount, uint256 width, uint256 height, string prompt);
    event ImageFulfilled(address indexed agentToken, bytes32 indexed requestId);
    event FeesWithdrawn(address indexed agentToken, uint256 amount);
    event RefundIssued(address indexed agentToken, bytes32 indexed requestId, uint256 amount);
    event ImageAgentDeployed(string agentName, string agentTicker, string agentDescription, address indexed owner, address indexed agentToken, uint256 minSpecAmount, uint256 tokenAmountOut);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _deployer, address _spectralTreasury, uint16 _treasuryCut) public initializer {
        require(_deployer != address(0), "AgentImageService: deployer cannot be zero address");
        require(_spectralTreasury != address(0), "AgentImageService: spectral treasury cannot be zero address");
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        parameters[Parameter.TREASURY_CUT] = _treasuryCut;
        spectralTreasury = _spectralTreasury;
        deployer = IAutonomousAgentDeployer(_deployer);
        version = 1;
    }

    modifier onlyAgentOwner(address agentToken) {
        require(IOctoDistributor(address(deployer.distributor())).agentCreators(agentToken) == msg.sender, "AgentImageService: : Not agent owner");
        _;
    }

    modifier onlyValidAgent(address agentToken) {
        require(deployer.isAgentToken(agentToken), "AgentImageService: : Invalid agent token");
        _;
    }

    function getAgentCreator(address agentToken) external view returns (address) {
        return IOctoDistributor(address(deployer.distributor())).agentCreators(agentToken);
    }

    function deployImageAgent(
        string memory agentName,
        string memory agentTicker,
        string memory agentDescription,
        address owner,
        uint256 minSpecAmount) external payable returns (address agentToken) {
        require(owner != address(0), "AgentImageService: Owner cannot be zero address");
        require(msg.value >= deployer.parameters(IAutonomousAgentDeployer.Parameter.DEPLOYMENT_COST_ETH), "AgentImageService: Incorrect ETH amount sent for deployment");
        // only transfer ETH to the this contract from the user in the next lines
        (agentToken) = deployer.deployAgentWithETH{value: msg.value}(agentName, agentTicker, minSpecAmount);
        agents[agentToken] = Agent({
            agentName: agentName,
            agentTicker: agentTicker,
            agentDescription: agentDescription
        });
        agentConfigs[agentToken] = AgentConfig({
            pricePerImage: 1 ether, // Default to 0 until configured
            imageDescription: "",
            refundTimeLimit: 1 days, // Default to 0 until configured
            isConfigured: true
        });
        uint256 tokenAmountOut = IERC20Upgradeable(agentToken).balanceOf(address(this));
        IERC20Upgradeable(agentToken).safeTransfer(owner, tokenAmountOut);
        emit ImageAgentDeployed(agentName, agentTicker, agentDescription, owner, agentToken, minSpecAmount, tokenAmountOut);

    }

    function _configureAgent(
        address agentToken,
        uint256 pricePerImage,
        string memory imageDescription,
        uint256 refundTimeLimit
    ) internal {
        require(pricePerImage > 0, "Price must be greater than 0");
        require(refundTimeLimit > 0, "Refund time limit must be greater than 0");
        
        agentConfigs[agentToken] = AgentConfig({
            pricePerImage: pricePerImage,
            imageDescription: imageDescription,
            refundTimeLimit: refundTimeLimit,
            isConfigured: true
        });
    }

    function configureAgent(
        address agentToken,
        uint256 pricePerImage,
        string memory imageDescription,
        uint256 refundTimeLimit
    ) external onlyAgentOwner(agentToken) onlyValidAgent(agentToken) {
        require(!agentConfigs[agentToken].isConfigured, "Agent already configured");
        _configureAgent(agentToken, pricePerImage, imageDescription, refundTimeLimit);

        emit AgentConfigured(agentToken, pricePerImage, imageDescription, refundTimeLimit);
    }

    function requestImage(
        address agentToken,
        string calldata prompt,
        uint256 width,
        uint256 height
    ) external nonReentrant onlyValidAgent(agentToken) {
        AgentConfig memory config = agentConfigs[agentToken];
        require(config.isConfigured, "Agent not configured");
        require(bytes(prompt).length > 0, "Prompt cannot be empty");
        require(width >= 64 && height >= 64, "Width and height must be greater or equal than 64");
        IERC20Upgradeable token = IERC20Upgradeable(agentToken);
        
        // Generate request ID from prompt and timestamp
        bytes32 requestId = keccak256(abi.encodePacked(prompt, block.timestamp, msg.sender));
        
        // Transfer tokens from user to this contract
        token.safeTransferFrom(msg.sender, address(this), config.pricePerImage);
        
        // Record the request
        imageRequests[agentToken][requestId] = ImageRequest({
            user: msg.sender,
            amount: config.pricePerImage,
            width: width,
            height: height,
            timestamp: block.timestamp,
            fulfilled: 0,
            refunded: 0,
            prompt: prompt
        });

        // Add to pending fees instead of accumulated
        pendingFees[agentToken] += config.pricePerImage;
        
        emit ImageRequested(agentToken, msg.sender, requestId, config.pricePerImage, width, height, prompt);
    }

    function fulfillImage(
        address agentToken,
        bytes32 requestId
    ) external onlyAgentOwner(agentToken) onlyValidAgent(agentToken) nonReentrant {
        ImageRequest storage request = imageRequests[agentToken][requestId];
        require(request.fulfilled == 0 && request.refunded == 0, "Request already processed");
        require(request.user != address(0), "Request does not exist");
        
        request.fulfilled = block.timestamp;
        
        // Move fee from pending to accumulated
        pendingFees[agentToken] -= request.amount;
        uint256 treasuryCut = (request.amount * parameters[Parameter.TREASURY_CUT]) / 10000;
        accumulatedFees[agentToken] += (request.amount - treasuryCut);
        IERC20Upgradeable(agentToken).safeTransfer(spectralTreasury, (request.amount * parameters[Parameter.TREASURY_CUT]) / 10000);
        
        emit ImageFulfilled(agentToken, requestId);
    }

    function requestRefund(
        address agentToken,
        bytes32 requestId
    ) external nonReentrant {
        ImageRequest storage request = imageRequests[agentToken][requestId];
        AgentConfig memory config = agentConfigs[agentToken];
        
        require(request.user == msg.sender, "Not request owner");
        require(request.fulfilled == 0 && request.refunded == 0, "Request already processed");
        require(
            block.timestamp >= request.timestamp + config.refundTimeLimit,
            "Refund time limit not reached"
        );

        request.refunded = block.timestamp;
        
        // Remove from pending fees
        pendingFees[agentToken] -= request.amount;
        
        // Transfer tokens back to user
        IERC20Upgradeable(agentToken).safeTransfer(msg.sender, request.amount);
        
        emit RefundIssued(agentToken, requestId, request.amount);
    }

    function withdrawFees(address agentToken) external onlyAgentOwner(agentToken) nonReentrant {
        uint256 amount = accumulatedFees[agentToken];
        require(amount > 0, "No fees to withdraw");
        
        accumulatedFees[agentToken] = 0;
        IERC20Upgradeable(agentToken).safeTransfer(msg.sender, amount);
        
        emit FeesWithdrawn(agentToken, amount);
    }

    function getRequestDetails(
        address agentToken,
        bytes32 requestId
    ) external view returns (
        address user,
        uint256 amount,
        uint256 timestamp,
        uint256 fulfilled,
        uint256 refunded,
        string memory prompt
    ) {
        ImageRequest memory request = imageRequests[agentToken][requestId];
        return (
            request.user,
            request.amount,
            request.timestamp,
            request.fulfilled,
            request.refunded,
            request.prompt
        );
    }

    // Helper function to check if an agent has any pending fees
    function getPendingFees(address agentToken) public view returns (uint256) {
        return pendingFees[agentToken];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        require(newImplementation != address(0), "ZERO_ADDRESS");
        ++version;
    }
} 