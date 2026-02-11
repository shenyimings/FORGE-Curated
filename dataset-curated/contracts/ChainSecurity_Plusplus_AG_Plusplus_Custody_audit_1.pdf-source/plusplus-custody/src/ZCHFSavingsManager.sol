// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {RedemptionLimiter} from "./RedemptionLimiter.sol";

/// @notice Minimal ERC-20 interface used for basic token operations
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

/// @notice Minimal interface for interacting with the Frankencoin savings module
interface IFrankencoinSavings {
    function save(uint192 amount) external;
    function currentTicks() external view returns (uint64);
    function currentRatePPM() external view returns (uint24);
    function INTEREST_DELAY() external view returns (uint64);
    function withdraw(address target, uint192 amount) external returns (uint256);
}

/// @title ZCHFSavingsManager
/// @notice Manages batch deposits into the Frankencoin Savings Module with delayed interest and fee deduction.
/// @dev Tracks each deposit independently using an identifier, computes accrued interest using the external tick-based system,
/// and deducts a fixed annual fee on interest. Only entities with OPERATOR_ROLE can create/redeem deposits.
/// Funds can only be received by addresses with RECEIVER_ROLE.
/// @author Plusplus AG (dev@plusplus.swiss)
/// @custom:security-contact security@plusplus.swiss
contract ZCHFSavingsManager is AccessControl, ReentrancyGuard, RedemptionLimiter {
    /// @notice Role required to create or redeem deposits
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Role required to receive withdrawn or rescued funds
    bytes32 public constant RECEIVER_ROLE = keccak256("RECEIVER_ROLE");

    /// @notice Annual fee in parts per million (ppm). For example, 12,500 ppm = 1.25% yearly.
    /// @dev Uint24 is used by the savings module for all ppm values.
    uint24 public constant FEE_ANNUAL_PPM = 12_500;

    /// @notice Struct representing a single tracked customer deposit
    /// @dev `ticksAtDeposit` includes a delay to skip initial non-interest-bearing period.
    struct Deposit {
        /// @dev Amount originally deposited into the savings module (principal). Uint192 is used by the savings module for all amount variables.
        uint192 initialAmount;
        /// @dev Block timestamp when the deposit was created. Uint40 is used by the savings module for all timestamps.
        uint40 createdAt;
        /// @dev Tick count (ppm-seconds) at which interest accrual starts for this deposit. Uint64 is used by the savings module for all tick variables.
        uint64 ticksAtDeposit;
    }

    /// @notice Mapping of unique deposit identifiers to deposit metadata
    /// @dev The identifier is a hashed customer ID, to retain pseudonimity on-chain.
    ///      No way to enumerate deposits as it is not needed by the contract logic. Use events or identifier lists.
    mapping(bytes32 => Deposit) public deposits;

    IERC20 public immutable ZCHF;
    IFrankencoinSavings public immutable savingsModule;

    /// @notice Emitted when a new deposit is created
    /// @param identifier Hashed customer ID
    /// @param amount The amount deposited in ZCHF
    event DepositCreated(bytes32 indexed identifier, uint192 amount);

    /// @notice Emitted when a deposit is redeemed
    /// @param identifier Hashed customer ID
    /// @param totalAmount Amount withdrawn (principal + net interest)
    event DepositRedeemed(bytes32 indexed identifier, uint192 totalAmount);

    // ===========================
    // Custom Errors
    // ===========================

    /// @notice Thrown when a deposit with the given identifier already exists
    error DepositAlreadyExists(bytes32 identifier);

    /// @notice Thrown when a deposit with the given identifier is not found
    error DepositNotFound(bytes32 identifier);

    /// @notice Thrown when expected positive amount is given as zero
    error ZeroAmount();

    /// @notice Thrown when transferFrom fails
    error TransferFromFailed(address from, address to, uint256 amount);

    /// @notice Thrown when an address lacks the RECEIVER_ROLE
    error InvalidReceiver(address receiver);

    /// @notice Thrown when input arrays do not match in length or other argument errors occur
    error InvalidArgument();

    /// @notice Thrown when withdrawal from the savings module is not the expected amount
    error UnexpectedWithdrawalAmount();

    /// @notice Initializes the manager and grants initial roles
    /// @dev This contract grants itself RECEIVER_ROLE for internal redemptions.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE
    /// @param zchfToken Address of the deployed ZCHF token contract
    /// @param savingsModule_ Address of the deployed Frankencoin savings module
    constructor(address admin, address zchfToken, address savingsModule_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RECEIVER_ROLE, address(this));
        ZCHF = IERC20(zchfToken);
        savingsModule = IFrankencoinSavings(savingsModule_);

        // Not needed as the savings module is a registered minter with max allowance to move funds
        // ZCHF.approve(address(savingsModule), type(uint256).max);
    }

    /// @notice Sets the daily redemption limit for a user (in ZCHF).
    /// @dev Only callable by DEFAULT_ADMIN_ROLE. See {RedemptionLimiter-_setDailyRedemptionLimit}.
    /// @param user The operator whose limit is being set.
    /// @param dailyLimit The daily quota (in ZCHF) for the rolling window.
    function setDailyLimit(address user, uint192 dailyLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDailyRedemptionLimit(user, dailyLimit);
    }

    /// @notice Creates one or more deposits and forwards the total amount to the savings module.
    /// @dev Each deposit is assigned a unique identifier and accrues interest starting after a fixed delay.
    ///      Reverts if any identifier already exists or any amount is zero. Saves once for all.
    /// @param identifiers Unique identifiers for each deposit. Is a hash of the customer ID (must not be reused).
    /// @param amounts Corresponding deposit amounts (must match identifiers length, non-zero)
    /// @param source The address providing the ZCHF. If `address(this)`, will skip pulling funds.
    function createDeposits(bytes32[] calldata identifiers, uint192[] calldata amounts, address source)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        uint256 len = identifiers.length;
        if (len != amounts.length) revert InvalidArgument();

        uint256 totalAmount;

        // Pre-validate and sum amounts
        for (uint256 i = 0; i < len; ++i) {
            uint192 amt = amounts[i];

            if (amt == 0) revert ZeroAmount();

            totalAmount += amt;
        }

        // Pull funds from source, if applicable
        if (source != address(this)) {
            bool success = ZCHF.transferFrom(source, address(this), totalAmount);
            if (!success) revert TransferFromFailed(source, address(this), totalAmount);
        }

        // In theory, totalAmount can overflow when cast down. This must be an Input error.
        if (totalAmount > type(uint192).max) revert InvalidArgument();

        // Forward to savings module in a single save() call
        savingsModule.save(uint192(totalAmount));

        // Interest starts accruing only after a fixed delay (defined in savings module).
        // Precompute common tick baseline and post-delay snapshot
        uint64 baseTicks = savingsModule.currentTicks();
        uint24 rate = savingsModule.currentRatePPM();
        uint64 delay = savingsModule.INTEREST_DELAY();
        uint64 tickDelay = uint64(uint256(rate) * delay);
        uint64 ticksAtDeposit = baseTicks + tickDelay;
        uint40 ts = uint40(block.timestamp);

        // Record each individual deposit
        for (uint256 i = 0; i < len; ++i) {
            bytes32 id = identifiers[i];
            uint192 amt = amounts[i];

            if (deposits[id].createdAt != 0) revert DepositAlreadyExists(id);
            deposits[id] = Deposit({initialAmount: amt, createdAt: ts, ticksAtDeposit: ticksAtDeposit});

            emit DepositCreated(id, amt);
        }
    }

    /// @notice Redeems a batch of deposits and forwards the total redeemed funds (principal + net interest) to a receiver.
    /// @dev Each deposit is deleted after redemption. The total amount is withdrawn in a single call to the savings module.
    ///      Operators must respect their daily redemption limit.
    /// @param identifiers Unique identifiers (hashed customer IDs) of the deposits to redeem
    /// @param receiver Address that will receive the ZCHF; must have RECEIVER_ROLE
    function redeemDeposits(bytes32[] calldata identifiers, address receiver)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        if (!hasRole(RECEIVER_ROLE, receiver)) revert InvalidReceiver(receiver);

        uint192 totalAmount;

        // Process each identifier and sum withdrawal amounts
        for (uint256 i = 0; i < identifiers.length; ++i) {
            bytes32 id = identifiers[i];
            Deposit storage deposit = deposits[id];
            uint192 initialAmount = deposit.initialAmount;

            if (initialAmount == 0) revert DepositNotFound(id);

            (, uint192 netInterest) = getDepositDetails(id);
            uint192 totalForDeposit = initialAmount + netInterest;

            emit DepositRedeemed(id, totalForDeposit);

            totalAmount += totalForDeposit;
            delete deposits[id];
        }

        _useMyRedemptionQuota(totalAmount);

        // Withdraw the full amount from savings to receiver and confirm the amount
        // (Savings module will silently return less if not enough available)
        uint256 withdrawn = savingsModule.withdraw(receiver, totalAmount);
        if (withdrawn != totalAmount) revert UnexpectedWithdrawalAmount();
    }

    /// @notice Returns the current principal and net interest for a given deposit
    /// @dev Accrual is calculated from `ticksAtDeposit` to current tick count.
    /// @param identifier The unique identifier of the deposit
    /// @return initialAmount The originally deposited amount (principal)
    /// @return netInterest The interest accrued after fee deduction
    function getDepositDetails(bytes32 identifier) public view returns (uint192 initialAmount, uint192 netInterest) {
        Deposit storage deposit = deposits[identifier];

        initialAmount = deposit.initialAmount;
        if (initialAmount == 0) return (0, 0);

        uint40 createdAt = deposit.createdAt;
        uint64 currentTicks = savingsModule.currentTicks();

        uint64 ticksAtDeposit = deposit.ticksAtDeposit;
        uint64 deltaTicks = currentTicks > ticksAtDeposit ? currentTicks - ticksAtDeposit : 0;

        // Total interest accrued over deposit lifetime (accounts for initial delay via `ticksAtDeposit`)
        uint256 totalInterest = (uint256(deltaTicks) * initialAmount) / 1_000_000 / 365 days;

        // Fee is time-based, not tick-based. Converts elapsed time to tick-equivalent.
        uint256 duration = block.timestamp - createdAt;
        uint256 feeableTicks = duration * FEE_ANNUAL_PPM;

        // Cap the fee to ensure it's never higher than the actual earned ticks
        uint256 feeTicks = feeableTicks < deltaTicks ? feeableTicks : deltaTicks;

        uint256 fee = feeTicks * initialAmount / 1_000_000 / 365 days;

        // Net interest must not be negative
        // The following clamp is not strictly required, since we clamp the feeTicks above.
        // It is still included to be explicit and futureproof.
        netInterest = totalInterest > fee ? uint192(totalInterest - fee) : 0;

        return (initialAmount, netInterest);
    }

    /// @notice Forwards ZCHF to the savings module without creating a tracked deposit.
    /// @dev Useful for correcting underfunding or over-withdrawal. Funds are added on behalf of this contract.
    /// @param source The address from which ZCHF should be pulled. Use `address(this)` if funds are already held.
    /// @param amount The amount of ZCHF to forward. Caller must have OPERATOR_ROLE.
    function addZCHF(address source, uint192 amount) public onlyRole(OPERATOR_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();

        // Pull ZCHF from external source if needed
        if (source != address(this)) {
            bool success = ZCHF.transferFrom(source, address(this), amount);
            if (!success) revert TransferFromFailed(source, address(this), amount);
        }

        // Save on behalf of the contract (untracked)
        savingsModule.save(amount);
    }

    /// @notice Moves funds from the savings module to a receiver, either to collect fees or migrate balances.
    /// @dev Reverts if not enough funds are available in the savings module.
    /// @param receiver Must have RECEIVER_ROLE
    /// @param amount The maximum amount of ZCHF to move
    function moveZCHF(address receiver, uint192 amount) public onlyRole(OPERATOR_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (!hasRole(RECEIVER_ROLE, receiver)) revert InvalidReceiver(receiver);

        uint256 movedAmount = savingsModule.withdraw(receiver, amount);
        if (movedAmount != amount) revert UnexpectedWithdrawalAmount();
    }

    /// @notice Recovers arbitrary ERC-20 tokens or ETH accidentally sent to this contract
    /// @dev If a token doesn't follow the ERC-20 specs, rescue can not be guaranteed
    /// @param token Address of the token to recover (use zero address for ETH)
    /// @param receiver Must have RECEIVER_ROLE
    /// @param amount The amount to recover
    function rescueTokens(address token, address receiver, uint256 amount)
        public
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (!hasRole(RECEIVER_ROLE, receiver)) revert InvalidReceiver(receiver);
        if (token == address(0)) {
            payable(receiver).transfer(amount);
        } else {
            IERC20(token).transfer(receiver, amount);
        }
    }
}
