// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

uint256 constant DOUBLE_CACHE_LENGTH = 2;

interface IVaultHub is IAccessControl {
    struct VaultConnection {
        // ### 1st slot
        /// @notice address of the vault owner
        address owner;
        /// @notice maximum number of stETH shares that can be minted by vault owner
        uint96 shareLimit;
        // ### 2nd slot
        /// @notice index of the vault in the list of vaults. Indexes are not guaranteed to be stable.
        /// @dev vaultIndex is always greater than 0
        uint96 vaultIndex;
        /// @notice if true, vault is disconnected and fee is not accrued
        uint48 disconnectInitiatedTs;
        /// @notice share of ether that is locked on the vault as an additional reserve
        /// e.g RR=30% means that for 1stETH minted 1/(1-0.3)=1.428571428571428571 ETH is locked on the vault
        uint16 reserveRatioBP;
        /// @notice if vault's reserve decreases to this threshold, it should be force rebalanced
        uint16 forcedRebalanceThresholdBP;
        /// @notice infra fee in basis points
        uint16 infraFeeBP;
        /// @notice liquidity fee in basis points
        uint16 liquidityFeeBP;
        /// @notice reservation fee in basis points
        uint16 reservationFeeBP;
        /// @notice if true, vault owner manually paused the beacon chain deposits
        bool isBeaconDepositsManuallyPaused;
    }
    /// 24 bits gap

    struct VaultRecord {
        // ### 1st slot
        /// @notice latest report for the vault
        Report report;
        // ### 2nd slot
        /// @notice max number of shares that was minted by the vault in current Oracle period
        /// (used to calculate the locked value on the vault)
        uint96 maxLiabilityShares;
        /// @notice liability shares of the vault
        uint96 liabilityShares;
        // ### 3rd and 4th slots
        /// @notice inOutDelta of the vault (all deposits - all withdrawals)
        Int104WithCache[2] inOutDelta; // 2 is the constant DOUBLE_CACHE_LENGTH from RefSlotCache.sol
        // ### 5th slot
        /// @notice the minimal value that the reserve part of the locked can be
        uint128 minimalReserve;
        /// @notice part of liability shares reserved to be burnt as Lido core redemptions
        uint128 redemptionShares;
        // ### 6th slot
        /// @notice cumulative value for Lido fees that accrued on the vault
        uint128 cumulativeLidoFees;
        /// @notice cumulative value for Lido fees that were settled on the vault
        uint128 settledLidoFees;
    }

    struct Report {
        /// @notice total value of the vault
        uint104 totalValue;
        /// @notice inOutDelta of the report
        int104 inOutDelta;
        /// @notice timestamp (in seconds)
        uint48 timestamp;
    }

    struct Int104WithCache {
        int104 value;
        int104 valueOnRefSlot;
        uint48 refSlot;
    }

    function CONNECT_DEPOSIT() external view returns (uint256);

    function vaultsCount() external view returns (uint256);
    function vaultByIndex(uint256 _index) external view returns (address);
    function fund(address vault) external payable;
    function withdraw(address vault, address recipient, uint256 etherAmount) external;
    function totalValue(address vault) external view returns (uint256);
    function withdrawableValue(address vault) external view returns (uint256);
    function requestValidatorExit(address vault, bytes calldata pubkeys) external;
    function triggerValidatorWithdrawals(
        address vault,
        bytes calldata pubkeys,
        uint64[] calldata amounts,
        address refundRecipient
    ) external payable;
    function mintShares(address _vault, address _recipient, uint256 _amountOfShares) external;
    function burnShares(address _vault, uint256 _amountOfShares) external;
    function transferAndBurnShares(address _vault, uint256 _amountOfShares) external;
    function vaultConnection(address _vault) external view returns (VaultConnection memory);
    function vaultRecord(address _vault) external view returns (VaultRecord memory);
    function maxLockableValue(address _vault) external view returns (uint256);
    function isReportFresh(address _vault) external view returns (bool);
    function isVaultConnected(address _vault) external view returns (bool);
    function isPendingDisconnect(address _vault) external view returns (bool);
    function isVaultHealthy(address _vault) external view returns (bool);
    function transferVaultOwnership(address _vault, address _newOwner) external;
    function liabilityShares(address _vault) external view returns (uint256);
    function locked(address _vault) external view returns (uint256);
    function totalMintingCapacityShares(address _vault, int256 _deltaValue) external view returns (uint256);
    function healthShortfallShares(address _vault) external view returns (uint256);
    function obligations(address _vault) external view returns (uint256 sharesToBurn, uint256 feesToSettle);
    function settleableLidoFeesValue(address _vault) external view returns (uint256);
    function badDebtToInternalize() external view returns (uint256);
    function decreaseInternalizedBadDebt(uint256 _amountOfShares) external;

    function connectVault(address _vault) external;
    function setLiabilitySharesTarget(address _vault, uint256 _liabilitySharesTarget) external;
    function updateConnection(
        address _vault,
        uint256 _shareLimit,
        uint16 _reserveRatioBP,
        uint16 _forcedRebalanceThresholdBP,
        uint16 _infraFeeBP,
        uint16 _liquidityFeeBP,
        uint16 _reservationFeeBP
    ) external;
    function disconnect(address _vault) external;
    function voluntaryDisconnect(address _vault) external;

    function applyVaultReport(
        address _vault,
        uint256 _reportTimestamp,
        uint256 _reportTotalValue,
        int256 _reportInOutDelta,
        uint256 _reportCumulativeLidoFees,
        uint256 _reportLiabilityShares,
        uint256 _reportMaxLiabilityShares,
        uint256 _reportSlashingReserve
    ) external;

    function latestReport(address _vault) external view returns (Report memory);

    function socializeBadDebt(address _vaultDonor, address _vaultAcceptor, uint256 _badDebtShares) external;

    function internalizeBadDebt(address _vault) external;

    function rebalance(address _vault, uint256 _shares) external;
    function pauseBeaconChainDeposits(address _vault) external;
    function resumeBeaconChainDeposits(address _vault) external;
    function forceValidatorExit(address _vault, bytes calldata _pubkeys, address _refundRecipient) external payable;
    function forceRebalance(address _vault) external;
    function settleLidoFees(address _vault) external;
    function proveUnknownValidatorToPDG(address _vault, bytes calldata _witness) external;
    function collectERC20FromVault(address _vault, address _token, address _recipient, uint256 _amount) external;

    // -----------------------------
    //           EVENTS
    // -----------------------------

    event VaultConnected(
        address indexed vault, uint256 shareLimit, uint16 reserveRatioBP, uint16 forcedRebalanceThresholdBP
    );
    event VaultConnectionUpdated(
        address indexed vault, uint256 shareLimit, uint16 reserveRatioBP, uint16 forcedRebalanceThresholdBP
    );
    event VaultFeesUpdated(address indexed vault, uint16 infraFeeBP, uint16 liquidityFeeBP, uint16 reservationFeeBP);
    event VaultDisconnectInitiated(address indexed vault);
    event VaultDisconnectCompleted(address indexed vault);
    event VaultDisconnectAborted(address indexed vault, uint256 slashingReserve);
    event VaultReportApplied(
        address indexed vault,
        uint256 reportTimestamp,
        uint256 reportTotalValue,
        int256 reportInOutDelta,
        uint256 reportCumulativeLidoFees,
        uint256 reportLiabilityShares,
        uint256 reportSlashingReserve
    );
    event MintedSharesOnVault(address indexed vault, uint256 amountOfShares, uint256 lockedAmount);
    event BurnedSharesOnVault(address indexed vault, uint256 amountOfShares);
    event VaultRebalanced(address indexed vault, uint256 sharesBurned, uint256 etherWithdrawn);
    event VaultInOutDeltaUpdated(address indexed vault, int256 inOutDelta);
    event ForcedValidatorExitTriggered(address indexed vault, bytes pubkeys, address refundRecipient);
    event VaultOwnershipTransferred(address indexed vault, address indexed newOwner, address indexed oldOwner);
    event LidoFeesSettled(
        address indexed vault, uint256 transferred, uint256 cumulativeLidoFees, uint256 settledLidoFees
    );
    event VaultRedemptionSharesUpdated(address indexed vault, uint256 redemptionShares);
    event BeaconChainDepositsPausedByOwner(address indexed vault);
    event BeaconChainDepositsResumedByOwner(address indexed vault);
    event BadDebtSocialized(address indexed vaultDonor, address indexed vaultAcceptor, uint256 badDebtShares);
    event BadDebtWrittenOffToBeInternalized(address indexed vault, uint256 badDebtShares);

    // -----------------------------
    //           ERRORS
    // -----------------------------

    error AmountExceedsTotalValue(address vault, uint256 totalValue, uint256 withdrawAmount);
    error AmountExceedsWithdrawableValue(address vault, uint256 withdrawable, uint256 requested);
    error NoFundsForForceRebalance(address vault);
    error NoReasonForForceRebalance(address vault);
    error NoUnsettledLidoFeesToSettle(address vault);
    error NoFundsToSettleLidoFees(address vault, uint256 unsettledLidoFees);

    error VaultMintingCapacityExceeded(
        address vault, uint256 totalValue, uint256 liabilityShares, uint256 newRebalanceThresholdBP
    );
    error InsufficientSharesToBurn(address vault, uint256 amount);
    error ShareLimitExceeded(address vault, uint256 expectedSharesAfterMint, uint256 shareLimit);
    error AlreadyConnected(address vault, uint256 index);
    error InsufficientStagedBalance(address vault);
    error NotConnectedToHub(address vault);
    error NotAuthorized();
    error ZeroAddress();
    error ZeroArgument();
    error InvalidBasisPoints(uint256 valueBP, uint256 maxValueBP);
    error ShareLimitTooHigh(uint256 shareLimit, uint256 maxShareLimit);
    error InsufficientValue(address vault, uint256 etherToLock, uint256 maxLockableValue);
    error NoLiabilitySharesShouldBeLeft(address vault, uint256 liabilityShares);
    error NoUnsettledLidoFeesShouldBeLeft(address vault, uint256 unsettledLidoFees);
    error VaultOssified(address vault);
    error VaultInsufficientBalance(address vault, uint256 currentBalance, uint256 expectedBalance);
    error VaultReportStale(address vault);
    error PDGNotDepositor(address vault);
    error VaultHubNotPendingOwner(address vault);
    error HasRedemptionsCannotDeposit(address vault);
    error FeesTooHighCannotDeposit(address vault);
    error UnhealthyVaultCannotDeposit(address vault);
    error VaultIsDisconnecting(address vault);
    error PartialValidatorWithdrawalNotAllowed();
    error ForcedValidatorExitNotAllowed();
    error BadDebtSocializationNotAllowed();
    error VaultNotFactoryDeployed(address vault);
}
