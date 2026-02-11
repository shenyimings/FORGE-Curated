// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

// Internal imports
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {IBeaconProxyFactory} from "src/interfaces/IBeaconProxyFactory.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {FeeManager} from "src/FeeManager.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";
import {LeverageToken} from "src/LeverageToken.sol";
import {
    ActionData,
    ActionType,
    ExternalAction,
    LeverageTokenConfig,
    BaseLeverageTokenConfig,
    RebalanceAction,
    TokenTransfer
} from "src/types/DataTypes.sol";

/**
 * @dev The LeverageManager contract is an upgradeable core contract that is responsible for managing the creation of LeverageTokens.
 * It also acts as an entry point for users to deposit and withdraw equity from the position held by the LeverageToken, and for
 * rebalancers to rebalance LeverageTokens.
 *
 * LeverageTokens are ERC20 tokens that are akin to shares in an ERC-4626 vault - they represent a claim on the equity held by
 * the LeverageToken. They can be created on this contract by calling `createNewLeverageToken`, and their configuration on the
 * LeverageManager is immutable.
 * Note: Although the LeverageToken configuration saved on the LeverageManager is immutable, the configured LendingAdapter and
 *       RebalanceAdapter for the LeverageToken may be upgradeable contracts.
 *
 * The LeverageManager also inherits the `FeeManager` contract, which is used to manage LeverageToken fees (which accrue to
 * the share value of the LeverageToken) and the treasury fees.
 *
 * For deposits of equity into a LeverageToken, the collateral and debt required is calculated by using the LeverageToken's
 * current collateral ratio. As such, the collateral ratio after a deposit must be equal to the collateral ratio before a
 * deposit, within some rounding error.
 *
 * [CAUTION]
 * ====
 * LeverageTokens are susceptible to inflation attacks like ERC-4626 vaults:
 *   "In empty (or nearly empty) ERC-4626 vaults, deposits are at high risk of being stolen through frontrunning
 *   with a "donation" to the vault that inflates the price of a share. This is variously known as a donation or inflation
 *   attack and is essentially a problem of slippage. Vault deployers can protect against this attack by making an initial
 *   deposit of a non-trivial amount of the asset, such that price manipulation becomes infeasible. Withdrawals may
 *   similarly be affected by slippage. Users can protect against this attack as well as unexpected slippage in general by
 *   verifying the amount received is as expected, using a wrapper that performs these checks such as
 *   https://github.com/fei-protocol/ERC4626#erc4626router-and-base[ERC4626Router]."
 *
 * As such it is highly recommended that LeverageToken creators make an initial deposit of a non-trivial amount of equity.
 * It is also recommended to use a router that performs slippage checks when depositing and withdrawing.
 */
contract LeverageManager is ILeverageManager, AccessControlUpgradeable, FeeManager, UUPSUpgradeable {
    // Base collateral ratio constant, 1e18 means that collateral / debt ratio is 1:1
    uint256 public constant BASE_RATIO = 1e18;
    uint256 public constant DECIMALS_OFFSET = 0;
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @dev Struct containing all state for the LeverageManager contract
    /// @custom:storage-location erc7201:seamless.contracts.storage.LeverageManager
    struct LeverageManagerStorage {
        /// @dev Factory for deploying new LeverageTokens
        IBeaconProxyFactory tokenFactory;
        /// @dev LeverageToken address => Base config for LeverageToken
        mapping(ILeverageToken token => BaseLeverageTokenConfig) config;
    }

    function _getLeverageManagerStorage() internal pure returns (LeverageManagerStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.LeverageManager")) - 1)) & ~bytes32(uint256(0xff));
            $.slot := 0x326e20d598a681eb69bc11b5176604d340fccf9864170f09484f3c317edf3600
        }
    }

    function initialize(address initialAdmin, IBeaconProxyFactory leverageTokenFactory) external initializer {
        __FeeManager_init(initialAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _getLeverageManagerStorage().tokenFactory = leverageTokenFactory;
        emit LeverageManagerInitialized(leverageTokenFactory);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /// @inheritdoc ILeverageManager
    function getLeverageTokenFactory() public view returns (IBeaconProxyFactory factory) {
        return _getLeverageManagerStorage().tokenFactory;
    }

    /// @inheritdoc ILeverageManager
    function getLeverageTokenCollateralAsset(ILeverageToken token) public view returns (IERC20 collateralAsset) {
        return getLeverageTokenLendingAdapter(token).getCollateralAsset();
    }

    /// @inheritdoc ILeverageManager
    function getLeverageTokenDebtAsset(ILeverageToken token) public view returns (IERC20 debtAsset) {
        return getLeverageTokenLendingAdapter(token).getDebtAsset();
    }

    /// @inheritdoc ILeverageManager
    function getLeverageTokenRebalanceAdapter(ILeverageToken token)
        public
        view
        returns (IRebalanceAdapterBase module)
    {
        return _getLeverageManagerStorage().config[token].rebalanceAdapter;
    }

    /// @inheritdoc ILeverageManager
    function getLeverageTokenConfig(ILeverageToken token) external view returns (LeverageTokenConfig memory config) {
        BaseLeverageTokenConfig memory baseConfig = _getLeverageManagerStorage().config[token];
        uint256 depositTokenFee = getLeverageTokenActionFee(token, ExternalAction.Deposit);
        uint256 withdrawTokenFee = getLeverageTokenActionFee(token, ExternalAction.Withdraw);

        return LeverageTokenConfig({
            lendingAdapter: baseConfig.lendingAdapter,
            rebalanceAdapter: baseConfig.rebalanceAdapter,
            depositTokenFee: depositTokenFee,
            withdrawTokenFee: withdrawTokenFee
        });
    }

    /// @inheritdoc ILeverageManager
    function getLeverageTokenLendingAdapter(ILeverageToken token) public view returns (ILendingAdapter adapter) {
        return _getLeverageManagerStorage().config[token].lendingAdapter;
    }

    /// @inheritdoc ILeverageManager
    function getLeverageTokenInitialCollateralRatio(ILeverageToken token) public view returns (uint256 ratio) {
        return getLeverageTokenRebalanceAdapter(token).getLeverageTokenInitialCollateralRatio(token);
    }

    /// @inheritdoc ILeverageManager
    function getLeverageTokenState(ILeverageToken token) public view returns (LeverageTokenState memory state) {
        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(token);

        uint256 collateral = lendingAdapter.getCollateralInDebtAsset();
        uint256 debt = lendingAdapter.getDebt();
        uint256 equity = lendingAdapter.getEquityInDebtAsset();

        uint256 collateralRatio =
            debt > 0 ? Math.mulDiv(collateral, BASE_RATIO, debt, Math.Rounding.Floor) : type(uint256).max;

        return LeverageTokenState({
            collateralInDebtAsset: collateral,
            debt: debt,
            equity: equity,
            collateralRatio: collateralRatio
        });
    }

    /// @inheritdoc ILeverageManager
    function createNewLeverageToken(LeverageTokenConfig calldata tokenConfig, string memory name, string memory symbol)
        external
        returns (ILeverageToken token)
    {
        IBeaconProxyFactory tokenFactory = getLeverageTokenFactory();

        // slither-disable-next-line reentrancy-events
        token = ILeverageToken(
            tokenFactory.createProxy(
                abi.encodeWithSelector(LeverageToken.initialize.selector, address(this), name, symbol),
                bytes32(tokenFactory.numProxies())
            )
        );

        _getLeverageManagerStorage().config[token] = BaseLeverageTokenConfig({
            lendingAdapter: tokenConfig.lendingAdapter,
            rebalanceAdapter: tokenConfig.rebalanceAdapter
        });
        _setLeverageTokenActionFee(token, ExternalAction.Deposit, tokenConfig.depositTokenFee);
        _setLeverageTokenActionFee(token, ExternalAction.Withdraw, tokenConfig.withdrawTokenFee);

        tokenConfig.lendingAdapter.postLeverageTokenCreation(msg.sender, address(token));
        tokenConfig.rebalanceAdapter.postLeverageTokenCreation(msg.sender, address(token));

        emit LeverageTokenCreated(
            token,
            tokenConfig.lendingAdapter.getCollateralAsset(),
            tokenConfig.lendingAdapter.getDebtAsset(),
            tokenConfig
        );
        return token;
    }

    /// @inheritdoc ILeverageManager
    function previewDeposit(ILeverageToken token, uint256 equityInCollateralAsset)
        public
        view
        returns (ActionData memory)
    {
        ActionData memory data = _previewAction(token, equityInCollateralAsset, ExternalAction.Deposit);

        // For deposits, the collateral amount returned by the preview is the total collateral required to execute the
        // deposit, so we add the treasury fee to it, since the collateral computed above is wrt the equity amount with
        // the treasury fee subtracted.
        data.collateral += data.treasuryFee;

        return data;
    }

    /// @inheritdoc ILeverageManager
    function previewWithdraw(ILeverageToken token, uint256 equityInCollateralAsset)
        public
        view
        returns (ActionData memory)
    {
        ActionData memory data = _previewAction(token, equityInCollateralAsset, ExternalAction.Withdraw);

        // For withdrawals, the collateral amount returned is the collateral transferred to the sender, so we subtract the
        // treasury fee, since the collateral computed by `previewAction` is wrt the equity amount without the treasury fee
        // subtracted.
        // Note: It is possible for collateral to be < treasuryFee because of rounding down for both the share calculation and
        //       the resulting collateral calculated using those shares in `previewAction`, while the treasury fee is calculated
        //       based on the initial equity amount rounded up. In this case, we set the collateral to 0 and the treasury fee to
        //       the computed collateral amount
        data.treasuryFee = Math.min(data.collateral, data.treasuryFee);
        data.collateral = data.collateral > data.treasuryFee ? data.collateral - data.treasuryFee : 0;

        return data;
    }

    /// @inheritdoc ILeverageManager
    function deposit(ILeverageToken token, uint256 equityInCollateralAsset, uint256 minShares)
        external
        returns (ActionData memory actionData)
    {
        ActionData memory depositData = previewDeposit(token, equityInCollateralAsset);

        if (depositData.shares < minShares) {
            revert SlippageTooHigh(depositData.shares, minShares);
        }

        // Take collateral asset from sender
        IERC20 collateralAsset = getLeverageTokenCollateralAsset(token);
        SafeERC20.safeTransferFrom(collateralAsset, msg.sender, address(this), depositData.collateral);

        // Add collateral to LeverageToken
        _executeLendingAdapterAction(token, ActionType.AddCollateral, depositData.collateral - depositData.treasuryFee);

        // Charge treasury fee
        _chargeTreasuryFee(collateralAsset, depositData.treasuryFee);

        // Borrow and send debt assets to caller
        _executeLendingAdapterAction(token, ActionType.Borrow, depositData.debt);
        SafeERC20.safeTransfer(getLeverageTokenDebtAsset(token), msg.sender, depositData.debt);

        // Mint shares to user
        // slither-disable-next-line reentrancy-events
        token.mint(msg.sender, depositData.shares);

        // Emit event and explicit return statement
        emit Deposit(token, msg.sender, depositData);
        return depositData;
    }

    /// @inheritdoc ILeverageManager
    function withdraw(ILeverageToken token, uint256 equityInCollateralAsset, uint256 maxShares)
        external
        returns (ActionData memory actionData)
    {
        ActionData memory withdrawData = previewWithdraw(token, equityInCollateralAsset);

        if (withdrawData.shares > maxShares) {
            revert SlippageTooHigh(withdrawData.shares, maxShares);
        }

        // Burn shares from user and total supply
        token.burn(msg.sender, withdrawData.shares);

        // Take assets from sender and repay the debt
        SafeERC20.safeTransferFrom(getLeverageTokenDebtAsset(token), msg.sender, address(this), withdrawData.debt);
        _executeLendingAdapterAction(token, ActionType.Repay, withdrawData.debt);

        // Withdraw collateral from lending pool
        _executeLendingAdapterAction(
            token, ActionType.RemoveCollateral, withdrawData.collateral + withdrawData.treasuryFee
        );

        // Send collateral assets to sender
        IERC20 collateralAsset = getLeverageTokenCollateralAsset(token);
        SafeERC20.safeTransfer(collateralAsset, msg.sender, withdrawData.collateral);

        // Charge treasury fee
        _chargeTreasuryFee(collateralAsset, withdrawData.treasuryFee);

        // Emit event and explicit return statement
        emit Withdraw(token, msg.sender, withdrawData);
        return withdrawData;
    }

    /// @inheritdoc ILeverageManager
    function rebalance(
        RebalanceAction[] calldata actions,
        TokenTransfer[] calldata tokensIn,
        TokenTransfer[] calldata tokensOut
    ) external {
        _transferTokens(tokensIn, msg.sender, address(this));

        LeverageTokenState[] memory leverageTokensStateBefore = new LeverageTokenState[](actions.length);

        for (uint256 i = 0; i < actions.length; i++) {
            ILeverageToken leverageToken = actions[i].leverageToken;

            // Check if the LeverageToken is eligible for rebalance if it has not been checked yet in a previous iteration of the loop
            if (!_isElementInSlice(actions, leverageToken, i)) {
                LeverageTokenState memory state = getLeverageTokenState(leverageToken);
                leverageTokensStateBefore[i] = state;

                IRebalanceAdapterBase rebalanceAdapter = getLeverageTokenRebalanceAdapter(leverageToken);
                if (!rebalanceAdapter.isEligibleForRebalance(leverageToken, state, msg.sender)) {
                    revert LeverageTokenNotEligibleForRebalance(leverageToken);
                }
            }

            _executeLendingAdapterAction(leverageToken, actions[i].actionType, actions[i].amount);
        }

        for (uint256 i = 0; i < actions.length; i++) {
            // Validate the LeverageToken state after rebalancing if it has not been validated yet in a previous iteration of the loop
            if (!_isElementInSlice(actions, actions[i].leverageToken, i)) {
                ILeverageToken leverageToken = actions[i].leverageToken;
                IRebalanceAdapterBase rebalanceAdapter = getLeverageTokenRebalanceAdapter(leverageToken);

                if (!rebalanceAdapter.isStateAfterRebalanceValid(leverageToken, leverageTokensStateBefore[i])) {
                    revert InvalidLeverageTokenStateAfterRebalance(leverageToken);
                }
            }
        }

        _transferTokens(tokensOut, address(this), msg.sender);
    }

    /// @notice Function that converts user's equity to shares
    /// @notice Function uses OZ formula for calculating shares
    /// @param token LeverageToken to convert equity for
    /// @param equityInCollateralAsset Equity to convert to shares, denominated in collateral asset
    /// @return shares Shares
    /// @dev Function should be used to calculate how much shares user should receive for their equity
    function _convertToShares(ILeverageToken token, uint256 equityInCollateralAsset)
        internal
        view
        returns (uint256 shares)
    {
        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(token);

        return Math.mulDiv(
            equityInCollateralAsset,
            token.totalSupply() + 10 ** DECIMALS_OFFSET,
            lendingAdapter.getEquityInCollateralAsset() + 1,
            Math.Rounding.Floor
        );
    }

    /// @notice Previews parameters related to a deposit action
    /// @param token LeverageToken to preview deposit for
    /// @param equityInCollateralAsset Amount of equity to add or withdraw, denominated in collateral asset
    /// @param action Type of the action to preview, can be Deposit or Withdraw
    /// @return data Preview data for the action
    /// @dev If the LeverageToken has zero total supply of shares (so the LeverageToken does not hold any collateral or debt,
    ///      or holds some leftover dust after all shares are redeemed), then the preview will use the target
    ///      collateral ratio for determining how much collateral and debt is required instead of the current collateral ratio.
    /// @dev If action is deposit collateral will be rounded down and debt up, if action is withdraw collateral will be rounded up and debt down
    function _previewAction(ILeverageToken token, uint256 equityInCollateralAsset, ExternalAction action)
        internal
        view
        returns (ActionData memory data)
    {
        (uint256 equityToCover, uint256 equityForShares, uint256 tokenFee, uint256 treasuryFee) =
            _computeEquityFees(token, equityInCollateralAsset, action);

        uint256 shares = _convertToShares(token, equityForShares);

        (uint256 collateral, uint256 debt) = _computeCollateralAndDebtForAction(token, equityToCover, action);

        // The collateral returned by `_computeCollateralAndDebtForAction` can be zero if the amount of equity for the LeverageToken
        // cannot be exchanged for at least 1 LeverageToken share due to rounding down in the exchange rate calculation.
        // The treasury fee returned by `_computeEquityFees` is wrt the equity amount, not the share amount, thus it's possible
        // for it to be non-zero even if the collateral amount is zero. In this case, the treasury fee should be set to 0
        treasuryFee = collateral == 0 ? 0 : treasuryFee;

        return ActionData({
            collateral: collateral,
            debt: debt,
            equity: equityInCollateralAsset,
            shares: shares,
            tokenFee: tokenFee,
            treasuryFee: treasuryFee
        });
    }

    /// @notice Function that computes collateral and debt required by the position held by a LeverageToken for a given action and an amount of equity to add / remove
    /// @param token LeverageToken to compute collateral and debt for
    /// @param equityInCollateralAsset Equity amount in collateral asset
    /// @param action Action to compute collateral and debt for
    /// @return collateral Collateral to add / remove from the LeverageToken
    /// @return debt Debt to borrow / repay to the LeverageToken
    function _computeCollateralAndDebtForAction(
        ILeverageToken token,
        uint256 equityInCollateralAsset,
        ExternalAction action
    ) internal view returns (uint256 collateral, uint256 debt) {
        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(token);
        uint256 totalDebt = lendingAdapter.getDebt();
        uint256 totalShares = token.totalSupply();

        Math.Rounding collateralRounding = action == ExternalAction.Deposit ? Math.Rounding.Ceil : Math.Rounding.Floor;
        Math.Rounding debtRounding = action == ExternalAction.Deposit ? Math.Rounding.Floor : Math.Rounding.Ceil;

        uint256 shares = _convertToShares(token, equityInCollateralAsset);

        // If action is deposit there might be some dust in collateral but debt can be 0. In that case we should follow target ratio
        bool shouldFollowInitialRatio = totalShares == 0 || (action == ExternalAction.Deposit && totalDebt == 0);

        if (shouldFollowInitialRatio) {
            uint256 initialRatio = getLeverageTokenInitialCollateralRatio(token);
            collateral =
                Math.mulDiv(equityInCollateralAsset, initialRatio, initialRatio - BASE_RATIO, collateralRounding);
            debt = lendingAdapter.convertCollateralToDebtAsset(collateral - equityInCollateralAsset);
        } else {
            collateral = Math.mulDiv(lendingAdapter.getCollateral(), shares, totalShares, collateralRounding);
            debt = Math.mulDiv(totalDebt, shares, totalShares, debtRounding);
        }

        return (collateral, debt);
    }

    /// @notice Helper function that checks if a specific element has already been processed in the slice up to the given index
    /// @param actions Entire array to go through
    /// @param token Element to search for
    /// @param untilIndex Search until this specific index
    /// @dev This function is used to check if we already stored the state of the LeverageToken before rebalance.
    ///      This function is used to check if LeverageToken state has been already validated after rebalance
    function _isElementInSlice(RebalanceAction[] calldata actions, ILeverageToken token, uint256 untilIndex)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < untilIndex; i++) {
            if (address(actions[i].leverageToken) == address(token)) {
                return true;
            }
        }

        return false;
    }

    /// @notice Executes actions on the LendingAdapter for a specific LeverageToken
    /// @param token LeverageToken to execute action for
    /// @param actionType Type of the action to execute
    /// @param amount Amount to execute action with
    function _executeLendingAdapterAction(ILeverageToken token, ActionType actionType, uint256 amount) internal {
        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(token);

        if (actionType == ActionType.AddCollateral) {
            IERC20 collateralAsset = lendingAdapter.getCollateralAsset();
            // slither-disable-next-line reentrancy-events
            SafeERC20.forceApprove(collateralAsset, address(lendingAdapter), amount);
            // slither-disable-next-line reentrancy-events
            lendingAdapter.addCollateral(amount);
        } else if (actionType == ActionType.RemoveCollateral) {
            // slither-disable-next-line reentrancy-events
            lendingAdapter.removeCollateral(amount);
        } else if (actionType == ActionType.Borrow) {
            // slither-disable-next-line reentrancy-events
            lendingAdapter.borrow(amount);
        } else if (actionType == ActionType.Repay) {
            IERC20 debtAsset = lendingAdapter.getDebtAsset();
            // slither-disable-next-line reentrancy-events
            SafeERC20.forceApprove(debtAsset, address(lendingAdapter), amount);
            // slither-disable-next-line reentrancy-events
            lendingAdapter.repay(amount);
        }
    }

    /// @notice Used for batching token transfers
    /// @param transfers Array of transfer data. Transfer data consist of token to transfer and amount
    /// @param from Address to transfer tokens from
    /// @param to Address to transfer tokens to
    /// @dev If from address is this smart contract it will use the regular transfer function otherwise it will use transferFrom
    function _transferTokens(TokenTransfer[] calldata transfers, address from, address to) internal {
        for (uint256 i = 0; i < transfers.length; i++) {
            TokenTransfer calldata transfer = transfers[i];

            if (from == address(this)) {
                SafeERC20.safeTransfer(IERC20(transfer.token), to, transfer.amount);
            } else {
                SafeERC20.safeTransferFrom(IERC20(transfer.token), from, to, transfer.amount);
            }
        }
    }
}
