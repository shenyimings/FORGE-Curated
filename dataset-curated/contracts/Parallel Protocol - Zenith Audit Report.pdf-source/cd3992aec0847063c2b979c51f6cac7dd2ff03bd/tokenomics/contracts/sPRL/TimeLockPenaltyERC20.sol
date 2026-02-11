// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";

import { MathsLib } from "contracts/libraries/MathsLib.sol";

/// @title TimeLockPenaltyERC20
/// @notice An ERC20 wrapper contract that allows users to deposit assets and can only withdraw them after a specified
/// time lock period. If the user withdraws before the time lock period, a penalty fee is applied relative to the time
/// left.
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
abstract contract TimeLockPenaltyERC20 is ERC20, ERC20Permit, ERC20Votes, AccessManaged, Pausable, ReentrancyGuard {
    using MathsLib for *;

    //-------------------------------------------
    // Storage
    //-------------------------------------------

    /// @notice The status of a withdrawal request.
    enum WITHDRAW_STATUS {
        UNUSED,
        UNLOCKING,
        RELEASED,
        CANCELLED
    }

    /// @notice A struct to store the details of a withdrawal request.
    struct WithdrawalRequest {
        /// @notice The amount of assets the user requested to withdraw.
        uint256 amount;
        /// @notice The time the user requested the withdrawal.
        uint64 requestTime;
        /// @notice The time the user can withdraw the assets.
        uint64 releaseTime;
        /// @notice The status of the withdrawal request.
        WITHDRAW_STATUS status;
    }

    /// @notice 1e18 = 100%
    uint256 private constant MAX_PENALTY_PERCENTAGE = 1e18;
    /// @notice The min duration of the time lock
    uint64 constant MIN_TIMELOCK_DURATION = 1 days;
    /// @notice The max duration of the time lock
    uint64 constant MAX_TIMELOCK_DURATION = 365 days;

    /// @notice The address of the underlying token.
    IERC20 public underlying;
    /// @notice The address that will receive the fees.
    address public feeReceiver;
    /// @notice The duration of the time lock.
    uint64 public timeLockDuration;
    /// @notice The amount of underlying tokens that are in unlocking state.
    uint256 public unlockingAmount;
    /// @notice The penalties percentage that will be applied at request time.
    uint256 public startPenaltyPercentage;
    /// @notice Mapping of user to their withdrawal requests.
    mapping(address user => mapping(uint256 requestId => WithdrawalRequest request)) public userVsWithdrawals;
    /// @notice Mapping of user to their next withdrawal request ID.
    mapping(address user => uint256 nextRequestId) public userVsNextID;

    //----------------------------------------
    // Events
    //----------------------------------------

    /// @notice Emitted when the time lock duration is changed.
    /// @param oldTimeLock The old time lock duration.
    /// @param newTimeLock The new time lock duration.
    event TimeLockUpdated(uint256 oldTimeLock, uint256 newTimeLock);

    /// @notice Emitted when a user requests to withdraw assets.
    /// @param id The ID of the request.
    /// @param user The user that requested the withdraw.
    event WithdrawalRequested(uint256 id, address user, uint256 amount);

    /// @notice Emitted when a user withdraws assets
    /// @param id The ID of the request
    /// @param user The user that withdrew the assets
    /// @param amount The amount of underlying assets withdrawn for the user
    /// @param slashAmount The amount of underlying assets slashed for the fee receiver
    event Withdraw(uint256 id, address user, uint256 amount, uint256 slashAmount);

    /// @notice Emitted when a user emergency withdraws assets.
    /// @param user The user that withdrew the assets.
    /// @param amount The amount of assets withdrawn.
    event EmergencyWithdraw(address user, uint256 amount);

    /// @notice Emitted when a user deposits assets
    /// @param user The user that deposited the assets.
    /// @param amount The amount of assets deposited.
    event Deposited(address user, uint256 amount);

    /// @notice Emitted when a user cancels a withdrawal request.
    /// @param id The ID of the request.
    /// @param user The user that cancelled the request.
    /// @param amount The amount of assets cancelled.
    event WithdrawalRequestCancelled(uint256 id, address user, uint256 amount);

    /// @notice Emitted when the fee receiver is updated.
    /// @param newFeeReceiver The new fee receiver.
    event FeeReceiverUpdated(address newFeeReceiver);

    /// @notice Emitted when the start penalty percentage is updated.
    /// @param oldPercentage The old penalty percentage.
    /// @param newPercentage The new penalty percentage.
    event StartPenaltyPercentageUpdated(uint256 oldPercentage, uint256 newPercentage);

    //-------------------------------------------
    // Errors
    //-------------------------------------------

    /// @notice Thrown when the time lock duration is out of range.
    error TimelockOutOfRange(uint256 attemptedTimelockDuration);
    /// @notice Thrown when a user tries to cancel a withdrawal request that is not in the unlocking state.
    error CannotCancelWithdrawalRequest(uint256 reqId);
    /// @notice Thrown when a user tries to withdraw assets that are not in the unlocking state.
    error CannotWithdraw(uint256 reqId);
    /// @notice Thrown when a user tries to withdraw assets that are not yet unlocked.
    error CannotWithdrawYet(uint256 reqId);
    /// @notice Thrown when the percentage is out of range.
    error PercentageOutOfRange(uint256 attemptedPercentage);

    //-------------------------------------------
    // Constructor
    //-------------------------------------------

    /// @notice Construct a new TimeLockedERC20 contract
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token.
    /// @param _underlying The underlying that is being locked.
    /// @param _timeLockDuration The duration of the time lock.
    constructor(
        string memory _name,
        string memory _symbol,
        address _underlying,
        address _feeReceiver,
        address _accessManager,
        uint256 _startPenaltyPercentage,
        uint64 _timeLockDuration
    )
        ERC20Permit(_name)
        ERC20(_name, _symbol)
        AccessManaged(_accessManager)
    {
        if (_timeLockDuration < MIN_TIMELOCK_DURATION || _timeLockDuration > MAX_TIMELOCK_DURATION) {
            revert TimelockOutOfRange(_timeLockDuration);
        }
        if (_startPenaltyPercentage > MAX_PENALTY_PERCENTAGE) {
            revert PercentageOutOfRange(_startPenaltyPercentage);
        }

        feeReceiver = _feeReceiver;
        underlying = IERC20(_underlying);
        timeLockDuration = _timeLockDuration;
        startPenaltyPercentage = _startPenaltyPercentage;
    }

    //-------------------------------------------
    // External functions
    //-------------------------------------------

    /// @notice Request to withdraw assets from the contract.
    /// @param _unlockingAmount The amount of assets to unlock.
    function requestWithdraw(uint256 _unlockingAmount) external {
        _burn(msg.sender, _unlockingAmount);

        uint256 id = userVsNextID[msg.sender]++;
        WithdrawalRequest storage request = userVsWithdrawals[msg.sender][id];

        request.amount = _unlockingAmount;
        request.requestTime = uint64(block.timestamp);
        request.releaseTime = uint64(block.timestamp) + timeLockDuration;
        request.status = WITHDRAW_STATUS.UNLOCKING;

        unlockingAmount += _unlockingAmount;

        emit WithdrawalRequested(id, msg.sender, _unlockingAmount);
    }

    /// @notice Cancel multiple withdrawal requests.
    /// @param _ids The IDs of the withdrawal requests to cancel.
    function cancelWithdrawalRequests(uint256[] calldata _ids) external {
        uint256 i = 0;
        for (; i < _ids.length; ++i) {
            _cancelWithdrawalRequest(_ids[i]);
        }
    }

    /// @notice This is for off-chain use, it finds any locked IDs in the specified range.
    /// @param _user The user to find the unlocking IDs for.
    /// @param _start The ID to start looking from.
    /// @param _startFromEnd Whether to start from the end.
    /// @param _countToCheck The number of IDs to check.
    /// @return ids The IDs of the unlocking requests.
    function findUnlockingIDs(
        address _user,
        uint256 _start,
        bool _startFromEnd,
        uint16 _countToCheck
    )
        external
        view
        returns (uint256[] memory ids)
    {
        uint256 nextId = userVsNextID[_user];

        if (_start >= nextId) return ids;
        if (_startFromEnd) _start = nextId - _start;
        uint256 end = _start + uint256(_countToCheck);
        if (end > nextId) end = nextId;

        mapping(uint256 => WithdrawalRequest) storage withdrawals = userVsWithdrawals[_user];

        ids = new uint256[](end - _start);
        uint256 length = 0;
        uint256 id = _start;
        // Nothing in here can overflow so disable the checks for the loop.
        unchecked {
            for (; id < end; ++id) {
                if (withdrawals[id].status == WITHDRAW_STATUS.UNLOCKING) {
                    ids[length++] = id;
                }
            }
        }

        // Need to force the array length to the correct value using assembly.
        assembly {
            mstore(ids, length)
        }
    }

    //-------------------------------------------
    // AccessManaged functions
    //-------------------------------------------

    /// @notice Allow the AccessManager to update the time lock duration.
    /// @param _newTimeLockDuration The new time lock duration.
    function updateTimeLockDuration(uint64 _newTimeLockDuration) external restricted {
        if (_newTimeLockDuration < MIN_TIMELOCK_DURATION || _newTimeLockDuration > MAX_TIMELOCK_DURATION) {
            revert TimelockOutOfRange(_newTimeLockDuration);
        }
        emit TimeLockUpdated(timeLockDuration, _newTimeLockDuration);
        timeLockDuration = _newTimeLockDuration;
    }

    /// @notice Allow the AccessManager to update the time lock duration.
    /// @param _newStartPenaltyPercentage The new time lock duration.
    function updateStartPenaltyPercentage(uint256 _newStartPenaltyPercentage) external restricted {
        if (_newStartPenaltyPercentage > MAX_PENALTY_PERCENTAGE) {
            revert PercentageOutOfRange(_newStartPenaltyPercentage);
        }
        emit StartPenaltyPercentageUpdated(startPenaltyPercentage, _newStartPenaltyPercentage);
        startPenaltyPercentage = _newStartPenaltyPercentage;
    }

    /// @notice Allow the AccessManager to update the fee receiver address.
    /// @param _newFeeReceiver The new fee receiver.
    function updateFeeReceiver(address _newFeeReceiver) external restricted {
        emit FeeReceiverUpdated(_newFeeReceiver);
        feeReceiver = _newFeeReceiver;
    }

    /// @notice Allow AccessManager to pause the contract.
    /// @dev This function can only be called by the AccessManager.
    function pause() external restricted {
        _pause();
    }

    /// @notice Allow AccessManager to unpause the contract.
    /// @dev This function can only be called by the AccessManager.
    function unpause() external restricted {
        _unpause();
    }

    //-------------------------------------------
    // Private/Internal functions
    //-------------------------------------------

    /// @notice Mint the equivalent amount of underlying tokens deposited.
    /// @param _amount The amount of underlying tokens deposited.
    function _deposit(uint256 _amount) internal {
        emit Deposited(msg.sender, _amount);
        _mint(msg.sender, _amount);
    }

    /// @notice Withdraw multiple withdrawal requests.
    /// @param _ids The IDs of the withdrawal requests to withdraw.
    /// @return totalAmountWithdrawn The total amount of assets withdrawn.
    /// @return totalSlashAmount The total amount of assets that were slashed.
    function _withdrawMultiple(uint256[] calldata _ids)
        internal
        returns (uint256 totalAmountWithdrawn, uint256 totalSlashAmount)
    {
        uint256 i = 0;
        for (; i < _ids.length; ++i) {
            (uint256 amountWithdrawn, uint256 slashAmount) = _withdraw(_ids[i]);
            totalAmountWithdrawn += amountWithdrawn;
            totalSlashAmount += slashAmount;
        }
    }

    /// @notice Withdraw assets from the contract
    /// @param _id The ID of the withdrawal request.
    /// @return amount The amount of assets user received.
    /// @return slashAmount The amount of assets that were slashed.
    function _withdraw(uint256 _id) internal returns (uint256 amount, uint256 slashAmount) {
        WithdrawalRequest storage request = userVsWithdrawals[msg.sender][_id];

        if (request.status != WITHDRAW_STATUS.UNLOCKING) {
            revert CannotWithdraw(_id);
        }

        slashAmount = _calculateFee(request.amount, request.requestTime, request.releaseTime);
        amount = request.amount - slashAmount;
        request.status = WITHDRAW_STATUS.RELEASED;

        emit Withdraw(_id, msg.sender, amount, slashAmount);
    }

    /// @notice Cancel a withdrawal request.
    /// @param _id The ID of the withdrawal request.
    function _cancelWithdrawalRequest(uint256 _id) internal {
        WithdrawalRequest storage request = userVsWithdrawals[msg.sender][_id];
        if (request.status != WITHDRAW_STATUS.UNLOCKING) {
            revert CannotCancelWithdrawalRequest(_id);
        }
        request.status = WITHDRAW_STATUS.CANCELLED;

        uint256 _amount = request.amount;
        unlockingAmount -= _amount;

        emit WithdrawalRequestCancelled(_id, msg.sender, _amount);

        _mint(msg.sender, _amount);
    }

    /// @notice Calculate the fee amount that will be slashed from the withdrawal amount.
    /// @dev The fee amount is calculated based on the time left until the release time.
    /// @param _amount The total amount of assets user should withdraw.
    /// @param _requestTime The time the user requested the withdrawal.
    /// @param _releaseTime The time the user can withdraw the assets.
    /// @return feeAmount The amount of assets that will be slashed.
    function _calculateFee(
        uint256 _amount,
        uint256 _requestTime,
        uint256 _releaseTime
    )
        internal
        view
        returns (uint256 feeAmount)
    {
        if (block.timestamp >= _releaseTime) return 0;
        uint256 timeLeft = _releaseTime - block.timestamp;
        uint256 lockDuration = _releaseTime - _requestTime;
        uint256 feePercentage = startPenaltyPercentage.mulDivUp(timeLeft, lockDuration);
        feeAmount = _amount.wadMulUp(feePercentage);
    }

    //-------------------------------------------
    // Overrides
    //-------------------------------------------

    /// @notice Update the balances of the token.
    /// @param from The address to transfer from.
    /// @param to The address to transfer to.
    /// @param value The amount to transfer.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /// @notice Get the nonce for an address.
    /// @param owner The address to get the nonce for.
    /// @return The nonce for the address.
    function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
