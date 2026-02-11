/// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { OApp, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { IOAppMsgInspector } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppMsgInspector.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import { OAppPreCrimeSimulator } from "@layerzerolabs/lz-evm-oapp-v2/contracts/precrime/OAppPreCrimeSimulator.sol";

import {
    IOFT, SendParam, OFTLimit, OFTReceipt, OFTFeeDetail, MessagingReceipt, MessagingFee
} from "./interfaces/IOFT.sol";
import { OFTMsgCodec } from "./libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "./libs/OFTComposeMsgCodec.sol";

/// @title OFTCore
/// @author Forked from
/// https://github.com/LayerZero-Labs/LayerZero-v2/blob/main/packages/layerzero-v2/evm/oapp/contracts/oft/OFTCore.sol
/// @dev Modifications made by Cooper Labs. Removed sharedDecimals/decimalConversionRate related code.
/// @dev Abstract contract for the OftChain (OFT) token.
abstract contract OFTCore is IOFT, OApp, OAppPreCrimeSimulator, OAppOptionsType3 {
    using OFTMsgCodec for bytes;
    using OFTMsgCodec for bytes32;

    /// @notice Msg types that are used to identify the various OFT operations.
    /// @dev This can be extended in child contracts for non-default oft operations
    /// @dev These values are used in things like combineOptions() in OAppOptionsType3.sol.
    uint16 public constant SEND = 1;
    uint16 public constant SEND_AND_CALL = 2;

    /// Address of an optional contract to inspect both 'message' and 'options'
    address public msgInspector;

    event MsgInspectorSet(address inspector);

    /// @dev Constructor.
    /// @param _endpoint The address of the LayerZero endpoint.
    /// @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
    constructor(address _endpoint, address _delegate) OApp(_endpoint, _delegate) { }

    /// @notice Retrieves interfaceID and the version of the OFT.
    /// @return interfaceId The interface ID.
    /// @return version The version.
    /// @dev interfaceId: This specific interface ID is '0x18fb6cf8'.
    /// @dev version: Indicates a cross-chain compatible msg encoding with other OFTs.
    /// @dev If a new feature is added to the OFT cross-chain msg encoding, the version will be incremented.
    /// ie. localOFT version(x,1) CAN send messages to remoteOFT version(x,1)
    function oftVersion() external pure virtual returns (bytes4 interfaceId, uint64 version) {
        return (type(IOFT).interfaceId, 1);
    }

    /// @dev Sets the message inspector address for the OFT.
    /// @param _msgInspector The address of the message inspector.
    /// @dev This is an optional contract that can be used to inspect both 'message' and 'options'.
    /// @dev Set it to address(0) to disable it, or set it to a contract address to enable it.
    function setMsgInspector(address _msgInspector) public virtual onlyOwner {
        msgInspector = _msgInspector;
        emit MsgInspectorSet(_msgInspector);
    }

    /// @notice Provides a quote for OFT-related operations.
    /// @param _sendParam The parameters for the send operation.
    /// @return oftLimit The OFT limit information.
    /// @return oftFeeDetails The details of OFT fees.
    /// @return oftReceipt The OFT receipt information.
    function quoteOFT(SendParam calldata _sendParam)
        external
        view
        virtual
        returns (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt)
    {
        uint256 minAmount = 0;
        /// Unused in the default implementation.
        uint256 maxAmount = type(uint256).max;
        /// Unused in the default implementation.
        oftLimit = OFTLimit(minAmount, maxAmount);

        /// Unused in the default implementation; reserved for future complex fee details.
        oftFeeDetails = new OFTFeeDetail[](0);

        /// @dev This is the same as the send() operation, but without the actual send.
        /// - amountSent is the amount that would be sent from the sender.
        /// - amountReceived is the amount that will be credited to the recipient on the remote OFT
        /// instance.
        /// @dev The amountSent MIGHT not equal the amount the user actually receives. HOWEVER, the default does.
        (uint256 amountSent, uint256 amountReceived) =
            _debitView(_sendParam.amount, _sendParam.minAmount, _sendParam.dstEid);
        oftReceipt = OFTReceipt(amountSent, amountReceived);
    }

    /// @notice Provides a quote for the send() operation.
    /// @param _sendParam The parameters for the send() operation.
    /// @param _payInLzToken Flag indicating whether the caller is paying in the LZ token.
    /// @return msgFee The calculated LayerZero messaging fee from the send() operation.
    /// @dev MessagingFee: LayerZero msg fee
    ///  - nativeFee: The native fee.
    ///  - lzTokenFee: The lzToken fee.
    function quoteSend(
        SendParam calldata _sendParam,
        bool _payInLzToken
    )
        external
        view
        virtual
        returns (MessagingFee memory msgFee)
    {
        /// @dev mock the amount to receive, this is the same operation used in the send().
        /// The quote is as similar as possible to the actual send() operation.
        (, uint256 amountReceived) = _debitView(_sendParam.amount, _sendParam.minAmount, _sendParam.dstEid);

        /// @dev Builds the options and OFT message to quote in the endpoint.
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, amountReceived);

        /// @dev Calculates the LayerZero fee for the send() operation.
        return _quote(_sendParam.dstEid, message, options, _payInLzToken);
    }

    /// @dev Executes the send operation.
    /// @param _sendParam The parameters for the send operation.
    /// @param _fee The calculated fee for the send() operation.
    ///      - nativeFee: The native fee.
    ///      - lzTokenFee: The lzToken fee.
    /// @param _refundAddress The address to receive any excess funds.
    /// @return msgReceipt The receipt for the send operation.
    /// @return oftReceipt The OFT receipt information.
    /// @dev MessagingReceipt: LayerZero msg receipt
    ///  - guid: The unique identifier for the sent message.
    ///  - nonce: The nonce of the sent message.
    ///  - fee: The LayerZero fee incurred for the message.
    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    )
        public
        payable
        virtual
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
    {
        /// @dev Applies the token transfers regarding this send() operation.
        /// - amountSent is the amount that was ACTUALLY sent/debited from the sender.
        /// - amountReceived is the amount that will be received/credited to the recipient on the
        /// remote OFT instance.
        (uint256 amountSent, uint256 amountReceived) =
            _debit(msg.sender, _sendParam.amount, _sendParam.minAmount, _sendParam.dstEid);

        /// @dev Builds the options and OFT message to quote in the endpoint.
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, amountReceived);

        /// @dev Sends the message to the LayerZero endpoint and returns the LayerZero msg receipt.
        msgReceipt = _lzSend(_sendParam.dstEid, message, options, _fee, _refundAddress);
        /// @dev Formulate the OFT receipt.
        oftReceipt = OFTReceipt(amountSent, amountReceived);

        emit OFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, amountSent, amountReceived);
    }

    /// @dev Internal function to build the message and options.
    /// @param _sendParam The parameters for the send() operation.
    /// @param _amount The amount.
    /// @return message The encoded message.
    /// @return options The encoded options.
    function _buildMsgAndOptions(
        SendParam calldata _sendParam,
        uint256 _amount
    )
        internal
        view
        virtual
        returns (bytes memory message, bytes memory options)
    {
        bool hasCompose;
        /// @dev This generated message has the msg.sender encoded into the payload so the remote knows who the caller
        /// is.
        (message, hasCompose) = OFTMsgCodec.encode(
            _sendParam.to,
            _amount,
            /// @dev Must be include a non empty bytes if you want to compose, EVEN if you dont need it on the remote.
            /// EVEN if you dont require an arbitrary payload to be sent... eg. '0x01'
            _sendParam.composeMsg
        );
        /// @dev Change the msg type depending if its composed or not.
        uint16 msgType = hasCompose ? SEND_AND_CALL : SEND;
        /// @dev Combine the callers _extraOptions with the enforced options via the OAppOptionsType3.
        options = combineOptions(_sendParam.dstEid, msgType, _sendParam.extraOptions);

        /// @dev Optionally inspect the message and options depending if the OApp owner has set a msg inspector.
        /// @dev If it fails inspection, needs to revert in the implementation. ie. does not rely on return boolean
        if (msgInspector != address(0)) IOAppMsgInspector(msgInspector).inspect(message, options);
    }

    /// @dev Internal function to handle the receive on the LayerZero endpoint.
    /// @param _origin The origin information.
    ///  - srcEid: The source chain endpoint ID.
    ///  - sender: The sender address from the src chain.
    ///  - nonce: The nonce of the LayerZero message.
    /// @param _guid The unique identifier for the received LayerZero message.
    /// @param _message The encoded message.
    /// @dev _executor The address of the executor.
    /// @dev _extraData Additional data.
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address, /*_executor*/ // @dev unused in the default implementation.
        bytes calldata /*_extraData*/ // @dev unused in the default implementation.
    )
        internal
        virtual
        override
    {
        /// @dev The src sending chain doesnt know the address length on this chain (potentially non-evm)
        /// Thus everything is bytes32() encoded in flight.
        address toAddress = _message.sendTo().bytes32ToAddress();
        /// @dev Credit the amount to the recipient and return the ACTUAL amount the recipient received in local
        /// decimals
        uint256 amountReceived = _credit(toAddress, _message.amount(), _origin.srcEid);

        if (_message.isComposed()) {
            /// @dev Proprietary composeMsg format for the OFT.
            bytes memory composeMsg =
                OFTComposeMsgCodec.encode(_origin.nonce, _origin.srcEid, amountReceived, _message.composeMsg());

            /// @dev Stores the lzCompose payload that will be executed in a separate tx.
            /// Standardizes functionality for executing arbitrary contract invocation on some non-evm chains.
            /// @dev The off-chain executor will listen and process the msg based on the src-chain-callers compose
            /// options passed.
            /// @dev The index is used when a OApp needs to compose multiple msgs on lzReceive.
            /// For default OFT implementation there is only 1 compose msg per lzReceive, thus its always 0.
            endpoint.sendCompose(toAddress, _guid, 0, /* the index of the composed message*/ composeMsg);
        }

        emit OFTReceived(_guid, _origin.srcEid, toAddress, amountReceived);
    }

    /// @dev Internal function to handle the OAppPreCrimeSimulator simulated receive.
    /// @param _origin The origin information.
    ///  - srcEid: The source chain endpoint ID.
    ///  - sender: The sender address from the src chain.
    ///  - nonce: The nonce of the LayerZero message.
    /// @param _guid The unique identifier for the received LayerZero message.
    /// @param _message The LayerZero message.
    /// @param _executor The address of the off-chain executor.
    /// @param _extraData Arbitrary data passed by the msg executor.
    /// @dev Enables the preCrime simulator to mock sending lzReceive() messages,
    /// routes the msg down from the OAppPreCrimeSimulator, and back up to the OAppReceiver.
    function _lzReceiveSimulate(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    )
        internal
        virtual
        override
    {
        _lzReceive(_origin, _guid, _message, _executor, _extraData);
    }

    /// @dev Check if the peer is considered 'trusted' by the OApp.
    /// @param _eid The endpoint ID to check.
    /// @param _peer The peer to check.
    /// @return Whether the peer passed is considered 'trusted' by the OApp.
    /// @dev Enables OAppPreCrimeSimulator to check whether a potential Inbound Packet is from a trusted source.
    function isPeer(uint32 _eid, bytes32 _peer) public view virtual override returns (bool) {
        return peers[_eid] == _peer;
    }

    /// @dev Internal function to mock the amount mutation from a OFT debit() operation.
    /// @param _amount The amount to send.
    /// @param _minAmount The minimum amount to send.
    /// @dev _dstEid The destination endpoint ID.
    /// @return amountSent The amount sent,.
    /// @return amountReceived The amount to be received on the remote chain,.
    /// @dev This is where things like fees would be calculated and deducted from the amount to be received on the
    /// remote.
    function _debitView(
        uint256 _amount,
        uint256 _minAmount,
        uint32 /*_dstEid*/
    )
        internal
        view
        virtual
        returns (uint256 amountSent, uint256 amountReceived)
    {
        amountSent = _amount;
        /// @dev The amount to send is the same as amount received in the default implementation.
        amountReceived = amountSent;

        /// @dev Check for slippage.
        if (amountReceived < _minAmount) {
            revert SlippageExceeded(amountReceived, _minAmount);
        }
    }

    /// @dev Internal function to perform a debit operation.
    /// @param _from The address to debit.
    /// @param _amount The amount to send.
    /// @param _minAmount The minimum amount to send.
    /// @param _dstEid The destination endpoint ID.
    /// @return amountSent The amount sent.
    /// @return amountReceived The amount received on the remote.
    /// @dev Defined here but are intended to be overriden depending on the OFT implementation.
    /// @dev Depending on OFT implementation the _amount could differ from the amountReceived.
    function _debit(
        address _from,
        uint256 _amount,
        uint256 _minAmount,
        uint32 _dstEid
    )
        internal
        virtual
        returns (uint256 amountSent, uint256 amountReceived);

    /// @dev Internal function to perform a credit operation.
    /// @param _to The address to credit.
    /// @param _amount The amount to credit.
    /// @param _srcEid The source endpoint ID.
    /// @return amountReceived The amount ACTUALLY received.
    /// @dev Defined here but are intended to be overriden depending on the OFT implementation.
    /// @dev Depending on OFT implementation the _amount could differ from the amountReceived.
    function _credit(address _to, uint256 _amount, uint32 _srcEid) internal virtual returns (uint256 amountReceived);
}
