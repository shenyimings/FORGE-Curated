// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardTransientUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
    RebalanceAction
} from "src/types/DataTypes.sol";

/**
 * @dev The LeverageManager contract is an upgradeable core contract that is responsible for managing the creation of LeverageTokens.
 * It also acts as an entry point for users to mint and redeem LeverageTokens (shares), and for
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
 * For mints of LeverageTokens (shares), the collateral and debt required is calculated by using the LeverageToken's
 * current collateral ratio. As such, the collateral ratio after a mint must be equal to the collateral ratio before a
 * mint, within some rounding error.
 *
 * [CAUTION]
 * ====
 * - LeverageTokens are susceptible to inflation attacks like ERC-4626 vaults:
 *   "In empty (or nearly empty) ERC-4626 vaults, mints are at high risk of being stolen through frontrunning
 *   with a "donation" to the vault that inflates the price of a share. This is variously known as a donation or inflation
 *   attack and is essentially a problem of slippage. Vault deployers can protect against this attack by making an initial
 *   mint of a non-trivial amount of the asset, such that price manipulation becomes infeasible. Redeems may
 *   similarly be affected by slippage. Users can protect against this attack as well as unexpected slippage in general by
 *   verifying the amount received is as expected, using a wrapper that performs these checks such as
 *   https://github.com/fei-protocol/ERC4626#erc4626router-and-base[ERC4626Router]."
 *
 *   As such it is highly recommended that LeverageToken creators make an initial mint of a non-trivial amount of equity.
 *   It is also recommended to use a router that performs slippage checks when minting and redeeming.
 *
 * - LeverageToken creation is permissionless and can be configured with arbitrary lending adapters, rebalance adapters, and
 *   underlying collateral and debt assets. As such, the adapters and tokens used by a LeverageToken are part of the risk
 *   profile of the LeverageToken, and should be carefully considered by users before using a LeverageToken.
 *
 * - LeverageTokens can be configured with arbitrary lending adapters, thus LeverageTokens are directly affected by the
 *   specific mechanisms of the underlying lending market that their lending adapter integrates with. As mentioned above,
 *   it is highly recommended that users research and understand the lending adapter used by the LeverageToken they are
 *   considering using. Some examples:
 *   - Morpho: Users should be aware that Morpho market creation is permissionless, and that the price oracle used by
 *     by the market may be manipulatable.
 *   - Aave v3: Allows rehypothecation of collateral, which may lead to reverts when trying to remove collateral from the
 *     market during redeems and rebalances.
 *
 * @custom:contact security@seamlessprotocol.com
 */
contract LeverageManager is
    ILeverageManager,
    AccessControlUpgradeable,
    ReentrancyGuardTransientUpgradeable,
    FeeManager,
    UUPSUpgradeable
{
    // Base collateral ratio constant, 1e18 means that collateral / debt ratio is 1:1
    uint256 public constant BASE_RATIO = 1e18;
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

    function initialize(address initialAdmin, address treasury, IBeaconProxyFactory leverageTokenFactory)
        external
        initializer
    {
        __FeeManager_init(initialAdmin, treasury);
        __ReentrancyGuardTransient_init();
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _getLeverageManagerStorage().tokenFactory = leverageTokenFactory;
        emit LeverageManagerInitialized(leverageTokenFactory);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /// @inheritdoc ILeverageManager
    function convertCollateralToDebt(ILeverageToken token, uint256 collateral, Math.Rounding rounding)
        external
        view
        returns (uint256 debt)
    {
        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(token);
        uint256 totalCollateral = lendingAdapter.getCollateral();
        uint256 totalDebt = lendingAdapter.getDebt();

        return _convertCollateralToDebt(token, lendingAdapter, collateral, totalCollateral, totalDebt, rounding);
    }

    /// @inheritdoc ILeverageManager
    function convertCollateralToShares(ILeverageToken token, uint256 collateral, Math.Rounding rounding)
        public
        view
        returns (uint256 shares)
    {
        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(token);
        uint256 totalSupply = getFeeAdjustedTotalSupply(token);
        return _convertCollateralToShares(token, lendingAdapter, collateral, totalSupply, rounding);
    }

    /// @inheritdoc ILeverageManager
    function convertDebtToCollateral(ILeverageToken token, uint256 debt, Math.Rounding rounding)
        external
        view
        returns (uint256 collateral)
    {
        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(token);
        uint256 totalCollateral = lendingAdapter.getCollateral();
        uint256 totalDebt = lendingAdapter.getDebt();

        if (totalDebt == 0) {
            if (totalCollateral == 0) {
                // Initial state: no collateral or debt, use initial collateral ratio
                uint256 initialCollateralRatio = getLeverageTokenInitialCollateralRatio(token);
                return lendingAdapter.convertDebtToCollateralAsset(
                    Math.mulDiv(debt, initialCollateralRatio, BASE_RATIO, rounding)
                );
            }
            // Liquidated state: no debt but collateral exists, cannot convert
            return 0;
        }

        return Math.mulDiv(debt, totalCollateral, totalDebt, rounding);
    }

    /// @inheritdoc ILeverageManager
    function convertSharesToCollateral(ILeverageToken token, uint256 shares, Math.Rounding rounding)
        external
        view
        returns (uint256 collateral)
    {
        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(token);
        uint256 totalCollateral = lendingAdapter.getCollateral();
        uint256 totalSupply = getFeeAdjustedTotalSupply(token);
        return _convertSharesToCollateral(token, lendingAdapter, shares, totalCollateral, totalSupply, rounding);
    }

    /// @inheritdoc ILeverageManager
    function convertSharesToDebt(ILeverageToken token, uint256 shares, Math.Rounding rounding)
        external
        view
        returns (uint256 debt)
    {
        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(token);
        uint256 totalDebt = lendingAdapter.getDebt();
        uint256 totalSupply = getFeeAdjustedTotalSupply(token);
        return _convertSharesToDebt(token, lendingAdapter, shares, totalDebt, totalSupply, rounding);
    }

    /// @inheritdoc ILeverageManager
    function convertToAssets(ILeverageToken token, uint256 shares)
        external
        view
        returns (uint256 equityInCollateralAsset)
    {
        uint256 totalEquityInCollateralAsset = getLeverageTokenLendingAdapter(token).getEquityInCollateralAsset();
        uint256 totalSupply = getFeeAdjustedTotalSupply(token);

        // slither-disable-next-line incorrect-equality,timestamp
        if (totalSupply == 0) {
            return 0;
        }

        return Math.mulDiv(shares, totalEquityInCollateralAsset, totalSupply, Math.Rounding.Floor);
    }

    /// @inheritdoc ILeverageManager
    function convertToShares(ILeverageToken token, uint256 equityInCollateralAsset)
        external
        view
        returns (uint256 shares)
    {
        uint256 totalEquityInCollateralAsset = getLeverageTokenLendingAdapter(token).getEquityInCollateralAsset();
        uint256 totalSupply = getFeeAdjustedTotalSupply(token);

        if (totalEquityInCollateralAsset == 0) {
            return 0;
        }

        return Math.mulDiv(equityInCollateralAsset, totalSupply, totalEquityInCollateralAsset, Math.Rounding.Floor);
    }

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
        uint256 mintTokenFee = getLeverageTokenActionFee(token, ExternalAction.Mint);
        uint256 redeemTokenFee = getLeverageTokenActionFee(token, ExternalAction.Redeem);

        return LeverageTokenConfig({
            lendingAdapter: baseConfig.lendingAdapter,
            rebalanceAdapter: baseConfig.rebalanceAdapter,
            mintTokenFee: mintTokenFee,
            redeemTokenFee: redeemTokenFee
        });
    }

    /// @inheritdoc ILeverageManager
    function getLeverageTokenLendingAdapter(ILeverageToken token) public view returns (ILendingAdapter adapter) {
        return _getLeverageManagerStorage().config[token].lendingAdapter;
    }

    /// @inheritdoc ILeverageManager
    function getLeverageTokenInitialCollateralRatio(ILeverageToken token) public view returns (uint256) {
        uint256 initialCollateralRatio =
            getLeverageTokenRebalanceAdapter(token).getLeverageTokenInitialCollateralRatio(token);

        if (initialCollateralRatio <= BASE_RATIO) {
            revert InvalidLeverageTokenInitialCollateralRatio(initialCollateralRatio);
        }

        return initialCollateralRatio;
    }

    /// @inheritdoc ILeverageManager
    function getLeverageTokenState(ILeverageToken token) external view returns (LeverageTokenState memory state) {
        return _getLeverageTokenState(getLeverageTokenLendingAdapter(token));
    }

    /// @inheritdoc ILeverageManager
    function createNewLeverageToken(LeverageTokenConfig calldata tokenConfig, string memory name, string memory symbol)
        external
        nonReentrant
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
        _setLeverageTokenActionFee(token, ExternalAction.Mint, tokenConfig.mintTokenFee);
        _setLeverageTokenActionFee(token, ExternalAction.Redeem, tokenConfig.redeemTokenFee);
        _setNewLeverageTokenManagementFee(token);

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
    function previewDeposit(ILeverageToken token, uint256 collateral) public view returns (ActionData memory) {
        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(token);
        uint256 feeAdjustedTotalSupply = getFeeAdjustedTotalSupply(token);

        uint256 debt = _convertCollateralToDebt(
            token,
            lendingAdapter,
            collateral,
            lendingAdapter.getCollateral(),
            lendingAdapter.getDebt(),
            Math.Rounding.Floor
        );

        uint256 shares =
            _convertCollateralToShares(token, lendingAdapter, collateral, feeAdjustedTotalSupply, Math.Rounding.Floor);
        (uint256 sharesAfterFee, uint256 sharesFee, uint256 treasuryFee) =
            _computeFeesForGrossShares(token, shares, ExternalAction.Mint);

        return ActionData({
            collateral: collateral,
            debt: debt,
            shares: sharesAfterFee,
            tokenFee: sharesFee,
            treasuryFee: treasuryFee
        });
    }

    /// @inheritdoc ILeverageManager
    function previewMint(ILeverageToken token, uint256 shares) public view returns (ActionData memory) {
        (uint256 grossShares, uint256 sharesFee, uint256 treasuryFee) =
            _computeFeesForNetShares(token, shares, ExternalAction.Mint);

        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(token);
        uint256 feeAdjustedTotalSupply = getFeeAdjustedTotalSupply(token);
        uint256 collateral = _convertSharesToCollateral(
            token,
            lendingAdapter,
            grossShares,
            lendingAdapter.getCollateral(),
            feeAdjustedTotalSupply,
            Math.Rounding.Ceil
        );
        uint256 debt = _convertCollateralToDebt(
            token,
            lendingAdapter,
            collateral,
            lendingAdapter.getCollateral(),
            lendingAdapter.getDebt(),
            Math.Rounding.Floor
        );

        return ActionData({
            collateral: collateral,
            debt: debt,
            shares: shares,
            tokenFee: sharesFee,
            treasuryFee: treasuryFee
        });
    }

    /// @inheritdoc ILeverageManager
    function previewRedeem(ILeverageToken token, uint256 shares) public view returns (ActionData memory) {
        (uint256 sharesAfterFees, uint256 sharesFee, uint256 treasuryFee) =
            _computeFeesForGrossShares(token, shares, ExternalAction.Redeem);

        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(token);
        uint256 feeAdjustedTotalSupply = getFeeAdjustedTotalSupply(token);

        // The redeemer receives collateral and repays debt for the net shares after fees are subtracted. The amount of
        // shares their balance is decreased by is that net share amount (which is burned) plus the fees.
        // - the treasury fee shares are given to the treasury
        // - the token fee shares are burned to increase share value
        uint256 collateral = _convertSharesToCollateral(
            token,
            lendingAdapter,
            sharesAfterFees,
            lendingAdapter.getCollateral(),
            feeAdjustedTotalSupply,
            Math.Rounding.Floor
        );
        uint256 debt = _convertSharesToDebt(
            token, lendingAdapter, sharesAfterFees, lendingAdapter.getDebt(), feeAdjustedTotalSupply, Math.Rounding.Ceil
        );

        return ActionData({
            collateral: collateral,
            debt: debt,
            shares: shares,
            tokenFee: sharesFee,
            treasuryFee: treasuryFee
        });
    }

    /// @inheritdoc ILeverageManager
    function previewWithdraw(ILeverageToken token, uint256 collateral) public view returns (ActionData memory) {
        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(token);
        uint256 feeAdjustedTotalSupply = getFeeAdjustedTotalSupply(token);

        // The withdrawer receives their specified collateral amount and pays debt for the shares that can be exchanged
        // for the collateral amount. The amount of shares their balance is decreased by is that share amount (which is
        // burned) plus the fees.
        // - the treasury fee shares are given to the treasury
        // - the token fee shares are burned to increase share value
        uint256 shares =
            _convertCollateralToShares(token, lendingAdapter, collateral, feeAdjustedTotalSupply, Math.Rounding.Ceil);
        uint256 debt = _convertCollateralToDebt(
            token,
            lendingAdapter,
            collateral,
            lendingAdapter.getCollateral(),
            lendingAdapter.getDebt(),
            Math.Rounding.Ceil
        );

        (uint256 sharesAfterFees, uint256 sharesFee, uint256 treasuryFee) =
            _computeFeesForNetShares(token, shares, ExternalAction.Redeem);

        return ActionData({
            collateral: collateral,
            debt: debt,
            shares: sharesAfterFees,
            tokenFee: sharesFee,
            treasuryFee: treasuryFee
        });
    }

    /// @inheritdoc ILeverageManager
    function deposit(ILeverageToken token, uint256 collateral, uint256 minShares)
        external
        nonReentrant
        returns (ActionData memory actionData)
    {
        // Management fee is calculated from the total supply of the LeverageToken, so we need to charge it first
        // before total supply is updated due to the mint
        chargeManagementFee(token);

        ActionData memory depositData = previewDeposit(token, collateral);

        // slither-disable-next-line timestamp
        if (depositData.shares < minShares) {
            revert SlippageTooHigh(depositData.shares, minShares); // TODO: check if this is correct
        }

        _mint(token, depositData);

        return depositData;
    }

    /// @inheritdoc ILeverageManager
    function mint(ILeverageToken token, uint256 shares, uint256 maxCollateral)
        external
        nonReentrant
        returns (ActionData memory actionData)
    {
        // Management fee is calculated from the total supply of the LeverageToken, so we need to charge it first
        // before total supply is updated due to the mint
        chargeManagementFee(token);

        ActionData memory mintData = previewMint(token, shares);

        // slither-disable-next-line timestamp
        if (mintData.collateral > maxCollateral) {
            revert SlippageTooHigh(mintData.collateral, maxCollateral);
        }

        _mint(token, mintData);

        return mintData;
    }

    /// @inheritdoc ILeverageManager
    function rebalance(
        ILeverageToken leverageToken,
        RebalanceAction[] calldata actions,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) external nonReentrant {
        _transferTokens(tokenIn, msg.sender, address(this), amountIn);

        ILendingAdapter lendingAdapter = getLeverageTokenLendingAdapter(leverageToken);

        // Check if the LeverageToken is eligible for rebalance
        LeverageTokenState memory stateBefore = _getLeverageTokenState(lendingAdapter);

        IRebalanceAdapterBase rebalanceAdapter = getLeverageTokenRebalanceAdapter(leverageToken);
        if (!rebalanceAdapter.isEligibleForRebalance(leverageToken, stateBefore, msg.sender)) {
            revert LeverageTokenNotEligibleForRebalance();
        }

        for (uint256 i = 0; i < actions.length; i++) {
            _executeLendingAdapterAction(leverageToken, actions[i].actionType, actions[i].amount);
        }

        // Validate the LeverageToken state after rebalancing
        if (!rebalanceAdapter.isStateAfterRebalanceValid(leverageToken, stateBefore)) {
            revert InvalidLeverageTokenStateAfterRebalance(leverageToken);
        }

        _transferTokens(tokenOut, address(this), msg.sender, amountOut);

        LeverageTokenState memory stateAfter = _getLeverageTokenState(lendingAdapter);

        emit Rebalance(leverageToken, msg.sender, stateBefore, stateAfter, actions);
    }

    /// @inheritdoc ILeverageManager
    function redeem(ILeverageToken token, uint256 shares, uint256 minCollateral)
        external
        nonReentrant
        returns (ActionData memory actionData)
    {
        // Management fee is calculated from the total supply of the LeverageToken, so we need to claim it first
        // before total supply is updated due to the redeem
        chargeManagementFee(token);

        ActionData memory redeemData = previewRedeem(token, shares);

        // slither-disable-next-line timestamp
        if (redeemData.collateral < minCollateral) {
            revert SlippageTooHigh(redeemData.collateral, minCollateral);
        }

        _redeem(token, redeemData);

        return redeemData;
    }

    /// @inheritdoc ILeverageManager
    function withdraw(ILeverageToken token, uint256 collateral, uint256 maxShares)
        external
        nonReentrant
        returns (ActionData memory actionData)
    {
        // Management fee is calculated from the total supply of the LeverageToken, so we need to claim it first
        // before total supply is updated due to the redeem
        chargeManagementFee(token);

        ActionData memory withdrawData = previewWithdraw(token, collateral);

        // slither-disable-next-line timestamp
        if (withdrawData.shares > maxShares) {
            revert SlippageTooHigh(withdrawData.shares, maxShares);
        }

        _redeem(token, withdrawData);

        return withdrawData;
    }

    /// @notice Converts collateral to debt given the state of the LeverageToken
    /// @param token LeverageToken to convert collateral for
    /// @param lendingAdapter Lending adapter of the LeverageToken
    /// @param collateral Collateral to convert to debt
    /// @param totalCollateral Total collateral of the LeverageToken
    /// @param totalDebt Total debt of the LeverageToken
    /// @param rounding Rounding mode
    /// @return debt Debt
    function _convertCollateralToDebt(
        ILeverageToken token,
        ILendingAdapter lendingAdapter,
        uint256 collateral,
        uint256 totalCollateral,
        uint256 totalDebt,
        Math.Rounding rounding
    ) internal view returns (uint256 debt) {
        if (totalCollateral == 0) {
            if (totalDebt == 0) {
                // Initial state: no collateral or debt, use initial collateral ratio
                uint256 initialCollateralRatio = getLeverageTokenInitialCollateralRatio(token);
                return lendingAdapter.convertCollateralToDebtAsset(
                    Math.mulDiv(collateral, BASE_RATIO, initialCollateralRatio, rounding)
                );
            }
            // Liquidated state: no collateral but debt exists, cannot convert
            return 0;
        }

        return Math.mulDiv(collateral, totalDebt, totalCollateral, rounding);
    }

    /// @notice Converts collateral to shares given the state of the LeverageToken
    /// @param token LeverageToken to convert collateral for
    /// @param lendingAdapter Lending adapter of the LeverageToken
    /// @param collateral Collateral to convert to shares
    /// @param totalSupply Total supply of shares of the LeverageToken
    /// @param rounding Rounding mode
    /// @return shares Shares
    function _convertCollateralToShares(
        ILeverageToken token,
        ILendingAdapter lendingAdapter,
        uint256 collateral,
        uint256 totalSupply,
        Math.Rounding rounding
    ) internal view returns (uint256 shares) {
        uint256 totalCollateral = lendingAdapter.getCollateral();

        // slither-disable-next-line incorrect-equality,timestamp
        if (totalSupply == 0) {
            uint256 initialCollateralRatio = getLeverageTokenInitialCollateralRatio(token);

            uint256 equityInCollateralAsset =
                Math.mulDiv(collateral, initialCollateralRatio - BASE_RATIO, initialCollateralRatio, rounding);

            uint256 leverageTokenDecimals = IERC20Metadata(address(token)).decimals();
            uint256 collateralDecimals = IERC20Metadata(address(lendingAdapter.getCollateralAsset())).decimals();

            // If collateral asset has more decimals than leverage token, we scale down the equity in collateral asset
            // Otherwise we scale up the equity in collateral asset
            if (collateralDecimals > leverageTokenDecimals) {
                uint256 scalingFactor = 10 ** (collateralDecimals - leverageTokenDecimals);
                return equityInCollateralAsset / scalingFactor;
            } else {
                uint256 scalingFactor = 10 ** (leverageTokenDecimals - collateralDecimals);
                return equityInCollateralAsset * scalingFactor;
            }
        }

        // If total supply != 0 and total collateral is zero, the LeverageToken was fully liquidated. In this case,
        // no amount of collateral can be converted to shares. An implication of this is that new mints of shares
        // will not be possible for the LeverageToken.
        if (totalCollateral == 0) {
            return 0;
        }

        return Math.mulDiv(collateral, totalSupply, totalCollateral, rounding);
    }

    /// @notice Converts shares to collateral given the state of the LeverageToken
    /// @param token LeverageToken to convert shares for
    /// @param lendingAdapter Lending adapter of the LeverageToken
    /// @param shares Shares to convert to collateral
    /// @param totalCollateral Total collateral of the LeverageToken
    /// @param totalSupply Total supply of shares of the LeverageToken
    /// @param rounding Rounding mode
    function _convertSharesToCollateral(
        ILeverageToken token,
        ILendingAdapter lendingAdapter,
        uint256 shares,
        uint256 totalCollateral,
        uint256 totalSupply,
        Math.Rounding rounding
    ) internal view returns (uint256 collateral) {
        // slither-disable-next-line incorrect-equality,timestamp
        if (totalSupply == 0) {
            uint256 leverageTokenDecimals = IERC20Metadata(address(token)).decimals();
            uint256 collateralDecimals = IERC20Metadata(address(lendingAdapter.getCollateralAsset())).decimals();

            uint256 initialCollateralRatio = getLeverageTokenInitialCollateralRatio(token);

            // If collateral asset has more decimals than leverage token, we scale down the equity in collateral asset
            // Otherwise we scale up the equity in collateral asset
            if (collateralDecimals > leverageTokenDecimals) {
                uint256 scalingFactor = 10 ** (collateralDecimals - leverageTokenDecimals);
                return Math.mulDiv(
                    shares * scalingFactor, initialCollateralRatio, initialCollateralRatio - BASE_RATIO, rounding
                );
            } else {
                uint256 scalingFactor = 10 ** (leverageTokenDecimals - collateralDecimals);
                return Math.mulDiv(
                    shares, initialCollateralRatio, (initialCollateralRatio - BASE_RATIO) * scalingFactor, rounding
                );
            }
        }

        return Math.mulDiv(shares, totalCollateral, totalSupply, rounding);
    }

    /// @notice Converts shares to debt given the state of the LeverageToken
    /// @param token LeverageToken to convert shares for
    /// @param lendingAdapter Lending adapter of the LeverageToken
    /// @param shares Shares to convert to debt
    /// @param totalDebt Total debt of the LeverageToken
    /// @param totalSupply Total supply of shares of the LeverageToken
    /// @param rounding Rounding mode
    function _convertSharesToDebt(
        ILeverageToken token,
        ILendingAdapter lendingAdapter,
        uint256 shares,
        uint256 totalDebt,
        uint256 totalSupply,
        Math.Rounding rounding
    ) internal view returns (uint256 debt) {
        // slither-disable-next-line incorrect-equality,timestamp
        if (totalSupply == 0) {
            uint256 leverageTokenDecimals = IERC20Metadata(address(token)).decimals();
            uint256 collateralDecimals = IERC20Metadata(address(lendingAdapter.getCollateralAsset())).decimals();

            uint256 initialCollateralRatio = getLeverageTokenInitialCollateralRatio(token);

            // If collateral asset has more decimals than leverage token, we scale down the equity in collateral asset
            // Otherwise we scale up the equity in collateral asset
            if (collateralDecimals > leverageTokenDecimals) {
                uint256 scalingFactor = 10 ** (collateralDecimals - leverageTokenDecimals);
                return lendingAdapter.convertCollateralToDebtAsset(
                    Math.mulDiv(shares * scalingFactor, BASE_RATIO, initialCollateralRatio - BASE_RATIO, rounding)
                );
            } else {
                uint256 scalingFactor = 10 ** (leverageTokenDecimals - collateralDecimals);
                return lendingAdapter.convertCollateralToDebtAsset(
                    Math.mulDiv(shares, BASE_RATIO, (initialCollateralRatio - BASE_RATIO) * scalingFactor, rounding)
                );
            }
        }

        return Math.mulDiv(shares, totalDebt, totalSupply, rounding);
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

    //// @notice Returns all data required to describe current LeverageToken state - collateral, debt, equity and collateral ratio
    /// @param lendingAdapter LendingAdapter of the LeverageToken
    /// @return state LeverageToken state
    function _getLeverageTokenState(ILendingAdapter lendingAdapter)
        internal
        view
        returns (LeverageTokenState memory state)
    {
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

    /// @notice Helper function for executing a mint action on a LeverageToken
    /// @param token LeverageToken to mint shares for
    /// @param mintData Action data for the mint
    function _mint(ILeverageToken token, ActionData memory mintData) internal {
        // Take collateral asset from sender
        IERC20 collateralAsset = getLeverageTokenCollateralAsset(token);
        SafeERC20.safeTransferFrom(collateralAsset, msg.sender, address(this), mintData.collateral);

        // Add collateral to LeverageToken
        _executeLendingAdapterAction(token, ActionType.AddCollateral, mintData.collateral);

        // Borrow and send debt assets to caller
        _executeLendingAdapterAction(token, ActionType.Borrow, mintData.debt);
        SafeERC20.safeTransfer(getLeverageTokenDebtAsset(token), msg.sender, mintData.debt);

        // Charge treasury fee
        _chargeTreasuryFee(token, mintData.treasuryFee);

        // Mint shares to user
        // slither-disable-next-line reentrancy-events
        token.mint(msg.sender, mintData.shares);

        // Emit event and explicit return statement
        emit Mint(token, msg.sender, mintData);
    }

    /// @notice Helper function for executing a redeem action on a LeverageToken
    /// @param token LeverageToken to redeem shares for
    /// @param redeemData Action data for the redeem
    function _redeem(ILeverageToken token, ActionData memory redeemData) internal {
        // Burn shares from user and total supply
        token.burn(msg.sender, redeemData.shares);

        // Mint shares to treasury for the treasury action fee
        _chargeTreasuryFee(token, redeemData.treasuryFee);

        // Take assets from sender and repay the debt
        SafeERC20.safeTransferFrom(getLeverageTokenDebtAsset(token), msg.sender, address(this), redeemData.debt);
        _executeLendingAdapterAction(token, ActionType.Repay, redeemData.debt);

        // Remove collateral from lending pool
        _executeLendingAdapterAction(token, ActionType.RemoveCollateral, redeemData.collateral);

        // Send collateral assets to sender
        SafeERC20.safeTransfer(getLeverageTokenCollateralAsset(token), msg.sender, redeemData.collateral);

        // Emit event and explicit return statement
        emit Redeem(token, msg.sender, redeemData);
    }

    /// @notice Helper function for transferring tokens, or no-op if token is 0 address
    /// @param token Token to transfer
    /// @param from Address to transfer tokens from
    /// @param to Address to transfer tokens to
    /// @dev If from address is this smart contract it will use the regular transfer function otherwise it will use transferFrom
    function _transferTokens(IERC20 token, address from, address to, uint256 amount) internal {
        if (address(token) == address(0)) {
            return;
        }

        if (from == address(this)) {
            SafeERC20.safeTransfer(token, to, amount);
        } else {
            SafeERC20.safeTransferFrom(token, from, to, amount);
        }
    }
}
