// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "./Pricing.sol";
import "./interfaces/ICollateral.sol";
import "./interfaces/ICollateralPool.sol";
import "./SignatureNonces.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/**
 * @title Collateral Vault providing authorized Collateralizable contracts access to collateral via the `ICollateral` interface.
 *
 * @notice Approved Collateralizable contracts may reserve, claim, modify, pool, and release collateral on behalf of an
 * account to fulfill their business logic. Note: CollateralVault contract governance AND the account must approve a
 * Collateralizable contract for it to use an account's collateral.
 *
 * A withdrawal fee will be applied to any collateral that exits this contract unless it is an account moving
 * available collateral to an approved upgraded Collateral contract if/when such contracts exist (no current plans). Any
 * updates to withdrawal fee through governance will not affect collateral that is already in use in a
 * `CollateralReservation` at the time of the update. The initial withdrawal fee can be found in the
 * `withdrawalFeeBasisPoints` variable declaration below.
 *
 * The specific ERC-20 tokens permitted for use as collateral within this contract and their usage limits may vary over
 * time through governance. If an existing token is disallowed in the future, existing CollateralReservations will be
 * honored, but no new collateral reservations may be created for that token.
 *
 * @custom:security-contact security@af.xyz
 */
contract CollateralVault is ICollateral, ERC165, Ownable2Step, EIP712, SignatureNonces {
    using SafeERC20 for IERC20;

    /******************
     * CONTRACT STATE *
     ******************/

    bytes32 public constant COLLATERALIZABLE_TOKEN_ALLOWANCE_ADJUSTMENT_TYPEHASH =
        keccak256(
            "CollateralizableTokenAllowanceAdjustment(address collateralizableAddress,address tokenAddress,int256 allowanceAdjustment,uint256 approverNonce)"
        );

    bytes32 public constant COLLATERALIZABLE_DEPOSIT_APPROVAL_TYPEHASH =
        keccak256(
            "CollateralizableDepositApproval(address collateralizableAddress,address tokenAddress,uint256 depositAmount,uint256 approverNonce)"
        );

    /// can be modified via governance through setWithdrawalFeeBasisPoints(...).
    uint16 public withdrawalFeeBasisPoints = 50;

    /// also known as reservationId in the ICollateral interface.
    /// NB: uint96 stores up to 7.9 x 10^28 and packs tightly with addresses (12 + 20 = 32 bytes).
    uint96 private collateralReservationNonce;

    /// account address => token address => CollateralBalance of the account.
    mapping(address => mapping(address => CollateralBalance)) public accountBalances;

    /// account address => collateralizable contract address => token address => approved amount, set by account to
    /// allow specified amount of collateral to be used by the associated collateralizable contract.
    mapping(address => mapping(address => mapping(address => uint256))) public accountCollateralizableTokenAllowances;

    /// contract address => approval, set by governance to [dis]allow use of this contract's ICollateral interface.
    mapping(address => bool) public collateralizableContracts;

    /// reservationId => CollateralReservation of active collateral reservations.
    mapping(uint96 => CollateralReservation) public collateralReservations;

    /// token address => CollateralToken modified via governance to indicate tokens approved for use within this contract.
    mapping(address => CollateralToken) public collateralTokens;

    /// CollateralUpgradeTarget address => enabled, set by governance to indicate valid Collateral contracts accounts may freely move available collateral to.
    mapping(address => bool) public permittedCollateralUpgradeContracts;

    /***********
     * STRUCTS *
     ***********/

    struct CollateralTokenConfig {
        bool enabled;
        address tokenAddress;
    }

    struct CollateralizableContractApprovalConfig {
        address collateralizableAddress;
        bool isApproved;
    }

    /*************
     * MODIFIERS *
     *************/

    /**
     * Asserts that the provided collateral token address is enabled by the protocol, reverting if not.
     * @param _collateralTokenAddress The collateral token address to check.
     */
    modifier onlyEnabledCollateralTokens(address _collateralTokenAddress) {
        _verifyTokenEnabled(_collateralTokenAddress);

        _;
    }

    /****************
     * PUBLIC VIEWS *
     ****************/

    /**
     * @inheritdoc ICollateral
     */
    function getCollateralToken(address _tokenAddress) public view returns (CollateralToken memory) {
        return collateralTokens[_tokenAddress];
    }

    /**
     * @inheritdoc ICollateral
     */
    function getAccountCollateralBalance(
        address _accountAddress,
        address _tokenAddress
    ) public view returns (CollateralBalance memory _balance) {
        return accountBalances[_accountAddress][_tokenAddress];
    }

    /**
     * @inheritdoc ICollateral
     */
    function getCollateralReservation(uint96 _reservationId) public view returns (CollateralReservation memory) {
        return collateralReservations[_reservationId];
    }

    /// Gets the claimable amount for the provided CollateralReservation, accounting for fees.
    function getClaimableAmount(uint96 _reservationId) public view returns (uint256) {
        return collateralReservations[_reservationId].claimableTokenAmount;
    }

    /**
     * @inheritdoc ICollateral
     */
    function getCollateralizableTokenAllowance(
        address _accountAddress,
        address _collateralizableContract,
        address _tokenAddress
    ) public view returns (uint256) {
        return accountCollateralizableTokenAllowances[_accountAddress][_collateralizableContract][_tokenAddress];
    }

    /**
     * @inheritdoc ICollateral
     */
    function getWithdrawalFeeBasisPoints() external view returns (uint16) {
        return withdrawalFeeBasisPoints;
    }

    /**
     * Indicates support for IERC165, ICollateral, and ICollateralUpgradeTarget.
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 _interfaceID) public view override returns (bool) {
        return
            _interfaceID == type(ICollateral).interfaceId ||
            _interfaceID == type(ICollateralDepositTarget).interfaceId ||
            super.supportsInterface(_interfaceID);
    }

    /*****************************
     * STATE-MODIFYING FUNCTIONS *
     *****************************/

    /**
     * @notice Constructs a `CollateralVault` contract with the `CollateralTokens` according to the provided configs.
     * @param _collateralTokens The `CollateralTokenConfig` array, specifying supported collateral token addresses and
     * their constraints.
     */
    constructor(CollateralTokenConfig[] memory _collateralTokens) Ownable(msg.sender) EIP712("CollateralVault", "1") {
        _authorizedUpsertCollateralTokens(_collateralTokens);
    }

    /**
     * Combines the deposit & approve steps, as accounts wishing to use this contract will likely not want to do one
     * without doing the other. This will add the provided amounts to the collateralizable allowance of the caller for
     * the tokens in question.
     *
     * @param _tokenAddresses The array of addresses of the Tokens to transfer. Indexes must correspond to _amounts.
     * @param _amounts The list of amounts of the Tokens to transfer. Indexes must correspond to _tokenAddresses.
     * @param _collateralizableContractAddressToApprove The Collateralizable contract to approve to use deposited collateral.
     */
    function depositAndApprove(
        address[] calldata _tokenAddresses,
        uint256[] calldata _amounts,
        address _collateralizableContractAddressToApprove
    ) external {
        if (!collateralizableContracts[_collateralizableContractAddressToApprove])
            revert ContractNotApprovedByProtocol(_collateralizableContractAddressToApprove);

        depositToAccount(msg.sender, _tokenAddresses, _amounts);
        for (uint256 i = 0; i < _amounts.length; i++) {
            _authorizedModifyCollateralizableTokenAllowance(
                msg.sender,
                _collateralizableContractAddressToApprove,
                _tokenAddresses[i],
                Pricing.safeCastToInt256(_amounts[i])
            );
        }
    }

    /**
     * @inheritdoc ICollateralDepositTarget
     */
    function depositToAccount(
        address _accountAddress,
        address[] calldata _tokenAddresses,
        uint256[] calldata _amounts
    ) public {
        if (_tokenAddresses.length != _amounts.length)
            revert RelatedArraysLengthMismatch(_tokenAddresses.length, _amounts.length);

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            _deposit(msg.sender, _accountAddress, _tokenAddresses[i], _amounts[i]);
        }
    }

    /**
     * @inheritdoc ICollateral
     */
    function claimCollateral(
        uint96 _reservationId,
        uint256 _amountToReceive,
        address _toAddress,
        bool _releaseRemainder
    ) external returns (uint256, uint256) {
        return _claimCollateral(_reservationId, _amountToReceive, _toAddress, _releaseRemainder);
    }

    /**
     * @inheritdoc ICollateral
     */
    function depositFromAccount(
        address _accountAddress,
        address _tokenAddress,
        uint256 _amount,
        bytes calldata _collateralizableDepositApprovalSignature
    ) external {
        if (!collateralizableContracts[msg.sender]) revert Unauthorized(msg.sender);

        _verifyDepositApprovalSignature(
            _accountAddress,
            _tokenAddress,
            _amount,
            _collateralizableDepositApprovalSignature
        );

        uint256 allowance = accountCollateralizableTokenAllowances[_accountAddress][msg.sender][_tokenAddress];
        if (allowance < _amount) {
            _authorizedModifyCollateralizableTokenAllowance(
                _accountAddress,
                msg.sender,
                _tokenAddress,
                int256(_amount - allowance)
            );
        }

        _deposit(_accountAddress, _accountAddress, _tokenAddress, _amount);
    }

    /**
     * @notice Modifies the amount of the calling account's collateral the Collateralizable contract may use through this contract.
     * @param _collateralizableContractAddress The address of the Collateralizable contract `msg.sender` is [dis]allowing.
     * @param _tokenAddress The address of the token for which the allowance is being checked and updated.
     * @param _byAmount The signed number by which the approved amount will be modified. Negative approved amounts
     * function the same as 0 when attempting to reserve collateral. An account may choose to modify such that the allowance
     * is negative since reservations, once released, add to the approved amount since that collateral was previously approved for use.
     */
    function modifyCollateralizableTokenAllowance(
        address _collateralizableContractAddress,
        address _tokenAddress,
        int256 _byAmount
    ) external {
        if (_byAmount > 0 && !collateralizableContracts[_collateralizableContractAddress])
            revert ContractNotApprovedByProtocol(_collateralizableContractAddress);

        _authorizedModifyCollateralizableTokenAllowance(
            msg.sender,
            _collateralizableContractAddress,
            _tokenAddress,
            _byAmount
        );
    }

    /**
     * @inheritdoc ICollateral
     */
    function modifyCollateralizableTokenAllowanceWithSignature(
        address _accountAddress,
        address _collateralizableContractAddress,
        address _tokenAddress,
        int256 _allowanceAdjustment,
        bytes calldata _signature
    ) external {
        if (_allowanceAdjustment > 0 && !collateralizableContracts[_collateralizableContractAddress])
            revert ContractNotApprovedByProtocol(_collateralizableContractAddress);

        _modifyCollateralizableTokenAllowanceWithSignature(
            _accountAddress,
            _collateralizableContractAddress,
            _tokenAddress,
            _allowanceAdjustment,
            _signature
        );
    }

    /**
     * @inheritdoc ICollateral
     */
    function modifyCollateralReservation(uint96 _reservationId, int256 _byAmount) external returns (uint256, uint256) {
        return _modifyCollateralReservation(_reservationId, _byAmount);
    }

    /**
     * @inheritdoc ICollateral
     */
    function poolCollateral(
        address _accountAddress,
        address _tokenAddress,
        uint256 _amount
    ) external onlyEnabledCollateralTokens(_tokenAddress) {
        _requireCollateralizableAndDecreaseApprovedAmount(msg.sender, _accountAddress, _tokenAddress, _amount);

        _transferCollateral(_tokenAddress, _accountAddress, _amount, msg.sender);
    }

    /**
     * @inheritdoc ICollateral
     */
    function releaseAllCollateral(uint96 _reservationId) external returns (uint256) {
        return _releaseAllCollateral(_reservationId);
    }

    /**
     * @inheritdoc ICollateral
     */
    function reserveClaimableCollateral(
        address _accountAddress,
        address _tokenAddress,
        uint256 _claimableAmount
    ) external returns (uint96 _reservationId, uint256 _totalAmountReserved) {
        _totalAmountReserved = Pricing.amountWithFee(_claimableAmount, withdrawalFeeBasisPoints);
        _reservationId = _reserveCollateral(
            msg.sender,
            _accountAddress,
            _tokenAddress,
            _totalAmountReserved,
            _claimableAmount
        );
    }

    /**
     * @inheritdoc ICollateral
     */
    function reserveCollateral(
        address _accountAddress,
        address _tokenAddress,
        uint256 _amount
    ) external returns (uint96 _reservationId, uint256 _claimableAmount) {
        _claimableAmount = Pricing.amountBeforeFee(_amount, withdrawalFeeBasisPoints);
        _reservationId = _reserveCollateral(msg.sender, _accountAddress, _tokenAddress, _amount, _claimableAmount);
    }

    /**
     * @inheritdoc ICollateral
     */
    function transferCollateral(address _tokenAddress, uint256 _amount, address _destinationAddress) external {
        _transferCollateral(_tokenAddress, msg.sender, _amount, _destinationAddress);
    }

    /**
     * @notice Upgrades the sender's account, sending the specified collateral tokens to a new ICollateralDepositTarget contract.
     * Note that the target ICollateral address must have previously been approved within this contract by governance.
     * @param _targetContractAddress The ICollateralDepositTarget contract that will be sent the collateral.
     * NOTE: the ICollateralDepositTarget implementation MUST iterate and transfer all tokens to itself or revert or
     * collateral will be "lost" within this contract. See ICollateralDepositTarget for more information.
     * @param _tokenAddresses The addresses of the tokens to be transferred. Indexes in this array correspond to those of _amounts.
     * @param _amounts The amounts to be transferred. Indexes in this array correspond to those of _tokenAddresses.
     */
    function upgradeAccount(
        address _targetContractAddress,
        address[] calldata _tokenAddresses,
        uint256[] calldata _amounts
    ) external {
        if (!permittedCollateralUpgradeContracts[_targetContractAddress])
            revert ContractNotApprovedByProtocol(_targetContractAddress);
        if (_tokenAddresses.length != _amounts.length)
            revert RelatedArraysLengthMismatch(_tokenAddresses.length, _amounts.length);

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            address tokenAddress = _tokenAddresses[i];
            CollateralBalance storage accountBalanceStorage = accountBalances[msg.sender][tokenAddress];
            uint256 available = accountBalanceStorage.available;

            uint256 amount = _amounts[i];
            if (available < amount) revert InsufficientCollateral(amount, available);
            accountBalanceStorage.available = available - amount;
            collateralTokens[tokenAddress].cumulativeUserBalance -= amount;
            IERC20(tokenAddress).forceApprove(_targetContractAddress, amount);
        }

        ICollateralDepositTarget(_targetContractAddress).depositToAccount(msg.sender, _tokenAddresses, _amounts);

        emit AccountInitiatedUpgrade(msg.sender, _targetContractAddress, _tokenAddresses, _amounts);
    }

    /**
     * @inheritdoc ICollateral
     */
    function withdraw(address _tokenAddress, uint256 _amount, address _destinationAddress) external {
        if (_amount == 0) revert InvalidZeroAmount();
        uint256 available = accountBalances[msg.sender][_tokenAddress].available;
        if (available < _amount) revert InsufficientCollateral(_amount, available);
        if (_destinationAddress == address(0)) revert InvalidTargetAddress(_destinationAddress);

        accountBalances[msg.sender][_tokenAddress].available = available - _amount;
        collateralTokens[_tokenAddress].cumulativeUserBalance -= _amount;

        uint256 fee = Pricing.percentageOf(_amount, uint256(withdrawalFeeBasisPoints));

        IERC20(_tokenAddress).safeTransfer(_destinationAddress, _amount - fee);

        emit FundsWithdrawn(msg.sender, _tokenAddress, _amount, fee, _destinationAddress);
    }

    /************************
     * GOVERNANCE FUNCTIONS *
     ************************/

    /**
     * @notice Updates the fee for withdrawing from this contract, via `withdraw(...)`, `claimCollateral(...)`, or any
     * other mechanism other than upgrading to an approved `ICollateralDepositTarget`.
     * Note: this may only be done through governance.
     * @param _feeBasisPoints The new fee in basis points.
     */
    function setWithdrawalFeeBasisPoints(uint16 _feeBasisPoints) external onlyOwner {
        // NB: No intention to raise fee, but 10% cap to offer at least some guarantee to depositors.
        if (_feeBasisPoints > 1_000) revert WithdrawalFeeTooHigh(_feeBasisPoints, 1_000);

        emit WithdrawalFeeUpdated(withdrawalFeeBasisPoints, _feeBasisPoints);

        withdrawalFeeBasisPoints = _feeBasisPoints;
    }

    /**
     * @notice Updates the approval status of one or more Collateralizable contracts that may use this contract's collateral.
     * Note: this may only be done through governance.
     * @dev Note: if disapproving an existing Collateralizable contract, its collateral status will enter a decrease-only
     * status, in which it may claim or release reserved collateral but not create new `CollateralReservations`.
     * @param _updates The array of CollateralizableContractApprovalConfigs containing all the contract approvals to modify.
     */
    function upsertCollateralizableContractApprovals(
        CollateralizableContractApprovalConfig[] calldata _updates
    ) external onlyOwner {
        for (uint256 i = 0; i < _updates.length; i++) {
            address contractAddress = _updates[i].collateralizableAddress;
            if (contractAddress == address(0)) revert InvalidTargetAddress(contractAddress);
            collateralizableContracts[contractAddress] = _updates[i].isApproved;

            bool isCollateralPool;
            try IERC165(contractAddress).supportsInterface(type(ICollateralPool).interfaceId) {
                // NB: We have to get the returndata this way because if contractAddress does not implement IERC165,
                // it will not return a boolean, so adding `returns (bool isCollateralPool)` to the try above reverts.
                assembly ("memory-safe") {
                    // Booleans, despite being a single bit, are ABI-encoded to a full 32-byte word.
                    if eq(returndatasize(), 0x20) {
                        // Memory at byte indexes 0-64 are to be used as "scratch space" -- perfect for this use.
                        returndatacopy(0, 0, 0x20)
                        // Since this block could be hit by any fallback function that returns 32-bytes (i.e. an integer),
                        // do a check for exactly 1 when setting `isCollateralPool`. Note: fallback functions should not
                        // return data, and the consequences of getting this wrong are extremely minor and off-chain.
                        if eq(mload(0), 1) {
                            isCollateralPool := true
                        }
                    }
                }
            } catch (bytes memory) {
                // contractAddress does not implement IERC165. `isCollateralPool` should be false in this case
            }

            emit CollateralizableContractApprovalUpdated(_updates[i].isApproved, contractAddress, isCollateralPool);
        }
    }

    /**
     * @notice Updates the `CollateralTokens` at the provided addresses. This permits adding new `CollateralTokens`
     * and/or disallowing future use of or updating the fields of an existing `CollateralToken`.
     * Note: this may only be done through governance.
     *
     * NOTE: Great care should be taken in reviewing tokens prior to addition, with the default being to disallow tokens
     * if unsure. A few types of tokens are generally considered unsafe, however this is not an exhaustive list:
     *   - Fee-on-transfer tokens. These tokens will result in erroneous accounting upon deposit actions as the amount
     *   received by the vault will be lower than the provided deposit amount.
     *   - Rebasing tokens. If the contract's balance is increasing after a rebase then the extra amount will be
     *   eventually held by the CollateralVault contract as fee which is unfair to the depositors. On the other hand, if
     *   after a token's rebase the contract's balance is decreasing, then the whole accounting is against the protocol
     *   and any depositor can benefit until all the contract's funds are drained.
     *   - Upgradeable token contracts. It is generally a risk to whitelist upgradeable contracts since their
     *   implementation might be altered.
     *
     * @dev Calling this with an `enabled` value of `false` disallows future use of this `CollateralToken` until it is
     * overridden by a subsequent call to this function setting it to `true`.
     * Calling this function has no impact on existing `CollateralReservations`. If a limit is decreased or the token is
     * disabled, existing reservations may not be increased, but they may still be claimed or released.
     * @param _collateralTokens The array of collateral token objects, containing their addresses and constraints.
     */
    function upsertCollateralTokens(CollateralTokenConfig[] memory _collateralTokens) public onlyOwner {
        _authorizedUpsertCollateralTokens(_collateralTokens);
    }

    /**
     * @notice Updates the approval status of a `ICollateralDepositTarget` contract that may be sent an account's
     * available collateral upon the account's request.
     * Note: this may only be done through governance.
     * The caller MUST verify that all approved addresses properly implement ICollateralDepositTarget. See all documentation in that interface for more information.
     * @param _collateralUpgradeContractAddress The address of the contract being approved/disapproved.
     * @param _approved true if the contract should be allowed to receive this contract's collateral, false otherwise.
     */
    function upsertCollateralUpgradeContractApproval(
        address _collateralUpgradeContractAddress,
        bool _approved
    ) external onlyOwner {
        permittedCollateralUpgradeContracts[_collateralUpgradeContractAddress] = _approved;

        emit CollateralUpgradeContractApprovalUpdated(_approved, _collateralUpgradeContractAddress);

        // NB: if the _collateralUpgradeContractAddress is an EOA, the transaction will revert without a reason.
        try
            IERC165(_collateralUpgradeContractAddress).supportsInterface(type(ICollateralDepositTarget).interfaceId)
        returns (bool supported) {
            if (!supported) revert InvalidUpgradeTarget(_collateralUpgradeContractAddress);
        } catch (bytes memory) {
            revert InvalidUpgradeTarget(_collateralUpgradeContractAddress);
        }
    }

    /**
     * @notice Withdraws assets amassed by the protocol to the target address.
     * Note: this may only be done through governance.
     * @param _tokenAddresses The addresses of the ERC-20 tokens being withdrawn.
     * Note: the indexes of this array correspond to those of _amounts.
     * @param _amounts The amounts of tokens being withdrawn.
     * Note: the indexes of this array correspond to those of _amounts.
     * @param _destination The address to which withdrawn assets will be sent.
     */
    function withdrawFromProtocolBalance(
        address[] calldata _tokenAddresses,
        uint256[] calldata _amounts,
        address _destination
    ) external onlyOwner {
        if (_tokenAddresses.length != _amounts.length)
            revert RelatedArraysLengthMismatch(_tokenAddresses.length, _amounts.length);
        if (_destination == address(0)) revert InvalidTargetAddress(_destination);

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            address tokenAddress = _tokenAddresses[i];
            uint256 amount = _amounts[i];
            uint256 protocolBalance = IERC20(tokenAddress).balanceOf(address(this)) -
                collateralTokens[tokenAddress].cumulativeUserBalance;
            if (protocolBalance < amount) revert InsufficientCollateral(amount, protocolBalance);

            IERC20(tokenAddress).safeTransfer(_destination, amount);
        }

        emit ProtocolBalanceWithdrawn(_destination, _tokenAddresses, _amounts);
    }

    /********************************
     * PRIVATE / INTERNAL FUNCTIONS *
     ********************************/

    /**
     * @notice Modifies the allowance of the provided collateralizable contract for the provided token and account by
     * the provided amount.
     * @dev It is assumed to have been done by the caller.
     * @param _accountAddress The account for which the allowance is being modified.
     * @param _collateralizableContractAddress The collateralizable contract to which the allowance pertains.
     * @param _tokenAddress The token of the allowance being  modified.
     * @param _byAmount The signed integer amount (positive if adding to the allowance, negative otherwise).
     */
    function _authorizedModifyCollateralizableTokenAllowance(
        address _accountAddress,
        address _collateralizableContractAddress,
        address _tokenAddress,
        int256 _byAmount
    ) private {
        uint256 newAllowance;
        uint256 currentAllowance = accountCollateralizableTokenAllowances[_accountAddress][
            _collateralizableContractAddress
        ][_tokenAddress];

        if (_byAmount > 0) {
            unchecked {
                newAllowance = currentAllowance + uint256(_byAmount);
            }
            if (newAllowance < currentAllowance) {
                // This means we overflowed, but the intention was to increase the allowance, so set the allowance to the max.
                newAllowance = type(uint256).max;
            }
        } else {
            unchecked {
                newAllowance = currentAllowance - uint256(-_byAmount);
            }
            if (newAllowance > currentAllowance) {
                // This means we underflowed, but the intention was to decrease the allowance, so set the allowance to 0.
                newAllowance = 0;
            }
        }

        // Only update storage and emit an event if the allowance was actually updated.
        if (newAllowance != currentAllowance) {
            accountCollateralizableTokenAllowances[_accountAddress][_collateralizableContractAddress][
                _tokenAddress
            ] = newAllowance;

            emit AccountCollateralizableContractAllowanceUpdated(
                _accountAddress,
                _collateralizableContractAddress,
                _tokenAddress,
                _byAmount,
                newAllowance
            );
        }
    }

    /**
     * @notice Does the same thing as `upsertCollateralTokens(...)` just without checking authorization. It is assumed that
     * the caller of this function will handle auth prior to calling this.
     */
    function _authorizedUpsertCollateralTokens(CollateralTokenConfig[] memory _tokens) private {
        for (uint256 i = 0; i < _tokens.length; i++) {
            address tokenAddress = _tokens[i].tokenAddress;
            // NB: we are not actually verifying that the _tokenAddress is an ERC-20.
            collateralTokens[tokenAddress] = CollateralToken(
                collateralTokens[tokenAddress].cumulativeUserBalance,
                _tokens[i].enabled
            );

            emit CollateralTokenUpdated(_tokens[i].enabled, tokenAddress);
        }
    }

    /// @dev Internal function with the same signature as similar external function to allow efficient reuse.
    function _claimCollateral(
        uint96 _reservationId,
        uint256 _amountToReceive,
        address _toAddress,
        bool _releaseRemainder
    ) internal returns (uint256 _remainingReservedCollateral, uint256 _remainingClaimableCollateral) {
        if (_amountToReceive == 0) revert ClaimAmountZero();

        if (_toAddress == address(0)) revert InvalidTargetAddress(_toAddress);
        CollateralReservation storage reservationStorage = collateralReservations[_reservationId];
        if (msg.sender != reservationStorage.collateralizableContract) revert Unauthorized(msg.sender);

        uint256 claimableTokenAmount = reservationStorage.claimableTokenAmount;
        if (claimableTokenAmount < _amountToReceive)
            revert InsufficientCollateral(_amountToReceive, claimableTokenAmount);

        uint256 amountWithFee;
        uint256 tokenAmount = reservationStorage.tokenAmount;
        _remainingClaimableCollateral = claimableTokenAmount - _amountToReceive;
        if (_remainingClaimableCollateral == 0) {
            _releaseRemainder = true;
            _remainingReservedCollateral = 0;
            amountWithFee = tokenAmount;
        } else {
            _remainingReservedCollateral = Pricing.amountWithFee(
                _remainingClaimableCollateral,
                reservationStorage.feeBasisPoints
            );
            amountWithFee = tokenAmount - _remainingReservedCollateral;
        }

        address tokenAddress = reservationStorage.tokenAddress;
        collateralTokens[tokenAddress].cumulativeUserBalance -= amountWithFee;
        if (_releaseRemainder) {
            CollateralBalance storage balanceStorage = accountBalances[reservationStorage.account][tokenAddress];
            balanceStorage.reserved -= tokenAmount;
            balanceStorage.available += _remainingReservedCollateral;

            delete collateralReservations[_reservationId];
        } else {
            accountBalances[reservationStorage.account][tokenAddress].reserved -= amountWithFee;

            reservationStorage.tokenAmount = _remainingReservedCollateral;
            reservationStorage.claimableTokenAmount = _remainingClaimableCollateral;
        }
        uint256 fee = amountWithFee - _amountToReceive;

        emit CollateralClaimed(_reservationId, amountWithFee, fee, _releaseRemainder);

        IERC20(tokenAddress).safeTransfer(_toAddress, _amountToReceive);
    }

    /**
     * @dev Helper function to ensure consistent processing of deposits, however they are received.
     * @param _transferSource The address from which collateral will be transferred. Preapproval is assumed.
     * @param _accountAddress The address to credit with the deposited collateral within the `CollateralVault`.
     * @param _tokenAddress The address of the token being deposited.
     * @param _amount The amount of the token being deposited.
     */
    function _deposit(
        address _transferSource,
        address _accountAddress,
        address _tokenAddress,
        uint256 _amount
    ) internal onlyEnabledCollateralTokens(_tokenAddress) {
        CollateralToken storage collateralTokenStorage = collateralTokens[_tokenAddress];

        CollateralBalance storage accountBalanceStorage = accountBalances[_accountAddress][_tokenAddress];
        uint256 available = accountBalanceStorage.available;
        accountBalanceStorage.available = available + _amount;
        collateralTokenStorage.cumulativeUserBalance += _amount;

        IERC20(_tokenAddress).safeTransferFrom(_transferSource, address(this), _amount);

        emit FundsDeposited(_transferSource, _accountAddress, _tokenAddress, _amount);
    }

    /// Internal function with the same signature as the one exposed externally so that it may be reused.
    function _modifyCollateralReservation(
        uint96 _reservationId,
        int256 _byAmount
    ) internal returns (uint256 _reservedCollateral, uint256 _claimableCollateral) {
        CollateralReservation storage reservationStorage = collateralReservations[_reservationId];
        uint256 oldReservedAmount = reservationStorage.tokenAmount;
        if (oldReservedAmount == 0) revert CollateralReservationNotFound(_reservationId);
        if (_byAmount == 0) {
            // NB: return early for efficiency and because it may otherwise change state, recalculating claimable
            // collateral from total collateral. We never want to do that unless there is a real modification.
            return (reservationStorage.tokenAmount, reservationStorage.claimableTokenAmount);
        }

        address collateralizable = reservationStorage.collateralizableContract;
        if (msg.sender != collateralizable) revert Unauthorized(msg.sender);

        if (_byAmount < 0) {
            uint256 byAmountUint = uint256(-_byAmount);
            if (byAmountUint >= oldReservedAmount) revert InsufficientCollateral(byAmountUint, oldReservedAmount);

            _reservedCollateral = oldReservedAmount - byAmountUint;
            reservationStorage.tokenAmount = _reservedCollateral;

            address account = reservationStorage.account;
            address tokenAddress = reservationStorage.tokenAddress;

            CollateralBalance storage balanceStorage = accountBalances[account][tokenAddress];
            balanceStorage.reserved -= byAmountUint;
            balanceStorage.available += byAmountUint;
        } else {
            address tokenAddress = reservationStorage.tokenAddress;
            // Cannot increase reservation if token is disabled.
            _verifyTokenEnabled(tokenAddress);

            uint256 byAmountUint = uint256(_byAmount);

            address account = reservationStorage.account;
            // Note: If no longer collateralizable, the calling contract may only decrease collateral usage.
            _requireCollateralizableAndDecreaseApprovedAmount(collateralizable, account, tokenAddress, byAmountUint);

            uint256 available = accountBalances[account][tokenAddress].available;
            if (byAmountUint > available) revert InsufficientCollateral(byAmountUint, available);

            _reservedCollateral = oldReservedAmount + byAmountUint;
            reservationStorage.tokenAmount = _reservedCollateral;

            CollateralBalance storage balanceStorage = accountBalances[account][tokenAddress];
            balanceStorage.reserved += byAmountUint;
            balanceStorage.available = available - byAmountUint;
        }
        _claimableCollateral = Pricing.amountBeforeFee(_reservedCollateral, reservationStorage.feeBasisPoints);
        if (_claimableCollateral == 0) revert ClaimableAmountZero();

        uint256 oldClaimableAmount = reservationStorage.claimableTokenAmount;
        reservationStorage.claimableTokenAmount = _claimableCollateral;
        emit CollateralReservationModified(
            _reservationId,
            oldReservedAmount,
            _reservedCollateral,
            oldClaimableAmount,
            _claimableCollateral
        );
    }

    /// Same as the external function with a similar name, but private for easy reuse.
    function _modifyCollateralizableTokenAllowanceWithSignature(
        address _accountAddress,
        address _collateralizableContractAddress,
        address _tokenAddress,
        int256 _allowanceAdjustment,
        bytes calldata _signature
    ) private {
        {
            bytes32 hash = _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        COLLATERALIZABLE_TOKEN_ALLOWANCE_ADJUSTMENT_TYPEHASH,
                        _collateralizableContractAddress,
                        _tokenAddress,
                        _allowanceAdjustment,
                        _useNonce(_accountAddress, COLLATERALIZABLE_TOKEN_ALLOWANCE_ADJUSTMENT_TYPEHASH)
                    )
                )
            );
            if (!SignatureChecker.isValidSignatureNow(_accountAddress, hash, _signature)) {
                revert InvalidSignature(_accountAddress);
            }
        }

        _authorizedModifyCollateralizableTokenAllowance(
            _accountAddress,
            _collateralizableContractAddress,
            _tokenAddress,
            _allowanceAdjustment
        );
    }

    /// Internal function with the same signature as the one exposed externally so that it may be reused.
    function _releaseAllCollateral(uint96 _reservationId) internal returns (uint256 _totalCollateralReleased) {
        CollateralReservation storage reservationStorage = collateralReservations[_reservationId];
        address collateralizable = reservationStorage.collateralizableContract;
        if (msg.sender != collateralizable) revert Unauthorized(msg.sender);

        _totalCollateralReleased = reservationStorage.tokenAmount;
        address tokenAddress = reservationStorage.tokenAddress;
        address account = reservationStorage.account;

        CollateralBalance storage balanceStorage = accountBalances[account][tokenAddress];
        balanceStorage.available += _totalCollateralReleased;
        balanceStorage.reserved -= _totalCollateralReleased;

        delete collateralReservations[_reservationId];

        emit CollateralReleased(_reservationId, _totalCollateralReleased);
    }

    /**
     * @dev Helper function to ensure the `msg.sender` is approved by governance and the `_accountAddress`. If either
     * has not approved, this transaction will revert.
     * NOTE: This function updates the account's approved amount for the collateralizable address. The caller should
     * use that amount or revert.
     * @param _collateralizableAddress The address of the collateralizable in question.
     * @param _accountAddress The account address that must have approved the calling collateralizable contract.
     * @param _tokenAddress The address of the token being verified and for which the allowance will be decreased.
     * @param _amount the amount that must be approved and by which the collateralizable allowance will be decreased.
     */
    function _requireCollateralizableAndDecreaseApprovedAmount(
        address _collateralizableAddress,
        address _accountAddress,
        address _tokenAddress,
        uint256 _amount
    ) internal {
        if (_collateralizableAddress == _accountAddress) {
            return;
        }
        if (!collateralizableContracts[_collateralizableAddress])
            revert ContractNotApprovedByProtocol(_collateralizableAddress);

        uint256 approvedAmount = accountCollateralizableTokenAllowances[_accountAddress][_collateralizableAddress][
            _tokenAddress
        ];
        if (approvedAmount < _amount)
            revert InsufficientAllowance(
                _collateralizableAddress,
                _accountAddress,
                _tokenAddress,
                _amount,
                approvedAmount
            );

        accountCollateralizableTokenAllowances[_accountAddress][_collateralizableAddress][_tokenAddress] =
            approvedAmount -
            _amount;
    }

    /**
     * @notice Reserves `_accountAddress`'s collateral on behalf of the `_reservingContract` so that it may not be rehypothecated.
     * @dev Note that the full _amount reserved will not be withdrawable via a claim due to withdrawalFeeBasisPoints.
     * The max that can be claimed is _amount * (10000 - withdrawalFeeBasisPoints) / 10000.
     * Use `reserveClaimableCollateral` to reserve a specific claimable amount.
     * @param _reservingContract The contract that called this contract to reserve the collateral.
     * @param _accountAddress The address of the account whose funds are being reserved.
     * @param _tokenAddress The address of the Token being reserved as collateral.
     * @param _reservedCollateral The total amount of the Token being reserved as collateral.
     * @param _claimableCollateral The collateral that may be claimed (factoring in the withdrawal fee).
     * @return _reservationId The ID that can be used to refer to this reservation when claiming or releasing collateral.
     */
    function _reserveCollateral(
        address _reservingContract,
        address _accountAddress,
        address _tokenAddress,
        uint256 _reservedCollateral,
        uint256 _claimableCollateral
    ) private onlyEnabledCollateralTokens(_tokenAddress) returns (uint96 _reservationId) {
        if (_claimableCollateral == 0) revert ClaimableAmountZero();

        _requireCollateralizableAndDecreaseApprovedAmount(
            _reservingContract,
            _accountAddress,
            _tokenAddress,
            _reservedCollateral
        );

        CollateralBalance storage accountBalanceStorage = accountBalances[_accountAddress][_tokenAddress];
        uint256 available = accountBalanceStorage.available;
        if (available < _reservedCollateral) revert InsufficientCollateral(_reservedCollateral, available);
        // sanity check -- this can never happen.
        if (_reservedCollateral < _claimableCollateral)
            revert InsufficientCollateral(_claimableCollateral, _reservedCollateral);

        accountBalanceStorage.available = available - _reservedCollateral;
        accountBalanceStorage.reserved += _reservedCollateral;

        uint16 withdrawalFee = withdrawalFeeBasisPoints;
        // NB: Return fields
        _reservationId = ++collateralReservationNonce;

        collateralReservations[_reservationId] = CollateralReservation(
            _reservingContract,
            _accountAddress,
            _tokenAddress,
            withdrawalFee,
            _reservedCollateral,
            _claimableCollateral
        );

        emit CollateralReserved(
            _reservationId,
            _accountAddress,
            _reservingContract,
            _tokenAddress,
            _reservedCollateral,
            _claimableCollateral,
            withdrawalFee
        );
    }

    /**
     * @dev Transfers tokens from the provided address's available balance to the available balance of the provided
     * destination address without incurring a fee.
     * NOTE: Since this function is private it trusts the caller to do authentication.
     * @param _tokenAddress The token to transfer.
     * @param _fromAddress The token sender's address.
     * @param _amount The amount of tokens being transferred.
     * @param _destinationAddress The token receiver's address.
     */
    function _transferCollateral(
        address _tokenAddress,
        address _fromAddress,
        uint256 _amount,
        address _destinationAddress
    ) private {
        if (_amount == 0 || _fromAddress == _destinationAddress) {
            // NB: 0 amounts should not revert, as transferCollateral may be used by pool contracts to do the reverse of
            // poolCollateral(...). If those contracts do not check for 0, reverting here may cause them to deadlock.
            return;
        }

        CollateralBalance storage fromStorage = accountBalances[_fromAddress][_tokenAddress];
        uint256 fromAvailable = fromStorage.available;
        if (_amount > fromAvailable) {
            revert InsufficientCollateral(_amount, fromAvailable);
        }

        accountBalances[_destinationAddress][_tokenAddress].available += _amount;
        fromStorage.available = fromAvailable - _amount;

        emit CollateralTransferred(_fromAddress, _tokenAddress, _destinationAddress, _amount);
    }

    /**
     * @notice Verifies that the provided collateral token is enabled by the protocol (owner), reverting if it is not.
     * @param _collateralTokenAddress The address of the collateral token being verified.
     */
    function _verifyTokenEnabled(address _collateralTokenAddress) private view {
        if (!collateralTokens[_collateralTokenAddress].enabled) revert TokenNotAllowed(_collateralTokenAddress);
    }

    /**
     * @dev verifies the provided collateralizable deposit approval signature, reverting with InvalidSignature if not valid.
     * Note: this function exists and is virtual so it can be overridden in tests that care to test the deposit
     * functionality but mock or otherwise ignore signature checking.
     * @param _accountAddress The address of the account that should have signed the deposit approval.
     * @param _tokenAddress The address of the token of the deposit approval.
     * @param _amount The amount of the deposit approval.
     * @param _signature The signature being verified.
     */
    function _verifyDepositApprovalSignature(
        address _accountAddress,
        address _tokenAddress,
        uint256 _amount,
        bytes memory _signature
    ) internal virtual {
        bytes32 hash = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    COLLATERALIZABLE_DEPOSIT_APPROVAL_TYPEHASH,
                    msg.sender,
                    _tokenAddress,
                    _amount,
                    _useNonce(_accountAddress, COLLATERALIZABLE_DEPOSIT_APPROVAL_TYPEHASH)
                )
            )
        );
        if (!SignatureChecker.isValidSignatureNow(_accountAddress, hash, _signature)) {
            revert InvalidSignature(_accountAddress);
        }
    }
}
