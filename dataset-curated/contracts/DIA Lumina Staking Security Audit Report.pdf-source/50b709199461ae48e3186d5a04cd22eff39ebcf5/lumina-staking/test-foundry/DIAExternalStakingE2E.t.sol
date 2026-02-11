// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.29;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
// import "../contracts/DIAExternalStaking.sol";
// import "../contracts/StakingErrorsAndEvents.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// contract MockToken is ERC20 {
//     constructor() ERC20("Mock Token", "MTK") {
//         _mint(msg.sender, 10000000000000000 * 10 ** 18);
//     }
// }

// contract DIAExternalStakingE2ETest is Test {
//     // Contract instances
//     DIAExternalStaking public staking;
//     MockToken public token;

//     // Addresses
//     address public admin;
//     address public rewardsWallet;
//     address public user1;
//     address public user2;
//     address public user3;
//     address public random;

//     // Constants
//     uint256 public constant STAKING_LIMIT = 1000000 * 10 ** 18;
//     uint256 public constant UNSTAKING_DURATION = 7 days;
//     uint256 public constant MINIMUM_STAKE = 1 * 10 ** 18;

//     // Test amounts
//     uint256 public constant STAKE_AMOUNT_1 = 1000 * 10 ** 18;
//     uint256 public constant STAKE_AMOUNT_2 = 500 * 10 ** 18;
//     uint256 public constant REWARD_AMOUNT = 100 * 10 ** 18;

//     function setUp() public {
//         // Initialize addresses
//         admin = address(0x4);
//         rewardsWallet = address(0x123);
//         user1 = address(0x1);
//         user2 = address(0x2);
//         user3 = address(0x3);
//         random = address(0x10);

//         // Deploy contracts
//         vm.startPrank(admin);
//         token = new MockToken();
//         staking = new DIAExternalStaking(
//             UNSTAKING_DURATION,
//             address(token),
//             STAKING_LIMIT
//         );

//         // Configure staking contract
//         staking.setWithdrawalCapBps(1000); // 10% withdrawal cap
//         vm.stopPrank();

//         // Fund accounts
//         deal(address(token), user1, STAKE_AMOUNT_1 * 2);
//         deal(address(token), user2, STAKE_AMOUNT_1 * 2);
//         deal(address(token), user3, STAKE_AMOUNT_1 * 2);
//         deal(address(token), rewardsWallet, REWARD_AMOUNT * 100);

//         // Approve rewards wallet
//         vm.startPrank(rewardsWallet);
//         token.approve(address(staking), type(uint256).max);
//         vm.stopPrank();
//     }

//     function testEndToEndStakingFlow() public {
//         console.log("\n\x1b[32m=== STARTING END-TO-END STAKING TEST ===\x1b[0m");

//         // Phase 1: Initial Staking
//         console.log("\n\x1b[36m[Phase 1] Initial Staking\x1b[0m");
//         _testInitialStaking();

//         // Phase 2: Reward Distribution
//         console.log("\n\x1b[36m[Phase 2] Reward Distribution\x1b[0m");
//         _testRewardDistribution();

//         // Phase 3: Partial Unstaking
//         console.log("\n\x1b[36m[Phase 3] Partial Unstaking\x1b[0m");
//         _testPartialUnstaking();

//         // Phase 4: Full Unstaking
//         console.log("\n\x1b[36m[Phase 4] Full Unstaking\x1b[0m");
//         _testFullUnstaking();

//         // Phase 5: Multiple Stakes and Unstakes
//         console.log("\n\x1b[36m[Phase 5] Multiple Stakes and Unstakes\x1b[0m");
//         _testMultipleStakesAndUnstakes();

//         console.log("\n\x1b[32m=== END-TO-END STAKING TEST COMPLETED ===\x1b[0m");
//     }

//     function _testInitialStaking() internal {
//         // User 1 stakes
//         vm.startPrank(user1);
//         token.approve(address(staking), STAKE_AMOUNT_1);
//         staking.stake(STAKE_AMOUNT_1, 0);
//         vm.stopPrank();

//         // Verify stake
//         (address beneficiary, , , uint256 principal, uint256 poolShares, , , ) = staking.stakingStores(1);
//         assertEq(beneficiary, user1, "Beneficiary should be user1");
//         assertEq(principal, STAKE_AMOUNT_1, "Principal should match stake amount");
//         assertEq(poolShares, STAKE_AMOUNT_1, "Pool shares should match stake amount");

//         // User 2 stakes with principal share
//         vm.startPrank(user2);
//         token.approve(address(staking), STAKE_AMOUNT_1);
//         staking.stake(STAKE_AMOUNT_1, 2000); // 20% principal share
//         vm.stopPrank();

//         // Verify stake with principal share
//         (beneficiary, , , principal, poolShares, , , ) = staking.stakingStores(2);
//         assertEq(beneficiary, user2, "Beneficiary should be user2");
//         assertEq(principal, STAKE_AMOUNT_1, "Principal should match stake amount");
//         assertEq(poolShares, STAKE_AMOUNT_1, "Pool shares should match stake amount");

//         // Verify total staked amount
//         assertEq(staking.tokensStaked(), STAKE_AMOUNT_1 * 2, "Total staked amount should be correct");
//     }

//     function _testRewardDistribution() internal {
//         // Add rewards
//         vm.startPrank(rewardsWallet);
//         staking.addRewardToPool(REWARD_AMOUNT);
//         vm.stopPrank();

//         // Verify rewards distribution
//         uint256 user1Reward = staking.getRewardForStakingStore(1);
//         uint256 user2Reward = staking.getRewardForStakingStore(2);

//         // Rewards should be proportional to stake amount
//         assertEq(user1Reward, user2Reward, "Rewards should be equal for equal stakes");
//         assertGt(user1Reward, 0, "Rewards should be greater than 0");
//     }

//     function _testPartialUnstaking() internal {
//         // Request unstake for user1
//         vm.startPrank(user1);
//         staking.requestUnstake(1);
//         vm.stopPrank();

//         // Fast forward past unstaking period
//         vm.warp(block.timestamp + UNSTAKING_DURATION + 1);

//         // Partial unstake
//         uint256 partialAmount = STAKE_AMOUNT_1 / 2;
//         uint256 balanceBefore = token.balanceOf(user1);
        
//         vm.startPrank(user1);
//         staking.unstake(1, partialAmount);
//         vm.stopPrank();

//         uint256 balanceAfter = token.balanceOf(user1);
//         assertEq(balanceAfter - balanceBefore, partialAmount, "User should receive partial stake amount");

//         // Verify remaining stake
//         (, , , uint256 remainingPrincipal, , , , ) = staking.stakingStores(1);
//         assertEq(remainingPrincipal, STAKE_AMOUNT_1 - partialAmount, "Remaining principal should be correct");
//     }

//     function _testFullUnstaking() internal {
//         // Request unstake for user2
//         vm.startPrank(user2);
//         staking.requestUnstake(2);
//         vm.stopPrank();

//         // Fast forward past unstaking period
//         vm.warp(block.timestamp + UNSTAKING_DURATION + 1);

//         // Full unstake
//         uint256 balanceBefore = token.balanceOf(user2);
        
//         vm.startPrank(user2);
//         staking.unstake(2, STAKE_AMOUNT_1);
//         vm.stopPrank();

//         uint256 balanceAfter = token.balanceOf(user2);
//         assertEq(balanceAfter - balanceBefore, STAKE_AMOUNT_1, "User should receive full stake amount");

//         // Verify stake is cleared
//         (, , , uint256 principal, , , , ) = staking.stakingStores(2);
//         assertEq(principal, 0, "Principal should be zero after full unstake");
//     }

//     function _testMultipleStakesAndUnstakes() internal {
//         // User 3 makes multiple stakes
//         vm.startPrank(user3);
//         token.approve(address(staking), STAKE_AMOUNT_1 * 2);
        
//         // First stake
//         staking.stake(STAKE_AMOUNT_1, 0);
        
//         // Second stake
//         staking.stake(STAKE_AMOUNT_2, 0);
//         vm.stopPrank();

//         // Request unstake for first stake
//         vm.startPrank(user3);
//         staking.requestUnstake(3);
//         vm.stopPrank();

//         // Fast forward past unstaking period
//         vm.warp(block.timestamp + UNSTAKING_DURATION + 1);

//         // Unstake first amount
//         uint256 balanceBefore = token.balanceOf(user3);
//         vm.startPrank(user3);
//         staking.unstake(3, STAKE_AMOUNT_1);
//         vm.stopPrank();
//         uint256 balanceAfter = token.balanceOf(user3);
//         assertEq(balanceAfter - balanceBefore, STAKE_AMOUNT_1, "User should receive first stake amount");

//         // Request unstake for second stake
//         vm.startPrank(user3);
//         staking.requestUnstake(4);
//         vm.stopPrank();

//         // Fast forward past unstaking period
//         vm.warp(block.timestamp + UNSTAKING_DURATION + 1);

//         // Unstake second amount
//         balanceBefore = token.balanceOf(user3);
//         vm.startPrank(user3);
//         staking.unstake(4, STAKE_AMOUNT_2);
//         vm.stopPrank();
//         balanceAfter = token.balanceOf(user3);
//         assertEq(balanceAfter - balanceBefore, STAKE_AMOUNT_2, "User should receive second stake amount");

//         // Verify final state
//         assertEq(token.balanceOf(user3), STAKE_AMOUNT_1 + STAKE_AMOUNT_2, "User should have all tokens back");
//         assertEq(staking.tokensStaked(), STAKE_AMOUNT_1 - (STAKE_AMOUNT_1 / 2), "Total staked amount should be correct");
//     }

//     // Helper function to format token amounts
//     function getEthString(uint256 weiAmount) internal pure returns (string memory) {
//         uint256 ethWhole = weiAmount / 1e18;
//         uint256 ethDecimals = (weiAmount % 1e18);
//         return string.concat(vm.toString(ethWhole), ".", vm.toString(ethDecimals), " DIA");
//     }
// } 