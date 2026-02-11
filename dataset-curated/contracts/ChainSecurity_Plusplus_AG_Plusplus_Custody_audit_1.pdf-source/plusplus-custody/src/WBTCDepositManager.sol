// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {RedemptionLimiter} from "./RedemptionLimiter.sol";

/// @notice Minimal ERC-20 interface used by {BTCDepositManager}.
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

/// @title WBTCDepositManager
/// @notice Manages WBTC deposits subject to linear, non-compounding custody fees over time.
/// @dev Tracks per-deposit state for principal and start time. Applies a fixed, linear fee
///      over elapsed time. Global aggregates allow constant-time computation of
///      total value and fee extraction. Designed for gas-efficient custody accounting.
/// @author Plusplus AG (dev@plusplus.swiss)
/// @custom:security-contact security@plusplus.swiss

contract WBTCDepositManager is AccessControl, ReentrancyGuard, RedemptionLimiter {
    /// @notice Role required to create and redeem deposits as well as collect fees
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Role required to receive transferred, redeemed or collected WBTC from this contract
    bytes32 public constant RECEIVER_ROLE = keccak256("RECEIVER_ROLE");

    /// @notice WBTC token contract (assumes 8 decimals)
    IERC20 public immutable WBTC;

    /// @notice Annual custody fee in parts per million (ppm). 9_500 = 0.95% per year.
    uint256 public constant FEE_ANNUAL_PPM = 9_500;

    /// @notice Metadata for each individual deposit
    /// @dev Deposits decay over time starting from `startTime` at fixed rate applied to `principal`. Packed for gas efficiency.
    ///      No way to enumerate deposits as it is not needed by the contract logic. Use events or identifier lists.
    struct Deposit {
        uint192 principal; // Amount of WBTC deposited
        uint64 startTime; // Timestamp when the deposit was created
    }

    /// @notice Mapping from deposit ID to deposit metadata
    mapping(bytes32 => Deposit) public deposits;

    /// @notice Total principal currently deposited (across all deposits)
    /// @dev Enables constant-time global fee/value computations.
    uint256 public totalPrincipal;

    /// @notice Aggregate of principal * startTime for all active deposits
    /// @dev Enables constant-time global fee/value computations.
    uint256 public principalTimeProductSum;

    /// @notice Emitted when a deposit is created
    /// @param identifier Unique identifier for the deposit (hashed customer ID)
    /// @param amount Amount of WBTC deposited
    event DepositCreated(bytes32 indexed identifier, uint256 amount);

    /// @notice Emitted when a deposit is redeemed
    /// @param identifier Unique identifier for the deposit (hashed customer ID)
    /// @param value Net amount returned to receiver (principal minus fees)
    event DepositRedeemed(bytes32 indexed identifier, uint256 value);

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

    /// @notice Thrown when transfer fails
    error TransferFailed(address to, uint256 amount);

    /// @notice Thrown when an address lacks the RECEIVER_ROLE
    error InvalidReceiver(address receiver);

    /// @notice Thrown when input arrays do not match in length or other argument errors occur
    error InvalidArgument();

    /// @notice Thrown when the source address is invalid (e.g. self)
    error InvalidSource();

    /// @notice Thrown when trying to rescue WBTC from this contract
    error CannotRescueWBTC();

    /// @notice Initializes the WBTCDepositManager and grants initial roles
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE
    /// @param wbtcToken Address of the deployed WBTC token contract
    /// @dev Contract grants itself RECEIVER_ROLE to enable controlled internal transfers.
    constructor(address admin, address wbtcToken) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RECEIVER_ROLE, address(this));
        WBTC = IERC20(wbtcToken);
    }

    /// @notice Sets the daily redemption limit for a user (in WBTC).
    /// @dev Only callable by DEFAULT_ADMIN_ROLE. See {RedemptionLimiter-_setDailyRedemptionLimit}.
    /// @param user The operator whose limit is being set.
    /// @param dailyLimit The daily quota (in WBTC) for the rolling window.
    function setDailyLimit(address user, uint192 dailyLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDailyRedemptionLimit(user, dailyLimit);
    }

    /// @notice Creates one or more WBTC deposits from the given source address.
    /// @dev Each deposit must use a unique identifier and a non-zero amount.
    /// Funds are pulled from `source` and stored in this contract.
    /// Aggregates (`totalPrincipal`, `principalTimeProductSum`) are updated for constant-time global computation.
    /// Emits a `DepositCreated` event per deposit.
    /// @param identifiers Unique identifiers for each deposit (hashed customer IDs)
    /// @param amounts Corresponding deposit amounts in WBTC (must match length of `identifiers`)
    /// @param source Address supplying the WBTC; cannot be the contract itself
    function createDeposits(bytes32[] calldata identifiers, uint192[] calldata amounts, address source)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        if (source == address(this)) revert InvalidSource();

        uint256 len = identifiers.length;
        if (len != amounts.length) revert InvalidArgument();

        uint256 totalAmount;
        for (uint256 i = 0; i < len; ++i) {
            bytes32 id = identifiers[i];
            uint192 amount = amounts[i];
            if (amount == 0) revert ZeroAmount();
            if (deposits[id].principal != 0) revert DepositAlreadyExists(id);

            deposits[id] = Deposit({principal: amount, startTime: uint64(block.timestamp)});

            emit DepositCreated(id, amount);
            totalAmount += amount;
        }

        totalPrincipal += totalAmount;
        principalTimeProductSum += totalAmount * block.timestamp;

        bool success = WBTC.transferFrom(source, address(this), totalAmount);
        if (!success) revert TransferFromFailed(source, address(this), totalAmount);
    }

    /// @notice Redeems one or more deposits and transfers the net value to the receiver.
    /// @dev Computes current value for each deposit.
    /// Each deposit is deleted after redemption. Emits a `DepositRedeemed` event per ID.
    /// Total transfer is done in a single WBTC call for gas efficiency.
    /// Operators must respect their daily redemption limit.
    /// @param identifiers Deposit identifiers to redeem (must exist and be non-zero)
    /// @param receiver Recipient address for the redeemed value; must have RECEIVER_ROLE
    function redeemDeposits(bytes32[] calldata identifiers, address receiver)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        if (!hasRole(RECEIVER_ROLE, receiver)) revert InvalidReceiver(receiver);

        uint256 totalValue;
        uint256 identifiersLength = identifiers.length;
        for (uint256 i = 0; i < identifiersLength; ++i) {
            bytes32 id = identifiers[i];
            Deposit memory deposit = deposits[id];
            uint192 principal = deposit.principal;
            if (principal == 0) revert DepositNotFound(id);

            uint256 value = depositValue(id);
            totalValue += value;

            totalPrincipal -= principal;
            principalTimeProductSum -= principal * deposit.startTime;

            delete deposits[id];
            emit DepositRedeemed(id, value);
        }

        _useMyRedemptionQuota(totalValue);

        bool success = WBTC.transfer(receiver, totalValue);
        if (!success) revert TransferFailed(receiver, totalValue);
    }

    /// @notice Returns the current value of a single deposit, after applying linear custody fees.
    /// @dev Custody fee is applied linearly from its `startTime` using `FEE_ANNUAL_PPM`.
    /// @param identifier Unique identifier of the deposit
    /// @return currentValue The current value of the deposit after fee deduction
    function depositValue(bytes32 identifier) public view returns (uint256 currentValue) {
        Deposit storage deposit = deposits[identifier];
        uint192 principal = deposit.principal;
        if (principal == 0) return 0;

        uint256 duration = block.timestamp - deposit.startTime;
        uint256 totalFees = (duration * principal) * FEE_ANNUAL_PPM / 1_000_000 / 365 days;
        currentValue = principal > totalFees ? principal - totalFees : 0;
        return currentValue;
    }

    /// @notice Computes the total current value of all deposits, after applying linear custody fees.
    /// @dev Uses global aggregates to calculate total value without looping through individual deposits.
    /// @return totalValue Sum of all remaining principal after fees
    function totalDepositValue() public view returns (uint256 totalValue) {
        uint256 elapsedProduct = block.timestamp * totalPrincipal - principalTimeProductSum;
        uint256 totalFees = elapsedProduct * FEE_ANNUAL_PPM / 1_000_000 / 365 days;
        totalValue = totalPrincipal > totalFees ? totalPrincipal - totalFees : 0;
        return totalValue;
    }

    /// @notice Computes the total accumulated custody fees currently held by the contract.
    /// @dev Calculated as the difference between WBTC balance and total deposit value.
    /// @return fees Amount of WBTC attributable to fees (i.e., not owed to depositors)
    function accumulatedFees() public view returns (uint256 fees) {
        uint256 totalValue = totalDepositValue();
        uint256 currentBalance = WBTC.balanceOf(address(this));
        fees = currentBalance > totalValue ? currentBalance - totalValue : 0;
        return fees;
    }

    /// @notice Transfers all currently accumulated fees to a receiver address.
    /// @dev Only callable by OPERATOR_ROLE. Receiver must have RECEIVER_ROLE.
    /// @param receiver The recipient of the fees
    /// @return collected The amount of fees transferred
    function collectFees(address receiver) external onlyRole(OPERATOR_ROLE) nonReentrant returns (uint256 collected) {
        if (!hasRole(RECEIVER_ROLE, receiver)) revert InvalidReceiver(receiver);
        collected = accumulatedFees();
        bool success = WBTC.transfer(receiver, collected);
        if (!success) revert TransferFailed(receiver, collected);
        return collected;
    }

    /// @notice Recovers ERC-20 tokens or ETH accidentally sent to this contract.
    /// @dev WBTC cannot be rescued to protect deposit accounting integrity.
    /// ETH is rescued when `token` is the zero address. Recipient must have RECEIVER_ROLE.
    /// @param token Address of the token to rescue (use address(0) for ETH)
    /// @param receiver Destination address for the rescued funds
    /// @param amount Amount of tokens or ETH to transfer
    function rescueTokens(address token, address receiver, uint256 amount)
        public
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        if (token == address(WBTC)) revert CannotRescueWBTC();
        if (amount == 0) revert ZeroAmount();
        if (!hasRole(RECEIVER_ROLE, receiver)) revert InvalidReceiver(receiver);
        if (token == address(0)) {
            payable(receiver).transfer(amount);
        } else {
            IERC20(token).transfer(receiver, amount);
        }
    }

    /// @notice Transfers WBTC held by the contract to a receiver (manual override / migration).
    /// @dev Only callable by DEFAULT_ADMIN_ROLE. Receiver must have RECEIVER_ROLE.
    /// No internal accounting is updated. Use with caution.
    /// @param receiver Recipient address for the WBTC
    /// @param amount Amount of WBTC to transfer
    function moveWBTC(address receiver, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (!hasRole(RECEIVER_ROLE, receiver)) revert InvalidReceiver(receiver);
        bool success = WBTC.transfer(receiver, amount);
        if (!success) revert TransferFailed(receiver, amount);
    }
}
