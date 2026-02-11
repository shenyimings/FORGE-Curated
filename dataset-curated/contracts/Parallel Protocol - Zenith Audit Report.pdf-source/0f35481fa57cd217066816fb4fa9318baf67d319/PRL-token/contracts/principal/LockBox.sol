// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { OFTMsgCodec } from "contracts/layerZero/libs/OFTMsgCodec.sol";
import { OFTAdapter } from "contracts/layerZero/OFTAdapter.sol";
import { SendParam, MessagingFee, MessagingReceipt, OFTReceipt } from "contracts/layerZero/interfaces/IOFT.sol";

/// @title LockBox
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice LayerZero OFTAdapter contract that allow PRL to be bridge between chains.
/// @dev This contract is only deployed on the main chain where the PRL token contract is deployed.
/// Locking PRL that has been bridged.
contract LockBox is OFTAdapter, Pausable {
    using OFTMsgCodec for bytes;
    using OFTMsgCodec for bytes32;

    //-------------------------------------------
    // Constructor
    //-------------------------------------------

    /// @notice Initializes the LockBox contract
    /// @param _prlToken Address of the PRL token contract
    /// @param _endpoint Address of the LayerZero endpoint
    /// @param _owner Address of the contract owner
    constructor(
        address _prlToken,
        address _endpoint,
        address _owner
    )
        OFTAdapter(_prlToken, _endpoint, _owner)
        Ownable(_owner)
    {
        // No additional initialization needed
    }

    //-------------------------------------------
    // External functions
    //-------------------------------------------

    /// @notice Sends tokens to another chain
    /// @dev This function is pausable and overrides the base OFT implementation
    /// @param _sendParam Parameters for the send operation
    /// @param _fee Messaging fee for the LayerZero transaction
    /// @param _refundAddress Address to refund excess fees
    /// @return msgReceipt Receipt for the LayerZero message
    /// @return oftReceipt Receipt for the OFT transaction
    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    )
        public
        payable
        override
        whenNotPaused
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
    {
        return super.send(_sendParam, _fee, _refundAddress);
    }

    /// @notice Sends tokens to another chain using EIP-2612 permit
    /// @dev This function combines permit and send operations
    /// @param _sendParam Parameters for the send operation
    /// @param _fee Messaging fee for the LayerZero transaction
    /// @param _refundAddress Address to refund excess fees
    /// @param _deadline Expiration time of the permit signature
    /// @param _v ECDSA signature parameter v
    /// @param _r ECDSA signature parameter r
    /// @param _s ECDSA signature parameter s
    /// @return msgReceipt Receipt for the LayerZero message
    /// @return oftReceipt Receipt for the OFT transaction
    function sendWithPermit(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )
        public
        payable
        whenNotPaused
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
    {
        // @dev using try catch to avoid reverting the transaction in case of front-running
        try IERC20Permit(address(innerToken)).permit(
            msg.sender, address(this), _sendParam.amount, _deadline, _v, _r, _s
        ) { } catch { }
        return super.send(_sendParam, _fee, _refundAddress);
    }

    //-------------------------------------------
    // OnlyOwner functions
    //-------------------------------------------

    /// @notice Allow owner to pause the contract
    /// @dev This function can only be called by the owner
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Allow owner to unpause the contract
    /// @dev This function can only be called by the owner
    function unpause() external onlyOwner {
        _unpause();
    }
}
