// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {IERC20, SafeERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts@4.9.3/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts@4.9.3/security/ReentrancyGuard.sol";

interface IReferralStorage {
    function setTraderReferralCodeByLocker(address _account, bytes32 _code)
        external;
}

/**
 * @title BMX Locking Contract
 * @notice This contract locks BMX into tranches with unique requirements and varying lock times.
 */
contract BmxLockingContract is ReentrancyGuard, Ownable2Step {
    using SafeERC20 for IERC20;

    struct Tranche {
        uint256 depositedUsers; // Total amount of users who locked
        uint256 requiredLockAmount;
        uint256 capacity; // How many users can lock
        uint256 lockDuration;
        bool depositEnabled; // Governance-controlled switch
        bytes32 masterCode; // Referral code specifically created for use by this contract
    }

    /// @notice BMX, token to lock
    IERC20 public constant bmx =
        IERC20(0x548f93779fBC992010C07467cBaf329DD5F059B7);

    /// @notice Referral storage holds info about users and who referred them
    address public immutable referralStorage;

    /// @notice Check if a user is deposited to a given tranche. Tranche => user address => is deposited.
    mapping(uint256 => mapping(address => bool)) public userDeposited;

    /// @notice End time for a given lock and user. Tranche ID => user => lock end time.
    mapping(uint256 => mapping(address => uint256)) public userLockEndTime;

    /// @notice Tranche values for a given tranche ID.
    mapping(uint256 => Tranche) public tranches;

    /// @notice Tranche ID for the next tranche that will be created.
    uint256 public nextTranche;

    // Events
    event Deposited(address user, uint256 tranche);
    event Withdrawn(address user, uint256 tranche);
    event SetDepositState(bool depositEnabled, uint256 tranche);
    event SetTranche(
        uint256 id,
        uint256 requiredLockAmount,
        uint256 capacity,
        uint256 lockDuration,
        bool depositEnabled,
        bytes32 masterCode
    );

    constructor(address _referralStorage) {
        if (_referralStorage == address(0)) {
            revert("Invalid storage address");
        }
        referralStorage = _referralStorage;
    }

    /// @notice Protect users from themselves
    receive() external payable {
        revert("Don't send ether here");
    }
    /**
     * @notice Deposit BMX to the specified tranche.
     * @dev All vars in the Tranche struct, including amount and length to lock, are specific to the tranche number. A
     *  tranche may only be deposited to if it has been enabled first.
     * @param _tranche The tranche to deposit our BMX to.
     */
    function deposit(uint256 _tranche) external nonReentrant {
        if (userDeposited[_tranche][msg.sender]) {
            revert("Already locked");
        }
        // access our tranche info
        Tranche memory tranche = tranches[_tranche];
        // make sure we can deposit
        if (!tranche.depositEnabled) {
            revert("Locking is disabled");
        }
        if (tranche.depositedUsers >= tranche.capacity) {
            revert("Tranche capacity is full");
        }
        if (bmx.balanceOf(msg.sender) < tranche.requiredLockAmount) {
            revert("Not enough BMX to deposit");
        }
        // lock the deposit for the given duration, make sure they can't deposit again and increment user counter
        userLockEndTime[_tranche][msg.sender] =
            block.timestamp +
            tranche.lockDuration;
        userDeposited[_tranche][msg.sender] = true;
        tranches[_tranche].depositedUsers++;

        // pull BMX needed, link deposit to referrer
        bmx.safeTransferFrom(
            msg.sender,
            address(this),
            tranche.requiredLockAmount
        );
        IReferralStorage(referralStorage).setTraderReferralCodeByLocker(
            msg.sender,
            tranche.masterCode
        );

        emit Deposited(msg.sender, _tranche);
    }

    /**
     * @notice Withdraw BMX from the specified tranche.
     * @dev All vars in the Tranche struct, including amount and length to lock, are specific to the tranche number.
     *  User's can't withdraw until their lock period has expired.
     * @param _tranche The tranche to withdraw our BMX from.
     */
    function withdraw(uint256 _tranche) external nonReentrant {
        if (!userDeposited[_tranche][msg.sender]) {
            revert("User hasn't locked");
        }
        if (userLockEndTime[_tranche][msg.sender] > block.timestamp) {
            revert("Lock period hasn't ended");
        }

        userDeposited[_tranche][msg.sender] = false;
        userLockEndTime[_tranche][msg.sender] = 0;

        // send user their unlocked funds
        bmx.safeTransfer(msg.sender, tranches[_tranche].requiredLockAmount);

        emit Withdrawn(msg.sender, _tranche);
    }

    /**
     * @notice Set the parameters for a given tranche ID.
     * @dev May only be called by owner.
     * @param _requiredLockAmount Amount of BMX needed to lock in this tranche.
     * @param _capacity Number of users allowed to deposit to this tranche.
     * @param _lockDuration Lockup length, in seconds.
     * @param _depositEnabled Whether deposits should be enabled to start.
     * @param _masterCode Unique code for tracking tranche deposit referrals.
     */
    function setTranche(
        uint256 _requiredLockAmount,
        uint256 _capacity,
        uint256 _lockDuration,
        bool _depositEnabled,
        bytes32 _masterCode
    ) external onlyOwner {
        Tranche storage tranche = tranches[nextTranche];

        tranche.requiredLockAmount = _requiredLockAmount;
        tranche.capacity = _capacity;
        tranche.lockDuration = _lockDuration;
        tranche.depositEnabled = _depositEnabled;
        tranche.masterCode = _masterCode;

        emit SetTranche(
            nextTranche,
            _requiredLockAmount,
            _capacity,
            _lockDuration,
            _depositEnabled,
            _masterCode
        );

        // increase our nextTranche counter
        nextTranche++;
    }

    /**
     * @notice Enable or disable deposits for a given tranche ID.
     * @dev May only be called by owner.
     * @param _tranche The tranche to set the deposit state for.
     * @param _depositEnabled True/False if deposits are enabled.
     */
    function setDepositState(uint256 _tranche, bool _depositEnabled)
        external
        onlyOwner
    {
        Tranche storage tranche = tranches[_tranche];
        tranche.depositEnabled = _depositEnabled;
        emit SetDepositState(_depositEnabled, _tranche);
    }
}