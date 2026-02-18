// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "../interfaces/IWithdrawRequestManager.sol";
import {Initializable} from "../proxy/Initializable.sol";
import {ClonedCoolDownHolder} from "./ClonedCoolDownHolder.sol";
import {
    Unauthorized,
    ExistingWithdrawRequest,
    NoWithdrawRequest,
    InvalidWithdrawRequestTokenization
} from "../interfaces/Errors.sol";
import {TypeConvert} from "../utils/TypeConvert.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {ADDRESS_REGISTRY, DEFAULT_PRECISION} from "../utils/Constants.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Trade, TradeType, TRADING_MODULE, nProxy, TradeFailed} from "../interfaces/ITradingModule.sol";


/**
 * Library to handle potentially illiquid withdraw requests of staking tokens where there
 * is some indeterminate lock up time before tokens can be redeemed. Examples would be withdraws
 * of staked or restaked ETH, tokens like sUSDe or stkAave which have cooldown periods before they
 * can be withdrawn.
 *
 * Primarily, this library tracks the withdraw request and an associated identifier for the withdraw
 * request. It also allows for the withdraw request to be "tokenized" so that shares of the withdraw
 * request can be liquidated.
 */
abstract contract AbstractWithdrawRequestManager is IWithdrawRequestManager, Initializable {
    using SafeERC20 for ERC20;
    using TypeConvert for uint256;

    /// @inheritdoc IWithdrawRequestManager
    address public immutable override YIELD_TOKEN;
    /// @inheritdoc IWithdrawRequestManager
    address public immutable override WITHDRAW_TOKEN;
    /// @inheritdoc IWithdrawRequestManager
    address public immutable override STAKING_TOKEN;

    mapping(address => bool) public override isApprovedVault;
    mapping(address vault => mapping(address account => WithdrawRequest)) private s_accountWithdrawRequest;
    mapping(uint256 requestId => TokenizedWithdrawRequest) private s_tokenizedWithdrawRequest;

    constructor(address _withdrawToken, address _yieldToken, address _stakingToken) Initializable() {
        WITHDRAW_TOKEN = _withdrawToken;
        YIELD_TOKEN = _yieldToken;
        STAKING_TOKEN = _stakingToken;
    }

    modifier onlyOwner() {
        if (msg.sender != ADDRESS_REGISTRY.upgradeAdmin()) revert Unauthorized(msg.sender);
        _;
    }

    /// @dev Ensures that only approved vaults can initiate withdraw requests.
    modifier onlyApprovedVault() {
        if (!isApprovedVault[msg.sender]) revert Unauthorized(msg.sender);
        _;
    }

    /// @inheritdoc IWithdrawRequestManager
    function getWithdrawRequest(address vault, address account) public view override
        returns (WithdrawRequest memory w, TokenizedWithdrawRequest memory s) {
        w = s_accountWithdrawRequest[vault][account];
        s = s_tokenizedWithdrawRequest[w.requestId];
    }

    /// @inheritdoc IWithdrawRequestManager
    function isPendingWithdrawRequest(address vault, address account) public view override returns (bool) {
        return s_accountWithdrawRequest[vault][account].requestId != 0;
    }

    /// @inheritdoc IWithdrawRequestManager
    function setApprovedVault(address vault, bool isApproved) external override onlyOwner {
        isApprovedVault[vault] = isApproved;
        emit ApprovedVault(vault, isApproved);
    }

    /// @inheritdoc IWithdrawRequestManager
    function stakeTokens(
        address depositToken,
        uint256 amount,
        bytes calldata data
    ) external override onlyApprovedVault returns (uint256 yieldTokensMinted) {
        uint256 initialYieldTokenBalance = ERC20(YIELD_TOKEN).balanceOf(address(this));
        ERC20(depositToken).safeTransferFrom(msg.sender, address(this), amount);
        (uint256 stakeTokenAmount, bytes memory stakeData) = _preStakingTrade(depositToken, amount, data);
        _stakeTokens(stakeTokenAmount, stakeData);

        yieldTokensMinted = ERC20(YIELD_TOKEN).balanceOf(address(this)) - initialYieldTokenBalance;
        ERC20(YIELD_TOKEN).safeTransfer(msg.sender, yieldTokensMinted);
    }

    /// @inheritdoc IWithdrawRequestManager
    function initiateWithdraw(
        address account,
        uint256 yieldTokenAmount,
        uint256 sharesAmount,
        bytes calldata data
    ) external override onlyApprovedVault returns (uint256 requestId) {
        WithdrawRequest storage accountWithdraw = s_accountWithdrawRequest[msg.sender][account];
        if (accountWithdraw.requestId != 0) revert ExistingWithdrawRequest(msg.sender, account, accountWithdraw.requestId);

        // Receive the requested amount of yield tokens from the approved vault.
        ERC20(YIELD_TOKEN).safeTransferFrom(msg.sender, address(this), yieldTokenAmount);

        requestId = _initiateWithdrawImpl(account, yieldTokenAmount, data);
        accountWithdraw.requestId = requestId;
        accountWithdraw.yieldTokenAmount = yieldTokenAmount.toUint120();
        accountWithdraw.sharesAmount = sharesAmount.toUint120();
        s_tokenizedWithdrawRequest[requestId] = TokenizedWithdrawRequest({
            totalYieldTokenAmount: yieldTokenAmount.toUint120(),
            totalWithdraw: 0,
            finalized: false
        });

        emit InitiateWithdrawRequest(account, msg.sender, yieldTokenAmount, sharesAmount, requestId);
    }

    /// @inheritdoc IWithdrawRequestManager
    function finalizeAndRedeemWithdrawRequest(
        address account,
        uint256 withdrawYieldTokenAmount,
        uint256 sharesToBurn
    ) external override onlyApprovedVault returns (uint256 tokensWithdrawn, bool finalized) {
        WithdrawRequest storage s_withdraw = s_accountWithdrawRequest[msg.sender][account];
        if (s_withdraw.requestId == 0) return (0, false);

        (tokensWithdrawn, finalized) = _finalizeWithdraw(account, s_withdraw);

        if (finalized) {
            // Allows for partial withdrawal of yield tokens
            if (withdrawYieldTokenAmount < s_withdraw.yieldTokenAmount) {
                tokensWithdrawn = tokensWithdrawn * withdrawYieldTokenAmount / s_withdraw.yieldTokenAmount;
                s_withdraw.sharesAmount -= sharesToBurn.toUint120();
                s_withdraw.yieldTokenAmount -= withdrawYieldTokenAmount.toUint120();
            } else {
                require(s_withdraw.yieldTokenAmount == withdrawYieldTokenAmount);
                delete s_accountWithdrawRequest[msg.sender][account];
            }

            ERC20(WITHDRAW_TOKEN).safeTransfer(msg.sender, tokensWithdrawn);
        }
    }

    /// @inheritdoc IWithdrawRequestManager
    function finalizeRequestManual(
        address vault,
        address account
    ) external override returns (uint256 tokensWithdrawn, bool finalized) {
        WithdrawRequest storage s_withdraw = s_accountWithdrawRequest[vault][account];
        if (s_withdraw.requestId == 0) revert NoWithdrawRequest(vault, account);

        // Do not transfer any tokens off of this method here. Withdrawn tokens will be held in the
        // tokenized withdraw request until the vault calls this contract to withdraw the tokens.
        (tokensWithdrawn, finalized) = _finalizeWithdraw(account, s_withdraw);
    }

    /// @inheritdoc IWithdrawRequestManager
    function tokenizeWithdrawRequest(
        address _from,
        address _to,
        uint256 sharesAmount
    ) external override onlyApprovedVault returns (bool didTokenize) {
        if (_from == _to) revert();

        WithdrawRequest storage s_withdraw = s_accountWithdrawRequest[msg.sender][_from];
        uint256 requestId = s_withdraw.requestId;
        if (requestId == 0 || sharesAmount == 0) return false;

        // Ensure that no withdraw request gets overridden, the _to account always receives their withdraw
        // request in the account withdraw slot. All storage is updated prior to changes to the `w` storage
        // variable below.
        WithdrawRequest storage toWithdraw = s_accountWithdrawRequest[msg.sender][_to];
        if (toWithdraw.requestId != 0 && toWithdraw.requestId != requestId) {
            revert ExistingWithdrawRequest(msg.sender, _to, toWithdraw.requestId);
        }

        toWithdraw.requestId = requestId;

        if (s_withdraw.sharesAmount < sharesAmount) {
            // This should never occur given the checks below.
            revert InvalidWithdrawRequestTokenization();
        } else if (s_withdraw.sharesAmount == sharesAmount) {
            // If the resulting vault shares is zero, then delete the request. The _from account's
            // withdraw request is fully transferred to _to. In this case, the _to account receives
            // the full amount of the _from account's withdraw request.
            toWithdraw.yieldTokenAmount = toWithdraw.yieldTokenAmount + s_withdraw.yieldTokenAmount;
            toWithdraw.sharesAmount = toWithdraw.sharesAmount + s_withdraw.sharesAmount;
            delete s_accountWithdrawRequest[msg.sender][_from];
        } else {
            // In this case, the amount of yield tokens is transferred from one account to the other.
            uint256 yieldTokenAmount = s_withdraw.yieldTokenAmount * sharesAmount / s_withdraw.sharesAmount;
            toWithdraw.yieldTokenAmount = (toWithdraw.yieldTokenAmount + yieldTokenAmount).toUint120();
            toWithdraw.sharesAmount = (toWithdraw.sharesAmount + sharesAmount).toUint120();
            s_withdraw.yieldTokenAmount = (s_withdraw.yieldTokenAmount - yieldTokenAmount).toUint120();
            s_withdraw.sharesAmount = (s_withdraw.sharesAmount - sharesAmount).toUint120();
        }

        emit WithdrawRequestTokenized(_from, _to, requestId, sharesAmount);
        return true;
    }

    /// @inheritdoc IWithdrawRequestManager
    function rescueTokens(
        address cooldownHolder, address token, address receiver, uint256 amount
    ) external override onlyOwner {
        ClonedCoolDownHolder(cooldownHolder).rescueTokens(ERC20(token), receiver, amount);
    }

    /// @notice Finalizes a withdraw request and updates the account required to determine how many
    /// tokens the account has a claim over.
    function _finalizeWithdraw(
        address account,
        WithdrawRequest memory w
    ) internal returns (uint256 tokensWithdrawn, bool finalized) {
        TokenizedWithdrawRequest storage s = s_tokenizedWithdrawRequest[w.requestId];

        // If the tokenized request was already finalized in a different transaction
        // then return the values here and we can short circuit the withdraw impl
        if (s.finalized) {
            return (
                uint256(s.totalWithdraw) * uint256(w.yieldTokenAmount) / uint256(s.totalYieldTokenAmount),
                true
            );
        }

        // These values are the total tokens claimed from the withdraw request, does not
        // account for potential tokenization.
        (tokensWithdrawn, finalized) = _finalizeWithdrawImpl(account, w.requestId);

        if (finalized) {
            s.totalWithdraw = tokensWithdrawn.toUint120();
            // Safety check to ensure that we do not override a finalized tokenized withdraw request
            require(s.finalized == false);
            s.finalized = true;

            tokensWithdrawn = uint256(s.totalWithdraw) * uint256(w.yieldTokenAmount) / uint256(s.totalYieldTokenAmount);
        } else {
            // No tokens claimed if not finalized
            require(tokensWithdrawn == 0);
        }
    }


    /// @notice Required implementation to begin the withdraw request
    /// @return requestId some identifier of the withdraw request
    function _initiateWithdrawImpl(
        address account,
        uint256 yieldTokenAmount,
        bytes calldata data
    ) internal virtual returns (uint256 requestId);

    /// @notice Required implementation to finalize the withdraw
    /// @return tokensWithdrawn total tokens claimed as a result of the withdraw, does not
    /// necessarily represent the tokens that go to the account if the request has been
    /// tokenized due to liquidation
    /// @return finalized returns true if the withdraw has been finalized
    function _finalizeWithdrawImpl(address account, uint256 requestId) internal virtual returns (uint256 tokensWithdrawn, bool finalized);

    /// @notice Required implementation to stake the deposit token to the yield token
    function _stakeTokens(uint256 amount, bytes memory stakeData) internal virtual;

    /// @dev Allows for the deposit token to be traded into the staking token prior to staking, i.e.
    /// enables USDC to USDe trades before staking into sUSDe.
    function _preStakingTrade(address depositToken, uint256 depositAmount, bytes calldata data) internal returns (uint256 amountBought, bytes memory stakeData) {
        if (depositToken == STAKING_TOKEN) {
            amountBought = depositAmount;
            stakeData = data;
        } else {
            StakingTradeParams memory params = abi.decode(data, (StakingTradeParams));
            stakeData = params.stakeData;

            (/* */, amountBought) = _executeTrade(Trade({
                tradeType: params.tradeType,
                sellToken: depositToken,
                buyToken: STAKING_TOKEN,
                amount: depositAmount,
                exchangeData: params.exchangeData,
                limit: params.minPurchaseAmount,
                deadline: block.timestamp
            }), params.dexId);
        }
    }

    function _executeTrade(
        Trade memory trade,
        uint16 dexId
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        (bool success, bytes memory result) = nProxy(payable(address(TRADING_MODULE))).getImplementation()
            .delegatecall(abi.encodeWithSelector(TRADING_MODULE.executeTrade.selector, dexId, trade));
        if (!success) {
            assembly {
                // Copy the return data to memory
                returndatacopy(0, 0, returndatasize())
                // Revert with the return data
                revert(0, returndatasize())
            }
        }

        (amountSold, amountBought) = abi.decode(result, (uint256, uint256));
    }

    /// @inheritdoc IWithdrawRequestManager
    function getWithdrawRequestValue(
        address vault,
        address account,
        address asset,
        uint256 shares
    ) external view override returns (bool hasRequest, uint256 valueInAsset) {
        WithdrawRequest memory w = s_accountWithdrawRequest[vault][account];
        if (w.requestId == 0) return (false, 0);

        TokenizedWithdrawRequest memory s = s_tokenizedWithdrawRequest[w.requestId];

        int256 tokenRate;
        uint256 tokenAmount;
        uint256 tokenDecimals;
        uint256 assetDecimals = TokenUtils.getDecimals(asset);
        if (s.finalized) {
            // If finalized the withdraw request is locked to the tokens withdrawn
            (tokenRate, /* */) = TRADING_MODULE.getOraclePrice(WITHDRAW_TOKEN, asset);
            tokenDecimals = TokenUtils.getDecimals(WITHDRAW_TOKEN);
            tokenAmount = (uint256(w.yieldTokenAmount) * uint256(s.totalWithdraw)) / uint256(s.totalYieldTokenAmount);
        } else {
            // Otherwise we use the yield token rate
            (tokenRate, /* */) = TRADING_MODULE.getOraclePrice(YIELD_TOKEN, asset);
            tokenDecimals = TokenUtils.getDecimals(YIELD_TOKEN);
            tokenAmount = w.yieldTokenAmount;
        }

        // The trading module always returns a positive rate in 18 decimals so we can safely
        // cast to uint256
        uint256 totalValue = (uint256(tokenRate) * tokenAmount * (10 ** assetDecimals)) /
            ((10 ** tokenDecimals) * DEFAULT_PRECISION);
        // NOTE: returns the normalized value given the shares input
        return (true, totalValue * shares / w.sharesAmount);
    }

}