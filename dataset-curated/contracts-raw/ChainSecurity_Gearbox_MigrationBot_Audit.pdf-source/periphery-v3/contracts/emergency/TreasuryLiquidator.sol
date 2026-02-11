// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.17;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {ICreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {PriceUpdate} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeedStore.sol";
import {SanityCheckTrait} from "@gearbox-protocol/core-v3/contracts/traits/SanityCheckTrait.sol";
import {PERCENTAGE_FACTOR} from "@gearbox-protocol/core-v3/contracts/libraries/Constants.sol";

import {IMarketConfigurator} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";
import {IContractsRegister} from "@gearbox-protocol/permissionless/contracts/interfaces/IContractsRegister.sol";

/**
 * @title TreasuryLiquidator
 * @notice This contract allows the treasury to liquidate credit accounts by providing the funds
 * needed for liquidation and receiving the seized collateral. The treasury can set exchange rates
 * for different token pairs, as well as approve liquidators to use this contract.
 */
contract TreasuryLiquidator is SanityCheckTrait {
    using SafeERC20 for IERC20;

    /// @notice Contract type for identification
    bytes32 public constant contractType = "TREASURY_LIQUIDATOR";

    /// @notice Contract version
    uint256 public constant version = 3_10;

    /// @notice The treasury address that funds are taken from and returned to
    address public immutable treasury;

    /// @notice The market configurator address
    address public immutable marketConfigurator;

    /// @notice Mapping of approved liquidators who can use this contract
    mapping(address => bool) public isLiquidator;

    /// @notice Mapping of minimum exchange rates (assetIn => assetOut => rate)
    /// Rate is in PERCENTAGE_FACTOR format (i.e. 10050 means 1.005 units of collateral per unit of underlying, regardless of decimals)
    mapping(address => mapping(address => uint256)) public minExchangeRates;

    // EVENTS
    event PartiallyLiquidateFromTreasury(
        address indexed creditFacade, address indexed creditAccount, address indexed liquidator
    );
    event SetLiquidatorStatus(address indexed liquidator, bool status);
    event SetMinExchangeRate(address indexed assetIn, address indexed assetOut, uint256 rate);

    // ERRORS
    error CallerNotTreasuryException();
    error CallerNotApprovedLiquidatorException();
    error InsufficientTreasuryFundsException();
    error UnsupportedTokenPairException();
    error InvalidCreditSuiteException();

    /// @notice Modifier to verify the sender is the treasury
    modifier onlyTreasury() {
        if (msg.sender != treasury) revert CallerNotTreasuryException();
        _;
    }

    /// @notice Modifier to verify the sender is an approved liquidator
    modifier onlyLiquidator() {
        if (!isLiquidator[msg.sender]) revert CallerNotApprovedLiquidatorException();
        _;
    }

    /// @notice Modifier to verify the credit facade is from the market configurator
    modifier onlyCFFromMarketConfigurator(address creditFacade) {
        address creditManager = ICreditFacadeV3(creditFacade).creditManager();
        bool isValidCM = IContractsRegister(IMarketConfigurator(marketConfigurator).contractsRegister()).isCreditManager(
            creditManager
        );
        if (!isValidCM || ICreditManagerV3(creditManager).creditFacade() != creditFacade) {
            revert InvalidCreditSuiteException();
        }
        _;
    }

    /**
     * @notice Constructor
     * @param _treasury The address of the treasury
     */
    constructor(address _treasury, address _marketConfigurator)
        nonZeroAddress(_treasury)
        nonZeroAddress(_marketConfigurator)
    {
        treasury = _treasury;
        marketConfigurator = _marketConfigurator;
    }

    /**
     * @notice Set liquidator status
     * @param liquidator The address to set status for
     * @param status True to approve, false to revoke
     */
    function setLiquidatorStatus(address liquidator, bool status) external onlyTreasury nonZeroAddress(liquidator) {
        if (isLiquidator[liquidator] == status) return;
        isLiquidator[liquidator] = status;
        emit SetLiquidatorStatus(liquidator, status);
    }

    /**
     * @notice Set minimum exchange rate between two assets
     * @param assetIn The asset being provided for liquidation
     * @param assetOut The asset expected to be received from liquidation
     * @param rate The minimum exchange rate (RATE_PRECISION format)
     */
    function setMinExchangeRate(address assetIn, address assetOut, uint256 rate)
        external
        onlyTreasury
        nonZeroAddress(assetIn)
        nonZeroAddress(assetOut)
    {
        if (minExchangeRates[assetIn][assetOut] == rate) return;

        minExchangeRates[assetIn][assetOut] = rate;
        emit SetMinExchangeRate(assetIn, assetOut, rate);
    }

    /**
     * @notice Partially liquidate a credit account using funds from the treasury
     * @param creditFacade The credit facade contract
     * @param creditAccount The credit account to partially liquidate
     * @param token The collateral token to seize
     * @param repaidAmount The amount of underlying to repay
     * @param priceUpdates Optional price updates to apply before liquidation
     */
    function partiallyLiquidateFromTreasury(
        address creditFacade,
        address creditAccount,
        address token,
        uint256 repaidAmount,
        PriceUpdate[] calldata priceUpdates,
        address wrappedUnderlying
    ) external onlyLiquidator onlyCFFromMarketConfigurator(creditFacade) {
        address underlying = ICreditFacadeV3(creditFacade).underlying();

        uint256 minSeizedAmount = _getMinSeizedAmount(underlying, token, repaidAmount);

        _transferUnderlying(underlying, wrappedUnderlying, repaidAmount);
        {
            address creditManager = ICreditFacadeV3(creditFacade).creditManager();
            IERC20(underlying).forceApprove(creditManager, repaidAmount);
        }

        ICreditFacadeV3(creditFacade).partiallyLiquidateCreditAccount(
            creditAccount, token, repaidAmount, minSeizedAmount, treasury, priceUpdates
        );

        emit PartiallyLiquidateFromTreasury(creditFacade, creditAccount, msg.sender);
    }

    function _getMinSeizedAmount(address underlying, address token, uint256 repaidAmount)
        internal
        view
        returns (uint256)
    {
        uint256 requiredRate = minExchangeRates[underlying][token];
        if (requiredRate == 0) revert UnsupportedTokenPairException();

        uint256 scaleUnderlying = 10 ** IERC20Metadata(underlying).decimals();
        uint256 scaleToken = 10 ** IERC20Metadata(token).decimals();

        return repaidAmount * requiredRate * scaleToken / (PERCENTAGE_FACTOR * scaleUnderlying);
    }

    function _transferUnderlying(address underlying, address wrappedUnderlying, uint256 amount) internal {
        if (wrappedUnderlying != address(0)) {
            uint256 wrappedAssets = IERC4626(wrappedUnderlying).maxWithdraw(treasury);
            if (wrappedAssets < amount) revert InsufficientTreasuryFundsException();
            IERC4626(wrappedUnderlying).withdraw(amount, address(this), treasury);
        } else {
            uint256 balance = IERC20(underlying).balanceOf(treasury);
            if (balance < amount) revert InsufficientTreasuryFundsException();
            IERC20(underlying).safeTransferFrom(treasury, address(this), amount);
        }
    }
}
