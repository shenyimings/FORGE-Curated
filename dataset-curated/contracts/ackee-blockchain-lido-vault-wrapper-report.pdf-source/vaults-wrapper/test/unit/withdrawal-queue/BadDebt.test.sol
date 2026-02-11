// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupWithdrawalQueue} from "./SetupWithdrawalQueue.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Test} from "forge-std/Test.sol";
import {StvPool} from "src/StvPool.sol";

contract BadDebtTest is Test, SetupWithdrawalQueue {
    using SafeCast for uint256;

    function setUp() public virtual override {
        super.setUp();

        // Deposit some ETH and mint max stETH shares for the test contract
        pool.depositETH{value: 10 ether}(address(this), address(0));
        pool.mintStethShares(pool.remainingMintingCapacitySharesOf(address(this), 0));

        // Deposit some ETH and mint max stETH shares for Alice
        vm.startPrank(userAlice);
        pool.depositETH{value: 10 ether}(userAlice, address(0));
        pool.mintStethShares(pool.remainingMintingCapacitySharesOf(userAlice, 0));
        vm.stopPrank();
    }

    function _simulateBadDebt() internal {
        // Simulate negative rewards to create bad debt
        uint256 totalAssets = vaultHub.totalValue(address(pool.VAULT()));
        uint256 liabilitySteth = steth.getPooledEthBySharesRoundUp(pool.totalLiabilityShares());
        uint256 value = totalAssets - liabilitySteth;

        dashboard.mock_simulateRewards(-(value).toInt256() - 10 wei);

        _assertBadDebt();
    }

    function _getValueAndLiabilityShares() internal view returns (uint256 valueShares, uint256 liabilityShares) {
        valueShares = steth.getSharesByPooledEth(vaultHub.totalValue(address(pool.VAULT())));
        liabilityShares = pool.totalLiabilityShares();
    }

    function _assertBadDebt() internal view {
        (uint256 valueShares, uint256 liabilityShares) = _getValueAndLiabilityShares();
        assertLt(valueShares, liabilityShares);
    }

    function _assertNoBadDebt() internal view {
        (uint256 valueShares, uint256 liabilityShares) = _getValueAndLiabilityShares();
        assertGe(valueShares, liabilityShares);
    }

    // Initial state tests

    function test_InitialState_NoBadDebt() public view {
        _assertNoBadDebt();
    }

    // Bad debt tests

    function test_BadDebt_RevertInRequestWithdrawals() public {
        _simulateBadDebt();

        uint256 balance = pool.balanceOf(address(this));
        assertGt(balance, 0);

        vm.expectRevert(StvPool.VaultInBadDebt.selector);
        withdrawalQueue.requestWithdrawal(address(pool), balance, 0);
    }

    function test_BadDebt_RevertOnFinalization() public {
        uint256 balance = pool.balanceOf(address(this));
        uint256 liabilityShares = pool.mintedStethSharesOf(address(this));
        assertGt(balance, 0);

        withdrawalQueue.requestWithdrawal(address(pool), balance, liabilityShares);

        _simulateBadDebt();
        _warpAndMockOracleReport();

        vm.prank(finalizeRoleHolder);
        vm.expectRevert(StvPool.VaultInBadDebt.selector);
        withdrawalQueue.finalize(1, address(0));
    }
}
