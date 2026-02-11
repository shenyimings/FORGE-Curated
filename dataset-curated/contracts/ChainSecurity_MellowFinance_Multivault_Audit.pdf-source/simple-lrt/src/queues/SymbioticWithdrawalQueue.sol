// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/queues/ISymbioticWithdrawalQueue.sol";

contract SymbioticWithdrawalQueue is ISymbioticWithdrawalQueue, Initializable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @inheritdoc IWithdrawalQueue
    address public immutable claimer;
    /// @inheritdoc ISymbioticWithdrawalQueue
    address public vault;
    /// @inheritdoc ISymbioticWithdrawalQueue
    ISymbioticVault public symbioticVault;
    /// @inheritdoc ISymbioticWithdrawalQueue
    address public collateral;

    mapping(uint256 epoch => EpochData data) private _epochData;
    mapping(address account => AccountData data) private _accountData;

    constructor(address claimer_) {
        claimer = claimer_;
        _disableInitializers();
    }

    function initialize(address vault_, address symbioticVault_) external initializer {
        __init_SymbioticWithdrawalQueue(vault_, symbioticVault_);
    }

    function __init_SymbioticWithdrawalQueue(address vault_, address symbioticVault_)
        internal
        onlyInitializing
    {
        vault = vault_;
        symbioticVault = ISymbioticVault(symbioticVault_);
        collateral = ISymbioticVault(symbioticVault_).collateral();
    }

    /// @inheritdoc ISymbioticWithdrawalQueue
    function getCurrentEpoch() public view returns (uint256) {
        return symbioticVault.currentEpoch();
    }

    /// @inheritdoc ISymbioticWithdrawalQueue
    function getAccountData(address account)
        external
        view
        returns (
            uint256 sharesToClaimPrev,
            uint256 sharesToClaim,
            uint256 claimableAssets,
            uint256 claimEpoch
        )
    {
        AccountData storage accountData = _accountData[account];
        claimEpoch = accountData.claimEpoch;
        sharesToClaimPrev = claimEpoch == 0 ? 0 : accountData.sharesToClaim[claimEpoch - 1];
        sharesToClaim = accountData.sharesToClaim[claimEpoch];
        claimableAssets = accountData.claimableAssets;
    }

    /// @inheritdoc ISymbioticWithdrawalQueue
    function getEpochData(uint256 epoch) external view returns (EpochData memory) {
        return _epochData[epoch];
    }

    /// @inheritdoc ISymbioticWithdrawalQueue
    function pendingAssets() public view returns (uint256) {
        uint256 epoch = getCurrentEpoch();
        address this_ = address(this);
        ISymbioticVault symbioticVault_ = symbioticVault;
        return symbioticVault_.withdrawalsOf(epoch, this_)
            + symbioticVault_.withdrawalsOf(epoch + 1, this_);
    }

    /// @inheritdoc ISymbioticWithdrawalQueue
    function pendingAssetsOf(address account) public view returns (uint256 assets) {
        uint256 epoch = getCurrentEpoch();

        AccountData storage accountData = _accountData[account];
        assets += _withdrawalsOf(epoch, accountData.sharesToClaim[epoch]);
        epoch += 1;
        assets += _withdrawalsOf(epoch, accountData.sharesToClaim[epoch]);
    }

    /// @inheritdoc ISymbioticWithdrawalQueue
    function claimableAssetsOf(address account) public view returns (uint256 assets) {
        AccountData storage accountData = _accountData[account];
        assets = accountData.claimableAssets;

        uint256 currentEpoch = getCurrentEpoch();
        uint256 epoch = accountData.claimEpoch;
        if (epoch > 0 && _isClaimableInSymbiotic(epoch - 1, currentEpoch)) {
            assets += _claimable(accountData, epoch - 1);
        }

        if (_isClaimableInSymbiotic(epoch, currentEpoch)) {
            assets += _claimable(accountData, epoch);
        }
    }

    /// @inheritdoc ISymbioticWithdrawalQueue
    function request(address account, uint256 amount) external {
        require(msg.sender == vault, "SymbioticWithdrawalQueue: forbidden");
        if (amount == 0) {
            return;
        }
        AccountData storage accountData = _accountData[account];

        uint256 epoch = getCurrentEpoch();
        _handlePendingEpochs(accountData, epoch);

        epoch = epoch + 1;
        EpochData storage epochData = _epochData[epoch];
        epochData.sharesToClaim += amount;

        accountData.sharesToClaim[epoch] += amount;
        accountData.claimEpoch = epoch;
        emit WithdrawalRequested(account, epoch, amount);
    }

    /// @inheritdoc IWithdrawalQueue
    function transferPendingAssets(address to, uint256 amount) external {
        address from = msg.sender;
        if (amount == 0 || from == to) {
            return;
        }

        uint256 epoch = getCurrentEpoch();
        uint256 nextEpoch = epoch + 1;
        AccountData storage fromData = _accountData[from];
        AccountData storage toData = _accountData[to];
        _handlePendingEpochs(fromData, epoch);
        _handlePendingEpochs(toData, epoch);

        uint256 nextSharesToClaim = fromData.sharesToClaim[nextEpoch];
        uint256 nextPending = _withdrawalsOf(nextEpoch, nextSharesToClaim);
        if (nextPending >= amount) {
            uint256 shares = nextSharesToClaim.mulDiv(amount, nextPending);
            fromData.sharesToClaim[nextEpoch] -= shares;
            toData.sharesToClaim[nextEpoch] += shares;
            toData.claimEpoch = nextEpoch;
            emit Transfer(from, to, nextEpoch, shares);
        } else {
            uint256 currentSharesToClaim = fromData.sharesToClaim[epoch];
            uint256 currentPending = _withdrawalsOf(epoch, currentSharesToClaim);
            require(
                nextPending + currentPending >= amount,
                "SymbioticWithdrawalQueue: insufficient pending assets"
            );

            if (nextSharesToClaim != 0) {
                toData.sharesToClaim[nextEpoch] += nextSharesToClaim;
                delete fromData.sharesToClaim[nextEpoch];
                amount -= nextPending;
                emit Transfer(from, to, nextEpoch, nextSharesToClaim);
            }

            uint256 shares = currentSharesToClaim.mulDiv(amount, currentPending);
            fromData.sharesToClaim[epoch] = currentSharesToClaim - shares;
            toData.sharesToClaim[epoch] += shares;
            toData.claimEpoch = nextEpoch;
            emit Transfer(from, to, epoch, shares);
        }
    }

    /// @inheritdoc ISymbioticWithdrawalQueue
    function pull(uint256 epoch) public {
        require(
            _isClaimableInSymbiotic(epoch, getCurrentEpoch()),
            "SymbioticWithdrawalQueue: invalid epoch"
        );
        _pullFromSymbioticForEpoch(epoch);
    }

    /// @inheritdoc ISymbioticWithdrawalQueue
    function claim(address account, address recipient, uint256 maxAmount)
        external
        returns (uint256 amount)
    {
        address sender = msg.sender;
        require(sender == account || sender == claimer, "SymbioticWithdrawalQueue: forbidden");
        AccountData storage accountData = _accountData[account];
        _handlePendingEpochs(accountData, getCurrentEpoch());
        amount = accountData.claimableAssets;
        if (amount == 0) {
            return 0;
        }
        if (amount <= maxAmount) {
            accountData.claimableAssets = 0;
        } else {
            amount = maxAmount;
            accountData.claimableAssets -= maxAmount;
        }
        if (amount != 0) {
            IERC20(collateral).safeTransfer(recipient, amount);
        }
        emit Claimed(account, recipient, amount);
    }

    /// @inheritdoc ISymbioticWithdrawalQueue
    function handlePendingEpochs(address account) public {
        _handlePendingEpochs(_accountData[account], getCurrentEpoch());
    }

    /**
     * @notice Calculates the amount of collateral that will be withdrawn for the given `shares` at the specified epoch.
     * @param epoch The epoch number in the Symbiotic Vault.
     * @param shares The amount of withdrawal shares.
     * @return assets The corresponding amount of collateral that will be withdrawn based on the `shares`.
     */
    function _withdrawalsOf(uint256 epoch, uint256 shares) private view returns (uint256) {
        if (shares == 0) {
            return 0;
        }
        return shares.mulDiv(
            symbioticVault.withdrawalsOf(epoch, address(this)), _epochData[epoch].sharesToClaim
        );
    }

    /**
     * @notice Claims collateral from the Symbiotic Vault for the given account at the current and previous epochs.
     * @dev This function updates the `epochData` and `accountData` mappings accordingly.
     * @param accountData The storage struct containing specific claim data for the account.
     * @param currentEpoch The current epoch in the Symbiotic Vault.
     *
     * @custom:requirements
     * - If `claimEpoch` is zero, no claims are made for `epochEpoch` - 1.
     * - If `claimEpoch` is non-zero, collateral is claimed for both `claimEpoch` and `claimEpoch`-1.
     * - Ensures that both `claimEpoch` and `claimEpoch`-1 are claimable.
     *
     * @custom:effects
     * - Emits `EpochClaimed` event when claims are successfully made.
     */
    function _handlePendingEpochs(AccountData storage accountData, uint256 currentEpoch) private {
        uint256 epoch = accountData.claimEpoch;
        if (epoch > 0) {
            _handlePendingEpoch(accountData, epoch - 1, currentEpoch);
        }
        _handlePendingEpoch(accountData, epoch, currentEpoch);
    }

    /**
     * @notice Claims collateral from the Symbiotic Vault for the given `epoch`.
     * @dev This function updates the `epochData` and `accountData` mappings.
     * @param accountData The storage struct containing specific claim data for the account.
     * @param epoch The epoch number from which the claim is made.
     * @param currentEpoch The current epoch in the Symbiotic Vault.
     *
     * @custom:requirements
     * - If `epoch` is not claimable, no claims are made.
     *
     * @custom:effects
     * - Emits `EpochClaimed` event when claims are successfully made.
     */
    function _handlePendingEpoch(
        AccountData storage accountData,
        uint256 epoch,
        uint256 currentEpoch
    ) private {
        if (!_isClaimableInSymbiotic(epoch, currentEpoch)) {
            return;
        }
        uint256 shares = accountData.sharesToClaim[epoch];
        if (shares == 0) {
            return;
        }
        _pullFromSymbioticForEpoch(epoch);

        EpochData storage epochData = _epochData[epoch];
        uint256 assets = shares.mulDiv(epochData.claimableAssets, epochData.sharesToClaim);

        epochData.sharesToClaim -= shares;
        epochData.claimableAssets -= assets;

        accountData.claimableAssets += assets;
        delete accountData.sharesToClaim[epoch];
    }

    /**
     * @notice Claims collateral from the Symbiotic Vault for the given `epoch`.
     * @dev This function ensures that the withdrawals for the specified `epoch` are not claimed from the Symbiotic Vault.
     * @param epoch The epoch number for which the collateral is being claimed.
     *
     * @custom:requirements
     * - Checks that the collateral for the given `epoch` has not already been claimed.
     * - Checks whether there are any claimable withdrawals for the given `epoch`.
     *
     * @custom:effects
     * - Emits `EpochClaimed` event when the claim is successful.
     */
    function _pullFromSymbioticForEpoch(uint256 epoch) private {
        EpochData storage epochData = _epochData[epoch];
        if (epochData.isClaimed) {
            return;
        }
        epochData.isClaimed = true;
        address this_ = address(this);
        ISymbioticVault symbioticVault_ = symbioticVault;
        if (symbioticVault_.isWithdrawalsClaimed(epoch, this_)) {
            return;
        }
        if (symbioticVault_.withdrawalsOf(epoch, this_) == 0) {
            return;
        }
        uint256 claimedAssets = symbioticVault_.claim(this_, epoch);
        epochData.claimableAssets = claimedAssets;
        emit EpochClaimed(epoch, claimedAssets);
    }

    /**
     * @notice Returns the claimable collateral amount for a given `accountData` at a specific `epoch`.
     * @param accountData The storage struct containing specific claim data for the account.
     * @param epoch The epoch number at which the claim is being checked.
     * @return The amount of claimable collateral corresponding to the given account's shares at the specified epoch.
     */
    function _claimable(AccountData storage accountData, uint256 epoch)
        private
        view
        returns (uint256)
    {
        uint256 shares = accountData.sharesToClaim[epoch];
        if (shares == 0) {
            return 0;
        }
        EpochData storage epochData = _epochData[epoch];
        if (epochData.isClaimed) {
            return shares.mulDiv(epochData.claimableAssets, epochData.sharesToClaim);
        }
        return _withdrawalsOf(epoch, shares);
    }

    /**
     * @notice Determines whether the given `epoch` is claimable based on the current epoch.
     * @param epoch The epoch number to check.
     * @param currentEpoch The current epoch in the Symbiotic Vault.
     * @return True if the epoch is claimable (i.e., it is less than the current epoch), false otherwise.
     */
    function _isClaimableInSymbiotic(uint256 epoch, uint256 currentEpoch)
        private
        pure
        returns (bool)
    {
        return epoch < currentEpoch;
    }
}
