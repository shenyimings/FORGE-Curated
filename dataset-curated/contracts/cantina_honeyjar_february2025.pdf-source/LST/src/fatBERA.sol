// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                          INTERFACES                        */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

contract fatBERA is
    ERC4626Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          ERRORS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error ZeroPrincipal();
    error ExceedsPrincipal();
    error ZeroRewards();
    error ExceedsMaxDeposits();
    error ExceedsAvailableRewards();
    error InvalidToken();
    error ZeroShares();
    error ExceedsMaxRewardsTokens();
    error RewardsDurationNotSet();
    error RewardPeriodStillActive();
    error ZeroRewardDuration();
    error CannotDepositToVault();
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct RewardData {
        uint256 rewardPerShareStored;
        uint256 totalRewards;
        uint256 rewardsDuration;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 remainingRewards;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          Events                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event RewardAdded(address indexed token, uint256 rewardAmount);
    event RewardsDurationUpdated(address indexed token, uint256 newDuration);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 public depositPrincipal;
    uint256 public maxDeposits;

    mapping(address => RewardData) public rewardData;
    mapping(address => mapping(address => uint256)) public userRewardPerSharePaid;
    mapping(address => mapping(address => uint256)) public rewards;

    address[] public rewardTokens;
    mapping(address => bool) public isRewardToken;
    uint256 public MAX_REWARDS_TOKENS;

    bytes32 public constant REWARD_NOTIFIER_ROLE = keccak256("REWARD_NOTIFIER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    mapping(address => uint256) public vaultedShares;
    mapping(address => bool) public isWhitelistedVault;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          CONSTRUCTOR                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Contract constructor.
     * @dev Disables initializers to prevent misuse.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          Events                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Initializes the contract variables and parent contracts.
     * @param _asset The address of the underlying asset.
     * @param _owner The admin owner address.
     * @param _maxDeposits The maximum deposit limit.
     * @dev Calls initializer functions from parent contracts and sets up admin roles.
     */
    function initialize(address _asset, address _owner, uint256 _maxDeposits) external initializer {
        __ERC4626_init(IERC20(_asset));
        __ERC20_init("fatBERA", "fatBERA");
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(REWARD_NOTIFIER_ROLE, _owner);
        _grantRole(PAUSER_ROLE, _owner);

        MAX_REWARDS_TOKENS = 10;

        maxDeposits = _maxDeposits;
        _pause();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          OWNER LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Pauses contract operations.
     * @dev Can be called by accounts with PAUSER_ROLE for quick emergency response.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses contract operations.
     * @dev Only callable by admin after thorough review of the emergency situation.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Sets the maximum number of allowed reward tokens.
     * @param newMax The new maximum reward tokens.
     * @dev Only callable by admin.
     */
    function setMaxRewardsTokens(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        MAX_REWARDS_TOKENS = newMax;
    }

    /**
     * @notice Withdraws the accumulated rounding losses for a specific reward token.
     * @param token The address of the reward token.
     * @param receiver The address receiving the rounded lost rewards.
     * @dev Only callable by admin.
     */
    function withdrawRemainingRewards(address token, address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = rewardData[token].remainingRewards;
        rewardData[token].remainingRewards = 0;
        IERC20(token).safeTransfer(receiver, amount);
    }

    /**
     * @notice Authorizes an upgrade of the contract implementation.
     * @param newImplementation The address of the new implementation.
     * @dev Only callable by admin.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * @notice Updates the maximum deposit limit.
     * @param newMax The new maximum deposit limit.
     * @dev If newMax is less than depositPrincipal, maxDeposits is set to depositPrincipal to halt deposits.
     */
    function setMaxDeposits(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxDeposits = newMax < depositPrincipal ? depositPrincipal : newMax;
    }

    /**
     * @notice Allows admin to withdraw principal deposits.
     * @param assets The amount of principal tokens to withdraw.
     * @param receiver The address receiving the withdrawn tokens.
     * @dev Reverts if assets is zero or exceeds the deposit principal.
     */
    function withdrawPrincipal(uint256 assets, address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (assets == 0) revert ZeroPrincipal();
        if (assets > depositPrincipal) revert ExceedsPrincipal();

        depositPrincipal -= assets;
        IERC20(asset()).safeTransfer(receiver, assets);
    }

    /**
     * @notice Notifies the contract of new reward tokens.
     * @param token The address of the reward token.
     * @param rewardAmount The amount of reward tokens to distribute.
     * @dev Updates reward rate and accumulates any rounding losses, ensuring exact division when reward period has ended.
     */
    function notifyRewardAmount(address token, uint256 rewardAmount) external onlyRole(REWARD_NOTIFIER_ROLE) {
        if (rewardAmount == 0) revert ZeroRewards();
        if (token == address(0) || token == address(this)) revert InvalidToken();

        uint256 totalSharesCurrent = totalSupply();
        if (totalSharesCurrent == 0) revert ZeroShares();

        IERC20 rewardToken = IERC20(token);
        rewardToken.safeTransferFrom(msg.sender, address(this), rewardAmount);

        // Add to reward tokens list if new
        if (!isRewardToken[token]) {
            rewardTokens.push(token);
            if (rewardTokens.length > MAX_REWARDS_TOKENS) revert ExceedsMaxRewardsTokens();
            isRewardToken[token] = true;
        }

        RewardData storage data = rewardData[token];
        // Ensure rewards duration is set
        if (data.rewardsDuration == 0) revert RewardsDurationNotSet();

        _updateReward(token);

        if (block.timestamp >= data.periodFinish) {
            data.rewardRate = rewardAmount / data.rewardsDuration;
            data.remainingRewards += rewardAmount - data.rewardRate * data.rewardsDuration;
        } else {
            uint256 remaining = data.periodFinish - block.timestamp;
            uint256 leftover = remaining * data.rewardRate;
            data.rewardRate = (rewardAmount + leftover) / data.rewardsDuration;
            data.remainingRewards += (rewardAmount + leftover) - data.rewardRate * data.rewardsDuration;
        }

        data.lastUpdateTime = block.timestamp;
        data.periodFinish = block.timestamp + data.rewardsDuration;
        data.totalRewards += rewardAmount;
        emit RewardAdded(token, rewardAmount);
    }

    /**
     * @notice Sets the rewards duration for a given reward token.
     * @param token The address of the reward token.
     * @param duration The new rewards duration.
     * @dev Only callable by admin after the current reward period has ended.
     */
    function setRewardsDuration(address token, uint256 duration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        RewardData storage data = rewardData[token];
        if (block.timestamp <= data.periodFinish) revert RewardPeriodStillActive();
        if (duration == 0) revert ZeroRewardDuration();
        data.rewardsDuration = duration;
        emit RewardsDurationUpdated(token, duration);
    }

    /**
     * @dev Admin function to set a whitelisted vault address.
     * Vaults are considered external contracts that hold fatBERA and
     * should not accrue rewards.
     */
    function setWhitelistedVault(address vaultAddress, bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!isWhitelistedVault[vaultAddress]) {
            _updateRewards(vaultAddress);
        }
        isWhitelistedVault[vaultAddress] = status;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        EXTERNAL LOGIC                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Returns the total assets in the vault.
     * @return The total assets, equal to the total supply.
     * @dev Overrides default behavior to ignore yield-related tokens.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return totalSupply();
    }

    /**
     * @notice Returns the maximum amount of assets that can be deposited.
     * @return The available deposit amount.
     * @dev The input parameter is unused; functionality is based solely on maxDeposits.
     */
    function maxDeposit(address) public view virtual override returns (uint256) {
        if (totalSupply() >= maxDeposits) return 0;
        return maxDeposits - totalSupply();
    }

    /**
     * @notice Returns the maximum number of shares that can be minted.
     * @param receiver The address for which to query.
     * @return The maximum shares that can be minted.
     * @dev Since shares map 1:1 to assets, this is equal to maxDeposit.
     */
    function maxMint(address receiver) public view virtual override returns (uint256) {
        return maxDeposit(receiver);
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn.
     * @return Always returns 0.
     * @dev The input parameter is unused; withdrawals are currently disabled.
     */
    function maxWithdraw(address) public view virtual override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the maximum number of shares that can be redeemed.
     * @return Always returns 0.
     * @dev The input parameter is unused; withdrawals are currently disabled.
     */
    function maxRedeem(address) public view virtual override returns (uint256) {
        return 0;
    }

    /**
     * @notice Deposits native ETH, wraps it, and mints vault shares.
     * @param receiver The address receiving the minted shares.
     * @return The number of shares minted.
     * @dev Wraps ETH to WBERA and bypasses ERC4626 deposit since assets are already provided.
     */
    function depositNative(address receiver) external payable nonReentrant returns (uint256) {
        if (msg.value == 0) revert ZeroPrincipal();
        if (msg.value > maxDeposit(receiver)) revert ExceedsMaxDeposits();
        if (isWhitelistedVault[receiver]) revert CannotDepositToVault();
        _updateRewards(receiver);

        // Wrap native token
        IWETH weth = IWETH(asset());
        weth.deposit{value: msg.value}();

        // Calculate shares using previewDeposit
        uint256 shares = previewDeposit(msg.value);

        // Bypass ERC4626 deposit and mint directly (assets already held)
        _mint(receiver, shares);
        depositPrincipal += msg.value;

        // Emit Deposit event to match ERC4626 spec
        emit Deposit(msg.sender, receiver, msg.value, shares);

        return shares;
    }

    /**
     * @notice Deposits assets into the vault and updates rewards.
     * @param assets The amount of assets to deposit.
     * @param receiver The address receiving the shares.
     * @return The number of shares minted.
     * @dev Overrides the parent deposit function and increments depositPrincipal.
     */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        if (isWhitelistedVault[receiver]) revert CannotDepositToVault();
        _updateRewards(receiver);

        uint256 sharesMinted = super.deposit(assets, receiver);
        depositPrincipal += assets;

        return sharesMinted;
    }

    /**
     * @notice Mints shares by depositing assets.
     * @param shares The number of shares to mint.
     * @param receiver The address receiving the minted shares.
     * @return The amount of assets required.
     * @dev Overrides the parent mint function and increments depositPrincipal.
     */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        if (isWhitelistedVault[receiver]) revert CannotDepositToVault();
        _updateRewards(receiver);

        uint256 assetsRequired = super.previewMint(shares);
        assetsRequired = super.mint(shares, receiver);
        depositPrincipal += assetsRequired;

        return assetsRequired;
    }
    /**
     * @notice Claims accrued rewards for a specific reward token.
     * @param token The address of the reward token.
     * @param receiver The address receiving the claimed rewards.
     * @dev Updates rewards prior to claiming and resets the user's reward balance.
     */

    function claimRewards(address token, address receiver) public nonReentrant {
        _updateRewards(msg.sender, token);

        uint256 reward = rewards[token][msg.sender];
        if (reward > 0) {
            rewards[token][msg.sender] = 0;
            IERC20(token).safeTransfer(receiver, reward);
        }
    }

    /**
     * @notice Claims accrued rewards for all reward tokens.
     * @param receiver The address receiving the claimed rewards.
     * @dev Iterates through all reward tokens and claims each one.
     */
    function claimRewards(address receiver) public {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            claimRewards(rewardTokens[i], receiver);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                WITHDRAWALS ARENT ENABLED YET               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Withdraws assets from the vault.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address receiving the assets.
     * @param owner The owner of the shares to be withdrawn.
     * @return The number of burned shares.
     * @dev Updates rewards and decrements depositPrincipal. Withdrawals are subject to pause conditions.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenNotPaused
        returns (uint256)
    {
        _updateRewards(owner);

        uint256 burnedShares = super.withdraw(assets, receiver, owner);
        depositPrincipal -= assets;

        return burnedShares;
    }

    /**
     * @notice Redeems shares for the underlying assets.
     * @param shares The number of shares to redeem.
     * @param receiver The address receiving the assets.
     * @param owner The owner of the shares.
     * @return The amount of redeemed assets.
     * @dev Updates rewards and decrements depositPrincipal. Withdrawals are subject to pause conditions.
     */
    function redeem(uint256 shares, address receiver, address owner) public override whenNotPaused returns (uint256) {
        _updateRewards(owner);

        uint256 redeemedAssets = super.redeem(shares, receiver, owner);
        depositPrincipal -= redeemedAssets;

        return redeemedAssets;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          VIEW LOGIC                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Simulates the effects of withdrawing assets at the current block.
     * @return Returns 0 if paused, otherwise returns the standard ERC4626 preview calculation.
     * @dev Overridden to maintain consistency with maxWithdraw when paused.
     */
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        if (paused()) return 0;
        return super.previewWithdraw(assets);
    }

    /**
     * @notice Simulates the effects of redeeming shares at the current block.
     * @return Returns 0 if paused, otherwise returns the standard ERC4626 preview calculation.
     * @dev Overridden to maintain consistency with maxRedeem when paused.
     */
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        if (paused()) return 0;
        return super.previewRedeem(shares);
    }

    /**
     * @dev Returns the effective balance of an account for reward calculations.
     * For a regular (non-vault) user, effective balance = wallet balance + vaultedShares.
     * For a whitelisted vault, effective balance is 0.
     */
    function effectiveBalance(address account) public view returns (uint256) {
        if (isWhitelistedVault[account]) return 0;
        return balanceOf(account) + vaultedShares[account];
    }

    function previewRewards(address account, address token) external view returns (uint256) {
        RewardData storage data = rewardData[token];
        uint256 currentRewardPerShare = data.rewardPerShareStored;
        uint256 supply = totalSupply();
        if (supply > 0) {
            uint256 lastApplicable = block.timestamp < data.periodFinish ? block.timestamp : data.periodFinish;
            uint256 elapsed = lastApplicable - data.lastUpdateTime;
            uint256 additional = FixedPointMathLib.fullMulDiv(elapsed * data.rewardRate, 1e36, supply);
            currentRewardPerShare += additional;
        }
        return rewards[token][account]
            + FixedPointMathLib.fullMulDiv(
                effectiveBalance(account), currentRewardPerShare - userRewardPerSharePaid[token][account], 1e36
            );
    }

    /**
     * @notice Retrieves the list of reward tokens.
     * @return An array containing the addresses of all reward tokens.
     * @dev Helper function for frontend and external integrations.
     */
    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Hook to update rewards during token transfers.
     * @param from The sender address.
     * @param to The recipient address.
     * @dev Only updates rewards if both addresses are non-zero.
     */
    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            if (!isWhitelistedVault[from] && isWhitelistedVault[to]) {
                // Depositing to a whitelisted vault.
                _updateRewards(from);
                vaultedShares[from] += amount;
            } else if (isWhitelistedVault[from] && !isWhitelistedVault[to]) {
                // Withdrawing from a whitelisted vault.
                _updateRewards(to);
                if (vaultedShares[to] < amount) revert("Insufficient vaulted shares");
                vaultedShares[to] -= amount;
            } else {
                // Normal transfer between non‑vault addresses (or vault <-> vault, though vaults have no effective balance).
                _updateRewards(from);
                _updateRewards(to);
            }
        }
        super._update(from, to, amount);
    }

    /**
     * @notice Updates rewards for all reward tokens for a given account.
     * @param account The address for which rewards are updated.
     * @dev Iterates over each reward token and calls _updateRewards for individual tokens.
     */
    function _updateRewards(address account) internal {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            _updateRewards(account, rewardTokens[i]);
        }
    }

    /**
     * @notice Updates rewards for a specific reward token for an account.
     * @param account The address for which rewards are updated.
     * @param token The reward token address.
     * @dev Updates global reward data before calculating and storing user-specific rewards.
     */
    function _updateRewards(address account, address token) internal {
        _updateReward(token);
        RewardData storage data = rewardData[token];
        uint256 effectiveBal = effectiveBalance(account);
        if (effectiveBal > 0) {
            uint256 earned = data.rewardPerShareStored - userRewardPerSharePaid[token][account];
            rewards[token][account] += FixedPointMathLib.fullMulDiv(effectiveBal, earned, 1e36);
        }
        userRewardPerSharePaid[token][account] = data.rewardPerShareStored;
    }

    /**
     * @notice Updates the global reward data for a specific token.
     * @param token The reward token address.
     * @dev Computes additional reward per share based on elapsed time and updates last update time.
     */
    function _updateReward(address token) internal {
        RewardData storage data = rewardData[token];
        uint256 lastApplicable = block.timestamp < data.periodFinish ? block.timestamp : data.periodFinish;
        if (totalSupply() > 0) {
            uint256 elapsed = lastApplicable - data.lastUpdateTime;
            if (elapsed > 0) {
                uint256 additional = FixedPointMathLib.fullMulDiv(elapsed * data.rewardRate, 1e36, totalSupply());
                data.rewardPerShareStored += additional;
            }
        }
        data.lastUpdateTime = lastApplicable;
    }
}
