pragma solidity >=0.8.8 <0.9.0;

import "../src/NttManager/NttManager.sol";
import "../src/mocks/DummyToken.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../src/interfaces/IManagerBase.sol";
import "../src/interfaces/INttManager.sol";
import "../src/interfaces/IRateLimiter.sol";
import "../src/NttManager/TransceiverRegistry.sol";
import "../src/libraries/external/OwnableUpgradeable.sol";
import "../src/libraries/TransceiverStructs.sol";
import "./helpers/FuzzingHelpers.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "solidity-bytes-utils/BytesLib.sol";
import "../test/mocks/DummyTransceiver.sol";
import "wormhole-solidity-sdk/Utils.sol";

contract FuzzNttManager is FuzzingHelpers {
    uint64[] queuedOutboundTransfersArray;
    mapping(uint64 => bool) queuedOutboundTransfers;
    mapping(uint256 => bool) executedQueuedOutboundTransfers;
    
    // Keep track of transceiver state
    uint256 numRegisteredTransceivers;
    uint256 numEnabledTransceivers;
    mapping(address => bool) isTransceiverRegistered;
    mapping(address => bool) isTransceiverEnabled;
    address[] registeredTransceivers;

    // Instructions
    uint256 constant numTransceiverInstructions = 10; // It takes some time to generate the instructions so let's use 10 as a default
    bytes[] orderedInstructions;
    bytes[] unorderedInstructions;


    NttManager nttManager;
    DummyToken dummyToken;
    DummyTransceiver dummyTransceiver;

    constructor() {
        _initialManagerSetup();
        _generateMultipleTransceiverInstructions(numTransceiverInstructions);
        
        dummyToken.mintDummy(address(this), type(uint256).max);
        IERC20(dummyToken).approve(address(nttManager), type(uint256).max);
    }

    function canOnlyPlayQueuedOutboundTransferOnce(uint256 warpTime, uint64 messageSequence, bool pickQueuedSequence) public {
        if (pickQueuedSequence) {
            messageSequence = queuedOutboundTransfersArray[clampBetween(uint256(messageSequence), 0, queuedOutboundTransfersArray.length)];
        }

        IRateLimiter.OutboundQueuedTransfer memory queuedTransfer = nttManager.getOutboundQueuedTransfer(messageSequence);
        
        warpTime = clampBetween(warpTime, 0, 365 days);
        uint64 newTimestamp = uint64(block.timestamp + warpTime); // We can safely cast here as the warp is clamped
        hevm.warp(newTimestamp);

        uint256 currentOutboundCapacity = nttManager.getCurrentOutboundCapacity();
        uint256 currentInboundCapacity = nttManager.getCurrentInboundCapacity(queuedTransfer.recipientChain);

        try nttManager.completeOutboundQueuedTransfer(messageSequence) {
            // Rate limits stay untouched
            assertWithMsg(
                currentOutboundCapacity == nttManager.getCurrentOutboundCapacity() &&
                currentInboundCapacity == nttManager.getCurrentInboundCapacity(queuedTransfer.recipientChain),
                "NttManager: completeOutboundQueuedTransfer expected not to change rate limit capacity"
            );

            // Set that this message sequence has been played
            executedQueuedOutboundTransfers[messageSequence] = true;
        }
        catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            // If the message has been executed before it shouldn't be found again
            if (executedQueuedOutboundTransfers[messageSequence]) {
                assertWithMsg(
                    errorSelector == selectorToUint(IRateLimiter.OutboundQueuedTransferNotFound.selector),
                    "NttManager: completeOutboundQueuedTransfer expected to fail if not found"
                );
            }

            if (queuedTransfer.txTimestamp == 0) {
                assertWithMsg(
                    errorSelector == selectorToUint(IRateLimiter.OutboundQueuedTransferNotFound.selector),
                    "NttManager: completeOutboundQueuedTransfer expected to fail if not found"
                );
            }
            else if (newTimestamp - queuedTransfer.txTimestamp < 1 days) {
                assertWithMsg(
                    errorSelector == selectorToUint(IRateLimiter.OutboundQueuedTransferStillQueued.selector),
                    "NttManager: completeOutboundQueuedTransfer expected to fail if not queued for long enough"
                );
            }
            else if (errorSelector == selectorToUint(TransceiverStructs.InvalidInstructionIndex.selector)) {
                TransceiverStructs.TransceiverInstruction[] memory instructions = 
                    TransceiverStructs.parseTransceiverInstructions(queuedTransfer.transceiverInstructions, numRegisteredTransceivers);
                for (uint256 i = 0; i < instructions.length; ++i) {
                    if (instructions[i].index < numRegisteredTransceivers) {
                        assertWithMsg(
                            false,
                            "NttManager: transfer should not fail if instruction index is in bounds"
                        );
                    }
                }
            }
            else if (numEnabledTransceivers == 0) {
                // In this case the sender should be able to cancel their outbound queued transfer
                try nttManager.cancelOutboundQueuedTransfer(messageSequence) {
                    // Set that this message sequence has been played
                    executedQueuedOutboundTransfers[messageSequence] = true;
                }
                catch {
                    assertWithMsg(
                        false,
                        "NttManager: cancelOutboundQueuedTransfer unexpected revert"
                    );
                }
            }
            else {
                assertWithMsg(
                    false,
                    "NttManager: completeOutboundQueuedTransfer unexpected revert"
                );
            }

        }
    }

    function cancelOutboundQueuedTransfer(bool pickQueuedSequence, uint64 messageSequence, address sender) public {
        if (pickQueuedSequence) {
            messageSequence = queuedOutboundTransfersArray[clampBetween(uint256(messageSequence), 0, queuedOutboundTransfersArray.length)];
        }

        IRateLimiter.OutboundQueuedTransfer memory queuedTransfer = nttManager.getOutboundQueuedTransfer(messageSequence);

        uint256 nttManagerBalanceBefore = IERC20(dummyToken).balanceOf(address(nttManager));
        uint256 senderBalanceBefore = IERC20(dummyToken).balanceOf(address(queuedTransfer.sender));
        uint8 decimals = ERC20(dummyToken).decimals();
        uint256 amount = TrimmedAmountLib.untrim(queuedTransfer.amount, decimals);

        hevm.prank(sender);
        try nttManager.cancelOutboundQueuedTransfer(messageSequence) {
            assert(IERC20(dummyToken).balanceOf(address(queuedTransfer.sender)) == senderBalanceBefore + amount);
            assert(IERC20(dummyToken).balanceOf(address(nttManager)) == nttManagerBalanceBefore - amount);

            // Set that this message sequence has been played since this has the same effect as executing an outbound transfer
            executedQueuedOutboundTransfers[messageSequence] = true;
        }
        catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            if (executedQueuedOutboundTransfers[messageSequence] || !queuedOutboundTransfers[messageSequence]) {
                assertWithMsg(
                    errorSelector == selectorToUint(IRateLimiter.OutboundQueuedTransferNotFound.selector),
                    "NttManager: cancelOutboundQueuedTransfer expected to fail if not found or already executed/cancelled"
                );
            }
            else if (sender != queuedTransfer.sender) {
                assertWithMsg(
                    errorSelector == selectorToUint(INttManager.CancellerNotSender.selector),
                    "NttManager: cancelOutboundQueuedTransfer expected to fail if called by a different sender"
                );
            }
            else {
                assertWithMsg(
                    false,
                    "NttManager: cancelOutboundQueuedTransfer unexpected revert"
                );
            }
        }
    }

    function setPeer(uint16 peerChainId,
        bytes32 peerContract,
        uint8 decimals,
        uint256 inboundLimit,
        bool clampLimit
    ) public {
        uint8 localDecimals = ERC20(dummyToken).decimals();
        if (clampLimit) inboundLimit = clampBetween(inboundLimit, 0, type(uint64).max * 10 ** (localDecimals - minUint8(8, localDecimals)));

        try nttManager.setPeer(peerChainId, peerContract, decimals, inboundLimit) {

        }
        catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);
            
            if (peerChainId == 0) {
                assertWithMsg(
                    errorSelector == selectorToUint(INttManager.InvalidPeerChainIdZero.selector),
                    "NttManager: setPeer expected to fail if setting zero peer chain id"
                );
            }
            else if (peerContract == bytes32(0)) {
                assertWithMsg(
                    errorSelector == selectorToUint(INttManager.InvalidPeerZeroAddress.selector),
                    "NttManager: setPeer expected to fail if setting zero peer contract address"
                );
            }
            else if (decimals == 0) {
                assertWithMsg(
                    errorSelector == selectorToUint(INttManager.InvalidPeerDecimals.selector),
                    "NttManager: setPeer expected to fail if setting zero peer decimals"
                );
            }
            // We set the chain id to 1 when we set up the manager
            else if (peerChainId == 1) {
                assertWithMsg(
                    errorSelector == selectorToUint(INttManager.InvalidPeerSameChainId.selector),
                    "NttManager: setPeer expected to fail if setting for the same chain id"
                );
            }
            else if (!clampLimit) {
                bytes32 errorStringHash = extractErrorString(revertData);
                assertWithMsg(
                    errorStringHash == keccak256(abi.encodePacked("SafeCast: value doesn't fit in 64 bits")),
                    "NttManager: setPeer expected to fail if setting too large an inbound limit"
                );
            }
            else {
                assertWithMsg(
                    false,
                    "NttManager: setPeer unexpected revert"
                );
            }
        }
    }

    function setOutboundLimit(uint256 limit, bool clampLimit) public {
        uint8 localDecimals = ERC20(dummyToken).decimals();
        if (clampLimit) limit = clampBetween(limit, 0, type(uint64).max * 10 ** (localDecimals - minUint8(8, localDecimals)));
        
        try nttManager.setOutboundLimit(limit) {

        }
        catch (bytes memory revertData) {
            if (!clampLimit) {
                bytes32 errorStringHash = extractErrorString(revertData);
                assertWithMsg(
                    errorStringHash == keccak256(abi.encodePacked("SafeCast: value doesn't fit in 64 bits")),
                    "NttManager: setOutboundLimit expected to fail if setting too large a limit"
                );
            }
            else {
                assertWithMsg(
                    false,
                    "NttManager: setOutboundLimit unexpected revert"
                );
            }
        }
    }

    function setInboundLimit(uint256 limit, uint16 chainId, bool clampLimit) public {
        uint8 localDecimals = ERC20(dummyToken).decimals();
        if (clampLimit) limit = clampBetween(limit, 0, type(uint64).max * 10 ** (localDecimals - minUint8(8, localDecimals)));
        
        try nttManager.setInboundLimit(limit, chainId) {

        }
        catch (bytes memory revertData) {
            if (!clampLimit) {
                bytes32 errorStringHash = extractErrorString(revertData);
                assertWithMsg(
                    errorStringHash == keccak256(abi.encodePacked("SafeCast: value doesn't fit in 64 bits")),
                    "NttManager: setInboundLimit expected to fail if setting too large a limit"
                );
            }
            else {
                assertWithMsg(
                    false,
                    "NttManager: setInboundLimit unexpected revert"
                );
            }
        }
    }

    function setTransceiver(bool newTransceiver, uint256 transceiverIndex) public {
        address transceiver;
        
        if (newTransceiver) {
            DummyTransceiver newDummyTransceiver = new DummyTransceiver(address(nttManager));
            transceiver = address(newDummyTransceiver);
        }
        else {
            transceiverIndex = clampBetween(transceiverIndex, 0, registeredTransceivers.length - 1);
            transceiver = registeredTransceivers[transceiverIndex];
        }
        
        try nttManager.setTransceiver(transceiver) {
            // We only set these if the transceiver wasn't registered before
            if (!isTransceiverRegistered[transceiver]) {
                isTransceiverRegistered[transceiver] = true;
                registeredTransceivers.push(transceiver);
                numRegisteredTransceivers++;
            }

            isTransceiverEnabled[transceiver] = true;
            numEnabledTransceivers++;
        }
        catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            if (isTransceiverRegistered[transceiver]) {
                assertWithMsg(
                    errorSelector == selectorToUint(TransceiverRegistry.TransceiverAlreadyEnabled.selector),
                    "NttManager: setTransceiver expected to fail if enabling an already enabled transceiver"
                );
            }
            else if (transceiver == address(0)) {
                assertWithMsg(
                    errorSelector == selectorToUint(TransceiverRegistry.InvalidTransceiverZeroAddress.selector),
                    "NttManager: setTransceiver expected to fail if registering the 0 address"
                );
            }
            else if (numRegisteredTransceivers >= 64) {
                assertWithMsg(
                    errorSelector == selectorToUint(TransceiverRegistry.TooManyTransceivers.selector),
                    "NttManager: setTransceiver expected to fail if registering too many transceivers"
                );
            }
            else {
                assertWithMsg(
                    false,
                    "NttManager: setTransceiver unexpected revert"
                );
            }
        }
    }

    function removeTransceiver(bool registeredTransceiver, uint256 transceiverIndex) public {
        address transceiver;
        
        if (registeredTransceiver) {
            transceiverIndex = clampBetween(transceiverIndex, 0, registeredTransceivers.length - 1);
            transceiver = registeredTransceivers[transceiverIndex];
        }
        else {
            transceiver = address(uint160(transceiverIndex));
        }

        try nttManager.removeTransceiver(transceiver) {
            isTransceiverEnabled[transceiver] = false;
            numEnabledTransceivers--;
        }
        catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            if (transceiver == address(0)) {
                assertWithMsg(
                    errorSelector == selectorToUint(TransceiverRegistry.InvalidTransceiverZeroAddress.selector),
                    "NttManager: removeTransceiver expected to fail if removing the 0 address"
                );
            }
            else if (!isTransceiverRegistered[transceiver]) {
                assertWithMsg(
                    errorSelector == selectorToUint(TransceiverRegistry.NonRegisteredTransceiver.selector),
                    "NttManager: removeTransceiver expected to fail if removing a non-registered transceiver"
                );
            }
            else if (!isTransceiverEnabled[transceiver]) {
                assertWithMsg(
                    errorSelector == selectorToUint(TransceiverRegistry.DisabledTransceiver.selector),
                    "NttManager: removeTransceiver expected to fail if removing an already disabled transceiver"
                );
            }
            else if (numEnabledTransceivers == 1) {
                assertWithMsg(
                    errorSelector == selectorToUint(IManagerBase.ZeroThreshold.selector),
                    "NttManager: removeTransceiver expected to fail if trying to remove the last enabled transceiver"
                );
            }
            else {
                assertWithMsg(
                    false,
                    "NttManager: removeTransceiver unexpected revert"
                );
            }
        }
    }

    function setThreshold(uint8 threshold) public {
        try nttManager.setThreshold(threshold) {

        }
        catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            if (threshold == 0) {
                assertWithMsg(
                    errorSelector == selectorToUint(IManagerBase.ZeroThreshold.selector),
                    "NttManager: setThreshold expected to fail if setting threshold to 0"
                );
            }
            else if (threshold > numEnabledTransceivers) {
                assertWithMsg(
                    errorSelector == selectorToUint(IManagerBase.ThresholdTooHigh.selector),
                    "NttManager: setThreshold expected to fail if trying to set threshold above num enabled transceivers"
                );
            }
            else {
                assertWithMsg(
                    false,
                    "NttManager: setThreshold unexpected revert"
                );
            }
        }
    }

    /// INTERNAL METHODS

    function _initialManagerSetup() internal {
        // Deploy an NTT token
        dummyToken = new DummyToken();
        // Deploy an implementation of the manager
        NttManager implementation = new NttManager(address(dummyToken), IManagerBase.Mode.LOCKING, 1, 1 days, false);
        // Place the manager behind a proxy
        nttManager = NttManager(address(new ERC1967Proxy(address(implementation), "")));
        // Initialize the proxy
        nttManager.initialize();
    }

    function _psuedoRandomNumber(uint256 seed) internal returns(uint256) {
        return uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, seed)));
    }

    function _generateMultipleTransceiverInstructions(uint256 num) internal {
        for (uint256 i = 0; i < num; ++i) {
            _generateTransceiverInstructions(true, i);
            _generateTransceiverInstructions(false, i);
        }
    }

    function _generateTransceiverInstructions(bool isOrdered, uint256 seed) internal {
        bytes memory encodedInstructions;
        uint256 numInstructions = clampBetween(_psuedoRandomNumber(seed), 0, type(uint8).max);
        
        TransceiverStructs.TransceiverInstruction[] memory instructions = new TransceiverStructs.TransceiverInstruction[](numInstructions);

        uint256 previousIndex = 0;

        for (uint256 i = 0; i < uint256(numInstructions); ++i) {
            // We've run out of room to still be ordered
            if (previousIndex >= type(uint8).max - 1 && isOrdered) {
                break;
            }

            uint256 newIndex = _psuedoRandomNumber(i);

            if (isOrdered) {
                newIndex = clampBetween(newIndex, previousIndex + 1, type(uint8).max);
            }
            else {
                newIndex = clampBetween(newIndex, 0, type(uint8).max);
            }

            TransceiverStructs.TransceiverInstruction memory instruction = TransceiverStructs.TransceiverInstruction({
                index: uint8(newIndex),
                payload: new bytes(newIndex) // We generate an arbitrary length byte array (of zeros for now)
            });

            instructions[i] = instruction;

            previousIndex = newIndex;
        }

        encodedInstructions = TransceiverStructs.encodeTransceiverInstructions(instructions);

        if (isOrdered) {
            orderedInstructions.push(encodedInstructions);
        }
        else {
            unorderedInstructions.push(encodedInstructions);
        }
    }
}