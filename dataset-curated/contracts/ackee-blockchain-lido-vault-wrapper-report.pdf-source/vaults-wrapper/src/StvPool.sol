// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AllowList} from "./AllowList.sol";
import {Distributor} from "./Distributor.sol";
import {WithdrawalQueue} from "./WithdrawalQueue.sol";
import {IDashboard} from "./interfaces/core/IDashboard.sol";
import {IStETH} from "./interfaces/core/IStETH.sol";
import {IStakingVault} from "./interfaces/core/IStakingVault.sol";
import {IVaultHub} from "./interfaces/core/IVaultHub.sol";
import {FeaturePausable} from "./utils/FeaturePausable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title StvPool
 * @notice ERC20 staking vault token pool that accepts ETH deposits and manages withdrawals through a queue
 * @dev Implements a tokenized staking pool where users deposit ETH and receive STV tokens representing their share
 */
contract StvPool is ERC20Upgradeable, AllowList, FeaturePausable {
    // Custom errors
    error ZeroDeposit();
    error InvalidRecipient();
    error NotWithdrawalQueue();
    error NotEnoughToRebalance();
    error UnassignedLiabilityOnVault();
    error VaultInBadDebt();
    error VaultReportStale();

    bytes32 public constant DEPOSITS_FEATURE = keccak256("DEPOSITS_FEATURE");
    bytes32 public constant DEPOSITS_PAUSE_ROLE = keccak256("DEPOSITS_PAUSE_ROLE");
    bytes32 public constant DEPOSITS_RESUME_ROLE = keccak256("DEPOSITS_RESUME_ROLE");

    uint256 public constant TOTAL_BASIS_POINTS = 100_00;

    uint8 private constant DECIMALS = 27;
    uint8 private constant ASSET_DECIMALS = 18;

    IStETH public immutable STETH;
    IDashboard public immutable DASHBOARD;
    IVaultHub public immutable VAULT_HUB;
    IStakingVault public immutable VAULT;

    WithdrawalQueue public immutable WITHDRAWAL_QUEUE;
    Distributor public immutable DISTRIBUTOR;

    bytes32 private immutable POOL_TYPE;

    event Deposit(
        address indexed sender, address indexed recipient, address indexed referral, uint256 assets, uint256 stv
    );

    event UnassignedLiabilityRebalanced(uint256 stethShares, uint256 ethFunded);

    constructor(
        address _dashboard,
        bool _allowListEnabled,
        address _withdrawalQueue,
        address _distributor,
        bytes32 _poolType
    ) AllowList(_allowListEnabled) {
        DASHBOARD = IDashboard(payable(_dashboard));
        VAULT_HUB = IVaultHub(DASHBOARD.VAULT_HUB());
        VAULT = IStakingVault(DASHBOARD.stakingVault());
        WITHDRAWAL_QUEUE = WithdrawalQueue(payable(_withdrawalQueue));
        STETH = IStETH(payable(DASHBOARD.STETH()));
        DISTRIBUTOR = Distributor(_distributor);
        POOL_TYPE = _poolType;

        // Disable initializers since we only support proxy deployment
        _disableInitializers();

        // Pause features in implementation
        _pauseFeature(DEPOSITS_FEATURE);
    }

    function poolType() external view virtual returns (bytes32) {
        return POOL_TYPE;
    }

    function initialize(address _owner, string memory _name, string memory _symbol) public virtual initializer {
        _initializeBasePool(_owner, _name, _symbol);
    }

    function _initializeBasePool(address _owner, string memory _name, string memory _symbol) internal {
        __ERC20_init(_name, _symbol);
        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _initializeAllowList(_owner);

        // Initial vault balance must include the connect deposit
        // Minting stv for it to have clear stv math
        uint256 initialVaultBalance = address(VAULT).balance;
        uint256 connectDeposit = VAULT_HUB.CONNECT_DEPOSIT();
        assert(initialVaultBalance >= connectDeposit);
        assert(totalSupply() == 0);

        uint256 stvToMint = initialVaultBalance * 10 ** (DECIMALS - ASSET_DECIMALS);
        _mint(address(this), stvToMint);
    }

    // =================================================================================
    // ASSETS
    // =================================================================================

    /**
     * @notice Total nominal assets managed by the pool
     * @return assets Total nominal assets (18 decimals)
     */
    function totalNominalAssets() public view returns (uint256 assets) {
        assets = DASHBOARD.maxLockableValue();
    }

    /**
     * @notice Nominal assets owned by an account
     * @param _account The account to query
     * @return assets Amount of account assets (18 decimals)
     */
    function nominalAssetsOf(address _account) public view returns (uint256 assets) {
        assets = _getAssetsShare(balanceOf(_account), totalNominalAssets());
    }

    /**
     * @notice Total assets managed by the pool
     * @return assets Total assets (18 decimals)
     * @dev Overridable method to include other assets if needed
     * @dev Subtract unassigned liability stETH from total nominal assets
     */
    function totalAssets() public view virtual returns (uint256 assets) {
        assets = Math.saturatingSub(totalNominalAssets(), totalUnassignedLiabilitySteth()); /* plus other assets if any */
    }

    /**
     * @notice Assets of a specific account
     * @param _account The address of the account
     * @return assets Assets of the account (18 decimals)
     */
    function assetsOf(address _account) public view returns (uint256 assets) {
        assets = _convertToAssets(balanceOf(_account));
    }

    // =================================================================================
    // CONVERSION
    // =================================================================================

    function _convertToStv(uint256 _assets, Math.Rounding _rounding) internal view returns (uint256 stv) {
        uint256 totalAssets_ = totalAssets();
        if (totalAssets_ == 0) return 0;

        stv = Math.mulDiv(_assets, totalSupply(), totalAssets_, _rounding);
    }

    function _convertToAssets(uint256 _stv) internal view returns (uint256 assets) {
        assets = _getAssetsShare(_stv, totalAssets());
    }

    function _getAssetsShare(uint256 _stv, uint256 _assets) internal view returns (uint256 assets) {
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) return 0;

        assets = Math.mulDiv(_stv, _assets, totalSupply_, Math.Rounding.Floor);
    }

    // =================================================================================
    // PREVIEW
    // =================================================================================

    /**
     * @notice Preview the amount of stv that would be received for a given asset amount
     * @param _assets Amount of assets to deposit (18 decimals)
     * @return stv Amount of stv that would be minted (27 decimals)
     */
    function previewDeposit(uint256 _assets) public view returns (uint256 stv) {
        stv = _convertToStv(_assets, Math.Rounding.Floor);
    }

    /**
     * @notice Preview the amount of stv that would be burned for a given asset withdrawal
     * @param _assets Amount of assets to withdraw (18 decimals)
     * @return stv Amount of stv that would be burned (27 decimals)
     */
    function previewWithdraw(uint256 _assets) external view returns (uint256 stv) {
        stv = _convertToStv(_assets, Math.Rounding.Ceil);
    }

    /**
     * @notice Preview the amount of assets that would be received for a given stv amount
     * @param _stv Amount of stv to redeem (27 decimals)
     * @return assets Amount of assets that would be received (18 decimals)
     */
    function previewRedeem(uint256 _stv) external view returns (uint256 assets) {
        assets = _convertToAssets(_stv);
    }

    // =================================================================================
    // DEPOSIT
    // =================================================================================

    receive() external payable {
        // Auto-deposit ETH sent directly to the contract
        depositETH(msg.sender, address(0));
    }

    /**
     * @notice Deposit native ETH and receive stv
     * @param _recipient Address to receive the minted shares
     * @param _referral Address of the referral (if any)
     * @return stv Amount of stv minted
     * @dev Requires fresh oracle report to price stv accurately
     */
    function depositETH(address _recipient, address _referral) public payable returns (uint256 stv) {
        stv = _deposit(_recipient, _referral);
    }

    function _deposit(address _recipient, address _referral) internal returns (uint256 stv) {
        if (msg.value == 0) revert ZeroDeposit();
        if (_recipient == address(0)) revert InvalidRecipient();
        _checkFeatureNotPaused(DEPOSITS_FEATURE);
        _checkAllowList();
        _checkFreshReport();

        stv = previewDeposit(msg.value);
        _mint(_recipient, stv);
        DASHBOARD.fund{value: msg.value}();

        emit Deposit(msg.sender, _recipient, _referral, msg.value, stv);
    }

    // =================================================================================
    // LIABILITY
    // =================================================================================

    /**
     * @notice Total liability stETH shares issued to the vault
     * @return liabilityShares Total liability stETH shares (18 decimals)
     */
    function totalLiabilityShares() public view returns (uint256) {
        return DASHBOARD.liabilityShares();
    }

    /**
     * @notice Total liability stETH shares that are not assigned to any users
     * @return unassignedLiabilityShares Total unassign liability stETH shares (18 decimals)
     * @dev Overridable method to get unassigned liability shares
     * @dev Should exclude individually minted stETH shares (if any)
     */
    function totalUnassignedLiabilityShares() public view virtual returns (uint256 unassignedLiabilityShares) {
        unassignedLiabilityShares = totalLiabilityShares(); /* minus individually minted stETH shares */
    }

    /**
     * @notice Total unassigned liability in stETH
     */
    function totalUnassignedLiabilitySteth() public view returns (uint256 unassignedLiabilitySteth) {
        unassignedLiabilitySteth = STETH.getPooledEthBySharesRoundUp(totalUnassignedLiabilityShares());
    }

    /**
     * @notice Rebalance unassigned liability by repaying it with assets held by the vault
     * @param _stethShares Amount of stETH shares to rebalance (18 decimals)
     * @dev Only unassigned liability can be rebalanced with this method, not individual liability
     * @dev Can be called by anyone if there is any unassigned liability
     * @dev Requires fresh oracle report before calling (check is performed in VaultHub)
     */
    function rebalanceUnassignedLiability(uint256 _stethShares) external {
        _checkOnlyUnassignedLiabilityRebalance(_stethShares);
        DASHBOARD.rebalanceVaultWithShares(_stethShares);

        emit UnassignedLiabilityRebalanced(_stethShares, 0);
    }

    /**
     * @notice Rebalance unassigned liability by repaying it with external ether
     * @dev Only unassigned liability can be rebalanced with this method, not individual liability
     * @dev Can be called by anyone if there is any unassigned liability
     * @dev This function accepts ETH and uses it to rebalance unassigned liability
     * @dev Requires fresh oracle report before calling (check is performed in VaultHub)
     */
    function rebalanceUnassignedLiabilityWithEther() external payable {
        uint256 stethShares = _getSharesByPooledEth(msg.value);
        _checkOnlyUnassignedLiabilityRebalance(stethShares);
        DASHBOARD.rebalanceVaultWithEther{value: msg.value}(msg.value);

        emit UnassignedLiabilityRebalanced(stethShares, msg.value);
    }

    /**
     * @dev Checks if only unassigned liability will be rebalanced, not individual liability
     */
    function _checkOnlyUnassignedLiabilityRebalance(uint256 _stethShares) internal view {
        if (_stethShares == 0) revert NotEnoughToRebalance();
        if (totalUnassignedLiabilityShares() < _stethShares) revert NotEnoughToRebalance();
    }

    /**
     * @dev Checks if there are no unassigned liability shares
     */
    function _checkNoUnassignedLiability() internal view {
        if (totalUnassignedLiabilityShares() > 0) revert UnassignedLiabilityOnVault();
    }

    /**
     * @dev Checks if the vault is not in bad debt (value < liability)
     */
    function _checkNoBadDebt() internal view {
        uint256 totalValueInStethShares = _getSharesByPooledEth(VAULT_HUB.totalValue(address(VAULT)));
        if (totalValueInStethShares < totalLiabilityShares()) revert VaultInBadDebt();
    }

    // =================================================================================
    // STETH HELPERS
    // =================================================================================

    function _getSharesByPooledEth(uint256 _ethAmount) internal view returns (uint256 stethShares) {
        stethShares = STETH.getSharesByPooledEth(_ethAmount);
    }

    function _getPooledEthByShares(uint256 _stethShares) internal view returns (uint256 ethAmount) {
        ethAmount = STETH.getPooledEthByShares(_stethShares);
    }

    function _getPooledEthBySharesRoundUp(uint256 _stethShares) internal view returns (uint256 ethAmount) {
        ethAmount = STETH.getPooledEthBySharesRoundUp(_stethShares);
    }

    // =================================================================================
    // ERC20 OVERRIDES
    // =================================================================================

    /**
     * @notice Returns the number of decimals used to get its user representation.
     * @return Number of decimals (27)
     */
    function decimals() public pure override returns (uint8) {
        return uint8(DECIMALS);
    }

    /**
     * @dev Overridden method from ERC20 to prevent updates if there are unassigned liability
     */
    function _update(address _from, address _to, uint256 _value) internal virtual override {
        // Ensure vault is not in bad debt (value < liability) before any transfer
        _checkNoBadDebt();

        // In rare scenarios, the vault could have liability shares that are not assigned to any pool users
        // In such cases, it prevents any transfers until the unassigned liability is rebalanced
        _checkNoUnassignedLiability();

        super._update(_from, _to, _value);
    }

    // =================================================================================
    // WITHDRAWALS
    // =================================================================================

    /**
     * @notice Transfer stv from user to WithdrawalQueue contract when enqueuing withdrawal requests
     * @param _from Address of the user
     * @param _stv Amount of stv to transfer (27 decimals)
     * @dev Can only be called by the WithdrawalQueue contract
     */
    function transferFromForWithdrawalQueue(address _from, uint256 _stv) external {
        _checkOnlyWithdrawalQueue();
        _transfer(_from, address(WITHDRAWAL_QUEUE), _stv);
    }

    /**
     * @notice Burn stv from WithdrawalQueue contract when finalizing withdrawal requests
     * @param _stv Amount of stv to burn (27 decimals)
     * @dev Can only be called by the WithdrawalQueue contract
     */
    function burnStvForWithdrawalQueue(uint256 _stv) external {
        _checkOnlyWithdrawalQueue();
        _checkNoBadDebt();
        _checkNoUnassignedLiability();
        _burnUnsafe(address(WITHDRAWAL_QUEUE), _stv);
    }

    function _burnUnsafe(address _account, uint256 _value) internal {
        if (_account == address(0)) revert ERC20InvalidSender(address(0));
        super._update(_account, address(0), _value);
    }

    function _checkOnlyWithdrawalQueue() internal view {
        if (address(WITHDRAWAL_QUEUE) != msg.sender) revert NotWithdrawalQueue();
    }

    // =================================================================================
    // PAUSE / RESUME DEPOSITS
    // =================================================================================

    /**
     * @notice Pause deposits
     * @dev Can only be called by accounts with the DEPOSITS_PAUSE_ROLE
     */
    function pauseDeposits() external {
        _checkRole(DEPOSITS_PAUSE_ROLE, msg.sender);
        _pauseFeature(DEPOSITS_FEATURE);
    }

    /**
     * @notice Resume deposits
     * @dev Can only be called by accounts with the DEPOSITS_RESUME_ROLE
     */
    function resumeDeposits() external {
        _checkRole(DEPOSITS_RESUME_ROLE, msg.sender);
        _resumeFeature(DEPOSITS_FEATURE);
    }

    // =================================================================================
    // ORACLE FRESHNESS CHECK
    // =================================================================================

    function _checkFreshReport() internal view {
        if (!VAULT_HUB.isReportFresh(address(VAULT))) revert VaultReportStale();
    }
}
