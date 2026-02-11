// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ERC20PermitUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { IMultipleRewardDistributor } from "../common/rewards/distributor/IMultipleRewardDistributor.sol";
import { IHarvesterCallback } from "../helpers/interfaces/IHarvesterCallback.sol";
import { IConvexFXNBooster } from "../interfaces/Convex/IConvexFXNBooster.sol";
import { IStakingProxyERC20 } from "../interfaces/Convex/IStakingProxyERC20.sol";
import { IFxUSDBasePool } from "../interfaces/IFxUSDBasePool.sol";
import { ISavingFxUSD } from "../interfaces/ISavingFxUSD.sol";
import { ILiquidityGauge } from "../voting-escrow/interfaces/ILiquidityGauge.sol";

import { WordCodec } from "../common/codec/WordCodec.sol";
import { ConcentratorBase } from "../common/concentrator/ConcentratorBase.sol";

contract LockedFxSaveProxy {
  address immutable fxSAVE;

  error ErrorCallerNotFxSave();

  constructor() {
    fxSAVE = msg.sender;
  }

  function execute(address target, bytes calldata data) external {
    if (msg.sender != fxSAVE) revert ErrorCallerNotFxSave();

    (bool success, ) = target.call(data);
    // below lines will propagate inner error up
    if (!success) {
      // solhint-disable-next-line no-inline-assembly
      assembly {
        let ptr := mload(0x40)
        let size := returndatasize()
        returndatacopy(ptr, 0, size)
        revert(ptr, size)
      }
    }
  }
}

contract SavingFxUSD is ERC20PermitUpgradeable, ERC4626Upgradeable, ConcentratorBase, ISavingFxUSD {
  using SafeERC20 for IERC20;
  using WordCodec for bytes32;

  /**********
   * Errors *
   **********/

  /// @dev Thrown when the threshold exceeds `MAX_THRESHOLD`.
  error ErrorThresholdTooLarge();

  /*************
   * Constants *
   *************/

  /// @dev The role for `claimFor` function.
  bytes32 public constant CLAIM_FOR_ROLE = keccak256("CLAIM_FOR_ROLE");

  /// @dev The address of Convex's f(x) Booster contract.
  address private constant BOOSTER = 0xAffe966B27ba3E4Ebb8A0eC124C7b7019CC762f8;

  /// @dev The address of FXN token.
  address private constant FXN = 0x365AccFCa291e7D3914637ABf1F7635dB165Bb09;

  /// @dev The denominator used for precision calculation.
  uint256 private constant PRECISION = 1e18;

  /// @dev The number of bits for threshold.
  uint256 private constant THRESHOLD_BITS = 80;

  /// @dev The offset of threshold in `_miscData`.
  uint256 private constant THRESHOLD_OFFSET = 60;
  
  /// @dev The maximum value of threshold, 2^80-1.
  uint256 private constant MAX_THRESHOLD = 1208925819614629174706175;

  /***********************
   * Immutable Variables *
   ***********************/

  /// @notice The address of `FxUSDBasePool` contract.
  address public immutable base;

  /// @notice The address of `FxUSDBasePool` gauge contract.
  address public immutable gauge;

  /*************
   * Variables *
   *************/

  /// @notice The address of Convex's `StakingProxyERC20` contract.
  address public vault;

  /// @notice Mapping from user address to `LockedFxSaveProxy` contract.
  mapping(address => address) public lockedProxy;

  /***************
   * Constructor *
   ***************/

  struct InitializationParameters {
    string name;
    string symbol;
    uint256 pid;
    uint256 threshold;
    address treasury;
    address harvester;
  }

  constructor(address _base, address _gauge) {
    base = _base;
    gauge = _gauge;
  }

  function initialize(address admin, InitializationParameters memory params) external initializer {
    __Context_init();
    __ERC165_init();
    __AccessControl_init();

    __ERC20_init(params.name, params.symbol);
    __ERC20Permit_init(params.name);
    __ERC4626_init(IERC20(base));

    __ConcentratorBase_init(params.treasury, params.harvester);

    _grantRole(DEFAULT_ADMIN_ROLE, admin);

    vault = IConvexFXNBooster(BOOSTER).createVault(params.pid);
    _updateThreshold(params.threshold);

    IERC20(base).forceApprove(gauge, type(uint256).max);
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @inheritdoc ERC4626Upgradeable
  function decimals() public view virtual override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
    return ERC4626Upgradeable.decimals();
  }

  /// @inheritdoc ERC4626Upgradeable
  function totalAssets() public view virtual override returns (uint256) {
    return IERC20(base).balanceOf(address(this)) + IERC20(gauge).balanceOf(vault);
  }

  /// @notice Return the threshold for batch deposit.
  function getThreshold() public view returns (uint256) {
    return _miscData.decodeUint(THRESHOLD_OFFSET, THRESHOLD_BITS);
  }

  /// @inheritdoc ISavingFxUSD
  function nav() external view returns (uint256) {
    return (IFxUSDBasePool(base).nav() * convertToAssets(PRECISION)) / PRECISION;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @inheritdoc ISavingFxUSD
  function depositGauge(uint256 assets, address receiver) external returns (uint256) {
    uint256 maxAssets = maxDeposit(receiver);
    if (assets > maxAssets) {
      revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
    }

    uint256 shares = previewDeposit(assets);

    IERC20(gauge).safeTransferFrom(_msgSender(), vault, assets);
    _mint(receiver, shares);

    emit Deposit(_msgSender(), receiver, assets, shares);

    return shares;
  }

  /// @inheritdoc ISavingFxUSD
  function requestRedeem(uint256 shares) external returns (uint256) {
    address owner = _msgSender();
    uint256 maxShares = maxRedeem(owner);
    if (shares > maxShares) {
      revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
    }

    uint256 assets = previewRedeem(shares);
    _requestRedeem(owner, assets, shares);

    return assets;
  }

  /// @inheritdoc ISavingFxUSD
  function claim(address receiver) external {
    _claim(_msgSender(), receiver);
  }

  /// @inheritdoc ISavingFxUSD
  function claimFor(address owner, address receiver) external onlyRole(CLAIM_FOR_ROLE) {
    _claim(owner, receiver);
  }

  /// @inheritdoc ISavingFxUSD
  function harvest() external {
    IStakingProxyERC20(vault).getReward();
    address[] memory tokens = IMultipleRewardDistributor(gauge).getActiveRewardTokens();
    address cachedHarvester = harvester;
    uint256 harvesterRatio = getHarvesterRatio();
    uint256 expenseRatio = getExpenseRatio();
    bool hasFXN = false;
    for (uint256 i = 0; i < tokens.length; ++i) {
      _transferRewards(tokens[i], cachedHarvester, harvesterRatio, expenseRatio);
      if (tokens[i] == FXN) hasFXN = true;
    }
    if (!hasFXN) {
      _transferRewards(FXN, cachedHarvester, harvesterRatio, expenseRatio);
    }
  }

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Update the threshold for batch deposit.
  /// @param newThreshold The address of new threshold.
  function updateThreshold(uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateThreshold(newThreshold);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @inheritdoc ERC4626Upgradeable
  function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
    ERC4626Upgradeable._deposit(caller, receiver, assets, shares);

    // batch deposit to gauge through convex vault
    uint256 balance = IERC20(base).balanceOf(address(this));
    if (balance >= getThreshold()) {
      ILiquidityGauge(gauge).deposit(balance, vault);
    }
  }

  /// @inheritdoc ERC4626Upgradeable
  function _withdraw(
    address caller,
    address receiver,
    address owner,
    uint256 assets,
    uint256 shares
  ) internal virtual override {
    if (caller != owner) {
      _spendAllowance(owner, caller, shares);
    }

    // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
    // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
    // calls the vault, which is assumed not malicious.
    //
    // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
    // shares are burned and after the assets are transferred, which is a valid state.
    _burn(owner, shares);

    emit Withdraw(caller, receiver, owner, assets, shares);

    // Withdraw from gauge
    IStakingProxyERC20(vault).withdraw(assets);
    IERC20(base).transfer(receiver, assets);
  }

  /// @inheritdoc ConcentratorBase
  function _onHarvest(address token, uint256 amount) internal virtual override {
    if (token == gauge) {
      IERC20(gauge).safeTransfer(vault, amount);
      return;
    } else if (token != base) {
      IERC20(token).forceApprove(base, amount);
      IFxUSDBasePool(base).deposit(address(this), token, amount, 0);
    }
    amount = IERC20(base).balanceOf(address(this));
    ILiquidityGauge(gauge).deposit(amount, vault);
  }

  /// @dev Internal function to update the threshold for batch deposit.
  /// @param newThreshold The address of new threshold.
  function _updateThreshold(uint256 newThreshold) internal {
    if (newThreshold > MAX_THRESHOLD) revert ErrorThresholdTooLarge();

    bytes32 _data = _miscData;
    uint256 oldThreshold = _miscData.decodeUint(THRESHOLD_OFFSET, THRESHOLD_BITS);
    _miscData = _data.insertUint(newThreshold, THRESHOLD_OFFSET, THRESHOLD_BITS);

    emit UpdateThreshold(oldThreshold, newThreshold);
  }

  /// @dev Internal function to transfer rewards to harvester.
  /// @param token The address of rewards.
  /// @param receiver The address of harvester.
  function _transferRewards(address token, address receiver, uint256 harvesterRatio, uint256 expenseRatio) internal {
    if (token == base) return;
    uint256 balance = IERC20(token).balanceOf(address(this));
    if (balance > 0) {
      uint256 performanceFee = (balance * expenseRatio) / FEE_PRECISION;
      uint256 harvesterBounty = (balance * harvesterRatio) / FEE_PRECISION;
      if (harvesterBounty > 0) {
        IERC20(token).safeTransfer(_msgSender(), harvesterBounty);
      }
      if (performanceFee > 0) {
        IERC20(token).safeTransfer(treasury, performanceFee);
      }
      IERC20(token).safeTransfer(receiver, balance - performanceFee - harvesterBounty);
    }
  }

  /// @dev Internal function to request redeem.
  function _requestRedeem(address owner, uint256 assets, uint256 shares) internal {
    // burn shares
    _burn(owner, shares);

    // Withdraw from gauge
    IStakingProxyERC20(vault).withdraw(assets);

    // create locked fxSave proxy
    address proxy = lockedProxy[owner];
    if (proxy == address(0)) {
      proxy = address(new LockedFxSaveProxy{ salt: keccak256(abi.encode(owner)) }());
      lockedProxy[owner] = proxy;
    }

    // transfer to proxy for unlocking and request unlock
    IERC20(base).transfer(proxy, assets);
    LockedFxSaveProxy(proxy).execute(base, abi.encodeCall(IFxUSDBasePool.requestRedeem, (assets)));

    emit RequestRedeem(owner, shares, assets);
  }

  /// @dev Internal function to claim unlocked tokens.
  function _claim(address owner, address receiver) internal {
    address proxy = lockedProxy[owner];
    LockedFxSaveProxy(proxy).execute(base, abi.encodeCall(IFxUSDBasePool.redeem, (receiver, type(uint256).max)));

    emit Claim(owner, receiver);
  }
}
