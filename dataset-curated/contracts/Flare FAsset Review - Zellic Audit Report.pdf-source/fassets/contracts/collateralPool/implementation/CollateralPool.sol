// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "../../openzeppelin/security/ReentrancyGuard.sol";
import {SafePct} from "../../utils/library/SafePct.sol";
import {Transfers} from "../../utils/library/Transfers.sol";
import {MathUtils} from "../../utils/library/MathUtils.sol";
import {IFAsset} from "../../userInterfaces/IFAsset.sol";
import {IWNat} from "../../flareSmartContracts/interfaces/IWNat.sol";
import {IIAssetManager} from "../../assetManager/interfaces/IIAssetManager.sol";
import {IICollateralPool} from "../../collateralPool/interfaces/IICollateralPool.sol";
import {IICollateralPoolToken} from "../interfaces/IICollateralPoolToken.sol";
import {ICollateralPoolToken} from "../../userInterfaces/ICollateralPoolToken.sol";
import {IRewardManager} from "@flarenetwork/flare-periphery-contracts/flare/IRewardManager.sol";
import {IDistributionToDelegators} from "@flarenetwork/flare-periphery-contracts/flare/IDistributionToDelegators.sol";
import {ICollateralPool} from "../../userInterfaces/ICollateralPool.sol";
import {EmergencyPause} from "../../userInterfaces/data/EmergencyPause.sol";


//slither-disable reentrancy    // all possible reentrancies guarded by nonReentrant
contract CollateralPool is IICollateralPool, ReentrancyGuard, UUPSUpgradeable, IERC165 {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafePct for uint256;
    using SafeERC20 for IFAsset;
    using SafeERC20 for IWNat;

    struct AssetPrice {
        uint256 mul;
        uint256 div;
    }

    uint256 public constant MIN_NAT_TO_ENTER = 1 ether;
    uint256 public constant MIN_TOKEN_SUPPLY_AFTER_EXIT = 1 ether;
    uint256 public constant MIN_NAT_BALANCE_AFTER_EXIT = 1 ether;

    address public agentVault;          // practically immutable because there is no setter
    IIAssetManager public assetManager; // practically immutable because there is no setter
    IFAsset public fAsset;              // practically immutable because there is no setter
    IICollateralPoolToken public token; // only changed once at deploy time

    IWNat public wNat;
    uint32 public exitCollateralRatioBIPS;

    uint32 private __topupCollateralRatioBIPS; // only storage placeholder
    uint16 private __topupTokenPriceFactorBIPS; // only storage placeholder

    bool private internalWithdrawal;
    bool private initialized;

    mapping(address => int256) private _fAssetFeeDebtOf;
    int256 public totalFAssetFeeDebt;
    uint256 public totalFAssetFees;
    uint256 public totalCollateral;

    modifier onlyAssetManager {
        _checkOnlyAssetManager();
        _;
    }

    modifier onlyAgent {
        _checkOnlyAgentVaultOwner();
        _;
    }

    modifier notEmergencyPaused {
        _checkEmergencyPauseNotActive();
        _;
    }

    // Only used in some tests.
    // The implementation in production will always be deployed with all zero addresses and parameters.
    constructor (
        address _agentVault,
        address _assetManager,
        address _fAsset,
        uint32 _exitCollateralRatioBIPS
    ) {
        initialize(_agentVault, _assetManager, _fAsset, _exitCollateralRatioBIPS);
    }

    function initialize(
        address _agentVault,
        address _assetManager,
        address _fAsset,
        uint32 _exitCollateralRatioBIPS
    )
        public
    {
        require(!initialized, AlreadyInitialized());
        initialized = true;
        // init vars
        agentVault = _agentVault;
        assetManager = IIAssetManager(_assetManager);
        fAsset = IFAsset(_fAsset);
        // for proxy implementation, assetManager will be 0
        wNat = address(assetManager) != address(0) ? assetManager.getWNat() : IWNat(address(0));
        exitCollateralRatioBIPS = _exitCollateralRatioBIPS;
        initializeReentrancyGuard();
    }

    receive() external payable {
        require(internalWithdrawal, OnlyInternalUse());
    }

    function setPoolToken(address _poolToken)
        external
        onlyAssetManager
    {
        require(address(token) == address(0), PoolTokenAlreadySet());
        token = IICollateralPoolToken(_poolToken);
    }

    /**
     * @notice Returns the collateral pool token contract used by this contract
     */
    function poolToken() external view returns (ICollateralPoolToken) {
        return token;
    }

    function setExitCollateralRatioBIPS(uint256 _exitCollateralRatioBIPS)
        external
        onlyAssetManager
    {
        exitCollateralRatioBIPS = _exitCollateralRatioBIPS.toUint32();
    }

    /**
     * @notice Enters the collateral pool by depositing some NAT
     */
    // slither-disable-next-line reentrancy-eth         // guarded by nonReentrant
    function enter()
        external payable
        notEmergencyPaused
        nonReentrant
        returns (uint256, uint256)
    {
        require(msg.value >= MIN_NAT_TO_ENTER, AmountOfNatTooLow());
        uint256 totalPoolTokens = token.totalSupply();
        if (totalPoolTokens == 0) {
            // this conditions are set for keeping a stable token value
            require(msg.value >= totalCollateral, AmountOfCollateralTooLow());
            AssetPrice memory assetPrice = _getAssetPrice();
            require(msg.value >= totalFAssetFees.mulDiv(assetPrice.mul, assetPrice.div), AmountOfCollateralTooLow());
        }
        // calculate obtained pool tokens and free f-assets
        uint256 tokenShare = _collateralToTokenShare(msg.value);
        require(tokenShare > 0, DepositResultsInZeroTokens());
        // calculate and create fee debt
        uint256 feeDebt = totalPoolTokens > 0 ? _totalVirtualFees().mulDiv(tokenShare, totalPoolTokens) : 0;
        _createFAssetFeeDebt(msg.sender, feeDebt);
        // deposit collateral
        _depositWNat();
        // mint pool tokens to the sender
        uint256 timelockExp = token.mint(msg.sender, tokenShare);
        // emit event
        emit CPEntered(msg.sender, msg.value, tokenShare, timelockExp);
        return (tokenShare, timelockExp);
    }

    /**
     * @notice Exits the pool by liquidating the given amount of pool tokens
     * @param _tokenShare   The amount of pool tokens to be liquidated
     *                      Must be positive and smaller or equal to the sender's token balance
     */
    // slither-disable-next-line reentrancy-eth         // guarded by nonReentrant
    function exit(uint256 _tokenShare)
        external
        notEmergencyPaused
        nonReentrant
        returns (uint256)
    {
        return _exitTo(_tokenShare, payable(msg.sender));
    }

    /**
     * @notice Exits the pool by liquidating the given amount of pool tokens
     * @param _tokenShare   The amount of pool tokens to be liquidated
     *                      Must be positive and smaller or equal to the sender's token balance
     * @param _recipient    The address to which NATs and FAsset fees will be transferred
     */
    // slither-disable-next-line reentrancy-eth         // guarded by nonReentrant
    function exitTo(uint256 _tokenShare, address payable _recipient)
        external
        notEmergencyPaused
        nonReentrant
        returns (uint256)
    {
        return _exitTo(_tokenShare, _recipient);
    }

    // slither-disable-next-line reentrancy-eth         // guarded by nonReentrant
    function _exitTo(uint256 _tokenShare, address payable _recipient)
        private
        returns (uint256)
    {
        require(_tokenShare > 0, TokenShareIsZero());
        require(_tokenShare <= token.balanceOf(msg.sender), TokenBalanceTooLow());
        _requireMinTokenSupplyAfterExit(_tokenShare);
        // token.totalSupply() >= token.balanceOf(msg.sender) >= _tokenShare > 0
        uint256 natShare = totalCollateral.mulDiv(_tokenShare, token.totalSupply());
        require(natShare > 0, SentAmountTooLow());
        _requireMinNatSupplyAfterExit(natShare);
        require(_staysAboveExitCR(natShare), CollateralRatioFallsBelowExitCR());
        // update the fasset fee debt
        uint256 debtFAssetFeeShare = _tokensToVirtualFeeShare(_tokenShare);
        _deleteFAssetFeeDebt(msg.sender, debtFAssetFeeShare);
        token.burn(msg.sender, _tokenShare, false);
        _withdrawWNatTo(_recipient, natShare);
        // emit event
        emit CPExited(msg.sender, _tokenShare, natShare);
        return natShare;
    }

    /**
     * @notice Exits the pool by liquidating the given amount of pool tokens and redeeming
     *  f-assets in a way that either preserves the pool collateral ratio or keeps it above exit CR
     * @param _tokenShare                   The amount of pool tokens to be liquidated
     *                                      Must be positive and smaller or equal to the sender's token balance
     * @param _redeemToCollateral           Specifies if redeemed f-assets should be exchanged to vault collateral
     *                                      by the agent
     * @param _redeemerUnderlyingAddress    Redeemer's address on the underlying chain
     * @param _executor                     The account that is allowed to execute redemption default
     * @notice F-assets will be redeemed in collateral if their value does not exceed one lot
     * @notice All f-asset fees will be redeemed along with potential additionally required f-assets taken
     *  from the sender's f-asset account
     */
    // slither-disable-next-line reentrancy-eth         // guarded by nonReentrant
    function selfCloseExit(
        uint256 _tokenShare,
        bool _redeemToCollateral,
        string memory _redeemerUnderlyingAddress,
        address payable _executor
    )
        external payable
        notEmergencyPaused
        nonReentrant
    {
        _selfCloseExitTo(_tokenShare, _redeemToCollateral, payable(msg.sender), _redeemerUnderlyingAddress, _executor);
    }

    /**
     * @notice Exits the pool by liquidating the given amount of pool tokens and redeeming
     *  f-assets in a way that either preserves the pool collateral ratio or keeps it above exit CR
     * @param _tokenShare                   The amount of pool tokens to be liquidated
     *                                      Must be positive and smaller or equal to the sender's token balance
     * @param _redeemToCollateral           Specifies if redeemed f-assets should be exchanged to vault collateral
     *                                      by the agent
     * @param _recipient                    The address to which NATs and FAsset fees will be transferred
     * @param _redeemerUnderlyingAddress    Redeemer's address on the underlying chain
     * @param _executor                     The account that is allowed to execute redemption default
     * @notice F-assets will be redeemed in collateral if their value does not exceed one lot
     * @notice All f-asset fees will be redeemed along with potential additionally required f-assets taken
     *  from the sender's f-asset account
     */
    // slither-disable-next-line reentrancy-eth         // guarded by nonReentrant
    function selfCloseExitTo(
        uint256 _tokenShare,
        bool _redeemToCollateral,
        address payable _recipient,
        string memory _redeemerUnderlyingAddress,
        address payable _executor
    )
        external payable
        notEmergencyPaused
        nonReentrant
    {
        require(_recipient != address(0) && _recipient != address(this) && _recipient != agentVault,
            InvalidRecipientAddress());
        _selfCloseExitTo(_tokenShare, _redeemToCollateral, _recipient, _redeemerUnderlyingAddress, _executor);
    }

    // slither-disable-next-line reentrancy-eth         // guarded by nonReentrant
    function _selfCloseExitTo(
        uint256 _tokenShare,
        bool _redeemToCollateral,
        address payable _recipient,
        string memory _redeemerUnderlyingAddress,
        address payable _executor
    )
        private
    {
        require(_tokenShare > 0, TokenShareIsZero());
        require(_tokenShare <= token.balanceOf(msg.sender), TokenBalanceTooLow());
        _requireMinTokenSupplyAfterExit(_tokenShare);
        // token.totalSupply() >= token.balanceOf(msg.sender) >= _tokenShare > 0
        uint256 natShare = totalCollateral.mulDiv(_tokenShare, token.totalSupply());
        require(natShare > 0, SentAmountTooLow());
        _requireMinNatSupplyAfterExit(natShare);
        uint256 maxAgentRedemption = assetManager.maxRedemptionFromAgent(agentVault);
        uint256 requiredFAssets = _getFAssetRequiredToNotSpoilCR(natShare);
        // Rare case: if agent has too many low-valued open tickets they can't redeem the requiredFAssets
        // in one transaction. In that case, we revert and the user should retry with lower amount.
        require(maxAgentRedemption >= requiredFAssets, RedemptionRequiresClosingTooManyTickets());
        // get owner f-asset fees to be spent (maximize fee withdrawal to cover the potentially necessary f-assets)
        uint256 debtFAssetFeeShare = _tokensToVirtualFeeShare(_tokenShare);
        // transfer the owner's fassets that will be redeemed
        require(fAsset.allowance(msg.sender, address(this)) >= requiredFAssets, FAssetAllowanceTooSmall());
        fAsset.safeTransferFrom(msg.sender, address(this), requiredFAssets);
        // redeem f-assets if necessary
        bool returnFunds = true;
        if (requiredFAssets > 0) {
            if (requiredFAssets < assetManager.lotSize() || _redeemToCollateral) {
                assetManager.redeemFromAgentInCollateral(agentVault, _recipient, requiredFAssets);
            } else {
                returnFunds = _executor == address(0);
                // pass `msg.value` to `redeemFromAgent` for the executor fee if `_executor` is set
                assetManager.redeemFromAgent{ value: returnFunds ? 0 : msg.value }(
                    agentVault, _recipient, requiredFAssets, _redeemerUnderlyingAddress, _executor);
            }
        }
        _deleteFAssetFeeDebt(msg.sender, debtFAssetFeeShare);
        token.burn(msg.sender, _tokenShare, false);
        _withdrawWNatTo(_recipient, natShare);
        if (returnFunds) {
            // return any NAT included by mistake to the recipient
            Transfers.transferNAT(_recipient, msg.value);
        }
        // emit event
        emit CPSelfCloseExited(msg.sender, _tokenShare, natShare, requiredFAssets);
    }

    /**
     * Get the amount of fassets that need to be burned to perform self close exit.
     */
    function fAssetRequiredForSelfCloseExit(uint256 _tokenAmountWei)
        external view
        returns (uint256)
    {
        uint256 tokenNatWeiEquiv = totalCollateral.mulDiv(_tokenAmountWei, token.totalSupply());
        return _getFAssetRequiredToNotSpoilCR(tokenNatWeiEquiv);
    }

    /**
     * @notice Collect f-asset fees by locking free tokens
     * @param _fAssets  The amount of f-asset fees to withdraw
     *                  Must be positive and smaller or equal to the sender's reward f-assets
     */
    function withdrawFees(uint256 _fAssets)
        external
        notEmergencyPaused
        nonReentrant
    {
        _withdrawFeesTo(_fAssets, msg.sender);
    }

    /**
     * @notice Collect f-asset fees by locking free tokens
     * @param _fAssets      The amount of f-asset fees to withdraw
     *                      Must be positive and smaller or equal to the sender's fAsset fees.
     * @param _recipient    The address to which FAsset fees will be transferred
     */
    function withdrawFeesTo(uint256 _fAssets, address _recipient)
        external
        notEmergencyPaused
        nonReentrant
    {
        _withdrawFeesTo(_fAssets, _recipient);
    }

    /**
     * @notice Collect f-asset fees by locking free tokens
     * @param _fAssets      The amount of f-asset fees to withdraw
     *                      Must be positive and smaller or equal to the sender's reward f-assets
     * @param _recipient    The address to which NATs and FAsset fees will be transferred
     */
    function _withdrawFeesTo(uint256 _fAssets, address _recipient)
        private
    {
        require(_fAssets > 0, WithdrawZeroFAsset());
        uint256 freeFAssetFeeShare = _fAssetFeesOf(msg.sender);
        require(_fAssets <= freeFAssetFeeShare, FreeFAssetBalanceTooSmall());
        _createFAssetFeeDebt(msg.sender, _fAssets);
        _transferFAssetTo(_recipient, _fAssets);
        // emit event
        emit CPFeesWithdrawn(msg.sender, _fAssets);
    }

    /**
     * @notice Free debt tokens by paying f-assets
     * @param _fAssets  Amount of payed f-assets
     *                  _fAssets must be positive and smaller or equal to the sender's debt f-assets
     */
    function payFAssetFeeDebt(uint256 _fAssets)
        external
        notEmergencyPaused
        nonReentrant
    {
        require(_fAssets != 0, ZeroFAssetDebtPayment());
        require(_fAssets.toInt256() <= _fAssetFeeDebtOf[msg.sender], PaymentLargerThanFeeDebt());
        require(fAsset.allowance(msg.sender, address(this)) >= _fAssets, FAssetAllowanceTooSmall());
        _deleteFAssetFeeDebt(msg.sender, _fAssets);
        _transferFAssetFrom(msg.sender, _fAssets);
        // emit event
        emit CPFeeDebtPaid(msg.sender, _fAssets);
    }

    // support for liquidation / redemption default payments
    // slither-disable-next-line reentrancy-eth         // guarded by nonReentrant
    function payout(
        address _recipient,
        uint256 _amount,
        uint256 _agentResponsibilityWei
    )
        external
        onlyAssetManager
        nonReentrant
    {
        // slash agent vault's pool tokens worth _agentResponsibilityWei in FLR (or less if there is not enough)
        uint256 agentTokenBalance = token.balanceOf(agentVault);
        uint256 maxSlashedTokens = totalCollateral > 0 ?
            token.totalSupply().mulDivRoundUp(_agentResponsibilityWei, totalCollateral) : agentTokenBalance;
        uint256 slashedTokens = Math.min(maxSlashedTokens, agentTokenBalance);
        if (slashedTokens > 0) {
            uint256 debtFAssetFeeShare = _tokensToVirtualFeeShare(slashedTokens);
            _deleteFAssetFeeDebt(agentVault, debtFAssetFeeShare);
            token.burn(agentVault, slashedTokens, true);
        }
        // transfer collateral to the recipient
        _transferWNatTo(_recipient, _amount);
        emit CPPaidOut(_recipient, _amount, slashedTokens);
    }

    function _collateralToTokenShare(
        uint256 _collateral
    )
        internal view
        returns (uint256)
    {
        uint256 totalPoolTokens = token.totalSupply();
        if (totalCollateral == 0 || totalPoolTokens == 0) { // pool is empty
            return _collateral;
        }
        return totalPoolTokens.mulDiv(_collateral, totalCollateral);
    }

    // _tokens is assumed to be smaller or equal to _account's token balance
    function _tokensToVirtualFeeShare(
        uint256 _tokens
    )
        internal view
        returns (uint256)
    {
        if (_tokens == 0) return 0;
        uint256 totalPoolTokens = token.totalSupply();
        assert(_tokens <= totalPoolTokens);
        // poolTokenSupply >= _tokens AND _tokens > 0 together imply poolTokenSupply != 0
        return _totalVirtualFees().mulDiv(_tokens, totalPoolTokens);
    }

    function _getFAssetRequiredToNotSpoilCR(
        uint256 _natShare
    )
        internal view
        returns (uint256)
    {
        // calculate f-assets required for CR to stay above max(exitCR, poolCR) when taking out _natShare
        // if pool is below exitCR, we shouldn't require it be increased above exitCR, only preserved
        // if pool is above exitCR, we require only for it to stay that way (like in the normal exit)
        AssetPrice memory assetPrice = _getAssetPrice();
        uint256 exitCR = _safeExitCR();
        uint256 backedFAssets = _agentBackedFAssets();
        uint256 resultWithoutRounding;
        if (_isAboveCR(assetPrice, backedFAssets, totalCollateral, exitCR)) {
            // f-asset required for CR to stay above exitCR (might not be needed)
            // solve (N - n) / (p / q (F - f)) >= cr get f = max(0, F - q (N - n) / (p cr))
            // assetPrice.mul > 0, exitCR > 1
            resultWithoutRounding = MathUtils.subOrZero(backedFAssets,
                assetPrice.div * (totalCollateral - _natShare) * SafePct.MAX_BIPS / (assetPrice.mul * exitCR));
        } else {
            // f-asset that preserves pool CR (assume poolNatBalance >= natShare > 0)
            // solve (N - n) / (F - f) = N / F get f = n F / N
            resultWithoutRounding = backedFAssets.mulDivRoundUp(_natShare, totalCollateral);
        }
        return MathUtils.roundUp(resultWithoutRounding, assetManager.assetMintingGranularityUBA());
    }

    function _staysAboveExitCR(
        uint256 _withdrawnNat
    )
        internal view
        returns (bool)
    {
        return _isAboveCR(_getAssetPrice(), _agentBackedFAssets(), totalCollateral - _withdrawnNat, _safeExitCR());
    }

    function _isAboveCR(
        AssetPrice memory _assetPrice,
        uint256 _backedFAssets,
        uint256 _poolCollateralNat,
        uint256 _crBIPS
    )
        internal pure
        returns (bool)
    {
        // check (N - n) / (F p / q) >= cr get (N - n) q >= F p cr
        return _poolCollateralNat * _assetPrice.div >= (_backedFAssets * _assetPrice.mul).mulBips(_crBIPS);
    }

    function _agentBackedFAssets()
        internal view
        returns (uint256)
    {
        return assetManager.getFAssetsBackedByPool(agentVault);
    }

    function _virtualFAssetFeesOf(
        address _account
    )
        internal view
        returns (uint256)
    {
        uint256 tokens = token.balanceOf(_account);
        return _tokensToVirtualFeeShare(tokens);
    }

    function _fAssetFeesOf(
        address _account
    )
        internal view
        returns (uint256)
    {
        int256 virtualFAssetFees = _virtualFAssetFeesOf(_account).toInt256();
        int256 accountFeeDebt = _fAssetFeeDebtOf[_account];
        int256 userFees = virtualFAssetFees - accountFeeDebt;
        // note: rounding errors can make debtFassets larger than virtualFassets by at most one
        // this can happen only when user has no free f-assets (that is why MathUtils.subOrZero)
        // note: rounding errors can make freeFassets larger than total pool f-asset fees by small amounts
        // (The reason for Math.min and Math.positivePart is to restrict to interval [0, poolFAssetFees])
        return Math.min(MathUtils.positivePart(userFees), totalFAssetFees);
    }

    function _debtFreeTokensOf(
        address _account
    )
        internal view
        returns (uint256)
    {
        int256 accountFeeDebt = _fAssetFeeDebtOf[_account];
        if (accountFeeDebt <= 0) {
            // with no debt, all tokens are free
            // this avoids the case where freeFassets == poolVirtualFAssetFees == 0
            return token.balanceOf(_account);
        }
        uint256 virtualFassets = _virtualFAssetFeesOf(_account);
        assert(virtualFassets <= _totalVirtualFees());
        uint256 freeFassets = MathUtils.positivePart(virtualFassets.toInt256() - accountFeeDebt);
        if (freeFassets == 0) return 0;
        // nonzero divisor: _totalVirtualFees() >= virtualFassets >= freeFassets > 0
        return token.totalSupply().mulDiv(freeFassets, _totalVirtualFees());
    }

    function _getAssetPrice()
        internal view
        returns (AssetPrice memory)
    {
        (uint256 assetPriceMul, uint256 assetPriceDiv) = assetManager.assetPriceNatWei();
        return AssetPrice({
            mul: assetPriceMul,
            div: assetPriceDiv
        });
    }

    function _totalVirtualFees()
        internal view
        returns (uint256)
    {
        int256 virtualFees = totalFAssetFees.toInt256() + totalFAssetFeeDebt;
        // Invariant: virtualFees >= 0 always (otherwise the following line will revert).
        // Proof: the places where `totalFAssetFees` and `totalFAssetFeeDebt` change are: `enter`,
        // `exit`/`selfCloseExit`, `withdrawFees` and `payFAssetFeeDebt`.
        // In `withdrawFees` and `payFAssetFeeDebt`, amounts of `totalFAssetFees` and `totalFAssetFeeDebt`
        // change with opposite sign, so virtualFees is unchanged.
        // In `enter`, the `totalFAssetFeeDebt` increases and the other is unchanged, so virtualFees increases.
        // Thus the only place where `totalFAssetFeeDebt` and thus virtualFees decreases is in`exit`/`selfCloseExit`.
        // The decrease there is by `_tokensToVirtualFeeShare()`, which is virtualFees times a factor
        // `tokenShare/totalTokens`, which is checked to be at most 1.
        return virtualFees.toUint256();
    }

    // if governance changes `minPoolCollateralRatioBIPS` it can be higher than `exitCollateralRatioBIPS`
    function _safeExitCR()
        internal view
        returns (uint256)
    {
        uint256 minPoolCollateralRatioBIPS = assetManager.getAgentMinPoolCollateralRatioBIPS(agentVault);
        return Math.max(minPoolCollateralRatioBIPS, exitCollateralRatioBIPS);
    }

    function _requireMinTokenSupplyAfterExit(
        uint256 _tokenShare
    )
        internal view
    {
        uint256 totalPoolTokens = token.totalSupply();
        require(totalPoolTokens == _tokenShare || totalPoolTokens - _tokenShare >= MIN_TOKEN_SUPPLY_AFTER_EXIT,
            TokenSupplyAfterExitTooLow());
    }

    function _requireMinNatSupplyAfterExit(
        uint256 _natShare
    )
        internal view
    {
        require(totalCollateral == _natShare || totalCollateral - _natShare >= MIN_NAT_BALANCE_AFTER_EXIT,
            CollateralAfterExitTooLow());
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // tracking wNat collateral and f-asset fees

    function depositNat()
        external payable
        onlyAssetManager
        nonReentrant
    {
        _depositWNat();
    }

    // this is needed to track asset manager's minting fee deposit
    function fAssetFeeDeposited(
        uint256 _amount
    )
        external
        onlyAssetManager
    {
        totalFAssetFees += _amount;
    }

    function _createFAssetFeeDebt(address _account, uint256 _fAssets)
        internal
    {
        if (_fAssets == 0) return;
        int256 fAssets = _fAssets.toInt256();
        _fAssetFeeDebtOf[_account] += fAssets;
        totalFAssetFeeDebt += fAssets;
        emit CPFeeDebtChanged(_account, _fAssetFeeDebtOf[_account]);
    }

    // _fAssets should be smaller or equal to _account's f-asset debt
    function _deleteFAssetFeeDebt(address _account, uint256 _fAssets)
        internal
    {
        if (_fAssets == 0) return;
        int256 fAssets = _fAssets.toInt256();
        _fAssetFeeDebtOf[_account] -= fAssets;
        totalFAssetFeeDebt -= fAssets;
        emit CPFeeDebtChanged(_account, _fAssetFeeDebtOf[_account]);
    }

    function _transferFAssetFrom(
        address _from,
        uint256 _amount
    )
        internal
    {
        if (_amount > 0) {
            totalFAssetFees += _amount;
            fAsset.safeTransferFrom(_from, address(this), _amount);
        }
    }

    function _transferFAssetTo(
        address _to,
        uint256 _amount
    )
        internal
    {
        if (_amount > 0) {
            totalFAssetFees -= _amount;
            fAsset.safeTransfer(_to, _amount);
        }
    }

    function _transferWNatTo(
        address _to,
        uint256 _amount
    )
        internal
    {
        if (_amount > 0) {
            totalCollateral -= _amount;
            wNat.safeTransfer(_to, _amount);
        }
    }

    function _withdrawWNatTo(
        address payable _recipient,
        uint256 _amount
    )
        internal
    {
        if (_amount > 0) {
            totalCollateral -= _amount;
            internalWithdrawal = true;
            wNat.withdraw(_amount);
            internalWithdrawal = false;
            Transfers.transferNAT(_recipient, _amount);
        }
    }

    function _depositWNat()
        internal
    {
        // msg.value is always > 0 in this contract
        if (msg.value > 0) {
            totalCollateral += msg.value;
            wNat.deposit{value: msg.value}();
            assetManager.updateCollateral(agentVault, wNat);
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // methods for viewing user balances

    /**
     * @notice Returns the sum of the user's reward f-assets and their corresponding f-asset debt
     * @param _account  User address
     */
    function virtualFAssetOf(address _account)
        external view
        returns (uint256)
    {
        return _virtualFAssetFeesOf(_account);
    }

    /**
     * @notice Returns user's reward f-assets
     * @param _account  User address
     */
    function fAssetFeesOf(address _account)
        external view
        returns (uint256)
    {
        return _fAssetFeesOf(_account);
    }

    /**
     * @notice Returns user's f-asset debt
     * @param _account  User address
     */
    function fAssetFeeDebtOf(address _account)
        external view
        returns (int256)
    {
        return _fAssetFeeDebtOf[_account];
    }

    /**
     * @notice Returns user's debt tokens
     * @param _account  User address
     */
    function debtLockedTokensOf(address _account)
        external view
        returns (uint256)
    {
        return MathUtils.subOrZero(token.balanceOf(_account), _debtFreeTokensOf(_account));
    }

    /**
     * @notice Returns user's free tokens
     * @param _account  User address
     */
    function debtFreeTokensOf(address _account)
        external view
        returns (uint256)
    {
        return _debtFreeTokensOf(_account);
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // Methods to allow for management and destruction of the pool

    function destroy(address payable _recipient)
        external
        onlyAssetManager
        nonReentrant
    {
        require(token.totalSupply() == 0, CannotDestroyPoolWithIssuedTokens());
        // transfer native balance as WNat, if any
        Transfers.depositWNat(wNat, _recipient, address(this).balance);
        // transfer untracked f-assets and wNat, if any
        uint256 untrackedWNat = wNat.balanceOf(address(this));
        uint256 untrackedFAsset = fAsset.balanceOf(address(this));
        if (untrackedWNat > 0) {
            wNat.safeTransfer(_recipient, untrackedWNat);
        }
        if (untrackedFAsset > 0) {
            fAsset.safeTransfer(_recipient, untrackedFAsset);
        }
    }

    // slither-disable-next-line reentrancy-eth         // guarded by nonReentrant
    function upgradeWNatContract(IWNat _newWNat)
        external
        onlyAssetManager
        nonReentrant
    {
        if (_newWNat == wNat) return;
        // transfer all funds to new WNat
        uint256 balance = wNat.balanceOf(address(this));
        internalWithdrawal = true;
        wNat.withdraw(balance);
        internalWithdrawal = false;
        _newWNat.deposit{value: balance}();
        // set new WNat contract
        wNat = _newWNat;
        assetManager.updateCollateral(agentVault, wNat);
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // Delegation of the pool's collateral and airdrop claiming (same as in AgentVault)

    function delegate(address _to, uint256 _bips)
        external
        notEmergencyPaused
        onlyAgent
    {
        wNat.delegate(_to, _bips);
    }

    function undelegateAll()
        external
        notEmergencyPaused
        onlyAgent
    {
        wNat.undelegateAll();
    }

    function delegateGovernance(address _to)
        external
        notEmergencyPaused
        onlyAgent
    {
        wNat.governanceVotePower().delegate(_to);
    }

    function undelegateGovernance()
        external
        notEmergencyPaused
        onlyAgent
    {
        wNat.governanceVotePower().undelegate();
    }

    function claimDelegationRewards(
        IRewardManager _rewardManager,
        uint24 _lastRewardEpoch,
        IRewardManager.RewardClaimWithProof[] calldata _proofs
    )
        external
        notEmergencyPaused
        onlyAgent
        nonReentrant
        returns (uint256)
    {
        uint256 balanceBefore = wNat.balanceOf(address(this));
        _rewardManager.claim(address(this), payable(address(this)), _lastRewardEpoch, true, _proofs);
        uint256 balanceAfter = wNat.balanceOf(address(this));
        uint256 claimed = balanceAfter - balanceBefore;
        totalCollateral += claimed;
        assetManager.updateCollateral(agentVault, wNat);
        emit CPClaimedReward(claimed, 1);
        return claimed;
    }

    function claimAirdropDistribution(
        IDistributionToDelegators _distribution,
        uint256 _month
    )
        external
        notEmergencyPaused
        onlyAgent
        nonReentrant
        returns(uint256)
    {
        uint256 balanceBefore = wNat.balanceOf(address(this));
        _distribution.claim(address(this), payable(address(this)), _month, true);
        uint256 balanceAfter = wNat.balanceOf(address(this));
        uint256 claimed = balanceAfter - balanceBefore;
        totalCollateral += claimed;
        assetManager.updateCollateral(agentVault, wNat);
        emit CPClaimedReward(claimed, 0);
        return claimed;
    }

    function optOutOfAirdrop(
        IDistributionToDelegators _distribution
    )
        external
        notEmergencyPaused
        onlyAgent
        nonReentrant
    {
        _distribution.optOutOfAirdrop();
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // UUPS proxy upgrade

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /**
     * Upgrade calls can only arrive through asset manager.
     * See UUPSUpgradeable._authorizeUpgrade.
     */
    function _authorizeUpgrade(address /* _newImplementation */)
        internal virtual override
        onlyAssetManager
    { // solhint-disable-line no-empty-blocks
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // ERC-165

    /**
     * Implementation of ERC-165 interface.
     */
    function supportsInterface(bytes4 _interfaceId)
        external pure override
        returns (bool)
    {
        return _interfaceId == type(IERC165).interfaceId
            || _interfaceId == type(ICollateralPool).interfaceId
            || _interfaceId == type(IICollateralPool).interfaceId;
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // modifier implementation methods

    function _checkOnlyAssetManager() private view {
        require(msg.sender == address(assetManager), OnlyAssetManager());
    }

    function _checkOnlyAgentVaultOwner() private view {
        require(assetManager.isAgentVaultOwner(agentVault, msg.sender), OnlyAgent());
    }

    function _checkEmergencyPauseNotActive() private view {
        require(assetManager.emergencyPauseLevel() < EmergencyPause.Level.START_OPERATIONS, EmergencyPauseActive());
    }
}
