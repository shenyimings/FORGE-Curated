// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MessageBridgeProver} from "../prover/MessageBridgeProver.sol";
import {IProver} from "../interfaces/IProver.sol";
import {IMessageBridgeProver} from "../interfaces/IMessageBridgeProver.sol";

/**
 * @title TestMessageBridgeProver
 * @notice Test implementation of MessageBridgeProver for unit testing
 * @dev Focuses on testing the MessageBridgeProver interface and whitelist functionality
 */
contract TestMessageBridgeProver is MessageBridgeProver {
    // Track dispatch state for testing
    bool public dispatched = false;
    uint256 public dispatchCallCount = 0;

    // Fee configuration for testing
    uint256 public feeAmount = 100000;

    // No events needed for testing

    constructor(
        address _portal,
        bytes32[] memory _provers,
        uint256 _gasLimit
    ) MessageBridgeProver(_portal, _provers, _gasLimit) {}

    /**
     * @notice Legacy test method for backward compatibility
     * @dev This method exists only for test compatibility with old code
     * In production code, always use isWhitelisted() directly instead of this method
     * @param _prover Address of the prover to test whitelisting for
     * @return Whether the prover is whitelisted
     * @custom:deprecated Use isWhitelisted() instead
     */
    function isAddressWhitelisted(
        address _prover
    ) external view returns (bool) {
        return isWhitelisted(bytes32(uint256(uint160(_prover))));
    }

    /**
     * @notice Test helper to access the whitelist
     * @return Array of all addresses in the whitelist
     */
    function getWhitelistedAddresses()
        external
        view
        returns (address[] memory)
    {
        bytes32[] memory whitelistBytes32 = getWhitelist();
        address[] memory whitelistAddresses = new address[](
            whitelistBytes32.length
        );

        for (uint256 i = 0; i < whitelistBytes32.length; i++) {
            whitelistAddresses[i] = address(bytes20(whitelistBytes32[i]));
        }

        return whitelistAddresses;
    }

    // No custom events needed for testing

    /**
     * @notice Mock implementation of prove
     * @dev Simply processes the proofs without actual dispatch
     */
    function prove(
        address _sender,
        uint64,
        bytes calldata _encodedProofs,
        bytes calldata /* _data */
    ) external payable override {
        // Basic validation - the message includes 8 bytes chain ID + proof pairs
        if (_encodedProofs.length < 8) {
            revert IMessageBridgeProver.InvalidProofMessage();
        }
        if ((_encodedProofs.length - 8) % 64 != 0) {
            revert IProver.ArrayLengthMismatch();
        }

        // Process the intent proofs using the base implementation
        _handleCrossChainMessage(
            bytes32(uint256(uint160(_sender))),
            _encodedProofs
        );

        // For testing, we don't actually dispatch, just mark it
        dispatched = true;
        dispatchCallCount++;
    }

    /**
     * @notice Mock implementation of fetchFee
     * @dev Returns a fixed fee amount for testing
     */
    function fetchFee(
        uint64 /* domainID */,
        bytes calldata /* _encodedProofs */,
        bytes calldata /* _data */
    ) public view override returns (uint256) {
        return feeAmount;
    }

    /**
     * @notice Mock implementation of _dispatchMessage
     * @dev Just tracks that dispatch was called
     */
    function _dispatchMessage(
        uint64 /* domainID */,
        bytes calldata /* encodedProofs */,
        bytes calldata /* data */,
        uint256 /* fee */
    ) internal override {
        dispatched = true;
        dispatchCallCount++;
    }

    /**
     * @notice Helper to manually add proven intents for testing
     */
    function addProvenIntent(
        bytes32 _hash,
        address _claimant,
        uint64 _destination
    ) public {
        _provenIntents[_hash] = ProofData({
            claimant: _claimant,
            destination: _destination
        });
    }

    /**
     * @notice Helper to set fee amount for testing
     */
    function setFeeAmount(uint256 _feeAmount) public {
        feeAmount = _feeAmount;
    }

    /**
     * @notice Helper to reset dispatch state for testing
     */
    function resetDispatchState() public {
        dispatched = false;
        dispatchCallCount = 0;
    }

    /**
     * @notice Implementation of getProofType from IProver
     * @return String indicating the proving mechanism used
     */
    function getProofType() external pure override returns (string memory) {
        return "TestMessageBridgeProver";
    }

    function version() external pure returns (string memory) {
        return "test";
    }
}
