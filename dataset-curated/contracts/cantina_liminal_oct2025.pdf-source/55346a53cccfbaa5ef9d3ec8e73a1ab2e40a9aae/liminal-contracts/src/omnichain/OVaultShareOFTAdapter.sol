// SPDX-License-Identifier: BUSL-1.1
// Terms: https://liminal.money/xtokens/license

pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {OFTAdapterUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";

/**
 * @title OVaultShareOFTAdapter
 * @notice OFT adapter for vault shares enabling cross-chain transfers
 * @dev The share token MUST be an OFT adapter (lockbox).
 * @dev A mint-burn adapter would not work since it transforms `ShareERC20::totalSupply()`
 */
contract OVaultShareOFTAdapter is OFTAdapterUpgradeable {
    /// @custom:storage-location erc7201:liminal.oVaultShareOFTAdapter.v1
    struct OVaultShareOFTAdapterStorage {
        /// @notice Blacklist mapping for addresses that cannot send or receive cross-chain transfers
        mapping(address => bool) blacklisted;
    }

    // keccak256(abi.encode(uint256(keccak256("liminal.storage.oVaultShareOFTAdapter.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OVAULT_SHARE_OFT_ADAPTER_STORAGE_LOCATION =
        0xad675e612cdf7b2e8029f936881f803c927289d8c260346dfda87182ab806600;

    function _getOVaultShareOFTAdapterStorage() private pure returns (OVaultShareOFTAdapterStorage storage $) {
        assembly {
            $.slot := OVAULT_SHARE_OFT_ADAPTER_STORAGE_LOCATION
        }
    }

    /// Events
    event Blacklisted(address indexed account);
    event Unblacklisted(address indexed account);

    constructor(address _token, address _lzEndpoint) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        require(_lzEndpoint != address(0), "lzEndpoint is required");
        _disableInitializers();
    }

    /**
     * @notice Creates a new OFT adapter for vault shares
     * @dev Sets up cross-chain token transfer capabilities for vault shares
     * @param _owner The account with administrative privileges
     */
    function initialize(address _owner) public initializer {
        __OFTAdapter_init(_owner);
        __Ownable_init(_owner);
        __Context_init();
    }

    /**
     * @notice Set blacklist status for an address
     * @param account Address to modify blacklist status
     * @param blacklisted True to blacklist, false to remove from blacklist
     */
    function setBlacklist(address account, bool blacklisted) external onlyOwner {
        require(account != address(0), "OVaultShareOFTAdapter: zero address");
        OVaultShareOFTAdapterStorage storage $ = _getOVaultShareOFTAdapterStorage();
        require($.blacklisted[account] != blacklisted, "OVaultShareOFTAdapter: status unchanged");
        $.blacklisted[account] = blacklisted;
         if (blacklisted) {
          emit Blacklisted(account);
        } else {
          emit Unblacklisted(account);
        }
    }

    /**
     * @notice Check if address is blacklisted
     * @param account Address to check
     * @return True if address is blacklisted
     */
    function isBlacklisted(address account) public view returns (bool) {
        return _getOVaultShareOFTAdapterStorage().blacklisted[account];
    }

    /**
     * @notice Override _debit to check blacklist before cross-chain sends
     * @dev Prevents blacklisted addresses from sending tokens cross-chain
     */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        OVaultShareOFTAdapterStorage storage $ = _getOVaultShareOFTAdapterStorage();
        require(!$.blacklisted[_from], "OVaultShareOFTAdapter: sender address is blacklisted");
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }

    /**
     * @notice Override _credit to check blacklist before crediting tokens
     * @dev Prevents blacklisted addresses from receiving tokens cross-chain
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override returns (uint256 amountReceivedLD) {
        OVaultShareOFTAdapterStorage storage $ = _getOVaultShareOFTAdapterStorage();
        require(!$.blacklisted[_to], "OVaultShareOFTAdapter: receiver address is blacklisted");
        return super._credit(_to, _amountLD, _srcEid);
    }
}
