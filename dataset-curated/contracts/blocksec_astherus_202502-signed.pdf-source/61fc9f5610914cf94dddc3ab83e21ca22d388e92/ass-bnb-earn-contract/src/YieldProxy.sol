// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IAsBnbMinter.sol";
import "./interfaces/IYieldProxy.sol";
import "./interfaces/IAsBNB.sol";
import "./interfaces/ISlisBNBProvider.sol";
import "./interfaces/IListaStakeManager.sol";

contract YieldProxy is
  IYieldProxy,
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

  /* ======================
        State Variables
   ====================== */
  // token address
  IERC20 public token;
  // asBnb address
  IAsBNB public asBnb;

  // launchpool activities
  Activity[] public activities;
  uint256 public lastUpdatedActivityIdx;

  // minter
  IAsBnbMinter public minter;

  // @dev clisBNB related
  // the accumulated amount of token rewarded from the activity
  uint256 public rewardedAmount;
  // the address(from Lista) sends the rewards
  address public rewardsSender;

  // Lista Stake Manager - deposit BNB and get slisBNB
  address public stakeManager;
  // Lista slisBNB Provider - collateralize slisBNB and get clisBNB
  address public slisBNBProvider;
  // Lista MPC wallet - delegate to this wallet to participate in LaunchPools
  address public mpcWallet;

  /* ======================
            Events
   ====================== */
  event ActivityAdded(uint256 startTime, uint256 endTime, uint256 rewardedTime, string tokenName);
  event ActivitySettled(uint256 rewardedTime, uint256 compoundedAmount, string tokenName);
  event Received(address indexed sender, uint256 value);
  event MinterSet(address indexed oldMinter, address indexed newMinter);
  event SlisBNBProviderSet(address indexed oldSlisBNBProvider, address indexed newSlisBNBProvider);
  event MPCWalletSet(address indexed oldMpcWallet, address indexed newMpcWallet);
  event RewardsSenderSet(address indexed oldRewardsSender, address indexed newRewardsSender);
  event TokenDelegated(address indexed sender, uint256 amount, uint256 lpAmount);
  event NativeTokensWithdrawn(address indexed sender, uint256 amount);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev initialize the contract
   * @param _admin - Address of the admin
   * @param _manager - Address of the manager
   * @param _pauser - Address of the pauser
   * @param _bot - Address of the bot
   * @param _token - Address of token
   * @param _asBnb - Address of asBnb
   * @param _stakeManager - Address of Lista Stake Manager
   */
  function initialize(
    address _admin,
    address _manager,
    address _pauser,
    address _bot,
    address _token,
    address _asBnb,
    address _stakeManager,
    address _mpcWallet
  ) external initializer {
    require(_admin != address(0), "Invalid admin address");
    require(_manager != address(0), "Invalid manager address");
    require(_pauser != address(0), "Invalid pauser address");
    require(_bot != address(0), "Invalid bot address");
    require(_token != address(0), "Invalid token address");
    require(_asBnb != address(0), "Invalid asBnb address");
    require(_stakeManager != address(0), "Invalid stakeManager address");
    require(_mpcWallet != address(0), "Invalid MPC wallet address");

    __Pausable_init();
    __ReentrancyGuard_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER, _manager);
    _grantRole(PAUSER, _pauser);
    _grantRole(BOT, _bot);

    token = IERC20(_token);
    asBnb = IAsBNB(_asBnb);
    stakeManager = _stakeManager;
    slisBNBProvider = address(0);
    mpcWallet = _mpcWallet;
  }

  /* ============================
          External Getters
  ============================ */
  /**
   * @dev check if there is any activity ongoing
   *      to save gas, searching from `lastUpdatedActivityIdx`
   *      as activities before that are already settled
   */
  function activitiesOnGoing() external view override returns (bool) {
    for (uint256 i = lastUpdatedActivityIdx; i < activities.length; ++i) {
      Activity memory activity = activities[i];
      // if it's started and not rewarded yet
      if (activity.startTime <= block.timestamp && activity.rewardedTime == 0) {
        return true;
      }
    }
    return false;
  }

  /* ============================
        External Functions
  ============================ */
  /**
   * @dev deposit slisBNB into this contract
   * @notice after transition period, clisBNBProvider will be set
   *         and the deposit will be converted to clisBNB
   * @param amount - amount of BNB
   */
  function deposit(uint256 amount) external override onlyRole(MINTER) whenNotPaused {
    require(amount > 0, "Invalid amount");
    token.safeTransferFrom(msg.sender, address(this), amount);

    // transition period
    if (slisBNBProvider != address(0)) {
      // convert to clisBNB and delegate to Lista's MPC
      token.safeIncreaseAllowance(slisBNBProvider, amount);
      uint256 lpAmount = ISlisBNBProvider(slisBNBProvider).provide(amount, mpcWallet);
      emit TokenDelegated(msg.sender, amount, lpAmount);
    }
  }

  /**
   * @dev allows user withdraw token with their asBnb
   * @param amount - amount of asBnb
   */
  function withdraw(uint256 amount) external override onlyRole(MINTER) nonReentrant whenNotPaused {
    require(slisBNBProvider != address(0), "slisBNBProvider not set");
    require(amount > 0, "Invalid amount");
    // pre balance of slisBNB
    uint256 preBalance = token.balanceOf(address(this));
    // withdraw tokens to minter
    ISlisBNBProvider(slisBNBProvider).release(address(this), amount);
    // post balance of slisBNB
    uint256 postBalance = token.balanceOf(address(this));
    if (postBalance - preBalance != amount) {
      // if there is a difference, revert
      revert("Invalid amount");
    }
    // send to minter
    token.safeTransfer(msg.sender, amount);
  }

  /**
   * @dev settle the activity
   * @notice only the bot can settle the activity
   *         also rewards from activity will be compounded
   */
  function settleActivity() external onlyRole(BOT) whenNotPaused {
    // only if there is active activity
    // and the rewarded amount is not 0
    require(address(minter) != address(0), "Minter not set");
    require(this.activitiesOnGoing(), "No active activity");
    require(rewardedAmount > 0, "No rewards to compound");

    // save rewarded time
    activities[lastUpdatedActivityIdx].rewardedTime = block.timestamp;
    // update last updated activity index
    ++lastUpdatedActivityIdx;

    // get pre-balance of slisBNB
    uint256 preBalance = token.balanceOf(address(this));
    // convert BNB to slisBNB
    IListaStakeManager(stakeManager).deposit{ value: rewardedAmount }();
    // get post-balance of slisBNB
    uint256 postBalance = token.balanceOf(address(this));
    uint256 netBalance = postBalance - preBalance;
    // compound rewards
    token.safeIncreaseAllowance(address(minter), netBalance);
    minter.compoundRewards(netBalance);
    // emit event
    emit ActivitySettled(block.timestamp, rewardedAmount, activities[lastUpdatedActivityIdx - 1].tokenName);
    // reset the rewarded amount
    rewardedAmount = 0;
  }

  /**
   * @dev admin withdraw native token (BNB)
   *      not including the rewarded amount
   * @param amount - amount of BNB
   */
  function withdrawNativeToken(uint256 amount) external onlyRole(MANAGER) {
    require(amount > 0, "Invalid amount");
    require(address(this).balance - rewardedAmount >= amount, "Insufficient balance");
    payable(msg.sender).transfer(amount);
    emit NativeTokensWithdrawn(msg.sender, amount);
  }

  // @dev records how much BNB was sent by the sender
  receive() external payable {
    // add up amounts determined by the sender
    if (msg.sender == rewardsSender) {
      rewardedAmount += msg.value;
    }
    emit Received(msg.sender, msg.value);
  }

  /* ============================
          Admin Functions
  ============================ */
  /**
   * @dev Flips the pause state
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

  /**
   * @dev add an activity
   * @param _startTime - start time of the activity
   * @param _endTime - end time of the activity
   * @param _tokenName - name of the token
   */
  function addActivity(
    uint256 _startTime,
    uint256 _endTime,
    string memory _tokenName
  ) external onlyRole(MANAGER) whenNotPaused {
    require(_startTime > block.timestamp, "Invalid start time");
    require(_startTime < _endTime, "Invalid time range");
    require(bytes(_tokenName).length > 0, "Invalid token name");
    activities.push(Activity(_startTime, _endTime, 0, _tokenName));
    emit ActivityAdded(_startTime, _endTime, 0, _tokenName);
  }

  /**
   * @dev end one or more activities from the last updated activity idx
   * @param numberOfActivity - number of the activity to end
   */
  function endActivity(uint256 numberOfActivity) external onlyRole(MANAGER) whenNotPaused {
    require(numberOfActivity > 0, "Invalid number of activities");
    // cache the last updated activity index
    uint256 max = lastUpdatedActivityIdx + numberOfActivity;
    // starting from lastUpdatedActivityIdx
    for (uint256 i = lastUpdatedActivityIdx; i < max; ++i) {
      // break if reach to the end
      if (i >= activities.length) {
        break;
      }
      activities[i].rewardedTime = block.timestamp;
      // emit event, note that no reward is compounded
      emit ActivitySettled(block.timestamp, 0, activities[lastUpdatedActivityIdx].tokenName);
      // update last updated activity index
      ++lastUpdatedActivityIdx;
    }
  }

  /**
   * @dev Delegate all tokens to a new MPC Wallet
   * @notice When Lista has announced in advance that the MPC wallet will be changed,
   *         manager(multi-sig) can call this function to delegate all tokens to the new MPC wallet
   */
  function reDelegateTokens() external onlyRole(MANAGER) whenNotPaused {
    require(slisBNBProvider != address(0), "slisBNBProvider not set");
    require(mpcWallet != address(0), "mpcWallet not set");
    ISlisBNBProvider(slisBNBProvider).delegateAllTo(mpcWallet);
  }

  /**
   * @dev convert all slisBNB to clisBNB
   */
  function convertAllSlisBNBToClisBNB() external onlyRole(MANAGER) whenNotPaused {
    require(slisBNBProvider != address(0), "slisBNBProvider not set");
    require(mpcWallet != address(0), "mpcWallet not set");
    uint256 balance = token.balanceOf(address(this));
    if (balance > 0) {
      token.safeIncreaseAllowance(slisBNBProvider, balance);
      ISlisBNBProvider(slisBNBProvider).provide(balance, mpcWallet);
    }
  }

  /**
   * @dev set slisBNBProvider address
   * @param _slisBNBProvider - address of the slisBNBProvider
   */
  function setSlisBNBProvider(address _slisBNBProvider) external onlyRole(MANAGER) {
    require(_slisBNBProvider != address(0) && _slisBNBProvider != slisBNBProvider, "Invalid slisBNBProvider address");
    address oldSlisBNBProvider = slisBNBProvider;
    slisBNBProvider = _slisBNBProvider;
    emit SlisBNBProviderSet(oldSlisBNBProvider, _slisBNBProvider);
  }

  /**
   * @dev set MPC wallet
   * @param _mpcWallet - address of the MPC wallet
   */
  function setMPCWallet(address _mpcWallet) external onlyRole(MANAGER) {
    require(_mpcWallet != address(0) && _mpcWallet != mpcWallet, "Invalid MPC wallet address");
    address oldMpcWallet = mpcWallet;
    mpcWallet = _mpcWallet;
    emit MPCWalletSet(oldMpcWallet, _mpcWallet);
  }

  /**
   * @dev set rewards sender
   * @param _rewardsSender - address of the rewards sender
   */
  function setRewardsSender(address _rewardsSender) external onlyRole(MANAGER) {
    require(_rewardsSender != address(0) && _rewardsSender != rewardsSender, "Invalid rewards sender address");
    address oldRewardsSender = rewardsSender;
    rewardsSender = _rewardsSender;
    emit RewardsSenderSet(oldRewardsSender, _rewardsSender);
  }

  /**
   * @dev set minter
   * @param _minter - address of the minter
   */
  function setMinter(address _minter) external onlyRole(MANAGER) {
    require(_minter != address(0) && _minter != address(minter), "Invalid minter address");

    address oldMinter = address(minter);
    // revoke previous minter's MINTER ROLE
    _revokeRole(MINTER, oldMinter);
    // set new minter
    minter = IAsBnbMinter(_minter);
    // grant role and revoke previous minter's MINTER ROLE
    _grantRole(MINTER, _minter);

    emit MinterSet(oldMinter, _minter);
  }

  /* ============================
        Internal Functions
  ============================ */
  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
