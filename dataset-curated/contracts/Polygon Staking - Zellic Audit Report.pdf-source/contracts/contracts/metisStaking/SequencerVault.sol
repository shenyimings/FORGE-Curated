// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "./interfaces/IL1Strategy.sol";
import "./interfaces/IMetisLockingPool.sol";

/**
 * @title Sequencer Vault
 * @notice Vault contract for depositing METIS collateral into the Metis locking pool -
 * each vault represents a single sequencer
 */
contract SequencerVault is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // address of METIS token
    IERC20Upgradeable public token;
    // address of L1 Strategy
    IL1Strategy public vaultController;
    // address of Metis LockingPool
    IMetisLockingPool public lockingPool;

    // public key of sequencer
    bytes public pubkey;
    // signer address of sequencer
    address public signer;
    // id of sequencer
    uint256 public seqId;

    // address on L2 to receive operator rewards
    address public rewardsReceiver;
    // tracks what total deposits should be without slashing
    uint128 public trackedTotalDeposits;

    // id of current locking pool batch during the latest withdrawal
    uint64 public lastWithdrawalBatchId;
    // time that sequencer can be exited after initiating an exit
    uint64 public exitDelayEndTime;

    event SetRewardsReceiver(address rewardsReceiver);

    error SenderNotAuthorized();
    error ZeroAddress();
    error SequencerStopped();
    error ExitDelayTimeNotElapsed();
    error CurrentBatchAlreadyWithdrawn();
    error AlreadyExited();
    error UnclaimedRewards();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes contract
     * @param _token address of METIS token
     * @param _vaultController address of L1 Strategy
     * @param _lockingPool address of Metis LockingPool
     * @param _lockingInfo address of Metis LockingInfo
     * @param _pubkey public key of sequencer
     * @param _signer signer address of sequencer
     * @param _rewardsReceiver address on L2 to receive operator rewards
     **/
    function initialize(
        address _token,
        address _vaultController,
        address _lockingPool,
        address _lockingInfo,
        bytes memory _pubkey,
        address _signer,
        address _rewardsReceiver
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        token = IERC20Upgradeable(_token);
        vaultController = IL1Strategy(_vaultController);
        lockingPool = IMetisLockingPool(_lockingPool);
        token.approve(_lockingInfo, type(uint256).max);
        pubkey = _pubkey;
        signer = _signer;
        rewardsReceiver = _rewardsReceiver;
    }

    /**
     * @notice Reverts if sender is not vaultController
     **/
    modifier onlyVaultController() {
        if (msg.sender != address(vaultController)) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Reverts if sender is not rewardsReceiver
     **/
    modifier onlyRewardsReceiver() {
        if (msg.sender != rewardsReceiver) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Deposits tokens into the Metis locking pool
     * @param _amount amount to deposit
     */
    function deposit(uint256 _amount) external onlyVaultController {
        if (exitDelayEndTime != 0) revert SequencerStopped();

        token.safeTransferFrom(msg.sender, address(this), _amount);
        trackedTotalDeposits += SafeCastUpgradeable.toUint128(_amount);

        if (seqId != 0) {
            lockingPool.relock(seqId, _amount, false);
        } else {
            lockingPool.lockWithRewardRecipient(
                signer,
                vaultController.rewardRecipient(),
                _amount,
                pubkey
            );
            seqId = lockingPool.seqOwners(address(this));
        }
    }

    /**
     * @notice Withdraws tokens from the Metis locking pool
     * @param _amount amount to withdraw
     * @dev can withdraw once per batch epoch
     * @dev if sequencer has been stopped, will withdraw entire principal balance
     */
    function withdraw(uint256 _amount) external onlyVaultController {
        if (exitDelayEndTime != 0) {
            if (block.timestamp <= exitDelayEndTime) revert ExitDelayTimeNotElapsed();

            trackedTotalDeposits -= uint128(getPrincipalDeposits());
            lockingPool.unlockClaim(seqId, 0);
        } else {
            if (lastWithdrawalBatchId >= lockingPool.currentBatch())
                revert CurrentBatchAlreadyWithdrawn();

            lockingPool.withdraw(seqId, _amount);
            trackedTotalDeposits -= uint128(_amount);
            lastWithdrawalBatchId = uint64(lockingPool.currentBatch());
        }

        token.safeTransfer(address(vaultController), token.balanceOf(address(this)));
    }

    /**
     * @notice Returns the amount that can be withdrawn
     * @return withdrawable amount
     */
    function canWithdraw() external view returns (uint256) {
        uint256 principalDeposits = getPrincipalDeposits();

        if (exitDelayEndTime != 0 && block.timestamp <= exitDelayEndTime) return 0;
        if (exitDelayEndTime != 0 && block.timestamp > exitDelayEndTime) return principalDeposits;
        if (lastWithdrawalBatchId >= lockingPool.currentBatch()) return 0;

        return
            principalDeposits > vaultController.getVaultDepositMin()
                ? principalDeposits - vaultController.getVaultDepositMin()
                : 0;
    }

    /**
     * @notice Returns the total balance of this sequencer in the Metis locking pool
     * @dev includes principal plus any rewards
     * @return total balance
     */
    function getTotalDeposits() public view returns (uint256) {
        return getPrincipalDeposits() + getRewards();
    }

    /**
     * @notice Returns the principal balance of this sequencer in the Metis locking pool
     * @return principal balance
     */
    function getPrincipalDeposits() public view returns (uint256) {
        (uint256 amount, , , , , , , , , , , , ) = lockingPool.sequencers(seqId);
        return amount;
    }

    /**
     * @notice Returns the claimable rewards balance of this sequencer in the Metis locking pool
     * @return rewards balance
     */
    function getRewards() public view returns (uint256) {
        (, uint256 reward, , , , , , , , , , , ) = lockingPool.sequencers(seqId);
        return reward;
    }

    /**
     * @notice Returns the amount of operator rewards that will be earned by this vault on the next update
     * @return newly earned rewards
     */
    function getPendingRewards() public view returns (uint256) {
        int256 depositChange = int256(getTotalDeposits()) - int256(uint256(trackedTotalDeposits));

        if (depositChange > 0) {
            return (uint256(depositChange) * vaultController.operatorRewardPercentage()) / 10000;
        }

        return 0;
    }

    /**
     * @notice Updates the deposit and reward accounting for this vault
     * @dev will only pay out rewards if the vault is net positive when accounting for lost deposits
     * @param _minRewards min amount of rewards to relock/claim (set 0 to skip reward claiming/relocking)
     * @param _l2Gas L2 gasLimit for bridging rewards
     * @return the current total deposits in this vault
     * @return the operator rewards earned by this vault since the last update
     * @return the rewards that were claimed in this update
     */
    function updateDeposits(
        uint256 _minRewards,
        uint32 _l2Gas
    ) external payable onlyVaultController returns (uint256, uint256, uint256) {
        uint256 principal = getPrincipalDeposits();
        uint256 rewards = getRewards();
        uint256 totalDeposits = principal + rewards;
        int256 depositChange = int256(totalDeposits) - int256(uint256(trackedTotalDeposits));

        uint256 opRewards;
        if (depositChange > 0) {
            opRewards =
                (uint256(depositChange) * vaultController.operatorRewardPercentage()) /
                10000;
            trackedTotalDeposits = SafeCastUpgradeable.toUint128(totalDeposits);
        }

        uint256 claimedRewards;
        if (_minRewards != 0 && rewards >= _minRewards) {
            if (
                (principal + rewards) <= vaultController.getVaultDepositMax() &&
                exitDelayEndTime == 0
            ) {
                lockingPool.relock(seqId, 0, true);
            } else {
                lockingPool.withdrawRewards{value: msg.value}(seqId, _l2Gas);
                trackedTotalDeposits -= SafeCastUpgradeable.toUint128(rewards);
                totalDeposits -= rewards;
                claimedRewards = rewards;
            }
        }

        if (address(this).balance != 0) {
            payable(msg.sender).transfer(address(this).balance);
        }

        return (totalDeposits, opRewards, claimedRewards);
    }

    /**
     * @notice Initiates an exit from the sequencer
     * @dev all sequencer rewards must be claimed before this function is called
     */
    function initiateExit() external onlyVaultController {
        if (exitDelayEndTime != 0) revert SequencerStopped();
        if (getRewards() != 0) revert UnclaimedRewards();

        exitDelayEndTime = uint64(block.timestamp + lockingPool.exitDelayPeriod());
        lockingPool.unlock(seqId, 0);
    }

    /**
     * @notice Withdraws all principal deposits from exited sequencer
     * @dev all sequencer rewards must be claimed before this function is called
     */
    function finalizeExit() external onlyVaultController {
        if (exitDelayEndTime == 0 || block.timestamp <= exitDelayEndTime) {
            revert ExitDelayTimeNotElapsed();
        }
        if (getRewards() != 0) revert UnclaimedRewards();

        uint256 principalDeposits = getPrincipalDeposits();
        if (principalDeposits == 0) revert AlreadyExited();

        lockingPool.unlockClaim(seqId, 0);
        trackedTotalDeposits -= uint128(principalDeposits);

        token.safeTransfer(address(vaultController), token.balanceOf(address(this)));
    }

    /**
     * @notice Sets the rewards receiver
     * @dev this address is authorized to withdraw rewards for this vault and/or change the rewardsReceiver
     * to a new a address
     * @param _rewardsReceiver rewards receiver address
     */
    function setRewardsReceiver(address _rewardsReceiver) external onlyRewardsReceiver {
        if (_rewardsReceiver == address(0)) revert ZeroAddress();
        rewardsReceiver = _rewardsReceiver;

        emit SetRewardsReceiver(_rewardsReceiver);
    }

    /**
     * @dev Checks authorization for contract upgrades
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
