// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../BaseTest.sol";

contract Unit is BaseTest {
    using RandomLib for RandomLib.Storage;

    function testConstructor() external {
        address withdrawalQueue = address(
            new EigenLayerWithdrawalQueue(
                address(new Claimer()), Constants.HOLESKY_EL_DELEGATION_MANAGER
            )
        );

        require(withdrawalQueue != address(0));
    }

    function testLatestWithdrawableBlock() external {
        EigenLayerWithdrawalQueue withdrawalQueue = new EigenLayerWithdrawalQueue(
            address(new Claimer()), Constants.HOLESKY_EL_DELEGATION_MANAGER
        );
        uint256 latestWithdrawableBlock = withdrawalQueue.latestWithdrawableBlock();

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(withdrawalQueue.strategy());
        require(
            latestWithdrawableBlock
                == block.number
                    - IDelegationManager(withdrawalQueue.delegation()).getWithdrawalDelay(strategies)
        );
    }

    function testInitialize() external {
        Claimer claimer = new Claimer();

        EigenLayerWithdrawalQueue withdrawalQueueSingleton =
            new EigenLayerWithdrawalQueue(address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER);

        require(address(withdrawalQueueSingleton) != address(0));

        vm.expectRevert(); // InvalidInitialization()
        withdrawalQueueSingleton.initialize(address(1), address(2), address(3));

        address proxyAdmin = rnd.randAddress();
        new TransparentUpgradeableProxy{salt: bytes32(uint256(1))}(
            address(withdrawalQueueSingleton),
            proxyAdmin,
            abi.encodeCall(
                EigenLayerWithdrawalQueue.initialize, (address(1), address(2), address(3))
            )
        );
    }

    function testClaimableAssetsOf() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,,) = createDefaultMultiVaultWithEigenWstETHVault(vaultAdmin);
        IEigenLayerWithdrawalQueue withdrawalQueue =
            EigenLayerWstETHWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user1 = rnd.randAddress();
        address user2 = rnd.randAddress();

        uint256 amount1 = 100 ether;
        uint256 amount2 = 10 ether;

        deal(Constants.WSTETH(), user1, amount1);
        deal(Constants.WSTETH(), user2, amount2);

        {
            vm.startPrank(user1);
            IERC20(Constants.WSTETH()).approve(address(vault), amount1);
            vault.deposit(amount1, user1);
            vault.withdraw(amount1 / 2, user1, user1);
            vm.stopPrank();

            assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "user1: claimableAssets");
            vm.roll(block.number + 10); // skip delay
            assertApproxEqAbs(
                withdrawalQueue.claimableAssetsOf(user1), amount1 / 2, 2, "user1: claimableAssets"
            );
        }
        {
            vm.startPrank(user2);
            IERC20(Constants.WSTETH()).approve(address(vault), amount2);
            vault.deposit(amount2, user2);
            vault.withdraw(amount2 / 2, user2, user2);
            vm.stopPrank();

            assertEq(withdrawalQueue.claimableAssetsOf(user2), 0, "user2: claimableAssets");
            vm.roll(block.number + 10); // skip delay
            assertApproxEqAbs(
                withdrawalQueue.claimableAssetsOf(user2), amount2 / 2, 2, "user2: claimableAssets"
            );
        }

        {
            vm.startPrank(user1);
            withdrawalQueue.claim(user1, user1, withdrawalQueue.claimableAssetsOf(user1));
            vm.stopPrank();
            assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "user1: claimableAssets");
            assertApproxEqAbs(
                IERC20(Constants.WSTETH()).balanceOf(user1), amount1 / 2, 3, "user1: balance"
            );
        }
        {
            vm.startPrank(user2);
            withdrawalQueue.claim(user2, user2, withdrawalQueue.claimableAssetsOf(user2));
            vm.stopPrank();
            assertEq(withdrawalQueue.claimableAssetsOf(user2), 0, "user2: claimableAssets");
            assertApproxEqAbs(
                IERC20(Constants.WSTETH()).balanceOf(user2), amount2 / 2, 3, "user2: balance"
            );
        }

        vm.startPrank(user1);
        vault.withdraw(vault.maxWithdraw(user1), user1, user1);
        vm.stopPrank();
        assertEq(withdrawalQueue.claimableAssetsOf(user1), 0, "user1: claimableAssets");
        vm.roll(block.number + 10); // skip delay
        assertApproxEqAbs(
            withdrawalQueue.claimableAssetsOf(user1), amount1 / 2, 3, "user1: claimableAssets"
        );

        vm.startPrank(user2);
        vault.withdraw(vault.maxWithdraw(user2), user2, user2);
        vm.stopPrank();
        assertEq(withdrawalQueue.claimableAssetsOf(user2), 0, "user2: claimableAssets");
        vm.roll(block.number + 10); // skip delay
        assertApproxEqAbs(
            withdrawalQueue.claimableAssetsOf(user2), amount2 / 2, 3, "user2: claimableAssets"
        );

        vm.startPrank(user1);
        withdrawalQueue.claim(user1, user1, withdrawalQueue.claimableAssetsOf(user1));
        vm.stopPrank();

        assertApproxEqAbs(IERC20(Constants.WSTETH()).balanceOf(user1), amount1, 6, "user1: balance");

        vm.startPrank(user2);
        withdrawalQueue.claim(user2, user2, withdrawalQueue.claimableAssetsOf(user2));
        vm.stopPrank();

        assertApproxEqAbs(IERC20(Constants.WSTETH()).balanceOf(user2), amount2, 6, "user2: balance");

        return;
    }

    function testTransferPendingAssets() external {
        address vaultAdmin = rnd.randAddress();
        (MultiVault vault,,,) = createDefaultMultiVaultWithEigenWstETHVault(vaultAdmin);
        IEigenLayerWithdrawalQueue withdrawalQueue =
            EigenLayerWstETHWithdrawalQueue(vault.subvaultAt(0).withdrawalQueue);

        address user1 = 0x0101010101010101010101010101010101010101; // rnd.randAddress();
        address user2 = 0x0202020202020202020202020202020202020202; //rnd.randAddress();

        uint256 amount1 = 100 ether;

        deal(Constants.WSTETH(), user1, amount1);

        vm.startPrank(user1);
        IERC20(Constants.WSTETH()).approve(address(vault), amount1);
        vault.deposit(amount1, user1);
        vault.withdraw(amount1 / 2, user1, user1);
        uint256 totalPending = withdrawalQueue.pendingAssetsOf(user1);

        uint256[] memory withdrawals = new uint256[](1);

        // zero amount == early exit
        withdrawalQueue.transferPendingAssets(user2, 0);
        assertEq(
            totalPending, withdrawalQueue.pendingAssetsOf(user1), "stage 1: pendingAssetsOf(user1)"
        );
        assertEq(0, withdrawalQueue.pendingAssetsOf(user2), "stage 1: pendingAssetsOf(user2)");

        withdrawalQueue.transferPendingAssets(user2, totalPending / 2);
        vm.stopPrank();

        vm.startPrank(user2);
        withdrawals[0] = 0;
        withdrawalQueue.acceptPendingAssets(user2, withdrawals);
        assertApproxEqAbs(
            totalPending / 2, withdrawalQueue.pendingAssetsOf(user2), 3, "user2: pending"
        );
        vm.stopPrank();

        vm.roll(block.number + 10); // skip delay
        vm.startPrank(user1);
        withdrawalQueue.claim(user1, user1, withdrawalQueue.claimableAssetsOf(user1) / 2);

        vm.expectRevert();
        withdrawalQueue.transferPendingAssets(user2, 1000 ether);

        withdrawalQueue.transferPendingAssets(user2, withdrawalQueue.claimableAssetsOf(user1));
        vm.stopPrank();

        vm.startPrank(user2);
        withdrawals[0] = 1;
        withdrawalQueue.acceptPendingAssets(user2, withdrawals);
        assertApproxEqAbs(
            3 * totalPending / 4, withdrawalQueue.claimableAssetsOf(user2), 3, "user2: claimable"
        );
        vm.stopPrank();
    }
}
