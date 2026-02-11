// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/IVault.sol";
import "../src/zkToken.sol";
import "./MockERC20.sol";
import "../src/WithdrawVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VaultV2Test is Test {
    Vault public vault;
    MockERC20 public mockUSDT;
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(4);
    address public user3 = address(5);
    address public newUser = address(6);
    address public ceffu = address(3);

    zkToken zk;

    address airdrop = makeAddr("airDropper");

    uint256 user1Assets = 800 ether;
    uint256 user2Assets = 5000 ether;
    uint256 user3Assets = 10000 ether;

    WithdrawVault withdrawVault;

    function setUp() public {
        mockUSDT = new MockERC20();

        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = address(mockUSDT);
        uint256[] memory rewardRate = new uint256[](1);
        rewardRate[0] = 700;
        uint256[] memory minStakeAmount = new uint256[](1);
        minStakeAmount[0] = 0;
        uint256[] memory maxStakeAmount = new uint256[](1);
        maxStakeAmount[0] = type(uint256).max;

        vm.startPrank(owner);
        withdrawVault = new WithdrawVault(supportedTokens, owner, owner, owner);
        vm.stopPrank();

        uint[] memory totalStaked = new uint[](1);

        totalStaked[0] = user1Assets + user2Assets + user3Assets;

        zk = new zkToken("zkUSDT", "zkUSDT", address(owner));
        address[] memory zks = new address[](1);
        zks[0] = address(zk);

        zk.mint(airdrop, totalStaked[0]);

        vm.startPrank(owner);
        vault = new Vault(
            supportedTokens,
            zks,
            rewardRate,
            minStakeAmount,
            maxStakeAmount,
            owner, // admin
            owner, // bot
            ceffu,
            14 days,
            payable(address(withdrawVault)),
            airdrop
        );

        withdrawVault.setVault(address(vault));
        zk.setToVault(address(vault), address(vault));
        zk.setAirdropper(airdrop);

        vm.stopPrank();
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    ///                                      Preparation                                         ///
    ////////////////////////////////////////////////////////////////////////////////////////////////
    
    // test1: airdrop
    function testAirDrop() public {

        vm.warp(block.timestamp + 1);

        vm.startPrank(airdrop);

        uint256 tvlBefore = vault.getTVL(address(mockUSDT));

        vault.sendLpTokens(address(mockUSDT), user1, 800 ether, true);
        vault.sendLpTokens(address(mockUSDT), user2, 5000 ether, true);
        vault.sendLpTokens(address(mockUSDT), user3, 10000 ether, true);

        uint256 tvlAfter = vault.getTVL(address(mockUSDT));
        assertEq(tvlAfter - tvlBefore, 15800 ether);

        vm.stopPrank();

        vm.startPrank(owner);
        vault.unpause();
        vm.stopPrank();

        uint256 user1StakedAmount = vault.getStakedAmount(user1, address(mockUSDT));
        uint256 user1TotalAmount = vault.getClaimableAssets(user1, address(mockUSDT));
        assertEq(user1StakedAmount, 800 ether);
        assertGt(user1TotalAmount, 800 ether); // principal + rewards

        uint256 user2StakedAmount = vault.getStakedAmount(user2, address(mockUSDT));
        uint256 user2TotalAmount = vault.getClaimableAssets(user2, address(mockUSDT));
        assertEq(user2StakedAmount, 5000 ether);
        assertGt(user2TotalAmount, 5000 ether); // principal + rewards

        uint256 user3StakedAmount = vault.getStakedAmount(user3, address(mockUSDT));
        uint256 user3TotalAmount = vault.getClaimableAssets(user3, address(mockUSDT));
        assertEq(user3StakedAmount, 10000 ether);
        assertGt(user3TotalAmount, 10000 ether); // principal + rewards

        assertEq(
            vault.totalStakeAmountByToken(address(mockUSDT)),
            15800 ether
        );
    }

    // test2: airdrop => stake
    function testStake() public {
        testAirDrop();

        uint256 tvlBefore = vault.getTVL(address(mockUSDT));

        vm.startPrank(user2);
        mockUSDT.mint(user2, 500 ether);
        mockUSDT.approve(address(vault), 500 ether);

        // Stake 500 tokens
        vault.stake_66380860(address(mockUSDT), 500 ether);

        // Check user's staked amount
        uint256 stakedAmount = vault.getStakedAmount(user2, address(mockUSDT));
        assertEq(stakedAmount, 500 ether + user2Assets);

        // Ensure Vault's token balance updated
        assertEq(mockUSDT.balanceOf(address(vault)), 500 ether);

        // ensure zkToken minted & equal to staked amount
        // uint256 zkAmount = vault.getZKTokenAmount(user2, address(mockUSDT));
        // console.log(
        //     zkAmount,
        //     vault.convertToShares(
        //         500 ether +
        //             user2Assets +
        //             vault.getClaimableRewards(user2, address(mockUSDT)),
        //         address(mockUSDT)
        //     )
        // );
        vm.stopPrank();

        uint256 tvlAfter = vault.getTVL(address(mockUSDT));

        assertEq(tvlAfter - tvlBefore, 500 ether);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    ///                                        Testing                                           ///
    ////////////////////////////////////////////////////////////////////////////////////////////////

    // test3: airdrop => stake => request => claim
    function testClaim() public {
        testStake();
        vm.startPrank(user2);

        // mint to withdrawVault for withdraw
        mockUSDT.mint(
            address(withdrawVault),
            10000 ether
        );

        uint256 balanceBeforeClaim = mockUSDT.balanceOf(user2);
        uint256 queueId = vault.requestClaim_8135334(address(mockUSDT) , type(uint256).max);

        vm.warp(block.timestamp + 14 days);

        vault.claim_41202704(queueId, address(mockUSDT));

        vm.stopPrank();

        uint256 balanceAfterClaim = mockUSDT.balanceOf(user2);

        assertGt(
            balanceAfterClaim - balanceBeforeClaim,
            5000 ether + 500 ether // principal + rewards
        );
    }

    // test4: airdrop => request => claim
    function testAirdropRequestAndClaim() public {
        testAirDrop();
        vm.startPrank(user1);

        // mint to withdrawVault for withdraw
        mockUSDT.mint(
            address(withdrawVault),
            10000 ether
        );

        uint256 user1BalanceBeforeClaim = mockUSDT.balanceOf(user1);

        uint256 queueId = vault.requestClaim_8135334(address(mockUSDT) , type(uint256).max);
        vm.warp(block.timestamp + 14 days);

        vault.claim_41202704(queueId, address(mockUSDT));
        vm.stopPrank();

        uint256 user1BalanceAfterClaim = mockUSDT.balanceOf(user1);

        assertGt(
            user1BalanceAfterClaim - user1BalanceBeforeClaim,
            800 ether // principal + rewards
        );

        vm.expectRevert();
        vault.cancelClaim(queueId, address(mockUSDT));
    }

    // test5: airdrop => request => cancel
    function testAirdropRequestAndCancel() public {
        testAirDrop();
        vm.startPrank(user1);

        // mint to withdrawVault for withdraw
        mockUSDT.mint(
            address(withdrawVault),
            10000 ether
        );
        uint256 queueId = vault.requestClaim_8135334(address(mockUSDT) , 500 ether);

        vault.cancelClaim(queueId, address(mockUSDT));

        vm.expectRevert();
        vault.cancelClaim(queueId, address(mockUSDT));

        vm.warp(block.timestamp + 14 days);

        vm.expectRevert();
        vault.claim_41202704(queueId, address(mockUSDT));

        vm.stopPrank();

        assertEq(mockUSDT.balanceOf(user1), 0);
    }

    // test6: airdrop => flashWithdraw
    function testFlashWithdraw() public {
        testAirDrop();
        mockUSDT.mint(address(vault), 10000 ether);

        uint256 tvlBefore = vault.getTVL(address(mockUSDT));
        uint256 totalStakedBefore = vault.totalStakeAmountByToken(address(mockUSDT));

        vm.startPrank(user2);
        vault.flashWithdrawWithPenalty(address(mockUSDT), type(uint256).max);
        vm.stopPrank();

        uint256 tvlAfter = vault.getTVL(address(mockUSDT));
        uint256 totalStakedAfter = vault.totalStakeAmountByToken(address(mockUSDT));

        assertEq(totalStakedAfter, totalStakedBefore - user2Assets);
        assertEq(tvlAfter, tvlBefore - user2Assets);

        assertEq(
            mockUSDT.balanceOf(user2),
            ((user2Assets + vault.getTotalRewards(user2, address(mockUSDT))) *
                (10000 - 50)) / 10000
        );
    }

    // test7: already possessing USDT => stake
    function testStakeNew() public {
        testAirDrop();
        vm.startPrank(newUser);
        mockUSDT.mint(newUser, 500 ether);
        mockUSDT.approve(address(vault), 500 ether);

        // Stake 500 tokens
        vault.stake_66380860(address(mockUSDT), 500 ether);

        // Check user's staked amount
        uint256 stakedAmount = vault.getStakedAmount(newUser, address(mockUSDT));
        assertEq(stakedAmount, 500 ether);
        assertEq(mockUSDT.balanceOf(newUser), 0);

        // Ensure Vault's token balance updated
        assertEq(mockUSDT.balanceOf(address(vault)), 500 ether);

        //ensure zkToken minted & equal to staked amount
        uint256 zkAmount = vault.getZKTokenAmount(newUser, address(mockUSDT));
        assertEq(zkAmount, vault.convertToShares(500 ether, address(mockUSDT)));
        vm.stopPrank();
    }

    // test8: already possessing USDT => stake => request
    function testRequestClaimNew() public returns (uint256, uint256, uint256) {
        testStakeNew();
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(newUser);
        uint256 reward = vault.getClaimableRewards(newUser, address(mockUSDT));
        uint256 withdrawAmount = 500 ether + reward;
        uint256 requestID = vault.requestClaim_8135334(
            address(mockUSDT),
            withdrawAmount
        );
        vm.stopPrank();

        // Validate the withdrawal request
        ClaimItem memory claimItem = vault.getClaimQueueInfo(requestID);
        assertEq(claimItem.totalAmount, withdrawAmount);
        assertEq(claimItem.token, address(mockUSDT));

        // burn all zkTokens
        assertEq(vault.getZKTokenAmount(newUser, address(mockUSDT)), 0);

        return (requestID, claimItem.totalAmount, claimItem.principalAmount);
    }

    // test9: already possessing USDT => stake => request => claim
    function testClaimNew() public {
        (
            uint256 id,
            uint256 totalAmount,
            uint256 principalAmount
        ) = testRequestClaimNew();
        mockUSDT.mint(address(withdrawVault), 1000 ether);

        vm.warp(block.timestamp + 14 days + 1);

        uint256 tvlBefore = vault.getTVL(address(mockUSDT));

        vm.startPrank(newUser);
        vault.claim_41202704(id, address(mockUSDT));
        vm.stopPrank();

        uint256 tvlAfter = vault.getTVL(address(mockUSDT));

        // Check user's balance
        assertEq(mockUSDT.balanceOf(newUser), totalAmount);
        assertEq(tvlAfter, tvlBefore - principalAmount);
    }

    // test10: already possessing USDT => stake => FlashWithdraw
    function testFlashWithdrawNew() public {
        testStakeNew();
        vm.warp(block.timestamp + 1 days);

        uint256 totalAssets = vault.getClaimableAssets(newUser, address(mockUSDT));
        mockUSDT.mint(address(vault), totalAssets);

        vm.startPrank(newUser);
        vault.flashWithdrawWithPenalty(address(mockUSDT), type(uint256).max);
        vm.stopPrank();

        // Check user's balance
        assertEq(
            mockUSDT.balanceOf(newUser),
            (totalAssets * (10000 - 50)) / 10000
        );
    }

    // test11: transferOrTransferFrom
    function testTokenTransfer() public {
        testAirDrop();
        uint256 user1AssetsAfterAirdrop = vault.getClaimableAssets(user1, address(mockUSDT));
        uint256 newUserAssetsAfterAirdrop = vault.getClaimableAssets(user1, address(mockUSDT));

        vm.startPrank(newUser);
        mockUSDT.mint(newUser, 500 ether);
        mockUSDT.approve(address(vault), 500 ether);
        vault.stake_66380860(address(mockUSDT), 500 ether);

        vault.transferOrTransferFrom(address(mockUSDT), newUser, user1, 100 ether);
        vm.stopPrank();

        assertGt(vault.getClaimableAssets(user1, address(mockUSDT)), user1AssetsAfterAirdrop + 100 ether);

        assertLe(vault.getClaimableAssets(newUser, address(mockUSDT)), newUserAssetsAfterAirdrop - 100 ether);
    }

    // test12: change rate
    function testChangeRate() public {
        testAirDrop();

        vm.startPrank(newUser);
        mockUSDT.mint(newUser, 500 ether);
        mockUSDT.approve(address(vault), 500 ether);
        vault.stake_66380860(address(mockUSDT), 500 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        vm.startPrank(owner);
        vault.setRewardRate(address(mockUSDT), 1400);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        uint256 reward = vault.getClaimableRewards(newUser, address(mockUSDT));

        uint256 expect = (uint256(500 ether) * 3500) / 3652500; //（700 * 1 + 1400 * 2）

        assertEq(reward, expect);
    }

    // test13: already possessing USDT => stake => request => cancel
    function testCancelRequest() public {
        testStake();

        vm.startPrank(user1);

        // mint to withdrawVault for withdraw
        mockUSDT.mint(
            address(withdrawVault),
            10000 ether
        );
        
        console.log("claimable assets:", vault.getClaimableAssets(user1, address(mockUSDT)));
        console.log("zkToken balances:", zk.balanceOf(user1));
        console.log();

        uint256 queueId = vault.requestClaim_8135334(address(mockUSDT) , 500 ether);

        vm.warp(block.timestamp + 7 days);

        console.log("claimable assets:", vault.getClaimableAssets(user1, address(mockUSDT)));
        console.log("zkToken balances:", zk.balanceOf(user1));
        console.log();

        vault.cancelClaim(queueId, address(mockUSDT));

        console.log("claimable assets:", vault.getClaimableAssets(user1, address(mockUSDT)));
        console.log("zkToken balances:", zk.balanceOf(user1));

        vm.warp(block.timestamp + 14 days);

        vm.expectRevert();
        vault.claim_41202704(queueId, address(mockUSDT));

        vm.stopPrank();
    }

    // test14: already possessing USDT => stake => flashWithdraw
    function testStakeAndFlashWithdraw() public {
        testAirDrop();

        mockUSDT.mint(address(vault), 5000 ether);

        vm.startPrank(user2);
        mockUSDT.mint(address(user2), 5000 ether);
        mockUSDT.approve(address(vault), 5000 ether);
        vault.stake_66380860(address(mockUSDT), 5000 ether);

        vm.stopPrank();

        uint256 tvlBefore = vault.getTVL(address(mockUSDT));
        uint256 totalStakedBefore = vault.totalStakeAmountByToken(address(mockUSDT));

        vm.startPrank(user2);
        vault.flashWithdrawWithPenalty(address(mockUSDT), type(uint256).max);
        vm.stopPrank();

        uint256 tvlAfter = vault.getTVL(address(mockUSDT));
        uint256 totalStakedAfter = vault.totalStakeAmountByToken(address(mockUSDT));

        user2Assets = mockUSDT.balanceOf(user2);

        assertEq(totalStakedAfter, totalStakedBefore - 10000 ether);
        assertEq(tvlAfter, tvlBefore - 10000 ether);

        assertEq(
            mockUSDT.balanceOf(user2),
            ((10000 ether + vault.getTotalRewards(user2, address(mockUSDT))) *
                (10000 - 50)) / 10000
        );
    }

    // test15: airdrop => stake => request => cancel
    function testAirDropCancel() public {
        testAirDrop();
        vm.startPrank(user1);

        // mint to withdrawVault for withdraw
        mockUSDT.mint(
            address(withdrawVault),
            10000 ether
        );
        uint256 queueId = vault.requestClaim_8135334(address(mockUSDT) , 500 ether);

        vault.cancelClaim(queueId, address(mockUSDT));

        vm.warp(block.timestamp + 14 days);

        vm.expectRevert();
        vault.claim_41202704(queueId, address(mockUSDT));

        vm.stopPrank();
    }
}
