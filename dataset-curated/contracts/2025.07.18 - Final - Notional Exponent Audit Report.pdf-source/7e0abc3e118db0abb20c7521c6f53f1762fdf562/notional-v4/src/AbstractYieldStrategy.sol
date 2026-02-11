// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {DEFAULT_DECIMALS, DEFAULT_PRECISION, YEAR, ADDRESS_REGISTRY} from "./utils/Constants.sol";

import {
    Unauthorized,
    UnauthorizedLendingMarketTransfer,
    InsufficientSharesHeld,
    CannotLiquidate,
    CannotEnterPosition,
    CurrentAccountAlreadySet
} from "./interfaces/Errors.sol";
import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {IOracle} from "./interfaces/Morpho/IOracle.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Trade, TradeType, TRADING_MODULE, nProxy, TradeFailed} from "./interfaces/ITradingModule.sol";
import {IWithdrawRequestManager} from "./interfaces/IWithdrawRequestManager.sol";
import {Initializable} from "./proxy/Initializable.sol";
import {ADDRESS_REGISTRY} from "./utils/Constants.sol";
import {ILendingRouter} from "./interfaces/ILendingRouter.sol";

/// @title AbstractYieldStrategy
/// @notice This is the base contract for all yield strategies, it implements the core logic for
/// minting, burning and the valuation of tokens.
abstract contract AbstractYieldStrategy is Initializable, ERC20, ReentrancyGuardTransient, IYieldStrategy {
    using TokenUtils for ERC20;
    using SafeERC20 for ERC20;

    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_YIELD_TOKENS = 1;
    uint256 internal constant SHARE_PRECISION = DEFAULT_PRECISION * VIRTUAL_SHARES;

    /// @inheritdoc IYieldStrategy
    address public immutable override asset;
    /// @inheritdoc IYieldStrategy
    address public immutable override yieldToken;
    /// @inheritdoc IYieldStrategy
    uint256 public immutable override feeRate;

    IWithdrawRequestManager internal immutable withdrawRequestManager;

    uint8 internal immutable _yieldTokenDecimals;
    uint8 internal immutable _assetDecimals;

    /********* Storage Variables *********/
    string private s_name;
    string private s_symbol;

    uint32 private s_lastFeeAccrualTime;
    uint256 private s_accruedFeesInYieldToken;
    uint256 private s_escrowedShares;
    /****** End Storage Variables ******/

    /********* Transient Variables *********/
    // Used to adjust the valuation call of price(), is set on some methods and
    // cleared by the lending router using clearCurrentAccount(). This is required to
    // ensure that the variable is set throughout the entire context of the lending router
    // call.
    address internal transient t_CurrentAccount;
    // Set and cleared on every call to a lending router authorized method
    address internal transient t_CurrentLendingRouter;
    // Used to authorize transfers off of the lending market
    address internal transient t_AllowTransfer_To;
    uint256 internal transient t_AllowTransfer_Amount;
    /****** End Transient Variables ******/

    constructor(
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        uint8 __yieldTokenDecimals
    ) ERC20("", "") {
        feeRate = _feeRate;
        asset = address(_asset);
        yieldToken = address(_yieldToken);
        // Not all yield tokens have a decimals() function (i.e. Convex staked tokens), so we
        // do have to pass in the decimals as a parameter.
        _yieldTokenDecimals = __yieldTokenDecimals;
        _assetDecimals = TokenUtils.getDecimals(_asset);
    }

    function name() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return s_name;
    }

    function symbol() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return s_symbol;
    }

    /*** Valuation and Conversion Functions ***/

    /// @inheritdoc IYieldStrategy
    function convertSharesToYieldToken(uint256 shares) public view override returns (uint256) {
        // NOTE: rounds down on division
        return (shares * (_yieldTokenBalance() - feesAccrued() + VIRTUAL_YIELD_TOKENS)) / (effectiveSupply());
    }

    /// @inheritdoc IYieldStrategy
    function convertYieldTokenToShares(uint256 yieldTokens) public view returns (uint256) {
        // NOTE: rounds down on division
        return (yieldTokens * effectiveSupply()) / (_yieldTokenBalance() - feesAccrued() + VIRTUAL_YIELD_TOKENS);
    }

    /// @inheritdoc IYieldStrategy
    function convertToShares(uint256 assets) public view override returns (uint256) {
        // NOTE: rounds down on division
        uint256 yieldTokens = assets * (10 ** (_yieldTokenDecimals + DEFAULT_DECIMALS)) / 
            (convertYieldTokenToAsset() * (10 ** _assetDecimals));
        return convertYieldTokenToShares(yieldTokens);
    }

    /// @inheritdoc IOracle
    function price() public view override returns (uint256) {
        return convertToAssets(SHARE_PRECISION) * (10 ** (36 - 24));
    }

    /// @inheritdoc IYieldStrategy
    function price(address borrower) external override returns (uint256) {
        // Do not change the current account in this method since this method is not
        // authenticated and we do not want to have any unexpected side effects.
        address prevCurrentAccount = t_CurrentAccount;

        t_CurrentAccount = borrower;
        uint256 p = convertToAssets(SHARE_PRECISION) * (10 ** (36 - 24));

        t_CurrentAccount = prevCurrentAccount;
        return p;
    }

    /// @inheritdoc IYieldStrategy
    function totalAssets() public view override returns (uint256) {
        return convertToAssets(totalSupply());
    }

    /// @inheritdoc IYieldStrategy
    function convertYieldTokenToAsset() public view returns (uint256) {
        // The trading module always returns a positive rate in 18 decimals so we can safely
        // cast to uint256
        (int256 rate , /* */) = TRADING_MODULE.getOraclePrice(yieldToken, asset);
        return uint256(rate);
    }

    /// @inheritdoc IYieldStrategy
    function effectiveSupply() public view returns (uint256) {
        return (totalSupply() - s_escrowedShares + VIRTUAL_SHARES);
    }

    /*** Fee Methods ***/

    /// @inheritdoc IYieldStrategy
    function feesAccrued() public view override returns (uint256 feesAccruedInYieldToken) {
        return s_accruedFeesInYieldToken + _calculateAdditionalFeesInYieldToken();
    }

    /// @inheritdoc IYieldStrategy
    function collectFees() external override {
        _accrueFees();
        _transferYieldTokenToOwner(ADDRESS_REGISTRY.feeReceiver(), s_accruedFeesInYieldToken);

        delete s_accruedFeesInYieldToken;
    }

    /*** Core Functions ***/
    modifier onlyLendingRouter() {
        if (ADDRESS_REGISTRY.isLendingRouter(msg.sender) == false) revert Unauthorized(msg.sender);
        t_CurrentLendingRouter = msg.sender;
        _;
        delete t_CurrentLendingRouter;
    }

    modifier setCurrentAccount(address onBehalf) {
        if (t_CurrentAccount == address(0)) {
            t_CurrentAccount = onBehalf;
        } else if (t_CurrentAccount != onBehalf) {
            revert CurrentAccountAlreadySet();
        }

        _;
    }

    /// @inheritdoc IYieldStrategy
    function clearCurrentAccount() external override onlyLendingRouter {
        delete t_CurrentAccount;
    }

    function mintShares(
        uint256 assetAmount,
        address receiver,
        bytes calldata depositData
    ) external override onlyLendingRouter setCurrentAccount(receiver) nonReentrant returns (uint256 sharesMinted) {
        // Cannot mint shares if the receiver has an active withdraw request
        if (_isWithdrawRequestPending(receiver)) revert CannotEnterPosition();
        ERC20(asset).safeTransferFrom(t_CurrentLendingRouter, address(this), assetAmount);
        sharesMinted = _mintSharesGivenAssets(assetAmount, depositData, receiver);

        t_AllowTransfer_To = t_CurrentLendingRouter;
        t_AllowTransfer_Amount = sharesMinted;
        // Transfer the shares to the lending router so it can supply collateral
        _transfer(receiver, t_CurrentLendingRouter, sharesMinted);
    }

    function burnShares(
        address sharesOwner,
        uint256 sharesToBurn,
        uint256 sharesHeld,
        bytes calldata redeemData
    ) external override onlyLendingRouter setCurrentAccount(sharesOwner) nonReentrant returns (uint256 assetsWithdrawn) {
        assetsWithdrawn = _burnShares(sharesToBurn, sharesHeld, redeemData, sharesOwner);

        // Send all the assets back to the lending router
        ERC20(asset).safeTransfer(t_CurrentLendingRouter, assetsWithdrawn);
    }

    function allowTransfer(
        address to, uint256 amount, address currentAccount
    ) external setCurrentAccount(currentAccount) onlyLendingRouter {
        // Sets the transient variables to allow the lending market to transfer shares on exit position
        // or liquidation.
        t_AllowTransfer_To = to;
        t_AllowTransfer_Amount = amount;
    }

    function preLiquidation(
        address liquidator,
        address liquidateAccount,
        uint256 sharesToLiquidate,
        uint256 accountSharesHeld
    ) external onlyLendingRouter {
        t_CurrentAccount = liquidateAccount;
        // Liquidator cannot liquidate if they have an active withdraw request, including a tokenized
        // withdraw request.
        if (_isWithdrawRequestPending(liquidator)) revert CannotEnterPosition();
        // Cannot receive a pending withdraw request if the liquidator has a balanceOf
        if (_isWithdrawRequestPending(liquidateAccount) && balanceOf(liquidator) > 0) {
            revert CannotEnterPosition();
        }
        _preLiquidation(liquidateAccount, liquidator, sharesToLiquidate, accountSharesHeld);

        // Allow transfers to the lending router which will proxy the call to liquidate.
        t_AllowTransfer_To = msg.sender;
        t_AllowTransfer_Amount = sharesToLiquidate;
    }

    function postLiquidation(
        address liquidator,
        address liquidateAccount,
        uint256 sharesToLiquidator
    ) external onlyLendingRouter {
        t_AllowTransfer_To = liquidator;
        t_AllowTransfer_Amount = sharesToLiquidator;
        // Transfer the shares to the liquidator from the lending router
        _transfer(t_CurrentLendingRouter, liquidator, sharesToLiquidator);

        _postLiquidation(liquidator, liquidateAccount, sharesToLiquidator);

        // Clear the transient variables to prevent re-use in a future call.
        delete t_CurrentAccount;
    }

    /// @inheritdoc IYieldStrategy
    /// @dev We do not set the current account here because valuation is not done in this method.
    /// A native balance does not require a collateral check.
    function redeemNative(
        uint256 sharesToRedeem,
        bytes memory redeemData
    ) external override nonReentrant returns (uint256 assetsWithdrawn) {
        uint256 sharesHeld = balanceOf(msg.sender);
        if (sharesHeld == 0) revert InsufficientSharesHeld();

        assetsWithdrawn = _burnShares(sharesToRedeem, sharesHeld, redeemData, msg.sender);
        ERC20(asset).safeTransfer(msg.sender, assetsWithdrawn);
    }

    /// @inheritdoc IYieldStrategy
    function initiateWithdraw(
        address account,
        uint256 sharesHeld,
        bytes calldata data
    ) external onlyLendingRouter setCurrentAccount(account) override returns (uint256 requestId) {
        requestId = _withdraw(account, sharesHeld, data);
    }

    /// @inheritdoc IYieldStrategy
    /// @dev We do not set the current account here because valuation is not done in this method. A
    /// native balance does not require a collateral check.
    function initiateWithdrawNative(
        bytes memory data
    ) external override returns (uint256 requestId) {
        requestId = _withdraw(msg.sender, balanceOf(msg.sender), data);
    }

    function _withdraw(address account, uint256 sharesHeld, bytes memory data) internal returns (uint256 requestId) {
        if (sharesHeld == 0) revert InsufficientSharesHeld();

        // Accrue fees before initiating a withdraw since it will change the effective supply
        _accrueFees();
        uint256 yieldTokenAmount = convertSharesToYieldToken(sharesHeld);
        requestId = _initiateWithdraw(account, yieldTokenAmount, sharesHeld, data);
        // Escrow the shares after the withdraw since it will change the effective supply
        // during reward claims when using the RewardManagerMixin.
        s_escrowedShares += sharesHeld;
    }

    /*** Private Functions ***/

    function _calculateAdditionalFeesInYieldToken() private view returns (uint256 additionalFeesInYieldToken) {
        uint256 timeSinceLastFeeAccrual = block.timestamp - s_lastFeeAccrualTime;
        // e ^ (feeRate * timeSinceLastFeeAccrual / YEAR)
        uint256 x = (feeRate * timeSinceLastFeeAccrual) / YEAR;
        if (x == 0) return 0;

        uint256 preFeeUserHeldYieldTokens = _yieldTokenBalance() - s_accruedFeesInYieldToken;
        // Taylor approximation of e ^ x = 1 + x + x^2 / 2! + x^3 / 3! + ...
        uint256 eToTheX = DEFAULT_PRECISION + x + (x * x) / (2 * DEFAULT_PRECISION) + (x * x * x) / (6 * DEFAULT_PRECISION * DEFAULT_PRECISION);
        // Decay the user's yield tokens by e ^ (feeRate * timeSinceLastFeeAccrual / YEAR)
        uint256 postFeeUserHeldYieldTokens = preFeeUserHeldYieldTokens * DEFAULT_PRECISION / eToTheX;

        additionalFeesInYieldToken = preFeeUserHeldYieldTokens - postFeeUserHeldYieldTokens;
    }

    function _accrueFees() private {
        if (s_lastFeeAccrualTime == block.timestamp) return;
        // NOTE: this has to be called before any mints or burns.
        s_accruedFeesInYieldToken += _calculateAdditionalFeesInYieldToken();
        s_lastFeeAccrualTime = uint32(block.timestamp);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            // Any transfers off of the lending market must be authorized here, this means that native balances
            // held cannot be transferred.
            if (t_AllowTransfer_To != to) revert UnauthorizedLendingMarketTransfer(from, to, value);
            if (t_AllowTransfer_Amount < value) revert UnauthorizedLendingMarketTransfer(from, to, value);

            delete t_AllowTransfer_To;
            delete t_AllowTransfer_Amount;
        }

        super._update(from, to, value);
    }

    /*** Internal Helper Functions ***/

    function _isWithdrawRequestPending(address account) virtual internal view returns (bool) {
        return address(withdrawRequestManager) != address(0)
            && withdrawRequestManager.isPendingWithdrawRequest(address(this), account);
    }

    function _yieldTokenBalance() internal view returns (uint256) {
        return ERC20(yieldToken).balanceOf(address(this));
    }

    /// @dev Can be used to delegate call to the TradingModule's implementation in order to execute a trade
    function _executeTrade(
        Trade memory trade,
        uint16 dexId
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        if (trade.tradeType == TradeType.STAKE_TOKEN) {
            IWithdrawRequestManager wrm = ADDRESS_REGISTRY.getWithdrawRequestManager(trade.buyToken);
            ERC20(trade.sellToken).checkApprove(address(wrm), trade.amount);
            amountBought = wrm.stakeTokens(trade.sellToken, trade.amount, trade.exchangeData);
            return (trade.amount, amountBought);
        } else {
            address implementation = nProxy(payable(address(TRADING_MODULE))).getImplementation();
            bytes memory result = _delegateCall(
                implementation, abi.encodeWithSelector(TRADING_MODULE.executeTrade.selector, dexId, trade)
            );
            (amountSold, amountBought) = abi.decode(result, (uint256, uint256));
        }
    }

    function _delegateCall(address target, bytes memory data) internal returns (bytes memory result) {
        bool success;
        (success, result) = target.delegatecall(data);
        if (!success) {
            assembly {
                // Copy the return data to memory
                returndatacopy(0, 0, returndatasize())
                // Revert with the return data
                revert(0, returndatasize())
            }
        }
    }

    /*** Virtual Functions ***/

    function _initialize(bytes calldata data) internal override virtual {
        (string memory _name, string memory _symbol) = abi.decode(data, (string, string));
        s_name = _name;
        s_symbol = _symbol;

        s_lastFeeAccrualTime = uint32(block.timestamp);
        emit VaultCreated(address(this));
    }

    /// @dev Marked as virtual to allow for RewardManagerMixin to override
    function _mintSharesGivenAssets(uint256 assets, bytes memory depositData, address receiver) internal virtual returns (uint256 sharesMinted) {
        if (assets == 0) return 0;

        // First accrue fees on the yield token
        _accrueFees();
        uint256 initialYieldTokenBalance = _yieldTokenBalance();
        _mintYieldTokens(assets, receiver, depositData);
        uint256 yieldTokensMinted = _yieldTokenBalance() - initialYieldTokenBalance;

        sharesMinted = (yieldTokensMinted * effectiveSupply()) / (initialYieldTokenBalance - feesAccrued() + VIRTUAL_YIELD_TOKENS);
        _mint(receiver, sharesMinted);
    }

    /// @dev Marked as virtual to allow for RewardManagerMixin to override
    function _burnShares(
        uint256 sharesToBurn,
        uint256 /* sharesHeld */,
        bytes memory redeemData,
        address sharesOwner
    ) internal virtual returns (uint256 assetsWithdrawn) {
        if (sharesToBurn == 0) return 0;
        bool isEscrowed = _isWithdrawRequestPending(sharesOwner);

        uint256 initialAssetBalance = TokenUtils.tokenBalance(asset);

        // First accrue fees on the yield token
        _accrueFees();
        _redeemShares(sharesToBurn, sharesOwner, isEscrowed, redeemData);
        if (isEscrowed) s_escrowedShares -= sharesToBurn;

        uint256 finalAssetBalance = TokenUtils.tokenBalance(asset);
        assetsWithdrawn = finalAssetBalance - initialAssetBalance;

        // This burns the shares from the sharesOwner's balance
        _burn(sharesOwner, sharesToBurn);
    }

    /// @dev Some yield tokens (such as Convex staked tokens) cannot be transferred, so we may need
    /// to override this function.
    function _transferYieldTokenToOwner(address owner, uint256 yieldTokens) internal virtual {
        ERC20(yieldToken).safeTransfer(owner, yieldTokens);
    }

    /// @dev Returns the maximum number of shares that can be liquidated. Allows the strategy to override the
    /// underlying lending market's liquidation logic.
    function _preLiquidation(address liquidateAccount, address liquidator, uint256 sharesToLiquidate, uint256 accountSharesHeld) internal virtual;

    /// @dev Called after liquidation
    function _postLiquidation(address liquidator, address liquidateAccount, uint256 sharesToLiquidator) internal virtual returns (bool didTokenize);

    /// @dev Mints yield tokens given a number of assets.
    function _mintYieldTokens(uint256 assets, address receiver, bytes memory depositData) internal virtual;

    /// @dev Redeems shares
    function _redeemShares(
        uint256 sharesToRedeem,
        address sharesOwner,
        bool isEscrowed,
        bytes memory redeemData
    ) internal virtual;

    function _initiateWithdraw(
        address account,
        uint256 yieldTokenAmount,
        uint256 sharesHeld,
        bytes memory data
    ) internal virtual returns (uint256 requestId);

    /// @inheritdoc IYieldStrategy
    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        uint256 yieldTokens = convertSharesToYieldToken(shares);
        // NOTE: rounds down on division
        return (yieldTokens * convertYieldTokenToAsset() * (10 ** _assetDecimals)) /
            (10 ** (_yieldTokenDecimals + DEFAULT_DECIMALS));
    }

}

