// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { OAppReceiver, OAppCore, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppReceiver.sol";

import { IGovernanceOAppReceiver, MessageOrigin } from "./interfaces/IGovernanceOAppReceiver.sol";

/**
 * @title GovernanceOAppReceiver
 * @dev Cross-chain governance receiver contract that handles inbound governance calls
 * @notice This contract receives and executes governance transactions from remote chains via LayerZero
 * @author LayerZero Labs
 */
contract GovernanceOAppReceiver is OAppReceiver, ReentrancyGuard, IGovernanceOAppReceiver {
    /// @dev Temporary variable to store the origin caller and expose it to target contracts during execution
    MessageOrigin private _messageOrigin;

    /**
     * @dev Constructor to initialize the GovernanceOAppReceiver contract
     * @param _governanceOAppSenderEid The GovernanceOAppSender endpoint ID
     * @param _governanceOAppSenderAddress The GovernanceOAppSender address
     * @param _endpoint The LayerZero endpoint address
     * @param _owner The delegate and owner address for the OApp
     */
    constructor(
        uint32 _governanceOAppSenderEid, 
        bytes32 _governanceOAppSenderAddress, 
        address _endpoint, 
        address _owner
    ) OAppCore(_endpoint, _owner) Ownable(_owner) {
        // Set the peer on the GovernanceOAppReceiver contract to the GovernanceOAppSender contract
        _setPeer(_governanceOAppSenderEid, _governanceOAppSenderAddress);

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
     * @inheritdoc IGovernanceOAppReceiver
     */
    function messageOrigin() external view returns (MessageOrigin memory) {
        return _messageOrigin;
    }

    /**
     * @dev Internal function to handle incoming LayerZero messages
     * @param _origin The origin information of the message
     * @param _guid The unique identifier for the message
     * @param _payload The message payload containing sender, target, and calldata
     * @dev _executor The executor address (unused)
     * @dev _extraData Additional data (unused)
     * @notice This function decodes the payload and executes the governance call on the target contract
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override nonReentrant {
        // Extract the source sender from the first 32 bytes of payload
        bytes32 srcSender = bytes32(_payload[0:32]);
        
        // Extract the target address from bytes 44:64 (last 20 bytes of the 32-byte padded field)
        // The source pads the address to 32 bytes for EVM compatibility.
        address dstTarget = address(uint160(bytes20(_payload[44:64])));
        
        // Extract the calldata from the remaining payload
        bytes memory dstCallData = _payload[64:];
    
        // Set the message origin for the target contract to validate
        // The target contract NEEDS to validate the MessageOrigin struct to confirm it is a valid caller from the source
        _messageOrigin = MessageOrigin({ srcEid: _origin.srcEid, srcSender: srcSender });

        // Execute the governance call on the target contract
        // Target contract SHOULD validate the msg.value if it's used
        (bool success, bytes memory returnData) = dstTarget.call{ value: msg.value }(dstCallData);
        if (!success) {
            if (returnData.length == 0) revert GovernanceCallFailed();
            // Bubble up the revert reason from the target contract
            assembly ("memory-safe") {
                revert(add(32, returnData), mload(returnData))
            }
        }

        // Clear the MessageOrigin to prevent reuse on subsequent calls
        _messageOrigin = MessageOrigin({ srcEid: 0, srcSender: bytes32(0) });

        emit GovernanceCallReceived(_guid);
    }
}
