// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;
import './Interface.sol';
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "forge-std/console.sol";

contract AssetLocking is Initializable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    event SetEpoch(address token, uint8 oldEpoch, uint8 newEpoch);
    event UpdateLockConfig(address token, uint8 epoch, uint256 lockLimit, uint48 cooldown);
    event Lock(address locker, address token, uint256 amount);
    event UnLock(address locker, address token, uint256 amount);
    event Withdraw(address locker, address token, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
        __Pausable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    uint48 public constant MAX_COOLDOWN = 90 days;

    struct LockConfig {
        uint8 epoch;
        uint256 lockLimit;
        uint48 cooldown;
        uint256 totalLock;
        uint256 totalCooldown;
    }

    struct LockData {
        uint256 amount;
        uint256 cooldownAmount;
        uint256 cooldownEndTimestamp;
    }

    EnumerableSet.AddressSet tokens_;
    mapping(address => uint8) public activeEpochs;
    mapping(address => LockConfig) public lockConfigs;
    mapping(address => mapping (address => LockData)) public lockDatas;

    function setEpoch(address token, uint8 newEpoch) external onlyOwner {
        uint8 oldEpoch = activeEpochs[token];
        require(newEpoch != activeEpochs[token], "epoch not change");
        activeEpochs[token] = newEpoch;
        emit SetEpoch(token, oldEpoch, newEpoch);
    }

    function updateLockConfig(address token, uint8 epoch, uint256 lockLimit, uint48 cooldown) external onlyOwner {
        if (!tokens_.contains(token)) {
            tokens_.add(token);
        }
        require(cooldown <= MAX_COOLDOWN, "cooldown exceeds MAX_COOLDOWN");
        LockConfig storage lockConfig = lockConfigs[token];
        lockConfig.epoch = epoch;
        lockConfig.lockLimit = lockLimit;
        lockConfig.cooldown = cooldown;
        emit UpdateLockConfig(token, epoch, lockLimit, cooldown);
    }

    function getActiveTokens() external view returns (address[] memory tokens)  {
        address[] memory tmp = new address[](tokens_.length());
        uint j = 0;
        for (uint i = 0; i < tokens_.length(); i++) {
            address token = tokens_.at(i);
            if (lockConfigs[token].epoch == activeEpochs[token]) {
                tmp[j] = token;
                j += 1;
            }
        }
        tokens = new address[](j);
        for (uint i = 0; i < j; i++) {
            tokens[i] = tmp[i];
        }
    }

    function lock(address token, uint256 amount) external whenNotPaused {
        require(tokens_.contains(token), "token not supported");
        require(lockConfigs[token].epoch == activeEpochs[token], "token cannot stake now");
        LockData storage lockData = lockDatas[token][msg.sender];
        LockConfig storage lockConfig = lockConfigs[token];
        require(lockConfig.totalLock + amount <= lockConfig.lockLimit, "total lock amount exceeds lock limit");
        require(IERC20(token).allowance(msg.sender, address(this)) >= amount, "not enough allowance");
        lockData.amount += amount;
        lockConfig.totalLock += amount;
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit Lock(msg.sender, token, amount);
    }

    function unlock(address token, uint256 amount) external whenNotPaused {
        LockData storage lockData = lockDatas[token][msg.sender];
        LockConfig storage lockConfig = lockConfigs[token];
        require(lockData.amount >= amount, "not enough balance to unlock");
        lockData.amount -= amount;
        lockData.cooldownAmount += amount;
        lockData.cooldownEndTimestamp = block.timestamp + lockConfig.cooldown;
        lockConfig.totalLock -= amount;
        lockConfig.totalCooldown += amount;
        emit UnLock(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external whenNotPaused {
        LockData storage lockData = lockDatas[token][msg.sender];
        require(lockData.cooldownAmount > 0, "nothing to withdraw");
        require(lockData.cooldownEndTimestamp <= block.timestamp, "coolingdown");
        require(amount <= lockData.cooldownAmount, "no enough balance to withdraw");
        lockData.cooldownAmount -= amount;
        LockConfig storage lockConfig = lockConfigs[token];
        lockConfig.totalCooldown -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, token, amount);
    }
}