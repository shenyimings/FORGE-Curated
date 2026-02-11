// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TokenHelper, TokenInterface} from "../../../libraries/TokenHelper.sol";

/**
 * @title IAirdrop
 * @author Tadle Team
 * @notice Interface for interacting with the Airdrop contract
 * @dev Provides functionality to query user claimed amounts
 */
interface IAirdrop {
    /// @notice Get the amount of tokens claimed by a user
    /// @param user Address of the user
    /// @param token Address of the token
    /// @return Amount of tokens claimed by the user
    function getUserClaimedAmount(
        address user,
        address token
    ) external view returns (uint256);
}

/**
 * @title IValidator
 * @notice Interface for validator contract
 * @dev Provides token whitelist verification functionality
 */
interface IValidator {
    /// @notice Verify if a validator is authorized for a specific key
    /// @param _key The validation key
    /// @param _validator The validator address to check
    /// @return True if validator is authorized, false otherwise
    function verify(
        bytes32 _key,
        address _validator
    ) external view returns (bool);
}

/**
 * @title AccountManagerResolver
 * @author Tadle Team
 * @notice Contract for managing account operations and asset withdrawals
 * @dev Handles secure token withdrawals with airdrop claim validation and whitelist checks
 * @custom:security Implements balance validation and whitelist verification
 */
contract AccountManagerResolver {
    /// @dev Address of the airdrop contract for claim validation
    /// @notice Immutable reference to airdrop contract
    address public immutable airdropAddress;

    /// @dev Address of the validator contract for whitelist checks
    /// @notice Immutable reference to validator contract
    address public immutable validatorAddress;

    /// @dev Ethereum token address representation
    /// @notice Standard ETH address used across the protocol
    address internal constant ethAddr =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev Key for token whitelist validation
    /// @notice Used to verify if tokens are approved for withdrawal
    bytes32 internal constant VALIDATOR_TOKEN_WHITELIST_KEY =
        keccak256("account-manager-token-whitelist");

    /**
     * @dev Constructor to initialize contract addresses
     * @param _airdropAddress Address of the airdrop contract
     * @param _validatorAddress Address of the validator contract
     * @notice Sets up the resolver with required system contracts
     * @custom:validation Addresses can be zero for optional functionality
     */
    constructor(address _airdropAddress, address _validatorAddress) {
        airdropAddress = _airdropAddress;
        validatorAddress = _validatorAddress;
    }

    /**
     * @dev Withdraw assets from the smart account
     * @param token Address of the token to withdraw (ethAddr for ETH)
     * @param amt Amount of tokens to withdraw
     * @param to Recipient address
     * @return _eventName Name of the event emitted
     * @return _eventParam Encoded event parameters
     * @notice Securely withdraws tokens with validation checks
     * @custom:validation Validates recipient, amount, and token whitelist
     * @custom:security Checks airdrop claims for ETH withdrawals
     * @custom:access-control Requires token to be whitelisted
     */
    function withdraw(
        address token,
        uint256 amt,
        address payable to
    )
        external
        payable
        returns (string memory _eventName, bytes memory _eventParam)
    {
        // Validate input parameters
        require(
            to != address(0),
            "AccountManagerResolver: recipient address cannot be zero"
        );
        require(
            amt > 0,
            "AccountManagerResolver: withdrawal amount must be greater than zero"
        );

        // Verify token is whitelisted
        require(
            IValidator(validatorAddress).verify(
                VALIDATOR_TOKEN_WHITELIST_KEY,
                token
            ),
            "AccountManagerResolver: token not whitelisted for withdrawal"
        );

        // Check ETH balance considering airdrop claims
        if (token == ethAddr && airdropAddress != address(0)) {
            uint256 claimedAmount = IAirdrop(airdropAddress)
                .getUserClaimedAmount(address(this), ethAddr);
            require(
                address(this).balance >= claimedAmount + amt,
                "AccountManagerResolver: insufficient balance after airdrop claims"
            );
        }

        // Transfer tokens based on type
        if (token == ethAddr) {
            _safeTransferETH(to, amt);
        } else {
            _safeTransferERC20(token, to, amt);
        }

        // Return event data
        _eventName = "LogWithdraw(address,uint256,address)";
        _eventParam = abi.encode(token, amt, to);
    }

    /**
     * @dev Safely transfers ETH to a recipient
     * @param to Recipient address
     * @param amount Amount of ETH to transfer
     * @notice Uses low-level call for ETH transfer with failure handling
     * @custom:security Validates transfer success and reverts on failure
     */
    function _safeTransferETH(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        require(success, "AccountManagerResolver: ETH transfer failed");
    }

    /**
     * @dev Safely transfers ERC20 tokens to a recipient
     * @param token Address of the ERC20 token
     * @param to Recipient address
     * @param amount Amount of tokens to transfer
     * @notice Uses TokenHelper for safe ERC20 transfers
     * @custom:security Leverages battle-tested transfer helper
     */
    function _safeTransferERC20(
        address token,
        address to,
        uint256 amount
    ) internal {
        TokenHelper.safeTransfer(TokenInterface(token), to, amount);
    }
}

/**
 * @title ConnectV1AccountManager
 * @author Tadle Team
 * @notice Version 1.0.0 of the Account Manager connector
 * @dev Extends AccountManagerResolver with version identification
 * @custom:version 1.0.0
 */
contract ConnectV1AccountManager is AccountManagerResolver {
    string public constant name = "AccountManager-v1.0.0";

    /**
     * @dev Constructor to initialize contract addresses
     * @param _airdropAddress Address of the airdrop contract
     * @param _validatorAddress Address of the validator contract
     * @notice Sets up the connector with required system contracts
     * @custom:initialization Inherits validation from AccountManagerResolver
     */
    constructor(
        address _airdropAddress,
        address _validatorAddress
    ) AccountManagerResolver(_airdropAddress, _validatorAddress) {}
}
