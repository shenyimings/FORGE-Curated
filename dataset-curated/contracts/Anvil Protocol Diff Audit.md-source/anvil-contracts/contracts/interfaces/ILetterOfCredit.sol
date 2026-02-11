// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "./IPriceOracle.sol";

/**
 * @title Interface for LetterOfCredit contract that simply contains events and errors for readability rather than
 * defining an interaction interface.
 */
interface ILetterOfCredit {
    /***************
     * ERROR TYPES *
     ***************/

    error NoOp();
    error LOCNotFound(uint96 _id);
    error AddressUnauthorizedForLOC(address _address, uint96 _forID);
    error PriceUpdateStale(uint32 _publishTimeSeconds, uint16 _maxPriceUpdateSecondsAgo);
    error InvalidSignature(address _accountAddress);
    error InvalidLOCParameters();
    error InvalidRedeemAmount(uint256 _requestedAmount, uint256 _maxAvailable);
    error InvalidZeroAddress();
    error InvalidUpgradeContract();
    error MaxLOCDurationExceeded(uint32 _maxSeconds, uint32 _expirationTimestampSeconds);
    error InsufficientCollateral(uint256 _need, uint256 _have);
    error AssetPairUnauthorized(address _collateralToken, address _creditedToken);
    error InvalidCollateralFactor(uint16 _maxBasisPoints, uint16 _basisPoints);
    error CollateralFactorOverlap(uint16 _creationCollateralFactor, uint16 _liquidationCollateralFactor);
    error ConversionFundsReceivedMismatch(uint256 _expectedFundsReceived, uint256 _actualFundsReceived);
    error CollateralAmountInCreditedTokenZero();
    error PartialRedeemInsolvent();
    error PartialConvertWithoutRedeem(uint96 _id);
    error InvalidBasisPointValue(uint16 _value);
    error LiquidatorIncentiveAboveMax(uint16 _max, uint16 _value);
    error LiquidatorIncentiveChanged(uint16 _was, uint16 _is);
    error InvalidMaxPriceUpdateSecondsAgo(uint16 _min, uint16 _max, uint16 _value);
    error InvalidLOCExtensionTimestamp(uint96 _id, uint32 _newExpirationTimestampSeconds);
    error CreditedTokenMinMaxOverlap();
    error EnabledCreditedTokenMinPerDynamicLOCZero();
    error LOCCreditedTokenMaxExceeded(uint256 _maxPerLOC, uint256 _value);
    error LOCCreditedTokenUnderMinimum(uint256 _minPerLOC, uint256 _value);
    error GlobalCreditedTokenMaxInUseExceeded(uint256 _globalMaxInUse, uint256 _value);
    error LOCExpired(uint96 _id, uint32 _expirationTimestampSeconds);
    error LOCAlreadyConverted(uint96 _id);
    error LiquidationAmountTooSmall(uint256 _collateralToSendLiquidator, uint256 _creditedAmountToReceive);

    /**********
     * EVENTS *
     **********/

    event LOCCreatedV2(
        address indexed creator,
        address indexed beneficiary,
        bytes32 indexed tag,
        address collateralContractAddress,
        address collateralTokenAddress,
        uint256 collateralTokenAmount,
        uint256 claimableCollateral,
        uint32 expirationTimestamp,
        uint16 collateralFactorBasisPoints,
        uint16 liquidatorIncentiveBasisPoints,
        address creditedTokenAddress,
        uint256 creditedTokenAmount,
        uint96 id,
        uint96 collateralId
    );

    /**
     * Deprecated. Some of these events were emitted prior to the proxy upgrade that moved to using LOCCreatedV2, so
     * this event must exist for backward compatibility.
     */
    event LOCCreated(
        address indexed creator,
        address indexed beneficiary,
        address collateralContractAddress,
        address collateralTokenAddress,
        uint256 collateralTokenAmount,
        uint256 claimableCollateral,
        uint32 expirationTimestamp,
        uint16 collateralFactorBasisPoints,
        uint16 liquidatorIncentiveBasisPoints,
        address creditedTokenAddress,
        uint256 creditedTokenAmount,
        uint96 id
    );

    event LOCCanceled(uint96 indexed id);

    event LOCExtended(uint96 indexed id, uint32 oldExpirationTimestamp, uint32 newExpirationTimestamp);

    event LOCConverted(
        uint96 indexed id,
        address indexed initiator,
        address indexed liquidator,
        uint256 liquidationAmount,
        uint256 liquidationFeeAmount,
        uint256 creditedTokenAmountReceived
    );

    // NB: Exact same args as LOCConverted, but we don't want to emit LOCConverted when the entire LOC is not converted.
    event LOCPartiallyLiquidated(
        uint96 indexed id,
        address indexed initiator,
        address indexed liquidator,
        uint256 liquidationAmount,
        uint256 liquidationFeeAmount,
        uint256 creditedTokenAmountReceived
    );

    event LOCRedeemed(
        uint96 indexed id,
        address indexed destinationAddress,
        uint256 creditedTokenAmount,
        uint256 collateralTokenAmountUsed,
        uint256 claimableCollateralUsed
    );

    event LOCCollateralModified(
        uint96 indexed id,
        uint256 oldCollateralAmount,
        uint256 newCollateralAmount,
        uint256 newClaimableCollateral
    );

    event CreditedTokenUpdated(
        address indexed tokenAddress,
        uint256 minPerDynamicLOC,
        uint256 maxPerDynamicLOC,
        uint256 globalMaxInDynamicUse
    );

    event CollateralFactorUpdated(
        address indexed collateralTokenAddress,
        address indexed creditedTokenAddress,
        uint16 creationCollateralFactorBasisPoints,
        uint16 collateralFactorBasisPoints,
        uint16 liquidatorIncentiveBasisPoints
    );

    event MaxPriceUpdateSecondsAgoUpdated(uint16 oldSecondsAgo, uint16 newSecondsAgo);
    event MaxLocDurationSecondsUpdated(uint32 oldMaxDurationSeconds, uint32 newMaxDurationSeconds);
    event CollateralAddressUpgraded(address oldCollateralAddress, address newCollateralAddress);

    event PriceOracleUpgradeRevoked();
    event PriceOracleUpgradePending(IPriceOracle priceOracle, uint256 validAfterTimestamp);
    event PriceOracleUpgraded(IPriceOracle oldPriceOracle, IPriceOracle newPriceOracle);

    event OracleTimeDelayUpdatePending(uint256 timeDelay, uint256 validAfterTimestamp);
    event OracleTimeDelayUpdated(uint256 oldTimeDelay, uint256 newTimeDelay);
}
