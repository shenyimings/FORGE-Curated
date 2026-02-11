// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlDefaultAdminRulesUpgradeable.sol"; // solhint-disable-line max-line-length
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PaxosBaseAbstract} from "./lib/PaxosBaseAbstract.sol";
import {EIP2612} from "./lib/EIP2612.sol";
import {EIP3009} from "./lib/EIP3009.sol";
import {EIP712} from "./lib/EIP712.sol";

/**
 * @title wYBS contract
 * @dev Wrapped Yield Bearing Stablecoin is a Pausable ERC20 token that wraps YBS using ERC-4626.
 * @custom:security-contact smart-contract-security@paxos.com
 */
// solhint-disable-next-line contract-name-camelcase
contract wYBS is
    ERC4626Upgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    UUPSUpgradeable,
    EIP2612,
    EIP3009
{
    // BLOCKLIST / FREEZE & SEIZE
    // Mapping of block/freeze status per account
    mapping(address => bool) private _blocklist;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * Expected storage slots used by this contract, 50.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap_wYBS; // solhint-disable-line var-name-mixedcase

    // Access control roles
    /**
     * @dev The role that allows accounts to pause the contract.
     * Derived from keccak256("PAUSE_ROLE")
     */
    bytes32 public constant PAUSE_ROLE = 0x139c2898040ef16910dc9f44dc697df79363da767d8bc92f2e310312b816e46d;
    /**
     * @dev The role that can block accounts and seize assets.
     * Derived from keccak256("ASSET_PROTECTION_ROLE")
     */
    bytes32 public constant ASSET_PROTECTION_ROLE = 0xe3e4f9d7569515307c0cdec302af069a93c9e33f325269bac70e6e22465a9796;

    // Events
    event AccountBlocked(address indexed account);
    event AccountUnblocked(address indexed account);
    event BlockedAccountWiped(address indexed account);

    // Errors
    error ZeroAddress();
    error InvalidOperation();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @dev Called on deployment, only can be called once.
     * @param name the token name
     * @param symbol the token symbol
     * @param ybs address of the YBS token
     * @param admin address of the default admin
     * @param pauser address of the pauser
     * @param assetProtector address of the asset protector
     */
    function initialize(
        string memory name,
        string memory symbol,
        IERC20Upgradeable ybs,
        address admin,
        address pauser,
        address assetProtector
    ) external initializer {
        if (address(ybs) == address(0) || pauser == address(0) || assetProtector == address(0)) {
            revert ZeroAddress();
        }

        __ERC20_init(name, symbol);
        __ERC4626_init(ybs);
        __AccessControlDefaultAdminRules_init(3 hours, admin);
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(PAUSE_ROLE, pauser);
        _grantRole(ASSET_PROTECTION_ROLE, assetProtector);
    }

    /**
     * @notice Pauses transfers.
     * @dev Restricted to PAUSE_ROLE.
     * @dev Inherits the _pause function from @openzeppelin/PausableUpgradeable contract.
     */
    function pause() external onlyRole(PAUSE_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses transfers.
     * @dev Restricted to PAUSE_ROLE.
     * @dev Inherits the _unpause function from @openzeppelin/PausableUpgradeable contract.
     */
    function unpause() external onlyRole(PAUSE_ROLE) {
        _unpause();
    }

    /**
     * @notice Batch block accounts.
     * @dev Restricted to ASSET_PROTECTION_ROLE.
     * @param addresses list of addresses to block.
     */
    function blockAccounts(
        address[] calldata addresses
    ) external onlyRole(ASSET_PROTECTION_ROLE) {
        for (uint256 i = 0; i < addresses.length;) {
            _blockAccount(addresses[i]);
            unchecked { ++i; }
        }
    }

    /**
     * @notice Batch unblock accounts.
     * @dev Restricted to ASSET_PROTECTION_ROLE.
     * @param addresses list of addresses to unblock.
     */
    function unblockAccounts(
        address[] calldata addresses
    ) external onlyRole(ASSET_PROTECTION_ROLE) {
        for (uint256 i = 0; i < addresses.length;) {
            _unblockAccount(addresses[i]);
            unchecked { ++i; }
        }
    }

    /**
     * @dev Wipes the shares of a blocked address, and transfers assets to a receiver address.
     * Restricted to ASSET_PROTECTION_ROLE.
     * @param blockedAddr The blocked address to wipe.
     * @param receiverAddr The address to send assets to.
     */
    function seizeAssets(
        address blockedAddr, address receiverAddr
    ) external onlyRole(ASSET_PROTECTION_ROLE) {
        if (!_blocklist[blockedAddr]) revert AccountNotBlocked();
        if (_blocklist[receiverAddr]) revert BlockedAccountReceiver();

        uint256 shares = balanceOf(blockedAddr);
        uint256 assets = previewRedeem(shares);
        
        _burn(blockedAddr, shares);
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset()), receiverAddr, assets);

        emit Withdraw(msg.sender, receiverAddr, blockedAddr, assets, shares);
        emit BlockedAccountWiped(blockedAddr);
    }

    /**
     * @dev Transfer tokens from one set of addresses to another set in a single transaction.
     * @param from The addresses which you want to send tokens from
     * @param to The addresses which you want to transfer to
     * @param amount The amounts of tokens to be transferred
     * @return True if successful
     */
    function transferFromBatch(
        address[] calldata from,
        address[] calldata to,
        uint256[] calldata amount
    ) external returns (bool)
    {
        if (!(to.length == from.length && amount.length == from.length)) revert ArgumentLengthMismatch();
        for (uint256 i = 0; i < from.length;) {
            transferFrom(from[i], to[i], amount[i]);
            unchecked { ++i; }
        }
        return true;
    }

    /**
     * @dev Function to check whether the address is currently blocked.
     * @param addr The address to check if blocked.
     * @return A bool representing whether the given address is blocked.
     */
    function isAddrBlocked(address addr) public view override returns (bool) {
        return _blocklist[addr];
    }

    /**
     * Get domain Separator.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return EIP712.makeDomainSeparator(name(), "1");
    }

    /**
     * @dev Transfer tokens from one address to another
     * @param from The address which you want to send tokens from
     * @param to The address which you want to transfer to
     * @param amount the amount of tokens to be transferred
     * @return True when the operation was successful.
     */
    function transferFrom(address from, address to, uint256 amount) public override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        if (_blocklist[msg.sender]) revert BlockedAccountSpender();

        return super.transferFrom(from, to, amount);
    }

    /**
     * @dev Override the approve function to add blocklist checks.
     * @param spender The address which will spend the funds.
     * @param amount The amount of tokens to be spent.
     * @return True when the operation was successful.
     */
    function approve(address spender, uint256 amount) public override(ERC20Upgradeable, IERC20Upgradeable)  returns (bool) {
        _beforeApprove(msg.sender, spender);

        return super.approve(spender, amount);
    }

    /**
     * @dev Override the increaseAllowance function to add blocklist checks.
     * @param spender The address which will spend the funds.
     * @param addedValue The amount of tokens to be spent.
     * @return True when the operation was successful.
     */
    function increaseAllowance(address spender, uint256 addedValue) public override returns (bool) {
        _beforeApprove(msg.sender, spender);

        return super.increaseAllowance(spender, addedValue);
    }

    /**
     * @dev Override the decreaseAllowance function to add blocklist checks.
     * _beforeApprove not used to allow decreasing an allowance for a blocklisted spender.
     * @param spender The address which will spend the funds.
     * @param subtractedValue The amount of tokens to be spent.
     * @return True when the operation was successful.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public override whenNotPaused returns (bool) {
        if (_blocklist[msg.sender]) revert BlockedAccountSender();

        return super.decreaseAllowance(spender, subtractedValue);
    }

    /**
     * @notice Override the _transfer function to implement PaxosBaseAbstract.
     * @param from The address to transfer from.
     * @param to The address to transfer to.
     * @param amount The amount to be transferred.
     */
    function _transfer(address from, address to, uint256 amount) internal override(ERC20Upgradeable, PaxosBaseAbstract) {
        super._transfer(from, to, amount);
    }

    /**
     * @dev Override the _approve function to implement PaxosBaseAbstract.
     * @param owner The address which owns the funds.
     * @param spender The address which will spend the funds.
     * @param amount The amount of tokens to be approved.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal override(ERC20Upgradeable, PaxosBaseAbstract) {
        super._approve(owner, spender, amount);
    }

    /**
     * @dev Override the _deposit function to add blocklist checks.
     * @param caller The address which initiated the deposit.
     * @param receiver The address which will receive the funds.
     * @param assets The amount of assets to be deposited.
     * @param shares The amount of shares to be minted.
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (_blocklist[caller]) revert BlockedAccountSender();

        super._deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Override the _withdraw function to add blocklist checks.
     * @param caller The address which initiated the withdrawal.
     * @param receiver The address which will receive the funds.
     * @param owner The address which owns the funds.
     * @param assets The amount of assets to be withdrawn.
     * @param shares The amount of shares to be burned.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (_blocklist[receiver]) revert BlockedAccountReceiver();
        if (_blocklist[caller]) revert BlockedAccountSpender();

        // ASSET_PROTECTION_ROLE should only be able to use seizeAssets() to withdraw from a blocked account.
        if (hasRole(ASSET_PROTECTION_ROLE, caller) && _blocklist[owner]) revert InvalidOperation();

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @dev Override the _beforeTokenTransfer function to add blocklist & pause checks.
     * @param from The address to transfer from.
     * @param to The address to transfer to.
     * @param amount The amount to be transferred.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Bypass blocklist checks if transferring from blocked account when seizing assets via ASSET_PROTECTION_ROLE.
        // Only for seizeAssets() which calls _burn() since _withdrawal() reverts for ASSET_PROTECTION_ROLE.
        if (hasRole(ASSET_PROTECTION_ROLE, msg.sender) && _blocklist[from] && to == address(0)) {
            return;
        }

        if (_blocklist[from]) revert BlockedAccountSender();
        if (_blocklist[to]) revert BlockedAccountReceiver();
        _requireNotPaused();

        super._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @dev required by the OZ UUPS module to authorize an upgrade 
     * of the contract. Restricted to DEFAULT_ADMIN_ROLE.
     */
    function _authorizeUpgrade(
        address
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {} // solhint-disable-line no-empty-blocks

    /**
     * @dev Private function to add an account to the _blocklist.
     * @param account The account to block.
     */
    function _blockAccount(address account) private {
        _blocklist[account] = true;
        emit AccountBlocked(account);
    }

    /**
     * @dev Private function to remove an account from the _blocklist.
     * @param account The account to unblock.
     */
    function _unblockAccount(address account) private {
        delete _blocklist[account];
        emit AccountUnblocked(account);
    }

    /**
     * @dev Private function to check if the sender and spender are not blocked.
     * @param sender The address to check if blocked.
     * @param spender The address to check if blocked.
     */
    function _beforeApprove(address sender, address spender) private view whenNotPaused {
        if (_blocklist[sender]) revert BlockedAccountSender();
        if (_blocklist[spender]) revert BlockedAccountSpender();
    }
}
