// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {BuilderCodes} from "../BuilderCodes.sol";

/// @notice Pseudo-random registrar for referral codes
///
/// @dev Generates unique referral codes using a pseudo-random algorithm
///
/// @author Coinbase
contract PseudoRandomRegistrar {
    /// @notice Prefix for new permissionless referral codes
    string public constant PREFIX = "rnd_";

    /// @notice Prefix for new permissionless referral codes
    string public constant ALPHANUMERIC = "0123456789abcdefghijklmonpqrstuvwxyz";

    /// @notice Default length of new permissionless referral codes
    uint256 public constant SUFFIX_LENGTH = 8;

    /// @notice Referral codes contract
    BuilderCodes public immutable codes;

    /// @notice Nonce for generating unique referral codes
    uint256 public nonce;

    /// @notice Constructor for PseudoRandomRegistrar
    ///
    /// @param codes_ Address of the BuilderCodes contract
    constructor(address codes_) {
        codes = BuilderCodes(codes_);
    }

    /// @notice Registers a new referral code in the system
    ///
    /// @param payoutAddress Default payout address for all chains
    function register(address payoutAddress) external returns (string memory code) {
        // Generate unique referral code by looping until we find an unused one
        do {
            code = computeCode(++nonce);
        } while (!codes.isValidCode(code) || codes.isRegistered(code));

        codes.register(code, msg.sender, payoutAddress);
    }

    /// @notice Generates a unique code for a referral code
    ///
    /// @param nonceValue Nonce value to generate a code from
    ///
    /// @return code Referral code for the referral code
    function computeCode(uint256 nonceValue) public view returns (string memory code) {
        bytes memory allowedCharacters = bytes(ALPHANUMERIC);
        uint256 len = allowedCharacters.length;
        bytes memory suffix = new bytes(SUFFIX_LENGTH);

        // Iteratively generate code with modulo arithmetic on pseudo-random hash
        uint256 hashNum = uint256(
            keccak256(abi.encodePacked(nonceValue, block.timestamp, blockhash(block.number - 1), block.prevrandao))
        );
        for (uint256 i; i < SUFFIX_LENGTH; i++) {
            suffix[i] = allowedCharacters[hashNum % len];
            hashNum /= len;
        }

        return string.concat(PREFIX, string(suffix));
    }
}
