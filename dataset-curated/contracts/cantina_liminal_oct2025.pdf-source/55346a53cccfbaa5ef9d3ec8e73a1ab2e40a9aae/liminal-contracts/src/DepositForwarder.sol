// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IDepositPipe} from "./interfaces/IDepositPipe.sol";

/**
 * @title DepositForwarder
 * @notice Forwarder contract for depositing tokens on behalf of users into a specific deposit pipe
 * @dev One forwarder is deployed per XToken, handling deposits for that specific token
 */
contract DepositForwarder is
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice Role for keeper operations
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /// @notice Role for emergency pause/unpause operations
    bytes32 public constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");

    /// @custom:storage-location erc7201:liminal.depositProxy.v1
    struct DepositForwarderStorage {
        /// @notice Mapping from asset address to deposit pipe address
        mapping(address => address) assetToDepositPipe;
        /// @notice Array of supported assets for enumeration
        address[] supportedAssets;
        /// @notice Mapping to check if asset is supported
        mapping(address => bool) isSupportedAsset;
        /// @notice Timelock controller for critical operations
        address timeLockController;
    }

    // keccak256(abi.encode(uint256(keccak256("liminal.storage.depositForwarder.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DEPOSIT_FORWARDER_STORAGE_LOCATION =
        0x43639106a183763e0d79da866d4c04316816dabf62bf4e69044fc03f2bdc7100;

    function _getDepositForwarderStorage() private pure returns (DepositForwarderStorage storage $) {
        assembly {
            $.slot := DEPOSIT_FORWARDER_STORAGE_LOCATION
        }
    }

    /// Events
    event DepositForUser(
        address indexed asset,
        address indexed user,
        address indexed depositPipe,
        uint256 amount,
        uint256 shares,
        bool permitUsed
    );
    event DepositPipeAdded(address indexed asset, address indexed depositPipe);
    event DepositPipeRemoved(address indexed asset, address indexed depositPipe);
    event TimelockControllerSet(address indexed oldTimelock, address indexed newTimelock);

    /// @notice Modifier for timelock-protected functions
    modifier onlyTimelock() {
        DepositForwarderStorage storage $ = _getDepositForwarderStorage();
        require(msg.sender == $.timeLockController, "DepositForwarder: only timelock");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the deposit proxy
     * @dev Ownership (DEFAULT_ADMIN_ROLE) is granted to deployer
     * @param _deployer Deployer address (receives DEFAULT_ADMIN_ROLE)
     * @param _keeper The keeper address
     * @param _timeLockController The timelock controller address
     * @param _emergencyManager The emergency manager MPC address (receives EMERGENCY_MANAGER_ROLE)
     */
    function initialize(address _deployer, address _keeper, address _timeLockController, address _emergencyManager) external initializer {
        require(_deployer != address(0), "DepositForwarder: zero deployer");
        require(_keeper != address(0), "DepositForwarder: zero keeper");
        require(_timeLockController != address(0), "DepositForwarder: zero timelock");
        require(_emergencyManager != address(0), "DepositForwarder: zero emergency manager");

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        DepositForwarderStorage storage $ = _getDepositForwarderStorage();
        $.timeLockController = _timeLockController;

        // Grant ownership to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, _deployer);
        _grantRole(EMERGENCY_MANAGER_ROLE, _emergencyManager);
        _grantRole(KEEPER_ROLE, _keeper);
    }

    /**
     * @notice Deposit tokens on behalf of a user using permit signature
     * @param asset The asset to deposit
     * @param user The user to deposit for (will receive shares)
     * @param amount The amount to deposit
     * @param deadline The permit deadline
     * @param v The recovery id of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     * @return shares The amount of shares minted
     */
    function depositFor(address asset, address user, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        onlyRole(KEEPER_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        require(asset != address(0), "DepositForwarder: zero asset");
        require(user != address(0), "DepositForwarder: zero user");
        require(amount > 0, "DepositForwarder: zero amount");

        DepositForwarderStorage storage $ = _getDepositForwarderStorage();
        address depositPipe = $.assetToDepositPipe[asset];
        require(depositPipe != address(0), "DepositForwarder: unsupported asset");

        // Attempt to use permit - follow OpenZeppelin's recommended pattern
        bool permitUsed = false;
        try IERC20Permit(asset).permit(user, address(this), amount, deadline, v, r, s) {
            permitUsed = true;
        } catch {
            // Permit failed - will rely on existing allowance
            // This handles frontrunning, already used permits, and non-permit tokens gracefully
        }

        // Transfer tokens from user to this contract
        IERC20(asset).safeTransferFrom(user, address(this), amount);

        // Approve deposit pipe to spend tokens
        IERC20(asset).forceApprove(depositPipe, amount);

        // Deposit into the deposit pipe with user as receiver and this contract as controller
        shares = IDepositPipe(depositPipe).deposit(amount, user, address(this));

        // Reset allowance to 0 for security
        IERC20(asset).forceApprove(depositPipe, 0);

        emit DepositForUser(asset, user, depositPipe, amount, shares, permitUsed);

        return shares;
    }

    /**
     * @notice Deposit tokens on behalf of a user using pre-existing approval
     * @dev Fallback function for wallets that don't support permits
     * @param asset The asset to deposit
     * @param user The user to deposit for (will receive shares)
     * @param amount The amount to deposit
     * @return shares The amount of shares minted
     */
    function depositForWithApproval(address asset, address user, uint256 amount)
        external
        onlyRole(KEEPER_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        require(asset != address(0), "DepositForwarder: zero asset");
        require(user != address(0), "DepositForwarder: zero user");
        require(amount > 0, "DepositForwarder: zero amount");

        DepositForwarderStorage storage $ = _getDepositForwarderStorage();
        address depositPipe = $.assetToDepositPipe[asset];
        require(depositPipe != address(0), "DepositForwarder: unsupported asset");

        // Transfer tokens from user to this contract
        IERC20(asset).safeTransferFrom(user, address(this), amount);

        // Approve deposit pipe to spend tokens
        IERC20(asset).forceApprove(depositPipe, amount);

        // Deposit into the deposit pipe with user as receiver and this contract as controller
        shares = IDepositPipe(depositPipe).deposit(amount, user, address(this));

        // Reset allowance to 0 for security
        IERC20(asset).forceApprove(depositPipe, 0);

        emit DepositForUser(asset, user, depositPipe, amount, shares, false);

        return shares;
    }

    /**
     * @notice Add a new deposit pipe for an asset
     * @param _depositPipe The deposit pipe address to add
     */
    function addDepositPipe(address _depositPipe) external onlyTimelock {
        require(_depositPipe != address(0), "DepositForwarder: zero deposit pipe");

        DepositForwarderStorage storage $ = _getDepositForwarderStorage();
        address asset = IDepositPipe(_depositPipe).asset();

        require($.assetToDepositPipe[asset] == address(0), "DepositForwarder: asset already supported");

        $.assetToDepositPipe[asset] = _depositPipe;

        if (!$.isSupportedAsset[asset]) {
            $.supportedAssets.push(asset);
            $.isSupportedAsset[asset] = true;
        }

        emit DepositPipeAdded(asset, _depositPipe);
    }

    /**
     * @notice Remove a deposit pipe for an asset
     * @param asset The asset address to remove support for
     */
    function removeDepositPipe(address asset) external onlyTimelock {
        require(asset != address(0), "DepositForwarder: zero asset");

        DepositForwarderStorage storage $ = _getDepositForwarderStorage();
        address depositPipe = $.assetToDepositPipe[asset];
        require(depositPipe != address(0), "DepositForwarder: asset not supported");

        delete $.assetToDepositPipe[asset];
        $.isSupportedAsset[asset] = false;

        uint256 supportedAssetsLength = $.supportedAssets.length;

        // Remove from supportedAssets array
        for (uint256 i = 0; i < supportedAssetsLength; i++) {
            if ($.supportedAssets[i] == asset) {
                $.supportedAssets[i] = $.supportedAssets[supportedAssetsLength - 1];
                $.supportedAssets.pop();
                break;
            }
        }

        emit DepositPipeRemoved(asset, depositPipe);
    }

 /**
     * @notice Set the timelock controller
     * @param _timeLockController New timelock controller address
     * @dev Can only be called by the current timelock (with delay enforced by VaultTimelockController)
     */
    function setTimelockController(address _timeLockController) external onlyTimelock {
        require(_timeLockController != address(0), "NAVOracle: zero timelock");

        DepositForwarderStorage storage $ = _getDepositForwarderStorage();
        address oldTimelock = $.timeLockController;
        $.timeLockController = _timeLockController;

        emit TimelockControllerSet(oldTimelock, _timeLockController);
    }


    // ========== VIEW FUNCTIONS ==========

    /**
     * @notice Get the deposit pipe for an asset
     * @param asset The asset address
     * @return The deposit pipe address
     */
    function getDepositPipe(address asset) external view returns (address) {
        return _getDepositForwarderStorage().assetToDepositPipe[asset];
    }

    /**
     * @notice Check if an asset is supported
     * @param asset The asset address
     * @return True if the asset is supported
     */
    function isAssetSupported(address asset) external view returns (bool) {
        return _getDepositForwarderStorage().assetToDepositPipe[asset] != address(0);
    }

    /**
     * @notice Get all supported assets
     * @return Array of supported asset addresses
     */
    function getSupportedAssets() external view returns (address[] memory) {
        return _getDepositForwarderStorage().supportedAssets;
    }

    /**
     * @notice Get the number of supported assets
     * @return The count of supported assets
     */
    function getSupportedAssetsCount() external view returns (uint256) {
        return _getDepositForwarderStorage().supportedAssets.length;
    }

    /**
     * @notice Get the timelock controller address
     * @return The timelock controller address
     */
    function timeLockController() external view returns (address) {
        return _getDepositForwarderStorage().timeLockController;
    }

    // ========== ADMIN FUNCTIONS ==========

    /**
     * @notice Emergency pause
     */
    function pause() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause operations
     */
    function unpause() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        _unpause();
    }

    /**
     * @notice Recover tokens from the contract (timelock-protected)
     * @param token The token to recover
     * @param to The address to send tokens to
     * @param amount The amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyTimelock {
        require(token != address(0), "DepositForwarder: zero token");
        require(to != address(0), "DepositForwarder: zero recipient");
        require(amount > 0, "DepositForwarder: zero amount");
        IERC20(token).safeTransfer(to, amount);
    }
}
