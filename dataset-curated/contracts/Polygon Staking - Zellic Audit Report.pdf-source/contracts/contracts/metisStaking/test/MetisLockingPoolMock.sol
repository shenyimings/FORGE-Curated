// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ILockingInfoMock {
    function newSequencer(address _owner, uint256 _amount) external;

    function increaseLocked(address _owner, uint256 _amount, uint256 _rewardsAmount) external;

    function withdrawLocking(address _owner, uint256 _amount) external;

    function exit(address _owner) external;
}

/**
 * @title Metis Locking Pool Mock
 * @dev Mocks contract for testing
 */
contract MetisLockingPoolMock {
    using SafeERC20 for IERC20;

    enum Status {
        Unavailabe, // placeholder for default value
        Inactive, // the sequencer will be Inactive if its owner starts unlock
        Active, // the sequencer is active when it locks tokens on the contract
        Unlocked // Exited, the sequencer has no locked tokens, and it's no longer produce blocks on L2
    }

    struct Sequencer {
        uint256 amount; // sequencer current locked
        uint256 reward; // sequencer current reward that have not claimed
        uint256 activationBatch; // sequencer activation batch id
        uint256 updatedBatch; // batch id of the last updated
        uint256 deactivationBatch; // sequencer deactivation batch id
        uint256 deactivationTime; // sequencer deactivation timestamp
        uint256 unlockClaimTime; // timestamp that sequencer can claim unlocked token, it's equal to deactivationTime + WITHDRAWAL_DELAY
        uint256 nonce; // sequencer operations number, starts from 1, and used internally by the Metis consensus client
        address owner; // the operator address, owns this sequencer node, it controls lock/relock/unlock/claim functions
        address signer; // sequencer signer, an address to sign L2 blocks, if you want to update it, you must have the privkey of this address
        bytes pubkey; // sequencer signer pubkey
        address rewardRecipient; // sequencer rewarder recipient address
        Status status; // sequencer status
    }

    IERC20 public token;
    ILockingInfoMock public lockingInfo;

    Sequencer[] public sequencers;
    mapping(address => uint256) public seqOwners;

    mapping(uint256 => uint256) public seqUnlockTimes;
    uint256 public exitDelayPeriod;

    uint256 public currentBatch;

    error InvalidAmount();
    error InvalidMsgValue();
    error SequencerStopped();
    error DelayPeriodNotElapsed();

    constructor(address _token, address _lockingInfo, uint256 _exitDelayPeriod) {
        token = IERC20(_token);
        lockingInfo = ILockingInfoMock(_lockingInfo);
        exitDelayPeriod = _exitDelayPeriod;
        sequencers.push();
    }

    function lockWithRewardRecipient(
        address _signer,
        address _rewardRecipient,
        uint256 _amount,
        bytes calldata _pubkey
    ) external {
        sequencers.push(
            Sequencer(
                _amount,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                msg.sender,
                _signer,
                _pubkey,
                _rewardRecipient,
                Status.Active
            )
        );
        seqOwners[msg.sender] = sequencers.length - 1;
        lockingInfo.newSequencer(msg.sender, _amount);
    }

    function relock(uint256 _seqId, uint256 _amount, bool _lockReward) external {
        if (seqUnlockTimes[_seqId] != 0) revert SequencerStopped();

        uint256 rewards;
        if (_lockReward) {
            rewards = sequencers[_seqId].reward;
            sequencers[_seqId].reward = 0;
        }
        sequencers[_seqId].amount += _amount + rewards;
        lockingInfo.increaseLocked(msg.sender, _amount, rewards);
    }

    function withdraw(uint256 _seqId, uint256 _amount) external {
        if (seqUnlockTimes[_seqId] != 0) revert SequencerStopped();
        lockingInfo.withdrawLocking(msg.sender, _amount);
        sequencers[_seqId].amount -= _amount;
    }

    function unlock(uint256 _seqId, uint32) external payable {
        if (msg.value == 0 && sequencers[_seqId].reward != 0) revert InvalidMsgValue();
        if (seqUnlockTimes[_seqId] != 0) revert SequencerStopped();
        sequencers[_seqId].reward = 0;
        seqUnlockTimes[_seqId] = block.timestamp + exitDelayPeriod;
    }

    function unlockClaim(uint256 _seqId, uint32) external payable {
        if (block.timestamp < seqUnlockTimes[_seqId]) revert DelayPeriodNotElapsed();
        lockingInfo.exit(msg.sender);
        sequencers[_seqId].amount = 0;
    }

    function withdrawRewards(uint256 _seqId, uint32) external payable {
        if (msg.value == 0) revert InvalidMsgValue();
        sequencers[_seqId].reward = 0;
    }

    function addReward(uint256 _seqId, uint256 _amount) external {
        sequencers[_seqId].reward += _amount;
    }

    function slashPrincipal(uint256 _seqId, uint256 _amount) external {
        sequencers[_seqId].amount -= _amount;
    }

    function incrementCurrentBatch() external {
        currentBatch++;
    }
}
