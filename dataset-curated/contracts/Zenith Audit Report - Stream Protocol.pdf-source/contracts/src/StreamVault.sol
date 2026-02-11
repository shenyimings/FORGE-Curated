// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ShareMath} from "./lib/ShareMath.sol";
import {Vault} from "./lib/Vault.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IStableWrapper} from "./interfaces/IStableWrapper.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import {SendParam, MessagingFee, MessagingReceipt, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/**
 * @title StreamVault
 * @notice A vault that allows users to stake and withdraw from an off-chain managed Stream strategy
 * @notice Users receive shares for their stakes, which can be redeemed for assets
 * @notice The rounds will be rolled over on a weekly basis
 */
contract StreamVault is ReentrancyGuard, OFT {
    using SafeERC20 for IERC20;
    using ShareMath for Vault.StakeReceipt;

    // #############################################
    // CONSTANTS
    // #############################################
    /// @notice Minimum round number for valid stake receipts
    uint256 private constant MINIMUM_VALID_ROUND = 2;

    // #############################################
    // STATE
    // #############################################
    /// @notice Stores the user's pending stake for the round
    mapping(address => Vault.StakeReceipt) public stakeReceipts;

    /// @notice On every round's close, the pricePerShare value of an rTHETA token is stored
    /// This is used to determine the number of shares to be returned
    /// to a user with their StakeReceipt.stakeAmount
    mapping(uint256 => uint256) public roundPricePerShare;

    /// @notice Vault's parameters like cap, decimals
    Vault.VaultParams public vaultParams;

    /// @notice Vault's lifecycle state like round and locked amounts
    Vault.VaultState public vaultState;

    /// @notice address of the stable wrapper contract
    address public stableWrapper;

    /// @notice the total supply of shares across all chains
    uint256 public omniTotalSupply;

    /// @notice Whether the vault allows independence from the stable wrapper
    bool public allowIndependence;

    // #############################################
    // EVENTS
    // #############################################
    event Stake(address indexed account, uint256 amount, uint256 round);

    event Unstake(address indexed account, uint256 amount, uint256 round);

    event Redeem(address indexed account, uint256 share, uint256 round);

    event CapSet(uint256 oldCap, uint256 newCap);

    event RoundRolled(
        uint256 round,
        uint256 pricePerShare,
        uint256 sharesMinted,
        uint256 wrappedTokensMinted,
        uint256 wrappedTokensBurned,
        uint256 yield,
        bool isYieldPositive
    );

    event InstantUnstake(
        address indexed account,
        uint256 amount,
        uint256 round
    );
    event AllowIndependenceSet(bool allowIndependence);

    // #############################################
    // ERRORS
    // #############################################
    error IndependenceNotAllowed();

    error AmountMustBeGreaterThanZero();

    error AddressMustBeNonZero();

    error CapExceeded();

    error MinimumSupplyNotMet();

    error RoundMismatch();

    error AmountExceedsReceipt();

    error RoundMustBeGreaterThanOne();

    error InsufficientUnredeemedShares();

    error CapMustBeGreaterThanZero();

    // #############################################
    // CONSTRUCTOR & INITIALIZATION
    // #############################################

    /**
     * @notice Initializes the contract with immutable variables
     * @param _tokenName is the token name of the share ERC-20
     * @param _tokenSymbol is the token symbol of the share ERC-20
     * @param _stableWrapper is the address of the stable wrapper contract
     * @param _lzEndpoint is the address of the LayerZero endpoint
     * @param _delegate is the address of the delegate
     * @param _vaultParams is the `VaultParams` struct with general vault data
     */
    constructor(
        string memory _tokenName,
        string memory _tokenSymbol,
        address _stableWrapper,
        address _lzEndpoint,
        address _delegate,
        Vault.VaultParams memory _vaultParams
    )
        ReentrancyGuard()
        OFT(_tokenName, _tokenSymbol, _lzEndpoint, _delegate)
        Ownable(msg.sender)
    {
        if (_vaultParams.cap == 0) revert CapMustBeGreaterThanZero();
        if (_stableWrapper == address(0)) revert AddressMustBeNonZero();

        stableWrapper = _stableWrapper;
        vaultParams = _vaultParams;
        vaultState.round = 1;
        allowIndependence = false;
    }
    // #############################################
    // Wrapper functions
    // #############################################

    /**
     * @notice Deposits assets and stakes them in a single transaction
     * @param amount Amount of assets to deposit and stake
     */
    function depositAndStake(
        uint104 amount,
        address creditor
    ) external nonReentrant {
        IStableWrapper(stableWrapper).depositToVault(msg.sender, amount);

        // Then stake the wrapped tokens
        _stakeInternal(amount, creditor);
    }

    /**
     * @notice Unstakes tokens and initiates withdrawal in a single transaction
     * @param numShares Number of shares to unstake
     */
    function unstakeAndWithdraw(uint256 numShares) external nonReentrant {
        // First unstake the tokens
        uint256 withdrawAmount = _unstake(numShares, stableWrapper);

        // Then initiate withdrawal in the wrapper
        IStableWrapper(stableWrapper).initiateWithdrawalFromVault(
            msg.sender,
            uint224(withdrawAmount)
        );
    }

    /**
     * @notice Performs instant unstake and initiates withdrawal in a single transaction
     * @param amount Amount to unstake instantly
     */
    function instantUnstakeAndWithdraw(uint104 amount) external nonReentrant {
        // First perform instant unstake
        _instantUnstake(amount, stableWrapper);

        // Then initiate withdrawal in the wrapper
        IStableWrapper(stableWrapper).initiateWithdrawalFromVault(
            msg.sender,
            uint224(amount)
        );
    }

    function bridgeWithRedeem(
        SendParam calldata sendParam,
        MessagingFee calldata fee,
        address payable refundAddress
    ) external payable returns (MessagingReceipt memory, OFTReceipt memory) {
        // First redeem any shares if needed
        Vault.StakeReceipt memory stakeReceipt = stakeReceipts[msg.sender];
        if (stakeReceipt.amount > 0 || stakeReceipt.unredeemedShares > 0) {
            _redeem(0);
        }

        // Then call the internal _send
        return _send(sendParam, fee, refundAddress);
    }

    // #############################################
    // PUBLIC STAKING
    // #############################################

    /**
     * @notice Stakes the `asset` from msg.sender added to `creditor`'s stake.
     * @notice Used for vault -> vault stakes on the user's behalf
     * @param amount is the amount of `asset` to stake
     * @param creditor is the address that can claim/withdraw staked amount
     * @dev An approve() by the msg.sender is required beforehand
     */
    function stake(uint104 amount, address creditor) public nonReentrant {
        if (!allowIndependence) revert IndependenceNotAllowed();
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (creditor == address(0)) revert AddressMustBeNonZero();

        IERC20(stableWrapper).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        _stakeInternal(amount, creditor);
    }

    /**
     * @notice Manages the stake receipts for a staker
     * @param amount is the amount of `asset` staked
     * @param creditor is the address to receieve the stake
     * @dev This function should be called after the underlying
     * token has been transferred to the vault
     */
    function _stakeInternal(uint104 amount, address creditor) private {
        uint16 currentRound = vaultState.round;
        Vault.VaultParams memory _vaultParams = vaultParams;
        uint256 totalWithStakedAmount = IERC20(stableWrapper).balanceOf(
            address(this)
        );

        if (totalWithStakedAmount > _vaultParams.cap) revert CapExceeded();
        if (totalWithStakedAmount < _vaultParams.minimumSupply)
            revert MinimumSupplyNotMet();

        emit Stake(creditor, amount, currentRound);

        Vault.StakeReceipt memory stakeReceipt = stakeReceipts[creditor];

        // If we have an unprocessed pending stake from the previous rounds, we have to process it.
        uint256 unredeemedShares = stakeReceipt.getSharesFromReceipt(
            currentRound,
            roundPricePerShare[stakeReceipt.round],
            _vaultParams.decimals
        );

        uint104 stakeAmount = amount;

        // If we have a pending stake in the current round, we add on to the pending stake
        if (currentRound == stakeReceipt.round) {
            stakeAmount = stakeAmount + stakeReceipt.amount;
        }

        stakeReceipts[creditor] = Vault.StakeReceipt({
            round: currentRound,
            amount: stakeAmount,
            unredeemedShares: uint128(unredeemedShares)
        });

        vaultState.totalPending = vaultState.totalPending + amount;
    }

    // #############################################
    // WITHDRAWALS
    // #############################################

    /**
     * @notice External wrapper for instant unstaking
     * @param amount is the amount to withdraw
     */
    function instantUnstake(uint104 amount) external nonReentrant {
        if (!allowIndependence) revert IndependenceNotAllowed();
        _instantUnstake(amount, msg.sender);
    }

    /**
     * @notice Withdraws the assets on the vault using the outstanding `StakeReceipt.amount`
     * @param amount is the amount to withdraw
     */
    function _instantUnstake(uint104 amount, address to) internal {
        Vault.StakeReceipt storage stakeReceipt = stakeReceipts[msg.sender];

        uint16 currentRound = vaultState.round;
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (stakeReceipt.round != currentRound) revert RoundMismatch();

        uint104 receiptAmount = stakeReceipt.amount;
        if (receiptAmount < amount) revert AmountExceedsReceipt();

        // Subtraction underflow checks already ensure it is smaller than uint104
        stakeReceipt.amount = receiptAmount - amount;
        vaultState.totalPending = vaultState.totalPending - amount;

        emit InstantUnstake(msg.sender, amount, currentRound);

        _transferAsset(to, amount);
    }

    /**
     * @notice External wrapper for unstaking shares
     * @param numShares is the number of shares to withdraw and burn
     */
    function unstake(uint256 numShares) external nonReentrant {
        if (!allowIndependence) revert IndependenceNotAllowed();
        _unstake(numShares, msg.sender);
    }

    /**
     * @notice Initiates a withdrawal
     * @param numShares is the number of shares to withdraw and burn
     */
    function _unstake(
        uint256 numShares,
        address to
    ) internal returns (uint256) {
        if (numShares == 0) revert AmountMustBeGreaterThanZero();
        if (to == address(0)) revert AddressMustBeNonZero();

        // We do a max redeem before initiating a withdrawal
        // But we check if they must first have unredeemed shares
        {
            Vault.StakeReceipt memory stakeReceipt = stakeReceipts[msg.sender];
            if (stakeReceipt.amount > 0 || stakeReceipt.unredeemedShares > 0) {
                _redeem(0);
            }
        }

        // This caches the `round` variable used in shareBalances
        uint256 currentRound = vaultState.round;
        if (currentRound < MINIMUM_VALID_ROUND)
            revert RoundMustBeGreaterThanOne();

        uint256 withdrawAmount = ShareMath.sharesToAsset(
            numShares,
            roundPricePerShare[currentRound - 1],
            vaultParams.decimals
        );

        emit Unstake(msg.sender, withdrawAmount, currentRound);

        _burn(msg.sender, numShares);

        omniTotalSupply = omniTotalSupply - numShares;

        IERC20(stableWrapper).safeTransfer(to, withdrawAmount);

        return withdrawAmount;
    }

    // #############################################
    // REDEMPTIONS
    // #############################################

    /**
     * @notice Redeems shares that are owed to the account
     * @param numShares is the number of shares to redeem
     */
    function redeem(uint256 numShares) external nonReentrant {
        if (numShares == 0) revert AmountMustBeGreaterThanZero();

        _redeem(numShares);
    }

    /**
     * @notice Redeems the entire unredeemedShares balance that is owed to the account
     */
    function maxRedeem() external nonReentrant {
        _redeem(0);
    }

    /**
     * @notice Redeems shares that are owed to the account
     * @param numShares is the number of shares to redeem,
     * if numShares is 0, it will redeem all unredeemed shares
     */
    function _redeem(uint256 numShares) internal {
        Vault.StakeReceipt memory stakeReceipt = stakeReceipts[msg.sender];

        uint256 currentRound = vaultState.round;

        uint256 unredeemedShares = stakeReceipt.getSharesFromReceipt(
            currentRound,
            roundPricePerShare[stakeReceipt.round],
            vaultParams.decimals
        );

        numShares = numShares == 0 ? unredeemedShares : numShares;
        if (numShares == 0) {
            return;
        }
        if (numShares > unredeemedShares) revert InsufficientUnredeemedShares();

        // If we have a stakeReceipt on the same round, BUT we have some unredeemed shares
        // we debit from the unredeemedShares, but leave the amount field intact
        // If the round has past, with no new stakes, we just zero it out for new stakes.
        if (stakeReceipt.round < currentRound) {
            stakeReceipts[msg.sender].amount = 0;
        }

        ShareMath.assertUint128(numShares);
        stakeReceipts[msg.sender].unredeemedShares = uint128(
            unredeemedShares - numShares
        );

        emit Redeem(msg.sender, numShares, stakeReceipt.round);

        _transfer(address(this), msg.sender, numShares);
    }

    // #############################################
    // VAULT OPERATIONS
    // #############################################

    /**
     * @notice Rolls to the next round, finalizing prev round pricePerShare and minting new shares
     * @param yield is the amount of assets earnt or lost in the round
     * @param isYieldPositive is true if the yield is positive, false if it is negative
     */
    function rollToNextRound(
        uint256 yield,
        bool isYieldPositive
    ) external onlyOwner nonReentrant {
        uint256 balance = IERC20(stableWrapper).balanceOf(address(this));
        uint256 currentBalance;
        if (isYieldPositive) {
            currentBalance = balance + yield;
        } else {
            currentBalance = balance - yield;
        }

        Vault.VaultParams memory _vaultParams = vaultParams;
        if (currentBalance < uint256(_vaultParams.minimumSupply)) {
            revert MinimumSupplyNotMet();
        }
        Vault.VaultState memory state = vaultState;
        uint256 currentRound = state.round;

        uint256 newPricePerShare = ShareMath.pricePerShare(
            omniTotalSupply,
            currentBalance,
            state.totalPending,
            _vaultParams.decimals
        );

        roundPricePerShare[currentRound] = newPricePerShare;

        vaultState.totalPending = 0;
        vaultState.round = uint16(currentRound + 1);

        uint256 mintShares = ShareMath.assetToShares(
            state.totalPending,
            newPricePerShare,
            _vaultParams.decimals
        );

        _mint(address(this), mintShares);

        omniTotalSupply = omniTotalSupply + mintShares;

        if (currentBalance > balance) {
            IStableWrapper(stableWrapper).permissionedMint(
                address(this),
                currentBalance - balance
            );
            emit RoundRolled(
                currentRound,
                newPricePerShare,
                mintShares,
                currentBalance - balance,
                0,
                yield,
                isYieldPositive
            );
        } else if (currentBalance < balance) {
            IStableWrapper(stableWrapper).permissionedBurn(
                address(this),
                balance - currentBalance
            );
            emit RoundRolled(
                currentRound,
                newPricePerShare,
                mintShares,
                0,
                balance - currentBalance,
                yield,
                isYieldPositive
            );
        } else {
            emit RoundRolled(
                currentRound,
                newPricePerShare,
                mintShares,
                0,
                0,
                yield,
                isYieldPositive
            );
        }
    }

    /**
     * @notice Helper function to make either an ETH transfer or ERC20 transfer
     * @param recipient is the receiving address
     * @param amount is the transfer amount
     */
    function _transferAsset(address recipient, uint256 amount) internal {
        IERC20(stableWrapper).safeTransfer(recipient, amount);
    }

    // #############################################
    // SETTERS
    // #############################################

    /**
     * @notice Sets a new stable wrapper contract address
     * @param newStableWrapper is the address of the new stable wrapper contract
     */
    function setStableWrapper(address newStableWrapper) external onlyOwner {
        if (newStableWrapper == address(0)) revert AddressMustBeNonZero();
        stableWrapper = newStableWrapper;
    }

    /**
     * @notice Allows owner to set allowIndependence
     * @param _allowIndependence New allowIndependence value
     */
    function setAllowIndependence(bool _allowIndependence) public onlyOwner {
        allowIndependence = _allowIndependence;
        emit AllowIndependenceSet(_allowIndependence);
    }

    /**
     * @notice Sets a new cap for stakes
     * @param newCap is the new cap for stakes
     */
    function setCap(uint256 newCap) external onlyOwner {
        if (newCap == 0) revert CapMustBeGreaterThanZero();
        ShareMath.assertUint104(newCap);
        emit CapSet(vaultParams.cap, newCap);
        vaultParams.cap = uint104(newCap);
    }

    /**
     * @notice Sets the new vault parameters
     */
    function setVaultParams(
        Vault.VaultParams memory newVaultParams
    ) external onlyOwner {
        if (newVaultParams.cap == 0) revert CapMustBeGreaterThanZero();
        vaultParams = newVaultParams;
    }

    // #############################################
    // GETTERS
    // #############################################

    /**
     * @notice Returns the asset balance held on the vault for the account not accounting for current round stakes
     * @param account is the address to lookup balance for
     * @return the amount of `asset` custodied by the vault for the user
     */
    function accountVaultBalance(
        address account
    ) public view returns (uint256) {
        if (vaultState.round < MINIMUM_VALID_ROUND)
            revert RoundMustBeGreaterThanOne();
        uint256 _decimals = vaultParams.decimals;
        uint256 pricePerShare = roundPricePerShare[vaultState.round - 1];
        return
            ShareMath.sharesToAsset(shares(account), pricePerShare, _decimals);
    }

    /**
     * @notice Getter for returning the account's share balance including unredeemed shares
     * @param account is the account to lookup share balance for
     * @return the share balance
     */
    function shares(address account) public view returns (uint256) {
        uint256 heldByAccount = shareBalancesHeldByAccount(account);
        uint256 heldByVault = shareBalancesHeldByVault(account);
        return heldByAccount + heldByVault;
    }

    /**
     * @notice Getter for returning the account's share balance held by the account
     * @param account is the account to lookup share balance for
     * @return heldByAccount is the shares held by account
     */
    function shareBalancesHeldByAccount(
        address account
    ) public view returns (uint256) {
        return balanceOf(account);
    }

    /**
     * @notice Getter for returning the account's share balance held by the vault
     * @param account is the account to lookup share balance for
     * @return heldByVault is the shares held by the vault (unredeemedShares)
     */
    function shareBalancesHeldByVault(
        address account
    ) public view returns (uint256) {
        Vault.StakeReceipt memory stakeReceipt = stakeReceipts[account];

        return
            stakeReceipt.getSharesFromReceipt(
                vaultState.round,
                roundPricePerShare[stakeReceipt.round],
                vaultParams.decimals
            );
    }

    /**
     * @notice Returns the token decimals
     */
    function decimals() public view override returns (uint8) {
        return vaultParams.decimals;
    }

    /**
     * @notice Returns the shared token decimals for OFT
     */
    function sharedDecimals() public view virtual override returns (uint8) {
        return decimals();
    }

    /**
     * @notice Returns the maximum amount of wrapped tokens
     * that can be deposited into the vault
     */
    function cap() public view returns (uint256) {
        return vaultParams.cap;
    }

    /**
     * @notice Returns the total amount of wrapped tokens
     * for which share issuance is pending
     */
    function totalPending() public view returns (uint256) {
        return vaultState.totalPending;
    }

    /**
     * @notice Returns the current round number
     */
    function round() public view returns (uint256) {
        return vaultState.round;
    }

    // #############################################
    // OTHER
    // #############################################

    /**
     * @notice Rescues ERC20 tokens stuck in the contract
     * @param _token The address of the token to rescue
     * @param amount The amount of tokens to rescue
     * @dev Only callable by owner
     */
    function rescueTokens(address _token, uint256 amount) external onlyOwner {
        if (_token == address(0)) revert AddressMustBeNonZero();
        if (amount == 0) revert AmountMustBeGreaterThanZero();

        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}
