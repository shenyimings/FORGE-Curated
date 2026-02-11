// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { WETH } from "@solmate/tokens/WETH.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { BeforeTransferHook } from "src/interfaces/BeforeTransferHook.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";
import { IKeyring } from "src/interfaces/IKeyring.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";

/**
 * @title TellerWithMultiAssetSupport
 */
contract TellerWithMultiAssetSupport is Auth, BeforeTransferHook, ReentrancyGuard {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    using SafeTransferLib for WETH;

    // ========================================= CONSTANTS =========================================

    /**
     * @notice Native address used to tell the contract to handle native asset deposits.
     */
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
     * @notice The maximum possible share lock period.
     */
    uint256 internal constant MAX_SHARE_LOCK_PERIOD = 3 days;

    // ========================================= STATE =========================================

    uint256 public depositCap;
    /**
     * @notice Mapping ERC20s to an isSupported bool.
     */
    mapping(ERC20 => bool) public isSupported;

    /**
     * @notice The deposit nonce used to map to a deposit hash.
     */
    uint96 public depositNonce = 1;

    /**
     * @notice After deposits, shares are locked to the msg.sender's address
     *         for `shareLockPeriod`.
     * @dev During this time all transfers from msg.sender will revert, and
     *      deposits are refundable.
     */
    uint64 public shareLockPeriod;

    /**
     * @notice Used to pause calls to `deposit` and `depositWithPermit`.
     */
    bool public isPaused;

    /**
     * @dev Maps deposit nonce to keccak256(address receiver, address _depositAsset, uint256 _depositAmount, uint256
     * _shareAmount, uint256 _timestamp, uint256 _shareLockPeriod).
     */
    mapping(uint256 => bytes32) public publicDepositHistory;

    /**
     * @notice Maps user address to the time their shares will be unlocked.
     */
    mapping(address => uint256) public shareUnlockTime;

    /**
     * @notice Access control mode for the vault
     */
    enum AccessControlMode {
        DISABLED,
        KEYRING_KYC,
        MANUAL_WHITELIST
    }

    /**
     * @notice Current access control mode
     */
    AccessControlMode public accessControlMode;

    /**
     * @notice Keyring contract interface
     */
    IKeyring public keyringContract;

    /**
     * @notice Keyring policy ID to check against
     */
    uint256 public keyringPolicyId;

    /**
     * @notice Manual whitelist for addresses when in MANUAL_WHITELIST mode
     */
    mapping(address => bool) public manualWhitelist;

    /**
     * @notice Whitelist for smart contracts (AMMs, protocols) that work in both modes
     */
    mapping(address => bool) public contractWhitelist;

    //============================== ERRORS ===============================

    error TellerWithMultiAssetSupport__ShareLockPeriodTooLong();
    error TellerWithMultiAssetSupport__SharesAreLocked();
    error TellerWithMultiAssetSupport__SharesAreUnLocked();
    error TellerWithMultiAssetSupport__BadDepositHash();
    error TellerWithMultiAssetSupport__AssetNotSupported();
    error TellerWithMultiAssetSupport__ZeroAssets();
    error TellerWithMultiAssetSupport__MinimumMintNotMet();
    error TellerWithMultiAssetSupport__MinimumAssetsNotMet();
    error TellerWithMultiAssetSupport__PermitFailedAndAllowanceTooLow();
    error TellerWithMultiAssetSupport__ZeroShares();
    error TellerWithMultiAssetSupport__Paused();
    error TellerWithMultiAssetSupport__KeyringCredentialInvalid();
    error TellerWithMultiAssetSupport__NotWhitelisted();

    //============================== EVENTS ===============================

    event Paused();
    event Unpaused();
    event AssetAdded(address indexed asset);
    event AssetRemoved(address indexed asset);
    event Deposit(
        uint256 indexed nonce,
        address indexed receiver,
        address indexed _depositAsset,
        uint256 _depositAmount,
        uint256 _shareAmount,
        uint256 depositTimestamp,
        uint256 shareLockPeriodAtTimeOfDeposit
    );
    event BulkDeposit(address indexed asset, uint256 _depositAmount);
    event BulkWithdraw(address indexed asset, uint256 _shareAmount);
    event DepositRefunded(uint256 indexed nonce, bytes32 depositHash, address indexed user);
    event DepositCapUpdated(uint256 oldCap, uint256 newCap);
    event AccessControlModeUpdated(AccessControlMode oldMode, AccessControlMode newMode);
    event KeyringConfigUpdated(address keyringContract, uint256 policyId);
    event ManualWhitelistUpdated(address indexed account, bool status);
    event ContractWhitelistUpdated(address indexed account, bool status);
    event ShareLockPeriodUpdated(uint64 oldPeriod, uint64 newPeriod);

    //============================== IMMUTABLES ===============================

    /**
     * @notice The BoringVault this contract is working with.
     */
    BoringVault public immutable vault;

    /**
     * @notice The AccountantWithRateProviders this contract is working with.
     */
    AccountantWithRateProviders public immutable accountant;

    /**
     * @notice One share of the BoringVault.
     */
    uint256 internal immutable ONE_SHARE;

    /**
     * @notice Check if an address has access to mint/redeem
     * @param _entity The address to check
     */
    modifier checkAccess(address _entity) {
        if (accessControlMode == AccessControlMode.KEYRING_KYC) {
            if (!contractWhitelist[_entity] && address(keyringContract) != address(0)) {
                if (!keyringContract.checkCredential(keyringPolicyId, _entity)) {
                    revert TellerWithMultiAssetSupport__KeyringCredentialInvalid();
                }
            }
        } else if (accessControlMode == AccessControlMode.MANUAL_WHITELIST) {
            if (!manualWhitelist[_entity] && !contractWhitelist[_entity]) {
                revert TellerWithMultiAssetSupport__NotWhitelisted();
            }
        }
        // If DISABLED, no checks performed
        _;
    }

    constructor(address _owner, address _vault, address _accountant) Auth(_owner, Authority(address(0))) {
        vault = BoringVault(payable(_vault));
        ONE_SHARE = 10 ** vault.decimals();
        accountant = AccountantWithRateProviders(_accountant);
    }

    // ========================================= ADMIN FUNCTIONS =========================================
    function setDepositCap(uint256 _depositCap) external requiresAuth {
        uint256 oldCap = depositCap;
        depositCap = _depositCap;
        emit DepositCapUpdated(oldCap, _depositCap);
    }

    /**
     * @notice Pause this contract, which prevents future calls to `deposit` and `depositWithPermit`.
     * @dev Callable by MULTISIG_ROLE.
     */
    function pause() external requiresAuth {
        isPaused = true;
        emit Paused();
    }

    /**
     * @notice Unpause this contract, which allows future calls to `deposit` and `depositWithPermit`.
     * @dev Callable by MULTISIG_ROLE.
     */
    function unpause() external requiresAuth {
        isPaused = false;
        emit Unpaused();
    }

    /**
     * @notice Adds this asset as a deposit asset.
     * @dev The accountant must also support pricing this asset, else the `deposit` call will revert.
     * @dev Callable by OWNER_ROLE.
     */
    function addAsset(ERC20 _asset) external requiresAuth {
        isSupported[_asset] = true;
        emit AssetAdded(address(_asset));
    }

    /**
     * @notice Removes this asset as a deposit asset.
     * @dev Callable by OWNER_ROLE.
     */
    function removeAsset(ERC20 _asset) external requiresAuth {
        isSupported[_asset] = false;
        emit AssetRemoved(address(_asset));
    }

    /**
     * @notice Sets the share lock period.
     * @dev This not only locks shares to the user address, but also serves as the pending deposit period, where
     * deposits can be reverted.
     * @dev If a new shorter share lock period is set, users with pending share locks could make a new deposit to
     * receive 1 wei shares,
     *      and have their shares unlock sooner than their original deposit allows. This state would allow for the user
     * deposit to be refunded,
     *      but only if they have not transferred their shares out of there wallet. This is an accepted limitation, and
     * should be known when decreasing
     *      the share lock period.
     * @dev Callable by OWNER_ROLE.
     */
    function setShareLockPeriod(uint64 _shareLockPeriod) external requiresAuth {
        if (_shareLockPeriod > MAX_SHARE_LOCK_PERIOD) revert TellerWithMultiAssetSupport__ShareLockPeriodTooLong();

        uint64 oldPeriod = shareLockPeriod;
        shareLockPeriod = _shareLockPeriod;

        emit ShareLockPeriodUpdated(oldPeriod, _shareLockPeriod);
    }

    /**
     * @notice Sets the access control mode
     * @dev Callable by OWNER_ROLE
     */
    function setAccessControlMode(AccessControlMode _mode) external requiresAuth {
        emit AccessControlModeUpdated(accessControlMode, _mode);
        accessControlMode = _mode;
    }

    /**
     * @notice Configure Keyring integration
     * @dev Callable by OWNER_ROLE
     */
    function setKeyringConfig(address _keyringContract, uint256 _policyId) external requiresAuth {
        keyringContract = IKeyring(_keyringContract);
        keyringPolicyId = _policyId;
        emit KeyringConfigUpdated(_keyringContract, _policyId);
    }

    /**
     * @notice Update manual whitelist
     * @dev Callable by OWNER_ROLE
     */
    function updateManualWhitelist(address[] calldata _addresses, bool _status) external requiresAuth {
        for (uint256 i = 0; i < _addresses.length; i++) {
            manualWhitelist[_addresses[i]] = _status;
            emit ManualWhitelistUpdated(_addresses[i], _status);
        }
    }

    /**
     * @notice Update contract whitelist (for AMMs, protocols)
     * @dev Callable by OWNER_ROLE
     */
    function updateContractWhitelist(address[] calldata _addresses, bool _status) external requiresAuth {
        for (uint256 i = 0; i < _addresses.length; i++) {
            contractWhitelist[_addresses[i]] = _status;
            emit ContractWhitelistUpdated(_addresses[i], _status);
        }
    }

    // ========================================= BeforeTransferHook FUNCTIONS =========================================

    /**
     * @notice Implement beforeTransfer hook to check if shares are locked.
     */
    function beforeTransfer(address _from) public view {
        if (shareUnlockTime[_from] > block.timestamp) revert TellerWithMultiAssetSupport__SharesAreLocked();
    }

    // ========================================= REVERT DEPOSIT FUNCTIONS =========================================

    /**
     * @notice Allows DEPOSIT_REFUNDER_ROLE to revert a pending deposit.
     * @dev Once a deposit share lock period has passed, it can no longer be reverted.
     * @dev It is possible the admin does not setup the BoringVault to call the transfer hook,
     *      but this contract can still be saving share lock state. In the event this happens
     *      deposits are still refundable if the user has not transferred their shares.
     *      But there is no guarantee that the user has not transferred their shares.
     * @dev Callable by STRATEGIST_MULTISIG_ROLE.
     */
    function refundDeposit(
        uint256 _nonce,
        address _receiver,
        address _depositAsset,
        uint256 _depositAmount,
        uint256 _shareAmount,
        uint256 _depositTimestamp,
        uint256 _shareLockUpPeriodAtTimeOfDeposit
    )
        external
        requiresAuth
    {
        if ((block.timestamp - _depositTimestamp) > _shareLockUpPeriodAtTimeOfDeposit) {
            // Shares are already unlocked, so we can not revert deposit.
            revert TellerWithMultiAssetSupport__SharesAreUnLocked();
        }
        bytes32 depositHash = keccak256(
            abi.encode(
                _receiver,
                _depositAsset,
                _depositAmount,
                _shareAmount,
                _depositTimestamp,
                _shareLockUpPeriodAtTimeOfDeposit
            )
        );
        if (publicDepositHistory[_nonce] != depositHash) revert TellerWithMultiAssetSupport__BadDepositHash();

        // Delete hash to prevent refund gas.
        delete publicDepositHistory[_nonce];

        accountant.checkpoint();

        // Burn shares and refund assets to receiver.
        vault.exit(_receiver, ERC20(_depositAsset), _depositAmount, _receiver, _shareAmount);

        emit DepositRefunded(_nonce, depositHash, _receiver);
    }

    // ========================================= USER FUNCTIONS =========================================

    /**
     * @notice Allows users to deposit into the BoringVault, if this contract is not paused.
     * @dev Publicly callable.
     */
    function deposit(
        ERC20 _depositAsset,
        uint256 _depositAmount,
        uint256 _minimumMint
    )
        external
        requiresAuth
        nonReentrant
        checkAccess(msg.sender)
        returns (uint256 shares)
    {
        if (isPaused) revert TellerWithMultiAssetSupport__Paused();
        if (!isSupported[_depositAsset]) revert TellerWithMultiAssetSupport__AssetNotSupported();

        shares = _erc20Deposit(_depositAsset, _depositAmount, _minimumMint, msg.sender);

        _afterPublicDeposit(msg.sender, _depositAsset, _depositAmount, shares, shareLockPeriod);
    }

    /**
     * @notice Allows users to deposit into BoringVault using permit.
     * @dev Publicly callable.
     */
    function depositWithPermit(
        ERC20 _depositAsset,
        uint256 _depositAmount,
        uint256 _minimumMint,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )
        external
        requiresAuth
        nonReentrant
        checkAccess(msg.sender)
        returns (uint256 shares)
    {
        if (isPaused) revert TellerWithMultiAssetSupport__Paused();
        if (!isSupported[_depositAsset]) revert TellerWithMultiAssetSupport__AssetNotSupported();

        // solhint-disable-next-line no-empty-blocks
        try _depositAsset.permit(msg.sender, address(vault), _depositAmount, _deadline, _v, _r, _s) { }
        catch {
            if (_depositAsset.allowance(msg.sender, address(vault)) < _depositAmount) {
                revert TellerWithMultiAssetSupport__PermitFailedAndAllowanceTooLow();
            }
        }
        shares = _erc20Deposit(_depositAsset, _depositAmount, _minimumMint, msg.sender);

        _afterPublicDeposit(msg.sender, _depositAsset, _depositAmount, shares, shareLockPeriod);
    }

    /**
     * @notice Allows on ramp role to deposit into this contract.
     * @dev Does NOT support native deposits.
     * @dev Callable by SOLVER_ROLE.
     */
    function bulkDeposit(
        ERC20 _depositAsset,
        uint256 _depositAmount,
        uint256 _minimumMint,
        address _to
    )
        external
        requiresAuth
        nonReentrant
        checkAccess(_to)
        returns (uint256 shares)
    {
        if (!isSupported[_depositAsset]) revert TellerWithMultiAssetSupport__AssetNotSupported();

        shares = _erc20Deposit(_depositAsset, _depositAmount, _minimumMint, _to);
        emit BulkDeposit(address(_depositAsset), _depositAmount);
    }

    /**
     * @notice Allows off ramp role to withdraw from this contract.
     * @dev Callable by SOLVER_ROLE.
     */
    function bulkWithdraw(
        ERC20 _withdrawAsset,
        uint256 _shareAmount,
        uint256 _minimumAssets,
        address _to
    )
        external
        requiresAuth
        checkAccess(msg.sender)
        returns (uint256 assetsOut)
    {
        if (!isSupported[_withdrawAsset]) revert TellerWithMultiAssetSupport__AssetNotSupported();
        if (_shareAmount == 0) revert TellerWithMultiAssetSupport__ZeroShares();

        accountant.checkpoint();

        // Get exchange rate in 18 decimals
        uint256 rate = accountant.getRate();

        // Calculate value in 18 decimals
        uint256 withdrawValueIn18 = _shareAmount.mulDivDown(rate, ONE_SHARE);

        // Convert to asset amount based on asset type
        if (address(_withdrawAsset) == address(accountant.base())) {
            // Base asset - convert from 18 to base decimals
            assetsOut = _changeDecimals(withdrawValueIn18, 18, accountant.decimals());
        } else {
            (bool isPegged,) = accountant.rateProviderData(_withdrawAsset);

            if (isPegged) {
                // Pegged asset - convert from 18 to asset decimals
                assetsOut = _changeDecimals(withdrawValueIn18, 18, _withdrawAsset.decimals());
            } else {
                // Non-pegged asset - use rate provider
                (, IRateProvider rateProvider) = accountant.rateProviderData(_withdrawAsset);
                uint256 assetRate = rateProvider.getRate();
                assetsOut = withdrawValueIn18.mulDivDown(10 ** _withdrawAsset.decimals(), assetRate);
            }
        }

        if (assetsOut < _minimumAssets) revert TellerWithMultiAssetSupport__MinimumAssetsNotMet();

        vault.exit(_to, _withdrawAsset, assetsOut, msg.sender, _shareAmount);
        emit BulkWithdraw(address(_withdrawAsset), _shareAmount);
    }

    // ========================================= INTERNAL HELPER FUNCTIONS =========================================

    /**
     * @notice Implements a common ERC20 deposit into BoringVault.
     */
    function _erc20Deposit(
        ERC20 _depositAsset,
        uint256 _depositAmount,
        uint256 _minimumMint,
        address _to
    )
        internal
        returns (uint256 shares)
    {
        if (_depositAmount == 0) revert TellerWithMultiAssetSupport__ZeroAssets();

        accountant.checkpoint();

        // Get exchange rate in 18 decimals
        uint256 rate = accountant.getRate();

        // Convert deposit amount to 18 decimal value based on asset type
        uint256 depositValueIn18;

        if (address(_depositAsset) == address(accountant.base())) {
            // Base asset - convert to 18 decimals
            depositValueIn18 = _changeDecimals(_depositAmount, accountant.decimals(), 18);
        } else {
            (bool isPegged,) = accountant.rateProviderData(_depositAsset);

            if (isPegged) {
                // Pegged asset - convert to 18 decimals (1:1 with base)
                depositValueIn18 = _changeDecimals(_depositAmount, _depositAsset.decimals(), 18);
            } else {
                // Non-pegged asset - use rate provider
                (, IRateProvider rateProvider) = accountant.rateProviderData(_depositAsset);
                uint256 assetRate = rateProvider.getRate();
                depositValueIn18 = _depositAmount.mulDivDown(assetRate, 10 ** _depositAsset.decimals());
            }
        }

        // Calculate shares using 18 decimal values
        shares = depositValueIn18.mulDivDown(ONE_SHARE, rate);

        if (shares < _minimumMint) revert TellerWithMultiAssetSupport__MinimumMintNotMet();

        uint256 shareValueInBase = shares.mulDivDown(rate, ONE_SHARE);
        // Convert to base decimals for cap check
        shareValueInBase = _changeDecimals(shareValueInBase, 18, accountant.decimals());
        uint256 currentTotalValue = vault.totalSupply().mulDivDown(rate, ONE_SHARE);
        currentTotalValue = _changeDecimals(currentTotalValue, 18, accountant.decimals());

        require(currentTotalValue + shareValueInBase <= depositCap, "Deposit cap exceeded");

        vault.enter(msg.sender, _depositAsset, _depositAmount, _to, shares);
    }

    /**
     * @notice Handle share lock logic, and event.
     */
    function _afterPublicDeposit(
        address _user,
        ERC20 _depositAsset,
        uint256 _depositAmount,
        uint256 _shares,
        uint256 _currentShareLockPeriod
    )
        internal
    {
        shareUnlockTime[_user] = block.timestamp + _currentShareLockPeriod;

        uint256 nonce = depositNonce;
        publicDepositHistory[nonce] = keccak256(
            abi.encode(_user, _depositAsset, _depositAmount, _shares, block.timestamp, _currentShareLockPeriod)
        );
        depositNonce++;
        emit Deposit(
            nonce, _user, address(_depositAsset), _depositAmount, _shares, block.timestamp, _currentShareLockPeriod
        );
    }

    /**
     * @notice Internal helper to change decimals
     */
    function _changeDecimals(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) return amount;
        if (fromDecimals < toDecimals) {
            return amount * 10 ** (toDecimals - fromDecimals);
        } else {
            return amount / 10 ** (fromDecimals - toDecimals);
        }
    }
}
