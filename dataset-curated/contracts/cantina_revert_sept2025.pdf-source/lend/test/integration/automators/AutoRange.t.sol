// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./AerodromeAutomatorTestBase.sol";

import "../../../src/transformers/AutoRange.sol";

import "v3-periphery/libraries/LiquidityAmounts.sol";
import "v3-core/interfaces/IUniswapV3Pool.sol";

import "../../../src/utils/Constants.sol";

// Updated to use Aerodrome on Base
contract AutoRangeTest is AerodromeAutomatorTestBase {
    AutoRange autoRange;

    function setUp() external {
        _setupBase();
        autoRange = new AutoRange(NPM, OPERATOR_ACCOUNT, WITHDRAWER_ACCOUNT, 60, 100, EX0x, UNIVERSAL_ROUTER);
    }

    function testSetTWAPSeconds() external {
        uint16 maxTWAPTickDifference = autoRange.maxTWAPTickDifference();
        autoRange.setTWAPConfig(maxTWAPTickDifference, 120);
        assertEq(autoRange.TWAPSeconds(), 120);

        vm.expectRevert(Constants.InvalidConfig.selector);
        autoRange.setTWAPConfig(maxTWAPTickDifference, 30);
    }

    function testSetMaxTWAPTickDifference() external {
        uint32 TWAPSeconds = autoRange.TWAPSeconds();
        autoRange.setTWAPConfig(5, TWAPSeconds);
        assertEq(autoRange.maxTWAPTickDifference(), 5);

        vm.expectRevert(Constants.InvalidConfig.selector);
        autoRange.setTWAPConfig(600, TWAPSeconds);
    }

    function testSetOperator() external {
        assertEq(autoRange.operators(TEST_NFT_ACCOUNT), false);
        autoRange.setOperator(TEST_NFT_ACCOUNT, true);
        assertEq(autoRange.operators(TEST_NFT_ACCOUNT), true);
    }

    function testUnauthorizedSetConfig() external {
        vm.expectRevert(Constants.Unauthorized.selector);
        vm.prank(TEST_NFT_ACCOUNT);
        autoRange.configToken(TEST_NFT_2, address(0), AutoRange.PositionConfig(0, 0, 0, 1, 0, 0, false, false, MAX_REWARD));
    }

    function testResetConfig() external {
        vm.prank(TEST_NFT_ACCOUNT);
        autoRange.configToken(TEST_NFT, address(0), AutoRange.PositionConfig(0, 0, 0, 0, 0, 0, false, false, MAX_REWARD));
    }

    function testInvalidConfig() external {
        vm.expectRevert(Constants.InvalidConfig.selector);
        vm.prank(TEST_NFT_ACCOUNT);
        autoRange.configToken(TEST_NFT, address(0), AutoRange.PositionConfig(0, 0, 1, 0, 0, 0, false, false, MAX_REWARD));
    }

    function testValidSetConfig() external {
        vm.prank(TEST_NFT_ACCOUNT);
        AutoRange.PositionConfig memory configIn = AutoRange.PositionConfig(1, -1, 0, 1, 123, 456, false, false, MAX_REWARD);
        autoRange.configToken(TEST_NFT, address(0), configIn);
        (int32 i1, int32 i2, int32 i3, int32 i4, uint64 i5, uint64 i6, bool i7, bool i8, uint64 i9) =
            autoRange.positionConfigs(TEST_NFT);
        assertEq(abi.encode(configIn), abi.encode(AutoRange.PositionConfig(i1, i2, i3, i4, i5, i6, i7, i8, i9)));
    }

    function testNonOperator() external {
        vm.expectRevert(Constants.Unauthorized.selector);
        vm.prank(TEST_NFT_ACCOUNT);
        autoRange.execute(AutoRange.ExecuteParams(TEST_NFT, false, 0, "", 0, 0, 0, 0, block.timestamp, MAX_REWARD));
    }

    function testAdjustWithoutApprove() external {
        // out of range position
        vm.prank(TEST_NFT_2_ACCOUNT);
        autoRange.configToken(TEST_NFT_2, address(0), AutoRange.PositionConfig(0, 0, 0, 1, 0, 0, false, false, MAX_REWARD));

        // fails when sending NFT
        vm.expectRevert(abi.encodePacked("Not approved"));

        vm.prank(OPERATOR_ACCOUNT);
        autoRange.execute(
            AutoRange.ExecuteParams(TEST_NFT_2, false, 0, "", 0, 0, 0, 0, block.timestamp, MAX_REWARD)
        );
    }

    function testAdjustWithoutConfig() external {
        vm.prank(TEST_NFT_ACCOUNT);
        NPM.setApprovalForAll(address(autoRange), true);

        vm.expectRevert(Constants.NotConfigured.selector);
        vm.prank(OPERATOR_ACCOUNT);
        autoRange.execute(AutoRange.ExecuteParams(TEST_NFT, false, 0, "", 0, 0, 0, 0, block.timestamp, MAX_REWARD));
    }

    function testAdjustNotAdjustable() external {
        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.setApprovalForAll(address(autoRange), true);

        vm.prank(TEST_NFT_2_ACCOUNT);
        autoRange.configToken(
            TEST_NFT_2_A,
            address(0),
            AutoRange.PositionConfig(0, 0, 0, 60, uint64(Q64 / 100), uint64(Q64 / 100), false, false, MAX_REWARD)
        ); // 1% max fee, 1% max slippage

        // in range position cant be adjusted
        vm.expectRevert(Constants.NotReady.selector);
        vm.prank(OPERATOR_ACCOUNT);
        autoRange.execute(
            AutoRange.ExecuteParams(TEST_NFT_2_A, false, 0, "", 0, 0, 0, 0, block.timestamp, MAX_REWARD)
        );
    }

    function testAdjustOutOfRange() external {
        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.setApprovalForAll(address(autoRange), true);

        vm.prank(TEST_NFT_2_ACCOUNT);
        autoRange.configToken(
            TEST_NFT_2,
            address(0),
            AutoRange.PositionConfig(
                0, 0, -int32(uint32(type(uint24).max)), int32(uint32(type(uint24).max)), 0, 0, false, false, MAX_REWARD
            )
        ); // 1% max fee, 1% max slippage

        // will be reverted because range Arithmetic over/underflow
        vm.expectRevert(abi.encodePacked("SafeCast: value doesn't fit in 24 bits"));
        vm.prank(OPERATOR_ACCOUNT);
        autoRange.execute(
            AutoRange.ExecuteParams(TEST_NFT_2, false, 0, "", 0, 0, 0, 0, block.timestamp, MAX_REWARD)
        );
    }

    struct SwapTestState {
        uint256 protocolDAIBalanceBefore;
        uint256 protocolWETHBalanceBefore;
        uint256 ownerDAIBalanceBefore;
        uint256 ownerWETHBalanceBefore;
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        address token0;
        address token1;
        uint24 fee;
        uint128 liquidityOld;
    }

    function testAdjustWithoutSwap(bool onlyFees) external {
        // using out of range position TEST_NFT_2
        // available amounts -> 311677619940061890346 506903060556612041
        // added to new position -> 778675263877745419944 196199406163820963

        SwapTestState memory state;

        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.setApprovalForAll(address(autoRange), true);

        vm.prank(TEST_NFT_2_ACCOUNT);
        autoRange.configToken(
            TEST_NFT_2,
            address(0),
            AutoRange.PositionConfig(
                0, 0, 0, 60, uint64(Q64 / 100), uint64(Q64 / 100), onlyFees, false, onlyFees ? MAX_FEE_REWARD : MAX_REWARD
            )
        ); // 1% max fee, 1% max slippage
        uint256 count = NPM.balanceOf(TEST_NFT_2_ACCOUNT);
        assertEq(count, 4);

        state.protocolDAIBalanceBefore = DAI.balanceOf(address(autoRange));
        state.protocolWETHBalanceBefore = WETH_ERC20.balanceOf(address(autoRange));

        state.ownerDAIBalanceBefore = DAI.balanceOf(TEST_NFT_2_ACCOUNT);
        state.ownerWETHBalanceBefore = TEST_NFT_2_ACCOUNT.balance;

        (,,,,,,, state.liquidity,,,,) = NPM.positions(TEST_NFT_2);

        // test max withdraw slippage
        vm.prank(OPERATOR_ACCOUNT);
        vm.expectRevert("Price slippage check");
        autoRange.execute(
            AutoRange.ExecuteParams(
                TEST_NFT_2,
                false,
                0,
                "",
                type(uint256).max,
                type(uint256).max,
                0, 0, 
                block.timestamp,
                MAX_REWARD
            )
        );

        vm.prank(OPERATOR_ACCOUNT);
        autoRange.execute(
            AutoRange.ExecuteParams(
                TEST_NFT_2, false, 0, "", 0, 0, 0, 0, block.timestamp, onlyFees ? MAX_FEE_REWARD : MAX_REWARD
            )
        ); // max fee with 1% is 7124618988448545

        // is not adjustable yet because config was removed
        (,,,,,,, state.liquidity,,,,) = NPM.positions(TEST_NFT_2);
        vm.prank(OPERATOR_ACCOUNT);
        vm.expectRevert(Constants.NotConfigured.selector);
        autoRange.execute(
            AutoRange.ExecuteParams(
                TEST_NFT_2, false, 0, "", 0, 0, 0, 0, block.timestamp, onlyFees ? MAX_FEE_REWARD : MAX_REWARD
            )
        );

        // protocol fee
        assertEq(
            DAI.balanceOf(address(autoRange)) - state.protocolDAIBalanceBefore,
            onlyFees ? 15583880997003094503 : 777250922543795237
        );
        assertEq(
            WETH_ERC20.balanceOf(address(autoRange)) - state.protocolWETHBalanceBefore,
            onlyFees ? 4948445849078767 : 193185163020990
        );

        // leftovers returned to owner
        assertEq(DAI.balanceOf(TEST_NFT_2_ACCOUNT) - state.ownerDAIBalanceBefore, onlyFees ? 0 : 1); // all was added to position
        assertEq(
            TEST_NFT_2_ACCOUNT.balance - state.ownerWETHBalanceBefore,
            onlyFees ? 428360726854687034 : 429435810185194946
        ); // leftover + fee + deposited = total in old position

        count = NPM.balanceOf(TEST_NFT_2_ACCOUNT);
        assertEq(count, 5);

        // new NFT is latest NFT - because of the order they are added
        state.tokenId = NPM.tokenOfOwnerByIndex(TEST_NFT_2_ACCOUNT, count - 1);

        (,,,,,,, state.liquidity,,,,) = NPM.positions(state.tokenId);

        // is not adjustable yet because in range
        vm.prank(OPERATOR_ACCOUNT);
        vm.expectRevert(Constants.NotReady.selector);
        autoRange.execute(
            AutoRange.ExecuteParams(
                state.tokenId,
                false,
                0,
                "",
                0,
                0,
                0,
                0,
                block.timestamp,
                onlyFees ? MAX_FEE_REWARD : MAX_REWARD
            )
        );

        // newly minted token
        assertEq(state.tokenId, 309207);

        (,,,,,,, state.liquidity,,,,) = NPM.positions(state.tokenId);
        (,,,,, int24 tickLowerAfter, int24 tickUpperAfter,,,,,) = NPM.positions(state.tokenId);
        (,, state.token0, state.token1, state.fee,,, state.liquidityOld,,,,) = NPM.positions(TEST_NFT_2);

        IUniswapV3Pool pool = IUniswapV3Pool(
            PoolAddress.computeAddress(FACTORY, PoolAddress.getPoolKey(state.token0, state.token1, state.fee))
        );
        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = pool.slot0();

        (state.amount0, state.amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLowerAfter),
            TickMath.getSqrtRatioAtTick(tickUpperAfter),
            state.liquidity
        );

        // new position amounts
        assertEq(state.amount0, onlyFees ? 296093738943058795842 : 310900369017518095107); //DAI
        assertEq(state.amount1, onlyFees ? 73593887852846239 : 77274065208396104); //WETH

        // check tick range correct
        assertEq(tickLowerAfter, -73260);
        assertEq(currentTick, -73244);
        assertEq(tickUpperAfter, -73260 + 60);

        assertEq(state.liquidity, onlyFees ? 3493233994488865101709 : 3667918618704675260835);
        assertEq(state.liquidityOld, 0);
    }
 
    function testDoubleAdjust() external {
        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.setApprovalForAll(address(autoRange), true);

        // bad config so it can be adjusted multiple times
        vm.prank(TEST_NFT_2_ACCOUNT);
        autoRange.configToken(
            TEST_NFT_2,
            address(0),
            AutoRange.PositionConfig(-100000, -100000, 0, 60, uint64(Q64 / 100), uint64(Q64 / 100), false, false, MAX_REWARD)
        );

        (,,,,,,, uint128 liquidity,,,,) = NPM.positions(TEST_NFT_2);

        // first adjust ok
        vm.prank(OPERATOR_ACCOUNT);
        autoRange.execute(AutoRange.ExecuteParams(TEST_NFT_2, false, 0, "", 0, 0, 0, 0, block.timestamp, 0));

        uint256 count = NPM.balanceOf(TEST_NFT_2_ACCOUNT);
        uint256 tokenId = NPM.tokenOfOwnerByIndex(TEST_NFT_2_ACCOUNT, count - 1);

        // newly minted token
        assertEq(tokenId, 309207);

        (,,,,,,, liquidity,,,,) = NPM.positions(tokenId);

        // second ajust leads to same range error
        vm.prank(OPERATOR_ACCOUNT);
        vm.expectRevert(Constants.SameRange.selector);
        autoRange.execute(AutoRange.ExecuteParams(tokenId, false, 0, "", 0, 0, 0, 0, block.timestamp, 0));
    }

    function testOracleCheck() external {
        // create range adjustor with more strict oracle config
        autoRange = new AutoRange(NPM, OPERATOR_ACCOUNT, WITHDRAWER_ACCOUNT, 60 * 30, 3, EX0x, UNIVERSAL_ROUTER);

        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.setApprovalForAll(address(autoRange), true);

        vm.prank(TEST_NFT_2_ACCOUNT);
        autoRange.configToken(
            TEST_NFT_2,
            address(0),
            AutoRange.PositionConfig(-100000, -100000, 0, 60, uint64(Q64 / 100), uint64(Q64 / 100), false, false, MAX_REWARD)
        );

        // TWAPCheckFailed
        vm.prank(OPERATOR_ACCOUNT);
        vm.expectRevert(Constants.TWAPCheckFailed.selector);
        autoRange.execute(AutoRange.ExecuteParams(TEST_NFT_2, false, 1000000, "", 0, 0, 0, 0, block.timestamp, 0));
    }

   
}
