// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "./ICollateralDepositTarget.sol";

/**
 * @title The Collateral interface that must be exposed to make stored collateral useful to a Collateralizable contract.
 */
interface ICollateral is ICollateralDepositTarget {
    /***************
     * ERROR TYPES *
     ***************/

    error CollateralReservationNotFound(uint96 _id);
    error ContractNotApprovedByProtocol(address _contract);
    error ClaimAmountZero();
    error ClaimableAmountZero();
    error InsufficientAllowance(
        address _contract,
        address _accountAddress,
        address _tokenAddress,
        uint256 _need,
        uint256 _have
    );
    error InsufficientCollateral(uint256 _need, uint256 _have);
    error InvalidSignature(address _accountAddress);
    error InvalidTargetAddress(address _address);
    error InvalidUpgradeTarget(address _contract);
    error InvalidZeroAmount();
    error RelatedArraysLengthMismatch(uint256 _firstLength, uint256 _secondLength);
    error TokenNotAllowed(address _address);
    error Unauthorized(address _address);
    error WithdrawalFeeTooHigh(uint16 _wouldBeValue, uint16 _max);

    /**********
     * EVENTS *
     **********/

    // common protocol events
    event AccountCollateralizableContractAllowanceUpdated(
        address indexed account,
        address indexed contractAddress,
        address indexed tokenAddress,
        int256 modifiedByAmount,
        uint256 newTotal
    );
    event AccountInitiatedUpgrade(
        address indexed account,
        address indexed toCollateralContract,
        address[] tokenAddresses,
        uint256[] amounts
    );

    event CollateralClaimed(
        uint96 indexed reservationId,
        uint256 amountWithFee,
        uint256 feeAmount,
        bool remainderReleased
    );
    event CollateralReleased(uint96 indexed reservationId, uint256 amount);
    event CollateralReservationModified(
        uint96 indexed reservationId,
        uint256 oldAmount,
        uint256 newAmount,
        uint256 oldClaimableAmount,
        uint256 newClaimableAmount
    );
    event CollateralReserved(
        uint96 indexed reservationId,
        address indexed account,
        address reservingContract,
        address tokenAddress,
        uint256 amount,
        uint256 claimableAmount,
        uint16 claimFeeBasisPoints
    );
    event CollateralTransferred(
        address indexed fromAccount,
        address indexed tokenAddress,
        address indexed toAccount,
        uint256 tokenAmount
    );

    event FundsDeposited(address indexed from, address indexed toAccount, address tokenAddress, uint256 amount);
    event FundsWithdrawn(
        address indexed fromAccount,
        address tokenAddress,
        uint256 amountWithFee,
        uint256 feeAmount,
        address beneficiary
    );

    // governance events
    event CollateralizableContractApprovalUpdated(bool approved, address contractAddress, bool isCollateralPool);
    event CollateralTokenUpdated(bool enabled, address tokenAddress);
    event CollateralUpgradeContractApprovalUpdated(bool approved, address upgradeContractAddress);
    event ProtocolBalanceWithdrawn(address indexed destination, address[] tokenAddresses, uint256[] amounts);
    event WithdrawalFeeUpdated(uint16 oldFeeBasisPoints, uint16 newFeeBasisPoints);

    /***********
     * STRUCTS *
     ***********/

    struct CollateralBalance {
        uint256 available;
        uint256 reserved;
    }

    struct CollateralToken {
        // total deposits for all users for this token.
        uint256 cumulativeUserBalance;
        bool enabled;
    }

    struct CollateralReservation {
        address collateralizableContract;
        address account;
        address tokenAddress;
        uint16 feeBasisPoints;
        uint256 tokenAmount;
        uint256 claimableTokenAmount;
    }

    /*************
     * FUNCTIONS *
     *************/

    /*** Views ***/

    /**
     * @notice Gets the CollateralToken with the provided address. If this collateral token does not exist, it will
     * not revert but return a CollateralToken with default values for every field.
     * @param _tokenAddress The address of the CollateralToken being fetched.
     * @return _token The populated CollateralToken if found, empty otherwise.
     */
    function getCollateralToken(address _tokenAddress) external view returns (CollateralToken memory _token);

    /**
     * @notice Gets the CollateralBalance for the provided account and token.
     * @param _accountAddress The account for which the CollateralBalance will be returned.
     * @param _tokenAddress The address of the token for which the account's CollateralBalance will be returned.
     * @return _balance The CollateralBalance for the account and token.
     */
    function getAccountCollateralBalance(
        address _accountAddress,
        address _tokenAddress
    ) external view returns (CollateralBalance memory _balance);

    /**
     * @notice Gets the CollateralReservation for the provided ID.
     * @dev NOTE: If a reservation does not exist for the provided ID, an empty CollateralReservation will be returned.
     * @param _reservationId The ID of the CollateralReservation to be returned.
     * @return _reservation The CollateralReservation.
     */
    function getCollateralReservation(
        uint96 _reservationId
    ) external view returns (CollateralReservation memory _reservation);

    /**
     * @notice Gets the claimable amount for the provided CollateralReservation ID.
     * @dev NOTE: If a reservation does not exist for the provided ID, 0 will be returned.
     * @param _reservationId The ID of the CollateralReservation to be returned.
     * @return _claimable The claimable amount.
     */
    function getClaimableAmount(uint96 _reservationId) external view returns (uint256 _claimable);

    /**
     * @notice Gets amount of the account's assets in the provided token that the Collateralizable contract may use
     * through this contract.
     * @param _accountAddress The address of the account in question.
     * @param _collateralizableContract The address of the Collateralizable contract.
     * @param _tokenAddress The address of the token to which the allowance pertains.
     * @return _allowance The allowance for the account-collateralizable-token combination. Note: If collateral is
     * released, it is added to the allowance, so negative allowances are allowed to disable future collateral use.
     */
    function getCollateralizableTokenAllowance(
        address _accountAddress,
        address _collateralizableContract,
        address _tokenAddress
    ) external view returns (uint256 _allowance);

    /**
     * @notice Gets the fee for withdrawing funds from this vault, either directly or through claim.
     * @return The fee in basis points.
     */
    function getWithdrawalFeeBasisPoints() external view returns (uint16);

    /*** State-modifying functions ***/

    /**
     * @notice Claims reserved collateral, withdrawing it from the ICollateral contract.
     * @dev The ICollateral contract will handle fee calculation and transfer _amountToReceive, supposing there is
     * sufficient collateral reserved to cover _amountToReceive and the _reservationId's _claimFeeBasisPoints.
     * @param _reservationId The ID of the collateral reservation in question.
     * @param _amountToReceive The amount of collateral needed.
     * @param _toAddress The address to which the `_amountToReceive` will be sent.
     * @param _releaseRemainder Whether or not the remaining collateral should be released.
     * Note: if the full amount is claimed, regardless of this value, the reservation is deleted.
     * @return _remainingReservedCollateral The amount of collateral that remains reserved, if not released.
     * @return _remainingClaimableCollateral The portion of the remaining collateral that may be claimed.
     */
    function claimCollateral(
        uint96 _reservationId,
        uint256 _amountToReceive,
        address _toAddress,
        bool _releaseRemainder
    ) external returns (uint256 _remainingReservedCollateral, uint256 _remainingClaimableCollateral);

    /**
     * @notice Deposits the provided amount of the specified token into the specified account. Assets are sourced from
     * the specified account's ERC-20 token balance.
     *
     * Note: Even if an account has previously approved a collateralizable to use its collateral, it must provide a
     * deposit signature allowing it to deposit on its behalf. If the account-collateralizable allowance is less than
     * the amount being deposited, the result of this call will be that the account-collateraliazble allowance is equal
     * to the amount being deposited. If the allowance was already sufficient to use this newly deposited amount, the
     * allowance will remain the same.
     *
     * @param _accountAddress The account address from which assets will be deposited and with which deposited assets will
     * be associated in this contract.
     * @param _tokenAddress The address of the token to be deposited.
     * @param _amount The amount of the token to be deposited.
     * @param _collateralizableDepositApprovalSignature Deposit approval signature permitting the calling collateralizable
     * to deposit the account's collateral. This enables deposit-approve-and-use functionality in a single transaction.
     */
    function depositFromAccount(
        address _accountAddress,
        address _tokenAddress,
        uint256 _amount,
        bytes calldata _collateralizableDepositApprovalSignature
    ) external;

    /**
     * @notice Modifies the amount of the calling account's assets the Collateralizable contract may use through this contract.
     * @param _collateralizableContractAddress The address of the Collateralizable contract `msg.sender` is [dis]allowing.
     * @param _tokenAddress The address of the token for which the allowance is being checked and updated.
     * @param _byAmount The signed number by which the approved amount will be modified. Negative approved amounts
     * function the same as 0 when attempting to reserve collateral. An account may choose to modify such that the allowance
     * is negative since reservations, once released, add to the approved amount since those assets were previously approved.
     */
    function modifyCollateralizableTokenAllowance(
        address _collateralizableContractAddress,
        address _tokenAddress,
        int256 _byAmount
    ) external;

    /**
     * @notice Approves the provided collateralizable contract on behalf of the provided account address using the
     * account's signature.
     * @dev The signature is the EIP-712 signature formatted according to the following type hash variable:
     * bytes32 public constant COLLATERALIZABLE_TOKEN_ALLOWANCE_ADJUSTMENT_TYPEHASH =
     *  keccak256("CollateralizableTokenAllowanceAdjustment(address collateralizableAddress,address tokenAddress,int256 allowanceAdjustment,uint256 approverNonce)");
     *
     * If this call is not successful, it will revert. If it succeeds, the caller may assume the modification succeeded.
     * @param _accountAddress The account for which approval will take place.
     * @param _collateralizableContractAddress The address of the collateralizable to approve.
     * @param _allowanceAdjustment The allowance adjustment to approve. Note: this is a relative amount.
     * @param _signature The signature to prove the account has authorized the approval.
     */
    function modifyCollateralizableTokenAllowanceWithSignature(
        address _accountAddress,
        address _collateralizableContractAddress,
        address _tokenAddress,
        int256 _allowanceAdjustment,
        bytes calldata _signature
    ) external;

    /**
     * @notice Adds/removes collateral to/from the reservation in question, leaving the reservation intact.
     * @dev This call will revert if the modification is not successful.
     * @param _reservationId The ID of the collateral reservation.
     * @param _byAmount The amount by which the reservation will be modified (adding if positive, removing if negative).
     * @return _reservedCollateral The total resulting reserved collateral.
     * @return _claimableCollateral The total resulting claimable collateral.
     */
    function modifyCollateralReservation(
        uint96 _reservationId,
        int256 _byAmount
    ) external returns (uint256 _reservedCollateral, uint256 _claimableCollateral);

    /**
     * @notice Pools assets from the provided account within the collateral contract into the calling Pool's account.
     * This allows the caller to use assets from one or more accounts as a pool of assets.
     * @dev This assumes the `_fromAccount` has given `msg.sender` permission to pool the provided amount of the token.
     * @param _fromAccount The account from which collateral assets will be pooled.
     * @param _tokenAddress The address of the token to pool.
     * @param _tokensToPool The number of tokens to pool from the provided account.
     */
    function poolCollateral(address _fromAccount, address _tokenAddress, uint256 _tokensToPool) external;

    /**
     * @notice Releases all collateral from the reservation in question, releasing the reservation.
     * @param _reservationId The ID of the collateral reservation.
     * @return _totalCollateralReleased The collateral amount that was released.
     */
    function releaseAllCollateral(uint96 _reservationId) external returns (uint256 _totalCollateralReleased);

    /**
     * @notice Reserves collateral from the storing contract so that it may not be rehypothecated.
     * @dev This call reserves the requisite amount of collateral such that the full `_amount` may be claimed. That is
     * to say that `_amount` + `_claimFeeBasisPoints` will actually be reserved.
     * @param _accountAddress The address of the account whose assets are being reserved.
     * @param _tokenAddress The address of the Token being reserved as collateral.
     * @param _claimableAmount The amount of the Token that must be claimable.
     * @return _reservationId The ID that can be used to refer to this reservation when claiming or releasing collateral.
     * @return _totalAmountReserved The total amount reserved from the account in question.
     */
    function reserveClaimableCollateral(
        address _accountAddress,
        address _tokenAddress,
        uint256 _claimableAmount
    ) external returns (uint96 _reservationId, uint256 _totalAmountReserved);

    /**
     * @notice Reserves collateral from the storing contract so that it may not be rehypothecated.
     * @dev Note that the full _amount reserved will not be received when claimed due to _claimFeeBasisPoints. Supposing
     * the whole amount is claimed, _amount * (1000 - _claimFeeBasisPoints) / 1000 will be received if claimed.
     * @param _accountAddress The address of the account whose assets are being reserved.
     * @param _tokenAddress The address of the Token being reserved as collateral.
     * @param _amount The amount of the Token being reserved as collateral.
     * @return _reservationId The ID that can be used to refer to this reservation when claiming or releasing collateral.
     * @return _claimableCollateral The collateral that may be claimed (factoring in the withdrawal fee).
     */
    function reserveCollateral(
        address _accountAddress,
        address _tokenAddress,
        uint256 _amount
    ) external returns (uint96 _reservationId, uint256 _claimableCollateral);

    /**
     * @notice Transfers the provided amount of the caller's available collateral to the provided destination address.
     * @param _tokenAddress The address of the collateral token being transferred.
     * @param _amount The number of collateral tokens being transferred.
     * @param _destinationAddress The address of the account to which assets will be released.
     */
    function transferCollateral(address _tokenAddress, uint256 _amount, address _destinationAddress) external;

    /**
     * @notice Withdraws an ERC-20 token from this `Collateral` vault to the provided address on behalf of the sender,
     * provided the requester has sufficient available balance.
     * @notice There is a protocol fee for withdrawals, so a successful withdrawal of `_amount` will entail the
     * account's balance being lowered by `_amount`, but the `_destination` address receiving `_amount` less the fee.
     * @param _tokenAddress The token address of the ERC-20 token to withdraw.
     * @param _amount The amount of the ERC-20 token to withdraw.
     * @param _destinationAddress The address that will receive the assets. Note: cannot be 0.
     */
    function withdraw(address _tokenAddress, uint256 _amount, address _destinationAddress) external;
}
