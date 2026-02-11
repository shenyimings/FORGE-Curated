// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { OAppReceiver, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppReceiver.sol";
import { OAppCore } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppCore.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";

import { SendParam, MessagingFee, IOFT } from "contracts/layerZero/interfaces/IOFT.sol";
import { OFTMsgCodec } from "contracts/layerZero/libs/OFTMsgCodec.sol";

import { ErrorsLib } from "contracts/libraries/ErrorsLib.sol";

/// @title PrincipalMigrationContract
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice LayerZero OappReceiver contract.
/// Messages received will contain the amount of Mimo the user want to migrate and the chain he want to receive it.
/// @dev This contract will use the LockBox contract to bridge PRL to the destination chain that user specified.
contract PrincipalMigrationContract is OAppReceiver, OAppOptionsType3, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using OFTMsgCodec for bytes;
    using OFTMsgCodec for bytes32;

    uint256 private constant EXTRA_OPTION_START = 192;
    /// MIMO contract token
    IERC20 public immutable MIMO;
    /// PRL contract token
    IERC20 public immutable PRL;
    /// LayerZero's OFTAdapter used to send PRL token to other chains
    IOFT public immutable lockBox;

    //-------------------------------------------
    // Events
    //-------------------------------------------

    /// @notice Emitted when MIMO tokens are migrated to PRL tokens directly on this chain.
    /// @param caller The address that initiate the migration.
    /// @param receiver The address receiving the PRL tokens.
    /// @param amount The amount of MIMO tokens migrated to PRL tokens.
    event MIMOToPRLMigrated(address caller, address receiver, uint256 amount);

    /// @notice Emitted when MIMO tokens are migrated to PRL tokens and bridged to another chain.
    /// @param caller The address that initiate the migration.
    /// @param receiver The address receiving the PRL tokens.
    /// @param sendParam The SendParam struct send to the LockBox contract.
    /// @param fee The MessagingFee struct paid for the bridging.
    event MIMOToPRLMigratedAndBridged(address caller, address receiver, SendParam sendParam, MessagingFee fee);

    /// @notice Emitted when a migration message is received
    /// @param guid The unique identifier of the received message
    /// @param srcEid The source endpoint ID
    /// @param sender The address of the sender
    /// @param destEid The destination endpoint ID
    /// @param receiver The address of the receiver
    /// @param mimoAmount The amount of tokens being migrated
    /// @param prlAmount The amount of PRL tokens to be received
    event MigrationMessageReceived(
        bytes32 guid,
        uint32 srcEid,
        address sender,
        uint32 destEid,
        address receiver,
        uint256 mimoAmount,
        uint256 prlAmount
    );

    /// @notice Emitted when tokens are rescued in an emergency
    /// @param token The address of the rescued token
    /// @param amount The amount of tokens rescued
    /// @param recipient The address that received the rescued tokens
    event EmergencyRescued(address indexed token, uint256 amount, address indexed recipient);

    //-------------------------------------------
    // Constructor
    //-------------------------------------------

    /// @notice Constructor for PrincipalMigrationContract
    /// @param _mimo Address of the MIMO token contract
    /// @param _prl Address of the PRL token contract
    /// @param _lockBox Address of the PRL bridge contract (OFTAdapter)
    /// @param _endpoint Address of the LayerZero endpoint
    /// @param _owner Address of the contract owner
    constructor(
        address _mimo,
        address _prl,
        address _lockBox,
        address _endpoint,
        address _owner
    )
        OAppCore(_endpoint, _owner)
        Ownable(_owner)
    {
        if (_mimo == address(0)) revert ErrorsLib.AddressZero();
        if (_prl == address(0)) revert ErrorsLib.AddressZero();
        if (_lockBox == address(0)) revert ErrorsLib.AddressZero();
        MIMO = IERC20(_mimo);
        PRL = IERC20(_prl);
        lockBox = IOFT(_lockBox);
    }

    //-------------------------------------------
    // External functions
    //-------------------------------------------

    /// @notice Migrates MIMO tokens to PRL tokens
    /// @param _amount The amount of MIMO tokens to migrate
    function migrateToPRL(uint256 _amount, address _recipient) external whenNotPaused nonReentrant {
        emit MIMOToPRLMigrated(msg.sender, _recipient, _amount);
        MIMO.safeTransferFrom(msg.sender, address(this), _amount);
        PRL.safeTransfer(_recipient, _amount);
    }

    /// @notice Migrates MIMO tokens to PRL tokens and bridges them to another chain
    /// @param _sendParam The parameters for the send operation.
    /// @param _fee The calculated fees for the send() operation.
    ///      - nativeFee: The native fees.
    ///      - lzTokenFee: The lzToken fees.
    function migrateToPRLAndBridge(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    )
        external
        payable
        whenNotPaused
        nonReentrant
    {
        if (_refundAddress == address(0)) revert ErrorsLib.AddressZero();
        emit MIMOToPRLMigratedAndBridged(msg.sender, _sendParam.to.bytes32ToAddress(), _sendParam, _fee);
        MIMO.safeTransferFrom(msg.sender, address(this), _sendParam.amount);
        PRL.approve(address(lockBox), _sendParam.amount);
        lockBox.send{ value: msg.value }(_sendParam, _fee, _refundAddress);
    }

    /// @notice Fallback function to receive Ether
    /// @dev This function allows the contract to receive Ether. It's required for
    ///      handling native token refunds from LayerZero or any other operations
    ///      that might send Ether to this contract.
    receive() external payable { }

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

    /// @dev Internal function to handle the received message on the LayerZero endpoint.
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
        override
    {
        (address receiver, uint256 amount, uint32 destEid, uint256 extraOptionsLength) = _decodeMessage(_message);
        emit MigrationMessageReceived(
            _guid, _origin.srcEid, _origin.sender.bytes32ToAddress(), destEid, receiver, amount, amount
        );

        if (extraOptionsLength == 0 || destEid == endpoint.eid()) {
            emit MIMOToPRLMigrated(_origin.sender.bytes32ToAddress(), receiver, amount);
            PRL.safeTransfer(receiver, amount);
        } else {
            SendParam memory sendParam = _buildSendParam(_message, receiver, amount, destEid, extraOptionsLength);
            emit MIMOToPRLMigratedAndBridged(
                _origin.sender.bytes32ToAddress(), receiver, sendParam, MessagingFee(msg.value, 0)
            );
            PRL.approve(address(lockBox), amount);
            lockBox.send{ value: msg.value }(sendParam, MessagingFee(msg.value, 0), receiver);
        }
    }

    /// @notice Decodes the received LayerZero message
    /// @param _encodedMessage The encoded message received from LayerZero
    /// @return receiver The address of the receiver
    /// @return amount The amount of tokens being migrated
    /// @return destEid The destination endpoint ID
    /// @return extraOptionsLength The length of extra options in the message
    function _decodeMessage(bytes calldata _encodedMessage)
        public
        pure
        returns (address receiver, uint256 amount, uint32 destEid, uint256 extraOptionsLength)
    {
        // Decode the first part of the message
        (bytes32 _to, uint256 _amount, uint32 _destEid, uint256 _extraOptionsLength) =
            abi.decode(_encodedMessage, (bytes32, uint256, uint32, uint256));
        return (_to.bytes32ToAddress(), _amount, _destEid, _extraOptionsLength);
    }

    /// @notice Builds the SendParam struct for the OFT bridge
    /// @param _encodedMessage The encoded message received from LayerZero
    /// @param _receiver The address of the receiver
    /// @param _finalAmount The final amount of PRL tokens to be sent
    /// @param _destEid The destination endpoint ID
    /// @param _extraOptionsLength The length of extra options in the message
    /// @return params The SendParam struct for the OFT bridge
    function _buildSendParam(
        bytes calldata _encodedMessage,
        address _receiver,
        uint256 _finalAmount,
        uint32 _destEid,
        uint256 _extraOptionsLength
    )
        internal
        pure
        returns (SendParam memory params)
    {
        bytes memory _options = _encodedMessage[EXTRA_OPTION_START:EXTRA_OPTION_START + _extraOptionsLength];
        return
            SendParam(_destEid, OFTMsgCodec.addressToBytes32(_receiver), _finalAmount, _finalAmount, _options, "", "");
    }
}
