// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/**
 * @title The contract handles whitelist related features
 * @notice The main functionalities are:
 * - Ownable: Add whitelisted/blacklisted addresses for senders and receivers
 * - Ownable: Set max ETH amount to buy (default 4 eth)
 * - Ownable: Set univ3 TWAP oracle
 * - Token contract `_beforeTokenTransfer` hook will call `checkWhitelist` function and this function will check if transfers are eligible
 */
contract Whitelist is Ownable {
    error SenderNotWhitelisted();
    error ReceiverNotWhitelisted();
    error Locked();
    error NotToken();
    error Blacklisted();
    error MaxAddressCapOverflow();

    /// @notice Maximum USDC amount to contribute (USDC has 6 decimals)
    uint256 private _maxAddressCap;
    /// @notice Flag for locked period
    bool private _locked;
    /// @notice Token token contract address
    address private _token;
    /// @notice Uniswap v3 TWAP oracle
    address private _oracle;
    /// @notice Uniswap v3 pool address
    address private _pool;
    /// @notice Total number of sender whitelisted addresses
    uint256 private _senderWhitelistCount;
    /// @notice Total number of receiver whitelisted addresses
    uint256 private _receiverWhitelistCount;
    /// @notice Max index allowed for sender whitelist
    uint256 private _allowedSenderWhitelistIndex;
    /// @notice Max index allowed for receiver whitelist
    uint256 private _allowedReceiverWhitelistIndex;
    /// @notice Sender whitelist index for each address
    mapping(address => uint256) private _senderWhitelistIndex;
    /// @notice Receiver whitelist index for each address
    mapping(address => uint256) private _receiverWhitelistIndex;
    /// @notice Mapping for blacklisted addresses
    mapping(address => bool) private _isBlacklisted;
    /// @notice Contributed USDC amounts
    mapping(address => uint256) private _contributed;

    /// @notice Set the default max address cap to 10,000 USDC (6 decimals) and lock token transfers initially
    constructor() Ownable(_msgSender()) {
        _maxAddressCap = 10_000 * 10 ** 6; // 10,000 USDC with 6 decimals
        _locked = true; // Initially, liquidity will be locked
        _allowedSenderWhitelistIndex = 0;
        _allowedReceiverWhitelistIndex = 0;
    }

    /// @notice Check if called from token contract.
    modifier onlyToken() {
        if (_msgSender() != _token) {
            revert NotToken();
        }
        _;
    }

    /// @notice Returns max address cap
    function maxAddressCap() external view returns (uint256) {
        return _maxAddressCap;
    }

    /// @notice Returns token address
    function token() external view returns (address) {
        return _token;
    }

    /// @notice Returns the sender whitelisted index. If not whitelisted, then it will be 0
    /// @param account The address to be checked
    function senderWhitelistIndex(address account) external view returns (uint256) {
        return _senderWhitelistIndex[account];
    }

    /// @notice Returns the receiver whitelisted index. If not whitelisted, then it will be 0
    /// @param account The address to be checked
    function receiverWhitelistIndex(address account) external view returns (uint256) {
        return _receiverWhitelistIndex[account];
    }

    /// @notice Returns if the account is blacklisted or not
    /// @param account The address to be checked
    function isBlacklisted(address account) external view returns (bool) {
        return _isBlacklisted[account];
    }

    /// @notice Returns Univ3 TWAP oracle address
    function oracle() external view returns (address) {
        return _oracle;
    }

    /// @notice Returns Univ3 pool address
    function pool() external view returns (address) {
        return _pool;
    }

    /// @notice Returns current sender whitelisted address count
    function senderWhitelistCount() external view returns (uint256) {
        return _senderWhitelistCount;
    }

    /// @notice Returns current receiver whitelisted address count
    function receiverWhitelistCount() external view returns (uint256) {
        return _receiverWhitelistCount;
    }

    /// @notice Returns current allowed sender whitelist index
    function allowedSenderWhitelistIndex() external view returns (uint256) {
        return _allowedSenderWhitelistIndex;
    }

    /// @notice Returns current allowed receiver whitelist index
    function allowedReceiverWhitelistIndex() external view returns (uint256) {
        return _allowedReceiverWhitelistIndex;
    }

    /// @notice Returns contributed ETH amount for address
    /// @param to The address to be checked
    function contributed(address to) external view returns (uint256) {
        return _contributed[to];
    }

    /// @notice If token transfer is locked or not
    function locked() external view returns (bool) {
        return _locked;
    }

    /// @notice Setter for locked flag
    /// @param newLocked New flag to be set
    function setLocked(bool newLocked) external onlyOwner {
        _locked = newLocked;
    }

    /// @notice Setter for max address cap
    /// @param newCap New cap for max ETH amount
    function setMaxAddressCap(uint256 newCap) external onlyOwner {
        _maxAddressCap = newCap;
    }

    /// @notice Setter for token
    /// @param newToken New token address
    function setToken(address newToken) external onlyOwner {
        _token = newToken;
    }

    /// @notice Setter for Univ3 TWAP oracle
    /// @param newOracle New oracle address
    function setOracle(address newOracle) external onlyOwner {
        _oracle = newOracle;
    }

    /// @notice Setter for Univ3 pool
    /// @param newPool New pool address
    function setPool(address newPool) external onlyOwner {
        _pool = newPool;
    }

    /// @notice Setter for blacklist
    /// @param blacklisted Address to be added
    /// @param flag New flag for address
    function setBlacklisted(address blacklisted, bool flag) external onlyOwner {
        _isBlacklisted[blacklisted] = flag;
    }

    /// @notice Setter for allowed sender whitelist index
    /// @param newIndex New index for allowed sender whitelist
    function setAllowedSenderWhitelistIndex(uint256 newIndex) external onlyOwner {
        _allowedSenderWhitelistIndex = newIndex;
    }

    /// @notice Setter for allowed receiver whitelist index
    /// @param newIndex New index for allowed receiver whitelist
    function setAllowedReceiverWhitelistIndex(uint256 newIndex) external onlyOwner {
        _allowedReceiverWhitelistIndex = newIndex;
    }

    /// @notice Add sender whitelisted address
    /// @param whitelisted Address to be added
    function addSenderWhitelistedAddress(address whitelisted) external onlyOwner {
        _addSenderWhitelistedAddress(whitelisted);
    }

    /// @notice Add receiver whitelisted address
    /// @param whitelisted Address to be added
    function addReceiverWhitelistedAddress(address whitelisted) external onlyOwner {
        _addReceiverWhitelistedAddress(whitelisted);
    }

    /// @notice Add batch sender whitelists
    /// @param whitelisted Array of addresses to be added
    function addBatchSenderWhitelist(address[] calldata whitelisted) external onlyOwner {
        for (uint256 i = 0; i < whitelisted.length; i++) {
            _addSenderWhitelistedAddress(whitelisted[i]);
        }
    }

    /// @notice Add batch receiver whitelists
    /// @param whitelisted Array of addresses to be added
    function addBatchReceiverWhitelist(address[] calldata whitelisted) external onlyOwner {
        for (uint256 i = 0; i < whitelisted.length; i++) {
            _addReceiverWhitelistedAddress(whitelisted[i]);
        }
    }

    /// @notice Check if addresses are eligible for whitelist
    /// @param from sender address
    /// @param to recipient address
    /// @param amount Number of tokens to be transferred
    /// @dev Check if both sender and receiver are whitelisted
    /// @dev Revert if locked, not whitelisted, blacklisted or already contributed more than capped amount
    /// @dev Update contributed amount
    function checkWhitelist(address from, address to, uint256 amount) external onlyToken {
        // Skip checks for transactions involving the owner
        if (from == owner() || to == owner()) {
            return;
        }

        // Check if sender is blacklisted
        if (_isBlacklisted[from]) {
            revert Blacklisted();
        }

        // Check if receiver is blacklisted
        if (_isBlacklisted[to]) {
            revert Blacklisted();
        }

        // If locked, only owner or whitelisted senders can transfer
        if (_locked) {
            // Owner check already handled above
            // Check if sender is on the sender whitelist
            if (
                _allowedSenderWhitelistIndex == 0 || _senderWhitelistIndex[from] == 0
                    || _senderWhitelistIndex[from] > _allowedSenderWhitelistIndex
            ) {
                revert Locked();
            }
            // In locked phase, whitelisted senders can send to anyone
            // No need to check receiver whitelist
            return;
        }

        // When unlocked (Phase 1)

        // Special handling for purchases from Uniswap pool
        if (from == _pool) {
            // Check if receiver is on the receiver whitelist
            if (
                _allowedReceiverWhitelistIndex == 0 || _receiverWhitelistIndex[to] == 0
                    || _receiverWhitelistIndex[to] > _allowedReceiverWhitelistIndex
            ) {
                revert ReceiverNotWhitelisted();
            }

            // Calculate equivalent USDC amount for token amount
            uint256 estimatedUSDCAmount = IOracle(_oracle).peek(amount);
            if (_contributed[to] + estimatedUSDCAmount > _maxAddressCap) {
                revert MaxAddressCapOverflow();
            }

            _contributed[to] += estimatedUSDCAmount;
            return;
        }

        // For non-pool transactions, check both sender and receiver whitelists
        // Check if sender is on the sender whitelist
        if (
            _allowedSenderWhitelistIndex == 0 || _senderWhitelistIndex[from] == 0
                || _senderWhitelistIndex[from] > _allowedSenderWhitelistIndex
        ) {
            revert SenderNotWhitelisted();
        }

        // Check if receiver is on the receiver whitelist
        if (
            _allowedReceiverWhitelistIndex == 0 || _receiverWhitelistIndex[to] == 0
                || _receiverWhitelistIndex[to] > _allowedReceiverWhitelistIndex
        ) {
            revert ReceiverNotWhitelisted();
        }
    }

    /// @notice Internal function used for sender whitelisting. Only increase whitelist count if address is not whitelisted before
    /// @param whitelisted Address to be added
    function _addSenderWhitelistedAddress(address whitelisted) private {
        if (_senderWhitelistIndex[whitelisted] == 0) {
            _senderWhitelistIndex[whitelisted] = ++_senderWhitelistCount;
        }
    }

    /// @notice Internal function used for receiver whitelisting. Only increase whitelist count if address is not whitelisted before
    /// @param whitelisted Address to be added
    function _addReceiverWhitelistedAddress(address whitelisted) private {
        if (_receiverWhitelistIndex[whitelisted] == 0) {
            _receiverWhitelistIndex[whitelisted] = ++_receiverWhitelistCount;
        }
    }
}
