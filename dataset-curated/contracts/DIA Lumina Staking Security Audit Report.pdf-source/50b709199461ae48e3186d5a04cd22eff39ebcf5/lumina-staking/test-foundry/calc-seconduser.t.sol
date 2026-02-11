// // // SPDX-License-Identifier: UNLICENSED
 pragma solidity ^0.8.29;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";

// import "../contracts/DIAWhitelistedStaking.sol";
// import "../contracts/DIAExternalStaking.sol";
// import "../contracts/DIAStakingCommons.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// contract MockToken is ERC20 {
//     constructor(
//         string memory name,
//         string memory symbol,
//         uint8 decimals
//     ) ERC20(name, symbol) {}

//     function mint(address to, uint256 amount) public {
//         _mint(to, amount);
//     }
// }

// contract StakingComparisonTest is Test {
//     MockToken public token;
//     DIAWhitelistedStaking public whitelistStaking;
//     DIAExternalStaking public externalStaking;
//     address public rewardsWallet = address(0xA);
//     address public user = address(0xB);

//     address public userWl = address(0xab);
//     address public userEx = address(0xac);
//     address public userEx2 = address(0xad);

//     uint256 public rewardRatePerDay = 10; // 0.001%
//     uint256 public amount = 100 * 10 * 10e18;

//     function pad(
//         string memory str,
//         uint256 width
//     ) internal pure returns (string memory) {
//         bytes memory bStr = bytes(str);
//         if (bStr.length >= width) return str;

//         bytes memory padded = new bytes(width);
//         uint256 padLength = width - bStr.length;

//         for (uint256 i = 0; i < padLength; i++) {
//             padded[i] = 0x20; // space
//         }

//         for (uint256 i = 0; i < bStr.length; i++) {
//             padded[padLength + i] = bStr[i];
//         }

//         return string(padded);
//     }

//     function printRow(
//         uint256 day,
//         uint256 wlReward,
//         uint256 exReward
//     ) internal {
//         console.log(
//             string.concat(
//                 pad(vm.toString(day), 2),
//                 " | ",
//                 pad(vm.toString(wlReward), 10),
//                 " | ",
//                 pad(vm.toString(exReward), 10)
//             )
//         );
//     }

//     function test_DailyUnstakeComparison() public {
//         console.log("Days | WL Reward | EX Reward");

//         for (uint256 daysStaked = 1; daysStaked <= 15; daysStaked++) {
//             simulateSingleContractCycle(daysStaked);
//         }
//     }

//     function simulateSingleContractCycle(uint256 daysStaked) internal {
//         uint256 principal = 10000;
//         uint256 rewardRatePerDay = 12;

//         // Deploy new token and mint balances
//         MockToken stakingToken = new MockToken("Mock", "MCK", 18);
//         stakingToken.mint(userWl, principal * 2);
//         stakingToken.mint(userEx, principal * 2);
//         stakingToken.mint(userEx2, principal * 2);

//         stakingToken.mint(rewardsWallet, principal * 100);

//         DIAWhitelistedStaking wl = new DIAWhitelistedStaking(
//             1 days,
//             address(stakingToken),
//             rewardsWallet,
//             rewardRatePerDay
//         );

//         DIAExternalStaking ex = new DIAExternalStaking(
//             1 days,
//             address(stakingToken),
//             1_000_000e18
//         );

//         wl.addWhitelistedStaker(userWl);
//         ex.setWithdrawalCapBps(10000);
//         wl.setWithdrawalCapBps(10000);


//         // userwl stake to wl
//         vm.startPrank(userWl);

//         // Approvals and setup
//         stakingToken.approve(address(wl), type(uint256).max);

//         // Stake
//         wl.stake(principal);

//         vm.stopPrank();

//         vm.startPrank(userEx);
//         stakingToken.approve(address(ex), type(uint256).max);

//         ex.stake(principal, 0);
//         vm.stopPrank();

//         vm.startPrank(userEx2);
//         stakingToken.approve(address(ex), type(uint256).max);

//         ex.stake(principal, 0);
//         vm.stopPrank();

//         vm.startPrank(rewardsWallet);
//         stakingToken.approve(address(wl), type(uint256).max);

//         stakingToken.approve(address(ex), type(uint256).max);
//         vm.stopPrank();

// 				// Add rewards
//         vm.prank(rewardsWallet);
//         stakingToken.approve(address(ex), type(uint256).max);
//         vm.prank(rewardsWallet);

//         ex.addRewardToPool(20);

//         // Wait for `daysStaked` days
//         skip(daysStaked * 1 days);

//         // Request unstake
//         vm.prank(userWl);
//         wl.requestUnstake(1);
//         vm.prank(userEx);
//         ex.requestUnstake(1);
//         vm.prank(userEx2);
//         ex.requestUnstake(2);

//         skip(1 days); // unstaking delay

//         // Unstake and check rewards
//         uint256 wlBefore = stakingToken.balanceOf(userWl);
//         uint256 exBefore = stakingToken.balanceOf(userEx);

//         (, , , uint256 wlPrincipal, , , , , , , ) = wl.stakingStores(1);

//         (, , , uint256 exPrincipal, , , , , , ) = ex.stakingStores(1);

//         vm.prank(userWl);
//         wl.unstake(1);
//         vm.prank(userEx);
//         ex.unstake(1, exPrincipal+1);
//         vm.prank(userEx2);
//         ex.unstake(2, exPrincipal+2);

//         uint256 wlAfter = stakingToken.balanceOf(userWl);
//         uint256 exAfter = stakingToken.balanceOf(userEx);

//         // console.log("exBefore",exBefore);
//         // console.log("exAfter",exAfter);

//         // console.log("wlBefore",wlBefore);
//         //         console.log("wlAfter",wlAfter);

//         uint256 wlReceived = wlAfter > wlBefore ? wlAfter - wlBefore : 0;

//         uint256 exReceived = exAfter > exBefore ? exAfter - exBefore : 0;

//         // console.log("exPrincipal",exPrincipal);
//         // console.log("exReceived",exReceived);

//         // console.log("wlPrincipal",wlPrincipal);

//         printRow(daysStaked, wlReceived, exReceived );
//     }
// }
