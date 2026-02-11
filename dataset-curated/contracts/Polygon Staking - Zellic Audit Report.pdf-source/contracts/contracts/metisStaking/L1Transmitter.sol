// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

import "./interfaces/IL1Strategy.sol";
import "./interfaces/IL1StandardBridge.sol";
import "./interfaces/IL1StandardBridgeGasOracle.sol";
import "../core/ccip/base/CCIPReceiverUpgradeable.sol";

/**
 * @title L1 Transmitter
 * @notice Sends and receives METIS transfers and CCIP messages to/from L2
 */
contract L1Transmitter is UUPSUpgradeable, OwnableUpgradeable, CCIPReceiverUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // address of METIS token
    IERC20Upgradeable public metisToken;

    // address authorized to deposit queued tokens
    address public depositController;

    // address of L1 Strategy
    IL1Strategy public l1Strategy;
    // address of L2 Transmitter on L2
    address public l2Transmitter;

    // address of Metis bridge
    IL1StandardBridge public l1StandardBridge;
    // address of MVM_DiscountOracle
    IL1StandardBridgeGasOracle public l1StandardBridgeGasOracle;
    // chain id of L2
    uint256 public l2ChainId;
    // address of METIS token on L2
    address public l2MetisToken;

    // CCIP chain selector for L2
    uint64 public l2ChainSelector;
    // extra args for outgoing CCIP messages
    bytes public extraArgs;

    // total new deposits since the last update
    uint256 public depositsSinceLastUpdate;
    // total queued withdrawals since the last update
    uint256 public queuedWithdrawals;
    // must exceed this amount of withdrawable tokens to withdraw to L2
    uint256 public minWithdrawalThreshold;

    event CCIPMessageSent(bytes32 indexed messageId);
    event CCIPMessageReceived(bytes32 indexed messageId);

    error NoTokensAvailable();
    error InvalidSourceChain();
    error InvalidSender();
    error SenderNotAuthorized();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param _metisToken address of the METIS token
     * @param _depositController address authorized to deposit queued tokens
     * @param _l1Strategy address of L1 Strategy
     * @param _l1StandardBridge address of the L1 standard bridge
     * @param _l1StandardBridgeGasOracle address of MVM_DiscountOracle
     * @param _l2Transmitter address of L2 Transmitter on L2
     * @param _l2ChainId chain id of L2
     * @param _l2MetisToken address of METIS token on L2
     * @param _minWithdrawalThreshold must exceed this amount of withdrawable tokens to withdraw to L2
     * @param _router address of CCIP router
     * @param _l2ChainSelector CCIP chain selector for L2
     * @param _extraArgs extra args for outgoing CCIP messages
     **/
    function initialize(
        address _metisToken,
        address _depositController,
        address _l1Strategy,
        address _l1StandardBridge,
        address _l1StandardBridgeGasOracle,
        address _l2Transmitter,
        uint256 _l2ChainId,
        address _l2MetisToken,
        uint256 _minWithdrawalThreshold,
        address _router,
        uint64 _l2ChainSelector,
        bytes memory _extraArgs
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __CCIPReceiverUpgradeable_init(_router);

        metisToken = IERC20Upgradeable(_metisToken);
        depositController = _depositController;
        l1Strategy = IL1Strategy(_l1Strategy);
        metisToken.safeApprove(_l1Strategy, type(uint256).max);
        l1StandardBridge = IL1StandardBridge(_l1StandardBridge);
        l1StandardBridgeGasOracle = IL1StandardBridgeGasOracle(_l1StandardBridgeGasOracle);
        l2Transmitter = _l2Transmitter;
        l2ChainId = _l2ChainId;
        l2MetisToken = _l2MetisToken;
        minWithdrawalThreshold = _minWithdrawalThreshold;
        l2ChainSelector = _l2ChainSelector;
        extraArgs = _extraArgs;
    }

    /**
     * @notice Reverts if sender is not deposit controller
     **/
    modifier onlyDepositController() {
        if (msg.sender != depositController) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Returns the total available tokens for deposit into L1 Strategy
     * @return available tokens
     **/
    function getAvailableTokens() public view returns (uint256) {
        return metisToken.balanceOf(address(this));
    }

    /**
     * @notice Deposits all newly received tokens into L1 Strategy
     * @dev should be called whenever there are available tokens
     **/
    function depositTokensFromL2() public {
        uint256 availableTokens = getAvailableTokens();

        if (availableTokens == 0) revert NoTokensAvailable();

        l1Strategy.deposit(availableTokens);
        depositsSinceLastUpdate += availableTokens;
    }

    /**
     * @notice Deposits queued tokens into L1 Strategy vaults
     * @dev called by deposit controller bot once certain conditions are met as defined offchain
     * @param _vaults list of vaults to deposit into
     * @param _amounts amount to deposit into each vault
     */
    function depositQueuedTokens(
        uint256[] calldata _vaults,
        uint256[] calldata _amounts
    ) external onlyDepositController {
        if (getAvailableTokens() != 0) {
            depositTokensFromL2();
        }
        l1Strategy.depositQueuedTokens(_vaults, _amounts);
    }

    /**
     * @notice Receives ETH transfers
     * @dev ETH must be deposited to pay for fees
     */
    receive() external payable {}

    /**
     * @notice Withdraws ETH sitting in the contract
     * @param _amount amount to withdraw
     */
    function withdrawETH(uint256 _amount) external onlyOwner {
        payable(msg.sender).transfer(_amount);
    }

    /**
     * @notice Sets the amount of withdrawable tokens that must be exceeded to withdraw to L2
     * @param _minWithdrawalThreshold min amount of tokens
     **/
    function setMinWithdrawalThreshold(uint256 _minWithdrawalThreshold) external onlyOwner {
        minWithdrawalThreshold = _minWithdrawalThreshold;
    }

    /**
     * @notice Sets the address authorized to deposit queued tokens
     * @param _depositController address of deposit controller
     */
    function setDepositController(address _depositController) external onlyOwner {
        depositController = _depositController;
    }

    /**
     * @notice Sets the address of the L2 Transmitter on L2
     * @param _l2Transmitter address of L2 Transmitter
     **/
    function setL2Transmitter(address _l2Transmitter) external onlyOwner {
        l2Transmitter = _l2Transmitter;
    }

    /**
     * @notice Sets extra args for outgoing CCIP update messages
     * @param _extraArgs extra args
     **/
    function setExtraArgs(bytes calldata _extraArgs) external onlyOwner {
        extraArgs = _extraArgs;
    }

    /**
     * @notice Updates accounting, executes queued withdrawals, and sends a CCIP message to L2 containing
     * updated data for L1 Strategy
     **/
    function _executeUpdate() private {
        // deposit any available tokens into L1 Strategy
        if (getAvailableTokens() != 0) {
            depositTokensFromL2();
        }

        uint256 l2Gas = l1StandardBridgeGasOracle.getMinL2Gas();
        uint256 l2Fee = l2Gas * l1StandardBridgeGasOracle.getDiscount();

        // execute queued withdrawals
        uint256 canWithdraw = l1Strategy.canWithdraw();
        uint256 toWithdraw = queuedWithdrawals > canWithdraw ? canWithdraw : queuedWithdrawals;
        uint256 withdrawn;
        if (toWithdraw > minWithdrawalThreshold) {
            l1Strategy.withdraw(toWithdraw);
            withdrawn = toWithdraw;

            metisToken.safeApprove(address(l1StandardBridge), toWithdraw);

            l1StandardBridge.depositERC20ToByChainId{value: l2Fee}(
                l2ChainId,
                address(metisToken),
                l2MetisToken,
                l2Transmitter,
                toWithdraw,
                uint32(l2Gas),
                ""
            );
        }

        (
            uint256 totalDeposits,
            uint256 claimedRewards,
            address[] memory opRewardReceivers,
            uint256[] memory opRewardAmounts
        ) = l1Strategy.updateDeposits{value: address(this).balance}(uint32(l2Gas), l2Fee);

        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPUpdateMessage(
            totalDeposits,
            claimedRewards + withdrawn,
            depositsSinceLastUpdate,
            opRewardReceivers,
            opRewardAmounts
        );

        uint256 fee = IRouterClient(getRouter()).getFee(l2ChainSelector, evm2AnyMessage);
        bytes32 messageId = IRouterClient(getRouter()).ccipSend{value: fee}(
            l2ChainSelector,
            evm2AnyMessage
        );

        depositsSinceLastUpdate = 0;
        queuedWithdrawals -= toWithdraw;

        emit CCIPMessageSent(messageId);
    }

    /**
     * @notice Handles an incoming CCIP update message sent from the L2 Transmitter
     * @param _message CCIP message
     **/
    function _ccipReceive(Client.Any2EVMMessage memory _message) internal override {
        if (_message.sourceChainSelector != l2ChainSelector) revert InvalidSourceChain();
        if (abi.decode(_message.sender, (address)) != l2Transmitter) revert InvalidSender();

        uint256 toWithdraw = abi.decode(_message.data, (uint256));
        queuedWithdrawals = toWithdraw;

        emit CCIPMessageReceived(_message.messageId);

        _executeUpdate();
    }

    /**
     * @notice Builds a CCIP update message
     * @param _totalDeposits total deposits in L1 Strategy
     * @param _tokensInTransitToL2 total tokens sent to L2 since the last update
     * @param _tokensReceivedFromL2 total new tokens received since the last update
     * @param _opRewardReceivers list of operator rewards receiver addresses
     * @param _opRewardAmounts list of operator reward amounts corresponding to each receiver
     * @return outgoing CCIP message
     **/
    function _buildCCIPUpdateMessage(
        uint256 _totalDeposits,
        uint256 _tokensInTransitToL2,
        uint256 _tokensReceivedFromL2,
        address[] memory _opRewardReceivers,
        uint256[] memory _opRewardAmounts
    ) private view returns (Client.EVM2AnyMessage memory) {
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(l2Transmitter),
                data: abi.encode(
                    _totalDeposits,
                    _tokensInTransitToL2,
                    _tokensReceivedFromL2,
                    _opRewardReceivers,
                    _opRewardAmounts
                ),
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
