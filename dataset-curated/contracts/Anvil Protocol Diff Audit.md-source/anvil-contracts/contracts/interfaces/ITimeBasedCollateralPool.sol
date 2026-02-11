// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITimeBasedCollateralPool {
    /***************
     * ERROR TYPES *
     ***************/

    error AlreadyInitialized();
    error InvalidZeroAddress();
    error InvalidZeroAmount();
    error DepositTooLarge();
    error InsufficientBalance(uint256 need, uint256 have);
    error InsufficientClaimable(uint256 need, uint256 have);
    error RelatedArraysLengthMismatch(uint256 firstLength, uint256 secondLength);
    error UnstakeAmountZero();

    /**********
     * EVENTS *
     **********/

    /// Emitted when an account processes a reset and becomes up-to-date with the latest reset nonce.
    event AccountResetNonceUpdated(address indexed account, uint256 oldNonce, uint256 newNonce);

    /// Emitted when tokens are claimed from the pool by a claimant.
    event CollateralClaimed(IERC20 indexed token, uint256 tokenAmount, address destinationAccount);

    /// Emitted when collateral is released back to an account through the ICollateral interface (the opposite of the stake operation).
    event CollateralReleased(IERC20 indexed token, uint256 tokenAmount, uint256 poolUnits, address destinationAccount);

    /// Emitted when tokens are staked via `depositAndStake(...)` or `stake(...)`
    event CollateralStaked(address indexed account, IERC20 indexed token, uint256 amount, uint256 poolUnitsIssued);

    /// Emitted when the default account to receive claimed tokens gets updated by the authorized updater role.
    event DefaultClaimDestinationAccountUpdated(address oldAccount, address newAccount);

    /// Emitted when the pool is reset for a token. See `resetPool(...)` below.
    event PoolReset(IERC20 indexed token, uint256 newResetNonce, uint256 totalTokens, uint256 totalUnits);

    /// Emitted when the claim destination account account override for the provided token is updated by the authorized updater role.
    event TokenClaimDestinationAccountOverrideUpdated(IERC20 indexed token, address oldAccount, address newAccount);

    /// Emitted when an account calls `unstake(...)` to initiate unstaking.
    /// Note: The tokens will still be claimable until `willCompleteAtTimestampSeconds`.
    event UnstakeInitiated(
        address indexed account,
        IERC20 indexed token,
        uint256 unitsToUnstake,
        uint256 willCompleteAtTimestampSeconds
    );

    /// Emitted when the contract processes unstakes for an epoch.
    /// Note: This event will be emitted after the referenced tokens are no longer claimable, but it may be well after that point in time.
    event UnstakeProcessed(IERC20 indexed token, uint256 poolUnitsUnstaked, uint256 poolTokensUnstaked);

    /***********
     * STRUCTS *
     ***********/

    struct ClaimableCollateral {
        uint256 amountClaimableUntilEndOfCurrentEpoch;
        uint256 endOfCurrentEpochTimestampSeconds;
        uint256 amountClaimableUntilEndOfNextEpoch;
        uint256 endOfNextEpochTimestampSeconds;
    }

    /**************************
     * CLAIM ROUTER FUNCTIONS *
     **************************/

    /**
     * @notice Updates the default claim destination account that will receive all claimed tokens if there is no
     * destination account override for the claimed token.
     * @param _defaultClaimDestinationAccount The account that will be set as the default destination for claims.
     */
    function setDefaultClaimDestinationAccount(address _defaultClaimDestinationAccount) external;

    /**
     * @notice Updates the claim destination account override for the provided token. If this is not the zero address,
     * it will receive claimed tokens for the provided token. Set to the zero address to fall back to the default.
     * @param _token The token for which the account will receive claimed tokens.
     * @param _destinationAccount The account that will receive claimed tokens.
     */
    function setTokenClaimDestinationAccountOverride(IERC20 _token, address _destinationAccount) external;

    /**********************
     * CLAIMANT FUNCTIONS *
     **********************/

    /**
     * @notice Claims the provided token amounts to the destination account configured in the contract.
     * @dev This function may only be called by the beneficiary of this contract.
     * @param _tokens The addresses of the tokens to claim. Indexes in this array correspond to those of _amounts.
     * @param _amounts The amounts of the tokens to claim. Indexes in this array correspond to those of _tokens.
     */
    function claim(IERC20[] calldata _tokens, uint256[] calldata _amounts) external;

    /**
     * @notice Gets the amounts of the provided tokens that are guaranteed to be claimable this epoch and next epoch.
     * @param _tokens The ERC-20 tokens for which claimable tokens are being requested.
     * @return _claimableCollateral The array of claimable tokens corresponding to the _tokens array in the same order.
     */
    function getClaimableCollateral(
        IERC20[] calldata _tokens
    ) external view returns (ClaimableCollateral[] memory _claimableCollateral);

    /**********************
     * RESETTER FUNCTIONS *
     **********************/

    /**
     * @notice Resets the pool, unstaking all staked tokens and requiring stakers to call `stake(...)` again if they wish
     * to stake again. All staked tokens at the time of this call are immediately releasable via a call to
     * `releaseEligibleTokens(...)`.
     * NOTE: This function may only be invoked by the resetter role.
     * @dev The main reason a resetter would invoke this function is due to unit dilution. Over time, claims of some
     * but not all of the pool tokens make it so one token corresponds to more and more pool units. Given the fact that
     * tokens may have many decimals of precision, it's plausible that total units approaches the limits of the uint256
     * datatype, making future deposits fail and pool token value to be capped at a low number.
     * Extreme Example:
     *  1. 1e25 tokens (1MM ERC-20 tokens with 18 decimals) are in the contract, which is 1e25 units.
     *  2. 9.999...e24 tokens get claimed. There are still 1e25 units.
     *  3. Add another 1e25 tokens. 1 token is worth 1e25 units, so you get 1e50 units.
     *  4. Repeat once more (uint256 can support ~77 digits).
     * @param _tokens The tokens for which the pool will be reset to a balance of 0 tokens and 0 units.
     */
    function resetPool(IERC20[] calldata _tokens) external;

    /********************
     * STAKER FUNCTIONS *
     ********************/

    /**
     * @notice Deposits the sender's provided token amount into this contract and stakes it using the CollateralVault.
     * @dev This requires that the caller has called IERC20.approve(...), permitting the CollateralVault to transfer its tokens.
     * @param _token The ERC-20 token to deposit and stake.
     * @param _amount The amount of the ERC-20 token to deposit and stake.
     * @param _collateralizableDepositApprovalSignature The signature to allow this collateralizable to deposit on
     * behalf of the calling account within the `ICollateral` contract.
     * @return _poolUnitsIssued The number of pool units issued to the sender as a result of this call.
     */
    function depositAndStake(
        IERC20 _token,
        uint256 _amount,
        bytes calldata _collateralizableDepositApprovalSignature
    ) external returns (uint256 _poolUnitsIssued);

    /**
     * @notice Releases all of the provided tokens that are eligible for release for the sender.
     * @dev This will be a no-op rather than an error if there are no releasable tokens.
     * @param _account The account for which eligible tokens will be released.
     * @param _tokens The ERC-20 tokens that should be released.
     */
    function releaseEligibleTokens(address _account, IERC20[] calldata _tokens) external;

    /**
     * @notice Adds the sender's existing available Collateral to this pool and stakes it.
     * @param _token The ERC-20 token to pool and stake.
     * @param _amount The amount of the ERC-20 token to pool and stake.
     * @param _collateralizableApprovalSignature [Optional] The signature to approve the use of this collateralizable
     * within the `ICollateral` contract.
     * @return _poolUnitsIssued The number of pool units issued to the sender as a result of this call.
     */
    function stake(
        IERC20 _token,
        uint256 _amount,
        bytes calldata _collateralizableApprovalSignature
    ) external returns (uint256 _poolUnitsIssued);

    /**
     * @notice Releases the sender's tokens from the provided stake pool and stakes the provided amount in this pool.
     * Note: If releasing from this contract (i.e. restaking), it is more efficient to call stake(...) directly, since
     * eligible tokens are released before that operation is processed.
     * @param _pool The pool from which tokens will be released in order to stake in this contract.
     * @param _token The ERC-20 token to pool and stake.
     * @param _amount The amount of the ERC-20 token to pool and stake.
     * @param _collateralizableApprovalSignature [Optional] The signature to approve the use of this collateralizable
     * within the `ICollateralPool` contract.
     * @return _poolUnitsIssued The number of pool units issued to the sender as a result of this call.
     */
    function stakeReleasableTokensFrom(
        ITimeBasedCollateralPool _pool,
        IERC20 _token,
        uint256 _amount,
        bytes calldata _collateralizableApprovalSignature
    ) external returns (uint256 _poolUnitsIssued);

    /**
     * @notice Starts the unstake vesting period for the caller's provided staked tokens.
     * Note: staked tokens are locked for at least one full epoch and are releasable at the end of the epoch in which
     * this unstake period lapses. This is to guarantee that the tokens are available to the claimant for at least a
     * full epoch.
     * @dev This function operates on the account state of the msg.sender.
     * @param _token The ERC-20 token to unstake.
     * @param _poolUnits The amount of the ERC-20 token to unstake.
     */
    function unstake(IERC20 _token, uint256 _poolUnits) external;
}
