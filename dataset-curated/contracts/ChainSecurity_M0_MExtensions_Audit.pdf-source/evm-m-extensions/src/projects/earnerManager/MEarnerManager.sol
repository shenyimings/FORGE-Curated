// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IERC20 } from "../../../lib/common/src/interfaces/IERC20.sol";

import {
    AccessControlUpgradeable
} from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import { IndexingMath } from "../../libs/IndexingMath.sol";
import { UIntMath } from "../../../lib/common/src/libs/UIntMath.sol";

import { IMEarnerManager } from "./IMEarnerManager.sol";

import { MExtension } from "../../MExtension.sol";

abstract contract MEarnerManagerStorageLayout {
    /**
     * @dev   Struct to represent an account's balance, whitelisted status, and earning details like `feeRate` and earning principal.
     * @param balance       The current balance of the account.
     * @param isWhitelisted Whether the account is whitelisted by an earner manager.
     * @param feeRate       The fee rate that defines yield split between account and earner manager.
     * @param principal     The earning principal for the account.
     */
    struct Account {
        // Slot 1
        uint256 balance;
        // Slot 2
        bool isWhitelisted;
        uint16 feeRate;
        uint112 principal;
    }

    /// @custom:storage-location erc7201:M0.storage.MEarnerManager
    struct MEarnerManagerStorageStruct {
        // Slot 1
        address feeRecipient;
        // Slot 2
        uint256 totalSupply;
        // Slot 3
        uint112 totalPrincipal;
        // Slot 4
        mapping(address account => Account) accounts;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.MEarnerManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _M_EARNER_MANAGER_STORAGE_LOCATION =
        0x1c4485857d96206482b943eeab7f941848f1c52b84a4bd59d8c2a3e8468f8300;

    function _getMEarnerManagerStorageLocation() internal pure returns (MEarnerManagerStorageStruct storage $) {
        assembly {
            $.slot := _M_EARNER_MANAGER_STORAGE_LOCATION
        }
    }
}

/**
 * @title M Extension where Earner Manager whitelists accounts and sets fee rates for them.
 * @author M0 Labs
 */
contract MEarnerManager is IMEarnerManager, AccessControlUpgradeable, MEarnerManagerStorageLayout, MExtension {
    /* ============ Variables ============ */

    /// @inheritdoc IMEarnerManager
    uint16 public constant ONE_HUNDRED_PERCENT = 10_000;

    /// @inheritdoc IMEarnerManager
    bytes32 public constant EARNER_MANAGER_ROLE = keccak256("EARNER_MANAGER_ROLE");

    /* ============ Initializer ============ */

    /**
     * @dev   Initializes the M extension token with earner manager role and different fee tiers.
     * @param name               The name of the token (e.g. "M Earner Manager").
     * @param symbol             The symbol of the token (e.g. "MEM").
     * @param mToken             The address of an M Token.
     * @param swapFacility       The address of the Swap Facility.
     * @param admin              The address administrating the M extension. Can grant and revoke roles.
     * @param earnerManager      The address of earner manager
     * @param feeRecipient_      The address that will receive the fees from all the earners.
     */
    function initialize(
        string memory name,
        string memory symbol,
        address mToken,
        address swapFacility,
        address admin,
        address earnerManager,
        address feeRecipient_
    ) public virtual initializer {
        if (admin == address(0)) revert ZeroAdmin();
        if (earnerManager == address(0)) revert ZeroEarnerManager();

        __MExtension_init(name, symbol, mToken, swapFacility);

        _setFeeRecipient(feeRecipient_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(EARNER_MANAGER_ROLE, earnerManager);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IMEarnerManager
    function setAccountInfo(address account, bool status, uint16 feeRate) public onlyRole(EARNER_MANAGER_ROLE) {
        _setAccountInfo(account, status, feeRate);
    }

    /// @inheritdoc IMEarnerManager
    function setAccountInfo(
        address[] calldata accounts,
        bool[] calldata statuses,
        uint16[] calldata feeRates
    ) external onlyRole(EARNER_MANAGER_ROLE) {
        if (accounts.length == 0) revert ArrayLengthZero();
        if (accounts.length != statuses.length || accounts.length != feeRates.length) revert ArrayLengthMismatch();

        for (uint256 index_; index_ < accounts.length; ++index_) {
            _setAccountInfo(accounts[index_], statuses[index_], feeRates[index_]);
        }
    }

    /// @inheritdoc IMEarnerManager
    function setFeeRecipient(address feeRecipient_) external onlyRole(EARNER_MANAGER_ROLE) {
        _setFeeRecipient(feeRecipient_);
    }

    /// @inheritdoc IMEarnerManager
    function claimFor(address account) public returns (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFee) {
        if (account == address(0)) revert ZeroAccount();

        (yieldWithFee, fee, yieldNetOfFee) = accruedYieldAndFeeOf(account);

        if (yieldWithFee == 0) return (0, 0, 0);

        MEarnerManagerStorageStruct storage $ = _getMEarnerManagerStorageLocation();

        // Emit the appropriate `YieldClaimed` and `Transfer` events.
        emit YieldClaimed(account, yieldNetOfFee);
        emit Transfer(address(0), account, yieldWithFee);

        // NOTE: No change in principal, only the balance is updated to include the newly claimed yield.
        unchecked {
            $.accounts[account].balance += yieldWithFee;
            $.totalSupply += yieldWithFee;
        }

        if (fee == 0) return (yieldWithFee, 0, yieldNetOfFee);

        address feeRecipient_ = $.feeRecipient;

        // Emit the appropriate `FeeClaimed` and `Transfer` events.
        emit FeeClaimed(account, feeRecipient_, fee);
        emit Transfer(account, feeRecipient_, fee);

        // Transfer fee to the fee recipient.
        _update(account, feeRecipient_, fee);
    }

    /* ============ External/Public view functions ============ */

    /// @inheritdoc IMEarnerManager
    function accruedYieldAndFeeOf(
        address account
    ) public view returns (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFee) {
        Account storage accountInfo_ = _getMEarnerManagerStorageLocation().accounts[account];

        yieldWithFee = _getAccruedYield(accountInfo_.balance, accountInfo_.principal, currentIndex());
        uint16 feeRate_ = accountInfo_.feeRate;

        if (feeRate_ == 0 || yieldWithFee == 0) return (yieldWithFee, 0, yieldWithFee);

        unchecked {
            fee = (yieldWithFee * feeRate_) / ONE_HUNDRED_PERCENT;
            yieldNetOfFee = yieldWithFee - fee;
        }
    }

    /// @inheritdoc IMEarnerManager
    function accruedYieldOf(address account) public view returns (uint256 yieldNetOfFee) {
        (, , yieldNetOfFee) = accruedYieldAndFeeOf(account);
    }

    /// @inheritdoc IMEarnerManager
    function accruedFeeOf(address account) public view returns (uint256 fee) {
        (, fee, ) = accruedYieldAndFeeOf(account);
    }

    /// @inheritdoc IMEarnerManager
    function balanceWithYieldOf(address account) external view returns (uint256) {
        unchecked {
            return balanceOf(account) + accruedYieldOf(account);
        }
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view override returns (uint256) {
        return _getMEarnerManagerStorageLocation().accounts[account].balance;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint256) {
        return _getMEarnerManagerStorageLocation().totalSupply;
    }

    /// @inheritdoc IMEarnerManager
    function projectedTotalSupply() public view returns (uint256) {
        return IndexingMath.getPresentAmountRoundedUp(totalPrincipal(), currentIndex());
    }

    /// @inheritdoc IMEarnerManager
    function totalPrincipal() public view returns (uint112) {
        return _getMEarnerManagerStorageLocation().totalPrincipal;
    }

    /// @inheritdoc IMEarnerManager
    function feeRecipient() public view returns (address) {
        return _getMEarnerManagerStorageLocation().feeRecipient;
    }

    /// @inheritdoc IMEarnerManager
    function isWhitelisted(address account) public view returns (bool) {
        return _getMEarnerManagerStorageLocation().accounts[account].isWhitelisted;
    }

    /// @inheritdoc IMEarnerManager
    function principalOf(address account) public view returns (uint112) {
        return _getMEarnerManagerStorageLocation().accounts[account].principal;
    }

    /// @inheritdoc IMEarnerManager
    function feeRateOf(address account) public view returns (uint16) {
        return _getMEarnerManagerStorageLocation().accounts[account].feeRate;
    }

    /* ============ Hooks For Internal Interactive Functions ============ */

    /**
     * @dev   Hook called before approving an allowance.
     * @param account  The account that is approving the allowance.
     * @param spender  The account that is being approved to spend tokens.
     */
    function _beforeApprove(address account, address spender, uint256 /* amount */) internal view override {
        MEarnerManagerStorageStruct storage $ = _getMEarnerManagerStorageLocation();

        _revertIfNotWhitelisted($, account);
        _revertIfNotWhitelisted($, spender);
    }

    /**
     * @dev    Hooks called before wrapping M into M Extension token.
     * @param  account   The account from which M is deposited.
     * @param  recipient The account receiving the minted M Extension token.
     */
    function _beforeWrap(address account, address recipient, uint256 /* amount */) internal view override {
        MEarnerManagerStorageStruct storage $ = _getMEarnerManagerStorageLocation();

        _revertIfNotWhitelisted($, account);
        _revertIfNotWhitelisted($, recipient);
    }

    /**
     * @dev   Hook called before unwrapping M Extension token.
     * @param account The account from which M Extension token is burned.
     */
    function _beforeUnwrap(address account, uint256 /* amount */) internal view override {
        _revertIfNotWhitelisted(_getMEarnerManagerStorageLocation(), account);
    }

    /**
     * @dev   Hook called before transferring tokens.
     * @param sender    The sender's address.
     * @param recipient The recipient's address.
     */
    function _beforeTransfer(address sender, address recipient, uint256 /* amount */) internal view override {
        MEarnerManagerStorageStruct storage $ = _getMEarnerManagerStorageLocation();

        _revertIfNotWhitelisted($, msg.sender);

        _revertIfNotWhitelisted($, sender);
        _revertIfNotWhitelisted($, recipient);
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @notice Sets the account info like:
     *         - whitelisting or removing account from whitelist,
     *         - fee rate for the account.
     * @param  account The address of the accounts to whitelist for earning or remove from the whitelist.
     * @param  status Whether an account is a whitelisted account, respectively, according to the admin.
     * @param  feeRate The fee rate, in bps, that will be taken from the yield generated by the account.
     */
    function _setAccountInfo(address account, bool status, uint16 feeRate) internal {
        if (account == address(0)) revert ZeroAccount();
        if (feeRate > ONE_HUNDRED_PERCENT) revert InvalidFeeRate();
        if (status == false && feeRate != 0) revert InvalidAccountInfo();

        Account storage accountInfo_ = _getMEarnerManagerStorageLocation().accounts[account];
        bool isWhitelisted_ = accountInfo_.isWhitelisted;

        // No change, no-op action
        if (!isWhitelisted_ && !status) return;

        // No change, no-op action
        if (isWhitelisted_ && status && accountInfo_.feeRate == feeRate) return;

        emit AccountInfoSet(account, status, feeRate);

        // Set up a new whitelisted account
        if (!isWhitelisted_ && status) {
            accountInfo_.isWhitelisted = true;
            accountInfo_.feeRate = feeRate;
            return;
        }

        // Claim yield as the action below will lead to the change in whitelisted account info.
        claimFor(account);

        if (!status) {
            // Remove whitelisted account info.
            accountInfo_.isWhitelisted = false;
            // fee recipient will receive all yield from such 'un-whitelisted' accounts.
            accountInfo_.feeRate = ONE_HUNDRED_PERCENT;
        } else {
            // Change fee rate for the whitelisted account.
            accountInfo_.feeRate = feeRate;
        }
    }

    /**
     * @notice Sets the yield fee recipient that will receive part of the yield generated by token.
     * @dev    Reverts if the yield fee recipient is address zero.
     * @dev    Returns early if the yield fee recipient is the same as the current one.
     * @param  feeRecipient_ The yield fee recipient address.
     */
    function _setFeeRecipient(address feeRecipient_) internal {
        if (feeRecipient_ == address(0)) revert ZeroFeeRecipient();

        MEarnerManagerStorageStruct storage $ = _getMEarnerManagerStorageLocation();

        if ($.feeRecipient == feeRecipient_) return;

        // Yield fee recipient does not pay fees.
        _setAccountInfo(feeRecipient_, true, 0);

        $.feeRecipient = feeRecipient_;

        emit FeeRecipientSet(feeRecipient_);
    }

    /**
     * @dev   Mints `amount` tokens to `account`.
     * @param account The address that will receive tokens.
     * @param amount  The amount of tokens to mint.
     */
    function _mint(address account, uint256 amount) internal override {
        MEarnerManagerStorageStruct storage $ = _getMEarnerManagerStorageLocation();
        Account storage accountInfo_ = $.accounts[account];

        // Slightly underestimate the principal amount to be minted, round down in favor of protocol.
        uint112 principal_ = IndexingMath.getPrincipalAmountRoundedDown(amount, currentIndex());

        // NOTE: Can be `unchecked` because the max amount of $M is never greater than `type(uint240).max`.
        //       Can be `unchecked` because UIntMath.safe112 is used for principal addition safety for `principal[account]`
        unchecked {
            accountInfo_.balance += amount;
            $.totalSupply += amount;

            $.totalPrincipal = UIntMath.safe112(uint256($.totalPrincipal) + principal_);
            // No need for `UIntMath.safe112`, `accountInfo_.principal` cannot be greater than `totalPrincipal`.
            accountInfo_.principal += principal_;
        }

        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev   Burns `amount` tokens from `account`.
     * @param account The address whose account balance will be decremented.
     * @param amount  The present amount of tokens to burn.
     */
    function _burn(address account, uint256 amount) internal override {
        MEarnerManagerStorageStruct storage $ = _getMEarnerManagerStorageLocation();
        Account storage accountInfo_ = $.accounts[account];

        // Slightly overestimate the principal amount to be burned and use safe value to avoid underflow in the unchecked block.
        uint112 fromPrincipal_ = accountInfo_.principal;
        uint112 principal_ = IndexingMath.getSafePrincipalAmountRoundedUp(amount, currentIndex(), fromPrincipal_);

        // NOTE: Can be `unchecked` because `_revertIfInsufficientBalance` is used.
        //       Can be `unchecked` because safety adjustment to `principal_` is applied above
        unchecked {
            accountInfo_.balance -= amount;
            $.totalSupply -= amount;

            accountInfo_.principal = fromPrincipal_ - principal_;
            $.totalPrincipal -= principal_;
        }

        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev   Internal ERC20 transfer function that needs to be implemented by the inheriting contract.
     * @param sender    The sender's address.
     * @param recipient The recipient's address.
     * @param amount    The amount to be transferred.
     */
    function _update(address sender, address recipient, uint256 amount) internal override {
        MEarnerManagerStorageStruct storage $ = _getMEarnerManagerStorageLocation();
        Account storage senderAccount_ = $.accounts[sender];
        Account storage recipientAccount_ = $.accounts[recipient];

        // Slightly overestimate the principal amount to be moved on transfer
        uint112 fromPrincipal_ = senderAccount_.principal;
        uint112 principal_ = IndexingMath.getSafePrincipalAmountRoundedUp(amount, currentIndex(), fromPrincipal_);

        // NOTE: Can be `unchecked` because `_revertIfInsufficientBalance` is used in MExtension.
        //       Can be `unchecked` because safety adjustment to `principal_` is applied above, and
        unchecked {
            senderAccount_.balance -= amount;
            recipientAccount_.balance += amount;

            senderAccount_.principal = fromPrincipal_ - principal_;
            recipientAccount_.principal += principal_;
        }
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @dev    Compute the yield given a balance, principal and index.
     * @param  balance   The current balance of the account.
     * @param  principal The principal of the account.
     * @param  index     The current index.
     * @return The yield accrued since the last claim.
     */
    function _getAccruedYield(uint256 balance, uint112 principal, uint128 index) internal pure returns (uint256) {
        if (principal == 0) return 0;

        uint256 balanceWithYield_ = IndexingMath.getPresentAmountRoundedDown(principal, index);
        unchecked {
            return balanceWithYield_ > balance ? balanceWithYield_ - balance : 0;
        }
    }

    /**
     * @dev Reverts if `account` is not whitelisted by earner manager.
     */
    function _revertIfNotWhitelisted(MEarnerManagerStorageStruct storage $, address account) internal view {
        if (!$.accounts[account].isWhitelisted) revert NotWhitelisted(account);
    }
}
