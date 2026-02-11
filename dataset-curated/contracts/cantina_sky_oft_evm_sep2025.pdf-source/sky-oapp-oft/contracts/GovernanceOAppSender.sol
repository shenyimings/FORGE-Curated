// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OAppSender, OAppCore, MessagingFee, MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";

import { IGovernanceOAppSender, TxParams } from "./interfaces/IGovernanceOAppSender.sol";

/**
 * @title GovernanceOAppSender
 * @dev Cross-chain governance sender contract that handles outbound governance calls
 * @notice This contract manages permissions and sends governance transactions to remote chains via LayerZero
 * @author LayerZero Labs
 */
contract GovernanceOAppSender is OAppSender, OAppOptionsType3, IGovernanceOAppSender {
    /// @dev The message type identifier for sending transactions
    uint16 public constant SEND_TX = 1;

    /// @dev This mapping is used to determine if a sender is allowed to call a specific target on a given dst EID.
    mapping(address srcSender => mapping(uint32 dstEid => mapping(bytes32 dstTarget => bool canCall))) public canCallTarget;

    /**
     * @dev Constructor to initialize the GovernanceOAppSender contract
     * @param _endpoint The LayerZero endpoint address
     * @param _owner The delegate and owner address for the OApp
     */
    constructor(address _endpoint, address _owner) OAppCore(_endpoint, _owner) Ownable(_owner) {

        // Deployment steps:
        // 1. Deploy the GovernanceOAppSender on a given chain.
        // 2. Deploy the GovernanceOAppReceiver on all the dst chains with eid, and addresses generated from step 1.
        // 3. Set the peers on the GovernanceOAppSender contract for all of the receivers deployed in step 2.
        //
        // IMPORTANT!!!!: Since the GovernanceOAppReceiver's lzReceive is gated by valid peers. 
        // If you remove the GovernanceOAppSender as a peer on the GovernanceOAppReceiver contracts, 
        // the GovernanceOAppReceiver will no longer be able to receive/execute messages from the GovernanceOAppSender. 
        // This will brick the system!!! So be very careful when removing a peer.
    }

    /**
     * @inheritdoc IGovernanceOAppSender
     */
    function setCanCallTarget(address _srcSender, uint32 _dstEid, bytes32 _dstTarget, bool _canCall) external onlyOwner {
        if (canCallTarget[_srcSender][_dstEid][_dstTarget] == _canCall) revert CanCallTargetIdempotent();

        canCallTarget[_srcSender][_dstEid][_dstTarget] = _canCall;
        emit CanCallTargetSet(_srcSender, _dstEid, _dstTarget, _canCall);
    }

    /**
     * @inheritdoc IGovernanceOAppSender
     */
    function quoteTx(TxParams calldata _params, bool _payInLzToken) external view returns (MessagingFee memory fee) {
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_params);

        return _quote(_params.dstEid, message, options, _payInLzToken);
    }

    /**
     * @inheritdoc IGovernanceOAppSender
     */
    function sendTx(
        TxParams calldata _params,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory msgReceipt) {
        if (!canCallTarget[msg.sender][_params.dstEid][_params.dstTarget]) revert CannotCallTarget();

        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_params);

        msgReceipt = _lzSend(_params.dstEid, message, options, _fee, _refundAddress);

        emit GovernanceCallSent(msgReceipt.guid);
    }

    /**
     * @dev Build the message and options for sending a governance transaction
     * @param _params The transaction parameters
     * @return message The encoded message containing sender, target, and calldata
     * @return options The LayerZero options for the message
     */
    function _buildMsgAndOptions(TxParams calldata _params) internal view returns (bytes memory, bytes memory) {
        // Convert msg.sender to bytes32 for cross-chain compatibility
        bytes32 msgSenderBytes32 = bytes32(uint256(uint160(msg.sender)));

        // Encode the message with sender, target, and calldata
        bytes memory message = abi.encodePacked(msgSenderBytes32, _params.dstTarget, _params.dstCallData);
        bytes memory options = combineOptions(_params.dstEid, SEND_TX, _params.extraOptions);

        return (message, options);
    }
}
