// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ISFC} from "./interfaces/ISFC.sol";
import {IRateProvider} from "./interfaces/IRateProvider.sol";

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title Beets Staked Sonic
 * @author Beets
 * @notice The contract for Beets Staked Sonic (stS)
 */
contract SonicStaking is
    IRateProvider,
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PermitUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant CLAIM_ROLE = keccak256("CLAIM_ROLE");

    uint256 public constant MAX_PROTOCOL_FEE_BIPS = 10_000;
    uint256 public constant MIN_DEPOSIT = 1e16;
    uint256 public constant MIN_UNDELEGATE_AMOUNT_SHARES = 1e12;
    uint256 public constant MIN_DONATION_AMOUNT = 1e12;
    uint256 public constant MIN_CLAIM_REWARDS_AMOUNT = 1e12;

    enum WithdrawKind {
        POOL,
        VALIDATOR,
        CLAW_BACK
    }

    struct WithdrawRequest {
        WithdrawKind kind;
        uint256 validatorId;
        uint256 assetAmount;
        bool isWithdrawn;
        uint256 requestTimestamp;
        address user;
    }

    /**
     * @dev Each undelegate request is given a unique withdraw id. Once the withdraw delay has passed, the request can be
     * processed, returning the underlying $S tokens to the user.
     */
    mapping(uint256 withdrawId => WithdrawRequest request) private _allWithdrawRequests;

    /**
     * @dev We track all withdraw ids for each user in order to allow for an easier off-chain UX.
     */
    mapping(address user => mapping(uint256 index => uint256 withdrawId)) public userWithdraws;
    mapping(address user => uint256 numWithdraws) public userNumWithdraws;

    /**
     * @dev A reference to the SFC contract
     */
    ISFC public SFC;

    /**
     * @dev A reference to the treasury address
     */
    address public treasury;

    /**
     * @dev The protocol fee in basis points (BIPS)
     */
    uint256 public protocolFeeBIPS;

    /**
     * The delay between undelegation & withdraw
     */
    uint256 public withdrawDelay;

    /**
     * @dev When true, no new deposits are allowed
     */
    bool public depositPaused;

    /**
     * @dev When true, user undelegations are paused.
     */
    bool public undelegatePaused;

    /**
     * @dev When true, user undelegations from pool are paused.
     */
    bool public undelegateFromPoolPaused;

    /**
     * @dev When true, no withdraws are allowed
     */
    bool public withdrawPaused;

    /**
     * @dev The total assets delegated to validators
     */
    uint256 public totalDelegated;

    /**
     * @dev The total assets that is in the pool (undelegated)
     */
    uint256 public totalPool;

    /**
     * @dev Pending operator clawbacked asset amounts are stored here to preserve the invariant. Once the withdraw
     * delay has passed, the assets are returned to the pool.
     */
    uint256 public pendingClawBackAmount;

    /**
     * @dev A counter to track the number of withdraws. Used to generate unique withdraw ids.
     * The current value of the counter is the last withdraw id used.
     */
    uint256 public withdrawCounter;

    event WithdrawDelaySet(address indexed owner, uint256 delay);
    event UndelegatePausedUpdated(address indexed owner, bool newValue);
    event UndelegateFromPoolPausedUpdated(address indexed owner, bool newValue);
    event WithdrawPausedUpdated(address indexed owner, bool newValue);
    event DepositPausedUpdated(address indexed owner, bool newValue);
    event Deposited(address indexed user, uint256 amountAssets, uint256 amountShares);
    event Delegated(uint256 indexed validatorId, uint256 amountAssets);
    event Undelegated(
        address indexed user, uint256 withdrawId, uint256 validatorId, uint256 amountAssets, WithdrawKind kind
    );
    event Withdrawn(address indexed user, uint256 withdrawId, uint256 amountAssets, WithdrawKind kind, bool emergency);
    event Donated(address indexed user, uint256 amountAssets);
    event RewardsClaimed(uint256 amountClaimed, uint256 protocolFee);
    event OperatorClawBackInitiated(uint256 indexed withdrawId, uint256 indexed validatorId, uint256 amountAssets);
    event OperatorClawBackExecuted(uint256 indexed withdrawId, uint256 amountAssetsWithdrawn, bool indexed emergency);
    event ProtocolFeeUpdated(address indexed owner, uint256 indexed newFeeBIPS);
    event TreasuryUpdated(address indexed owner, address indexed newTreasury);

    error DelegateAmountCannotBeZero();
    error UndelegateAmountCannotBeZero();
    error NoDelegationForValidator(uint256 validatorId);
    error UndelegateAmountExceedsDelegated(uint256 validatorId);
    error WithdrawIdDoesNotExist(uint256 withdrawId);
    error WithdrawDelayNotElapsed(uint256 withdrawId);
    error WithdrawAlreadyProcessed(uint256 withdrawId);
    error UnauthorizedWithdraw(uint256 withdrawId);
    error TreasuryAddressCannotBeZero();
    error SFCAddressCannotBeZero();
    error ProtocolFeeTooHigh();
    error DepositTooSmall();
    error DepositPaused();
    error UndelegatePaused();
    error UndelegateFromPoolPaused();
    error WithdrawsPaused();
    error NativeTransferFailed();
    error ProtocolFeeTransferFailed();
    error PausedValueDidNotChange();
    error UndelegateAmountExceedsPool();
    error UserWithdrawsSkipTooLarge();
    error UserWithdrawsMaxSizeCannotBeZero();
    error ArrayLengthMismatch();
    error UndelegateAmountTooSmall();
    error DonationAmountCannotBeZero();
    error DonationAmountTooSmall();
    error UnsupportedWithdrawKind();
    error RewardsClaimedTooSmall();
    error SfcSlashMustBeAccepted(uint256 refundRatio);
    error SenderNotSFC();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializer
     * @param _sfc the address of the SFC contract (is NOT modifiable)
     * @param _treasury The address of the treasury where fees are sent to (is modifiable)
     */
    function initialize(ISFC _sfc, address _treasury) public initializer {
        __ERC20_init("Beets Staked Sonic", "stS");
        __ERC20Burnable_init();
        __ERC20Permit_init("Beets Staked Sonic");

        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        require(address(_sfc) != address(0), SFCAddressCannotBeZero());
        require(_treasury != address(0), TreasuryAddressCannotBeZero());

        SFC = _sfc;
        treasury = _treasury;
        withdrawDelay = 604800 * 2; // 14 days
        undelegatePaused = false;
        undelegateFromPoolPaused = false;
        withdrawPaused = false;
        depositPaused = false;
        protocolFeeBIPS = 1000; // 10%
        withdrawCounter = 100;
    }

    /**
     * @dev This modifier is used to validate a given withdrawId when performing a withdraw. A valid withdraw Id:
     *      - exists
     *      - has not been processed
     *      - has passed the withdraw delay
     */
    modifier withValidWithdrawId(uint256 withdrawId) {
        WithdrawRequest storage request = _allWithdrawRequests[withdrawId];
        uint256 earliestWithdrawTime = request.requestTimestamp + withdrawDelay;

        require(request.requestTimestamp > 0, WithdrawIdDoesNotExist(withdrawId));
        require(_now() >= earliestWithdrawTime, WithdrawDelayNotElapsed(withdrawId));
        require(!request.isWithdrawn, WithdrawAlreadyProcessed(withdrawId));

        _;
    }

    /**
     *
     * Getter & helper functions
     *
     */

    /**
     * @notice Returns the current asset worth of the protocol
     *
     * Considers:
     *  - current staked assets
     *  - current delegated assets
     *  - pending operator withdraws
     */
    function totalAssets() public view returns (uint256) {
        return totalPool + totalDelegated + pendingClawBackAmount;
    }

    /**
     * @notice Returns the amount of asset equivalent to 1 share (with 18 decimals)
     * @dev This function is provided for native compatability with balancer pools
     */
    function getRate() public view returns (uint256) {
        return convertToAssets(1 ether);
    }

    /**
     * @notice Returns the amount of share equivalent to the provided number of assets
     * @param assetAmount the amount of assets to convert
     */
    function convertToShares(uint256 assetAmount) public view returns (uint256) {
        uint256 assetsTotal = totalAssets();
        uint256 totalShares = totalSupply();

        if (assetsTotal == 0 || totalShares == 0) {
            return assetAmount;
        }

        return (assetAmount * totalShares) / assetsTotal;
    }

    /**
     * @notice Returns the amount of asset equivalent to the provided number of shares
     * @param sharesAmount the amount of shares to convert
     */
    function convertToAssets(uint256 sharesAmount) public view returns (uint256) {
        uint256 assetsTotal = totalAssets();
        uint256 totalShares = totalSupply();

        if (assetsTotal == 0 || totalShares == 0) {
            return sharesAmount;
        }

        return (sharesAmount * assetsTotal) / totalShares;
    }

    /**
     * @notice Returns the user's withdraws
     * @param user the user to get the withdraws for
     * @param skip the number of withdraws to skip, used for pagination
     * @param maxSize the maximum number of withdraws to return. It's possible to return less than maxSize. Used for pagination.
     * @param reverseOrder whether to return the withdraws in reverse order (newest first)
     */
    function getUserWithdraws(address user, uint256 skip, uint256 maxSize, bool reverseOrder)
        public
        view
        returns (WithdrawRequest[] memory)
    {
        require(skip < userNumWithdraws[user], UserWithdrawsSkipTooLarge());
        require(maxSize > 0, UserWithdrawsMaxSizeCannotBeZero());

        uint256 remaining = userNumWithdraws[user] - skip;
        uint256 size = remaining < maxSize ? remaining : maxSize;
        WithdrawRequest[] memory items = new WithdrawRequest[](size);

        for (uint256 i = 0; i < size; i++) {
            if (!reverseOrder) {
                // In chronological order we simply skip the first (older) entries
                items[i] = _allWithdrawRequests[userWithdraws[user][skip + i]];
            } else {
                // In reverse order we go back to front, skipping the last (newer) entries. Note that `remaining` will
                // equal the total count if `skip` is 0, meaning we'd start with the newest entry.
                items[i] = _allWithdrawRequests[userWithdraws[user][remaining - 1 - i]];
            }
        }

        return items;
    }

    function getWithdrawRequest(uint256 withdrawId) external view returns (WithdrawRequest memory) {
        return _allWithdrawRequests[withdrawId];
    }

    /**
     *
     * End User Functions
     *
     */

    /**
     * @notice Deposit native assets and mint shares of stS.
     */
    function deposit() external payable nonReentrant returns (uint256) {
        uint256 amount = msg.value;
        require(amount >= MIN_DEPOSIT, DepositTooSmall());
        require(!depositPaused, DepositPaused());

        address user = msg.sender;

        uint256 sharesAmount = convertToShares(amount);

        // Deposits are added to the pool initially. The assets are delegated to validators by the operator
        totalPool += amount;

        _mint(user, sharesAmount);

        emit Deposited(user, amount, sharesAmount);

        return sharesAmount;
    }

    /**
     * @notice Undelegate staked assets. The shares are burnt from the msg.sender and a withdraw request is created.
     * The assets are withdrawable after the `withdrawDelay` has passed.
     * @param validatorId the validator to undelegate from
     * @param amountShares the amount of shares to undelegate
     */
    function undelegate(uint256 validatorId, uint256 amountShares) external nonReentrant returns (uint256) {
        return _undelegate(validatorId, amountShares);
    }

    /**
     * @notice Undelegate staked assets from multiple validators.
     * @dev This function is provided as a convenience for bulking large undelegation requests across several
     * validators. This function is not gas optimized as we operate in an environment where gas is less of a concern.
     * We instead optimize for simpler code that is easier to reason about.
     * @param validatorIds an array of validator ids to undelegate from
     * @param amountShares an array of amounts of shares to undelegate
     */
    function undelegateMany(uint256[] calldata validatorIds, uint256[] calldata amountShares)
        external
        nonReentrant
        returns (uint256[] memory withdrawIds)
    {
        require(validatorIds.length == amountShares.length, ArrayLengthMismatch());

        withdrawIds = new uint256[](validatorIds.length);

        for (uint256 i = 0; i < validatorIds.length; i++) {
            withdrawIds[i] = _undelegate(validatorIds[i], amountShares[i]);
        }
    }

    /**
     * @notice Undelegate from the pool.
     * @dev While always possible to undelegate from the pool, the standard flow is to undelegate from a validator.
     * @param amountShares the amount of shares to undelegate
     */
    function undelegateFromPool(uint256 amountShares) external nonReentrant returns (uint256 withdrawId) {
        require(!undelegateFromPoolPaused, UndelegateFromPoolPaused());
        require(amountShares >= MIN_UNDELEGATE_AMOUNT_SHARES, UndelegateAmountTooSmall());

        uint256 amountToUndelegate = convertToAssets(amountShares);

        require(amountToUndelegate <= totalPool, UndelegateAmountExceedsPool());

        _burn(msg.sender, amountShares);

        // The validatorId is ignored for pool withdrawals
        withdrawId = _createAndPersistWithdrawRequest(WithdrawKind.POOL, 0, amountToUndelegate);

        // The amount is subtracted from the pool, but the assets stay in this contract.
        // The user is able to `withdraw` their assets after the `withdrawDelay` has passed.
        totalPool -= amountToUndelegate;

        emit Undelegated(msg.sender, withdrawId, 0, amountToUndelegate, WithdrawKind.POOL);
    }

    /**
     * @notice Withdraw undelegated assets
     * @param withdrawId the unique withdraw id for the undelegation request
     * @param emergency flag to withdraw without checking the amount, risk to get less assets than what is owed
     */
    function withdraw(uint256 withdrawId, bool emergency) external nonReentrant returns (uint256) {
        return _withdraw(withdrawId, emergency);
    }

    /**
     * @notice Withdraw undelegated assets for a list of withdrawIds
     * @dev This function is provided as a convenience for bulking multiple withdraws into a single tx.
     * @param withdrawIds the unique withdraw ids for the undelegation requests
     * @param emergency flag to withdraw without checking the amount, risk to get less assets than what is owed
     */
    function withdrawMany(uint256[] calldata withdrawIds, bool emergency)
        external
        nonReentrant
        returns (uint256[] memory amountsWithdrawn)
    {
        amountsWithdrawn = new uint256[](withdrawIds.length);

        for (uint256 i = 0; i < withdrawIds.length; i++) {
            amountsWithdrawn[i] = _withdraw(withdrawIds[i], emergency);
        }
    }

    /**
     *
     * OPERATOR functions
     *
     */

    /**
     * @notice Delegate from the pool to a specific validator
     * @param validatorId the ID of the validator to delegate to
     * @param amount the amount of assets to delegate. If an amount greater than the pool is provided, the entire pool
     * is delegated.
     */
    function delegate(uint256 validatorId, uint256 amount)
        external
        nonReentrant
        onlyRole(OPERATOR_ROLE)
        returns (uint256)
    {
        // To prevent DoS vectors and improve operator UX, if an amount larger than the pool is provided,
        // we default to the entire pool.
        if (amount > totalPool) {
            amount = totalPool;
        }

        require(amount > 0, DelegateAmountCannotBeZero());

        totalPool -= amount;
        totalDelegated += amount;

        SFC.delegate{value: amount}(validatorId);

        emit Delegated(validatorId, amount);

        // Return the actual amount delegated since it could be less than the amount provided
        return amount;
    }

    /**
     * @notice Initiate a claw back of delegated assets to a specific validator, the claw back can be executed after `withdrawDelay`
     * @param validatorId the validator to claw back from
     * @param amountAssets the amount of assets to claw back from given validator
     */
    function operatorInitiateClawBack(uint256 validatorId, uint256 amountAssets)
        external
        nonReentrant
        onlyRole(OPERATOR_ROLE)
        returns (uint256 withdrawId, uint256 actualAmountUndelegated)
    {
        require(amountAssets > 0, UndelegateAmountCannotBeZero());

        uint256 amountDelegated = SFC.getStake(address(this), validatorId);

        if (amountAssets > amountDelegated) {
            amountAssets = amountDelegated;
        }

        require(amountDelegated > 0, NoDelegationForValidator(validatorId));

        withdrawId = _createAndPersistWithdrawRequest(WithdrawKind.CLAW_BACK, validatorId, amountAssets);

        totalDelegated -= amountAssets;

        // The amount clawed back is still considered part of the total assets.
        // As such, we need to track the pending amount to ensure the invariant is maintained.
        pendingClawBackAmount += amountAssets;

        SFC.undelegate(validatorId, withdrawId, amountAssets);

        emit OperatorClawBackInitiated(withdrawId, validatorId, amountAssets);

        actualAmountUndelegated = amountAssets;
    }

    /**
     * @notice Execute a claw back, withdrawing assets to the pool
     * @dev This is the only operation that allows for the rate to decrease.
     * @param withdrawId the unique withdrawId for the claw back request
     * @param emergency when true, the operator acknowledges that the amount withdrawn may be less than what is owed,
     * potentially decreasing the rate.
     */
    function operatorExecuteClawBack(uint256 withdrawId, bool emergency)
        external
        nonReentrant
        onlyRole(OPERATOR_ROLE)
        withValidWithdrawId(withdrawId)
        returns (uint256)
    {
        WithdrawRequest storage request = _allWithdrawRequests[withdrawId];

        require(request.kind == WithdrawKind.CLAW_BACK, UnsupportedWithdrawKind());

        // We allow any address with the operator role to execute a pending clawback.
        // It does not need to be the same operator that initiated the call.

        request.isWithdrawn = true;

        // Potential slashing events are handled by _withdrawFromSFC
        uint256 actualWithdrawnAmount = _withdrawFromSFC(request.validatorId, withdrawId, emergency);

        // we need to subtract the request amount from the pending amount since that is the value that was added during
        // the initiate claw back operation.
        pendingClawBackAmount -= request.assetAmount;

        // We then account for the actual amount we were able to withdraw
        // In the instance of a realized slashing event, this will result in a drop in the rate.
        totalPool += actualWithdrawnAmount;

        emit OperatorClawBackExecuted(withdrawId, actualWithdrawnAmount, emergency);

        return actualWithdrawnAmount;
    }

    /**
     * @notice Donate assets to the pool
     * @dev Donations are added to the pool, causing the rate to increase. Only the operator can donate.
     */
    function donate() external payable onlyRole(OPERATOR_ROLE) {
        uint256 donationAmount = msg.value;

        require(donationAmount > 0, DonationAmountCannotBeZero());
        // Since convertToAssets is a round down operation, very small donations can cause the rate to not grow.
        // So, we enforce a minimum donation amount.
        require(donationAmount >= MIN_DONATION_AMOUNT, DonationAmountTooSmall());

        totalPool += donationAmount;

        emit Donated(msg.sender, donationAmount);
    }

    /**
     * @notice Pause all protocol functions
     * @dev The operator is given the power to pause the protocol, giving them the power to take action in the case of
     *      an emergency. Enabling the protocol is reserved for the admin.
     */
    function pause() external onlyRole(OPERATOR_ROLE) {
        _setDepositPaused(true);
        _setUndelegatePaused(true);
        _setUndelegateFromPoolPaused(true);
        _setWithdrawPaused(true);
    }

    /**
     *
     * DEFAULT_ADMIN_ROLE functions
     *
     */

    /**
     * @notice Set withdraw delay
     * @param delay the new delay
     */
    function setWithdrawDelay(uint256 delay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        withdrawDelay = delay;
        emit WithdrawDelaySet(msg.sender, delay);
    }

    /**
     * @notice Pause/unpause user undelegations
     * @param newValue the desired value of the switch
     */
    function setUndelegatePaused(bool newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setUndelegatePaused(newValue);
    }

    /**
     * @notice Pause/unpause user undelegations from pool
     * @param newValue the desired value of the switch
     */
    function setUndelegateFromPoolPaused(bool newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setUndelegateFromPoolPaused(newValue);
    }

    /**
     * @notice Pause/unpause user withdraws
     * @param newValue the desired value of the switch
     */
    function setWithdrawPaused(bool newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setWithdrawPaused(newValue);
    }

    /**
     * @notice Pause/unpause deposit function
     * @param newValue the desired value of the switch
     */
    function setDepositPaused(bool newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDepositPaused(newValue);
    }

    /**
     * @notice Update the treasury address
     * @param newTreasury the new treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasury != address(0), TreasuryAddressCannotBeZero());

        treasury = newTreasury;

        emit TreasuryUpdated(msg.sender, newTreasury);
    }

    /**
     * @notice Update the protocol fee
     * @param newFeeBIPS the value of the fee (in BIPS)
     */
    function setProtocolFeeBIPS(uint256 newFeeBIPS) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFeeBIPS <= MAX_PROTOCOL_FEE_BIPS, ProtocolFeeTooHigh());

        protocolFeeBIPS = newFeeBIPS;

        emit ProtocolFeeUpdated(msg.sender, newFeeBIPS);
    }

    /**
     * @notice Claim rewards from all contracts and add them to the pool
     * @param validatorIds an array of validator IDs to claim rewards from
     */
    function claimRewards(uint256[] calldata validatorIds) external nonReentrant onlyRole(CLAIM_ROLE) {
        uint256 balanceBefore = address(this).balance;

        for (uint256 i = 0; i < validatorIds.length; i++) {
            uint256 rewards = SFC.pendingRewards(address(this), validatorIds[i]);

            if (rewards > 0) {
                SFC.claimRewards(validatorIds[i]);
            }
        }

        uint256 totalRewardsClaimed = address(this).balance - balanceBefore;

        // We enforce a minimum amount to ensure the math stays well behaved
        require(totalRewardsClaimed > MIN_CLAIM_REWARDS_AMOUNT, RewardsClaimedTooSmall());

        uint256 protocolFee = 0;

        if (protocolFeeBIPS > 0) {
            protocolFee = (totalRewardsClaimed * protocolFeeBIPS) / MAX_PROTOCOL_FEE_BIPS;
            totalPool += totalRewardsClaimed - protocolFee;

            (bool protocolFeesClaimed,) = treasury.call{value: protocolFee}("");
            require(protocolFeesClaimed, ProtocolFeeTransferFailed());
        } else {
            totalPool += totalRewardsClaimed;
        }

        emit RewardsClaimed(totalRewardsClaimed, protocolFee);
    }

    /**
     *
     * Internal functions
     *
     */
    function _undelegate(uint256 validatorId, uint256 amountShares) internal returns (uint256 withdrawId) {
        require(!undelegatePaused, UndelegatePaused());
        require(amountShares >= MIN_UNDELEGATE_AMOUNT_SHARES, UndelegateAmountTooSmall());

        uint256 amountAssets = convertToAssets(amountShares);
        uint256 amountDelegated = SFC.getStake(address(this), validatorId);

        require(amountAssets <= amountDelegated, UndelegateAmountExceedsDelegated(validatorId));

        _burn(msg.sender, amountShares);

        withdrawId = _createAndPersistWithdrawRequest(WithdrawKind.VALIDATOR, validatorId, amountAssets);

        totalDelegated -= amountAssets;

        SFC.undelegate(validatorId, withdrawId, amountAssets);

        emit Undelegated(msg.sender, withdrawId, validatorId, amountAssets, WithdrawKind.VALIDATOR);
    }

    function _withdraw(uint256 withdrawId, bool emergency) internal withValidWithdrawId(withdrawId) returns (uint256) {
        require(!withdrawPaused, WithdrawsPaused());

        // We've already checked that the withdrawId exists and is valid, so we can safely access the request
        WithdrawRequest storage request = _allWithdrawRequests[withdrawId];

        require(msg.sender == request.user, UnauthorizedWithdraw(withdrawId));

        // Claw backs can only be executed by the operator via the operatorExecuteClawBack function
        require(request.kind != WithdrawKind.CLAW_BACK, UnsupportedWithdrawKind());

        request.isWithdrawn = true;

        uint256 amountWithdrawn = 0;

        if (request.kind == WithdrawKind.POOL) {
            // An undelegate from the pool only effects the internal accounting of this contract.
            // The amount has already been subtracted from the pool and the assets were already owned by this contract.
            // The amount withdrawn is always the same as the request amount.
            amountWithdrawn = request.assetAmount;
        } else {
            //The only WithdrawKind left is VALIDATOR

            // Potential slashing events are handled by _withdrawFromSFC
            amountWithdrawn = _withdrawFromSFC(request.validatorId, withdrawId, emergency);
        }

        address user = msg.sender;
        (bool withdrawnToUser,) = user.call{value: amountWithdrawn}("");
        require(withdrawnToUser, NativeTransferFailed());

        emit Withdrawn(user, withdrawId, amountWithdrawn, request.kind, emergency);

        // Return the actual amount withdrawn
        return amountWithdrawn;
    }

    function _withdrawFromSFC(uint256 validatorId, uint256 withdrawId, bool emergency)
        internal
        returns (uint256 actualAmountWithdrawn)
    {
        uint256 balanceBefore = address(this).balance;
        bool isSlashed = SFC.isSlashed(validatorId);

        if (isSlashed) {
            uint256 refundRatio = SFC.slashingRefundRatio(validatorId);

            // The caller is required to acknowledge they understand their stake has been slashed
            // by setting emergency to true.
            require(emergency, SfcSlashMustBeAccepted(refundRatio));

            // When a validator isSlashed, a refundRatio of 0 can have two different meanings:
            // 1. The validator has been slashed but the percentage has not yet been set
            // 2. The validator has been fully slashed

            // In either case, a call to SFC.withdraw when isSlashed && refundRatio == 0 will revert with
            // StakeIsFullySlashed. So, we cannot make the call to SFC.withdraw.

            // In the instance that isSlashed == true && refundRatio == 0 && emergency == true, the caller is
            // acknowledging that their delegation has been fully slashed.

            // In the instance that refundRatio != 0, a slashing refund ratio has been set and can now be realized
            // by calling SFC.withdraw
            if (refundRatio != 0) {
                SFC.withdraw(validatorId, withdrawId);
            }
        } else {
            SFC.withdraw(validatorId, withdrawId);
        }

        // The SFC sends native assets to this contract, increasing it's balance. We measure the change
        // in balance before and after the call to get the actual amount withdrawn.
        actualAmountWithdrawn = address(this).balance - balanceBefore;
    }

    function _createAndPersistWithdrawRequest(WithdrawKind kind, uint256 validatorId, uint256 amount)
        internal
        returns (uint256 withdrawId)
    {
        address user = msg.sender;
        withdrawId = _incrementWithdrawCounter();
        WithdrawRequest storage request = _allWithdrawRequests[withdrawId];

        request.kind = kind;
        request.requestTimestamp = _now();
        request.user = user;
        request.assetAmount = amount;
        request.validatorId = validatorId;
        request.isWithdrawn = false;

        // We store the user's withdraw ids to allow for easier off-chain processing.
        userWithdraws[user][userNumWithdraws[user]] = withdrawId;
        userNumWithdraws[user]++;
    }

    function _now() internal view returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev Given the size of uint256 and the maximum supply of $S, we can safely assume that this will never overflow
     * with a 1e18 minimum undelegate amount.
     */
    function _incrementWithdrawCounter() internal returns (uint256) {
        withdrawCounter++;

        return withdrawCounter;
    }

    function _setUndelegatePaused(bool newValue) internal {
        require(undelegatePaused != newValue, PausedValueDidNotChange());

        undelegatePaused = newValue;
        emit UndelegatePausedUpdated(msg.sender, newValue);
    }

    function _setUndelegateFromPoolPaused(bool newValue) internal {
        require(undelegateFromPoolPaused != newValue, PausedValueDidNotChange());

        undelegateFromPoolPaused = newValue;
        emit UndelegateFromPoolPausedUpdated(msg.sender, newValue);
    }

    function _setWithdrawPaused(bool newValue) internal {
        require(withdrawPaused != newValue, PausedValueDidNotChange());

        withdrawPaused = newValue;
        emit WithdrawPausedUpdated(msg.sender, newValue);
    }

    function _setDepositPaused(bool newValue) internal {
        require(depositPaused != newValue, PausedValueDidNotChange());

        depositPaused = newValue;

        emit DepositPausedUpdated(msg.sender, newValue);
    }

    /**
     *
     * OWNER functions
     *
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice To receive native asset rewards from SFC
     */
    receive() external payable {
        require(msg.sender == address(SFC), SenderNotSFC());
    }
}
