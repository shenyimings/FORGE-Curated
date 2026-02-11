// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StvPool} from "./StvPool.sol";
import {IVaultHub} from "./interfaces/core/IVaultHub.sol";
import {IWstETH} from "./interfaces/core/IWstETH.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title StvStETHPool
 * @notice Extended STV pool with (w)stETH minting, liability management, and rebalancing capabilities
 * @dev Allows users to mint (w)stETH against their deposits with configurable reserve ratios
 */
contract StvStETHPool is StvPool {
    event StethSharesMinted(address indexed account, uint256 stethShares);
    event StethSharesBurned(address indexed account, uint256 stethShares);
    event StethSharesRebalanced(address indexed account, uint256 stethShares, uint256 stvBurned);
    event SocializedLoss(uint256 stv, uint256 assets, uint256 maxLossSocializationBP);
    event VaultParametersUpdated(uint256 newReserveRatioBP, uint256 newForcedRebalanceThresholdBP);
    event MaxLossSocializationUpdated(uint256 newMaxLossSocializationBP);

    error InsufficientMintingCapacity();
    error InsufficientStethShares();
    error InsufficientBalance();
    error InsufficientReservedBalance();
    error InsufficientMintedShares();
    error InsufficientExceedingShares();
    error InsufficientStv();
    error ZeroArgument();
    error CannotRebalanceWithdrawalQueue();
    error CannotTransferLiabilityToWithdrawalQueue();
    error UndercollateralizedAccount();
    error CollateralizedAccount();
    error ExcessiveLossSocialization();
    error SameValue();
    error InvalidValue();

    bytes32 public constant MINTING_FEATURE = keccak256("MINTING_FEATURE");
    bytes32 public constant MINTING_PAUSE_ROLE = keccak256("MINTING_PAUSE_ROLE");
    bytes32 public constant MINTING_RESUME_ROLE = keccak256("MINTING_RESUME_ROLE");

    bytes32 public constant LOSS_SOCIALIZER_ROLE = keccak256("LOSS_SOCIALIZER_ROLE");

    /// @notice The gap between the reserve ratio in Staking Vault and Pool (in basis points)
    uint256 public immutable RESERVE_RATIO_GAP_BP;

    IWstETH public immutable WSTETH;

    /// @custom:storage-location erc7201:pool.storage.StvStETHPool
    struct StvStETHPoolStorage {
        mapping(address => uint256) mintedStethShares;
        uint256 totalMintedStethShares;
        uint16 poolReserveRatioBP;
        uint16 poolForcedRebalanceThresholdBP;
        uint16 maxLossSocializationBP;
    }

    // keccak256(abi.encode(uint256(keccak256("pool.storage.StvStETHPool")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STV_STETH_POOL_STORAGE_LOCATION =
        0xcb955bfb671da6f0ca24747fd5d6827b1540ffa01981f020957afc070cf0eb00;

    function _getStvStETHPoolStorage() internal pure returns (StvStETHPoolStorage storage $) {
        assembly {
            $.slot := STV_STETH_POOL_STORAGE_LOCATION
        }
    }

    constructor(
        address _dashboard,
        bool _allowListEnabled,
        uint256 _reserveRatioGapBP,
        address _withdrawalQueue,
        address _distributor,
        bytes32 _poolType
    ) StvPool(_dashboard, _allowListEnabled, _withdrawalQueue, _distributor, _poolType) {
        RESERVE_RATIO_GAP_BP = _reserveRatioGapBP;
        WSTETH = IWstETH(DASHBOARD.WSTETH());

        // Pause features in implementation
        _pauseFeature(MINTING_FEATURE);
    }

    function initialize(address _owner, string memory _name, string memory _symbol) public override initializer {
        _initializeBasePool(_owner, _name, _symbol);

        // Approve max to the Dashboard for burning
        STETH.approve(address(DASHBOARD), type(uint256).max);
        WSTETH.approve(address(DASHBOARD), type(uint256).max);

        // Sync reserve ratio and forced rebalance threshold from the VaultHub
        syncVaultParameters();
    }

    // =================================================================================
    // DEPOSIT
    // =================================================================================

    /**
     * @notice Deposit native ETH and receive stv, minting a specific amount of stETH shares
     * @param _referral Address of the referral (if any)
     * @param _stethSharesToMint Optional amount of stETH shares to mint (18 decimals)
     * @return stv Amount of stv minted (27 decimals)
     */
    function depositETHAndMintStethShares(address _referral, uint256 _stethSharesToMint)
        external
        payable
        virtual
        returns (uint256 stv)
    {
        stv = depositETH(msg.sender, _referral);
        if (_stethSharesToMint != 0) mintStethShares(_stethSharesToMint);
    }

    /**
     * @notice Deposit native ETH and receive stv, minting a specific amount of wstETH
     * @param _referral Address of the referral (if any)
     * @param _wstethToMint Optional amount of wstETH to mint (18 decimals)
     * @return stv Amount of stv minted (27 decimals)
     */
    function depositETHAndMintWsteth(address _referral, uint256 _wstethToMint)
        external
        payable
        virtual
        returns (uint256 stv)
    {
        stv = depositETH(msg.sender, _referral);
        if (_wstethToMint != 0) mintWsteth(_wstethToMint);
    }

    // =================================================================================
    // WITHDRAWALS
    // =================================================================================

    /**
     * @notice Calculate the amount of assets that can be unlocked if a specified amount of stETH shares is burned
     * @param _account The address of the account
     * @param _stethSharesToBurn The amount of stETH shares to burn
     * @return assets The amount of assets that can be unlocked (18 decimals)
     */
    function unlockedAssetsOf(address _account, uint256 _stethSharesToBurn) public view returns (uint256 assets) {
        uint256 mintedStethShares = mintedStethSharesOf(_account);
        if (mintedStethShares < _stethSharesToBurn) revert InsufficientStethShares();

        uint256 mintedStethSharesAfter = mintedStethShares - _stethSharesToBurn;
        uint256 minLockedAssetsAfter = calcAssetsToLockForStethShares(mintedStethSharesAfter);
        assets = Math.saturatingSub(assetsOf(_account), minLockedAssetsAfter);
    }

    /**
     * @notice Calculate the amount of unlocked assets for an account
     * @param _account The address of the account
     * @return assets The amount of assets (18 decimals)
     */
    function unlockedAssetsOf(address _account) public view returns (uint256 assets) {
        assets = unlockedAssetsOf(_account, 0);
    }

    /**
     * @notice Calculate the amount of stv that can be unlocked if a specified amount of stETH shares is burned
     * @param _account The address of the account
     * @param _stethSharesToBurn The amount of stETH shares to burn
     * @return stv The amount of stv that can be unlocked (27 decimals)
     */
    function unlockedStvOf(address _account, uint256 _stethSharesToBurn) public view returns (uint256 stv) {
        stv = _convertToStv(unlockedAssetsOf(_account, _stethSharesToBurn), Math.Rounding.Floor);
    }

    /**
     * @notice Calculate the amount of unlocked stv for an account
     * @param _account The address of the account
     * @return stv The amount of stv (27 decimals)
     */
    function unlockedStvOf(address _account) public view returns (uint256 stv) {
        stv = unlockedStvOf(_account, 0);
    }

    /**
     * @notice Calculate the amount of stETH shares to burn to unlock a given amount of stv
     * @param _account The address of the account
     * @param _stv The amount of stv to unlock
     * @return stethShares The corresponding amount of stETH shares needed to burn (18 decimals)
     */
    function stethSharesToBurnForStvOf(address _account, uint256 _stv) external view returns (uint256 stethShares) {
        if (_stv == 0) return 0;

        uint256 currentBalance = balanceOf(_account);
        if (currentBalance < _stv) revert InsufficientBalance();

        uint256 balanceAfter = currentBalance - _stv;
        uint256 maxStethSharesAfter = calcStethSharesToMintForStv(balanceAfter);
        stethShares = Math.saturatingSub(mintedStethSharesOf(_account), maxStethSharesAfter);
    }

    /**
     * @notice Transfer stv with liability from user to WithdrawalQueue contract when enqueuing withdrawal requests
     * @param _from Address of the user
     * @param _stv Amount of stv to transfer (27 decimals)
     * @param _stethShares Amount of stETH shares liability to transfer (18 decimals)
     * @dev Ensures that the transferred stv covers the minimum required to lock for the transferred stETH shares liability
     * @dev Can only be called by the WithdrawalQueue contract
     * @dev Requires fresh oracle report, which is checked in the Withdrawal Queue
     */
    function transferFromWithLiabilityForWithdrawalQueue(address _from, uint256 _stv, uint256 _stethShares) external {
        _checkOnlyWithdrawalQueue();
        _transferWithLiability(_from, address(WITHDRAWAL_QUEUE), _stv, _stethShares);
    }

    function _checkMinStvToLock(uint256 _stv, uint256 _stethShares) internal view {
        uint256 minStvAmountToLock = calcStvToLockForStethShares(_stethShares);
        if (_stv < minStvAmountToLock) revert InsufficientStv();
    }

    // =================================================================================
    // ASSETS
    // =================================================================================

    /**
     * @notice Total assets managed by the pool
     * @return assets Total assets (18 decimals)
     * @dev Includes total assets + total exceeding minted stETH
     */
    function totalAssets() public view override returns (uint256 assets) {
        /// As a result of the rebalancing initiated in the Staking Vault, bypassing the Wrapper,
        /// part of the total liability can be reduced at the expense of the Staking Vault's assets.
        ///
        /// As a result of this operation, the total liabilityShares on the Staking Vault will decrease,
        /// while mintedStethShares will remain the same, as will the users' debts on these obligations.
        /// The difference between these two values is the stETH that users owe to Wrapper, but which
        /// should not be returned to Staking Vault, but should be distributed among all participants
        /// in exchange for the withdrawn ETH.
        ///
        /// Thus, in rare situations, StvStETHPool may have two assets: ETH and stETH, which are
        /// distributed among all users in proportion to their shares.

        uint256 exceedingMintedSteth = totalExceedingMintedSteth();

        /// total assets = nominal assets + exceeding minted steth - unassigned liability steth
        ///
        /// exceeding minted steth = minted steth on wrapper - liability on vault
        /// unassigned liability steth = liability on vault - minted steth on wrapper
        /// so only one of these values can be > 0 at any time
        if (exceedingMintedSteth > 0) {
            assets = totalNominalAssets() + exceedingMintedSteth;
        } else {
            assets = Math.saturatingSub(totalNominalAssets(), totalUnassignedLiabilitySteth());
        }
    }

    // =================================================================================
    // MINTED STETH SHARES
    // =================================================================================

    /**
     * @notice Total stETH shares minted by the pool
     * @return stethShares Total stETH shares minted (18 decimals)
     */
    function totalMintedStethShares() public view returns (uint256 stethShares) {
        stethShares = _getStvStETHPoolStorage().totalMintedStethShares;
    }

    /**
     * @notice Amount of stETH shares minted by the pool for a specific account
     * @param _account The address of the account
     * @return stethShares Amount of stETH shares minted (18 decimals)
     */
    function mintedStethSharesOf(address _account) public view returns (uint256 stethShares) {
        stethShares = _getStvStETHPoolStorage().mintedStethShares[_account];
    }

    /**
     * @notice Calculate the total minting capacity in stETH shares for a specific account
     * @param _account The address of the account
     * @return stethShares The total minting capacity in stETH shares
     */
    function totalMintingCapacitySharesOf(address _account) external view returns (uint256 stethShares) {
        stethShares = calcStethSharesToMintForAssets(assetsOf(_account));
    }

    /**
     * @notice Calculate the remaining minting capacity in stETH shares for a specific account
     * @param _account The address of the account
     * @param _ethToFund The amount of ETH to fund
     * @return stethShares The remaining minting capacity in stETH shares
     */
    function remainingMintingCapacitySharesOf(address _account, uint256 _ethToFund)
        public
        view
        returns (uint256 stethShares)
    {
        // Simulate depositing ETH to account for rounded down assets after conversion
        uint256 stvForAssets = _convertToStv(_ethToFund, Math.Rounding.Floor);
        uint256 ethRoundedDown = _convertToAssets(stvForAssets);

        uint256 stethSharesForAssets = calcStethSharesToMintForAssets(assetsOf(_account) + ethRoundedDown);
        stethShares = Math.saturatingSub(stethSharesForAssets, mintedStethSharesOf(_account));
    }

    /**
     * @notice Mint wstETH up to the user's minting capacity
     * @param _wsteth The amount of wstETH to mint
     * @dev Note that minted wstETH may not be enough to cover the full obligation in stETH shares because of rounding error
     * on WSTETH contract during unwrapping. The dust from rounding accumulates on the WSTETH contract during unwrapping
     */
    function mintWsteth(uint256 _wsteth) public {
        _checkFeatureNotPaused(MINTING_FEATURE);
        _checkRemainingMintingCapacityOf(msg.sender, _wsteth);

        _increaseMintedStethShares(msg.sender, _wsteth);
        DASHBOARD.mintWstETH(msg.sender, _wsteth);
    }

    /**
     * @notice Mint stETH shares up to the user's minting capacity
     * @param _stethShares The amount of stETH shares to mint
     */
    function mintStethShares(uint256 _stethShares) public {
        _checkFeatureNotPaused(MINTING_FEATURE);
        _checkRemainingMintingCapacityOf(msg.sender, _stethShares);

        _increaseMintedStethShares(msg.sender, _stethShares);
        DASHBOARD.mintShares(msg.sender, _stethShares);
    }

    /**
     * @notice Burn wstETH to reduce the user's minted stETH obligation
     * @param _wsteth The amount of wstETH to burn
     * @dev Note that minted wstETH may not be enough to cover the full obligation in stETH shares because of rounding error
     * on WSTETH contract during unwrapping. The dust from rounding accumulates on the WSTETH contract during unwrapping
     */
    function burnWsteth(uint256 _wsteth) external {
        /// @dev Simulate conversions during unwrapping to account for possible reduction due to rounding errors
        uint256 unwrappedSteth = _getPooledEthByShares(_wsteth);
        uint256 unwrappedStethShares = _getSharesByPooledEth(unwrappedSteth);
        _decreaseMintedStethShares(msg.sender, unwrappedStethShares);

        // Transfer on WSTETH contract always return true or revert
        assert(WSTETH.transferFrom(msg.sender, address(this), _wsteth));
        DASHBOARD.burnWstETH(_wsteth);
    }

    /**
     * @notice Burn stETH shares to reduce the user's minted stETH obligation
     * @param _stethShares The amount of stETH shares to burn
     */
    function burnStethShares(uint256 _stethShares) external {
        _decreaseMintedStethShares(msg.sender, _stethShares);
        STETH.transferSharesFrom(msg.sender, address(this), _stethShares);
        DASHBOARD.burnShares(_stethShares);
    }

    function _checkRemainingMintingCapacityOf(address _account, uint256 _stethShares) internal view {
        if (remainingMintingCapacitySharesOf(_account, 0) < _stethShares) revert InsufficientMintingCapacity();
    }

    function _increaseMintedStethShares(address _account, uint256 _stethShares) internal {
        StvStETHPoolStorage storage $ = _getStvStETHPoolStorage();

        if (_stethShares == 0) revert ZeroArgument();

        $.totalMintedStethShares += _stethShares;
        $.mintedStethShares[_account] += _stethShares;

        emit StethSharesMinted(_account, _stethShares);
    }

    function _decreaseMintedStethShares(address _account, uint256 _stethShares) internal {
        StvStETHPoolStorage storage $ = _getStvStETHPoolStorage();

        if (_stethShares == 0) revert ZeroArgument();
        if ($.mintedStethShares[_account] < _stethShares) revert InsufficientMintedShares();

        $.totalMintedStethShares -= _stethShares;
        $.mintedStethShares[_account] -= _stethShares;

        emit StethSharesBurned(_account, _stethShares);
    }

    function _transferStethSharesLiability(address _from, address _to, uint256 _stethShares) internal {
        StvStETHPoolStorage storage $ = _getStvStETHPoolStorage();

        if (_stethShares == 0) revert ZeroArgument();
        if ($.mintedStethShares[_from] < _stethShares) revert InsufficientMintedShares();

        $.mintedStethShares[_from] -= _stethShares;
        $.mintedStethShares[_to] += _stethShares;

        emit StethSharesBurned(_from, _stethShares);
        emit StethSharesMinted(_to, _stethShares);
    }

    /**
     * @notice Calculate the amount of stETH shares to mint for a given amount of assets
     * @param _assets The amount of assets (18 decimals)
     * @return stethShares The corresponding amount of stETH shares to mint (18 decimals)
     */
    function calcStethSharesToMintForAssets(uint256 _assets) public view returns (uint256 stethShares) {
        uint256 maxStethToMint =
            Math.mulDiv(_assets, TOTAL_BASIS_POINTS - poolReserveRatioBP(), TOTAL_BASIS_POINTS, Math.Rounding.Floor);

        stethShares = _getSharesByPooledEth(maxStethToMint);
    }

    /**
     * @notice Calculate the amount of stETH shares to mint for a given amount of stv
     * @param _stv The amount of stv (27 decimals)
     * @return stethShares The corresponding amount of stETH shares to mint (18 decimals)
     */
    function calcStethSharesToMintForStv(uint256 _stv) public view returns (uint256 stethShares) {
        stethShares = calcStethSharesToMintForAssets(_convertToAssets(_stv));
    }

    /**
     * @notice Calculate the min amount of assets to lock for a given amount of stETH shares
     * @param _stethShares The amount of stETH shares (18 decimals)
     * @return assetsToLock The min amount of assets to lock (18 decimals)
     * @dev Use the ceiling rounding to ensure enough assets are locked
     */
    function calcAssetsToLockForStethShares(uint256 _stethShares) public view returns (uint256 assetsToLock) {
        if (_stethShares == 0) return 0;

        assetsToLock = Math.mulDiv(
            _getPooledEthBySharesRoundUp(_stethShares),
            TOTAL_BASIS_POINTS,
            TOTAL_BASIS_POINTS - poolReserveRatioBP(),
            Math.Rounding.Ceil
        );
    }

    /**
     * @notice Calculate the min amount of stv to lock for a given amount of stETH shares
     * @param _stethShares The amount of stETH shares (18 decimals)
     * @return stvToLock The min amount of stv to lock (27 decimals)
     */
    function calcStvToLockForStethShares(uint256 _stethShares) public view returns (uint256 stvToLock) {
        stvToLock = _convertToStv(calcAssetsToLockForStethShares(_stethShares), Math.Rounding.Ceil);
    }

    // =================================================================================
    // VAULT PARAMETERS
    // =================================================================================

    /**
     * @notice Reserve ratio in basis points with the gap applied
     * @return reserveRatio The reserve ratio in basis points
     */
    function poolReserveRatioBP() public view returns (uint256 reserveRatio) {
        reserveRatio = uint256(_getStvStETHPoolStorage().poolReserveRatioBP);
    }

    /**
     * @notice Forced rebalance threshold in basis points
     * @return threshold The forced rebalance threshold in basis points
     */
    function poolForcedRebalanceThresholdBP() public view returns (uint256 threshold) {
        threshold = uint256(_getStvStETHPoolStorage().poolForcedRebalanceThresholdBP);
    }

    /**
     * @notice Sync reserve ratio and forced rebalance threshold from VaultHub
     * @dev Permissionless method to keep reserve ratio and forced rebalance threshold in sync with VaultHub
     * @dev Adds a gap defined by RESERVE_RATIO_GAP_BP to VaultHub's values
     */
    function syncVaultParameters() public {
        IVaultHub.VaultConnection memory connection = DASHBOARD.vaultConnection();

        uint256 maxReserveRatioBP = TOTAL_BASIS_POINTS - 1;
        uint256 maxForcedRebalanceThresholdBP = maxReserveRatioBP - 1;

        /// Invariants from the OperatorGrid
        assert(connection.reserveRatioBP > 0);
        assert(connection.reserveRatioBP <= maxReserveRatioBP);
        assert(connection.forcedRebalanceThresholdBP > 0);
        assert(connection.forcedRebalanceThresholdBP < connection.reserveRatioBP);

        uint16 newPoolReserveRatioBP =
            uint16(Math.min(connection.reserveRatioBP + RESERVE_RATIO_GAP_BP, maxReserveRatioBP));
        uint16 newPoolForcedRebalanceThresholdBP = uint16(
            Math.min(connection.forcedRebalanceThresholdBP + RESERVE_RATIO_GAP_BP, maxForcedRebalanceThresholdBP)
        );

        StvStETHPoolStorage storage $ = _getStvStETHPoolStorage();

        if (
            newPoolReserveRatioBP == $.poolReserveRatioBP
                && newPoolForcedRebalanceThresholdBP == $.poolForcedRebalanceThresholdBP
        ) {
            return;
        }

        $.poolReserveRatioBP = newPoolReserveRatioBP;
        $.poolForcedRebalanceThresholdBP = newPoolForcedRebalanceThresholdBP;

        emit VaultParametersUpdated(newPoolReserveRatioBP, newPoolForcedRebalanceThresholdBP);
    }

    // =================================================================================
    // EXCEEDING MINTED STETH
    // =================================================================================

    /**
     * @notice Amount of minted stETH shares exceeding the Staking Vault's liability
     * @return stethShares Amount of exceeding stETH shares (18 decimals)
     * @dev May occur if rebalancing happens on the Staking Vault bypassing the Wrapper
     */
    function totalExceedingMintedStethShares() public view returns (uint256 stethShares) {
        stethShares = Math.saturatingSub(totalMintedStethShares(), totalLiabilityShares());
    }

    /**
     * @notice Amount of minted stETH exceeding the Staking Vault's liability
     * @return steth Amount of exceeding stETH (18 decimals)
     * @dev May occur if rebalancing happens on the Staking Vault bypassing the Wrapper
     */
    function totalExceedingMintedSteth() public view returns (uint256 steth) {
        steth = _getPooledEthByShares(totalExceedingMintedStethShares());
    }

    // =================================================================================
    // UNASSIGNED LIABILITY
    // =================================================================================

    /**
     * @notice Total unassigned liability shares in the Staking Vault
     * @return unassignedLiabilityShares Total unassigned liability shares (18 decimals)
     * @dev Overridden method from StvPool to include unassigned liability shares
     * @dev May occur if liability was transferred from another Staking Vault
     */
    function totalUnassignedLiabilityShares() public view override returns (uint256 unassignedLiabilityShares) {
        unassignedLiabilityShares = Math.saturatingSub(totalLiabilityShares(), totalMintedStethShares());
    }

    // =================================================================================
    // REBALANCE
    // =================================================================================

    /**
     * @notice Rebalance the user's minted stETH shares by burning stv
     * @param _stethShares The amount of stETH shares to rebalance
     * @param _maxStvToBurn The maximum amount of stv to burn for rebalancing
     * @return stvBurned The actual amount of stv burned for rebalancing
     * @dev First, rebalances internally by burning stv, which decreases exceeding shares (if any)
     * @dev Second, if there are remaining liability shares, rebalances Staking Vault
     * @dev Requires fresh oracle report, which is checked in the Withdrawal Queue
     */
    function rebalanceMintedStethSharesForWithdrawalQueue(uint256 _stethShares, uint256 _maxStvToBurn)
        public
        returns (uint256 stvBurned)
    {
        _checkOnlyWithdrawalQueue();
        stvBurned = _rebalanceMintedStethShares(msg.sender, _stethShares, _maxStvToBurn);
    }

    /**
     * @notice Force rebalance the user's minted stETH shares if the reserve ratio threshold is breached
     * @param _account The address of the account to rebalance
     * @return stvBurned The actual amount of stv burned for rebalancing
     * @dev Permissionless method to rebalance any account that breached the health threshold
     * @dev Requires fresh oracle report to price stv accurately
     */
    function forceRebalance(address _account) external returns (uint256 stvBurned) {
        if (_account == address(WITHDRAWAL_QUEUE)) revert CannotRebalanceWithdrawalQueue();
        _checkFreshReport();

        (uint256 stethShares, uint256 stv, bool isUndercollateralized) = previewForceRebalance(_account);
        if (isUndercollateralized) revert UndercollateralizedAccount();

        stvBurned = _rebalanceMintedStethShares(_account, stethShares, stv);
    }

    /**
     * @notice Force rebalance undercollateralized account and socialize the remaining loss to all pool participants
     * @param _account The address of the account to rebalance
     * @return stvBurned The actual amount of stv burned for rebalancing
     * @dev Requires fresh oracle report to price stv accurately
     */
    function forceRebalanceAndSocializeLoss(address _account) external returns (uint256 stvBurned) {
        if (_account == address(WITHDRAWAL_QUEUE)) revert CannotRebalanceWithdrawalQueue();
        _checkRole(LOSS_SOCIALIZER_ROLE, msg.sender);
        _checkFreshReport();

        (uint256 stethShares, uint256 stv, bool isUndercollateralized) = previewForceRebalance(_account);
        if (!isUndercollateralized) revert CollateralizedAccount();

        stvBurned = _rebalanceMintedStethShares(_account, stethShares, stv);
    }

    /**
     * @notice Preview the amount of stETH shares and stv needed to force rebalance the user's position
     * @param _account The address of the account to preview
     * @return stethShares The amount of stETH shares to rebalance, limited by available assets
     * @return stv The amount of stv needed to burn in exchange for the stETH shares, limited by user's stv balance
     * @return isUndercollateralized True if the user's assets are insufficient to cover the liability
     * @dev Requires fresh oracle report to price stv accurately (not enforced in this method, so caller must ensure it)
     */
    function previewForceRebalance(address _account)
        public
        view
        returns (uint256 stethShares, uint256 stv, bool isUndercollateralized)
    {
        uint256 stethSharesLiability = mintedStethSharesOf(_account);
        uint256 stvBalance = balanceOf(_account);
        uint256 assets = assetsOf(_account);

        /// Position is healthy, nothing to rebalance
        if (!_isThresholdBreached(assets, stethSharesLiability)) return (0, 0, false);

        /// Rebalance (swap steth liability for stv at the current rate) user to the reserve ratio level
        ///
        /// To calculate how much steth shares to rebalance to reach the target reserve ratio, we can set up the equation:
        /// (1 - reserveRatio) = (liabilityShares - x) / (assetsInStethShares - x)
        ///
        /// Rearranging the equation to solve for x gives us:
        /// x = (liabilityShares - (1 - reserveRatio) * assetsInStethShares) / reserveRatio
        uint256 reserveRatioBP_ = poolReserveRatioBP();
        uint256 assetsInStethShares = _getSharesByPooledEth(assets);
        uint256 targetStethSharesToRebalance = Math.ceilDiv(
            /// Shouldn't underflow as threshold breach is already checked
            stethSharesLiability * TOTAL_BASIS_POINTS - (TOTAL_BASIS_POINTS - reserveRatioBP_) * assetsInStethShares,
            reserveRatioBP_
        );

        /// If the target rebalance amount exceeds the liability itself, the user is undercollateralized
        if (targetStethSharesToRebalance > stethSharesLiability) {
            targetStethSharesToRebalance = stethSharesLiability;
            isUndercollateralized = true;
        }

        /// Limit rebalance to available assets
        ///
        /// First, the rebalancing will use exceeding minted steth shares, bringing the vault closer to minted steth == liability,
        /// then the rebalancing mechanism on the vault, which is limited by available balance in the staking vault
        stethShares = totalExceedingMintedStethShares() + _getSharesByPooledEth(VAULT.availableBalance());
        stethShares = Math.min(targetStethSharesToRebalance, stethShares);

        uint256 stethToRebalance = _getPooledEthBySharesRoundUp(stethShares);
        uint256 stvRequired = _convertToStv(stethToRebalance, Math.Rounding.Ceil);

        stv = Math.min(stvRequired, stvBalance);
        isUndercollateralized = isUndercollateralized || stvRequired > stvBalance;
    }

    /**
     * @notice Check if the user's minted stETH shares are healthy (not breaching the threshold)
     * @param _account The address of the account to check
     * @return isHealthy True if the account is healthy, false if the forced rebalance threshold is breached
     */
    function isHealthyOf(address _account) external view returns (bool isHealthy) {
        isHealthy = !_isThresholdBreached(assetsOf(_account), mintedStethSharesOf(_account));
    }

    /**
     * @notice Reduce user's stETH shares liability by burning stv when exceeding minted stETH exists
     * @param _stethShares The amount of stETH shares liability to reduce (18 decimals)
     * @return stvBurned The amount of stv burned (27 decimals)
     * @dev Requires fresh oracle report to price stv accurately
     * @dev When totalMintedStethShares > totalLiabilityShares (exceeding shares exist), users can voluntarily
     * rebalance their liability directly against their stv within the exceeding amount
     *
     * @dev WARNING: Front-running risk. Exceeding shares are a shared pool-wide limit. Multiple users
     * competing for limited exceeding shares may have transactions revert with `InsufficientExceedingShares`.
     * This is accepted: scenario is rare (requires vault liability < pool minted shares), no value extraction,
     * and worst case is transaction revert with option to retry with smaller amount.
     */
    function rebalanceExceedingMintedStethShares(uint256 _stethShares) external returns (uint256 stvBurned) {
        _checkFreshReport();

        if (_stethShares == 0) revert ZeroArgument();
        if (_stethShares > mintedStethSharesOf(msg.sender)) revert InsufficientMintedShares();
        if (_stethShares > totalExceedingMintedStethShares()) revert InsufficientExceedingShares();

        uint256 stethToRebalance = _getPooledEthBySharesRoundUp(_stethShares);
        stvBurned = _convertToStv(stethToRebalance, Math.Rounding.Ceil);

        _decreaseMintedStethShares(msg.sender, _stethShares);
        _burnUnsafe(msg.sender, stvBurned);

        emit StethSharesRebalanced(msg.sender, _stethShares, stvBurned);
    }

    /**
     * @dev Requires fresh oracle report to price stv accurately
     */
    function _rebalanceMintedStethShares(address _account, uint256 _stethShares, uint256 _maxStvToBurn)
        internal
        returns (uint256 stvToBurn)
    {
        _checkNoUnassignedLiability();
        _checkNoBadDebt();

        if (_stethShares == 0) revert ZeroArgument();
        if (_stethShares > mintedStethSharesOf(_account)) revert InsufficientMintedShares();

        uint256 exceedingStethShares = totalExceedingMintedStethShares();
        uint256 remainingStethShares = Math.saturatingSub(_stethShares, exceedingStethShares);
        uint256 ethToRebalance = _getPooledEthBySharesRoundUp(_stethShares);
        uint256 ethForMaxStvToBurn = _convertToAssets(_maxStvToBurn);
        stvToBurn = _convertToStv(ethToRebalance, Math.Rounding.Ceil);

        if (remainingStethShares > 0) DASHBOARD.rebalanceVaultWithShares(remainingStethShares);

        if (stvToBurn > _maxStvToBurn) {
            _checkAllowedLossSocializationPortion(stvToBurn, _maxStvToBurn);

            emit SocializedLoss(
                stvToBurn - _maxStvToBurn,
                ethToRebalance - ethForMaxStvToBurn,
                _getStvStETHPoolStorage().maxLossSocializationBP
            );
            stvToBurn = _maxStvToBurn;
        }

        _decreaseMintedStethShares(_account, _stethShares);
        _burnUnsafe(_account, stvToBurn);

        emit StethSharesRebalanced(_account, _stethShares, stvToBurn);
    }

    function _isThresholdBreached(uint256 _assets, uint256 _stethShares) internal view returns (bool isBreached) {
        if (_stethShares == 0) return false;

        uint256 assetsThreshold = Math.mulDiv(
            _getPooledEthBySharesRoundUp(_stethShares),
            TOTAL_BASIS_POINTS,
            TOTAL_BASIS_POINTS - poolForcedRebalanceThresholdBP(),
            Math.Rounding.Ceil
        );

        isBreached = _assets < assetsThreshold;
    }

    function _checkAllowedLossSocializationPortion(uint256 stvRequired, uint256 stvAvailable) internal view {
        // It's guaranteed that stvRequired > stvAvailable here
        uint256 portionToSocializeBP =
            Math.mulDiv(stvRequired - stvAvailable, TOTAL_BASIS_POINTS, stvRequired, Math.Rounding.Ceil);

        if (portionToSocializeBP > _getStvStETHPoolStorage().maxLossSocializationBP) {
            revert ExcessiveLossSocialization();
        }
    }

    // =================================================================================
    // LOSS SOCIALIZATION LIMITER
    // =================================================================================

    // During rebalancing, it's possible that the stv available for burning is not sufficient to cover the entire liability.
    // This may be due to a sharp drop in the stv price, which has resulted in an individual account or a request in Withdrawal Queue
    // no longer being collateralized (assets < liability).
    //
    // The limiter on loss socialization is introduced to prevent excessive losses from being socialized to all pool participants.
    // The limiter is defined as a maximum portion of the loss that can be socialized, expressed in basis points (BP).
    //
    // The default value is set to 0 BP, meaning that no loss socialization is allowed without explicit permission.

    /**
     * @notice Maximum allowed loss socialization in basis points
     * @return maxSocializablePortionBP The maximum allowed portion of loss to be socialized in basis points
     * @dev Used to limit the portion of loss that can be socialized to all pool participants during rebalance
     */
    function maxLossSocializationBP() external view returns (uint256 maxSocializablePortionBP) {
        maxSocializablePortionBP = uint256(_getStvStETHPoolStorage().maxLossSocializationBP);
    }

    /**
     * @notice Set the maximum allowed loss socialization in basis points
     * @param _maxSocializablePortionBP The new maximum allowed loss socialization in basis points
     * @dev Sets the maximum portion of loss that can be socialized to all pool participants during rebalance
     * @dev Can only be called by accounts with the DEFAULT_ADMIN_ROLE
     */
    function setMaxLossSocializationBP(uint16 _maxSocializablePortionBP) external {
        _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);

        if (_maxSocializablePortionBP > TOTAL_BASIS_POINTS) revert InvalidValue();

        StvStETHPoolStorage storage $ = _getStvStETHPoolStorage();
        if (_maxSocializablePortionBP == $.maxLossSocializationBP) revert SameValue();
        $.maxLossSocializationBP = _maxSocializablePortionBP;

        emit MaxLossSocializationUpdated(_maxSocializablePortionBP);
    }

    // =================================================================================
    // TRANSFER WITH LIABILITY
    // =================================================================================

    /**
     * @notice Transfer stv along with stETH shares liability
     * @param _to The address to transfer to
     * @param _stv The amount of stv to transfer
     * @param _stethShares The amount of stETH shares liability to transfer
     * @return success True if the transfer was successful
     * @dev Ensures that the transferred stv covers the minimum required to lock for the transferred stETH shares liability
     * @dev Requires fresh oracle report to price stv accurately
     */
    function transferWithLiability(address _to, uint256 _stv, uint256 _stethShares) external returns (bool success) {
        if (_to == address(WITHDRAWAL_QUEUE)) revert CannotTransferLiabilityToWithdrawalQueue();
        _checkFreshReport();

        _transferWithLiability(msg.sender, _to, _stv, _stethShares);
        success = true;
    }

    function _transferWithLiability(address _from, address _to, uint256 _stv, uint256 _stethShares) internal {
        _checkMinStvToLock(_stv, _stethShares);

        _transferStethSharesLiability(_from, _to, _stethShares);
        _transfer(_from, _to, _stv);
    }

    // =================================================================================
    // ERC20 OVERRIDES
    // =================================================================================

    /**
     * @dev Overridden method from ERC20 to include reserve ratio check
     * @dev Ensures that after any transfer, the sender still has enough reserved balance for their minted stETH shares
     */
    function _update(address _from, address _to, uint256 _value) internal override {
        super._update(_from, _to, _value);

        uint256 mintedStethShares = mintedStethSharesOf(_from);
        if (mintedStethShares == 0) return;

        uint256 stvToLock = calcStvToLockForStethShares(mintedStethShares);

        if (balanceOf(_from) < stvToLock) revert InsufficientReservedBalance();
    }

    // =================================================================================
    // PAUSE / RESUME MINTING
    // =================================================================================

    /**
     * @notice Pause (w)stETH minting
     * @dev Can only be called by accounts with the MINTING_PAUSE_ROLE
     */
    function pauseMinting() external {
        _checkRole(MINTING_PAUSE_ROLE, msg.sender);
        _pauseFeature(MINTING_FEATURE);
    }

    /**
     * @notice Resume (w)stETH minting
     * @dev Can only be called by accounts with the MINTING_RESUME_ROLE
     */
    function resumeMinting() external {
        _checkRole(MINTING_RESUME_ROLE, msg.sender);
        _resumeFeature(MINTING_FEATURE);
    }
}
