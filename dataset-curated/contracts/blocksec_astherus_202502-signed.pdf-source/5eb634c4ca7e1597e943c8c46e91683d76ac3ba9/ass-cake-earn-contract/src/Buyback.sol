// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IBuyback.sol";

contract Buyback is
  IBuyback,
  Initializable,
  AccessControlUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  UUPSUpgradeable
{
  using SafeERC20 for IERC20;
  // bot role
  bytes32 public constant BOT = keccak256("BOT");
  // pause role
  bytes32 public constant PAUSER = keccak256("PAUSER");
  // manager role
  bytes32 public constant MANAGER = keccak256("MANAGER");

  uint256 internal constant DAY = 1 days;

  // call 1inch swap method to swap
  bytes4 public constant SWAP_SELECTOR =
    bytes4(keccak256("swap(address,(address,address,address,address,uint256,uint256,uint256),bytes)"));

  /* ============ State Variables ============ */
  // buyback receiver address
  address public receiver;
  // eg:CAKE
  address public swapDstToken;
  // oneInchRouter Whitelist
  mapping(address => bool) public oneInchRouterWhitelist;
  // swap source token Whitelist
  mapping(address => bool) public swapSrcTokenWhitelist;
  // daily Bought
  mapping(uint256 => uint256) public dailyBought;
  // total bought
  uint256 public totalBought;

  //swap native address
  address public swapNativeAddress;

  /* ============ Events ============ */
  event BoughtBack(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
  event ReceiverChanged(address indexed receiver);
  event swapNativeAddressChanged(address indexed swapNativeAddress);
  event OneInchRouterChanged(address indexed oneInchRouter, bool added);
  event SwapSrcTokenChanged(address indexed srcToken, bool added);
  event ReceiveBNB(address indexed from, address indexed to, uint256 amount);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  receive() external payable {
    if (msg.value > 0) {
      emit ReceiveBNB(msg.sender, address(this), msg.value);
    }
  }

  /**
   * @dev initialize the contract
   * @param _admin - Address of the admin
   * @param _manager - Address of the manager
   * @param _swapDstToken - Address of the swapDstToken
   * @param _receiver - Address of the receiver
   * @param _oneInchRouter - Address of swap oneInchRouter
   */
  function initialize(
    address _admin,
    address _manager,
    address _pauser,
    address _swapDstToken,
    address _receiver,
    address _oneInchRouter,
    address _swapNativeAddress
  ) external override initializer {
    require(_admin != address(0), "Invalid admin address");
    require(_manager != address(0), "Invalid _manager address");
    require(_pauser != address(0), "Invalid _pauser address");
    require(_swapDstToken != address(0), "Invalid swapDstToken address");
    require(_receiver != address(0), "Invalid receiver address");
    require(_oneInchRouter != address(0), "Invalid oneInchRouter address");
    require(_swapNativeAddress != address(0), "Invalid swapNativeAddress address");

    __AccessControl_init();
    __Pausable_init();
    __ReentrancyGuard_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER, _manager);
    _grantRole(PAUSER, _pauser);

    swapDstToken = _swapDstToken;
    receiver = _receiver;
    swapNativeAddress = _swapNativeAddress;
    oneInchRouterWhitelist[_oneInchRouter] = true;
  }

  // /* ============ External Functions ============ */

  /**
   * @dev after receiving the voting reward, exchange the meme or BNB into CAKE
   * 1. call Get data (swapData) from https://api.1inch.dev/swap/v6.0/56/swap
   * 2. post swapData to this method
   * @param _1inchRouter - Address of the 1inchRouter
   * @param swapData - swap data
   */
  function buyback(
    address _1inchRouter,
    bytes calldata swapData
  ) external override onlyRole(BOT) nonReentrant whenNotPaused {
    // 1inch has v5 v6 version, the contract needs to support the correct version
    require(oneInchRouterWhitelist[_1inchRouter], "1inchRouter not whitelisted");

    // Get data (swapData) from https://api.1inch.dev/swap/v6.0/56/swap without making any changes and pass it to the contract method
    require(bytes4(swapData[0:4]) == SWAP_SELECTOR, "invalid 1Inch function selector");

    // remove the 4-byte method signature hash，decode to SwapDescription
    (, SwapDescription memory swapDesc, ) = abi.decode(swapData[4:], (address, SwapDescription, bytes));

    // only supports configured tokens
    require(swapSrcTokenWhitelist[address(swapDesc.srcToken)], "srcToken not whitelisted");
    // only supports configured tokens,CAKE
    require(address(swapDesc.dstToken) == swapDstToken, "invalid dstToken");
    // after swap, receive the token
    require(swapDesc.dstReceiver == receiver, "invalid dstReceiver");
    // amount more than 0
    require(swapDesc.amount > 0, "invalid amount");

    // support native token
    bool isNativeSrcToken = address(swapDesc.srcToken) == swapNativeAddress ? true : false;
    // get src token balance
    uint256 srcTokenBalance = isNativeSrcToken ? address(this).balance : swapDesc.srcToken.balanceOf(address(this));
    // the balance must be sufficient
    require(srcTokenBalance >= swapDesc.amount, "insufficient balance");

    // not native token,increase allowance for _1inchRouter
    if (!isNativeSrcToken) {
      swapDesc.srcToken.safeIncreaseAllowance(_1inchRouter, swapDesc.amount);
    }
    // balance before swap
    uint256 beforeBalance = swapDesc.dstToken.balanceOf(receiver);

    bool succ;
    bytes memory _data;
    if (isNativeSrcToken) {
      // native
      (succ, _data) = address(_1inchRouter).call{ value: swapDesc.amount }(swapData);
    } else {
      // token
      (succ, _data) = address(_1inchRouter).call(swapData);
    }

    require(succ, "1inch call failed");

    // balance after swap
    uint256 afterBalance = swapDesc.dstToken.balanceOf(receiver);
    // decode data,received amount
    (uint256 amountOut, ) = abi.decode(_data, (uint256, uint256));
    // after swap, the difference amount
    uint256 diff = afterBalance - beforeBalance;

    // the amount received must be equal to the return value
    require(amountOut == diff, "received incorrect token amount");
    // the received amount is greater than or equal to the estimated amount
    require(amountOut >= swapDesc.minReturnAmount, "less than minReturnAmount");

    // increase totalBought
    totalBought += amountOut;
    uint256 today = (block.timestamp / DAY) * DAY;
    dailyBought[today] = dailyBought[today] + amountOut;

    //emit event
    emit BoughtBack(address(swapDesc.srcToken), address(swapDesc.dstToken), swapDesc.amount, amountOut);
  }

  /**
   * @dev changeReceiver
   * @param _receiver - Address of the receiver for 1inch swap
   */
  function changeReceiver(address _receiver) external onlyRole(MANAGER) {
    require(_receiver != address(0), "_receiver is the zero address");
    require(_receiver != receiver, "_receiver is the same");

    //set receiver
    receiver = _receiver;
    emit ReceiverChanged(_receiver);
  }

  /**
   * @dev changeSwapNativeAddress
   * @param _swapNativeAddress - Address of the swap native for 1inch swap
   */
  function changeSwapNativeAddress(address _swapNativeAddress) external onlyRole(MANAGER) {
    require(_swapNativeAddress != address(0), "_swapNativeAddress is the zero address");
    require(swapNativeAddress != _swapNativeAddress, "_swapNativeAddress is the same");

    //set swapNativeAddress
    swapNativeAddress = _swapNativeAddress;
    emit swapNativeAddressChanged(swapNativeAddress);
  }

  /**
   * @dev add1InchRouterWhitelist
   * @param oneInchRouter - Address of the oneInchRouter for 1inch swap
   */
  function add1InchRouterWhitelist(address oneInchRouter) external onlyRole(MANAGER) {
    require(!oneInchRouterWhitelist[oneInchRouter], "oneInchRouter already whitelisted");

    // add oneInchRouter to oneInchRouterWhitelist
    oneInchRouterWhitelist[oneInchRouter] = true;
    emit OneInchRouterChanged(oneInchRouter, true);
  }

  /**
   * @dev remove1InchRouterWhitelist
   * @param oneInchRouter - Address of the oneInchRouter for 1inch swap
   */
  function remove1InchRouterWhitelist(address oneInchRouter) external onlyRole(MANAGER) {
    require(oneInchRouterWhitelist[oneInchRouter], "oneInchRouter not whitelisted");

    //delete oneInchRouter form oneInchRouterWhitelist
    delete oneInchRouterWhitelist[oneInchRouter];
    emit OneInchRouterChanged(oneInchRouter, false);
  }

  /**
   * @dev addSwapSrcTokenWhitelist
   * @param srcToken - Address of the srcToken for 1inch swap
   */
  function addSwapSrcTokenWhitelist(address srcToken) external onlyRole(MANAGER) {
    require(!swapSrcTokenWhitelist[srcToken], "srcToken already whitelisted");

    // add srcToken to swapSrcTokenWhitelist
    swapSrcTokenWhitelist[srcToken] = true;
    emit SwapSrcTokenChanged(srcToken, true);
  }

  /**
   * @dev removeSwapSrcTokenWhitelist
   * @param srcToken - Address of the srcToken for 1inch swap
   */
  function removeSwapSrcTokenWhitelist(address srcToken) external onlyRole(MANAGER) {
    require(swapSrcTokenWhitelist[srcToken], "srcToken not whitelisted");

    //delete srcToken form swapSrcTokenWhitelist
    delete swapSrcTokenWhitelist[srcToken];
    emit SwapSrcTokenChanged(srcToken, false);
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

  // /* ============ Internal Functions ============ */

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
