// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {StvStETHPool} from "src/StvStETHPool.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {StvStETHPoolHarness} from "test/utils/StvStETHPoolHarness.sol";

/**
 * @title StvStrategyPoolHarness
 * @notice Helper contract for integration tests that provides common setup for StvStETHPool with strategy support
 */
contract StvStrategyPoolHarness is StvStETHPoolHarness {
    IStrategy public strategy;

    function _deployStvStETHPool(
        bool enableAllowlist,
        uint256 nodeOperatorFeeBP,
        uint256 reserveRatioGapBP,
        address _teller,
        address _boringQueue
    ) internal returns (WrapperContext memory) {
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
            strategyKind: StrategyKind.GGV,
            ggvTeller: _teller,
            ggvBoringQueue: _boringQueue,
            timelockMinDelaySeconds: 0,
            timelockExecutor: NODE_OPERATOR,
            name: "Integration Strategy Pool",
            symbol: "iSTRAT"
        });

        WrapperContext memory ctx = _deployWrapperSystem(config);

        strategy = IStrategy(payable(ctx.strategy));

        return ctx;
    }

    function _allPossibleStvHolders(WrapperContext memory ctx) internal view override returns (address[] memory) {
        address[] memory holders_ = super._allPossibleStvHolders(ctx);
        address[] memory holders = new address[](holders_.length + 2);
        uint256 i = 0;
        for (i = 0; i < holders_.length; i++) {
            holders[i] = holders_[i];
        }
        holders[i++] = address(strategy);
        //        holders[i++] = address(strategy.LENDER_MOCK());
        return holders;
    }

    function _checkInitialState(WrapperContext memory ctx) internal virtual override {
        // Call parent checks first
        super._checkInitialState(ctx);

        // StvStETHPool specific: has strategy checks
        if (address(strategy) != address(0)) {
            assertTrue(ctx.pool.isAllowListed(address(strategy)), "Strategy should be added to allowlist");
            // Additional strategy-specific initial state checks can go here
        }
    }

    function _assertUniversalInvariants(string memory _context, WrapperContext memory _ctx) internal virtual override {
        // Call parent invariants
        super._assertUniversalInvariants(_context, _ctx);

        // StvStETHPool specific: strategy-related invariants
        if (address(strategy) != address(0)) {
            // Add strategy-specific invariants here if needed
            // For example, checking strategy positions, health factors, etc.
        }
    }

    // Helper function to access StvStETHPool-specific functionality from context
    function stvStrategyPool(WrapperContext memory ctx) internal pure returns (StvStETHPool) {
        return StvStETHPool(payable(address(ctx.pool)));
    }
}
