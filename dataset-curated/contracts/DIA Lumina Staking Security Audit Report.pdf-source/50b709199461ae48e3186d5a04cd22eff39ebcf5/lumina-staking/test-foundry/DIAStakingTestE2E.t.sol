pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../contracts/DIAExternalStaking.sol";
import "../contracts/DIARewardsDistribution.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../contracts/DIAWhitelistedStaking.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

/// @title DIA Staking End-to-End Tests
/// @notice Tests the complete staking lifecycle including external and whitelisted staking
/// @dev Tests cover staking, unstaking, rewards distribution, and partial unstaking scenarios
contract DIAStakingTestE2E is Test {
    // Constants
    uint256 constant TOTAL_REWARDS = 500000000000 * 10 * 1e50;
    uint256 constant INITIAL_USER_BALANCE = 1000 * 10 ** 18;
    uint256 constant INITIAL_CONTRACT_BALANCE = 1000 * 10 ** 18;
    uint256 constant STAKING_LIMIT = 1000 * 10 ** 18;
    uint256 constant DEFAULT_STAKE_AMOUNT = 50 * 10 ** 18; // 50 tokens per staker
    
    // Contract instances
    DIAExternalStaking public externalStaking;
    DIAWhitelistedStaking public whitelistStaking;
    IERC20 public stakingToken;
    
    // Main addresses
    address public owner = address(this);
    address public rewardsWallet = address(0x124);
    
    // Delegator addresses
    address public whitelistDelegator1 = address(0xAAA);
    address public whitelistDelegator2 = address(0xBBB);
    address public externalDelegator1 = address(0xCCC);
    address public externalDelegator2 = address(0xDDD);
    address public externalDelegator3 = address(0xEEE);

    // Stakers
    address[8] public externalStakers;
    uint256[8] public externalStakersBalance = [
        100 * 10 ** 18,
        150 * 10 ** 18,
        200 * 10 ** 18,
        50 * 10 ** 18,
        70 * 10 ** 18,
        89.5 * 10 ** 18,
        111.1 * 10 ** 18,
        229.4 * 10 ** 18
    ];
    address[10] public stakers;
    address[11] public whitelistStakers;

    // Reward rates (225 DIA/day for external, 275 DIA/day for whitelist)
    uint256 public rewardRatePerDayExternal = 225/60 * 1e18; 
    uint256 public rewardRatePerDayWhitelist =  uint256(275 ) / 60;

    // Setup function
    function setUp() public {
        // Initialize token
        stakingToken = IERC20(address(new MockERC20("TestToken", "TT", 18)));
        
        // Initialize contracts
        externalStaking = new DIAExternalStaking(
            24 hours,
            address(stakingToken),
            STAKING_LIMIT
        );

        whitelistStaking = new DIAWhitelistedStaking(
            24 hours,
            address(stakingToken),
            rewardsWallet,
            rewardRatePerDayWhitelist
        );

        externalStaking.setWithdrawalCapBps(10000);
        whitelistStaking.setWithdrawalCapBps(10000);

        // Configure contracts
        //externalStaking.setDailyWithdrawalThreshold(10_000 * 10 ** 18);
        externalStaking.setDailyWithdrawalThreshold(10_000);
        
        // Fund rewards wallet
        deal(address(stakingToken), rewardsWallet, TOTAL_REWARDS);
        
        // Approve spending from rewards wallet
        vm.startPrank(rewardsWallet);
        stakingToken.approve(address(externalStaking), TOTAL_REWARDS);
        stakingToken.approve(address(whitelistStaking), TOTAL_REWARDS);
        vm.stopPrank();
        
        // Initialize staker addresses
        _initializeAddresses();
    }
    
    // Initialize staker and whitelisted addresses
    function _initializeAddresses() internal {
        // Generate whitelist staker addresses
        for (uint256 i = 0; i < whitelistStakers.length; i++) {
            whitelistStakers[i] = address(
                uint160(uint256(keccak256(abi.encodePacked("whitelist", i))))
            );
        }
        
        // Assign unique addresses to stakers
        for (uint256 i = 0; i < stakers.length; i++) {
            stakers[i] = address(uint160(0x100 + i));
            deal(stakers[i], 1 ether); // Give ETH for gas
        }
        
        // Initialize external staker addresses
        for (uint256 i = 0; i < externalStakers.length; i++) {
            externalStakers[i] = address(uint160(0x3CC + i));
        }
    }
    
    // Main test function
    function testEndToEndStakingWithRewards() public {
        setupStaking();
        setupCase1_UnstakeWithPrincipal();
        setupCase2_ClaimFullRewards();
       setupCase3_Remove30PercentStake();
    }
    
    // Setup staking - distribute tokens and make stakes
    function setupStaking() public {
        // Fund delegators
        _fundDelegators();
        
        // Add whitelist stakers
        _setupWhitelistedStakers();
        
        // Setup external staking
        _setupExternalStaking();
    }
    
    // Fund all delegator wallets
    function _fundDelegators() internal {
        // Define balances for delegators
        uint256[2] memory whitelistDelegatorBalances = [uint256(500 * 10 ** 18), uint256(500 * 10 ** 18)];
        uint256[3] memory externalDelegatorBalances = [uint256(500 * 10 ** 18), uint256(500 * 10 ** 18), uint256(500 * 10 ** 18)];
        address[2] memory whitelistDelegators = [whitelistDelegator1, whitelistDelegator2];
        address[3] memory externalDelegators = [externalDelegator1, externalDelegator2, externalDelegator3];

        // Log and fund whitelist delegators
        console.log("\nFunding whitelist delegators:");
        for (uint256 i = 0; i < whitelistDelegators.length; i++) {
            console.log("Delegator %s: %s tokens", whitelistDelegators[i], getEthString(whitelistDelegatorBalances[i]));
            deal(address(stakingToken), whitelistDelegators[i], whitelistDelegatorBalances[i]);
            
            vm.startPrank(whitelistDelegators[i]);
            stakingToken.approve(address(externalStaking), whitelistDelegatorBalances[i]);
            stakingToken.approve(address(whitelistStaking), whitelistDelegatorBalances[i]);
            vm.stopPrank();
        }

        // Log and fund external delegators
        console.log("\nFunding external delegators:");
        for (uint256 i = 0; i < externalDelegators.length; i++) {
            console.log("Delegator %s: %s tokens", externalDelegators[i], getEthString(externalDelegatorBalances[i]));
            deal(address(stakingToken), externalDelegators[i], externalDelegatorBalances[i]);
        }
        
        // Fund external stakers
        console.log("\nFunding external stakers:");
        for (uint256 i = 0; i < externalStakers.length; i++) {
            console.log("Staker %s: %s tokens", externalStakers[i], getEthString(externalStakersBalance[i]));
            deal(address(stakingToken), externalStakers[i], externalStakersBalance[i]);
        }
    }
    
    // Setup whitelisted stakers
    function _setupWhitelistedStakers() internal {
        console.log("\x1b[32m Stake to Whitelist contract \x1b[0m");
        console.log("\x1b[32m From two separate addresses delegate 50 $DIA to 10 whitelist stakers \x1b[0m");
        console.log("\x1b[32m For 8 of the nodes delegate 100% of the rewards; for 1 80%; for 1 50% \x1b[0m");
        
        // Add addresses to whitelist
        for (uint256 i = 0; i < whitelistStakers.length; i++) {
            vm.startPrank(owner);
            console.log("addWhitelistedStaker", whitelistStakers[i]);
            whitelistStaking.addWhitelistedStaker(whitelistStakers[i]);
            vm.stopPrank();
        }
        
        // First delegator stakes to first 5 whitelisted stakers with 100% reward to staker
        for (uint256 i = 0; i < 5; i++) {
            _stakeToWhitelist(whitelistDelegator1, whitelistStakers[i], DEFAULT_STAKE_AMOUNT, 0, i);
        }
        
        // Second delegator stakes to next 3 whitelisted stakers with 100% reward to staker
        for (uint256 i = 5; i < 8; i++) {
            _stakeToWhitelist(whitelistDelegator2, whitelistStakers[i], DEFAULT_STAKE_AMOUNT, 0, i);
        }
        
        // Second delegator stakes to 9th whitelisted staker with 80% reward to staker (20% to delegator)
        _stakeToWhitelist(whitelistDelegator2, whitelistStakers[8], DEFAULT_STAKE_AMOUNT, 2000, 8);
        
        // Second delegator stakes to 10th whitelisted staker with 50% reward to staker (50% to delegator)
        _stakeToWhitelist(whitelistDelegator2, whitelistStakers[9], DEFAULT_STAKE_AMOUNT, 5000, 9);
        
        // 11th whitelisted staker provides own capital
        console.log("---");
        console.log("\x1b[32m 1 whitelist staker has to provide their own capital \x1b[0m");
        
        deal(address(stakingToken), whitelistStakers[10], 500 * 10 ** 18);
        
        vm.startPrank(whitelistStakers[10]);
        stakingToken.approve(address(whitelistStaking), DEFAULT_STAKE_AMOUNT);
        
        console.log("Share principalShareBps %s ", "10000");
        console.log("stakeAmount %s ", getEthString(DEFAULT_STAKE_AMOUNT));
        console.log(
            "Self-staking: %s index %s",
            whitelistStakers[10],
            10
        );
        
        whitelistStaking.stake(DEFAULT_STAKE_AMOUNT);
        vm.stopPrank();
    }
    
    // Helper function to stake to whitelist
    function _stakeToWhitelist(
        address delegator, 
        address staker, 
        uint256 stakeAmount, 
        uint32 principalShareBps,
        uint256 index
    ) internal {
        vm.startPrank(delegator);
        stakingToken.approve(address(whitelistStaking), stakeAmount);
        
        console.log("---");
        console.log("Share principalShareBps %s ", principalShareBps);
        console.log("stakeAmount %s ", getEthString(stakeAmount));
        console.log(
            "Delegator: %s => Whitelisted: %s index %s",
            delegator,
            staker,
            index
        );
        
        whitelistStaking.stakeForAddress(staker, stakeAmount, principalShareBps);
        vm.stopPrank();
    }
    
    // Setup external staking
    function _setupExternalStaking() internal {
        console.log("\x1b[32m Stake to External contract \x1b[0m");
        console.log("\x1b[32m Stake delegate on 3 different external stakers: \x1b[0m");
        
        // Delegator 1 stakes to external staker 1 (100% reward to staker)
        console.log("\x1b[32m Stake delegate 100 $DIA with 100% reward to delegate \x1b[0m");
        _stakeToExternal(externalDelegator1, externalStakers[0], externalStakersBalance[0], 0);
        
        // Delegator 2 stakes to external staker 2 (90% reward to staker, 10% to delegator)
        console.log("\x1b[32m Stake delegate 150 $DIA with 90% reward to delegate \x1b[0m");
        _stakeToExternal(externalDelegator2, externalStakers[1], externalStakersBalance[1], 1000);
        
        // Delegator 2 stakes to external staker 3 (60% reward to staker, 40% to delegator)
        console.log("\x1b[32m Stake delegate 200 $DIA with 60% reward to delegate \x1b[0m");
        _stakeToExternal(externalDelegator2, externalStakers[2], externalStakersBalance[2], 4000);
        
        // Remaining stakers stake directly
        console.log("\x1b[32m Fill in the remaining external pool (550 $DIA) from 5 separate addresses: \x1b[0m");
        for (uint256 i = 3; i < externalStakers.length; i++) {
            _stakeSelfExternal(externalStakers[i], externalStakersBalance[i]);
        }
    }
    
    // Helper to stake to external contract via delegation
    function _stakeToExternal(
        address delegator, 
        address staker, 
        uint256 stakeAmount, 
        uint32 principalShareBps
    ) internal {
        vm.startPrank(delegator);
        stakingToken.approve(address(externalStaking), stakeAmount);
        
        console.log("---");
        console.log("stakeAmount %s ", getEthString(stakeAmount));
        console.log(
            "Delegator: %s => External: %s principalShareBps %s",
            delegator,
            staker,
            principalShareBps
        );
        
        externalStaking.stakeForAddress(staker, stakeAmount, principalShareBps);
        vm.stopPrank();
    }
    
    // Helper for individual external staking
    function _stakeSelfExternal(address staker, uint256 stakeAmount) internal {
        vm.startPrank(staker);
        stakingToken.approve(address(externalStaking), stakeAmount);

        string memory stakeAmountString = getEthString(stakeAmount);
        
        console.log("staker: %s => External: stakeAmount %s", staker, stakeAmountString);

        externalStaking.stake(stakeAmount, 10000);
        vm.stopPrank();
    }
    
     function setupCase1_UnstakeWithPrincipal() public {
        console.log("\n=== CASE 1: UNSTAKING WITH FULL PRINCIPAL ===");
        
        // Add daily rewards for 60 days
        for (uint256 i = 0; i < 60; i++) {
            vm.startPrank(rewardsWallet);
            externalStaking.addRewardToPool(rewardRatePerDayExternal);
            // whitelistStaking.addRewardToPool(rewardRatePerDayWhitelist);
            vm.stopPrank();
            skip(1 days);
        }
        console.log("\nSkipped forward 60 days and added daily rewards");

        console.log("\x1b[32m Calling request Unstake, 60 Days later \x1b[0m");
        
         for (uint256 i = 0; i < whitelistStakers.length; i++) {
            uint256[] memory indices = whitelistStaking.getStakingIndicesByBeneficiary(whitelistStakers[i]);
            vm.startPrank(whitelistStakers[i]);
            whitelistStaking.requestUnstake(indices[0]);
            vm.stopPrank();
        }
        
         for (uint256 i = 0; i < externalStakers.length; i++) {
            uint256[] memory indices = externalStaking.getStakingIndicesByBeneficiary(externalStakers[i]);
            vm.startPrank(externalStakers[i]);
            externalStaking.requestUnstake(indices[0]);
            vm.stopPrank();
        }
        
         skip(1 days);
 
        console.log("\x1b[32m After request Unstake, 1 Days later \x1b[0m");
        
        // Process sample of whitelist unstakes with full principal
        console.log("\x1b[31m For delegated whitelist from 2 wallets \x1b[0m");
        for (uint256 i = 0; i < 2; i++) {
            _processWhitelistUnstake(i);
        }

        _processWhitelistUnstake(8);
                _processWhitelistUnstake(9);
                                _processWhitelistUnstake(10);
 

        
        // Process sample of external unstakes with full principal
        console.log("\n\n\n\n");
        console.log("\x1b[31m For delegated external staker wallets from 2 wallets \x1b[0m");
        for (uint256 i = 0; i < 2; i++) {
            _processExternalUnstake(i);
        }
        
        // Process a single self-staked external unstake
        console.log("\n\n\n\n");
        console.log("\x1b[31m For external staker wallet \x1b[0m");
        _processExternalUnstake(3);
    }
    
     function setupCase2_ClaimFullRewards() public {
                console.log("\n\n\n\n");

        console.log("\n=== CASE 2: CLAIMING REWARDS ONLY (NO PRINCIPAL) ===");
        
         console.log("\x1b[31m For delegated whitelist from 2 wallets \x1b[0m");
        for (uint256 i = 2; i < 4; i++) {
            _processWhitelistClaimOnly(i);
        }
        
         console.log("\n\n\n\n");
        console.log("\x1b[31m For delegated external staker wallets from 1 wallets \x1b[0m");
        
        _processExternalUnstake(2);

        
         console.log("\n\n\n\n");
        console.log("\x1b[31m For external staker wallet \x1b[0m");
        _processExternalUnstake(4);
    }


      function setupCase3_Remove30PercentStake() public {
        //         console.log("\n\n\n\n");

        console.log("\n=== CASE 3 b: Remove 30% of the stake ===");
        
        // Process whitelist rewards for stakers 2-3
        console.log("\x1b[31m For delegated whitelist from 2 wallets \x1b[0m");
        for (uint256 i = 4; i < 6; i++) {
             _processWhitelistPartialUnstake(i);
        }
        
        //  console.log("\n\n\n\n");
        console.log("\x1b[31m For delegated external staker wallets from 1 wallets \x1b[0m");
        
        _processExternalPartialUnstake(5);

        
         console.log("\n\n\n\n");
        console.log("\x1b[31m For external staker wallet \x1b[0m");
        _processExternalPartialUnstake(6);
    }


    function _processExternalPartialUnstake(uint256 stakerIndex) internal {
    uint256[] memory indices = externalStaking.getStakingIndicesByBeneficiary(externalStakers[stakerIndex]);

    uint256 balanceBefore = stakingToken.balanceOf(externalStakers[stakerIndex]);
    console.log("\nProcessing *partial* unstake (30%%) for external staker %s (Index: %s)", 
        externalStakers[stakerIndex],
        indices[0]
    );
    console.log("Balance before: %s tokens", getEthString(balanceBefore));

    vm.startPrank(externalStakers[stakerIndex]);
    (, , , uint256 principal, , , ,   ) = externalStaking.stakingStores(indices[0]);
    uint256 partialAmount = principal * 30 / 100;
    console.log("Principal amount: %s tokens from Contract", getEthString(principal));
    console.log("Attempting to unstake: %s tokens (30%%)", getEthString(partialAmount));

    externalStaking.unstake(indices[0], partialAmount);
    vm.stopPrank();

    uint256 balanceAfter = stakingToken.balanceOf(externalStakers[stakerIndex]);
    console.log("Balance after: %s tokens", getEthString(balanceAfter));
    console.log("Tokens received: %s", getEthString(balanceAfter - balanceBefore));

    console.log("\nStaking details after partial unstake:");
    printStakingStoreExternal(indices[0]);
}

function _processWhitelistPartialUnstake(uint256 stakerIndex) internal {
    uint256[] memory indices = whitelistStaking.getStakingIndicesByBeneficiary(whitelistStakers[stakerIndex]);

    uint256 balanceBefore = stakingToken.balanceOf(whitelistStakers[stakerIndex]);
    console.log("\nProcessing *partial* unstake (30%%) for whitelisted staker %s (Index: %s)", 
        whitelistStakers[stakerIndex],
        indices[0]
    );
    console.log("Balance before: %s tokens", getEthString(balanceBefore));

    vm.startPrank(whitelistStakers[stakerIndex]);
    (, , , uint256 principal, , , , ,  ) = whitelistStaking.stakingStores(indices[0]);
    uint256 partialAmount = principal * 30 / 100;
    console.log("Principal amount: %s tokens", getEthString(principal));
    console.log("Attempting to unstake: %s tokens (30%%)", getEthString(partialAmount));

    whitelistStaking.unstake(indices[0]);
    vm.stopPrank();

    uint256 balanceAfter = stakingToken.balanceOf(whitelistStakers[stakerIndex]);
    console.log("Balance after: %s tokens", getEthString(balanceAfter));
    console.log("Tokens received: %s", getEthString(balanceAfter - balanceBefore));

    console.log("\nStaking details after partial unstake:");
    printStakingStoreWhitelist(indices[0]);
}

    
    function _processWhitelistUnstake(uint256 stakerIndex) internal {


        uint256[] memory indices = whitelistStaking.getStakingIndicesByBeneficiary(whitelistStakers[stakerIndex]);
        
        uint256 balanceBefore = stakingToken.balanceOf(whitelistStakers[stakerIndex]);
        console.log("\nProcessing unstake for whitelisted staker %s (Index: %s)", 
            whitelistStakers[stakerIndex],
            indices[0]
        );
        console.log("Balance before: %s tokens", getEthString(balanceBefore));
        
        vm.startPrank(whitelistStakers[stakerIndex]);
        (, , , uint256 principal, , , , ,  ) = whitelistStaking.stakingStores(indices[0]);
        console.log("Principal amount: %s tokens", getEthString(principal));
                 console.log("\nStaking details Before unstake:---------------------");

                printStakingStoreWhitelist(indices[0]);

        whitelistStaking.unstake(indices[0]);
        vm.stopPrank();
        
        uint256 balanceAfter = stakingToken.balanceOf(whitelistStakers[stakerIndex]);
        console.log("Balance after: %s tokens", getEthString(balanceAfter));
        console.log("Tokens received: %s", getEthString(balanceAfter - balanceBefore));
        
        console.log("\nStaking details after unstake:");
        printStakingStoreWhitelist(indices[0]);
    }
    
    // Helper to process whitelist claim only (no principal)
    function _processWhitelistClaimOnly(uint256 stakerIndex) internal {
        uint256[] memory indices = whitelistStaking.getStakingIndicesByBeneficiary(whitelistStakers[stakerIndex]);
        
        uint256 balanceBefore = stakingToken.balanceOf(whitelistStakers[stakerIndex]);
        console.log("\nProcessing rewards claim for whitelisted staker %s (Index: %s)", 
            whitelistStakers[stakerIndex],
            indices[0]
        );
        console.log("Balance before: %s tokens", getEthString(balanceBefore));
        
        vm.startPrank(whitelistStakers[stakerIndex]);
        whitelistStaking.unstake(indices[0]); // 0 principal = claim rewards only
        vm.stopPrank();
        
        uint256 balanceAfter = stakingToken.balanceOf(whitelistStakers[stakerIndex]);
        console.log("Balance after: %s tokens", getEthString(balanceAfter));
        console.log("Rewards claimed: %s tokens", getEthString(balanceAfter - balanceBefore));
        
        console.log("\nStaking details after claim:");
        printStakingStoreWhitelist(indices[0]);
    }
    
    // Helper to process external staking unstake
    function _processExternalUnstake(uint256 stakerIndex) internal {
        uint256[] memory indices = externalStaking.getStakingIndicesByBeneficiary(externalStakers[stakerIndex]);
        skip(1 days);

         
        (uint256 principalWalletReward, uint256 fullReward) = externalStaking.getRewardForStakingStore(indices[0]);
        uint256 rewards = principalWalletReward * fullReward;
        uint256 balanceBefore = stakingToken.balanceOf(externalStakers[stakerIndex]);
        console.log("\nProcessing unstake for external staker %s (Index: %s)", 
            externalStakers[stakerIndex],
            indices[0]
        );
        console.log("Balance before: %s tokens", getEthString(balanceBefore));
        
        vm.startPrank(externalStakers[stakerIndex]);
        (, , , uint256 principal, , , ,  ) = externalStaking.stakingStores(indices[0]);
        console.log("Principal amount from contract: %s tokens", getEthString(principal));
        console.log("Principal amount from staker: %s tokens", getEthString(externalStakersBalance[stakerIndex]));

        console.log("Balance Staked: %s tokens", getEthString(externalStakersBalance[stakerIndex]));


          (  principalWalletReward,  fullReward) = externalStaking.getRewardForStakingStore(indices[0]);
        uint256 reward = principalWalletReward + fullReward;

        console.log("Reward amount: %s tokens", getEthString(reward));
        console.log("principalWalletReward amount: %s tokens", getEthString(principalWalletReward));
        console.log("Beneficiary Reward amount: %s tokens", getEthString(fullReward));



        
        externalStaking.unstake(indices[0], principal+reward);
        vm.stopPrank();
        
        uint256 balanceAfter = stakingToken.balanceOf(externalStakers[stakerIndex]);
 
        console.log("Balance after unstake: %s tokens  of %s", getEthString(balanceAfter), externalStakers[stakerIndex]);
        console.log("Tokens received: %s", getEthString(balanceAfter - balanceBefore));
        
        console.log("\nStaking details after unstake:");
        printStakingStoreExternal(indices[0]);
    }
    
    // Print whitelist staking store details
    function printStakingStoreWhitelist(uint256 index) internal view {
        (
            address beneficiary,
            address principalPayoutWallet,
            address principalUnstaker,
            uint256 principal,
            uint256 reward,
            uint256 paidOutReward,
            uint64 stakingStartTime,
            uint64 unstakingRequestTime,
            uint32 principalWalletShareBps
        ) = whitelistStaking.stakingStores(index);

        _printStakingCommonDetails(
            index,
            beneficiary, 
            principalPayoutWallet, 
            principalUnstaker, 
            principal, 
            reward, 
            paidOutReward,
            stakingStartTime, 
            unstakingRequestTime, 
            principalWalletShareBps
        );
    }

   
    
    // Print external staking store details
    function printStakingStoreExternal(uint256 index) internal view {
        (
            address beneficiary,
            address principalPayoutWallet,
            address principalUnstaker,
            uint256 principal,
            uint256 poolShares,
            uint64 stakingStartTime,
            uint64 unstakingRequestTime,
            uint32 principalWalletShareBps
        ) = externalStaking.stakingStores(index);

        console2.log("\x1b[36mStake ID: %s\x1b[0m", index);
        console2.log("\x1b[36m  Beneficiary: %s (Balance: %s)\x1b[0m", 
            beneficiary, 
            getEthString(stakingToken.balanceOf(beneficiary))
        );
        console2.log("\x1b[36m  Payout Wallet: %s (Balance: %s)\x1b[0m", 
            principalPayoutWallet, 
            getEthString(stakingToken.balanceOf(principalPayoutWallet))
        );
        console2.log("\x1b[36m  Unstaker: %s (Balance: %s)\x1b[0m", 
            principalUnstaker, 
            getEthString(stakingToken.balanceOf(principalUnstaker))
        );
        console2.log("\x1b[36m  Principal: %s\x1b[0m", principal);
        console2.log("\x1b[36m  Pool Shares: %s\x1b[0m", poolShares);
        console2.log("\x1b[36m  Stake Start: %s\x1b[0m", stakingStartTime);
        console2.log("\x1b[36m  Unstake Request Time: %s\x1b[0m", unstakingRequestTime);
        console2.log("\x1b[36m  Principal Share BPS: %s\x1b[0m", principalWalletShareBps);
    }
    
    // Common staking details printer
    function _printStakingCommonDetails(
        uint256 index,
        address beneficiary,
        address principalPayoutWallet,
        address principalUnstaker,
        uint256 principal,
        uint256 reward,
        uint256 paidOutReward,
        uint64 stakingStartTime,
        uint64 unstakingRequestTime,
        uint32 principalWalletShareBps
    ) internal view {
        console2.log("\x1b[36mStake ID: %s\x1b[0m", index);
        console2.log("\x1b[36m  Beneficiary: %s (Balance: %s)\x1b[0m", 
            beneficiary, 
            getEthString(stakingToken.balanceOf(beneficiary))
        );
        console2.log("\x1b[36m  Payout Wallet: %s (Balance: %s)\x1b[0m", 
            principalPayoutWallet, 
            getEthString(stakingToken.balanceOf(principalPayoutWallet))
        );
        console2.log("\x1b[36m  Unstaker: %s (Balance: %s)\x1b[0m", 
            principalUnstaker, 
            getEthString(stakingToken.balanceOf(principalUnstaker))
        );
        console2.log("\x1b[36m  Principal: %s\x1b[0m", getEthString(principal));
        console2.log("\x1b[36m  Reward: %s\x1b[0m", getEthString(reward));
        console2.log("\x1b[36m  Paid Out Reward: %s\x1b[0m", getEthString(paidOutReward));
        console2.log("\x1b[36m  Stake Start: %s\x1b[0m", stakingStartTime);
        console2.log("\x1b[36m  Unstake Request Time: %s\x1b[0m", unstakingRequestTime);
        console2.log("\x1b[36m  Principal Share BPS: %s\x1b[0m", principalWalletShareBps);
    }
    
    // Print state of all staking contracts
    function printState() public view {
        uint256 totalExternalStakes = externalStaking.stakingIndex();
        console.log(" \x1b[32m ----------Total Stakes External------ \x1b[0m", totalExternalStakes);
        
        for (uint256 i = 0; i <= totalExternalStakes; i++) {
            printStakingStoreExternal(i);
        }
        
        uint256 totalWhitelistStakes = whitelistStaking.stakingIndex();
        console.log("--------Total Stakes Whitelist-------", totalWhitelistStakes);
        
        for (uint256 i = 0; i <= totalWhitelistStakes; i++) {
            printStakingStoreWhitelist(i);
        }
    }

    // Add helper functions for common operations
    function _approveAndStake(
        address staker,
        address contractAddress,
        uint256 amount
    ) internal {
        vm.startPrank(staker);
        stakingToken.approve(contractAddress, amount);
        vm.stopPrank();
    }

    function _checkBalanceChange(
        address account,
        uint256 expectedChange,
        string memory message
    ) internal {
        uint256 balanceBefore = stakingToken.balanceOf(account);
        // ... perform operation ...
        uint256 balanceAfter = stakingToken.balanceOf(account);
        assertEq(
            balanceAfter - balanceBefore,
            expectedChange,
            message
        );
    }

      function getEthString(  uint256 weiAmount) internal view returns (string memory) {
    uint256 ethWhole = weiAmount / 1e18;
    uint256 ethDecimals = (weiAmount % 1e18) ; // 4 decimal digits

    return string.concat(vm.toString(ethWhole), ".", vm.toString(ethDecimals), " DIA");

    // Make sure you convert both to strings
 }
}
