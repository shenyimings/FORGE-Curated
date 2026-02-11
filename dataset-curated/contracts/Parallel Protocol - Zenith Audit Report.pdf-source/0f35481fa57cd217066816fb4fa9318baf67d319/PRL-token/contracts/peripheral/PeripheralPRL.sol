// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import { OFTMsgCodec } from "contracts/layerZero/libs/OFTMsgCodec.sol";
import { OFT } from "contracts/layerZero/OFT.sol";
import { SendParam, MessagingFee, MessagingReceipt, OFTReceipt } from "contracts/layerZero/interfaces/IOFT.sol";

import { ErrorsLib } from "contracts/libraries/ErrorsLib.sol";

/// @title PeripheralPRL
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
contract PeripheralPRL is OFT, ERC20Permit, Pausable {
    using OFTMsgCodec for bytes;
    using OFTMsgCodec for bytes32;

    /// @notice Initializes the PeripheralPRL contract
    /// @param _endpoint Address of the LayerZero endpoint
    /// @param _owner Address of the contract owner
    constructor(
        address _endpoint,
        address _owner
    )
        OFT("Parallel Governance Token", "PRL", _endpoint, _owner)
        Ownable(_owner)
        ERC20Permit("Parallel Governance Token")
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
        if (_refundAddress == address(0)) revert ErrorsLib.AddressZero();
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
