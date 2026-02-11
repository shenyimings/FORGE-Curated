// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IWrappedLST.sol";
import "./base/CCIPReceiver.sol";

/**
 * @title Wrapped token bridge
 * @notice Handles CCIP transfers with a wrapped token
 * @dev This contract can perform 2 functions:
 * - can wrap tokens and initiate a CCIP transfer of the wrapped tokens to a destination chain
 * - can receive a CCIP transfer of wrapped tokens, unwrap them, and send them to the receiver
 */
contract WrappedTokenBridge is CCIPReceiver {
    using SafeERC20 for IERC20;

    IERC20 linkToken;

    IERC20 token;
    IWrappedLST wrappedToken;

    event TokensTransferred(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed sender,
        address receiver,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );
    event TokensReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address indexed sender,
        address receiver,
        uint256 tokenAmount
    );

    error InvalidSender();
    error InvalidValue();
    error InsufficientFee();
    error TransferFailed();
    error FeeExceedsLimit();
    error InvalidMessage();
    error InvalidMsgValue();
    error InvalidReceiver();

    /**
     * @notice Initializes the contract
     * @param _router address of the CCIP router
     * @param _linkToken address of the LINK token
     * @param _token address of the unwrapped token
     * @param _wrappedToken address of the wrapped token
     **/
    constructor(
        address _router,
        address _linkToken,
        address _token,
        address _wrappedToken
    ) CCIPReceiver(_router) {
        linkToken = IERC20(_linkToken);

        token = IERC20(_token);
        wrappedToken = IWrappedLST(_wrappedToken);

        linkToken.approve(_router, type(uint256).max);
        token.approve(_wrappedToken, type(uint256).max);
        wrappedToken.approve(_router, type(uint256).max);
    }

    /**
     * @notice ERC677 implementation to receive a token transfer to be wrapped and sent to a destination chain
     * @param _sender address of sender
     * @param _value amount of tokens transferred
     * @param _calldata encoded calldata consisting of destinationChainSelector (uint64), receiver (address),
     * maxLINKFee (uint256)
     **/
    function onTokenTransfer(address _sender, uint256 _value, bytes calldata _calldata) external {
        if (msg.sender != address(token)) revert InvalidSender();
        if (_value == 0) revert InvalidValue();

        (uint64 destinationChainSelector, address receiver, uint256 maxLINKFee) = abi.decode(
            _calldata,
            (uint64, address, uint256)
        );
        _transferTokens(destinationChainSelector, _sender, receiver, _value, false, maxLINKFee);
    }

    /**
     * @notice Wraps and transfers tokens to a destination chain
     * @param _destinationChainSelector id of destination chain
     * @param _receiver address to receive tokens on destination chain
     * @param _amount amount of tokens to transfer
     * @param _payNative whether fee should be paid natively or with LINK
     * @param _maxLINKFee call will revert if LINK fee exceeds this value
     **/
    function transferTokens(
        uint64 _destinationChainSelector,
        address _receiver,
        uint256 _amount,
        bool _payNative,
        uint256 _maxLINKFee
    ) external payable returns (bytes32 messageId) {
        if (_payNative == false && msg.value != 0) revert InvalidMsgValue();

        token.safeTransferFrom(msg.sender, address(this), _amount);
        return
            _transferTokens(
                _destinationChainSelector,
                msg.sender,
                _receiver,
                _amount,
                _payNative,
                _maxLINKFee
            );
    }

    /**
     * @notice Returns the current fee for a token transfer
     * @param _destinationChainSelector id of destination chain
     * @param _amount amount of tokens to transfer
     * @param _payNative whether fee should be paid natively or with LINK
     * @return fee current fee
     **/
    function getFee(
        uint64 _destinationChainSelector,
        uint256 _amount,
        bool _payNative
    ) external view returns (uint256) {
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            address(this),
            _amount,
            _payNative ? address(0) : address(linkToken)
        );

        return IRouterClient(this.getRouter()).getFee(_destinationChainSelector, evm2AnyMessage);
    }

    /**
     * @notice Withdraws tokens held by this contract
     * @param _tokens list of tokens to withdraw
     * @param _amounts list of corresponding amounts to withdraw
     * @param _receiver address to receive tokens
     **/
    function recoverTokens(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        address _receiver
    ) external onlyOwner {
        if (_receiver == address(0)) revert InvalidReceiver();

        for (uint256 i = 0; i < _tokens.length; ++i) {
            IERC20(_tokens[i]).safeTransfer(_receiver, _amounts[i]);
        }
    }

    /**
     * @notice Sets the CCIP router
     * @param _router router address
     **/
    function setRouter(address _router) external override onlyOwner {
        if (_router == address(0)) revert InvalidRouter(address(0));

        address curRouter = getRouter();
        linkToken.approve(curRouter, 0);
        wrappedToken.approve(curRouter, 0);

        linkToken.approve(_router, type(uint256).max);
        wrappedToken.approve(_router, type(uint256).max);
        i_router = _router;
    }

    /**
     * @notice Wraps and transfers tokens to a destination chain
     * @param _destinationChainSelector id of destination chain
     * @param _sender address of token sender
     * @param _receiver address to receive tokens on destination chain
     * @param _amount amount of tokens to transfer
     * @param _payNative whether fee should be paid natively or with LINK
     * @param _maxLINKFee call will revert if LINK fee exceeds this value
     **/
    function _transferTokens(
        uint64 _destinationChainSelector,
        address _sender,
        address _receiver,
        uint256 _amount,
        bool _payNative,
        uint256 _maxLINKFee
    ) internal returns (bytes32 messageId) {
        uint256 preWrapBalance = wrappedToken.balanceOf(address(this));
        wrappedToken.wrap(_amount);
        uint256 amountToTransfer = wrappedToken.balanceOf(address(this)) - preWrapBalance;

        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            amountToTransfer,
            _payNative ? address(0) : address(linkToken)
        );

        IRouterClient router = IRouterClient(this.getRouter());
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (_payNative) {
            if (fees > msg.value) revert InsufficientFee();
            messageId = router.ccipSend{value: fees}(_destinationChainSelector, evm2AnyMessage);
            if (fees < msg.value) {
                (bool success, ) = _sender.call{value: msg.value - fees}("");
                if (!success) revert TransferFailed();
            }
        } else {
            if (fees > _maxLINKFee) revert FeeExceedsLimit();
            linkToken.safeTransferFrom(_sender, address(this), fees);
            messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);
        }

        emit TokensTransferred(
            messageId,
            _destinationChainSelector,
            _sender,
            _receiver,
            amountToTransfer,
            _payNative ? address(0) : address(linkToken),
            fees
        );
        return messageId;
    }

    /**
     * @notice Builds a CCIP message
     * @param _receiver address to receive tokens on destination chain
     * @param _amount amount of tokens to transfer
     * @param _feeTokenAddress address of token that fees will be paid in
     **/
    function _buildCCIPMessage(
        address _receiver,
        uint256 _amount,
        address _feeTokenAddress
    ) internal view returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: address(wrappedToken),
            amount: _amount
        });
        tokenAmounts[0] = tokenAmount;

        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})),
            feeToken: _feeTokenAddress
        });

        return evm2AnyMessage;
    }

    /**
     * @notice Processes a received message
     * @param _message CCIP message
     **/
    function _ccipReceive(Client.Any2EVMMessage memory _message) internal override {
        if (_message.destTokenAmounts.length != 1) revert InvalidMessage();

        address tokenAddress = _message.destTokenAmounts[0].token;
        uint256 tokenAmount = _message.destTokenAmounts[0].amount;
        address receiver = abi.decode(_message.data, (address));

        if (tokenAddress != address(wrappedToken) || receiver == address(0))
            revert InvalidMessage();

        uint256 preUnwrapBalance = token.balanceOf(address(this));
        wrappedToken.unwrap(tokenAmount);
        uint256 amountToTransfer = token.balanceOf(address(this)) - preUnwrapBalance;
        token.safeTransfer(receiver, amountToTransfer);

        emit TokensReceived(
            _message.messageId,
            _message.sourceChainSelector,
            abi.decode(_message.sender, (address)),
            receiver,
            tokenAmount
        );
    }
}
