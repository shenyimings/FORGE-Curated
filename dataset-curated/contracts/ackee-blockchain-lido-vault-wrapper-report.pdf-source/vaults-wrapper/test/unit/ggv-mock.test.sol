// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {GGVMockTeller} from "src/mock/ggv/GGVMockTeller.sol";
import {GGVQueueMock} from "src/mock/ggv/GGVQueueMock.sol";
import {GGVVaultMock} from "src/mock/ggv/GGVVaultMock.sol";
import {MockStETH} from "test/mocks/MockStETH.sol";
import {MockWstETH} from "test/mocks/MockWstETH.sol";

contract GGVMockTest is Test {
    using SafeCast for uint256;

    GGVVaultMock public vault;
    GGVMockTeller public teller;
    GGVQueueMock public queue;
    MockStETH public steth;
    MockWstETH public wsteth;

    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public admin = address(0x3);

    uint256 public constant INITIAL_BALANCE = 100 ether;

    function setUp() public {
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        vm.deal(admin, INITIAL_BALANCE);

        steth = new MockStETH();
        wsteth = new MockWstETH(address(steth));
        // give admin 10 steth for ggv rebase
        vm.prank(admin);
        steth.submit{value: 10 ether}(admin);

        vault = new GGVVaultMock(admin, address(steth), address(wsteth));
        teller = GGVMockTeller(address(vault.TELLER()));
        queue = GGVQueueMock(address(vault.BORING_QUEUE()));

        // approve admin's steth for ggv rebase
        vm.prank(admin);
        steth.approve(address(vault), type(uint256).max);
    }

    function test_depositToGGV() public {
        vm.startPrank(user1);
        uint256 userStethShares = steth.submit{value: 1 ether}(address(0));
        assertEq(userStethShares, steth.sharesOf(user1));
        assertEq(steth.balanceOf(user1), 1 ether);

        steth.approve(address(vault), type(uint256).max);
        uint256 ggvShares = teller.deposit(steth, 1 ether, 0, address(0));
        assertEq(ggvShares, vault.balanceOf(user1));
        uint256 ggvUserAssets = vault.getAssetsByShares(ggvShares);
        vm.stopPrank();

        vm.startPrank(admin);
        // add 1 steth to ggv balance for rebase
        vault.rebaseSteth(1 ether);
        uint256 newGgvUserAssets = vault.getAssetsByShares(ggvShares);
        assertEq(newGgvUserAssets > ggvUserAssets, true);
    }

    function test_withdrawFromGGV() public {
        // USER
        vm.startPrank(user1);
        // get steth
        steth.submit{value: 1 ether}(address(0));
        steth.approve(address(vault), type(uint256).max);
        // deposit to ggv
        uint256 userGgvShares = teller.deposit(steth, 1 ether, 0, address(0));
        uint256 userStethSharesAfterDeposit = steth.sharesOf(user1);

        // withdraw from ggv
        GGVQueueMock.WithdrawAsset memory wa = queue.withdrawAssets(address(steth));
        uint256 previewAmountAssetsStethShares =
            queue.previewAssetsOut(address(steth), userGgvShares.toUint128(), wa.minDiscount);

        vault.approve(address(queue), userGgvShares);
        bytes32 requestId =
            queue.requestOnChainWithdraw(address(steth), userGgvShares.toUint128(), wa.minDiscount, type(uint24).max);
        GGVQueueMock.OnChainWithdraw memory req = queue.mockGetRequestById(requestId);

        GGVQueueMock.OnChainWithdraw[] memory requests = new GGVQueueMock.OnChainWithdraw[](1);
        requests[0] = req;
        // ADMIN SOLVER
        vm.startPrank(admin);
        queue.solveOnChainWithdraws(requests, new bytes(0), address(0));
        uint256 userStethSharesAfterWithdrawSolve = steth.sharesOf(user1);

        // user receives steth shares
        assertEq(userStethSharesAfterWithdrawSolve - userStethSharesAfterDeposit, previewAmountAssetsStethShares);
    }
}
