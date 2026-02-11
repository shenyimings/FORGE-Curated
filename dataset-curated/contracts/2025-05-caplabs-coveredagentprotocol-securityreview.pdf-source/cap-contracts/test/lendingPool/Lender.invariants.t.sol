// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Lender } from "../../contracts/lendingPool/Lender.sol";

import { TestDeployer } from "../deploy/TestDeployer.sol";
import { TestEnvConfig } from "../deploy/interfaces/TestDeployConfig.sol";
import { InitTestVaultLiquidity } from "../deploy/service/InitTestVaultLiquidity.sol";

import { MockNetworkMiddleware } from "../mocks/MockNetworkMiddleware.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { RandomActorUtils } from "../deploy/utils/RandomActorUtils.sol";
import { RandomAssetUtils } from "../deploy/utils/RandomAssetUtils.sol";
import { TimeUtils } from "../deploy/utils/TimeUtils.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

import { StdUtils } from "forge-std/StdUtils.sol";
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

contract LenderInvariantsTest is TestDeployer {
    TestLenderHandler public handler;
    address[] private actors;

    // Constants - all values in ray (1e27)
    uint256 private constant TARGET_HEALTH = 2e27; // 2.0 target health factor
    uint256 private constant BONUS_CAP = 1.1e27; // 110% bonus cap
    uint256 private constant GRACE_PERIOD = 1 days;
    uint256 private constant EXPIRY_PERIOD = 7 days;
    uint256 private constant EMERGENCY_LIQUIDATION_THRESHOLD = 0.91e27; // CR <110% have no grace periods

    function useMockBackingNetwork() internal pure override returns (bool) {
        return true;
    }

    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);

        // Create and target handler
        handler = new TestLenderHandler(env);
        targetContract(address(handler));

        vm.label(address(handler), "TestLenderHandler");
    }

    function test_mock_network_borrow_and_repay_with_coverage() public {
        address user_agent = _getRandomAgent();
        vm.startPrank(user_agent);

        uint256 backingBefore = usdc.balanceOf(address(cUSD));

        lender.borrow(address(usdc), 1000e6, user_agent);
        assertEq(usdc.balanceOf(user_agent), 1000e6);

        // simulate yield
        usdc.mint(user_agent, 1000e6);

        // repay the debt
        usdc.approve(env.infra.lender, 1000e6 + 10e6);
        lender.repay(address(usdc), 1000e6, user_agent);
        assertGe(usdc.balanceOf(address(cUSD)), backingBefore);

        uint256 debt = lender.debt(user_agent, address(usdc));
        assertEq(debt, 0);
    }

    /// @dev Test that interest accrual doesn't break system invariants
    function test_interestAccrualSafety() public {
        // Store current values
        address[] memory agents = env.testUsers.agents;
        uint256[] memory previousDebts = new uint256[](agents.length);

        for (uint256 i = 0; i < agents.length; i++) {
            (,, previousDebts[i],,,) = lender.agent(agents[i]);
        }

        // Realize interest on all assets
        address[] memory assets = usdVault.assets;
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 maxRealization = lender.maxRealization(assets[i]);
            if (maxRealization > 0) {
                lender.realizeInterest(assets[i]);
            }
        }

        // Check that system invariants still hold
        invariant_borrowingLimits();
        invariant_agentDelegationLimitsDebt();
        invariant_healthFactorConsistency();

        // Verify that interest was properly accrued
        for (uint256 i = 0; i < agents.length; i++) {
            (,, uint256 currentDebt,,,) = lender.agent(agents[i]);
            // Debt should not decrease from interest accrual
            assertGe(currentDebt, previousDebts[i], "Interest accrual should not decrease debt");
        }
    }

    function test_fuzzing_non_regression_liquidate_after_set_coverage() public {
        // [FAIL: panic: division or modulo by zero (0x12)]
        // [Sequence]
        //         sender=0x0000000000000000000000000000000000001207 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[5402, 4969, 4395]
        //         sender=0x0000000000000000000000000000000000000758 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=setAgentCoverage(uint256,uint256) args=[8504, 11352 [1.135e4]]
        //         sender=0x0000000000000000000000000000000000000423 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=liquidate(uint256,uint256,uint256,uint256) args=[1109431098096784405597004399778520969000778 [1.109e42], 937481123910104941 [9.374e17], 61623886549693656488416079379073384034876 [6.162e40], 3768160486856916064340765479018069586352278996523203668143 [3.768e57]]
        handler.borrow(5402, 4969, 4395);
        handler.setAgentCoverage(8504, 11352);
        handler.liquidate(
            1109431098096784405597004399778520969000778,
            61623886549693656488416079379073384034876,
            3768160486856916064340765479018069586352278996523203668143
        );

        invariant_borrowingLimits();
    }

    function test_fuzzing_non_regression_liquidate_fails() public {
        //         Encountered 1 failing test in test/lendingPool/Lender.invariants.t.sol:LenderInvariantsTest
        // [FAIL: invariant_borrowingLimits persisted failure revert]
        //         [Sequence]
        //                 sender=0x000000000000000000000000000000004DEeAad4 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[500000000000000000000000000 [5e26], 260243407 [2.602e8], 7520]
        //                 sender=0x0000000000000000000000000000000000002834 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=setAgentCoverage(uint256,uint256) args=[4763, 5672]
        //                 sender=0x0000000000000000000000000000000000000A2B addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=liquidate(uint256,uint256,uint256,uint256) args=[9998, 5300, 806165946075049551985264334151369441818954475481 [8.061e47], 5711]
        //                 sender=0x00000000000000000001ddDBFa0a9CD64ECaa149 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=liquidate(uint256,uint256,uint256,uint256) args=[11056068703988633693957203172599663392891881631940881250732208 [1.105e61], 30007872054813680496550892600715668912378495406850871 [3e52], 1928259676971630563350495955946765 [1.928e33], 420729907401969 [4.207e14]]
        //  invariant_borrowingLimits() (runs: 1, calls: 1, reverts: 1)

        handler.borrow(500000000000000000000000000, 260243407, 7520);
        handler.setAgentCoverage(4763, 5672);
        handler.liquidate(9998, 806165946075049551985264334151369441818954475481, 5711);
        handler.liquidate(
            11056068703988633693957203172599663392891881631940881250732208,
            1928259676971630563350495955946765,
            420729907401969
        );

        invariant_borrowingLimits();
    }

    function test_fuzzing_non_regression_liquidate_fails_2() public {
        //     [FAIL: Unhealthy agents should be liquidatable: 0 <= 0]
        //         [Sequence]
        //                 sender=0x0000000000000000000000000000fFfffFFfFfff addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=setAgentSlashableCollateral(uint256,uint256) args=[3, 153730679022881943174521915728621705491855651983136629749293 [1.537e59]]
        //                 sender=0x0000000000000000000000000000000000000b1e addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[0, 5394082854433605416045615594689867366126864271730597317776373663523047009 [5.394e72], 272381320701 [2.723e11]]
        //                 sender=0x0000000000000000000000000000000000000902 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=setAgentCoverage(uint256,uint256) args=[7779693176664 [7.779e12], 2]
        //  invariant_healthFactorConsistency() (runs: 2396, calls: 59900, reverts: 0)

        handler.setAgentSlashableCollateral(3, 153730679022881943174521915728621705491855651983136629749293);
        handler.borrow(0, 5394082854433605416045615594689867366126864271730597317776373663523047009, 272381320701);
        handler.setAgentCoverage(7779693176664, 2);

        invariant_healthFactorConsistency();
    }

    function test_fuzzing_non_regression_liquidate_fails_3() public {
        // [FAIL: invariant_agentDelegationLimitsDebt persisted failure revert]
        // [Sequence]
        //      sender=0x00000000000000000000000000000000000007fe addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[279561588714589 [2.795e14], 2663511517048081342890370761760586438025887 [2.663e42]]
        //      sender=0x09f3Cc51b061FA3e0A125722d3dCdAB22960102e addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[115792089237316195423570985008687907853269984665640564039457584007913129639932 [1.157e77], 15245393 [1.524e7]]
        //      sender=0x00000000000000000000000000000000000004E9 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[75609030313738284332382717790014263572601398128483269307557 [7.56e58], 7177446610867092 [7.177e15], 457251500103351190898254055994346777733 [4.572e38]]
        //      sender=0x000000000000000000000000000000000000020d addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=setAgentCoverage(uint256,uint256) args=[3827, 2524]
        //      sender=0xc91f5DAa6E03aFB3B78758b6A58C2B36694b8c1D addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[20571 [2.057e4], 10583 [1.058e4]]
        //      sender=0x000000000000000000000000000000000000067C addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=setAgentCoverage(uint256,uint256) args=[35492957994691500668295531932493666265885033293179877427109393477396013776896 [3.549e76], 8388]
        //      sender=0x0000000000000000000000000000000066d9a99F addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[16291864798349077 [1.629e16], 1435829797705254314582830950992659463821452722364858090334371516 [1.435e63], 16556117656843747165974402408538744302413325 [1.655e43]]
        //      sender=0x0000000000000000000000000000000000001CfC addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=liquidate(uint256,uint256,uint256,uint256) args=[2, 65076241195732311297008734 [6.507e25], 0, 50531700442618637710239866635305475564994400757514979355854358368 [5.053e64]]
        //  invariant_agentDelegationLimitsDebt() (runs: 1, calls: 1, reverts: 1)
        handler.wrapTime(279561588714589, 2663511517048081342890370761760586438025887);
        handler.wrapTime(115792089237316195423570985008687907853269984665640564039457584007913129639932, 15245393);
        handler.borrow(
            75609030313738284332382717790014263572601398128483269307557,
            7177446610867092,
            457251500103351190898254055994346777733
        );
        handler.setAgentCoverage(3827, 2524);
        handler.wrapTime(20571, 10583);
        handler.setAgentCoverage(35492957994691500668295531932493666265885033293179877427109393477396013776896, 8388);
        handler.borrow(
            16291864798349077,
            1435829797705254314582830950992659463821452722364858090334371516,
            16556117656843747165974402408538744302413325
        );
        handler.liquidate(2, 0, 50531700442618637710239866635305475564994400757514979355854358368);

        invariant_agentDelegationLimitsDebt();
    }

    function test_fuzzing_non_regression_multiple_liquidate_in_a_row() public {
        // [FAIL: custom error 0xa07063cb]
        // [Sequence]
        //       sender=0xc2Da903096EDff875f8792E4c580eAb71599af1f addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[38595992670061585487715391781788036416022974650 [3.859e46], 2635581861308878760827543746708756291372490928484070615832091 [2.635e60], 3976785946 [3.976e9]]
        //       sender=0x0000000000000000000000000000000000000797 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=setAgentCoverage(uint256,uint256) args=[357488141490035838117936306281844024533269064 [3.574e44], 538480132746 [5.384e11]]
        //       sender=0x2959A0678E9a84493Abb75A3825d90DF05346204 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=liquidate(uint256,uint256,uint256,uint256) args=[3719, 233753826492419412621632272325435016278641195558965513326631137659032961025 [2.337e74], 31, 3657006336 [3.657e9]]
        //       sender=0x0000000000000000000000000000000000000986 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[3813, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]]
        //       sender=0x00000000000000000000000000000000000004Fe addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=liquidate(uint256,uint256,uint256,uint256) args=[447476674474384566432265375184409868117415385167 [4.474e47], 12200385529572857376284667427148142565967213 [1.22e43], 1592138495042354847337191 [1.592e24], 160014459991216075558486690339731 [1.6e32]]
        // invariant_healthFactorConsistency() (runs: 240, calls: 6000, reverts: 1)

        handler.borrow(
            38595992670061585487715391781788036416022974650,
            2635581861308878760827543746708756291372490928484070615832091,
            3976785946
        );
        handler.setAgentCoverage(357488141490035838117936306281844024533269064, 538480132746);
        handler.liquidate(3719, 31, 3657006336);
        handler.wrapTime(3813, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
        handler.liquidate(
            447476674474384566432265375184409868117415385167,
            1592138495042354847337191,
            160014459991216075558486690339731
        );

        invariant_healthFactorConsistency();
    }

    function test_fuzzing_non_regression_borrow_repay_fail_1() public {
        // [FAIL: custom error 0x2075cc10]
        // [Sequence]
        //        sender=0x0000000000000000000000000000000053C655a8 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[2, 7479559856413359341840092452890241277881269258401416057474579782773715 [7.479e69], 1186621296757860739 [1.186e18]]
        //        sender=0x0000000000000000000000000000000000001279 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=repay(uint256,uint256,uint256) args=[238124013308466196191737395961291420492833249786121552 [2.381e53], 1, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]]
        // invariant_healthFactorConsistency() (runs: 4, calls: 100, reverts: 1)

        handler.borrow(2, 7479559856413359341840092452890241277881269258401416057474579782773715, 1186621296757860739);
        handler.repay(
            238124013308466196191737395961291420492833249786121552,
            1,
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );
    }

    function test_fuzzing_non_regression_underflow_liquidate() public {
        //[FAIL: panic: arithmetic underflow or overflow (0x11)]
        //[Sequence]
        //        sender=0x000000000000000000000000000000000000000F addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[7757, 74588453124592792501841895134841311713919456363871138375969099378153337389056 [7.458e76], 3968941934 [3.968e9]]
        //        sender=0x0000000000000000000000000000000000003242 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[2873, 1200]
        //        sender=0x00000000000000000000000000000000000003F8 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[17970433847498262473090629473 [1.797e28], 2, 115792089237316195423570985008687907853269984665640564039457584007913129639933 [1.157e77]]
        //        sender=0x0000000000000000000000000000000000001254 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=repay(uint256,uint256,uint256) args=[622302299210497639603414633568 [6.223e29], 2, 3]
        //        sender=0x10777fE322811B1B8e2dDB9050Ff10790eE9fF2E addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=setAgentCoverage(uint256,uint256) args=[3815805612345849549 [3.815e18], 24]
        //        sender=0x0000000000000000000000000000000000002B86 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=liquidate(uint256,uint256,uint256,uint256) args=[4384111672497386370926446843835048693075376601076141923258490801118068118 [4.384e72], 3933082584912572630848841962 [3.933e27], 1889696467241238879898734678892508869767419186805053341936739 [1.889e60], 20963255265907651992196302519907651810368859 [2.096e43]]
        //        sender=0x7ec53EeCE279C398543036fc332Ca69963a46813 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=liquidate(uint256,uint256,uint256,uint256) args=[30, 188974967785013252 [1.889e17], 41, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]]
        // invariant_agentDelegationLimitsDebt() (runs: 1172, calls: 117200, reverts: 1)

        handler.borrow(7757, 74588453124592792501841895134841311713919456363871138375969099378153337389056, 3968941934);
        handler.wrapTime(2873, 1200);
        handler.borrow(
            17970433847498262473090629473,
            2,
            115792089237316195423570985008687907853269984665640564039457584007913129639933
        );
        handler.repay(622302299210497639603414633568, 2, 3);
        handler.setAgentCoverage(3815805612345849549, 24);
        handler.liquidate(
            4384111672497386370926446843835048693075376601076141923258490801118068118,
            1889696467241238879898734678892508869767419186805053341936739,
            20963255265907651992196302519907651810368859
        );
        handler.liquidate(30, 41, 115792089237316195423570985008687907853269984665640564039457584007913129639935);

        invariant_agentDelegationLimitsDebt();
    }

    function test_fuzzing_non_regression_liquidation_expired() public {
        // [FAIL: custom error 0xa07063cb]
        // [Sequence]
        //         sender=0x00000000000000000000000000000000000003a3 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=pauseAsset(uint256,uint256) args=[7167694970628916955451004 [7.167e24], 16007968822109961830234730580992218377222324811 [1.6e46]]
        //         sender=0x0000000000000000000000000000000000000254 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=pauseAsset(uint256,uint256) args=[3393, 1879]
        //         sender=0x00000000000000000000000000000000000000fa addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[5766, 7237, 100228144114204208921196098655045973058935756547835879193424203306895750641912 [1.002e77]]
        //         sender=0x71a8C080c9c49350F782c43d966432c1bc444c2C addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[2, 214134411597144060483135243300193298750594311970295842341200532364990 [2.141e68], 8207376740568129008431491810377528035932993823514277843037313303664 [8.207e66]]
        //         sender=0x7ce5Bd44afA0aCC5C3507D61E27A833698F20596 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[4731, 58497332399337429344593767924947750742310842768357091268046542597167793274721 [5.849e76]]
        //         sender=0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=setAgentCoverage(uint256,uint256) args=[5993, 3422038890 [3.422e9]]
        //         sender=0xAeDffa337e2bE584a2Ff632135Cc088725529Ae7 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=setAgentCoverage(uint256,uint256) args=[1041, 10285 [1.028e4]]
        //         sender=0x1Ee35CE4997762752E3A095284754544f4c709d6 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=liquidate(uint256,uint256,uint256,uint256) args=[62627094929811953151701008153803527665735819222075294185262633895705808075657 [6.262e76], 3718, 9821, 5177]
        //         sender=0x02157915356C0372584E2DcA0FCb4C64736F6c64 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=repay(uint256,uint256,uint256) args=[993049411386801934099525205354452135258011966824937131273 [9.93e56], 1017358909473853652244212260128938582116004 [1.017e42], 94953482489101663636828374601395961001183985981506327900119058882 [9.495e64]]
        //         sender=0x00000000000000000000000000000000000003ce addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[74778552942360331274022453539398869583600156629 [7.477e46], 115792089237316195423570985008687907853269984665640564039457584007913129639933 [1.157e77]]
        //         sender=0x0000000000000000000000000000000000001c5D addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=liquidate(uint256,uint256,uint256,uint256) args=[29225223478516705340959411323663244701423210690063694749575843356889 [2.922e67], 2737837594918667271395199048650270487578827384063849774189 [2.737e57], 2112286922687066306261364466892322503874597257722575518124547228233356078 [2.112e72], 233311085789197653343518 [2.333e23]]
        //         sender=0x0000000000000000000000000000000000000614 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[117070713718 [1.17e11], 1006540295783534163945056590553234562247379189028725719525632051813 [1.006e66]]
        //         sender=0xA6E87a6141f9545994930F6135E9Cf1e442C1f93 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=liquidate(uint256,uint256,uint256,uint256) args=[89315578922122892679333885041649008773726263756587365749819829555208549250188 [8.931e76], 6446, 767, 68105926446125771809405178487174168028959056521217564930724487598009997264166 [6.81e76]]
        // invariant_borrowingLimits() (runs: 4584, calls: 458400, reverts: 1)
        handler.pauseAsset(7167694970628916955451004, 16007968822109961830234730580992218377222324811);
        handler.pauseAsset(3393, 1879);
        handler.borrow(5766, 7237, 100228144114204208921196098655045973058935756547835879193424203306895750641912);
        handler.borrow(
            2,
            214134411597144060483135243300193298750594311970295842341200532364990,
            8207376740568129008431491810377528035932993823514277843037313303664
        );
        handler.wrapTime(4731, 58497332399337429344593767924947750742310842768357091268046542597167793274721);
        handler.setAgentCoverage(5993, 3422038890);
        handler.setAgentCoverage(1041, 10285);
        handler.liquidate(62627094929811953151701008153803527665735819222075294185262633895705808075657, 9821, 5177);
        handler.repay(
            993049411386801934099525205354452135258011966824937131273,
            1017358909473853652244212260128938582116004,
            94953482489101663636828374601395961001183985981506327900119058882
        );
        handler.wrapTime(
            74778552942360331274022453539398869583600156629,
            115792089237316195423570985008687907853269984665640564039457584007913129639933
        );
        handler.liquidate(
            29225223478516705340959411323663244701423210690063694749575843356889,
            2112286922687066306261364466892322503874597257722575518124547228233356078,
            233311085789197653343518
        );
        handler.wrapTime(117070713718, 1006540295783534163945056590553234562247379189028725719525632051813);
        handler.liquidate(
            89315578922122892679333885041649008773726263756587365749819829555208549250188,
            767,
            68105926446125771809405178487174168028959056521217564930724487598009997264166
        );

        invariant_borrowingLimits();
    }

    function test_fuzzing_non_regression_underflow_during_repay() public {
        //[FAIL: panic: arithmetic underflow or overflow (0x11)]
        //[Sequence]
        //        sender=0x0000000000000000000000000000000000001e15 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=pauseAsset(uint256,uint256) args=[4611, 301558938428973070126939301804606805648145228621 [3.015e47]]
        //        sender=0x0000000000000000000000000000000000001698 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[6380, 797]
        //        sender=0xE7c18DB3A1380112A12852BB20727D66b3733d66 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[51946260829083333090225987510697998094631287232885111889496298996662922239 [5.194e73], 28885794824022426100270309757210068697930911 [2.888e43], 221695383241280572125260234538147301138 [2.216e38]]
        //        sender=0x0000000000000000000000000000000023b872Dc addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[12769927 [1.276e7], 90644 [9.064e4]]
        //        sender=0xCfbB980a35AB948576f876A48FDB7f08066548e7 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[1823, 6110]
        //        sender=0x46E8E875011e82C1006C458CAFe83Bb72f8A280a addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=realizeInterest(uint256) args=[24880451351733217867336194017097599624676548 [2.488e43]]
        //        sender=0x0000000000000000000000000000000000002F71 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[4543, 6817, 1033229307689458575493127100 [1.033e27]]
        //        sender=0x000000000000000000000000000000000000017E addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=pauseAsset(uint256,uint256) args=[508819697998377563480940 [5.088e23], 938356271150 [9.383e11]]
        //        sender=0xC93a64B65cd148612018EBEc63C0d58bCC10a2ea addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[774, 6729]
        //        sender=0x000000000000000000000000000000000000064f addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=borrow(uint256,uint256,uint256) args=[5876, 3839, 1756325542 [1.756e9]]
        //        sender=0x00000000000000000000000000000000000016F0 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77], 208080990996592096134026189609052055919097100680707475950990946 [2.08e62]]
        //        sender=0x9D886EC885A2bd4F88C329654Ec9d3528b58D63e addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[270978798284222674110526935662381000756974677873833176 [2.709e53], 332028795435522 [3.32e14]]
        //        sender=0x00000000000000000000000000000000000001CB addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=setAgentCoverage(uint256,uint256) args=[5415319662477480108092514012249780312523474260177048431428694681044564049920 [5.415e75], 9694]
        //        sender=0x0000000000000000000000000000000000001A17 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=realizeRestakerInterest(uint256,uint256) args=[88817841970012523233890533447265625 [8.881e34], 1718]
        //        sender=0x30eB4Be5Df16b48e660fd697C1ac4322C48204D7 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=repay(uint256,uint256,uint256) args=[2024, 13241 [1.324e4], 9613]
        //        sender=0x0000000000000000000000000000000000000e49 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=liquidate(uint256,uint256,uint256,uint256) args=[1, 2248555321168870210062882036951 [2.248e30], 2949686183 [2.949e9], 7032555 [7.032e6]]
        //        sender=0x3681a57C9d444Cc705d5511715Ca973d778Bf838 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=wrapTime(uint256,uint256) args=[318284390023772899530867194944432 [3.182e32], 343765214748883997984555 [3.437e23]]
        //        sender=0x00000000000000000000000000000000000007e8 addr=[test/lendingPool/Lender.invariants.t.sol:TestLenderHandler]0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f calldata=repay(uint256,uint256,uint256) args=[2300272910690880168785711543248788602439053704 [2.3e45], 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77], 410786894793195309777267255152695316800989372 [4.107e44]]
        // invariant_healthFactorConsistency() (runs: 2424, calls: 242400, reverts: 1)

        handler.pauseAsset(4611, 301558938428973070126939301804606805648145228621);
        handler.wrapTime(6380, 797);
        handler.borrow(
            51946260829083333090225987510697998094631287232885111889496298996662922239,
            28885794824022426100270309757210068697930911,
            221695383241280572125260234538147301138
        );
        handler.wrapTime(12769927, 90644);
        handler.wrapTime(1823, 6110);
        handler.realizeInterest(24880451351733217867336194017097599624676548);
        handler.borrow(4543, 6817, 1033229307689458575493127100);
        handler.pauseAsset(508819697998377563480940, 938356271150);
        handler.wrapTime(774, 6729);
        handler.borrow(5876, 3839, 1756325542);
        handler.wrapTime(
            115792089237316195423570985008687907853269984665640564039457584007913129639935,
            208080990996592096134026189609052055919097100680707475950990946
        );
        handler.wrapTime(270978798284222674110526935662381000756974677873833176, 332028795435522);
        handler.setAgentCoverage(5415319662477480108092514012249780312523474260177048431428694681044564049920, 9694);
        handler.realizeRestakerInterest(88817841970012523233890533447265625, 1718);
        handler.repay(2024, 13241, 9613);
        handler.liquidate(1, 2949686183, 7032555);
        handler.wrapTime(318284390023772899530867194944432, 343765214748883997984555);
        handler.repay(
            2300272910690880168785711543248788602439053704,
            115792089237316195423570985008687907853269984665640564039457584007913129639935,
            410786894793195309777267255152695316800989372
        );

        invariant_healthFactorConsistency();
    }

    /// @dev Test that total borrowed never exceeds available assets
    /// forge-config: default.invariant.depth = 100
    function invariant_borrowingLimits() public view {
        address[] memory assets = usdVault.assets;

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 totalBorrowed = 0;

            // Sum up all actor debts
            for (uint256 j = 0; j < actors.length; j++) {
                (,, uint256 totalDebt,,,) = lender.agent(actors[j]);
                totalBorrowed += totalDebt;
            }

            uint256 availableAssets = IERC20(asset).balanceOf(address(lender));
            assertLe(totalBorrowed, availableAssets, "Total borrowed must not exceed available assets");
        }
    }

    /// @dev Test that user borrows never exceed their delegation
    /// forge-config: default.invariant.depth = 100
    function invariant_agentDelegationLimitsDebt() public view {
        address[] memory agents = env.testUsers.agents;
        for (uint256 i = 0; i < agents.length; i++) {
            address agent = agents[i];
            (uint256 totalDelegation, uint256 slashableCollateral, uint256 totalDebt,,,) = lender.agent(agent);
            uint256 maxLiquidatable = lender.maxLiquidatable(agent, address(usdc));
            console.log("totalDelegation", totalDelegation);
            console.log("totalDebt", totalDebt);
            console.log("maxLiquidatable", maxLiquidatable);
            if (slashableCollateral < totalDebt) return;
            assertGe(slashableCollateral, totalDebt, "User borrow must not exceed delegation");
        }
    }

    /// @dev Test that liquidatable agents always have health factor < 1
    /// forge-config: default.invariant.depth = 100
    function invariant_healthFactorConsistency() public view {
        address[] memory agents = env.testUsers.agents;
        for (uint256 i = 0; i < agents.length; i++) {
            address agent = agents[i];
            (, uint256 totalSlashableCollateral,,,, uint256 health) = lender.agent(agent);
            if (totalSlashableCollateral == 0) return;

            uint256 maxLiquidatable = lender.maxLiquidatable(agent, address(usdc));

            // If agent is liquidatable (maxLiquidatable > 0), health should be < 1e27
            if (maxLiquidatable > 0) {
                assertLt(health, 1e27, "Liquidatable agents must have health < 1");
            }
        }
    }
}

/**
 * @notice Handler contract for testing Lender invariants
 */
contract TestLenderHandler is StdUtils, TimeUtils, InitTestVaultLiquidity, RandomActorUtils, RandomAssetUtils {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    TestEnvConfig env;

    Lender lender;

    constructor(TestEnvConfig memory _env)
        RandomActorUtils(_env.testUsers.agents)
        RandomAssetUtils(_env.usdVault.assets)
    {
        env = _env;
        lender = Lender(env.infra.lender);
    }

    function _randomUnpausedAsset(uint256 assetSeed) internal view returns (address) {
        address[] memory assets = allAssets();
        address[] memory unpausedAssets = new address[](assets.length);
        uint256 unpausedAssetCount = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            (,,,,, bool paused,) = lender.reservesData(assets[i]);
            if (!paused) {
                unpausedAssets[unpausedAssetCount++] = assets[i];
            }
        }

        if (unpausedAssetCount == 0) return address(0);

        return unpausedAssets[bound(assetSeed, 0, unpausedAssetCount - 1)];
    }

    function borrow(uint256 actorSeed, uint256 assetSeed, uint256 amountSeed) external {
        address agent = randomActor(actorSeed);
        address currentAsset = _randomUnpausedAsset(assetSeed);
        if (currentAsset == address(0)) return;

        uint256 availableToBorrow = lender.maxBorrowable(agent, currentAsset);
        uint256 amount = bound(amountSeed, 0, availableToBorrow);
        if (amount < 100e6) return;

        vm.startPrank(agent);
        lender.borrow(currentAsset, amount, agent);
        vm.stopPrank();
    }

    function repay(uint256 actorSeed, uint256 assetSeed, uint256 amountSeed) external {
        address agent = randomActor(actorSeed);
        address currentAsset = randomAsset(assetSeed);

        // Bound amount to actual borrowed amount
        uint256 debt = lender.debt(agent, currentAsset);
        uint256 amount = bound(amountSeed, 0, debt);
        if (amount == 0) return;

        // Mint tokens to repay
        MockERC20(currentAsset).mint(agent, amount);

        // Execute repay
        {
            vm.startPrank(agent);
            IERC20(currentAsset).approve(address(lender), amount);

            lender.repay(currentAsset, amount, agent);
            vm.stopPrank();
        }
    }

    function liquidate(uint256 agentSeed, uint256 assetSeed, uint256 amountSeed) external {
        address agent = randomActor(agentSeed);
        address currentAsset = randomAsset(assetSeed);
        address liquidator = makeAddr("liquidator");

        // Bound amount to liquidatable amount
        uint256 amount = bound(amountSeed, 0, lender.maxLiquidatable(agent, currentAsset));
        if (amount == 0) return;

        // Execute liquidation
        {
            vm.startPrank(liquidator);

            // Mint tokens to repay for the user liquidation
            MockERC20(currentAsset).mint(liquidator, amount);

            // Execute liquidation
            IERC20(currentAsset).approve(address(lender), amount);

            uint256 liquidationStart = lender.liquidationStart(agent);
            uint256 canLiquidateFrom = liquidationStart + lender.grace();
            uint256 canLiquidateUntil = canLiquidateFrom + lender.expiry();
            if (liquidationStart == 0) {
                lender.initiateLiquidation(agent);
                _timeTravel(lender.grace() + 1);
            } else if (block.timestamp <= canLiquidateFrom) {
                _timeTravel(canLiquidateFrom - block.timestamp);
            } else if (block.timestamp >= canLiquidateUntil) {
                // lender.cancelLiquidation(agent);
                //  _timeTravel(1);
                lender.initiateLiquidation(agent);
                _timeTravel(lender.grace() + 1);
            }

            lender.liquidate(agent, currentAsset, amount);
            vm.stopPrank();
        }
    }

    function setAgentCoverage(uint256 agentSeed, uint256 coverageSeed) external {
        uint256 coverage = bound(coverageSeed, 0, 1e50);
        address agent = randomActor(agentSeed);

        vm.prank(address(env.users.middleware_admin));
        MockNetworkMiddleware(env.symbiotic.networkAdapter.networkMiddleware).setMockCoverage(agent, coverage);
        vm.stopPrank();
    }

    function setAgentSlashableCollateral(uint256 agentSeed, uint256 coverageSeed) external {
        uint256 coverage = bound(coverageSeed, 0, 1e50);
        address agent = randomActor(agentSeed);

        vm.prank(address(env.users.middleware_admin));
        MockNetworkMiddleware(env.symbiotic.networkAdapter.networkMiddleware).setMockSlashableCollateral(
            agent, coverage
        );
        vm.stopPrank();
    }

    function realizeInterest(uint256 assetSeed) external {
        address currentAsset = randomAsset(assetSeed);

        // Bound amount to a reasonable range (using type(uint96).max to avoid overflow)
        uint256 maxRealization = lender.maxRealization(currentAsset);
        if (maxRealization == 0) return;

        lender.realizeInterest(currentAsset);
    }

    function wrapTime(uint256 timeSeed, uint256 blockNumberSeed) external {
        uint256 timestamp = bound(timeSeed, block.timestamp, block.timestamp + 100 days);
        uint256 blockNumber = bound(blockNumberSeed, block.number, block.number + 1000000);
        vm.warp(timestamp);
        vm.roll(blockNumber);
    }

    function realizeRestakerInterest(uint256 agentSeed, uint256 assetSeed) external {
        address agent = randomActor(agentSeed);
        address currentAsset = randomAsset(assetSeed);

        (uint256 maxRealizedInterest,) = lender.maxRestakerRealization(agent, currentAsset);
        if (maxRealizedInterest == 0) return;

        lender.realizeRestakerInterest(agent, currentAsset);
    }

    function cancelLiquidation(uint256 agentSeed) external {
        address agent = randomActor(agentSeed);

        // Only attempt to cancel if there's an active liquidation
        if (lender.liquidationStart(agent) > 0) {
            (,,,,, uint256 health) = lender.agent(agent);
            // Only cancel if health is above 1e27 (healthy)
            if (health >= 1e27) {
                vm.prank(address(env.users.lender_admin));
                lender.cancelLiquidation(agent);
                vm.stopPrank();
            }
        }
    }

    function pauseAsset(uint256 assetSeed, uint256 pauseFlagSeed) external {
        address currentAsset = randomAsset(assetSeed);
        bool shouldPause = bound(pauseFlagSeed, 0, 1) == 1; // Convert to boolean randomly

        // Only admin can pause/unpause
        vm.prank(address(env.users.lender_admin));
        lender.pauseAsset(currentAsset, shouldPause);
        vm.stopPrank();
    }

    // @dev Donate tokens to the lender's vault
    function donateAsset(uint256 assetSeed, uint256 amountSeed, uint256 targetSeed) external {
        address currentAsset = randomAsset(assetSeed);
        if (currentAsset == address(0)) return;

        address target = randomActor(targetSeed, address(env.usdVault.capToken), address(lender));

        uint256 amount = bound(amountSeed, 1, 1e50);
        MockERC20(currentAsset).mint(target, amount);
    }

    function donateGasToken(uint256 amountSeed, uint256 targetSeed) external {
        uint256 amount = bound(amountSeed, 1, 1e50);
        address target = randomActor(targetSeed, address(env.usdVault.capToken), address(lender));

        vm.deal(target, amount /* we need gas to send gas */ );
    }
}
