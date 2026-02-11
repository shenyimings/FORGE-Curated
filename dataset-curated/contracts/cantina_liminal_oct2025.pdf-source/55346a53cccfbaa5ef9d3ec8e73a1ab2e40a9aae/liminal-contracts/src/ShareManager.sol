// SPDX-License-Identifier: BUSL-1.1
// Terms: https://liminal.money/xtokens/license

pragma solidity 0.8.28;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract ShareManager is
    ERC20Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    bytes32 public constant FEE_COLLECTOR_ROLE = keccak256("FEE_COLLECTOR_ROLE");

    bytes32 public constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");

    bytes32 public constant SAFE_MANAGER_ROLE = keccak256("SAFE_MANAGER_ROLE");

    struct ShareManagerStorage {
        mapping(address => mapping(address => bool)) isOperator;
        address timeLockController;
        address oVaultComposerMulti;
        uint256 maxDeposit;
        uint256 maxSupply;
        uint256 maxWithdraw;
        mapping(address => bool) blacklisted;
    }

    bytes32 private constant SHARE_MANAGER_STORAGE_LOCATION =
        0x337847f0cd9f9997f865bb5bc45c11df60e99bcb99c84221ba315731aed2fc00;

    function _getShareManagerStorage() private pure returns (ShareManagerStorage storage $) {
        assembly {
            $.slot := SHARE_MANAGER_STORAGE_LOCATION
        }
    }

    function isOperator(address controller, address operator) public view returns (bool) {
        ShareManagerStorage storage $ = _getShareManagerStorage();
        return $.isOperator[controller][operator] || $.oVaultComposerMulti == operator;
    }

    event OperatorSet(address indexed controller, address indexed operator, bool approved);
    event SharesMinted(address indexed to, uint256 amount, address indexed minter);
    event SharesBurned(address indexed from, uint256 amount, address indexed burner);
    event TimelockControllerSet(address indexed oldTimelock, address indexed newTimelock);
    event OVaultComposerMultiSet(address indexed oldOVaultComposerMulti, address indexed newOVaultComposerMulti, address indexed shareOftAdapter);
    event MaxDepositSet(uint256 oldMaxDeposit, uint256 newMaxDeposit);
    event MaxSupplySet(uint256 oldMaxSupply, uint256 newMaxSupply);
    event MaxWithdrawSet(uint256 oldMaxWithdraw, uint256 newMaxWithdraw);
    event Blacklisted(address indexed account);
    event Unblacklisted(address indexed account);

    modifier onlyTimelock() {
        ShareManagerStorage storage $ = _getShareManagerStorage();
        require(msg.sender == $.timeLockController, "ShareManager: only timelock");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _deployer,
        address _safeManager,
        address _emergencyManager,
        address _timeLockController,
        uint256 _maxDeposit,
        uint256 _maxSupply,
        uint256 _maxWithdraw
    ) external initializer {
        require(_deployer != address(0), "ShareManager: zero deployer");
        require(_safeManager != address(0), "ShareManager: zero safe manager");
        require(_timeLockController != address(0), "ShareManager: zero timelock");

        __ERC20_init(_name, _symbol);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        ShareManagerStorage storage $ = _getShareManagerStorage();
        $.timeLockController = _timeLockController;
        $.maxDeposit = _maxDeposit;
        $.maxSupply = _maxSupply;
        $.maxWithdraw = _maxWithdraw;

        _grantRole(DEFAULT_ADMIN_ROLE, _deployer);
        _grantRole(SAFE_MANAGER_ROLE, _safeManager);
        _grantRole(EMERGENCY_MANAGER_ROLE, _emergencyManager);
    }

    function mintShares(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
        ShareManagerStorage storage $ = _getShareManagerStorage();
        require(!$.blacklisted[to], "ShareManager: receiver address is blacklisted");
        require(to != address(0), "ShareManager: mint to zero");
        require(amount > 0, "ShareManager: zero amount");

        _mint(to, amount);
        emit SharesMinted(to, amount, msg.sender);
    }

    function burnShares(address from, uint256 amount) external onlyRole(BURNER_ROLE) whenNotPaused nonReentrant {
        ShareManagerStorage storage $ = _getShareManagerStorage();
        require(!$.blacklisted[from], "ShareManager: address is blacklisted");
        require(from != address(0), "ShareManager: burn from zero");
        require(amount > 0, "ShareManager: zero amount");
        require(balanceOf(from) >= amount, "ShareManager: insufficient balance");

        _burn(from, amount);
        emit SharesBurned(from, amount, msg.sender);
    }

    function burnSharesFromSelf(uint256 amount) external onlyRole(BURNER_ROLE) whenNotPaused nonReentrant {
        require(amount > 0, "ShareManager: zero amount");
        _burn(msg.sender, amount);

        emit SharesBurned(msg.sender, amount, msg.sender);
    }

    function mintFeesShares(address to, uint256 amount)
        external
        onlyRole(FEE_COLLECTOR_ROLE)
        whenNotPaused
        nonReentrant
    {
        require(to != address(0), "ShareManager: mint to zero");
        require(amount > 0, "ShareManager: zero amount");

        _mint(to, amount);

        emit SharesMinted(to, amount, msg.sender);
    }

    function setOperator(address operator, bool approved) external returns (bool) {
        require(msg.sender != operator, "ShareManager: self operator");
        ShareManagerStorage storage $ = _getShareManagerStorage();
        $.isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    function setTimelockController(address _timeLockController) external onlyTimelock {
        require(_timeLockController != address(0), "ShareManager: zero timelock");

        ShareManagerStorage storage $ = _getShareManagerStorage();
        address oldTimelock = $.timeLockController;
        $.timeLockController = _timeLockController;

        emit TimelockControllerSet(oldTimelock, _timeLockController);
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override
        whenNotPaused
        returns (bool)
    {
        ShareManagerStorage storage $ = _getShareManagerStorage();
        require(!$.blacklisted[from], "ShareManager: sender address is blacklisted");
        require(!$.blacklisted[to], "ShareManager: receiver address is blacklisted");

        address spender = _msgSender();

        if (from != spender) {
            if (!isOperator(from, spender)) {
                _spendAllowance(from, spender, amount);
            }
        }

        _transfer(from, to, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual override whenNotPaused returns (bool) {
        ShareManagerStorage storage $ = _getShareManagerStorage();
        require(!$.blacklisted[_msgSender()], "ShareManager: sender address is blacklisted");
        require(!$.blacklisted[to], "ShareManager: receiver address is blacklisted");
        return super.transfer(to, amount);
    }

    function pause() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        _unpause();
    }

    function addMinter(address pipe) external onlyTimelock {
        require(pipe != address(0), "ShareManager: zero address");
        grantRole(MINTER_ROLE, pipe);
    }

    function addBurner(address dst) external onlyTimelock {
        require(dst != address(0), "ShareManager: zero address");
        grantRole(BURNER_ROLE, dst);
    }

    function removeMinter(address pipe) external onlyTimelock {
        revokeRole(MINTER_ROLE, pipe);
    }

    function removeBurner(address dst) external onlyTimelock {
        revokeRole(BURNER_ROLE, dst);
    }

    function addFeeCollector(address feeCollector) external onlyTimelock {
        require(feeCollector != address(0), "ShareManager: zero address");
        grantRole(FEE_COLLECTOR_ROLE, feeCollector);
    }

    function removeFeeCollector(address feeCollector) external onlyTimelock {
        revokeRole(FEE_COLLECTOR_ROLE, feeCollector);
    }

    function setOVaultComposerMulti(address oVaultComposerMulti, address shareOftAdapter) external onlyTimelock {
        require(oVaultComposerMulti != address(0), "ShareManager: zero address");
        ShareManagerStorage storage $ = _getShareManagerStorage();
        address oldOVaultComposerMulti = $.oVaultComposerMulti;
        $.isOperator[oVaultComposerMulti][shareOftAdapter] = true;
        $.oVaultComposerMulti = oVaultComposerMulti;
        emit OVaultComposerMultiSet(oldOVaultComposerMulti, oVaultComposerMulti, shareOftAdapter);
    }

    function setMaxDeposit(uint256 _maxDeposit) external onlyTimelock {
        require(_maxDeposit > 0, "ShareManager: zero max deposit");
        ShareManagerStorage storage $ = _getShareManagerStorage();
        uint256 oldMaxDeposit = $.maxDeposit;
        $.maxDeposit = _maxDeposit;
        emit MaxDepositSet(oldMaxDeposit, _maxDeposit);
    }

    function setMaxSupply(uint256 _maxSupply) external onlyTimelock {
        require(_maxSupply > 0, "ShareManager: zero max supply");
        ShareManagerStorage storage $ = _getShareManagerStorage();
        uint256 oldMaxSupply = $.maxSupply;
        $.maxSupply = _maxSupply;
        emit MaxSupplySet(oldMaxSupply, _maxSupply);
    }

    function setMaxWithdraw(uint256 _maxWithdraw) external onlyTimelock {
        require(_maxWithdraw > 0, "ShareManager: zero max withdraw");
        ShareManagerStorage storage $ = _getShareManagerStorage();
        uint256 oldMaxWithdraw = $.maxWithdraw;
        $.maxWithdraw = _maxWithdraw;
        emit MaxWithdrawSet(oldMaxWithdraw, _maxWithdraw);
    }

    function setBlacklist(address account, bool blacklisted) external onlyRole(SAFE_MANAGER_ROLE) {
        require(account != address(0), "ShareManager: zero address");
        ShareManagerStorage storage $ = _getShareManagerStorage();
        require($.blacklisted[account] != blacklisted, "ShareManager: status unchanged");
        $.blacklisted[account] = blacklisted;
        if (blacklisted) {
          emit Blacklisted(account);
        } else {
          emit Unblacklisted(account);
        }
    }

    function isBlacklisted(address account) public view returns (bool) {
        return _getShareManagerStorage().blacklisted[account];
    }

    function maxDeposit() public view returns (uint256) {
        return _getShareManagerStorage().maxDeposit;
    }

    function maxSupply() public view returns (uint256) {
        return _getShareManagerStorage().maxSupply;
    }

    function maxWithdraw() public view returns (uint256) {
        return _getShareManagerStorage().maxWithdraw;
    }

    function timeLockController() external view returns (address) {
        return _getShareManagerStorage().timeLockController;
    }

    function oVaultComposerMulti() external view returns (address) {
        return _getShareManagerStorage().oVaultComposerMulti;
    }
}
