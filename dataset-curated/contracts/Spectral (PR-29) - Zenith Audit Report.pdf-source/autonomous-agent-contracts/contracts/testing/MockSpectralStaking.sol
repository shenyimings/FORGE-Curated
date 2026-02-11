// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/ISpectralStakingToken.sol";
import "./MockSpectralStakingToken.sol";

contract SpectralStaking is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // State variables
    IERC20Upgradeable public spectralToken;
    ISpectralStakingToken public stakingToken;
    address public admin;
    uint8 version;

    // Global state variables
    uint256 public totalStaked;
    int256 public totalDebtWeight;
    uint256 public distributionCount; // Tracks the last distribution index
    uint256 public distributionBufferBundlingPeriod; // Time period to bundle the buffer distributions into the main distributions

    // Constants
    uint256 private constant PRECISION = 1e12;
    uint256 public constant CLAIM_WITHDRAW_DELAY = 12 hours;

    // Distribution struct
    struct DistributionInfo {
        address rewardTokenA;
        address rewardTokenB;
        uint256 totalRewardsA;
        uint256 totalRewardsB;
        uint256 staked;
        int256 accDebtWeight;
        uint256 creationTimestamp;
    }

    struct DistributionBufferInfo {
        address rewardTokenA;
        address rewardTokenB;
        uint256 totalRewardsA;
        uint256 totalRewardsB;
        uint256 creationTimestamp;
    }

    // User distribution struct
    struct UserDistributionInfo {
        uint256 totalStaked; // User's total staked amount at the distribution
        int256 debtWeight; // User's debt weight for the specific distribution
        int256 potentialStaked; // User's potential staked amount during the distribution and before adding it to the totalStaked
        bool claimed; // Whether the user has claimed rewards for this distribution
    }

    // Maps user address to the timestamp of their last deposit
    mapping(address => uint256) public lastDeposit;
    // Maps user address to the index of the last claimed distribution so they can only claim sequentially from the last claimed distribution
    mapping(address => uint256) public lastClaimedIndex;
    // Maps distribution index to distribution info
    mapping(uint256 => DistributionInfo) public distributions;
    // Maps distribution index to user address to user distribution info
    mapping(uint256 => mapping(address => UserDistributionInfo)) public userDistributions;
    // Maps reward token A to reward token B to distribution buffer info
    mapping(address => mapping (address => DistributionBufferInfo)) public distributionBuffer;

    //Variables After Deployment
    address public deployer;

    //gap for future variable additions
    uint256[49] private __gap;

    event Upgrade(address indexed newImplementation, uint8 newVersion);
    event UpdateAdmin(address indexed admin);
    event Stake(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event RegisterDistribution(
        uint256 indexed distributionIndex,
        address indexed rewardTokenA,
        address indexed rewardTokenB,
        uint256 totalRewardsA,
        uint256 totalRewardsB,
        uint256 creationTimestamp
    );
    event Claim(
        address indexed user,
        uint256 indexed distributionIndex,
        address rewardTokenA,
        address rewardTokenB,
        uint256 amountA,
        uint256 amountB
    );
    event BufferDistribution(
        address rewardTokenA,
        address rewardTokenB,
        uint256 totalRewardsA,
        uint256 totalRewardsB,
        uint256 creationTimestamp
    );

    modifier onlyAdmin() {
        require(admin == msg.sender, "Only admin");
        _;
    }

    modifier onlyAdminOrDeployer() {
        require(admin == msg.sender || deployer == msg.sender, "Only admin or deployer");
        _;
    }

    modifier onlyStakingToken() {
        require(address(stakingToken) == msg.sender, "Only staking token");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _spectralToken, address _deployer) public initializer {
        require(_spectralToken != address(0), "Invalid token address");
        require(version == 0, "Already initialized");
        spectralToken = IERC20Upgradeable(_spectralToken);
        // first admin is owner
        admin = msg.sender;
        deployer = _deployer;
        version = 1;
        distributionBufferBundlingPeriod = 2 days;
        SpectralStakingToken stakingTokenImplementation = new SpectralStakingToken();
        stakingToken = ISpectralStakingToken(
            address(stakingTokenImplementation)
        );
        // Create the genesis distribution to track its creation timestamp
        distributions[distributionCount] = DistributionInfo({
            rewardTokenA: address(0),
            rewardTokenB: address(0),
            totalRewardsA: 0,
            totalRewardsB: 0,
            staked: 0,
            accDebtWeight: 0,
            creationTimestamp: block.timestamp
        });
        distributionCount = 1;
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }

    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Invalid admin address");
        admin = _admin;
        emit UpdateAdmin(_admin);
    }

    // This function is used to add the distribution to the main distributions
    function addDistribution(
        address rewardTokenA,
        address rewardTokenB,
        uint256 totalRewardsA,
        uint256 totalRewardsB
    ) external onlyAdminOrDeployer nonReentrant {

        _transferDistributionRewards(rewardTokenA, rewardTokenB, totalRewardsA, totalRewardsB);
        _addDistribution(rewardTokenA, rewardTokenB, totalRewardsA, totalRewardsB);
    }

    // This function is used to add the distribution to the buffer
    // This is useful when distriuting swap fees that are happening frequently per day and you need to bundle them into weekly distributions
    // The distribution will be automatically released to the main distribution after the time period has passed
    function addDistributionToBuffer(
        address rewardTokenA,
        address rewardTokenB,
        uint256 totalRewardsA,
        uint256 totalRewardsB) external onlyAdminOrDeployer nonReentrant {
        _transferDistributionRewards(rewardTokenA, rewardTokenB, totalRewardsA, totalRewardsB);
        DistributionBufferInfo storage oldDistributionBufferInfo = distributionBuffer[rewardTokenA][rewardTokenB];
        uint256 oldCreationTimestamp = oldDistributionBufferInfo.creationTimestamp;
        // If the buffer is empty, we set the creation timestamp to the current block timestamp
        if(oldCreationTimestamp == 0)
        {
            oldCreationTimestamp = block.timestamp;
        }
        oldDistributionBufferInfo.rewardTokenA = rewardTokenA;
        oldDistributionBufferInfo.rewardTokenB = rewardTokenB;
        oldDistributionBufferInfo.totalRewardsA = totalRewardsA + oldDistributionBufferInfo.totalRewardsA;
        oldDistributionBufferInfo.totalRewardsB = totalRewardsB + oldDistributionBufferInfo.totalRewardsB;
        oldDistributionBufferInfo.creationTimestamp = oldCreationTimestamp;


        // Will be auto-triggered to future buffer additions when the time period has passed
        if(block.timestamp >= oldCreationTimestamp + distributionBufferBundlingPeriod)
        {
            _releaseDistributionBuffer(distributionBuffer[rewardTokenA][rewardTokenB]);
        }
        emit BufferDistribution(rewardTokenA, rewardTokenB, totalRewardsA, totalRewardsB, block.timestamp);
    }

    // This function is used to release the distribution from the buffer to the main distribution by the Admin (not restricted by time period)
    // This is useful when distriuting swap fees that are happening frequently per day and you need to bundle them into weekly distributions
    function releaseDistributionBuffer(
        address rewardTokenA,
        address rewardTokenB) external onlyAdmin {
        DistributionBufferInfo storage distributionBufferInfo = distributionBuffer[rewardTokenA][rewardTokenB];
        require(distributionBufferInfo.creationTimestamp > 0, "No distribution in buffer");
        _releaseDistributionBuffer(distributionBufferInfo);
    }

    function _releaseDistributionBuffer(DistributionBufferInfo storage distributionBufferInfo) internal {
        // Add the distribution to the main distributions
        _addDistribution(distributionBufferInfo.rewardTokenA,
        distributionBufferInfo.rewardTokenB,
        distributionBufferInfo.totalRewardsA,
        distributionBufferInfo.totalRewardsB);
        // Reset the buffer
        distributionBufferInfo.rewardTokenA = distributionBufferInfo.rewardTokenA;
        distributionBufferInfo.rewardTokenB = distributionBufferInfo.rewardTokenB;
        distributionBufferInfo.totalRewardsA = 0;
        distributionBufferInfo.totalRewardsB = 0;
        distributionBufferInfo.creationTimestamp = 0;
    }

    function _addDistribution(
        address rewardTokenA,
        address rewardTokenB,
        uint256 totalRewardsA,
        uint256 totalRewardsB) internal {

        // Create the new distribution while copying the current global staked and debt
        distributions[distributionCount] = DistributionInfo({
            rewardTokenA: rewardTokenA,
            rewardTokenB: rewardTokenB,
            totalRewardsA: totalRewardsA,
            totalRewardsB: totalRewardsB,
            staked: totalStaked,
            accDebtWeight: totalDebtWeight,
            creationTimestamp: block.timestamp
        });

        // Increment the distribution count
        distributionCount++;

        // Reset the total debt weight
        totalDebtWeight = 0;

        emit RegisterDistribution(
            distributionCount - 1,
            rewardTokenA,
            rewardTokenB,
            totalRewardsA,
            totalRewardsB,
            block.timestamp
        );
    }

    function _transferDistributionRewards (
        address rewardTokenA,
        address rewardTokenB,
        uint256 totalRewardsA,
        uint256 totalRewardsB) internal {
        // The tokens are also deployed by us, so we trust them
        require(rewardTokenA != address(0), "Invalid reward token address");
        require(totalRewardsA > 0, "Reward must be greater than 0");

        // Transfer the reward tokens to the contract
        IERC20Upgradeable(rewardTokenA).transferFrom(
            msg.sender,
            address(this),
            totalRewardsA
        );

        if(rewardTokenB != address(0))
        {
            require(totalRewardsB > 0, "Reward must be greater than 0");
            IERC20Upgradeable(rewardTokenB).transferFrom(
                msg.sender,
                address(this),
                totalRewardsB
            );
        }
    }


    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");

        spectralToken.safeTransferFrom(msg.sender, address(this), amount);

        // update user debt which is stake * time since last distribution
        int userDebtWeight = int(amount) *
            int(block.timestamp - distributions[distributionCount - 1].creationTimestamp);

        // update user distribution
        UserDistributionInfo storage userDistribution = userDistributions[distributionCount][msg.sender];

        // We are adding the staked amount and subtracting the time the user has not staked in the current distribution
        // By using this concept of debtWeight
        userDistribution.debtWeight -= userDebtWeight;
        userDistribution.potentialStaked += int256(amount);

        // update global debt and staking
        totalDebtWeight -= userDebtWeight;
        totalStaked += amount;

        // mint the LP tokens
        stakingToken.mint(msg.sender, amount);

        //Let the user skip the sequential claiming for distributions before their first deposit
        if(lastDeposit[msg.sender] == 0)
        {
            userDistributions[distributionCount - 1][msg.sender].claimed = true;
            lastClaimedIndex[msg.sender] = distributionCount - 1;
        }
        // Update interaction time
        lastDeposit[msg.sender] = block.timestamp;

        emit Stake(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        require(
            block.timestamp >= lastDeposit[msg.sender] + CLAIM_WITHDRAW_DELAY,
            "Cannot withdraw within 12 hours of the last interaction"
        );
        require(
            stakingToken.balanceOf(msg.sender) >= amount,
            "Insufficient staked amount"
        );

        // update user debt which is stake * time since last distribution
        int userDebtWeight = int(amount) *
            int(block.timestamp - distributions[distributionCount - 1].creationTimestamp);

        UserDistributionInfo storage userDistribution = userDistributions[distributionCount][msg.sender];

        // We are subtracting the staked amount and adding the time the user has staked in the current distribution
        // By using this concept of debtWeight
        userDistribution.debtWeight += userDebtWeight;
        userDistribution.potentialStaked -= int256(amount);

        // update global debt and staking
        totalDebtWeight += userDebtWeight;

        totalStaked -= amount;

        // burn the LP tokens
        stakingToken.burn(msg.sender, amount);

        spectralToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function _claim(uint256 distributionIndex) internal {
        // Cannot claim genesis distribution
        require(distributionIndex > 0, "Cannot claim genesis distribution");

        // Can only claim before last distribution
        require(
            distributionIndex <= distributionCount,
            "Invalid distribution index"
        );

        // We continue if the user is at distribution 1 since they don't have to claim genesis distribution
        require(userDistributions[distributionIndex - 1][msg.sender].claimed || distributionIndex == 1 ||
        lastClaimedIndex[msg.sender] == distributionIndex - 1, "Can only claim sequentially");

        // Can only claim after 12 hours of the last interaction
        require(
            block.timestamp >= lastDeposit[msg.sender] + CLAIM_WITHDRAW_DELAY,
            "Cannot claim within 12 hours of the last interaction"
        );

        UserDistributionInfo storage userDistribution = userDistributions[
            distributionIndex
        ][msg.sender];

        // Can only claim once and if the lastClaimedIndex is less than the current distribution index
        // Example usage if the user started at distrubition 10
        require(userDistribution.claimed == false && lastClaimedIndex[msg.sender] < distributionIndex, "Already claimed");
        uint256 userRewardA = 0;
        uint256 userRewardB = 0;
        address rewardTokenA = distributions[distributionIndex].rewardTokenA;
        address rewardTokenB = distributions[distributionIndex].rewardTokenB;
        // If the user has staked in the current distribution, otherwise they can still claim 0 if they skipped a distribution
        // debtWeight and staked cannot be added since they are different units
        if((int256(userDistribution.totalStaked) + userDistribution.potentialStaked) > 0 || userDistribution.debtWeight > 0)
        {
            // Get total time
            uint256 distributionPeriod = distributions[distributionIndex].creationTimestamp -
            distributions[distributionIndex - 1].creationTimestamp;

            // Get total distribution weight = total staked * time + debt weight from previous stakes of users entering in the middle of the distribution
            uint256 stakedTimeWeight = distributions[distributionIndex].staked.mul(distributionPeriod);
            require(stakedTimeWeight <= uint256(type(int256).max), "Value exceeds int256 max");

            int256 totalWeightSigned = int256(stakedTimeWeight) + distributions[distributionIndex].accDebtWeight;
            // Ensure result is positive before uint256 conversion
            require(totalWeightSigned > 0, "Total weight must be positive");
            uint256 totalDistributionWeight = uint256(totalWeightSigned);

            // Get total user weight = total staked * time + debt weight from previous stakes of that user if they entered in the middle of the distribution
            require(userDistribution.totalStaked <= uint256(type(int256).max), "totalStaked exceeds int256 max");
            require(distributionPeriod <= uint256(type(int256).max), "Period exceeds int256 max");
            int256 totalUserWeightSigned = ((int256(userDistribution.totalStaked) + userDistribution.potentialStaked) * int256(distributionPeriod)) + userDistribution.debtWeight;

            // Ensure result is positive before uint256 conversion
            require(totalUserWeightSigned > 0, "Total user weight must be positive");

            // Finally multiply by PRECISION
            uint256 totalUserWeight = uint256(totalUserWeightSigned).mul(PRECISION);

            // Calculate the user reward which is time weighted and stake weighted
            userRewardA = Math.mulDiv(totalUserWeight, distributions[distributionIndex].totalRewardsA, totalDistributionWeight.mul(PRECISION));

            // Update the user's total staked amount in the next distribution for continuity
            userDistributions[
                distributionIndex + 1
            ][msg.sender].totalStaked = uint256(int256(userDistribution.totalStaked) + userDistribution.potentialStaked);

            // Transfer the reward tokens to the user
            IERC20Upgradeable(rewardTokenA).transfer(
                msg.sender,
                userRewardA
            );
            if(rewardTokenB != address(0))
            {
                userRewardB = Math.mulDiv(totalUserWeight, distributions[distributionIndex].totalRewardsB, totalDistributionWeight.mul(PRECISION));
                IERC20Upgradeable(rewardTokenB).transfer(
                    msg.sender,
                    userRewardB
                );
            }
        }

        // Mark the distribution as claimed even if the reward is 0 for continuity
        userDistribution.claimed = true;
        lastClaimedIndex[msg.sender] = distributionIndex;
        emit Claim(msg.sender, distributionIndex, rewardTokenA, rewardTokenB, userRewardA, userRewardB);
    }

    function claim(uint256 distributionIndex) external nonReentrant {
        _claim(distributionIndex);
    }

    function claimBatch(uint256 _fromDistributionIndex, uint256 _toDistributionIndex) external nonReentrant {
        require(_toDistributionIndex < distributionCount, "Invalid distribution index");
        for (uint256 i = _fromDistributionIndex; i <= _toDistributionIndex; i++) {
            _claim(i);
        }
    }

    function transferCalibration(address _from, address _to, uint256 amount) external onlyStakingToken {
        require(amount > 0, "Cannot transfer 0");
        require(
            stakingToken.balanceOf(_from) >= amount,
            "Insufficient staked amount"
        );

        // Calculate user debt Weight
        int userDebtWeight = int(amount) *
            int(block.timestamp - distributions[distributionCount - 1].creationTimestamp);

        UserDistributionInfo storage userDistributionFrom = userDistributions[distributionCount][_from];
        UserDistributionInfo storage userDistributionTo = userDistributions[distributionCount][_to];

        // Update both users' debt weights
        userDistributionFrom.debtWeight += userDebtWeight;
        userDistributionTo.debtWeight -= userDebtWeight;

        // Update both users' potential staked amounts
        userDistributionFrom.potentialStaked -= int256(amount);
        userDistributionTo.potentialStaked += int256(amount);

        // If this is the first deposit of the user, mark the previous distribution as claimed to skip empty distributions
         if(lastDeposit[_to] == 0)
        {
            userDistributions[distributionCount - 1][_to].claimed = true;
            lastClaimedIndex[_to] = distributionCount - 1;
        }

        lastDeposit[_to] = block.timestamp;

        emit Withdraw(_from, amount);
        emit Stake(_to, amount);
    }

    function setBufferBundlingPeriod(uint256 _bufferBundlingPeriod) external onlyAdmin {
        require(_bufferBundlingPeriod > 0, "Invalid bundling period");
        distributionBufferBundlingPeriod = _bufferBundlingPeriod;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        require(newImplementation != address(0), "ZERO_ADDRESS");
        ++version;
        emit Upgrade(newImplementation, version);
    }
}