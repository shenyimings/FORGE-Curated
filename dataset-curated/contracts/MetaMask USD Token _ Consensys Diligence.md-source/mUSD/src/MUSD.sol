// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { PausableUpgradeable } from "../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { MYieldToOne } from "../lib/evm-m-extensions/src/projects/yieldToOne/MYieldToOne.sol";

import { IMUSD } from "./IMUSD.sol";

/**
 * @title  MUSD
 * @notice M extension for the MUSD token.
 * @author M0 Labs
 */
contract MUSD is IMUSD, MYieldToOne, PausableUpgradeable {
    /* ============ Variables ============ */

    /// @inheritdoc IMUSD
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @inheritdoc IMUSD
    bytes32 public constant FORCED_TRANSFER_MANAGER_ROLE = keccak256("FORCED_TRANSFER_MANAGER_ROLE");

    /* ============ Constructor ============ */

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     * @notice Constructs MUSD Implementation contract
     * @dev    `_disableInitializers()` is called in the inherited MExtension's constructor.
     * @param  mToken       The address of the MToken
     * @param  swapFacility The address of the SwapFacility
     */
    constructor(address mToken, address swapFacility) MYieldToOne(mToken, swapFacility) {}

    /* ============ Initializer ============ */

    /**
     * @dev   Initializes the MUSD token.
     * @param yieldRecipient        The address of a yield destination.
     * @param admin                 The address of an admin.
     * @param freezeManager         The address of a freeze manager.
     * @param yieldRecipientManager The address of a yield recipient setter.
     * @param pauser                The address of a pauser.
     */
    function initialize(
        address yieldRecipient,
        address admin,
        address freezeManager,
        address yieldRecipientManager,
        address pauser,
        address forcedTransferManager
    ) public virtual initializer {
        if (pauser == address(0)) revert ZeroPauser();
        if (forcedTransferManager == address(0)) revert ZeroForcedTransferManager();

        __MYieldToOne_init("MUSD", "mUSD", yieldRecipient, admin, freezeManager, yieldRecipientManager);
        __Pausable_init();

        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(FORCED_TRANSFER_MANAGER_ROLE, forcedTransferManager);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IMUSD
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IMUSD
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @inheritdoc IMUSD
    function forceTransfer(
        address frozenAccount,
        address recipient,
        uint256 amount
    ) external onlyRole(FORCED_TRANSFER_MANAGER_ROLE) {
        _forceTransfer(frozenAccount, recipient, amount);
    }

    /// @inheritdoc IMUSD
    function forceTransfers(
        address[] calldata frozenAccounts,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyRole(FORCED_TRANSFER_MANAGER_ROLE) {
        if (frozenAccounts.length != recipients.length || frozenAccounts.length != amounts.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i; i < frozenAccounts.length; ++i) {
            _forceTransfer(frozenAccounts[i], recipients[i], amounts[i]);
        }
    }

    /* ============ Hooks For Internal Interactive Functions ============ */

    /**
     * @dev   Hook called before approval of mUSD.
     * @param account The sender's address.
     * @param spender The spender's address.
     * @param amount  The amount to be approved.
     */
    function _beforeApprove(address account, address spender, uint256 amount) internal view override {
        _requireNotPaused();

        super._beforeApprove(account, spender, amount);
    }

    /**
     * @dev   Hook called before wrapping M into mUSD.
     * @param account   The account from which M is deposited.
     * @param recipient The account receiving the minted mUSD.
     * @param amount    The amount of tokens to wrap.
     */
    function _beforeWrap(address account, address recipient, uint256 amount) internal view override {
        _requireNotPaused();

        super._beforeWrap(account, recipient, amount);
    }

    /**
     * @dev   Hook called before unwrapping mUSD.
     * @param account The account from which mUSD is burned.
     * @param amount  The amount of tokens to unwrap.
     */
    function _beforeUnwrap(address account, uint256 amount) internal view override {
        _requireNotPaused();

        super._beforeUnwrap(account, amount);
    }

    /**
     * @dev   Hook called before transferring mUSD.
     * @param sender    The address from which the tokens are being transferred.
     * @param recipient The address to which the tokens are being transferred.
     * @param amount    The amount of tokens to transfer.
     */
    function _beforeTransfer(address sender, address recipient, uint256 amount) internal view override {
        _requireNotPaused();

        super._beforeTransfer(sender, recipient, amount);
    }

    /**
     * @dev    Hook called before claiming yield.
     * @notice MUST only be callable by the YIELD_RECIPIENT_MANAGER_ROLE.
     */
    function _beforeClaimYield() internal view override onlyRole(YIELD_RECIPIENT_MANAGER_ROLE) {}

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Internal ERC20 force transfer function to seize funds from a frozen account.
     * @param frozenAccount The frozen account from which tokens are seized.
     * @param recipient     The recipient's address.
     * @param amount        The amount to be transferred.
     * @dev   Force transfer is only allowed for frozen accounts.
     * @dev   No `_beforeTransfer` checks apply to forced transfers; ignore checks for paused and frozen states.
     * @dev   Since this function can only be called by the `FORCED_TRANSFER_MANAGER_ROLE`,
     *        we do not check if the recipient is frozen.
     */
    function _forceTransfer(address frozenAccount, address recipient, uint256 amount) internal {
        _revertIfInvalidRecipient(recipient);
        _revertIfNotFrozen(frozenAccount);

        emit Transfer(frozenAccount, recipient, amount);
        emit ForcedTransfer(frozenAccount, recipient, msg.sender, amount);

        if (amount == 0) return;

        _revertIfInsufficientBalance(frozenAccount, balanceOf(frozenAccount), amount);

        _update(frozenAccount, recipient, amount);
    }
}
