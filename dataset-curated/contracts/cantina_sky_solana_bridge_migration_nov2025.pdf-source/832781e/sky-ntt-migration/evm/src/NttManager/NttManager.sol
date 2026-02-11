// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "wormhole-solidity-sdk/Utils.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

import "../libraries/RateLimiter.sol";

import "../interfaces/INttManager.sol";
import "../interfaces/INttToken.sol";
import "../interfaces/ITransceiver.sol";

import {ManagerBase} from "./ManagerBase.sol";

/// @title NttManager
/// @author Wormhole Project Contributors.
/// @notice The NttManager contract is responsible for managing the token
///         and associated transceivers.
///
/// @dev Each NttManager contract is associated with a single token but
///      can be responsible for multiple transceivers.
///
/// @dev When transferring tokens, the NttManager contract will either
///      lock the tokens or burn them, depending on the mode.
///
/// @dev To initiate a transfer, the user calls the transfer function with:
///  - the amount
///  - the recipient chain
///  - the recipient address
///  - the refund address: the address to which refunds are issued for any unused gas
///    for attestations on a given transfer. If the gas limit is configured
///    to be too high, users will be refunded the difference.
///  - (optional) a flag to indicate whether the transfer should be queued
///    if the rate limit is exceeded
contract NttManager is INttManager, RateLimiter, ManagerBase {
    using BytesParsing for bytes;
    using SafeERC20 for IERC20;
    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    // @dev kept at 1.1.0 to avoid need to make changes to offchain code including NTT CLI
    string public constant NTT_MANAGER_VERSION = "1.1.0";

    // =============== Setup =================================================================

    constructor(
        address _token,
        Mode _mode,
        uint16 _chainId,
        uint64 _rateLimitDuration,
        bool _skipRateLimiting
    ) RateLimiter(_rateLimitDuration, _skipRateLimiting) ManagerBase(_token, _mode, _chainId) {}

    function __NttManager_init() internal onlyInitializing {
        // check if the owner is the deployer of this contract
        if (msg.sender != deployer) {
            revert UnexpectedDeployer(deployer, msg.sender);
        }
        if (msg.value != 0) {
            revert UnexpectedMsgValue();
        }
        __PausedOwnable_init(msg.sender, msg.sender);
        __ReentrancyGuard_init();
        _setOutboundLimit(TrimmedAmountLib.max(tokenDecimals()));
    }

    function _initialize() internal virtual override {
        __NttManager_init();
        _checkThresholdInvariants();
        _checkTransceiversInvariants();
    }

    // =============== Storage ==============================================================

    bytes32 private constant PEERS_SLOT = bytes32(uint256(keccak256("ntt.peers")) - 1);

    // =============== Storage Getters/Setters ==============================================

    function _getPeersStorage()
        internal
        pure
        returns (mapping(uint16 => NttManagerPeer) storage $)
    {
        uint256 slot = uint256(PEERS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    // =============== Public Getters ========================================================

    /// @inheritdoc INttManager
    function getPeer(
        uint16 chainId_
    ) external view returns (NttManagerPeer memory) {
        return _getPeersStorage()[chainId_];
    }

    // =============== Admin ==============================================================

    /// @inheritdoc INttManager
    function setPeer(
        uint16 peerChainId,
        bytes32 peerContract,
        uint8 decimals,
        uint256 inboundLimit
    ) public onlyOwner {
        if (peerChainId == 0) {
            revert InvalidPeerChainIdZero();
        }
        if (peerContract == bytes32(0)) {
            revert InvalidPeerZeroAddress();
        }
        if (decimals == 0) {
            revert InvalidPeerDecimals();
        }
        if (peerChainId == chainId) {
            revert InvalidPeerSameChainId();
        }

        NttManagerPeer memory oldPeer = _getPeersStorage()[peerChainId];

        _getPeersStorage()[peerChainId].peerAddress = peerContract;
        _getPeersStorage()[peerChainId].tokenDecimals = decimals;

        uint8 toDecimals = tokenDecimals();
        _setInboundLimit(inboundLimit.trim(toDecimals, toDecimals), peerChainId);

        emit PeerUpdated(
            peerChainId, oldPeer.peerAddress, oldPeer.tokenDecimals, peerContract, decimals
        );
    }

    /// @inheritdoc INttManager
    function setOutboundLimit(
        uint256 limit
    ) external onlyOwner {
        uint8 toDecimals = tokenDecimals();
        _setOutboundLimit(limit.trim(toDecimals, toDecimals));
    }

    /// @inheritdoc INttManager
    function setInboundLimit(uint256 limit, uint16 chainId_) external onlyOwner {
        uint8 toDecimals = tokenDecimals();
        _setInboundLimit(limit.trim(toDecimals, toDecimals), chainId_);
    }

    function migrateLockedTokens(
        address recipient
    ) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(recipient, balance);
    }

    /// ============== Invariants =============================================

    /// @dev When we add new immutables, this function should be updated
    function _checkImmutables() internal view override {
        super._checkImmutables();
        assert(this.rateLimitDuration() == rateLimitDuration);
    }

    // ==================== External Interface ===============================================

    /// @inheritdoc INttManager
    function attestationReceived(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        TransceiverStructs.NttManagerMessage memory payload
    ) external onlyTransceiver whenNotPaused {
        _verifyPeer(sourceChainId, sourceNttManagerAddress);

        // Compute manager message digest and record transceiver attestation.
        bytes32 nttManagerMessageHash = _recordTransceiverAttestation(sourceChainId, payload);

        if (isMessageApproved(nttManagerMessageHash)) {
            executeMsg(sourceChainId, sourceNttManagerAddress, payload);
        }
    }

    /// @inheritdoc INttManager
    function executeMsg(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        TransceiverStructs.NttManagerMessage memory message
    ) public whenNotPaused {
        (bytes32 digest, bool alreadyExecuted) =
            _isMessageExecuted(sourceChainId, sourceNttManagerAddress, message);

        if (alreadyExecuted) {
            return;
        }

        TransceiverStructs.NativeTokenTransfer memory nativeTokenTransfer =
            TransceiverStructs.parseNativeTokenTransfer(message.payload);

        // verify that the destination chain is valid
        if (nativeTokenTransfer.toChain != chainId) {
            revert InvalidTargetChain(nativeTokenTransfer.toChain, chainId);
        }
        uint8 toDecimals = tokenDecimals();
        TrimmedAmount nativeTransferAmount =
            (nativeTokenTransfer.amount.untrim(toDecimals)).trim(toDecimals, toDecimals);

        address transferRecipient = fromWormholeFormat(nativeTokenTransfer.to);

        {
            // Check inbound rate limits
            bool isRateLimited = _isInboundAmountRateLimited(nativeTransferAmount, sourceChainId);
            if (isRateLimited) {
                // queue up the transfer
                _enqueueInboundTransfer(digest, nativeTransferAmount, transferRecipient);

                // end execution early
                return;
            }
        }

        // consume the amount for the inbound rate limit
        _consumeInboundAmount(nativeTransferAmount, sourceChainId);
        // When receiving a transfer, we refill the outbound rate limit
        // by the same amount (we call this "backflow")
        _backfillOutboundAmount(nativeTransferAmount);

        _mintOrUnlockToRecipient(digest, transferRecipient, nativeTransferAmount, false);
    }

    /// @inheritdoc INttManager
    function completeInboundQueuedTransfer(
        bytes32 digest
    ) external nonReentrant whenNotPaused {
        // find the message in the queue
        InboundQueuedTransfer memory queuedTransfer = getInboundQueuedTransfer(digest);
        if (queuedTransfer.txTimestamp == 0) {
            revert InboundQueuedTransferNotFound(digest);
        }

        // check that > RATE_LIMIT_DURATION has elapsed
        if (block.timestamp - queuedTransfer.txTimestamp < rateLimitDuration) {
            revert InboundQueuedTransferStillQueued(digest, queuedTransfer.txTimestamp);
        }

        // remove transfer from the queue
        delete _getInboundQueueStorage()[digest];

        // run it through the mint/unlock logic
        _mintOrUnlockToRecipient(digest, queuedTransfer.recipient, queuedTransfer.amount, false);
    }

    /// @inheritdoc INttManager
    function completeOutboundQueuedTransfer(
        uint64 messageSequence
    ) external payable nonReentrant whenNotPaused returns (uint64) {
        // find the message in the queue
        OutboundQueuedTransfer memory queuedTransfer = _getOutboundQueueStorage()[messageSequence];
        if (queuedTransfer.txTimestamp == 0) {
            revert OutboundQueuedTransferNotFound(messageSequence);
        }

        // check that > RATE_LIMIT_DURATION has elapsed
        if (block.timestamp - queuedTransfer.txTimestamp < rateLimitDuration) {
            revert OutboundQueuedTransferStillQueued(messageSequence, queuedTransfer.txTimestamp);
        }

        // remove transfer from the queue
        delete _getOutboundQueueStorage()[messageSequence];

        // run it through the transfer logic and skip the rate limit
        return _transfer(
            messageSequence,
            queuedTransfer.amount,
            queuedTransfer.recipientChain,
            queuedTransfer.recipient,
            queuedTransfer.refundAddress,
            queuedTransfer.sender,
            queuedTransfer.transceiverInstructions
        );
    }

    /// @inheritdoc INttManager
    function cancelOutboundQueuedTransfer(
        uint64 messageSequence
    ) external nonReentrant whenNotPaused {
        // find the message in the queue
        OutboundQueuedTransfer memory queuedTransfer = _getOutboundQueueStorage()[messageSequence];
        if (queuedTransfer.txTimestamp == 0) {
            revert OutboundQueuedTransferNotFound(messageSequence);
        }

        // check msg.sender initiated the transfer
        if (queuedTransfer.sender != msg.sender) {
            revert CancellerNotSender(msg.sender, queuedTransfer.sender);
        }

        // remove transfer from the queue
        delete _getOutboundQueueStorage()[messageSequence];

        // return the queued funds to the sender
        _mintOrUnlockToRecipient(
            bytes32(uint256(messageSequence)), msg.sender, queuedTransfer.amount, true
        );
    }

    // ==================== Internal Business Logic =========================================

    function _transfer(
        uint64 sequence,
        TrimmedAmount amount,
        uint16 recipientChain,
        bytes32 recipient,
        bytes32 refundAddress,
        address sender,
        bytes memory transceiverInstructions
    ) internal returns (uint64 msgSequence) {
        // verify chain has not forked
        checkFork(evmChainId);

        (
            address[] memory enabledTransceivers,
            TransceiverStructs.TransceiverInstruction[] memory instructions,
            uint256[] memory priceQuotes,
            uint256 totalPriceQuote
        ) = _prepareForTransfer(recipientChain, transceiverInstructions);

        // push it on the stack again to avoid a stack too deep error
        uint64 seq = sequence;

        TransceiverStructs.NativeTokenTransfer memory ntt = TransceiverStructs.NativeTokenTransfer(
            amount, toWormholeFormat(token), recipient, recipientChain
        );

        // construct the NttManagerMessage payload
        bytes memory encodedNttManagerPayload = TransceiverStructs.encodeNttManagerMessage(
            TransceiverStructs.NttManagerMessage(
                bytes32(uint256(seq)),
                toWormholeFormat(sender),
                TransceiverStructs.encodeNativeTokenTransfer(ntt)
            )
        );

        // push onto the stack again to avoid stack too deep error
        uint16 destinationChain = recipientChain;

        // send the message
        _sendMessageToTransceivers(
            recipientChain,
            refundAddress,
            _getPeersStorage()[destinationChain].peerAddress,
            priceQuotes,
            instructions,
            enabledTransceivers,
            encodedNttManagerPayload
        );

        // push it on the stack again to avoid a stack too deep error
        TrimmedAmount amt = amount;

        emit TransferSent(
            recipient,
            refundAddress,
            amt.untrim(tokenDecimals()),
            totalPriceQuote,
            destinationChain,
            seq
        );

        // return the sequence number
        return seq;
    }

    function _mintOrUnlockToRecipient(
        bytes32 digest,
        address recipient,
        TrimmedAmount amount,
        bool cancelled
    ) internal {
        // verify chain has not forked
        checkFork(evmChainId);

        // calculate proper amount of tokens to unlock/mint to recipient
        // untrim the amount
        uint256 untrimmedAmount = amount.untrim(tokenDecimals());

        if (cancelled) {
            emit OutboundTransferCancelled(uint256(digest), recipient, untrimmedAmount);
        } else {
            emit TransferRedeemed(digest);
        }

        if (mode == Mode.LOCKING) {
            // unlock tokens to the specified recipient
            IERC20(token).safeTransfer(recipient, untrimmedAmount);
        } else if (mode == Mode.BURNING) {
            // mint tokens to the specified recipient
            INttToken(token).mint(recipient, untrimmedAmount);
        } else {
            revert InvalidMode(uint8(mode));
        }
    }

    function tokenDecimals() public view override(INttManager, RateLimiter) returns (uint8) {
        (bool success, bytes memory queriedDecimals) =
            token.staticcall(abi.encodeWithSignature("decimals()"));

        if (!success) {
            revert StaticcallFailed();
        }

        return abi.decode(queriedDecimals, (uint8));
    }

    // ==================== Internal Helpers ===============================================

    /// @dev Verify that the peer address saved for `sourceChainId` matches the `peerAddress`.
    function _verifyPeer(uint16 sourceChainId, bytes32 peerAddress) internal view {
        if (_getPeersStorage()[sourceChainId].peerAddress != peerAddress) {
            revert InvalidPeer(sourceChainId, peerAddress);
        }
    }

    function _trimTransferAmount(
        uint256 amount,
        uint16 toChain
    ) internal view returns (TrimmedAmount) {
        uint8 toDecimals = _getPeersStorage()[toChain].tokenDecimals;

        if (toDecimals == 0) {
            revert InvalidPeerDecimals();
        }

        TrimmedAmount trimmedAmount;
        {
            uint8 fromDecimals = tokenDecimals();
            trimmedAmount = amount.trim(fromDecimals, toDecimals);
            // don't deposit dust that can not be bridged due to the decimal shift
            uint256 newAmount = trimmedAmount.untrim(fromDecimals);
            if (amount != newAmount) {
                revert TransferAmountHasDust(amount, amount - newAmount);
            }
        }

        return trimmedAmount;
    }

    function _getTokenBalanceOf(
        address tokenAddr,
        address accountAddr
    ) internal view returns (uint256) {
        (bool success, bytes memory queriedBalance) =
            tokenAddr.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, accountAddr));

        if (!success) {
            revert StaticcallFailed();
        }

        return abi.decode(queriedBalance, (uint256));
    }
}
