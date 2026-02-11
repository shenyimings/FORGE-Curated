// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvPool} from "./SetupStvPool.sol";
import {Test} from "forge-std/Test.sol";
import {StvPool} from "src/StvPool.sol";

contract BadDebtTest is Test, SetupStvPool {
    function _simulateBadDebt() internal {
        // Create bad debt
        dashboard.mock_increaseLiability(steth.getSharesByPooledEth(pool.totalAssets()) + 1);

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

    function test_BadDebt_TransfersNotAllowed() public {
        _simulateBadDebt();

        vm.expectRevert(StvPool.VaultInBadDebt.selector);
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        pool.transfer(address(1), 1 ether);
    }

    function test_BadDebt_DepositsNotAllowed() public {
        _simulateBadDebt();

        vm.expectRevert(StvPool.VaultInBadDebt.selector);
        pool.depositETH{value: 1 ether}(address(this), address(0));
    }
}
