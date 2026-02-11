// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interface/IWithdrawVault.sol";


contract WithdrawVault is Initializable, PausableUpgradeable, AccessControlEnumerableUpgradeable, UUPSUpgradeable, IWithdrawVault, ReentrancyGuardUpgradeable {

    //admin role
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");

    using Address for address payable;
    using SafeERC20 for IERC20;

    address public immutable TIMELOCK_ADDRESS;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address timelockAddress) {
        require(timelockAddress != address(0), "timelockAddress cannot be a zero address");
        TIMELOCK_ADDRESS = timelockAddress;
        _disableInitializers();
    }

    receive() external payable {
        if (msg.value > 0) {
            emit ReceiveETH(msg.sender, address(this), msg.value);
        }
    }

    modifier onlyTimelock() {
        require(msg.sender == TIMELOCK_ADDRESS, "only timelock");
        _;
    }

    function initialize(address defaultAdmin) initializer public {
        __Pausable_init();
        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, TIMELOCK_ADDRESS);
        _grantRole(PAUSE_ROLE, defaultAdmin);
    }

    function pause() external onlyRole(PAUSE_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal onlyTimelock override {}

    function transferNative(address receipt, uint256 amount) external nonReentrant whenNotPaused onlyRole(TRANSFER_ROLE) {
        require(amount > 0, "invalid amount");

        payable(receipt).sendValue(amount);

        emit TransferNative(receipt, amount);
    }

    function transfer(address receipt, address token, uint256 amount) external nonReentrant whenNotPaused onlyRole(TRANSFER_ROLE) {
        require(amount > 0, "invalid amount");
        require(IERC20(token).balanceOf(address(this)) >= amount, "insufficient balance");

        IERC20(token).safeTransfer(receipt, amount);

        emit Transfer(receipt, token, amount);
    }

    function balance(address currency) external view returns (uint256) {
        return IERC20(currency).balanceOf(address(this));
    }
}
