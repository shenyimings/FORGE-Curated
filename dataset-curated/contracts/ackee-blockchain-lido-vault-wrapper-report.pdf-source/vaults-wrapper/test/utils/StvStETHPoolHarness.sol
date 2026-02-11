// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {StvStETHPool} from "src/StvStETHPool.sol";
import {StvPoolHarness} from "test/utils/StvPoolHarness.sol";

/**
 * @title StvStETHPoolHarness
 * @notice Helper contract for integration tests that provides common setup for StvStETHPool (minting, no strategy)
 */
contract StvStETHPoolHarness is StvPoolHarness {
    function _deployStvStETHPool(bool enableAllowlist, uint256 nodeOperatorFeeBP, uint256 reserveRatioGapBP)
        internal
        returns (WrapperContext memory)
    {
        DeploymentConfig memory config = DeploymentConfig({
            allowListEnabled: enableAllowlist,
            mintingEnabled: true,
            owner: NODE_OPERATOR,
            nodeOperator: NODE_OPERATOR,
            nodeOperatorManager: NODE_OPERATOR,
            nodeOperatorFeeBP: nodeOperatorFeeBP,
            confirmExpiry: CONFIRM_EXPIRY,
            minWithdrawalDelayTime: 1 days,
            reserveRatioGapBP: reserveRatioGapBP,
            strategyKind: StrategyKind.NONE,
            ggvTeller: address(0),
            ggvBoringQueue: address(0),
            timelockMinDelaySeconds: 0,
            timelockExecutor: NODE_OPERATOR,
            name: "Test stETH Pool",
            symbol: "tSTETH"
        });

        WrapperContext memory context = _deployWrapperSystem(config);

        return context;
    }

    function _checkInitialState(WrapperContext memory ctx) internal virtual override {
        // Call parent checks first
        super._checkInitialState(ctx);

        // StvStETHPool specific: has minting capacity
        // Note: Cannot check mintableStShares for users with no deposits as it would cause underflow
        // Minting capacity checks are performed in individual tests after deposits are made
        assertEq(ctx.dashboard.totalMintingCapacityShares(), 0, "Total minting capacity should be equal to 0");
        assertEq(ctx.dashboard.remainingMintingCapacityShares(0), 0, "Remaining minting capacity should be equal to 0");
    }

    function _assertUniversalInvariants(string memory _context, WrapperContext memory _ctx) internal virtual override {
        // Call parent invariants
        super._assertUniversalInvariants(_context, _ctx);

        // TODO: check minting capacity of pool which owns connect deposit stv shares

        address[] memory holders = _allPossibleStvHolders(_ctx);

        {
            // Check none can mint beyond mintable capacity
            for (uint256 i = 0; i < holders.length; i++) {
                address holder = holders[i];
                uint256 mintableStShares = stvStETHPool(_ctx).remainingMintingCapacitySharesOf(holder, 0);

                vm.startPrank(holder);
                vm.expectRevert(StvStETHPool.InsufficientMintingCapacity.selector);
                stvStETHPool(_ctx).mintStethShares(mintableStShares + 1);
                vm.stopPrank();
            }
        }
    }

    // Helper function to access StvStETHPool-specific functionality from context
    function stvStETHPool(WrapperContext memory ctx) internal pure returns (StvStETHPool) {
        return StvStETHPool(payable(address(ctx.pool)));
    }

    /**
     * @notice Calculate max mintable stETH shares for a given ETH amount
     * @dev Uses poolReserveRatioBP from StvStETHPool which includes the pool gap
     */
    function _calcMaxMintableStShares(WrapperContext memory ctx, uint256 _eth) public view returns (uint256) {
        uint256 wrapperRrBp = stvStETHPool(ctx).poolReserveRatioBP();
        return steth.getSharesByPooledEth(_eth * (TOTAL_BASIS_POINTS - wrapperRrBp) / TOTAL_BASIS_POINTS);
    }
}
