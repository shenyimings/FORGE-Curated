// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IUniversalProxy.sol";
import "./interfaces/IMinter.sol";
import "./interfaces/IRewardDistributionScheduler.sol";
import "./interfaces/pancakeswap/IVeCake.sol";
import "./interfaces/pancakeswap/IGaugeVoting.sol";
import "./interfaces/pancakeswap/IRevenueSharingPool.sol";
import "./interfaces/pancakeswap/IRevenueSharingPoolGateway.sol";
import "./interfaces/pancakeswap/IIFOV8.sol";
import "./interfaces/stakeDao/ICakePlatform.sol";

contract UniversalProxy is
  IUniversalProxy,
  AccessControlUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  UUPSUpgradeable
{
  using SafeERC20 for IERC20;
  // pause role
  bytes32 public constant PAUSER = keccak256("PAUSER");
  // minter role
  bytes32 public constant MINTER = keccak256("MINTER");
  // bot role
  bytes32 public constant BOT = keccak256("BOT");
  // manager role
  bytes32 public constant MANAGER = keccak256("MANAGER");

  /* ============ State Variables ============ */
  // token address
  IERC20 public token;
  // veCake contract
  IVeCake public veToken;
  // gauge voting contract
  IGaugeVoting public gaugeVoting;
  // IFO contract
  IIFOV8 public ifo;
  // revenue sharing pools
  address[] public revenueSharingPools;
  IRevenueSharingPoolGateway public revenueSharingPoolGateway;
  // rewards distribution scheduler
  IRewardDistributionScheduler public rewardsDistributionScheduler;
  // IFO info (pid => depositAmount)
  mapping(uint8 => uint256) public ifoPositions;
  // StakeDao's CakePlatform
  ICakePlatform public cakePlatform;

  // lock created flag
  bool public lockCreated;
  // maximum lock duration = 4 years - 1s (same as PCS)
  uint256 public constant WEEK = 7 days;
  uint256 public constant MAX_LOCK_DURATION = (209 * WEEK) - 1;
  uint256 public constant REWARD_VESTING_EPOCHS = 7;

  /* ============ Events ============ */
  event LockIncreased(uint256 value);
  event LockExtended(uint256 unlockTime);
  event VeTokenRewardsClaimed(uint256 amount);
  event IFODeposited(uint8 pid, uint256 amount);
  event IFOHarvested(uint8 pid, address rewardToken, uint256 amount);
  event RevenuePoolIdsSet(address[] poolIds);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev initialize the contract
   * @param _admin - Address of the admin
   * @param _pauser - Address of the pauser
   * @param _minter - Address of the minter
   * @param _bot - Address of the bot
   * @param _manager - Address of the manager
   * @param _token - Address of the token
   * @param _veToken - Address of the veToken
   * @param _gaugeVoting - Address of the gaugeVoting
   * @param _ifo - Address of the ifo
   * @param _rewardDistributionScheduler - Address of the rewardDistributionScheduler
   * @param _revenueSharingPools - Array of revenue sharing pools
   * @param _cakePlatform - Address of the cakePlatform
   */
  function initialize(
    address _admin,
    address _pauser,
    address _minter,
    address _bot,
    address _manager,
    address _token,
    address _veToken,
    address _gaugeVoting,
    address _ifo,
    address _rewardDistributionScheduler,
    address[] memory _revenueSharingPools,
    address _revenueSharingPoolGateway,
    address _cakePlatform
  ) external initializer {
    require(_admin != address(0), "Invalid admin address");
    require(_token != address(0), "Invalid token address");
    require(_veToken != address(0), "Invalid veToken address");
    require(_gaugeVoting != address(0), "Invalid gaugeVoting address");
    require(_ifo != address(0), "Invalid ifo address");
    require(_revenueSharingPoolGateway != address(0), "Invalid revenueSharingPoolGateway address");
    require(_cakePlatform != address(0), "Invalid cakePlatform address");
    require(_rewardDistributionScheduler != address(0), "Invalid rewardDistributionScheduler address");
    require(_revenueSharingPools.length > 0, "revenueSharingPools must have at least one address");

    __AccessControl_init();
    __Pausable_init();
    __ReentrancyGuard_init();
    __UUPSUpgradeable_init();
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(PAUSER, _pauser);
    _grantRole(MINTER, _minter);
    _grantRole(BOT, _bot);
    _grantRole(MANAGER, _manager);

    lockCreated = false;
    token = IERC20(_token);
    veToken = IVeCake(_veToken);
    gaugeVoting = IGaugeVoting(_gaugeVoting);
    ifo = IIFOV8(_ifo);
    revenueSharingPools = _revenueSharingPools;
    revenueSharingPoolGateway = IRevenueSharingPoolGateway(_revenueSharingPoolGateway);
    rewardsDistributionScheduler = IRewardDistributionScheduler(_rewardDistributionScheduler);
    cakePlatform = ICakePlatform(_cakePlatform);
  }

  // ------------------------------ //
  //           Lock token           //
  // ------------------------------ //
  /**
   * @dev increase lock amount of the veToken
   *      if lock is not created then create a new lock,
   *      otherwise, increase the lock amount also check if the
   *      new unlock time is greater than lock end time
   *      increase unlock time if so
   * @dev token will be transferred from MINTER
   * @param amount - amount to lock
   */
  function lock(uint256 amount) external override onlyRole(MINTER) whenNotPaused {
    require(amount > 0, "value must greater than 0");
    // transfer token from minter to this contract
    token.safeTransferFrom(msg.sender, address(this), amount);
    token.safeIncreaseAllowance(address(veToken), amount);
    // increase amt + extend lock if locked already
    if (lockCreated) {
      // increase lock amount
      veToken.increaseLockAmount(amount);
      // attempt to extend lock duration
      _extendLock();
    } else {
      // create lock if not created
      veToken.createLock(amount, block.timestamp + MAX_LOCK_DURATION);
      lockCreated = true;
    }
    emit LockIncreased(amount);
  }

  /**
   * @dev extend the lock duration in case lock() is not called
   *      for a long time and the lock duration is about to expire
   */
  function extendLock() external override onlyRole(BOT) whenNotPaused {
    _extendLock();
  }

  // @dev extend lock with max. unlock timestamp
  function _extendLock() private {
    // get new unlock time
    uint256 newUnlockTime = block.timestamp + MAX_LOCK_DURATION;
    // get lock end time
    (, uint256 end, , , , , , ) = veToken.getUserInfo(address(this));
    // increase unlock time if new unlock time is greater than lock end time
    if (((newUnlockTime / 1 weeks) * 1 weeks) > end) {
      veToken.increaseUnlockTime(newUnlockTime);
      emit LockExtended(newUnlockTime);
    }
  }

  // @dev check if we need to extend lock
  function needToExtendLock() external view returns (bool) {
    // lock is not created yet
    if (!lockCreated) {
      return false;
    }
    // get lock end time and new unlock time
    (, uint256 end, , , , , , ) = veToken.getUserInfo(address(this));
    uint256 newUnlockTime = block.timestamp + MAX_LOCK_DURATION;
    return ((newUnlockTime / 1 weeks) * 1 weeks) > end;
  }

  // ------------------------------ //
  //             Voting             //
  // ------------------------------ //

  /**
   * @dev cast vote for gauge weights
   * @param gaugeAddrs - array of gauge addresses
   * @param userWeights - array of user weights
   * @param chainIds - array of chain ids
   * @param skipNative - skip native chain
   * @param skipProxy - skip proxy chain
   */
  function castVote(
    address[] memory gaugeAddrs,
    uint256[] memory userWeights,
    uint256[] memory chainIds,
    bool skipNative,
    bool skipProxy
  ) external onlyRole(MANAGER) whenNotPaused {
    gaugeVoting.voteForGaugeWeightsBulk(gaugeAddrs, userWeights, chainIds, skipNative, skipProxy);
  }

  /**
   * @dev claim veToken rewards to this contract
   *      then rewards will be sent and distributed to rewardsDistributionScheduler
   *      for more info of PCS's voting, plz refer to:
   *      https://developer.pancakeswap.finance/contracts/vecake-and-gauge-voting
   */
  function claimVeTokenRewards() external onlyRole(BOT) whenNotPaused nonReentrant {
    // get reward token balance before
    uint256 tokenBalanceBefore = token.balanceOf(address(this));
    // claim rewards from revenueSharingPoolGateway
    revenueSharingPoolGateway.claimMultipleWithoutProxy(revenueSharingPools, address(this));
    // get balance after the claim
    uint256 tokenBalanceAfter = token.balanceOf(address(this));
    // calculate total claimed rewards
    uint256 totalClaimed = tokenBalanceAfter - tokenBalanceBefore;
    // approve rewardsDistributionScheduler to spend reward tokens
    token.safeIncreaseAllowance(address(rewardsDistributionScheduler), totalClaimed);
    // create rewards distribution schedule
    // rewards are collected from 2 source in the form of CAKE token
    // 1. weekly revenue sharing rewards
    // 2. weekly veCAKE emission rewards
    // then collected rewards(totalClaimed) will be distributed in 7 days
    rewardsDistributionScheduler.addRewardsSchedule(
      IMinter.RewardsType.VeTokenRewards,
      totalClaimed,
      REWARD_VESTING_EPOCHS,
      block.timestamp
    );
    emit VeTokenRewardsClaimed(totalClaimed);
  }

  // ------------------------------ //
  //               IFO              //
  // ------------------------------ //
  /**
   * @dev deposit token to IFO
   * @param pid - pool id
   * @param amount - amount to deposit
   */
  function depositIFO(uint8 pid, uint256 amount) external onlyRole(MANAGER) whenNotPaused {
    require(amount > 0, "amount must be greater than 0");
    require(pid >= 0, "invalid pid");
    // transfer token from multi-sig wallet to here
    token.safeTransferFrom(msg.sender, address(this), amount);
    // approve IFO contract to spend the token
    token.safeIncreaseAllowance(address(ifo), amount);
    // join IFO
    ifo.depositPool(amount, pid);
    emit IFODeposited(pid, amount);
  }

  /**
   * @dev harvest IFO rewards
   * @param pid - pool id
   * @param rewardToken - reward token address
   */
  function harvestIFO(uint8 pid, address rewardToken) external onlyRole(MANAGER) whenNotPaused nonReentrant {
    // get deposit token balance before
    uint256 tokenBalanceBefore = token.balanceOf(address(this));
    // get harvested token amount from IFO
    uint256 harvestedAmtBefore = IERC20(rewardToken).balanceOf(address(this));

    // get harvested token from IFO
    ifo.harvestPool(pid);

    // get deposit token balance after
    uint256 tokenBalanceAfter = token.balanceOf(address(this));
    // get harvested token amount after
    uint256 harvestedAmtAfter = IERC20(rewardToken).balanceOf(address(this));

    // not all tokens are exchanged to IFO tokens
    uint256 refundAmt = tokenBalanceAfter - tokenBalanceBefore;
    // harvested token amount
    uint256 harvestedAmt = harvestedAmtAfter - harvestedAmtBefore;

    // record diff. into ifoPositions
    ifoPositions[pid] = refundAmt;

    // send deposited token and reward tokens back to msg.sender
    if (refundAmt > 0) {
      token.safeTransfer(msg.sender, refundAmt);
    }
    if (harvestedAmt > 0) {
      IERC20(rewardToken).safeTransfer(msg.sender, harvestedAmt);
    }
    emit IFOHarvested(pid, rewardToken, harvestedAmt);
  }

  // ------------------------------ //
  //        StakeDAO Rewards        //
  // ------------------------------ //

  /**
   * @dev Set a recipient address for calling user.
   *      Recipient are used when calling claimFor functions. Regular functions will use msg.sender as recipient,
   *      or recipient parameter provided if called by msg.sender.
   * @param recipient - address of the recipient
   */
  function setRecipient(address recipient) external onlyRole(MANAGER) whenNotPaused {
    // if zero address is set, then msg.sender will be used as recipient
    // recipient can't be zero address
    require(recipient != address(0), "Invalid recipient address");
    cakePlatform.setRecipient(recipient);
  }

  /**
   * @dev claim whatever we can claim from StakeDao
   * @dev when we cast vote for gauges on PancakeSwap,
   *      we can gain rewards from StakeDao if gauges voted supports
   *      StakeDao's CakePlatform (please refer to it's vote market)
   * @param ids - Bounty IDs
   */
  function claimRewardsFromStakeDao(uint256[] calldata ids) external whenNotPaused {
    // claim rewards from multiple bounties
    cakePlatform.claimAllFor(address(this), ids);
  }

  // ------------------------------ //
  //         Administration         //
  // ------------------------------ //
  /**
   * @dev set revenue sharing pools
   * @param poolIds - array of pool ids
   */
  function setRevenuePoolIds(address[] memory poolIds) external onlyRole(MANAGER) {
    revenueSharingPools = poolIds;
    emit RevenuePoolIdsSet(poolIds);
  }

  /**
   * @dev set rewardDistributionScheduler
   * @param _rewardDistributionScheduler - address of the rewardDistributionScheduler
   */
  function setRewardDistributionScheduler(address _rewardDistributionScheduler) external onlyRole(MANAGER) {
    require(_rewardDistributionScheduler != address(0), "Invalid rewardDistributionScheduler address");
    require(
      _rewardDistributionScheduler != address(rewardsDistributionScheduler),
      "rewardDistributionScheduler can't be the same address"
    );
    rewardsDistributionScheduler = IRewardDistributionScheduler(_rewardDistributionScheduler);
  }

  /**
   * @dev unpause the contract
   */
  function unpause() external onlyRole(MANAGER) {
    _unpause();
  }

  /**
   * @dev pause the contract
   */
  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
