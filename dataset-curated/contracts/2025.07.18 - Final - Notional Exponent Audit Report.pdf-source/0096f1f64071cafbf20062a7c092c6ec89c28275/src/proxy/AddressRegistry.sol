// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {Unauthorized, CannotEnterPosition, InvalidVault} from "../interfaces/Errors.sol";
import {IWithdrawRequestManager} from "../interfaces/IWithdrawRequestManager.sol";
import {VaultPosition} from "../interfaces/ILendingRouter.sol";
import {Initializable} from "./Initializable.sol";

/// @notice Registry for the addresses for different components of the protocol.
contract AddressRegistry is Initializable {
    event PendingUpgradeAdminSet(address indexed newPendingUpgradeAdmin);
    event UpgradeAdminTransferred(address indexed newUpgradeAdmin);
    event PendingPauseAdminSet(address indexed newPendingPauseAdmin);
    event PauseAdminTransferred(address indexed newPauseAdmin);
    event FeeReceiverTransferred(address indexed newFeeReceiver);
    event WithdrawRequestManagerSet(address indexed yieldToken, address indexed withdrawRequestManager);
    event LendingRouterSet(address indexed lendingRouter);
    event AccountPositionCreated(address indexed account, address indexed vault, address indexed lendingRouter);
    event AccountPositionCleared(address indexed account, address indexed vault, address indexed lendingRouter);
    event WhitelistedVault(address indexed vault, bool isWhitelisted);

    /// @notice Address of the admin that is allowed to:
    /// - Upgrade TimelockUpgradeableProxy contracts given a 7 day timelock
    /// - Transfer the upgrade admin role
    /// - Set the pause admin
    /// - Set the fee receiver
    /// - Add reward tokens to the RewardManager
    /// - Set the WithdrawRequestManager for a yield token
    /// - Whitelist vaults for the WithdrawRequestManager
    /// - Whitelist new lending routers
    address public upgradeAdmin;
    address public pendingUpgradeAdmin;

    /// @notice Address of the admin that is allowed to selectively pause or unpause
    /// TimelockUpgradeableProxy contracts
    address public pauseAdmin;
    address public pendingPauseAdmin;

    /// @notice Address of the account that receives the protocol fees
    address public feeReceiver;

    /// @notice Mapping of yield token to WithdrawRequestManager
    mapping(address token => address withdrawRequestManager) public withdrawRequestManagers;

    /// @notice Mapping of lending router to boolean indicating if it is whitelisted
    mapping(address lendingRouter => bool isLendingRouter) public lendingRouters;

    /// @notice Mapping to whitelisted vaults
    mapping(address vault => bool isWhitelisted) public whitelistedVaults;

    /// @notice Mapping of accounts to their existing position on a given vault
    mapping(address account => mapping(address vault => VaultPosition)) internal accountPositions;

    function _initialize(bytes calldata data) internal override {
        (address _upgradeAdmin, address _pauseAdmin, address _feeReceiver) = abi.decode(data, (address, address, address));
        upgradeAdmin = _upgradeAdmin;
        pauseAdmin = _pauseAdmin;
        feeReceiver = _feeReceiver;
    }

    modifier onlyUpgradeAdmin() {
        if (msg.sender != upgradeAdmin) revert Unauthorized(msg.sender);
        _;
    }

    function transferUpgradeAdmin(address _newUpgradeAdmin) external onlyUpgradeAdmin {
        pendingUpgradeAdmin = _newUpgradeAdmin;
        emit PendingUpgradeAdminSet(_newUpgradeAdmin);
    }

    function acceptUpgradeOwnership() external {
        if (msg.sender != pendingUpgradeAdmin) revert Unauthorized(msg.sender);
        upgradeAdmin = pendingUpgradeAdmin;
        delete pendingUpgradeAdmin;
        emit UpgradeAdminTransferred(upgradeAdmin);
    }

    function transferPauseAdmin(address _newPauseAdmin) external onlyUpgradeAdmin {
        pendingPauseAdmin = _newPauseAdmin;
        emit PendingPauseAdminSet(_newPauseAdmin);
    }

    function acceptPauseAdmin() external {
        if (msg.sender != pendingPauseAdmin) revert Unauthorized(msg.sender);
        pauseAdmin = pendingPauseAdmin;
        delete pendingPauseAdmin;
        emit PauseAdminTransferred(pauseAdmin);
    }

    function transferFeeReceiver(address _newFeeReceiver) external onlyUpgradeAdmin {
        feeReceiver = _newFeeReceiver;
        emit FeeReceiverTransferred(_newFeeReceiver);
    }

    function setWithdrawRequestManager(address withdrawRequestManager) external onlyUpgradeAdmin {
        address yieldToken = IWithdrawRequestManager(withdrawRequestManager).YIELD_TOKEN();
        // Prevent accidental override of a withdraw request manager, this is dangerous
        // as it could lead to withdraw requests being stranded on the deprecated withdraw
        // request manager. Managers can be upgraded using a TimelockUpgradeableProxy.
        require (withdrawRequestManagers[yieldToken] == address(0), "Withdraw request manager already set");

        withdrawRequestManagers[yieldToken] = withdrawRequestManager;
        emit WithdrawRequestManagerSet(yieldToken, withdrawRequestManager);
    }

    function setWhitelistedVault(address vault, bool isWhitelisted) external onlyUpgradeAdmin {
        whitelistedVaults[vault] = isWhitelisted;
        emit WhitelistedVault(vault, isWhitelisted);
    }

    function getWithdrawRequestManager(address yieldToken) external view returns (IWithdrawRequestManager) {
        return IWithdrawRequestManager(withdrawRequestManagers[yieldToken]);
    }

    function setLendingRouter(address lendingRouter) external onlyUpgradeAdmin {
        lendingRouters[lendingRouter] = true;
        emit LendingRouterSet(lendingRouter);
    }

    function isLendingRouter(address lendingRouter) external view returns (bool) {
        return lendingRouters[lendingRouter];
    }

    function getVaultPosition(address account, address vault) external view returns (VaultPosition memory) {
        return accountPositions[account][vault];
    }

    function setPosition(address account, address vault) external {
        // Must only be called by a lending router
        if (!lendingRouters[msg.sender]) revert Unauthorized(msg.sender);
        VaultPosition storage position = accountPositions[account][vault];

        if (position.lendingRouter == address(0)) position.lendingRouter = msg.sender;
        else if (position.lendingRouter != msg.sender) revert CannotEnterPosition();

        // Lending routers may be used to enter positions on any vault, including a malicious vault
        // so this ensures that only whitelisted vaults can be used to enter positions
        if (!whitelistedVaults[vault]) revert InvalidVault(vault);

        position.lastEntryTime = uint32(block.timestamp);
        emit AccountPositionCreated(account, vault, msg.sender);
    }

    function clearPosition(address account, address vault) external {
        // Must only be called by a lending router
        if (!lendingRouters[msg.sender]) revert Unauthorized(msg.sender);

        delete accountPositions[account][vault];
        emit AccountPositionCleared(account, vault, msg.sender);
    }
}