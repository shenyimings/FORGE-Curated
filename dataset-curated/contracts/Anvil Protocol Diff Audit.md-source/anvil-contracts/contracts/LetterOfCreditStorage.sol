// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "./interfaces/ICollateral.sol";
import "./interfaces/ILetterOfCredit.sol";

/**
 * @title Contract specifying all ordered storage used by the existing LetterOfCredit contract proxy to avoid upgrade
 * storage collisions. All upgrade target candidates must inherit from this contract before any others.
 *
 * @dev These state variables were pulled verbatim from first LetterOfCredit contract pointed at by Anvil's
 * LetterOfCredit proxy.
 */
abstract contract LetterOfCreditStorage {
    /***********
     * STORAGE *
     ***********/

    /// NB: uint96 stores up to 7.9 x 10^28 and packs tightly with addresses (12 + 20 = 32 bytes).
    uint96 internal locNonce;

    /// Max age of oracle update.
    /// NB: uint16 gets us up to ~18hrs, which should be plenty. If our oracle is that stale we have very large problems.
    uint16 public maxPriceUpdateSecondsAgo;

    /// Extending a LOC can make it so that the total duration of any given LOC may be larger than this, but no LOC may
    /// have more than this number of seconds remaining.
    uint32 public maxLocDurationSeconds;

    /// The ICollateral contract to use for new LOCs, after which, it is stored on the LOC referenced.
    ICollateral public collateralContract;
    // The IPriceOracle to use for all price interactions (NB: for both new and existing LOCs).
    IPriceOracle public priceOracle;

    /// id (nonce) => Letter of Credit
    mapping(uint96 id => LOC letterOfCredit) internal locs;

    /// Credited Token Address => token available for use as LOC credited tokens and its limits for use.
    mapping(address creditedTokenAddress => CreditedToken creditedToken) internal creditedTokens;

    /// collateral token address => credited token address => CollateralFactor.
    mapping(address collateralTokenAddress => mapping(address creditedTokenAddress => CollateralFactor collateralFactor))
        internal collateralToCreditedToCollateralFactors;

    /*******************
     * STORAGE STRUCTS *
     *******************/

    struct CreditedToken {
        uint256 minPerDynamicLOC;
        uint256 maxPerDynamicLOC;
        uint256 globalMaxInDynamicUse;
        uint256 globalAmountInDynamicUse;
    }

    struct CollateralFactor {
        uint16 creationCollateralFactorBasisPoints;
        uint16 collateralFactorBasisPoints;
        uint16 liquidatorIncentiveBasisPoints;
    }

    struct LOC {
        uint96 collateralId;
        address creator;
        // --- storage slot separator
        address beneficiary;
        // NB: uint32 gets us to the year 2106. If we hit that, redeploy.
        uint32 expirationTimestamp;
        uint16 collateralFactorBasisPoints;
        uint16 liquidatorIncentiveBasisPoints;
        // --- storage slot separator
        ICollateral collateralContract;
        address collateralTokenAddress;
        uint256 collateralTokenAmount;
        uint256 claimableCollateral;
        address creditedTokenAddress;
        uint256 creditedTokenAmount;
    }
}
