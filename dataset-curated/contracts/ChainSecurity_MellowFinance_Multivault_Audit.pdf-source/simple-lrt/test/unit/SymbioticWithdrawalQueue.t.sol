// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../BaseTest.sol";

contract Unit is BaseTest {
    using RandomLib for RandomLib.Storage;

    uint48 public constant epochDuration = 1 weeks;

    function testConstructor() external {
        // vm.expectRevert();
        // new SymbioticWithdrawalQueue(address(0));

        (address symbioticVault,,,) =
            symbioticHelper.createDefaultSymbioticVault(Constants.WSTETH());
        assertNotEq(address(0), address(new SymbioticWithdrawalQueue(address(0))));
    }

    function testRegularCreationSymbioticWithdrawalQueue() external {
        address vault = rnd.randAddress();
        SymbioticAdapter adapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        (address symbioticVault,,,) =
            symbioticHelper.createDefaultSymbioticVault(Constants.WSTETH());
        vm.startPrank(vault);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(adapter.handleVault(symbioticVault));
        assertNotEq(address(withdrawalQueue), address(0));
    }

    function testSymbioticWithdrawalQueue() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,, address symbioticVault) =
            createDefaultMultiVaultWithSymbioticVault(vaultAdmin);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user = rnd.randAddress();
        vm.startPrank(user);
        deal(Constants.WSTETH(), user, 1 ether);
        IERC20(Constants.WSTETH()).approve(address(vault), type(uint256).max);
        vault.deposit(1 ether, user);
        vault.redeem(vault.balanceOf(user), user, user);
        vm.stopPrank();

        assertEq(ISymbioticVault(symbioticVault).activeBalanceOf(address(withdrawalQueue)), 0);
        assertEq(
            ISymbioticVault(symbioticVault).slashableBalanceOf(address(withdrawalQueue)), 1 ether
        );
    }

    function testWithdrawalQueue() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,, address symbioticVault) =
            createDefaultMultiVaultWithSymbioticVault(vaultAdmin);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user1 = rnd.randAddress();
        address user2 = rnd.randAddress();

        uint256 amount1 = 100 ether;
        uint256 amount2 = 10 ether;

        deal(Constants.WSTETH(), user1, amount1);
        deal(Constants.WSTETH(), user2, amount2);

        uint256 nextEpochStartIn = epochDuration - (block.timestamp % epochDuration);
        skip(nextEpochStartIn);

        vm.startPrank(user1);
        IERC20(Constants.WSTETH()).approve(address(vault), amount1);
        vault.deposit(amount1, user1);
        vault.withdraw(amount1 / 2, user1, user1);
        vm.stopPrank();

        // new epoch
        skip(epochDuration);

        vm.startPrank(user2);
        IERC20(Constants.WSTETH()).approve(address(vault), amount2);
        vault.deposit(amount2, user2);
        vault.withdraw(amount2 / 2, user2, user2);
        vm.stopPrank();

        assertEq(
            withdrawalQueue.pendingAssetsOf(user1), amount1 / 2, "initial pendingAssetsOf(user1)"
        );
        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "initial claimableAssetsOf(user1)");

        assertEq(
            withdrawalQueue.pendingAssetsOf(user2), amount2 / 2, "initial pendingAssetsOf(user2)"
        );
        assertEq(withdrawalQueue.claimableAssetsOf(user2), 0, "initial claimableAssetsOf(user2)");

        // new epoch
        skip(epochDuration);

        assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "stage 1: pendingAssetsOf(user1)");
        assertEq(
            withdrawalQueue.claimableAssetsOf(user1),
            amount1 / 2,
            "stage 1: claimableAssetsOf(user1)"
        );

        assertEq(
            withdrawalQueue.pendingAssetsOf(user2), amount2 / 2, "stage 1: pendingAssetsOf(user2)"
        );
        assertEq(withdrawalQueue.claimableAssetsOf(user2), 0, "stage 1: claimableAssetsOf(user2)");

        skip(epochDuration);

        assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "stage 2: pendingAssetsOf(user1)");
        assertEq(
            withdrawalQueue.claimableAssetsOf(user1),
            amount1 / 2,
            "stage 2: claimableAssetsOf(user1)"
        );

        assertEq(withdrawalQueue.pendingAssetsOf(user2), 0, "stage 2: pendingAssetsOf(user2)");
        assertEq(
            withdrawalQueue.claimableAssetsOf(user2),
            amount2 / 2,
            "stage 2: claimableAssetsOf(user2)"
        );
    }

    function testWithdrawalQueueMultipleRequests() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,, address symbioticVault) =
            createDefaultMultiVaultWithSymbioticVault(vaultAdmin);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user1 = rnd.randAddress();
        address user2 = rnd.randAddress();

        uint256 amount1 = 100 ether;

        deal(Constants.WSTETH(), user1, amount1);

        uint256 nextEpochStartIn = epochDuration - (block.timestamp % epochDuration);
        skip(nextEpochStartIn);

        vm.startPrank(user1);
        IERC20(Constants.WSTETH()).approve(address(vault), amount1);
        vault.deposit(amount1, user1);
        vault.withdraw(amount1 / 10, user1, user1);
        vm.stopPrank();

        assertEq(
            withdrawalQueue.pendingAssetsOf(user1), amount1 / 10, "initial pendingAssetsOf(user1)"
        );
        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "initial claimableAssetsOf(user1)");

        // new epoch
        skip(epochDuration);

        assertEq(
            withdrawalQueue.pendingAssetsOf(user1), amount1 / 10, "stage 1: pendingAssetsOf(user1)"
        );
        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "stage 1: claimableAssetsOf(user1)");

        vm.prank(user1);
        vault.withdraw(amount1 / 10, user1, user1);

        assertEq(
            withdrawalQueue.pendingAssetsOf(user1),
            2 * amount1 / 10,
            "stage 2: pendingAssetsOf(user1)"
        );
        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "stage 2: claimableAssetsOf(user1)");

        skip(epochDuration);

        assertEq(
            withdrawalQueue.pendingAssetsOf(user1), amount1 / 10, "stage 3: pendingAssetsOf(user1)"
        );
        assertEq(
            withdrawalQueue.claimableAssetsOf(user1),
            amount1 / 10,
            "stage 3: claimableAssetsOf(user1)"
        );

        skip(epochDuration);

        assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "stage 4: pendingAssetsOf(user1)");
        assertEq(
            withdrawalQueue.claimableAssetsOf(user1),
            2 * amount1 / 10,
            "stage 4: claimableAssetsOf(user1)"
        );

        vm.prank(user1);
        withdrawalQueue.claim(user1, user1, type(uint256).max);

        assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "stage 5: pendingAssetsOf(user1)");
        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "stage 5: claimableAssetsOf(user1)");
    }

    function testCurrentEpoch() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,, address symbioticVault) =
            createDefaultMultiVaultWithSymbioticVault(vaultAdmin);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user1 = rnd.randAddress();
        address user2 = rnd.randAddress();

        assertEq(withdrawalQueue.getCurrentEpoch(), 0, "initial getCurrentEpoch");
        assertEq(ISymbioticVault(symbioticVault).currentEpoch(), 0, "initial currentEpoch");
        skip(epochDuration);

        assertEq(withdrawalQueue.getCurrentEpoch(), 1, "stage 1: getCurrentEpoch");
        assertEq(ISymbioticVault(symbioticVault).currentEpoch(), 1, "stage 1: currentEpoch");
        skip(epochDuration);

        assertEq(withdrawalQueue.getCurrentEpoch(), 2, "stage 2: getCurrentEpoch");
        assertEq(ISymbioticVault(symbioticVault).currentEpoch(), 2, "stage 2: currentEpoch");
        skip(epochDuration);

        assertEq(withdrawalQueue.getCurrentEpoch(), 3, "stage 3: getCurrentEpoch");
        assertEq(ISymbioticVault(symbioticVault).currentEpoch(), 3, "stage 3: currentEpoch");
    }

    function testPendingAssets() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,, address symbioticVault) =
            createDefaultMultiVaultWithSymbioticVault(vaultAdmin);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user1 = rnd.randAddress();
        address user2 = rnd.randAddress();

        uint256 amount1 = 100 ether;
        uint256 amount2 = 10 ether;

        deal(Constants.WSTETH(), user1, amount1);
        deal(Constants.WSTETH(), user2, amount2);

        vm.startPrank(user1);
        IERC20(Constants.WSTETH()).approve(address(vault), amount1);
        vault.deposit(amount1, user1);
        vault.withdraw(amount1 / 2, user1, user1);
        vm.stopPrank();

        // new epoch
        skip(epochDuration);

        vm.startPrank(user2);
        IERC20(Constants.WSTETH()).approve(address(vault), amount2);
        vault.deposit(amount2, user2);
        vault.withdraw(amount2 / 2, user2, user2);
        vm.stopPrank();

        assertEq(
            withdrawalQueue.pendingAssets(), amount1 / 2 + amount2 / 2, "epoch 0: pendingAssets"
        );
        skip(epochDuration);
        assertEq(withdrawalQueue.pendingAssets(), amount2 / 2, "epoch 1: pendingAssets");
        skip(epochDuration);
        assertEq(withdrawalQueue.pendingAssets(), 0, "epoch 2: pendingAssets");
    }

    function testPendingAssetsOf() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,, address symbioticVault) =
            createDefaultMultiVaultWithSymbioticVault(vaultAdmin);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user1 = rnd.randAddress();
        address user2 = rnd.randAddress();

        {
            uint256 amount1 = 100 ether;
            uint256 amount2 = 10 ether;

            deal(Constants.WSTETH(), user1, amount1);
            deal(Constants.WSTETH(), user2, amount2);

            vm.startPrank(user1);
            IERC20(Constants.WSTETH()).approve(address(vault), amount1);
            vault.deposit(amount1, user1);
            vault.withdraw(amount1 / 2, user1, user1);
            vm.stopPrank();

            // new epoch
            skip(epochDuration);

            vm.startPrank(user2);
            IERC20(Constants.WSTETH()).approve(address(vault), amount2);
            vault.deposit(amount2, user2);
            vault.withdraw(amount2 / 2, user2, user2);
            vm.stopPrank();

            assertEq(withdrawalQueue.pendingAssetsOf(user1), amount1 / 2, "user1: pendingAssets");

            assertEq(withdrawalQueue.pendingAssetsOf(user2), amount2 / 2, "user2: pendingAssets");

            skip(epochDuration);

            assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "user1: pendingAssets");
            assertEq(withdrawalQueue.pendingAssetsOf(user2), amount2 / 2, "user2: pendingAssets");

            skip(epochDuration);

            assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "user1: pendingAssets");
            assertEq(withdrawalQueue.pendingAssetsOf(user2), 0, "user2: pendingAssets");

            vm.prank(user1);
            withdrawalQueue.claim(user1, user1, amount1 / 2 - 1);

            assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "user1: pendingAssets");
            assertEq(withdrawalQueue.pendingAssetsOf(user2), 0, "user2: pendingAssets");

            vm.prank(user1);
            withdrawalQueue.claim(user1, user1, 1);

            assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "user1: pendingAssets");
            assertEq(withdrawalQueue.pendingAssetsOf(user2), 0, "user2: pendingAssets");
        }
        {
            uint256 amount1 = 100 ether;
            uint256 amount2 = 10 ether;

            deal(Constants.WSTETH(), user1, amount1);
            deal(Constants.WSTETH(), user2, amount2);

            vm.startPrank(user1);
            IERC20(Constants.WSTETH()).approve(address(vault), amount1);
            vault.deposit(amount1, user1);
            vault.withdraw(amount1 / 2, user1, user1);
            vm.stopPrank();

            // new epoch
            skip(epochDuration);

            vm.startPrank(user1);
            vault.withdraw(amount1 / 2, user1, user1);
            vm.stopPrank();

            assertEq(withdrawalQueue.pendingAssetsOf(user1), amount1, "user1: pendingAssets");

            skip(epochDuration);

            assertEq(withdrawalQueue.pendingAssetsOf(user1), amount1 / 2, "user1: pendingAssets");

            skip(epochDuration);

            assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "user1: pendingAssets");

            vm.prank(user1);
            withdrawalQueue.claim(user1, user1, amount1 / 2);

            assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "user1: pendingAssets");

            vm.prank(user1);
            withdrawalQueue.claim(user1, user1, amount1 / 2);

            assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "user1: pendingAssets");

            uint256 epoch = SymbioticWithdrawalQueue(address(withdrawalQueue)).getCurrentEpoch() - 1;
            bytes32 slot = bytes32(uint256(keccak256(bytes.concat(bytes32(epoch), bytes32(0)))));
            vm.store(address(withdrawalQueue), slot, bytes32(0));

            vm.prank(user1);
            SymbioticWithdrawalQueue(address(withdrawalQueue)).pull(epoch);

            assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "user1: pendingAssets");
        }
    }

    function testClaimableAssetsOf() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,, address symbioticVault) =
            createDefaultMultiVaultWithSymbioticVault(vaultAdmin);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user1 = rnd.randAddress();
        address user2 = rnd.randAddress();

        uint256 amount1 = 100 ether;
        uint256 amount2 = 10 ether;

        deal(Constants.WSTETH(), user1, amount1);
        deal(Constants.WSTETH(), user2, amount2);

        vm.startPrank(user1);
        IERC20(Constants.WSTETH()).approve(address(vault), amount1);
        vault.deposit(amount1, user1);
        vault.withdraw(amount1 / 2, user1, user1);
        vm.stopPrank();

        // new epoch
        skip(epochDuration);

        vm.startPrank(user2);
        IERC20(Constants.WSTETH()).approve(address(vault), amount2);
        vault.deposit(amount2, user2);
        vault.withdraw(amount2 / 2, user2, user2);
        vm.stopPrank();

        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "user1: claimableAssets");
        assertEq(withdrawalQueue.claimableAssetsOf(user2), 0, "user2: claimableAssets");

        skip(epochDuration);

        assertEq(withdrawalQueue.claimableAssetsOf(user1), amount1 / 2, "user1: claimableAssets");
        assertEq(withdrawalQueue.claimableAssetsOf(user2), 0, "user2: claimableAssets");

        skip(epochDuration);

        assertEq(withdrawalQueue.claimableAssetsOf(user1), amount1 / 2, "user1: claimableAssets");
        assertEq(withdrawalQueue.claimableAssetsOf(user2), amount2 / 2, "user2: claimableAssets");

        vm.prank(user1);
        withdrawalQueue.claim(user1, user1, amount1 / 2 - 1);

        assertEq(withdrawalQueue.claimableAssetsOf(user1), 1, "user1: claimableAssets");
        assertEq(withdrawalQueue.claimableAssetsOf(user2), amount2 / 2, "user2: claimableAssets");

        vm.prank(user1);
        withdrawalQueue.claim(user1, user1, 1);

        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "user1: claimableAssets");
        assertEq(withdrawalQueue.claimableAssetsOf(user2), amount2 / 2, "user2: claimableAssets");
    }

    function testRequest() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,, address symbioticVault) =
            createDefaultMultiVaultWithSymbioticVault(vaultAdmin);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user1 = rnd.randAddress();
        address user2 = rnd.randAddress();

        uint256 amount1 = 100 ether;
        uint256 amount2 = 10 ether;

        deal(Constants.WSTETH(), user1, amount1);
        deal(Constants.WSTETH(), user2, amount2);

        vm.startPrank(user1);
        IERC20(Constants.WSTETH()).approve(address(vault), amount1);
        vault.deposit(amount1, user1);
        vm.stopPrank();

        vm.expectRevert();
        withdrawalQueue.request(user1, amount1 / 2);

        vm.startPrank(address(vault));
        ISymbioticVault(symbioticVault).withdraw(address(withdrawalQueue), amount1 / 2);
        withdrawalQueue.request(user1, amount1 / 2);
        vm.stopPrank();

        assertEq(withdrawalQueue.pendingAssetsOf(user1), amount1 / 2, "stage 0: pendingAssetsOf");
        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "stage 0: claimableAssetsOf");

        skip(epochDuration * 2);

        assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "stage 1: pendingAssetsOf");
        assertEq(
            withdrawalQueue.claimableAssetsOf(user1), amount1 / 2, "stage 1: claimableAssetsOf"
        );
    }

    function testPull() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,, address symbioticVault) =
            createDefaultMultiVaultWithSymbioticVault(vaultAdmin);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user1 = rnd.randAddress();
        address user2 = rnd.randAddress();

        uint256 amount1 = 100 ether;
        uint256 amount2 = 10 ether;

        deal(Constants.WSTETH(), user1, amount1);
        deal(Constants.WSTETH(), user2, amount2);

        vm.startPrank(user1);
        IERC20(Constants.WSTETH()).approve(address(vault), amount1);
        vault.deposit(amount1, user1);
        vault.withdraw(amount1 / 2, user1, user1);
        vm.stopPrank();

        assertEq(withdrawalQueue.pendingAssetsOf(user1), amount1 / 2, "stage 0: pendingAssetsOf");
        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "stage 0: claimableAssetsOf");

        skip(epochDuration);

        assertEq(withdrawalQueue.pendingAssetsOf(user1), amount1 / 2, "stage 0: pendingAssetsOf");
        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "stage 0: claimableAssetsOf");

        uint256 currentEpoch = withdrawalQueue.getCurrentEpoch();

        assertGt(currentEpoch, 0, "currentEpoch > 0");

        vm.expectRevert();
        withdrawalQueue.pull(currentEpoch);
        withdrawalQueue.pull(currentEpoch - 1);

        assertEq(withdrawalQueue.pendingAssetsOf(user1), amount1 / 2, "stage 0: pendingAssetsOf");
        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "stage 0: claimableAssetsOf");
    }

    function testClaim() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,, address symbioticVault) =
            createDefaultMultiVaultWithSymbioticVault(vaultAdmin);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user1 = rnd.randAddress();
        address user2 = rnd.randAddress();

        uint256 amount1 = 100 ether;
        uint256 amount2 = 10 ether;

        deal(Constants.WSTETH(), user1, amount1);
        deal(Constants.WSTETH(), user2, amount2);

        vm.startPrank(user1);
        IERC20(Constants.WSTETH()).approve(address(vault), amount1);
        vault.deposit(amount1, user1);
        vault.withdraw(amount1 / 2, user1, user1);
        vm.stopPrank();

        assertEq(withdrawalQueue.pendingAssetsOf(user1), amount1 / 2, "stage 0: pendingAssetsOf");
        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "stage 0: claimableAssetsOf");

        skip(epochDuration * 2);

        assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "stage 1: pendingAssetsOf");
        assertEq(
            withdrawalQueue.claimableAssetsOf(user1), amount1 / 2, "stage 1: claimableAssetsOf"
        );

        // uint256 currentEpoch = withdrawalQueue.getCurrentEpoch();

        vm.expectRevert();
        withdrawalQueue.claim(user1, user1, amount1 / 2);

        vm.startPrank(user1);

        uint256 claimableAmount = amount1 / 2;
        assertEq(withdrawalQueue.claimableAssetsOf(user1), claimableAmount, "wrong claimableAmount");
        uint256 balanceBefore = IERC20(Constants.WSTETH()).balanceOf(user1);
        withdrawalQueue.claim(user1, user1, amount1 / 2);
        uint256 balanceAfter = IERC20(Constants.WSTETH()).balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, claimableAmount, "wrong claimed amount");

        withdrawalQueue.claim(user1, user1, amount1 / 2);

        vm.stopPrank();
    }

    function testHandlePendingEpochs() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,, address symbioticVault) =
            createDefaultMultiVaultWithSymbioticVault(vaultAdmin);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user1 = rnd.randAddress();
        address user2 = rnd.randAddress();

        uint256 amount1 = 100 ether;
        uint256 amount2 = 10 ether;

        deal(Constants.WSTETH(), user1, amount1);
        deal(Constants.WSTETH(), user2, amount2);

        vm.startPrank(user1);
        IERC20(Constants.WSTETH()).approve(address(vault), amount1);
        vault.deposit(amount1, user1);
        vault.withdraw(amount1 / 2, user1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        IERC20(Constants.WSTETH()).approve(address(vault), amount2);
        vault.deposit(amount2, user2);
        vault.withdraw(amount2 / 2, user2, user2);
        vm.stopPrank();

        assertEq(withdrawalQueue.pendingAssetsOf(user1), amount1 / 2, "stage 0: pendingAssetsOf");
        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "stage 0: claimableAssetsOf");

        skip(epochDuration * 2);
        uint256 epoch = withdrawalQueue.getCurrentEpoch() - 1;
        assertFalse(withdrawalQueue.getEpochData(epoch).isClaimed);

        assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "stage 1: pendingAssetsOf");
        assertEq(
            withdrawalQueue.claimableAssetsOf(user1), amount1 / 2, "stage 1: claimableAssetsOf"
        );

        withdrawalQueue.handlePendingEpochs(user1);
        assertTrue(withdrawalQueue.getEpochData(epoch).isClaimed);

        assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "stage 1: pendingAssetsOf");
        assertEq(
            withdrawalQueue.claimableAssetsOf(user1), amount1 / 2, "stage 1: claimableAssetsOf"
        );
        assertEq(withdrawalQueue.pendingAssetsOf(user2), 0, "stage 1: pendingAssetsOf");
        assertEq(
            withdrawalQueue.claimableAssetsOf(user2), amount2 / 2, "stage 1: claimableAssetsOf"
        );

        withdrawalQueue.handlePendingEpochs(user2);

        assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "stage 1: pendingAssetsOf");
        assertEq(
            withdrawalQueue.claimableAssetsOf(user1), amount1 / 2, "stage 1: claimableAssetsOf"
        );
        assertEq(withdrawalQueue.pendingAssetsOf(user2), 0, "stage 1: pendingAssetsOf");
        assertEq(
            withdrawalQueue.claimableAssetsOf(user2), amount2 / 2, "stage 1: claimableAssetsOf"
        );

        withdrawalQueue.handlePendingEpochs(user1);
        withdrawalQueue.handlePendingEpochs(user2);

        assertEq(withdrawalQueue.pendingAssetsOf(user1), 0, "stage 1: pendingAssetsOf");
        assertEq(
            withdrawalQueue.claimableAssetsOf(user1), amount1 / 2, "stage 1: claimableAssetsOf"
        );
        assertEq(withdrawalQueue.pendingAssetsOf(user2), 0, "stage 1: pendingAssetsOf");
        assertEq(
            withdrawalQueue.claimableAssetsOf(user2), amount2 / 2, "stage 1: claimableAssetsOf"
        );
    }

    function testGetAccountData() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,, address symbioticVault) =
            createDefaultMultiVaultWithSymbioticVault(vaultAdmin);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user = rnd.randAddress();
        (
            uint256 sharesToClaimPrev,
            uint256 sharesToClaim,
            uint256 claimableAssets,
            uint256 claimEpoch
        ) = withdrawalQueue.getAccountData(user);
        assertEq(sharesToClaimPrev, 0, "initial sharesToClaimPrev");
        assertEq(sharesToClaim, 0, "initial sharesToClaim");
        assertEq(claimableAssets, 0, "initial claimableAssets");
        assertEq(claimEpoch, 0, "initial claimEpoch");

        vm.startPrank(user);

        deal(Constants.WSTETH(), user, 100 ether);
        IERC20(Constants.WSTETH()).approve(address(vault), 100 ether);
        vault.deposit(100 ether, user);
        vault.withdraw(50 ether, user, user);

        (sharesToClaimPrev, sharesToClaim, claimableAssets, claimEpoch) =
            withdrawalQueue.getAccountData(user);

        assertEq(sharesToClaimPrev, 0, "stage 1: sharesToClaimPrev");
        assertEq(sharesToClaim, 50 ether, "stage 1: sharesToClaim");
        assertEq(claimableAssets, 0, "stage 1: claimableAssets");
        assertEq(claimEpoch, 1, "stage 1: claimEpoch");

        skip(epochDuration);

        (sharesToClaimPrev, sharesToClaim, claimableAssets, claimEpoch) =
            withdrawalQueue.getAccountData(user);

        assertEq(sharesToClaimPrev, 0, "stage 2: sharesToClaimPrev");
        assertEq(sharesToClaim, 50 ether, "stage 2: sharesToClaim");
        assertEq(claimableAssets, 0, "stage 2: claimableAssets");
        assertEq(claimEpoch, 1, "stage 2: claimEpoch");

        skip(epochDuration);

        (sharesToClaimPrev, sharesToClaim, claimableAssets, claimEpoch) =
            withdrawalQueue.getAccountData(user);

        assertEq(sharesToClaimPrev, 0, "stage 3: sharesToClaimPrev");
        assertEq(sharesToClaim, 50 ether, "stage 3: sharesToClaim");
        assertEq(claimableAssets, 0, "stage 3: claimableAssets");
        assertEq(claimEpoch, 1, "stage 3: claimEpoch");

        withdrawalQueue.pull(1);

        (sharesToClaimPrev, sharesToClaim, claimableAssets, claimEpoch) =
            withdrawalQueue.getAccountData(user);

        assertEq(sharesToClaimPrev, 0, "stage 4: sharesToClaimPrev");
        assertEq(sharesToClaim, 50 ether, "stage 4: sharesToClaim");
        assertEq(claimableAssets, 0, "stage 4: claimableAssets");
        assertEq(claimEpoch, 1, "stage 4: claimEpoch");

        withdrawalQueue.handlePendingEpochs(user);

        (sharesToClaimPrev, sharesToClaim, claimableAssets, claimEpoch) =
            withdrawalQueue.getAccountData(user);

        assertEq(sharesToClaimPrev, 0, "stage 5: sharesToClaimPrev");
        assertEq(sharesToClaim, 0, "stage 5: sharesToClaim");
        assertEq(claimableAssets, 50 ether, "stage 5: claimableAssets");
        assertEq(claimEpoch, 1, "stage 5: claimEpoch");

        vm.stopPrank();
    }

    function testTransferPendingAssets() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,, address symbioticVault) =
            createDefaultMultiVaultWithSymbioticVault(vaultAdmin);
        ISymbioticWithdrawalQueue withdrawalQueue =
            ISymbioticWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user = rnd.randAddress();
        (
            uint256 sharesToClaimPrev,
            uint256 sharesToClaim,
            uint256 claimableAssets,
            uint256 claimEpoch
        ) = withdrawalQueue.getAccountData(user);
        assertEq(sharesToClaimPrev, 0, "initial sharesToClaimPrev");
        assertEq(sharesToClaim, 0, "initial sharesToClaim");
        assertEq(claimableAssets, 0, "initial claimableAssets");
        assertEq(claimEpoch, 0, "initial claimEpoch");

        vm.startPrank(user);

        deal(Constants.WSTETH(), user, 100 ether);
        IERC20(Constants.WSTETH()).approve(address(vault), 100 ether);
        vault.deposit(100 ether, user);
        vault.withdraw(50 ether, user, user);

        uint256 totalPending = withdrawalQueue.pendingAssetsOf(user);

        address user2 = rnd.randAddress();
        // zero amount == early exit
        withdrawalQueue.transferPendingAssets(user2, 0);
        assertEq(
            totalPending, withdrawalQueue.pendingAssetsOf(user), "stage 1: pendingAssetsOf(user)"
        );
        assertEq(0, withdrawalQueue.pendingAssetsOf(user2), "stage 1: pendingAssetsOf(user2)");

        // self transfer == early exit
        withdrawalQueue.transferPendingAssets(user, totalPending);
        assertEq(
            totalPending, withdrawalQueue.pendingAssetsOf(user), "stage 1: pendingAssetsOf(user)"
        );
        assertEq(0, withdrawalQueue.pendingAssetsOf(user2), "stage 1: pendingAssetsOf(user2)");

        // current epoch is enounch
        withdrawalQueue.transferPendingAssets(user2, totalPending / 2);
        assertEq(
            totalPending / 2,
            withdrawalQueue.pendingAssetsOf(user),
            "stage 2: pendingAssetsOf(user)"
        );
        assertEq(
            totalPending / 2,
            withdrawalQueue.pendingAssetsOf(user2),
            "stage 2: pendingAssetsOf(user2)"
        );

        skip(epochDuration);
        vault.withdraw(50 ether, user, user);

        // current epoch is not enounch
        withdrawalQueue.transferPendingAssets(user2, totalPending + 1 wei);
        assertEq(
            totalPending / 2 - 1 wei,
            withdrawalQueue.pendingAssetsOf(user),
            "stage 3: pendingAssetsOf(user)"
        );
        assertEq(
            totalPending * 3 / 2 + 1 wei,
            withdrawalQueue.pendingAssetsOf(user2),
            "stage 3: pendingAssetsOf(user2)"
        );

        // current epoch is not enounch
        withdrawalQueue.transferPendingAssets(user2, totalPending / 2 - 1 wei);
        assertEq(0, withdrawalQueue.pendingAssetsOf(user), "stage 4: pendingAssetsOf(user)");
        assertEq(
            totalPending * 2,
            withdrawalQueue.pendingAssetsOf(user2),
            "stage 4: pendingAssetsOf(user2)"
        );

        vm.expectRevert("SymbioticWithdrawalQueue: insufficient pending assets");
        withdrawalQueue.transferPendingAssets(user2, 1 wei);

        vm.stopPrank();
    }
}
