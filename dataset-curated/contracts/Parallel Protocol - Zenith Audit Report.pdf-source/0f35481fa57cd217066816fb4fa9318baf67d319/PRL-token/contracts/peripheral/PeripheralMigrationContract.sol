// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { OAppSender } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { OAppCore } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppCore.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";

import { OFTMsgCodec } from "contracts/layerZero/libs/OFTMsgCodec.sol";
import { MessagingFee, MessagingReceipt } from "contracts/layerZero/interfaces/IOFT.sol";

import { ErrorsLib } from "contracts/libraries/ErrorsLib.sol";

/// @title PeripheralMigrationContract
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Contract that send message to the PrincipalMigrationContract and own MIMO migrated from it.
contract PeripheralMigrationContract is OAppSender, OAppOptionsType3, Pausable {
    using SafeERC20 for IERC20;

    uint16 public constant SEND = 1;
    uint16 public constant SEND_AND_MIGRATE = 2;
    uint256 private constant EXTRA_OPTION_START = 160;

    /// MIMO contract token
    IERC20 public immutable MIMO;

    uint32 public immutable mainEid;

    //-------------------------------------------
    // Events
    //-------------------------------------------

    /// @notice Emitted when a migration message is sent
    /// @param guid The unique identifier of the sent message
    /// @param dstEid The destination endpoint ID
    /// @param from The address sending the migration
    /// @param to The address receiving the migrated tokens
    /// @param nativeFeeAmount The amount of native fee paid for the message
    /// @param amountSent The amount of tokens being migrated
    event MigrationMessageSent(
        bytes32 guid, uint32 dstEid, address from, address to, uint256 nativeFeeAmount, uint256 amountSent
    );

    /// @notice Emitted when tokens are rescued in an emergency
    /// @param token The address of the rescued token
    /// @param amount The amount of tokens rescued
    /// @param recipient The address that received the rescued tokens
    event EmergencyRescued(address indexed token, uint256 amount, address indexed recipient);

    //-------------------------------------------
    // Constructor
    //-------------------------------------------

    /// @notice Initializes the PeripheralMigrationContract
    /// @param _mimo Address of the MIMO token contract
    /// @param _endpoint Address of the LayerZero endpoint
    /// @param _owner Address of the contract owner
    /// @param _mainEid Endpoint ID of the main chain where the PrincipalMigrationContract is deployed
    constructor(
        address _mimo,
        address _endpoint,
        address _owner,
        uint32 _mainEid
    )
        OAppCore(_endpoint, _owner)
        Ownable(_owner)
    {
        if (_mimo == address(0)) revert ErrorsLib.AddressZero();
        MIMO = IERC20(_mimo);
        mainEid = _mainEid;
    }

    //-------------------------------------------
    // External functions
    //-------------------------------------------

    /// @notice Migrates MIMO tokens to PRL tokens on another chain
    /// @param _receiver The address that will receive the PRL tokens
    /// @param _amount The amount of MIMO tokens to migrate
    /// @param _dstEid The destination endpoint ID
    /// @param _extraSendOptions Gas settings for A -> Main Chain
    /// @param _extraReturnOptions Gas settings for Main Chain -> Final chain
    /// @return msgReceipt The receipt of the LayerZero message
    function migrateToPRL(
        address _receiver,
        uint256 _amount,
        uint32 _dstEid,
        address _refundAddress,
        bytes calldata _extraSendOptions,
        bytes calldata _extraReturnOptions
    )
        external
        payable
        whenNotPaused
        returns (MessagingReceipt memory msgReceipt)
    {
        if (_refundAddress == address(0)) revert ErrorsLib.AddressZero();
        uint256 fee = msg.value;
        bytes memory options =
            combineOptions(_dstEid, _extraSendOptions.length > 0 ? SEND_AND_MIGRATE : SEND, _extraSendOptions);

        MIMO.safeTransferFrom(msg.sender, address(this), _amount);
        msgReceipt = _lzSend(
            mainEid,
            _encodeMessage(_receiver, _amount, _dstEid, _extraReturnOptions),
            options,
            // Fee in native gas and ZRO token.
            MessagingFee(msg.value, 0),
            // Refund address in case of failed source message.
            _refundAddress
        );
        emit MigrationMessageSent(msgReceipt.guid, _dstEid, msg.sender, _receiver, fee, _amount);
    }

    /// @notice Returns the estimated messaging fee for a given message.
    /// @param _dstEid Destination endpoint ID where the message will be sent.
    /// @param _receiver Address that will receive the PRL token.abi
    /// @param _amount The amount of Mimo token to migrate.
    /// @param _extraSendOptions Gas options for receiving the send call (A -> B).
    /// @param _extraReturnOptions Additional gas options for the return call (B -> A).
    /// @return fee The estimated messaging fee.
    function quote(
        uint32 _dstEid,
        address _receiver,
        uint256 _amount,
        bytes calldata _extraSendOptions,
        bytes calldata _extraReturnOptions
    )
        public
        view
        returns (MessagingFee memory fee)
    {
        bytes memory payload = _encodeMessage(_receiver, _amount, _dstEid, _extraReturnOptions);
        bytes memory options =
            combineOptions(_dstEid, _extraSendOptions.length > 0 ? SEND_AND_MIGRATE : SEND, _extraSendOptions);
        fee = _quote(mainEid, payload, options, false);
    }

    //-------------------------------------------
    // OnlyOwner functions
    //-------------------------------------------

    /// @notice Allows the owner to rescue any ERC20 token from the contract in case of emergency
    /// @dev This function can only be called by the owner and only when the contract is paused
    /// @param _token The address of the ERC20 token to rescue
    /// @param _amount The amount of tokens to rescue
    function emergencyRescue(address _token, uint256 _amount) external onlyOwner whenPaused {
        emit EmergencyRescued(_token, _amount, msg.sender);
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

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

    //-------------------------------------------
    // Internal functions
    //-------------------------------------------

    /// @notice Encodes the migration message
    /// @param _receiver The address that will receive the PRL tokens
    /// @param _amount The amount of MIMO tokens to migrate
    /// @param _dstEid The destination endpoint ID
    /// @param _extraReturnOptions Additional gas options for the return call (B -> A)
    /// @return The encoded message
    function _encodeMessage(
        address _receiver,
        uint256 _amount,
        uint32 _dstEid,
        bytes memory _extraReturnOptions
    )
        internal
        pure
        returns (bytes memory)
    {
        // Get the length of _extraReturnOptions
        uint256 extraOptionsLength = _extraReturnOptions.length;

        // Encode the entire message, prepend and append the length of _extraReturnOptions
        return abi.encode(
            OFTMsgCodec.addressToBytes32(_receiver), _amount, _dstEid, extraOptionsLength, _extraReturnOptions
        );
    }
}
