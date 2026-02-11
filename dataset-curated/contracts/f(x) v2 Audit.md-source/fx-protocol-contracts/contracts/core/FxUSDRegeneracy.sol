// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable-v4/access/AccessControlUpgradeable.sol";
import { ERC20PermitUpgradeable } from "@openzeppelin/contracts-upgradeable-v4/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable-v4/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable-v4/token/ERC20/IERC20Upgradeable.sol";
import { EnumerableSetUpgradeable } from "@openzeppelin/contracts-upgradeable-v4/utils/structs/EnumerableSetUpgradeable.sol";

import { IFxFractionalTokenV2 } from "../v2/interfaces/IFxFractionalTokenV2.sol";
import { IFxMarketV2 } from "../v2/interfaces/IFxMarketV2.sol";
import { IFxTreasuryV2 } from "../v2/interfaces/IFxTreasuryV2.sol";
import { IFxUSD } from "../v2/interfaces/IFxUSD.sol";
import { IFxShareableRebalancePool } from "../v2/interfaces/IFxShareableRebalancePool.sol";
import { IFxUSDRegeneracy } from "../interfaces/IFxUSDRegeneracy.sol";
import { IPegKeeper } from "../interfaces/IPegKeeper.sol";

import { Math } from "../libraries/Math.sol";

/// @dev It has the same storage layout with `https://github.com/AladdinDAO/aladdin-v3-contracts/contracts/f(x)/v2/FxUSD.sol`.
contract FxUSDRegeneracy is AccessControlUpgradeable, ERC20PermitUpgradeable, IFxUSD, IFxUSDRegeneracy {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

  /**********
   * Errors *
   **********/

  error ErrorCallerNotPoolManager();

  error ErrorCallerNotPegKeeper();

  error ErrorExceedStableReserve();

  error ErrorInsufficientOutput();

  error ErrorInsufficientBuyBack();

  /*************
   * Constants *
   *************/

  /// @notice The role for migrator.
  bytes32 public constant MIGRATOR_ROLE = keccak256("MIGRATOR_ROLE");

  /// @dev The precision used to compute nav.
  uint256 private constant PRECISION = 1e18;

  /***********
   * Structs *
   ***********/

  /// @param fToken The address of Fractional Token.
  /// @param treasury The address of treasury contract.
  /// @param market The address of market contract.
  /// @param mintCap The maximum amount of fToken can be minted.
  /// @param managed The amount of fToken managed in this contract.
  struct FxMarketStruct {
    address fToken;
    address treasury;
    address market;
    uint256 mintCap;
    uint256 managed;
  }

  /// @dev The struct for stable token reserve.
  /// @param owned The number of stable coins owned in this contract.
  /// @param managed The amount of fxUSD managed under this stable coin.
  /// @param enabled Whether this stable coin is enabled, currently always true
  /// @param decimals The decimal for the stable coin.
  /// @param reserved Reserved slots for future usage.
  struct StableReserveStruct {
    uint96 owned;
    uint96 managed;
    uint8 decimals;
  }

  /***********************
   * Immutable Variables *
   ***********************/

  /// @inheritdoc IFxUSDRegeneracy
  address public immutable poolManager;

  /// @inheritdoc IFxUSDRegeneracy
  address public immutable stableToken;

  /// @inheritdoc IFxUSDRegeneracy
  address public immutable pegKeeper;

  /*********************
   * Storage Variables *
   *********************/

  /// @notice Mapping from base token address to metadata.
  mapping(address => FxMarketStruct) public markets;

  /// @dev The list of supported base tokens.
  EnumerableSetUpgradeable.AddressSet private supportedTokens;

  /// @dev The list of supported rebalance pools.
  EnumerableSetUpgradeable.AddressSet private supportedPools;

  /// @notice The total supply for legacy 2.0 pools.
  uint256 public legacyTotalSupply;

  /// @notice The reserve struct for stable token.
  StableReserveStruct public stableReserve;

  /*************
   * Modifiers *
   *************/

  modifier onlySupportedMarket(address _baseToken) {
    _checkBaseToken(_baseToken);
    _;
  }

  modifier onlySupportedPool(address _pool) {
    if (!supportedPools.contains(_pool)) revert ErrorUnsupportedRebalancePool();
    _;
  }

  modifier onlyMintableMarket(address _baseToken, bool isMint) {
    _checkMarketMintable(_baseToken, isMint);
    _;
  }

  modifier onlyPoolManager() {
    if (_msgSender() != poolManager) revert ErrorCallerNotPoolManager();
    _;
  }

  modifier onlyPegKeeper() {
    if (_msgSender() != pegKeeper) revert ErrorCallerNotPegKeeper();
    _;
  }

  /***************
   * Constructor *
   ***************/

  constructor(address _poolManager, address _stableToken, address _pegKeeper) {
    poolManager = _poolManager;
    stableToken = _stableToken;
    pegKeeper = _pegKeeper;
  }

  function initialize(string memory _name, string memory _symbol) external initializer {
    __Context_init();
    __ERC165_init();
    __AccessControl_init();
    __ERC20_init(_name, _symbol);
    __ERC20Permit_init(_name);

    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  function initializeV2() external reinitializer(2) {
    stableReserve.decimals = FxUSDRegeneracy(stableToken).decimals();
    legacyTotalSupply = totalSupply();
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @inheritdoc IFxUSD
  function getMarkets() external view override returns (address[] memory _tokens) {
    uint256 _numMarkets = supportedTokens.length();
    _tokens = new address[](_numMarkets);
    for (uint256 i = 0; i < _numMarkets; ++i) {
      _tokens[i] = supportedTokens.at(i);
    }
  }

  /// @inheritdoc IFxUSD
  function getRebalancePools() external view override returns (address[] memory _pools) {
    uint256 _numPools = supportedPools.length();
    _pools = new address[](_numPools);
    for (uint256 i = 0; i < _numPools; ++i) {
      _pools[i] = supportedPools.at(i);
    }
  }

  /// @inheritdoc IFxUSD
  function nav() external view override returns (uint256 _nav) {
    uint256 _numMarkets = supportedTokens.length();
    uint256 _supply = legacyTotalSupply;
    if (_supply == 0) return PRECISION;

    for (uint256 i = 0; i < _numMarkets; i++) {
      address _baseToken = supportedTokens.at(i);
      address _fToken = markets[_baseToken].fToken;
      uint256 _fnav = IFxFractionalTokenV2(_fToken).nav();
      _nav += _fnav * markets[_baseToken].managed;
    }
    _nav /= _supply;
  }

  /// @inheritdoc IFxUSD
  function isUnderCollateral() public view override returns (bool) {
    uint256 _numMarkets = supportedTokens.length();
    for (uint256 i = 0; i < _numMarkets; i++) {
      address _baseToken = supportedTokens.at(i);
      address _treasury = markets[_baseToken].treasury;
      if (IFxTreasuryV2(_treasury).isUnderCollateral()) return true;
    }
    return false;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @inheritdoc IFxUSD
  function wrap(
    address _baseToken,
    uint256 _amount,
    address _receiver
  ) external override onlySupportedMarket(_baseToken) onlyMintableMarket(_baseToken, false) {
    if (isUnderCollateral()) revert ErrorUnderCollateral();

    address _fToken = markets[_baseToken].fToken;
    IERC20Upgradeable(_fToken).safeTransferFrom(_msgSender(), address(this), _amount);

    _mintShares(_baseToken, _receiver, _amount);

    emit Wrap(_baseToken, _msgSender(), _receiver, _amount);
  }

  /// @inheritdoc IFxUSD
  function unwrap(
    address _baseToken,
    uint256 _amount,
    address _receiver
  ) external onlyRole(MIGRATOR_ROLE) onlySupportedMarket(_baseToken) {
    if (isUnderCollateral()) revert ErrorUnderCollateral();

    _burnShares(_baseToken, _msgSender(), _amount);

    address _fToken = markets[_baseToken].fToken;
    IERC20Upgradeable(_fToken).safeTransfer(_receiver, _amount);

    emit Unwrap(_baseToken, _msgSender(), _receiver, _amount);
  }

  /// @inheritdoc IFxUSD
  function wrapFrom(address _pool, uint256 _amount, address _receiver) external override onlySupportedPool(_pool) {
    if (isUnderCollateral()) revert ErrorUnderCollateral();

    address _baseToken = IFxShareableRebalancePool(_pool).baseToken();
    _checkBaseToken(_baseToken);
    _checkMarketMintable(_baseToken, false);

    IFxShareableRebalancePool(_pool).withdrawFrom(_msgSender(), _amount, address(this));
    _mintShares(_baseToken, _receiver, _amount);

    emit Wrap(_baseToken, _msgSender(), _receiver, _amount);
  }

  /// @inheritdoc IFxUSD
  function mint(address, uint256, address, uint256) external virtual override returns (uint256) {
    revert("mint paused");
  }

  /// @inheritdoc IFxUSD
  function earn(address, uint256, address) external virtual override {
    revert("earn paused");
  }

  /// @inheritdoc IFxUSD
  function mintAndEarn(address, uint256, address, uint256) external virtual override returns (uint256) {
    revert("mint and earn paused");
  }

  /// @inheritdoc IFxUSD
  function redeem(
    address _baseToken,
    uint256 _amountIn,
    address _receiver,
    uint256 _minOut
  ) external override onlySupportedMarket(_baseToken) returns (uint256 _amountOut, uint256 _bonusOut) {
    if (isUnderCollateral()) revert ErrorUnderCollateral();

    address _market = markets[_baseToken].market;
    address _fToken = markets[_baseToken].fToken;

    uint256 _balance = IERC20Upgradeable(_fToken).balanceOf(address(this));
    (_amountOut, _bonusOut) = IFxMarketV2(_market).redeemFToken(_amountIn, _receiver, _minOut);
    // the real amount of fToken redeemed
    _amountIn = _balance - IERC20Upgradeable(_fToken).balanceOf(address(this));

    _burnShares(_baseToken, _msgSender(), _amountIn);
    emit Unwrap(_baseToken, _msgSender(), _receiver, _amountIn);
  }

  /// @inheritdoc IFxUSD
  function redeemFrom(
    address _pool,
    uint256 _amountIn,
    address _receiver,
    uint256 _minOut
  ) external override onlySupportedPool(_pool) returns (uint256 _amountOut, uint256 _bonusOut) {
    address _baseToken = IFxShareableRebalancePool(_pool).baseToken();
    address _market = markets[_baseToken].market;
    address _fToken = markets[_baseToken].fToken;

    // calculate the actual amount of fToken withdrawn from rebalance pool.
    _amountOut = IERC20Upgradeable(_fToken).balanceOf(address(this));
    IFxShareableRebalancePool(_pool).withdrawFrom(_msgSender(), _amountIn, address(this));
    _amountOut = IERC20Upgradeable(_fToken).balanceOf(address(this)) - _amountOut;

    // redeem fToken as base token
    // assume all fToken will be redeem for simplicity
    (_amountOut, _bonusOut) = IFxMarketV2(_market).redeemFToken(_amountOut, _receiver, _minOut);
  }

  /// @inheritdoc IFxUSD
  function autoRedeem(
    uint256 _amountIn,
    address _receiver,
    uint256[] memory _minOuts
  )
    external
    override
    returns (address[] memory _baseTokens, uint256[] memory _amountOuts, uint256[] memory _bonusOuts)
  {
    uint256 _numMarkets = supportedTokens.length();
    if (_minOuts.length != _numMarkets) revert ErrorLengthMismatch();

    _baseTokens = new address[](_numMarkets);
    _amountOuts = new uint256[](_numMarkets);
    _bonusOuts = new uint256[](_numMarkets);
    uint256[] memory _supplies = new uint256[](_numMarkets);

    bool _isUnderCollateral = false;
    for (uint256 i = 0; i < _numMarkets; i++) {
      _baseTokens[i] = supportedTokens.at(i);
      _supplies[i] = markets[_baseTokens[i]].managed;
      address _treasury = markets[_baseTokens[i]].treasury;
      if (IFxTreasuryV2(_treasury).isUnderCollateral()) _isUnderCollateral = true;
    }

    uint256 _supply = legacyTotalSupply;
    if (_amountIn > _supply) revert("redeem exceed supply");
    unchecked {
      legacyTotalSupply = _supply - _amountIn;
    }
    _burn(_msgSender(), _amountIn);

    if (_isUnderCollateral) {
      // redeem proportionally
      for (uint256 i = 0; i < _numMarkets; i++) {
        _amountOuts[i] = (_supplies[i] * _amountIn) / _supply;
      }
    } else {
      // redeem by sorted fToken amounts
      while (_amountIn > 0) {
        unchecked {
          uint256 maxSupply = _supplies[0];
          uint256 maxIndex = 0;
          for (uint256 i = 1; i < _numMarkets; i++) {
            if (_supplies[i] > maxSupply) {
              maxSupply = _supplies[i];
              maxIndex = i;
            }
          }
          if (_amountIn > maxSupply) _amountOuts[maxIndex] = maxSupply;
          else _amountOuts[maxIndex] = _amountIn;
          _supplies[maxIndex] -= _amountOuts[maxIndex];
          _amountIn -= _amountOuts[maxIndex];
        }
      }
    }

    for (uint256 i = 0; i < _numMarkets; i++) {
      if (_amountOuts[i] == 0) continue;
      emit Unwrap(_baseTokens[i], _msgSender(), _receiver, _amountOuts[i]);

      markets[_baseTokens[i]].managed -= _amountOuts[i];
      address _market = markets[_baseTokens[i]].market;
      (_amountOuts[i], _bonusOuts[i]) = IFxMarketV2(_market).redeemFToken(_amountOuts[i], _receiver, _minOuts[i]);
    }
  }

  /// @inheritdoc IFxUSDRegeneracy
  function mint(address to, uint256 amount) external onlyPoolManager {
    _mint(to, amount);
  }

  /// @inheritdoc IFxUSDRegeneracy
  function burn(address from, uint256 amount) external onlyPoolManager {
    _burn(from, amount);
  }

  /// @inheritdoc IFxUSDRegeneracy
  function onRebalanceWithStable(uint256 amountStableToken, uint256 amountFxUSD) external onlyPoolManager {
    stableReserve.owned += uint96(amountStableToken);
    stableReserve.managed += uint96(amountFxUSD);

    emit RebalanceWithStable(amountStableToken, amountFxUSD);
  }

  /// @inheritdoc IFxUSDRegeneracy
  function buyback(
    uint256 amountIn,
    address receiver,
    bytes calldata data
  ) external onlyPegKeeper returns (uint256 amountOut, uint256 bonusOut) {
    StableReserveStruct memory cachedStableReserve = stableReserve;
    if (amountIn > cachedStableReserve.owned) revert ErrorExceedStableReserve();

    // rounding up
    uint256 expectedFxUSD = Math.mulDivUp(amountIn, cachedStableReserve.managed, cachedStableReserve.owned);

    // convert USDC to fxUSD
    IERC20Upgradeable(stableToken).safeTransfer(pegKeeper, amountIn);
    uint256 actualOut = balanceOf(address(this));
    amountOut = IPegKeeper(pegKeeper).onSwap(stableToken, address(this), amountIn, data);
    actualOut = balanceOf(address(this)) - actualOut;

    // check actual fxUSD swapped in case peg keeper is hacked.
    if (amountOut > actualOut) revert ErrorInsufficientOutput();

    // check fxUSD swapped can cover debts
    if (amountOut < expectedFxUSD) revert ErrorInsufficientBuyBack();
    bonusOut = amountOut - expectedFxUSD;

    _burn(address(this), expectedFxUSD);
    unchecked {
      cachedStableReserve.owned -= uint96(amountIn);
      if (cachedStableReserve.managed > expectedFxUSD) {
        cachedStableReserve.managed -= uint96(expectedFxUSD);
      } else {
        cachedStableReserve.managed = 0;
      }
      stableReserve = cachedStableReserve;
    }

    if (bonusOut > 0) {
      _transfer(address(this), receiver, bonusOut);
    }

    emit Buyback(amountIn, amountOut, bonusOut);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to check base token.
  /// @param _baseToken The address of the base token.
  function _checkBaseToken(address _baseToken) private view {
    if (!supportedTokens.contains(_baseToken)) revert ErrorUnsupportedMarket();
  }

  /// @dev Internal function to check market.
  /// @param _baseToken The address of the base token.
  /// @param _checkCollateralRatio Whether to check collateral ratio.
  function _checkMarketMintable(address _baseToken, bool _checkCollateralRatio) private view {
    address _treasury = markets[_baseToken].treasury;
    if (_checkCollateralRatio) {
      uint256 _collateralRatio = IFxTreasuryV2(_treasury).collateralRatio();
      uint256 _stabilityRatio = IFxMarketV2(markets[_baseToken].market).stabilityRatio();
      // not allow to mint when collateral ratio <= stability ratio
      if (_collateralRatio <= _stabilityRatio) revert ErrorMarketInStabilityMode();
    }
    // not allow to mint when price is invalid
    if (!IFxTreasuryV2(_treasury).isBaseTokenPriceValid()) revert ErrorMarketWithInvalidPrice();
  }

  /// @dev Internal function to mint fxUSD.
  /// @param _baseToken The address of the base token.
  /// @param _receiver The address of fxUSD recipient.
  /// @param _amount The amount of fxUSD to mint.
  function _mintShares(address _baseToken, address _receiver, uint256 _amount) private {
    unchecked {
      markets[_baseToken].managed += _amount;
      legacyTotalSupply += _amount;
    }

    _mint(_receiver, _amount);
  }

  /// @dev Internal function to burn fxUSD.
  /// @param _baseToken The address of the base token.
  /// @param _owner The address of fxUSD owner.
  /// @param _amount The amount of fxUSD to burn.
  function _burnShares(address _baseToken, address _owner, uint256 _amount) private {
    uint256 _managed = markets[_baseToken].managed;
    if (_amount > _managed) revert ErrorInsufficientLiquidity();
    unchecked {
      markets[_baseToken].managed -= _amount;
      legacyTotalSupply -= _amount;
    }

    _burn(_owner, _amount);
  }
}
