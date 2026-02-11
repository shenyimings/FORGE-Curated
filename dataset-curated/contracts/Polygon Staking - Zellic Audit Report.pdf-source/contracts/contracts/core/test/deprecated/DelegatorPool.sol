// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./RewardsPoolControllerV1.sol";
import "../../interfaces/IStakingAllowance.sol";

interface IPoolRouter {
    function isReservedMode() external view returns (bool);

    function getReservedMultiplier() external view returns (uint256);
}

interface ISDLPool {
    function migrate(address _account, uint256 _amount, uint64 _lockingDuration) external;
}

/**
 * @title Delegator Pool
 * @notice Allows users to stake allowance tokens and receive a percentage of earned rewards
 */
contract DelegatorPool is RewardsPoolControllerV1 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct VestingSchedule {
        uint256 totalAmount;
        uint64 startTimestamp;
        uint64 durationSeconds;
    }

    IERC20Upgradeable public allowanceToken;
    IPoolRouter public poolRouter;
    address public feeCurve; // unused

    mapping(address => VestingSchedule) private vestingSchedules; // unused

    mapping(address => uint256) private lockedBalances;
    mapping(address => uint256) private lockedApprovals;
    mapping(address => bool) public communityPools;
    uint256 public totalLocked;

    address public sdlPool;

    event AllowanceStaked(address indexed user, uint256 amount);
    event AllowanceWithdrawn(address indexed user, uint256 amount);
    event Migration(address indexed user, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _allowanceToken,
        string calldata _dTokenName,
        string calldata _dTokenSymbol,
        address[] calldata _vestingAddresses
    ) public reinitializer(2) {
        if (address(allowanceToken) == address(0)) {
            __RewardsPoolController_init(_dTokenName, _dTokenSymbol);
            allowanceToken = IERC20Upgradeable(_allowanceToken);
        } else {
            for (uint256 i = 0; i < _vestingAddresses.length; ++i) {
                address account = _vestingAddresses[i];
                VestingSchedule memory vestingSchedule = vestingSchedules[account];
                lockedBalances[account] += vestingSchedule.totalAmount;
                totalLocked += vestingSchedule.totalAmount;
                delete vestingSchedules[account];
            }
        }
    }

    /**
     * @notice ERC677 implementation to stake allowance or distribute rewards
     * @param _sender of the stake
     * @param _value of the token transfer
     * @param _calldata encoded locked allowance amount if applicable
     **/
    function onTokenTransfer(
        address _sender,
        uint256 _value,
        bytes calldata _calldata
    ) external override {
        require(sdlPool == address(0), "Deposits disabled");
        require(
            msg.sender == address(allowanceToken) || isTokenSupported(msg.sender),
            "Sender must be allowance or rewards token"
        );

        if (msg.sender == address(allowanceToken)) {
            _stakeAllowance(_sender, _value);
            if (_calldata.length != 0) {
                uint256 lockedAmount = abi.decode(_calldata, (uint256));
                require(_value >= lockedAmount, "Cannot lock more than transferred value");
                lockedBalances[_sender] += lockedAmount;
                totalLocked += lockedAmount;
            }
        } else {
            distributeToken(msg.sender);
        }
    }

    /**
     * @notice receipt tokens within the delegator pool cannot be transferred
     */
    function _transfer(address, address, uint256) internal override {
        revert("Token cannot be transferred");
    }

    /**
     * @notice returns an account's staked amount for use by reward pools
     * controlled by this contract
     * @dev excludes locked balances for community pools
     * @param _account account address
     * @return account's staked amount
     */
    function staked(address _account) external view override returns (uint256) {
        return
            communityPools[msg.sender]
                ? balanceOf(_account) - lockedBalances[_account]
                : balanceOf(_account);
    }

    /**
     * @notice returns an accounts balance
     * @dev required for backwards compatability with the PoolRouter
     * @param _account account address
     * @return balance accounts balance
     */
    function totalBalanceOf(address _account) external view returns (uint256) {
        return balanceOf(_account);
    }

    /**
     * @notice returns the total staked amount for use by reward pools
     * controlled by this contract
     * @return total staked amount
     */
    function totalStaked() external view override returns (uint256) {
        return communityPools[msg.sender] ? totalSupply() - totalLocked : totalSupply();
    }

    /**
     * @notice returns the available balance of an account, taking into account any locked and approved tokens
     * @param _account account address
     * @return available balance
     */
    function availableBalanceOf(address _account) public view returns (uint256) {
        return balanceOf(_account) - lockedBalances[_account] + lockedApprovals[_account];
    }

    /**
     * @notice returns the locked balance for a given account
     * @param _account account address
     * @return locked balance
     */
    function lockedBalanceOf(address _account) public view returns (uint256) {
        return lockedBalances[_account] - lockedApprovals[_account];
    }

    /**
     * @notice returns the approved locked balance for a given account
     * @param _account account address
     * @return approved locked balance
     */
    function approvedLockedBalanceOf(address _account) external view returns (uint256) {
        return lockedApprovals[_account];
    }

    /**
     * @notice withdraws allowance tokens if no pools are in reserve mode
     * @param _amount amount to withdraw
     **/
    function withdrawAllowance(uint256 _amount) external updateRewards(msg.sender) {
        require(
            availableBalanceOf(msg.sender) >= _amount,
            "Withdrawal amount exceeds available balance"
        );

        uint256 unlockedBalance = balanceOf(msg.sender) - lockedBalances[msg.sender];
        if (_amount > unlockedBalance) {
            uint256 approvedAmountToUnlock = _amount - unlockedBalance;
            lockedApprovals[msg.sender] -= approvedAmountToUnlock;
            lockedBalances[msg.sender] -= approvedAmountToUnlock;
            totalLocked -= approvedAmountToUnlock;
        }

        _burn(msg.sender, _amount);
        emit AllowanceWithdrawn(msg.sender, _amount);

        allowanceToken.safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice approves an amount of locked balances to be withdrawn
     * @param _account account to approve locked balance
     * @param _amount account to approve
     */
    function setLockedApproval(address _account, uint256 _amount) external onlyOwner {
        require(lockedBalances[_account] >= _amount, "Cannot approve more than locked balance");
        lockedApprovals[_account] = _amount;
    }

    /**
     * @notice burns an amount of an accounts locked allowance token
     * @param _account account to burn tokens
     * @param _amount amount of tokens to burn
     */
    function burnLockedBalance(address _account, uint256 _amount) external onlyOwner {
        require(lockedBalances[_account] >= _amount, "Cannot burn more than locked balance");

        uint256 lockedApproval = lockedApprovals[_account];
        if (lockedApproval != 0 && _amount >= lockedApproval) {
            delete lockedApprovals[_account];
        } else if (lockedApproval != 0) {
            lockedApprovals[_account] -= _amount;
        }
        lockedBalances[_account] -= _amount;
        totalLocked -= _amount;

        _burn(_account, _amount);
        IStakingAllowance(address(allowanceToken)).burn(_amount);
    }

    /**
     * @notice sets the pool router address
     * @param _poolRouter pool router address
     **/
    function setPoolRouter(address _poolRouter) external onlyOwner {
        require(address(poolRouter) == address(0), "pool router already set");
        poolRouter = IPoolRouter(_poolRouter);
    }

    /**
     * @notice sets whether a given token pool is a community pool
     * @param _pool address of token pool
     * @param _isCommunityPool is community pool
     */
    function setCommunityPool(address _pool, bool _isCommunityPool) external onlyOwner {
        require(address(tokenPools[_pool]) != address(0), "Token pool must exist");
        communityPools[address(tokenPools[_pool])] = _isCommunityPool;
    }

    /**
     * @notice retires the contract
     * @param _lockedAddresses list of all operator addresses with a locked balance
     */
    function retireDelegatorPool(
        address[] calldata _lockedAddresses,
        address _sdlPool
    ) external onlyOwner {
        require(_sdlPool != address(0), "Invalid address");
        allowanceToken.approve(_sdlPool, type(uint256).max);

        IRewardsPool rewardsPool = tokenPools[tokens[0]];
        uint256 toBurn;

        for (uint256 i = 0; i < _lockedAddresses.length; ++i) {
            address account = _lockedAddresses[i];
            uint256 unlockedBalance = availableBalanceOf(account);
            toBurn += lockedBalanceOf(account);

            rewardsPool.withdraw(account);

            _burn(account, balanceOf(account));
            delete lockedBalances[account];
            delete lockedApprovals[account];

            if (unlockedBalance != 0) {
                ISDLPool(_sdlPool).migrate(account, unlockedBalance, 0);
                emit Migration(account, unlockedBalance);
            }
        }

        IStakingAllowance(address(allowanceToken)).burn(toBurn);
        totalLocked -= toBurn;
        sdlPool = _sdlPool;
    }

    /**
     * @notice migrates a stake to the new SDL pool
     * @param _amount amount of tokens to migrate
     * @param _lockingDuration duration of the lock in the SDL pool
     */
    function migrate(uint256 _amount, uint64 _lockingDuration) external {
        require(sdlPool != address(0), "Cannot migrate until contract is retired");
        require(_amount != 0, "Invalid amount");
        require(_amount <= availableBalanceOf(msg.sender), "Insufficient balance");

        tokenPools[tokens[0]].withdraw(msg.sender);

        _burn(msg.sender, _amount);
        ISDLPool(sdlPool).migrate(msg.sender, _amount, _lockingDuration);

        emit Migration(msg.sender, _amount);
    }

    /**
     * @notice stakes allowance tokens
     * @param _sender account to stake for
     * @param _amount amount to stake
     **/
    function _stakeAllowance(address _sender, uint256 _amount) private updateRewards(_sender) {
        _mint(_sender, _amount);
        emit AllowanceStaked(_sender, _amount);
    }
}
