// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "../interfaces/IStakingPool.sol";
import "../interfaces/ISDLPool.sol";
import "../interfaces/IWithdrawalPool.sol";

/**
 * @title Priority Pool
 * @notice Allows users to queue asset tokens which are eventually deposited into the staking pool when space becomes available -
 * liquid staking tokens minted by the staking pool are then distributed using a merkle tree
 */
contract PriorityPool is UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    enum PoolStatus {
        OPEN,
        DRAINING,
        CLOSED
    }

    // address of staking asset token
    IERC20Upgradeable public token;
    // address of staking pool and liquid staking token
    IStakingPool public stakingPool;
    // address of SDL pool
    ISDLPool public sdlPool;
    // address of oracle contract that handles LST distribution
    address public distributionOracle;

    // min amount of tokens that can be deposited into the staking pool strategies in a single tx
    uint128 public queueDepositMin;
    // max amount of tokens that can be deposited into the staking pool strategies in a single tx
    uint128 public queueDepositMax;
    // current status of the pool
    PoolStatus public poolStatus;

    // merkle root for the latest distribution tree
    bytes32 public merkleRoot;
    // ipfs hash where the latest distribution tree is stored
    bytes32 public ipfsHash;
    // number of entries in the latest distribution tree
    uint256 public merkleTreeSize;

    // total number of tokens queued for deposit into the staking pool
    uint256 public totalQueued;
    // total number of tokens deposited into the staking pool or swapped for LSTs since the last distribution
    uint256 public depositsSinceLastUpdate;
    // total number of shares received for depositsSinceLastUpdate
    uint256 private sharesSinceLastUpdate;

    // list of all accounts that have ever queued tokens
    address[] private accounts;
    // stores each account's index in the distribution tree
    mapping(address => uint256) private accountIndexes;
    // stores the lifetime amount of queued tokens for each account less any tokens that were unqueued
    mapping(address => uint256) private accountQueuedTokens;
    // stores the total amount of LSTs that each account has claimed
    mapping(address => uint256) private accountClaimed;
    // stored the total amount of LST shares that each account has claimed
    mapping(address => uint256) private accountSharesClaimed;

    // address with authorization to pause the pool
    address public rebaseController;

    // address of withdrawal pool
    IWithdrawalPool public withdrawalPool;
    // whether instant withdrawals are enabled
    bool public allowInstantWithdrawals;

    event UnqueueTokens(address indexed account, uint256 amount);
    event ClaimLSDTokens(address indexed account, uint256 amount, uint256 amountWithYield);
    event Deposit(address indexed account, uint256 instantAmount, uint256 queueAmount);
    event Withdraw(address indexed account, uint256 amount);
    event UpdateDistribution(
        bytes32 merkleRoot,
        bytes32 ipfsHash,
        uint256 incrementalAmount,
        uint256 incrementalSharesAmount
    );
    event SetPoolStatus(PoolStatus status);
    event SetQueueDepositParams(uint128 queueDepositMin, uint128 queueDepositMax);
    event DepositTokens(uint256 unusedTokensAmount, uint256 queuedTokensAmount);

    error InvalidValue();
    error UnauthorizedToken();
    error InsufficientQueuedTokens();
    error InvalidProof();
    error InsufficientBalance();
    error NothingToClaim();
    error DepositsDisabled();
    error WithdrawalsDisabled();
    error InsufficientDepositRoom();
    error CannotSetClosedStatus();
    error SenderNotAuthorized();
    error InvalidAmount();
    error StatusAlreadySet();
    error InsufficientLiquidity();
    error WithdrawFailed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes contract
     * @param _token address of staking asset token
     * @param _stakingPool address of staking pool
     * @param _sdlPool address of SDL pool
     * @param _queueDepositMin min amount of tokens that can be deposited into the staking pool in a single tx
     * @param _queueDepositMax mmaxin amount of tokens that can be deposited into the staking pool in a single tx
     * @param _allowInstantWithdrawals whether instant withdrawals are enabled
     **/
    function initialize(
        address _token,
        address _stakingPool,
        address _sdlPool,
        uint128 _queueDepositMin,
        uint128 _queueDepositMax,
        bool _allowInstantWithdrawals
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __Pausable_init();
        token = IERC20Upgradeable(_token);
        stakingPool = IStakingPool(_stakingPool);
        sdlPool = ISDLPool(_sdlPool);
        queueDepositMin = _queueDepositMin;
        queueDepositMax = _queueDepositMax;
        allowInstantWithdrawals = _allowInstantWithdrawals;
        accounts.push(address(0));
        token.safeIncreaseAllowance(_stakingPool, type(uint256).max);
    }

    /**
     * @notice Reverts if sender is not distribution oracle
     **/
    modifier onlyDistributionOracle() {
        if (msg.sender != distributionOracle) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Reverts if sender is not withdrawal pool
     **/
    modifier onlyWithdrawalPool() {
        if (msg.sender != address(withdrawalPool)) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Returns a list of all accounts
     * @dev accounts are returned in the same order as they are in the merkle tree
     * @return list of accounts
     */
    function getAccounts() external view returns (address[] memory) {
        return accounts;
    }

    /**
     * @notice Returns the index of an account
     * @dev this index represents an account's position in the merkle tree
     * @param _account account address
     * @return account index
     */
    function getAccountIndex(address _account) external view returns (uint256) {
        return accountIndexes[_account];
    }

    /**
     * @notice Returns an account's current amount of queued tokens
     * @dev _distributionAmount is stored on IPFS
     * @param _account account address
     * @param _distributionAmount account's distribution amount from the latest distribution
     * @return amount of queued tokens for an account
     */
    function getQueuedTokens(
        address _account,
        uint256 _distributionAmount
    ) public view returns (uint256) {
        return accountQueuedTokens[_account] - _distributionAmount;
    }

    /**
     * @notice Returns an account's current amount of withdrawable liquid staking tokens
     * @dev _distributionShareAmount is stored on IPFS
     * @param _account account address
     * @param _distributionShareAmount account's distribution share amounts from the latest distribution
     * @return withdrawable LSD tokens for account
     */
    function getLSDTokens(
        address _account,
        uint256 _distributionShareAmount
    ) external view returns (uint256) {
        uint256 sharesToClaim = _distributionShareAmount - accountSharesClaimed[_account];
        return stakingPool.getStakeByShares(sharesToClaim);
    }

    /**
     * @notice Returns the current amount of withdrawable LSD tokens for multiple accounts
     * @dev _distributionShareAmounts are stored on IPFS and should align with the provided accounts
     * @param _accounts List of account addresses
     * @param _distributionShareAmounts List of distribution share amounts corresponding to each account
     * @return Array of withdrawable LSD token amounts for each account
     */
    function getLSDTokensBatch(
        address[] calldata _accounts,
        uint256[] calldata _distributionShareAmounts
    ) external view returns (uint256[] memory) {
        uint256[] memory withdrawableAmounts = new uint256[](_accounts.length);

        for (uint256 i = 0; i < _accounts.length; i++) {
            address account = _accounts[i];
            uint256 sharesToClaim = _distributionShareAmounts[i] - accountSharesClaimed[account];
            withdrawableAmounts[i] = stakingPool.getStakeByShares(sharesToClaim);
        }

        return withdrawableAmounts;
    }

    /**
     * @notice Returns the total amount of asset tokens that an account can withdraw
     * @dev includes account's queued tokens and LST balance and checks both priority pool
     * and staking pool liquidity
     * @dev _distributionAmount is stored on IPFS
     * @param _account account address
     * @param _distributionAmount account's distribution amount from the latest distribution
     * @return amount of withdrawable tokens
     */
    function canWithdraw(
        address _account,
        uint256 _distributionAmount
    ) external view returns (uint256) {
        uint256 canUnqueue = paused()
            ? 0
            : MathUpgradeable.min(getQueuedTokens(_account, _distributionAmount), totalQueued);
        uint256 stLINKCanWithdraw = poolStatus == PoolStatus.CLOSED
            ? 0
            : MathUpgradeable.min(
                stakingPool.balanceOf(_account),
                (
                    ((allowInstantWithdrawals && withdrawalPool.getTotalQueuedWithdrawals() == 0) ||
                        _account == address(withdrawalPool))
                        ? stakingPool.canWithdraw()
                        : 0
                ) +
                    totalQueued -
                    canUnqueue
            );
        return canUnqueue + stLINKCanWithdraw;
    }

    /**
     * @notice ERC677 implementation to receive a token deposit or withdrawal
     * @dev can receive both asset tokens (deposit) and liquid staking tokens (withdrawal)
     * @param _sender of the token transfer
     * @param _value of the token transfer
     * @param _calldata encoded shouldQueue (bool) and deposit/withdrawal data to pass to
     * staking pool strategies (bytes[])
     **/
    function onTokenTransfer(address _sender, uint256 _value, bytes calldata _calldata) external {
        if (_value == 0) revert InvalidValue();

        (bool shouldQueue, bytes[] memory data) = abi.decode(_calldata, (bool, bytes[]));

        if (msg.sender == address(token)) {
            _deposit(_sender, _value, shouldQueue, data);
        } else if (msg.sender == address(stakingPool)) {
            uint256 amountWithdrawn = _withdraw(_sender, _value, shouldQueue, true, data);
            token.safeTransfer(_sender, amountWithdrawn);
        } else {
            revert UnauthorizedToken();
        }
    }

    /**
     * @notice Deposits asset tokens into the staking pool and/or queues them
     * @param _amount amount to deposit
     * @param _shouldQueue whether tokens should be queued if there's no room in the staking pool
     * @param _data deposit data passed to staking pool strategies
     */
    function deposit(uint256 _amount, bool _shouldQueue, bytes[] calldata _data) external {
        if (_amount == 0) revert InvalidAmount();
        token.safeTransferFrom(msg.sender, address(this), _amount);
        _deposit(msg.sender, _amount, _shouldQueue, _data);
    }

    /**
     * @notice Withdraws asset tokens
     * @dev will unqueue sender's asset tokens before swapping liquid staking tokens if there is
     * sufficient liquidity and _shouldUnqueue is set to true
     * @param _amountToWithdraw amount of tokens to withdraw
     * @param _amount amount as recorded in sender's merkle tree entry (stored on IPFS)
     * @param _sharesAmount shares amount as recorded in sender's merkle tree entry (stored on IPFS)
     * @param _merkleProof merkle proof for sender's merkle tree entry (generated using IPFS data)
     * @param _shouldUnqueue whether tokens should be unqueued before taking LSD tokens
     * @param _shouldQueueWithdrawal whether a withdrawal should be queued if the full withdrawal amount cannot be satisfied
     * @param _data list of withdrawal data passed to staking pool strategies if executing instant withdrawal
     */
    function withdraw(
        uint256 _amountToWithdraw,
        uint256 _amount,
        uint256 _sharesAmount,
        bytes32[] calldata _merkleProof,
        bool _shouldUnqueue,
        bool _shouldQueueWithdrawal,
        bytes[] calldata _data
    ) external {
        if (_amountToWithdraw == 0) revert InvalidAmount();

        uint256 toWithdraw = _amountToWithdraw;
        address account = msg.sender;

        // attempt to unqueue tokens before withdrawing if flag is set
        if (_shouldUnqueue == true) {
            _requireNotPaused();

            if (_merkleProof.length != 0) {
                bytes32 node = keccak256(
                    bytes.concat(keccak256(abi.encode(account, _amount, _sharesAmount)))
                );
                if (!MerkleProofUpgradeable.verify(_merkleProof, merkleRoot, node))
                    revert InvalidProof();
            } else if (accountIndexes[account] != 0 && accountIndexes[account] < merkleTreeSize) {
                revert InvalidProof();
            }

            uint256 queuedTokens = getQueuedTokens(account, _amount);
            uint256 canUnqueue = queuedTokens <= totalQueued ? queuedTokens : totalQueued;
            uint256 amountToUnqueue = toWithdraw <= canUnqueue ? toWithdraw : canUnqueue;

            if (amountToUnqueue != 0) {
                accountQueuedTokens[account] -= amountToUnqueue;
                totalQueued -= amountToUnqueue;
                toWithdraw -= amountToUnqueue;
                emit UnqueueTokens(account, amountToUnqueue);
            }
        }

        // attempt to withdraw if tokens remain after unqueueing
        if (toWithdraw != 0) {
            IERC20Upgradeable(address(stakingPool)).safeTransferFrom(
                account,
                address(this),
                toWithdraw
            );
            toWithdraw -= _withdraw(
                account,
                toWithdraw,
                _shouldQueueWithdrawal,
                toWithdraw == _amountToWithdraw,
                _data
            );
        }

        token.safeTransfer(account, _amountToWithdraw - toWithdraw);
    }

    /**
     * @notice Unqueues queued tokens
     * @param _amountToUnqueue amount of tokens to unqueue
     * @param _amount amount as recorded in sender's merkle tree entry (stored on IPFS)
     * @param _sharesAmount shares amount as recorded in sender's merkle tree entry (stored on IPFS)
     * @param _merkleProof merkle proof for sender's merkle tree entry (generated from IPFS data)
     */
    function unqueueTokens(
        uint256 _amountToUnqueue,
        uint256 _amount,
        uint256 _sharesAmount,
        bytes32[] calldata _merkleProof
    ) external whenNotPaused {
        if (_amountToUnqueue == 0) revert InvalidAmount();
        if (_amountToUnqueue > totalQueued) revert InsufficientQueuedTokens();

        address account = msg.sender;

        // verify merkle proof only if sender is included in tree
        if (accountIndexes[account] != 0 && accountIndexes[account] < merkleTreeSize) {
            bytes32 node = keccak256(
                bytes.concat(keccak256(abi.encode(account, _amount, _sharesAmount)))
            );
            if (!MerkleProofUpgradeable.verify(_merkleProof, merkleRoot, node))
                revert InvalidProof();
        }

        if (_amountToUnqueue > getQueuedTokens(account, _amount)) revert InsufficientBalance();

        accountQueuedTokens[account] -= _amountToUnqueue;
        totalQueued -= _amountToUnqueue;
        token.safeTransfer(account, _amountToUnqueue);

        emit UnqueueTokens(account, _amountToUnqueue);
    }

    /**
     * @notice Claims withdrawable liquid staking tokens
     * @param _amount amount as recorded in sender's merkle tree entry (stored on IPFS)
     * @param _sharesAmount shares amount as recorded in sender's merkle tree entry (stored on IPFS)
     * @param _merkleProof merkle proof for sender's merkle tree entry (generated from IPFS data)
     */
    function claimLSDTokens(
        uint256 _amount,
        uint256 _sharesAmount,
        bytes32[] calldata _merkleProof
    ) external {
        address account = msg.sender;

        bytes32 node = keccak256(
            bytes.concat(keccak256(abi.encode(account, _amount, _sharesAmount)))
        );
        if (!MerkleProofUpgradeable.verify(_merkleProof, merkleRoot, node)) revert InvalidProof();

        uint256 amountToClaim = _amount - accountClaimed[account];
        uint256 sharesAmountToClaim = _sharesAmount - accountSharesClaimed[account];
        uint256 amountToClaimWithYield = stakingPool.getStakeByShares(sharesAmountToClaim);

        if (amountToClaimWithYield == 0) revert NothingToClaim();

        accountClaimed[account] = _amount;
        accountSharesClaimed[account] = _sharesAmount;
        IERC20Upgradeable(address(stakingPool)).safeTransfer(account, amountToClaimWithYield);

        emit ClaimLSDTokens(account, amountToClaim, amountToClaimWithYield);
    }

    /**
     * @notice Deposits queued tokens and/or unused tokens sitting in staking pool
     * @dev allows bypassing of the stored deposit limits
     * @param _queueDepositMin min amount of tokens required for deposit into staking pool strategies
     * @param _queueDepositMax max amount of tokens that can be deposited into staking pool strategies at once
     * @param _data list of deposit data passed to staking pool strategies
     */
    function depositQueuedTokens(
        uint256 _queueDepositMin,
        uint256 _queueDepositMax,
        bytes[] calldata _data
    ) external {
        _depositQueuedTokens(_queueDepositMin, _queueDepositMax, _data);
    }

    /**
     * @notice Returns whether a call should be made to performUpkeep to deposit queued/unused tokens
     * into staking pool strategies
     * @return true if performUpkeep should be called, false otherwise
     * @return encoded amount of tokens to be deposited
     */
    function checkUpkeep(bytes calldata) external view returns (bool, bytes memory) {
        uint256 strategyDepositRoom = stakingPool.getStrategyDepositRoom();
        uint256 unusedDeposits = stakingPool.getUnusedDeposits();

        if (poolStatus != PoolStatus.OPEN) return (false, "");
        if (
            strategyDepositRoom < queueDepositMin ||
            (totalQueued + unusedDeposits) < queueDepositMin
        ) return (false, "");

        return (
            true,
            abi.encode(
                MathUpgradeable.min(
                    MathUpgradeable.min(strategyDepositRoom, totalQueued + unusedDeposits),
                    queueDepositMax
                )
            )
        );
    }

    /**
     * @notice Deposits queued and/or unused tokens into staking pool strategies
     * @dev will revert if less than queueDepositMin tokens can be deposited
     * @param _performData encoded list of deposit data to be passed to staking pool strategies (bytes[])
     */
    function performUpkeep(bytes calldata _performData) external {
        bytes[] memory depositData = abi.decode(_performData, (bytes[]));
        _depositQueuedTokens(queueDepositMin, queueDepositMax, depositData);
    }

    /**
     * @notice Returns the total number of tokens deposited into the staking pool or swapped for LSTs since
     * the last call to updateDistribution and the amount of shares received for those tokens
     * @return amount of deposits
     * @return amount of shares
     */
    function getDepositsSinceLastUpdate() external view returns (uint256, uint256) {
        return (depositsSinceLastUpdate, sharesSinceLastUpdate);
    }

    /**
     * @notice Returns account data used for calculating a new merkle tree
     * @dev merkle tree is calculated based on users' reSDL balance and the number of tokens they have queued
     * @dev accounts are returned in the same order as they are in the merkle tree
     * @return accounts list of all accounts that have ever queued tokens
     * @return sdlBalances list of SDL balances for each account
     * @return queuedBalances list of queued token amounts for each account (ignores previously distributed
     * liquid staking tokens)
     */
    function getAccountData()
        external
        view
        returns (address[] memory, uint256[] memory, uint256[] memory)
    {
        uint256[] memory reSDLBalances = new uint256[](accounts.length);
        uint256[] memory queuedBalances = new uint256[](accounts.length);

        for (uint256 i = 0; i < reSDLBalances.length; ++i) {
            address account = accounts[i];
            reSDLBalances[i] = address(sdlPool) == address(0)
                ? 0
                : sdlPool.effectiveBalanceOf(account);
            queuedBalances[i] = accountQueuedTokens[account];
        }

        return (accounts, reSDLBalances, queuedBalances);
    }

    /**
     * @notice Distributes a new batch of liquid staing tokens to users that have queued tokens
     * @param _merkleRoot new merkle root for the distribution tree
     * @param _ipfsHash new ipfs hash for the distribution tree (CIDv0, no prefix - only hash)
     * @param _amountDistributed amount of tokens distributed in this distribution
     * @param _sharesAmountDistributed amount of shares distributed in this distribution
     */
    function updateDistribution(
        bytes32 _merkleRoot,
        bytes32 _ipfsHash,
        uint256 _amountDistributed,
        uint256 _sharesAmountDistributed
    ) external onlyDistributionOracle {
        _unpause();

        depositsSinceLastUpdate -= _amountDistributed;
        sharesSinceLastUpdate -= _sharesAmountDistributed;
        merkleRoot = _merkleRoot;
        ipfsHash = _ipfsHash;
        merkleTreeSize = accounts.length;

        emit UpdateDistribution(
            _merkleRoot,
            _ipfsHash,
            _amountDistributed,
            _sharesAmountDistributed
        );
    }

    /**
     * @notice Pauses queueing and unqueueing so a new merkle tree can be generated
     */
    function pauseForUpdate() external onlyDistributionOracle {
        _pause();
    }

    /**
     * @notice Executes a batch of withdrawals that have been queued in the withdrawal pool
     * @dev withdraws tokens from the staking pool and sends them to the withdrawal pool
     * @param _amount total amount to withdraw
     * @param _data list of withdrawal data passed to staking pool strategies
     */
    function executeQueuedWithdrawals(
        uint256 _amount,
        bytes[] calldata _data
    ) external onlyWithdrawalPool {
        IERC20Upgradeable(address(stakingPool)).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        stakingPool.withdraw(address(this), address(this), _amount, _data);
        token.safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice Sets the pool's status
     * @param _status pool status
     */
    function setPoolStatus(PoolStatus _status) external {
        if (msg.sender != owner() && msg.sender != rebaseController) revert SenderNotAuthorized();
        if (_status == poolStatus) revert StatusAlreadySet();
        poolStatus = _status;
        emit SetPoolStatus(_status);
    }

    /**
     * @notice Sets the minimum and maximum amount that can be deposited into strategies at once
     * @param _queueDepositMin minimum amount of tokens required for deposit into staking pool strategies
     * @param _queueDepositMax maximum amount of tokens that can be deposited into staking pool strategies at once
     */
    function setQueueDepositParams(
        uint128 _queueDepositMin,
        uint128 _queueDepositMax
    ) external onlyOwner {
        queueDepositMin = _queueDepositMin;
        queueDepositMax = _queueDepositMax;
        emit SetQueueDepositParams(_queueDepositMin, _queueDepositMax);
    }

    /**
     * @notice Sets whether instant withdrawals are enabled
     * @dev if disabled, all withdrawals will be queued through the withdrawal pool
     * event if there is withdrawal room in the staking pool
     * @param _allowInstantWithdrawals true to allow instant withdrawals, false otherwise
     */
    function setAllowInstantWithdrawals(bool _allowInstantWithdrawals) external onlyOwner {
        allowInstantWithdrawals = _allowInstantWithdrawals;
    }

    /**
     * @notice Sets the distribution oracle
     * @param _distributionOracle address of oracle
     */
    function setDistributionOracle(address _distributionOracle) external onlyOwner {
        distributionOracle = _distributionOracle;
    }

    /**
     * @notice Sets the address of the rebase controller
     * @dev this address has authorization to close the pool in case of emergency
     * @param _rebaseController address of rebase controller
     */
    function setRebaseController(address _rebaseController) external onlyOwner {
        rebaseController = _rebaseController;
    }

    /**
     * @notice Sets the withdrawal pool
     * @param _withdrawalPool address of withdrawal pool
     */
    function setWithdrawalPool(address _withdrawalPool) external onlyOwner {
        if (address(withdrawalPool) != address(0)) {
            IERC20Upgradeable(address(stakingPool)).safeApprove(address(withdrawalPool), 0);
            token.safeApprove(address(withdrawalPool), 0);
        }

        IERC20Upgradeable(address(stakingPool)).safeApprove(_withdrawalPool, type(uint256).max);
        token.safeApprove(_withdrawalPool, type(uint256).max);

        withdrawalPool = IWithdrawalPool(_withdrawalPool);
    }

    /**
     * @notice Deposits asset tokens into the withdrawal pool, staking pool, and/or queues them
     * @dev tokens will be deposited into the withdrawal pool if there are queued withdrawals, then the
     * staking pool if there is deposit room. Remaining tokens will then be queued if `_shouldQueue`
     * is true, or otherwise returned to sender
     * @param _account account to deposit for
     * @param _amount amount to deposit
     * @param _shouldQueue whether tokens should be queued
     * @param _data deposit data passed to staking pool strategies
     **/
    function _deposit(
        address _account,
        uint256 _amount,
        bool _shouldQueue,
        bytes[] memory _data
    ) internal {
        if (poolStatus != PoolStatus.OPEN) revert DepositsDisabled();

        uint256 toDeposit = _amount;

        if (totalQueued == 0) {
            uint256 queuedWithdrawals = withdrawalPool.getTotalQueuedWithdrawals();
            if (queuedWithdrawals != 0) {
                uint256 toDepositIntoQueue = toDeposit <= queuedWithdrawals
                    ? toDeposit
                    : queuedWithdrawals;
                withdrawalPool.deposit(toDepositIntoQueue);
                toDeposit -= toDepositIntoQueue;
                IERC20Upgradeable(address(stakingPool)).safeTransfer(_account, toDepositIntoQueue);
            }

            if (toDeposit != 0) {
                uint256 canDeposit = stakingPool.canDeposit();
                if (canDeposit != 0) {
                    uint256 toDepositIntoPool = toDeposit <= canDeposit ? toDeposit : canDeposit;
                    stakingPool.deposit(_account, toDepositIntoPool, _data);
                    toDeposit -= toDepositIntoPool;
                }
            }
        }

        if (toDeposit != 0) {
            if (_shouldQueue) {
                _requireNotPaused();
                if (accountIndexes[_account] == 0) {
                    accounts.push(_account);
                    accountIndexes[_account] = accounts.length - 1;
                }
                accountQueuedTokens[_account] += toDeposit;
                totalQueued += toDeposit;
            } else {
                token.safeTransfer(_account, toDeposit);
            }
        }

        emit Deposit(_account, _amount - toDeposit, _shouldQueue ? toDeposit : 0);
    }

    /**
     * @notice Withdraws asset tokens
     * @dev will swap liquid staking tokens for queued tokens if there are any queued, then
     * remaining tokens will be queued for withdrawal in the withdrawal pool if
     * `_shouldQueueWithdrawal` is true, otherwise function will revert
     * @param _account account to withdraw for
     * @param _amount amount to withdraw
     * @param _shouldQueueWithdrawal whether a withdrawal should be queued if the the full amount cannot be satisfied
     * @param _shouldRevertOnZero whether call should revert if nothing is withdrawn or queued for withdrawal
     * @param _data list of withdrawal data passed to staking pool strategies if executing instant withdrawal
     * @return the amount of tokens that were withdrawn
     **/
    function _withdraw(
        address _account,
        uint256 _amount,
        bool _shouldQueueWithdrawal,
        bool _shouldRevertOnZero,
        bytes[] memory _data
    ) internal returns (uint256) {
        if (poolStatus == PoolStatus.CLOSED) revert WithdrawalsDisabled();
        if (_amount == 0) revert InvalidAmount();

        uint256 toWithdraw = _amount;
        uint256 queued;

        if (totalQueued != 0) {
            uint256 toWithdrawFromQueue = toWithdraw <= totalQueued ? toWithdraw : totalQueued;

            totalQueued -= toWithdrawFromQueue;
            depositsSinceLastUpdate += toWithdrawFromQueue;
            sharesSinceLastUpdate += stakingPool.getSharesByStake(toWithdrawFromQueue);
            toWithdraw -= toWithdrawFromQueue;
        }

        if (
            toWithdraw != 0 &&
            allowInstantWithdrawals &&
            withdrawalPool.getTotalQueuedWithdrawals() == 0
        ) {
            uint256 toWithdrawFromPool = MathUpgradeable.min(stakingPool.canWithdraw(), toWithdraw);
            if (toWithdrawFromPool != 0) {
                stakingPool.withdraw(address(this), address(this), toWithdrawFromPool, _data);
                toWithdraw -= toWithdrawFromPool;
            }
        }

        if (toWithdraw != 0) {
            if (!_shouldQueueWithdrawal) revert InsufficientLiquidity();

            if (toWithdraw >= withdrawalPool.minWithdrawalAmount()) {
                withdrawalPool.queueWithdrawal(_account, toWithdraw);
                queued = toWithdraw;
            } else {
                IERC20Upgradeable(address(stakingPool)).safeTransfer(_account, toWithdraw);
            }
        }

        uint256 withdrawn = _amount - toWithdraw;

        if (_shouldRevertOnZero && withdrawn + queued == 0) revert WithdrawFailed();
        if (withdrawn != 0) emit Withdraw(_account, withdrawn);

        return withdrawn;
    }

    /**
     * @notice Deposits queued and/or unused tokens
     * @dev will prioritize unused staking pool deposits, then queued deposits
     * @param _depositMin min amount of tokens required to deposit
     * @param _depositMax max amount of tokens that can be deposited into at once
     * @param _data deposit data passed to staking pool strategies
     **/
    function _depositQueuedTokens(
        uint256 _depositMin,
        uint256 _depositMax,
        bytes[] memory _data
    ) internal {
        if (poolStatus != PoolStatus.OPEN) revert DepositsDisabled();

        uint256 strategyDepositRoom = stakingPool.getStrategyDepositRoom();
        if (strategyDepositRoom == 0 || strategyDepositRoom < _depositMin)
            revert InsufficientDepositRoom();

        uint256 _totalQueued = totalQueued;
        uint256 unusedDeposits = stakingPool.getUnusedDeposits();
        uint256 canDeposit = _totalQueued + unusedDeposits;
        if (canDeposit == 0 || canDeposit < _depositMin) revert InsufficientQueuedTokens();

        uint256 toDepositFromStakingPool = MathUpgradeable.min(
            MathUpgradeable.min(unusedDeposits, strategyDepositRoom),
            _depositMax
        );
        uint256 toDepositFromQueue = MathUpgradeable.min(
            MathUpgradeable.min(_totalQueued, strategyDepositRoom - toDepositFromStakingPool),
            _depositMax - toDepositFromStakingPool
        );

        stakingPool.deposit(address(this), toDepositFromQueue, _data);
        _totalQueued -= toDepositFromQueue;

        if (_totalQueued != totalQueued) {
            uint256 diff = totalQueued - _totalQueued;
            depositsSinceLastUpdate += diff;
            sharesSinceLastUpdate += stakingPool.getSharesByStake(diff);
            totalQueued = _totalQueued;
        }

        emit DepositTokens(toDepositFromStakingPool, toDepositFromQueue);
    }

    /**
     * @dev Checks authorization for contract upgrades
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
