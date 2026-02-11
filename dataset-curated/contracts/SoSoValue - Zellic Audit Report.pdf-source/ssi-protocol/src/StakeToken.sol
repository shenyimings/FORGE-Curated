// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;
import './Interface.sol';
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
// import "forge-std/console.sol";

contract StakeToken is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    address public token;
    uint48 public cooldown;
    uint48 public constant MAX_COOLDOWN = 30 days;

    struct CooldownInfo {
        uint256 cooldownAmount;
        uint256 cooldownEndTimestamp;
    }

    mapping(address => CooldownInfo) public cooldownInfos;

    event Stake(address staker, uint256 amount);
    event UnStake(address unstaker, uint256 amount);
    event Withdraw(address withdrawer, uint256 amount);
    event SetCooldown(uint48 oldCooldown, uint48 cooldown);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address token_,
        uint48 cooldown_,
        address owner_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
        __Pausable_init();
        require(token_ != address(0), "token address is zero");
        require(cooldown_ < MAX_COOLDOWN, "cooldown exceeds MAX_COOLDOWN");
        token = token_;
        cooldown = cooldown_;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function decimals() public view override(ERC20Upgradeable) returns (uint8) {
        return ERC20Upgradeable(token).decimals();
    }

    function stake(uint256 amount) external whenNotPaused {
        require(amount > 0, "amount is zero");
        require(IERC20(token).allowance(msg.sender, address(this)) >= amount, "not enough allowance");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
        emit Stake(msg.sender, amount);
    }

    function unstake(uint256 amount) external whenNotPaused {
        require(amount > 0, "amount is zero");
        CooldownInfo storage cooldownInfo = cooldownInfos[msg.sender];
        require(amount <= balanceOf(msg.sender), "not enough to unstake");
        cooldownInfo.cooldownAmount += amount;
        cooldownInfo.cooldownEndTimestamp = block.timestamp + cooldown;
        _burn(msg.sender, amount);
        emit UnStake(msg.sender, amount);
    }

    function withdraw(uint256 amount) external whenNotPaused {
        require(amount > 0, "amount is zero");
        CooldownInfo storage cooldownInfo = cooldownInfos[msg.sender];
        require(cooldownInfo.cooldownAmount >= amount, "not enough cooldown amount");
        require(cooldownInfo.cooldownEndTimestamp <= block.timestamp, "cooldowning");
        cooldownInfo.cooldownAmount -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function setCooldown(uint48 cooldown_) external onlyOwner {
        require(cooldown != cooldown_, "cooldown not change");
        require(cooldown_ < MAX_COOLDOWN, "cooldown exceeds MAX_COOLDOWN");
        emit SetCooldown(cooldown, cooldown_);
        cooldown = cooldown_;
    }
}