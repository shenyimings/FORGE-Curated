// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IMinter.sol";
import "./interfaces/IAssToken.sol";
import "./interfaces/pancakeswap/IPancakeStableSwapPool.sol";
import "./interfaces/pancakeswap/IPancakeStableSwapRouter.sol";
import "./interfaces/IUniversalProxy.sol";

contract Minter is
  IMinter,
  Initializable,
  AccessControlUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  UUPSUpgradeable
{
  using SafeERC20 for IERC20;
  // compounder role
  bytes32 public constant COMPOUNDER = keccak256("COMPOUNDER");
  // pause role
  bytes32 public constant PAUSER = keccak256("PAUSER");
  // manager role
  bytes32 public constant MANAGER = keccak256("MANAGER");
  // denominator
  uint256 public constant DENOMINATOR = 10000;
  // rewards compounded are vesting every day
  uint256 private constant VESTING_PERIOD = 1 days;

  /* ============ State Variables ============ */
  // token address
  IERC20 public token;
  // assToken address
  IAssToken public assToken;
  // total tokens
  uint256 private _totalTokens;
  // total veToken rewards
  uint256 public totalVeTokenRewards;
  // total vote rewards
  uint256 public totalVoteRewards;
  // total donate rewards
  uint256 public totalDonateRewards;
  // total rewards per type
  mapping(IMinter.RewardsType => uint256) public totalRewards;
  // veToken rewards fee rate in percentage (10_000 = 100%)
  uint256 public veTokenRewardsFeeRate;
  // vote rewards fee rate in percentage (10_000 = 100%)
  uint256 public voteRewardsFeeRate;
  // donate rewards fee rate in percentage (10_000 = 100%)
  uint256 public donateRewardsFeeRate;
  // total totalFee
  uint256 public totalFee;
  // pancake swap router
  address public pancakeSwapRouter;
  // pancake swap pool
  address public pancakeSwapPool;
  // max swap ratio
  uint256 public maxSwapRatio;
  //universal Proxy
  address public universalProxy;
  // The amount of the last asset distribution from the controller contract into this
  // contract + any unvested remainder at that time
  uint256 public vestingAmount;
  // The timestamp of the last asset distribution from the controller contract into this contract
  uint256 public lastDistributionTimestamp;

  /* ============ Events ============ */
  event SmartMinted(address indexed user, uint256 cakeInput, uint256 obtainedAssCake);
  event RewardsCompounded(address indexed sender, uint256 compoundAmount, uint256 fee);
  event FeeRateUpdated(address indexed sender, RewardsType rewardsType, uint256 oldFeeRate, uint256 newFeeRate);
  event FeeWithdrawn(address indexed sender, address receipt, uint256 amount);
  event PancakeSwapRouterChanged(address indexed sender, address indexed pancakeSwapRouter);
  event PancakeSwapPoolChanged(address indexed sender, address indexed pancakeSwapPool);
  event MaxSwapRatioChanged(address indexed sender, uint256 maxSwapRatio);
  event AddToken(address indexed assToken, address indexed token);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev initialize the contract
   * @param _admin - Address of the admin
   * @param _manager - Address of the manager
   * @param _pauser - Address of the pauser
   * @param _token - Address of the token
   * @param _assToken - Address of the assToken
   * @param _universalProxy - Address of the universalProxy
   * @param _pancakeSwapRouter - Address of swap router
   * @param _pancakeSwapPool - Address of swap pool
   * @param _maxSwapRatio - Max swap ratio
   */
  function initialize(
    address _admin,
    address _manager,
    address _pauser,
    address _token,
    address _assToken,
    address _universalProxy,
    address _pancakeSwapRouter,
    address _pancakeSwapPool,
    uint256 _maxSwapRatio
  ) external override initializer {
    require(_admin != address(0), "Invalid admin address");
    require(_manager != address(0), "Invalid manager address");
    require(_pauser != address(0), "Invalid pauser address");
    require(_token != address(0), "Invalid token address");
    require(_assToken != address(0), "Invalid AssToken address");
    require(_universalProxy != address(0), "Invalid universalProxy address");
    require(_pancakeSwapRouter != address(0), "Invalid pancake swap router address");
    require(_pancakeSwapPool != address(0), "Invalid pancake swap pool address");
    require(_maxSwapRatio <= DENOMINATOR, "Invalid max swap ratio");

    __AccessControl_init();
    __Pausable_init();
    __ReentrancyGuard_init();
    __UUPSUpgradeable_init();
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER, _manager);
    _grantRole(PAUSER, _pauser);

    // CAKE
    token = IERC20(_token);
    // asCAKE
    assToken = IAssToken(_assToken);
    universalProxy = _universalProxy;
    pancakeSwapRouter = _pancakeSwapRouter;
    pancakeSwapPool = _pancakeSwapPool;
    maxSwapRatio = _maxSwapRatio;

    emit AddToken(_assToken, _token);
  }

  /* ============ External Getters ============ */

  /**
   * @dev estimateTotalOut  get asCAKE amount
   * @param _amountIn - amount of CAKE
   * @param _mintRatio - mint ratio
   */
  function estimateTotalOut(uint256 _amountIn, uint256 _mintRatio) public view returns (uint256 minimumEstimatedTotal) {
    // valid mintRatio
    require(_mintRatio <= DENOMINATOR, "Incorrect Ratio");

    // convert CAKE amount by this contract
    uint256 mintAmount = ((_amountIn * _mintRatio) / DENOMINATOR);
    // swap CAKE amount by pancakeSwap
    uint256 buybackAmount = _amountIn - mintAmount;

    // asCAKE amount
    uint256 amountOut = 0;

    if (buybackAmount > 0) {
      // swap to asCAKE by pancakeSwap
      amountOut += swapToAssTokens(buybackAmount);
    }

    if (mintAmount > 0) {
      // convert to asCAKE by this contract
      amountOut += convertToAssTokens(mintAmount);
    }

    // asCAKE amount
    return amountOut;
  }

  /**
   * @dev swapToAssTokens  get assToken amount
   * @param tokens - amount of token
   */
  function swapToAssTokens(uint256 tokens) public view returns (uint256) {
    // swap by pancakeSwap
    return IPancakeStableSwapPool(pancakeSwapPool).get_dy(0, 1, tokens);
  }

  /**
   * @dev convertToTokens  get token amount
   * @param assTokens - amount of assTokens
   */
  function convertToTokens(uint256 assTokens) public view returns (uint256) {
    uint256 totalSupply = assToken.totalSupply();
    //why +1？
    //When using the contract for the first time, totalTokens and totalSupply are both 0.
    //After calling smartMint and mint assToken, totalTokens and totalSupply are not 0.
    return (assTokens * (totalTokens() + 1)) / (totalSupply + 1);
  }

  /**
   * @dev convertToAssTokens  get assToken amount
   * @param tokens - amount of token
   */
  function convertToAssTokens(uint256 tokens) public view returns (uint256) {
    uint256 totalSupply = assToken.totalSupply();
    //why +1？
    //When using the contract for the first time, totalTokens and totalSupply are both 0.
    //After calling smartMint and mint assToken, totalTokens and totalSupply are not 0.
    return (tokens * (totalSupply + 1)) / (totalTokens() + 1);
  }

  // /* ============ External Functions ============ */

  /**
   * @dev smart mint assToken
   * @param _amountIn - amount of token
   * @param _mintRatio - mint ratio
   * @param _minOut - minimum output
   */
  function smartMint(
    uint256 _amountIn,
    uint256 _mintRatio,
    uint256 _minOut
  ) external override whenNotPaused nonReentrant returns (uint256) {
    // smart mint assToken
    return _smartMint(_amountIn, _mintRatio, _minOut);
  }

  /**
   * @dev totalTokens
   * @notice returns the total amount of tokens in the contract
   */
  function totalTokens() public view returns (uint256) {
    return _totalTokens - getUnvestedAmount();
  }

  /**
   * @dev compoundRewards
   * @param _rewards - rewards type and amount in
   */
  function compoundRewards(
    IMinter.RewardsType[] memory _rewardsTypes,
    uint256[] memory _rewards
  ) external override onlyRole(COMPOUNDER) whenNotPaused nonReentrant {
    require(_rewardsTypes.length > 0 && _rewardsTypes.length == _rewards.length, "Invalid rewards length");

    // separate compoundAmount and fee
    uint256 compoundAmount = 0;
    uint256 fee = 0;
    // compound the rewards
    for (uint i; i < _rewardsTypes.length; ++i) {
      IMinter.RewardsType rewardsType = _rewardsTypes[i];
      uint256 amountInPerType = _rewards[i];
      // process only if amount is not 0
      if (amountInPerType != 0) {
        uint256 feePerType = 0;
        // collect fee per type
        if (rewardsType == RewardsType.VeTokenRewards) {
          feePerType = (amountInPerType * veTokenRewardsFeeRate) / DENOMINATOR;
        } else if (rewardsType == RewardsType.VoteRewards) {
          feePerType = (amountInPerType * voteRewardsFeeRate) / DENOMINATOR;
        } else if (rewardsType == RewardsType.Donate) {
          feePerType = (amountInPerType * donateRewardsFeeRate) / DENOMINATOR;
        } else {
          revert("Invalid rewardsType");
        }
        // add up fee
        fee += feePerType;
        // add up amt. of compound after fee is deducted
        compoundAmount += amountInPerType - feePerType;
        // accumulate rewards per type
        totalRewards[rewardsType] += amountInPerType - feePerType;
      }
    }
    // transfer token from compounder
    require(compoundAmount + fee > 0, "Invalid compound amount");
    IERC20(token).safeTransferFrom(msg.sender, address(this), compoundAmount + fee);

    // reset vesting amount
    _updateVestingAmount(compoundAmount);

    // update total fee and actual total tokens
    totalFee += fee;
    _totalTokens += compoundAmount;

    // compound rewards
    IERC20(token).safeIncreaseAllowance(universalProxy, compoundAmount);
    IUniversalProxy(universalProxy).lock(compoundAmount);

    emit RewardsCompounded(msg.sender, compoundAmount, fee);
  }

  /**
   * @dev reset lastDistributionTimestamp and reward vesting amount
   * @param newVestingAmount - new vesting amount
   */
  function _updateVestingAmount(uint256 newVestingAmount) internal {
    if (getUnvestedAmount() > 0) revert("reward still vesting");

    vestingAmount = newVestingAmount;
    lastDistributionTimestamp = block.timestamp;
  }

  /**
   * @notice Returns the amount of tokens that are unvested in the contract.
   */
  function getUnvestedAmount() public view returns (uint256) {
    uint256 timeSinceLastDistribution = block.timestamp - lastDistributionTimestamp;
    // vesting period is over
    if (timeSinceLastDistribution >= VESTING_PERIOD) {
      return 0;
    }

    uint256 deltaT;
    unchecked {
      deltaT = (VESTING_PERIOD - timeSinceLastDistribution);
    }
    return (deltaT * vestingAmount) / VESTING_PERIOD;
  }

  /**
   * @dev mint assToken
   * @param _amountIn - amount of token
   */
  function _mint(uint256 _amountIn) private returns (uint256) {
    // increase allowance for universalProxy
    IERC20(token).safeIncreaseAllowance(universalProxy, _amountIn);
    // increase lock amount of the veToken
    IUniversalProxy(universalProxy).lock(_amountIn);

    // calculate how much asCAKE can get
    uint256 assTokens = convertToAssTokens(_amountIn);

    // mint asCAKE
    assToken.mint(address(this), assTokens);

    return assTokens;
  }

  /**
   * @dev buyback assToken
   * @param _amountIn - amount of token
   * @param _minOut - minimum output
   */
  function _buyback(uint256 _amountIn, uint256 _minOut) private returns (uint256) {
    address[] memory tokenPath = new address[](2);
    // token address
    tokenPath[0] = address(token);
    // assToken address
    tokenPath[1] = address(assToken);
    uint256[] memory flag = new uint256[](1);
    flag[0] = 2;
    // increase allowance for pancakeSwapRouter
    token.safeIncreaseAllowance(pancakeSwapRouter, _amountIn);
    // balance before swap
    uint256 oldBalance = assToken.balanceOf(address(this));
    uint256 amountOut = IPancakeStableSwapRouter(pancakeSwapRouter).exactInputStableSwap(
      tokenPath,
      flag,
      _amountIn,
      _minOut,
      address(this)
    );
    //balance after swap
    uint256 newBalance = assToken.balanceOf(address(this));
    // amountOut must equals to the net diff.
    require(amountOut == newBalance - oldBalance, "Invalid amountOut");

    //after swap, the difference amount
    return (newBalance - oldBalance);
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

  /* ============ Admin Functions ============ */

  /**
   * @dev updateFeeRate
   * @param _rewardsType - rewards type
   * @param _feeRate - fee rate
   */
  function updateFeeRate(RewardsType _rewardsType, uint256 _feeRate) external nonReentrant onlyRole(MANAGER) {
    // valid feeRate
    require(_feeRate < DENOMINATOR, "Incorrect Fee Ratio");

    uint256 oldFeeRate = 0;
    if (_rewardsType == RewardsType.VeTokenRewards) {
      require(veTokenRewardsFeeRate != _feeRate, "newFeeRate can not be equal oldFeeRate");

      oldFeeRate = veTokenRewardsFeeRate;
      // set veTokenRewardsFeeRate
      veTokenRewardsFeeRate = _feeRate;
    } else if (_rewardsType == RewardsType.VoteRewards) {
      require(voteRewardsFeeRate != _feeRate, "newFeeRate can not be equal oldFeeRate");

      oldFeeRate = voteRewardsFeeRate;
      // set voteRewardsFeeRate
      voteRewardsFeeRate = _feeRate;
    } else if (_rewardsType == RewardsType.Donate) {
      require(donateRewardsFeeRate != _feeRate, "newFeeRate can not be equal oldFeeRate");

      oldFeeRate = donateRewardsFeeRate;
      // set donateRewardsFeeRate
      donateRewardsFeeRate = _feeRate;
    } else {
      revert("Invalid rewardsType");
    }
    // emit event
    emit FeeRateUpdated(msg.sender, _rewardsType, oldFeeRate, _feeRate);
  }

  /**
   * @dev withdrawFee withdraw the reward commission amount collected by the platform to an address
   * @param receipt - Address of the receipt
   * @param amount - amount of token
   */
  function withdrawFee(address receipt, uint256 amount) external nonReentrant onlyRole(MANAGER) {
    // valid receipt
    require(receipt != address(0), "Invalid address");
    // valid amount
    require(amount > 0, "Invalid amount");
    // The totalFee must be sufficient
    require(amount <= totalFee, "Invalid amount");

    // reduce totalFee
    totalFee -= amount;
    // transfer CAKE to receipt
    IERC20(token).safeTransfer(receipt, amount);
    // emit event
    emit FeeWithdrawn(msg.sender, receipt, amount);
  }

  /**
   * @dev changePancakeSwapRouter
   * @param _pancakeSwapRouter - Address of the pancakeSwapRouter
   */
  function changePancakeSwapRouter(address _pancakeSwapRouter) external onlyRole(MANAGER) {
    require(_pancakeSwapRouter != address(0), "_pancakeSwapRouter is the zero address");
    require(_pancakeSwapRouter != pancakeSwapRouter, "_pancakeSwapRouter is the same");
    // set pancakeSwapRouter
    pancakeSwapRouter = _pancakeSwapRouter;
    emit PancakeSwapRouterChanged(msg.sender, _pancakeSwapRouter);
  }

  /**
   * @dev changePancakeSwapPool
   * @param _pancakeSwapPool - Address of the pancakeSwapPool
   */
  function changePancakeSwapPool(address _pancakeSwapPool) external onlyRole(MANAGER) {
    require(_pancakeSwapPool != address(0), "_pancakeSwapPool is the zero address");
    require(_pancakeSwapPool != pancakeSwapPool, "_pancakeSwapPool is the same");
    // set pancakeSwapPool
    pancakeSwapPool = _pancakeSwapPool;
    emit PancakeSwapPoolChanged(msg.sender, _pancakeSwapPool);
  }

  /**
   * @dev changeMaxSwapRatio
   * @param _maxSwapRatio - Address of the maxSwapRatio
   */
  function changeMaxSwapRatio(uint256 _maxSwapRatio) external onlyRole(MANAGER) {
    require(_maxSwapRatio <= DENOMINATOR, "Invalid max swap ratio");
    require(_maxSwapRatio != maxSwapRatio, "_maxSwapRatio is the same");
    // set maxSwapRatio
    maxSwapRatio = _maxSwapRatio;
    emit MaxSwapRatioChanged(msg.sender, _maxSwapRatio);
  }

  // /* ============ Internal Functions ============ */

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

  function _smartMint(uint256 _amountIn, uint256 _mintRatio, uint256 _minOut) private returns (uint256) {
    // valid amount
    require(_amountIn > 0, "Invalid amount");
    // valid mintRatio
    require(_mintRatio <= DENOMINATOR, "Incorrect Ratio");
    // transfer funds to this contract
    token.safeTransferFrom(msg.sender, address(this), _amountIn);
    //convert CAKE amount by this contract
    uint256 mintAmount = (_amountIn * _mintRatio) / DENOMINATOR;
    // swap CAKE amount by pancakeSwap
    uint256 buybackAmount = _amountIn - mintAmount;
    // asCAKE amount
    uint256 amountRec = 0;

    if (mintAmount > 0) {
      // swap to asCAKE by pancakeSwap
      amountRec += _mint(mintAmount);
      // increase total CAKE
      _totalTokens += mintAmount;
    }

    if (buybackAmount > 0) {
      // make sure minOut is not 0
      require(_minOut > amountRec, "MinOut not match");
      //swap CAKE by pancakeSwap
      amountRec += _buyback(buybackAmount, _minOut - amountRec);
    }
    // the received amount is greater than equal to the estimated amount
    require(amountRec >= _minOut, "MinOut not match");

    // transfer asCAKE to sender
    IERC20(assToken).safeTransfer(msg.sender, amountRec);

    // emit event
    emit SmartMinted(msg.sender, _amountIn, amountRec);

    return amountRec;
  }
}
