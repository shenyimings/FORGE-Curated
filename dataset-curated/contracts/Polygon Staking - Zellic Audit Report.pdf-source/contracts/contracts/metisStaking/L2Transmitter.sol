// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

import "./interfaces/IL2Strategy.sol";
import "./interfaces/IL2StandardBridge.sol";
import "./interfaces/IL2StandardBridgeGasOracle.sol";
import "../core/interfaces/IWithdrawalPool.sol";
import "../core/ccip/base/CCIPReceiverUpgradeable.sol";

/**
 * @title L2 Transmitter
 * @notice Sends and receives METIS transfers and CCIP messages to/from L1
 */
contract L2Transmitter is UUPSUpgradeable, OwnableUpgradeable, CCIPReceiverUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // address of METIS token
    IERC20Upgradeable public metisToken;

    // address of Withdrawal Pool
    IWithdrawalPool public withdrawalPool;

    // address of L2 Strategy
    IL2Strategy public l2Strategy;
    // address of Metis bridge
    IL2StandardBridge public l2StandardBridge;
    // address of OVM_GasPriceOracle
    IL2StandardBridgeGasOracle public l2StandardBridgeGasOracle;
    // address of L1 Transmitter on L1
    address public l1Transmitter;

    // must exceed this amount of queued tokens to deposit to L1
    uint256 public minDepositThreshold;

    // min amount of time between calls to executeUpdate
    uint64 public minTimeBetweenUpdates;
    // time of last call to executeUpdate
    uint64 public timeOfLastUpdate;

    // CCIP chain selector for L1
    uint64 public l1ChainSelector;
    // extra args for outgoing CCIP messages
    bytes public extraArgs;

    event CCIPMessageSent(bytes32 indexed messageId);
    event CCIPMessageReceived(bytes32 indexed messageId);

    error InvalidTransfer();
    error InvalidSourceChain();
    error InvalidSender();
    error CannotExecuteWithdrawals();
    error InsufficientTimeElapsed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param _metisToken address of the METIS token
     * @param _l2Strategy address of L2 Strategy
     * @param _l2StandardBridge address of the L2 standard bridge
     * @param _l2StandardBridgeGasOracle address of OVM_GasPriceOracle
     * @param _l1Transmitter address of L1 Transmitter on L1
     * @param _withdrawalPool address of Withdrawal Pool
     * @param _minDepositThreshold must exceed this amount of queued tokens to deposit to L1
     * @param _minTimeBetweenUpdates min amount of time between calls to executeUpdate
     * @param _router address of CCIP router
     * @param _l1ChainSelector CCIP selector for L1
     * @param _extraArgs extra args for CCIP messaging
     **/
    function initialize(
        address _metisToken,
        address _l2Strategy,
        address _l2StandardBridge,
        address _l2StandardBridgeGasOracle,
        address _l1Transmitter,
        address _withdrawalPool,
        uint256 _minDepositThreshold,
        uint64 _minTimeBetweenUpdates,
        address _router,
        uint64 _l1ChainSelector,
        bytes memory _extraArgs
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __CCIPReceiverUpgradeable_init(_router);

        metisToken = IERC20Upgradeable(_metisToken);
        l2Strategy = IL2Strategy(_l2Strategy);
        metisToken.safeApprove(_l2Strategy, type(uint256).max);
        l2StandardBridge = IL2StandardBridge(_l2StandardBridge);
        l2StandardBridgeGasOracle = IL2StandardBridgeGasOracle(_l2StandardBridgeGasOracle);
        l1Transmitter = _l1Transmitter;
        withdrawalPool = IWithdrawalPool(_withdrawalPool);
        minDepositThreshold = _minDepositThreshold;
        minTimeBetweenUpdates = _minTimeBetweenUpdates;
        l1ChainSelector = _l1ChainSelector;
        extraArgs = _extraArgs;
    }

    /**
     * @notice Returns the total available tokens
     * @return available tokens
     **/
    function getAvailableTokens() public view returns (uint256) {
        return metisToken.balanceOf(address(this));
    }

    /**
     * @notice Returns the total tokens in transit from L1
     * @return outstanding tokens
     **/
    function getOutstandingTokens() public view returns (uint256) {
        return l2Strategy.tokensInTransitFromL1();
    }

    /**
     * @notice Transfers tokens to the L2 strategy
     * @dev includes claimed rewards and withdrawn tokens
     **/
    function depositTokensFromL1() public {
        uint256 toTransfer = MathUpgradeable.min(getAvailableTokens(), getOutstandingTokens());
        if (toTransfer == 0) revert InvalidTransfer();

        l2Strategy.handleIncomingTokensFromL1(toTransfer);
    }

    /**
     * @notice Executes withdrawals queued in the Withdrawal Pool
     **/
    function executeQueuedWithdrawals() public {
        (bool upkeepNeeded, ) = withdrawalPool.checkUpkeep("");
        if (!upkeepNeeded) return;

        uint256 queuedTokens = l2Strategy.getTotalQueuedTokens();
        uint256 queuedWithdrawals = withdrawalPool.getTotalQueuedWithdrawals();
        uint256 toWithdraw = MathUpgradeable.min(queuedTokens, queuedWithdrawals);

        if (toWithdraw == 0) revert CannotExecuteWithdrawals();

        bytes[] memory args = new bytes[](1);
        args[0] = "0x";
        withdrawalPool.performUpkeep(abi.encode(args));
    }

    /**
     * @notice Returns the maximum fee for a call to executeUpdate
     * @return fee in native token
     **/
    function getExecuteUpdateFee() external view returns (uint256) {
        uint256 bridgeFee = l2StandardBridgeGasOracle.minErc20BridgeCost();

        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(type(uint256).max);
        uint256 ccipFee = IRouterClient(getRouter()).getFee(l1ChainSelector, evm2AnyMessage);

        return bridgeFee + ccipFee;
    }

    /**
     * @notice Deposits any new tokens received from L1 into L2 Strategy, executes queued withdrawals,
     * then deposits remaining tokens to L1 or withdraws tokens from L1 depending on what's needed
     * @dev should be called as soon as soon minTimeBetweenUpdates has elapsed
     * @dev sender should ensure a sufficient msg.value to pay for any fees that may be incurred
     * (unused funds will be returned to sender)
     **/
    function executeUpdate() external payable {
        if (block.timestamp < timeOfLastUpdate + minTimeBetweenUpdates) {
            revert InsufficientTimeElapsed();
        }
        if (getAvailableTokens() != 0 && getOutstandingTokens() != 0) depositTokensFromL1();

        uint256 queuedTokens = l2Strategy.getTotalQueuedTokens();
        uint256 queuedWithdrawals = withdrawalPool.getTotalQueuedWithdrawals();

        if (queuedTokens != 0 && queuedWithdrawals != 0) {
            executeQueuedWithdrawals();
            queuedTokens = l2Strategy.getTotalQueuedTokens();
            queuedWithdrawals = withdrawalPool.getTotalQueuedWithdrawals();
        }

        if (queuedTokens > minDepositThreshold) {
            uint256 fee = l2StandardBridgeGasOracle.minErc20BridgeCost();
            l2Strategy.handleOutgoingTokensToL1(queuedTokens);
            l2StandardBridge.withdrawMetisTo{value: fee}(l1Transmitter, queuedTokens, 0, "");
        }

        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            queuedWithdrawals - MathUpgradeable.min(getOutstandingTokens(), queuedWithdrawals)
        );
        uint256 fee = IRouterClient(getRouter()).getFee(l1ChainSelector, evm2AnyMessage);
        bytes32 messageId = IRouterClient(getRouter()).ccipSend{value: fee}(
            l1ChainSelector,
            evm2AnyMessage
        );
        emit CCIPMessageSent(messageId);

        timeOfLastUpdate = uint64(block.timestamp);

        // return any unused fees to sender
        if (address(this).balance != 0) {
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    /**
     * @notice Sets the min amount of time between calls to executeUpdate
     * @param _minTimeBetweenUpdates min time in seconds
     **/
    function setMinTimeBetweenUpdates(uint64 _minTimeBetweenUpdates) external onlyOwner {
        minTimeBetweenUpdates = _minTimeBetweenUpdates;
    }

    /**
     * @notice Sets the amount of queued tokens that must be exceeded to deposit to L1
     * @param _minDepositThreshold min amount of tokens
     **/
    function setMinDepositThreshold(uint256 _minDepositThreshold) external onlyOwner {
        minDepositThreshold = _minDepositThreshold;
    }

    /**
     * @notice Sets the address of the L1 Transmitter on L1
     * @param _l1Transmitter address of L1 Transmitter
     **/
    function setL1Transmitter(address _l1Transmitter) external onlyOwner {
        l1Transmitter = _l1Transmitter;
    }

    /**
     * @notice Sets extra args for CCIP withdrawal messages
     * @param _extraArgs extra args
     **/
    function setExtraArgs(bytes calldata _extraArgs) external onlyOwner {
        extraArgs = _extraArgs;
    }

    /**
     * @notice Handles an incoming CCIP update message from the L1 Transmitter on L1
     * @param _message CCIP message
     **/
    function _ccipReceive(Client.Any2EVMMessage memory _message) internal override {
        if (_message.sourceChainSelector != l1ChainSelector) revert InvalidSourceChain();
        if (abi.decode(_message.sender, (address)) != l1Transmitter) revert InvalidSender();

        (
            uint256 totalDeposits,
            uint256 tokensInTransitFromL1,
            uint256 tokensReceivedAtL1,
            address[] memory opRewardReceivers,
            uint256[] memory opRewardAmounts
        ) = abi.decode(_message.data, (uint256, uint256, uint256, address[], uint256[]));

        l2Strategy.handleUpdateFromL1(
            totalDeposits,
            tokensInTransitFromL1,
            tokensReceivedAtL1,
            opRewardReceivers,
            opRewardAmounts
        );

        emit CCIPMessageReceived(_message.messageId);
    }

    /**
     * @notice Builds a CCIP withdrawal message
     * @param _amountToWithdraw amount of tokens to withdraw
     **/
    function _buildCCIPMessage(
        uint256 _amountToWithdraw
    ) private view returns (Client.EVM2AnyMessage memory) {
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(l1Transmitter),
                data: abi.encode(_amountToWithdraw),
                tokenAmounts: new Client.EVMTokenAmount[](0),
                extraArgs: extraArgs,
                feeToken: address(0)
            });
    }

    /**
     * @dev Checks authorization for contract upgrades
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
