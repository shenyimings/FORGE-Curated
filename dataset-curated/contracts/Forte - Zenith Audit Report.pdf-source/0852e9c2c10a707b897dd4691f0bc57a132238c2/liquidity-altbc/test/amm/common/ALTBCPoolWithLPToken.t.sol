// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ALTBCTestSetup, PoolBase} from "test/util/ALTBCTestSetup.sol";
import {IERC721, IERC721Errors} from "lib/liquidity-base/test/amm/common/LPToken.t.sol";
import {packedFloat, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {QofMTestBase} from "test/equations/QofM/QofMTestBase.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {ALTBCInput, ALTBCDef} from "src/amm/ALTBC.sol";
import {IERC20Errors} from "lib/liquidity-base/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {ALTBCPool, IERC20} from "src/amm/ALTBCPool.sol";
import {MathLibs, packedFloat} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import "lib/liquidity-base/src/common/IErrors.sol";
import {TestCommonSetup, LPToken} from "lib/liquidity-base/test/util/TestCommonSetup.sol";
import "forge-std/console2.sol";

contract ALTBCPoolWithLPToken is TestCommonSetup, ALTBCTestSetup {
    ALTBCPool _pool;

    using ALTBCEquations for ALTBCDef;
    using MathLibs for int256;
    using MathLibs for packedFloat;

    uint256 constant MAX_SUPPLY = 1e11 * ERC20_DECIMALS;

    // TODO Clean this setup when factory is complete and sending xAdd tokens in the constrctor on the pool.
    function setUp() public {
        _deployFactory();
        _setUpTokens(1e29);
        _loadAdminAndAlice();
        vm.startPrank(admin);

        _pool = new ALTBCPool(address(xToken), address(yToken), fees, altbcInput, "Name", "SYMBOL");
        // Initial liquidity deposit with w0 is done in constructor
        xToken.approve(address(_pool), MAX_SUPPLY);
        xToken.transfer(address(_pool), X_TOKEN_MAX_SUPPLY);
        _pool.initializePool(admin);

        assertEq(_pool.currentTokenId(), 3);
        assertEq(_pool.balanceOf(admin), 1);
        assertEq(_pool.w(), X_TOKEN_MAX_SUPPLY);

        (packedFloat b, packedFloat c, packedFloat C, packedFloat xMin, packedFloat maxX, packedFloat V, ) = ALTBCPool(address(_pool))
            .tbc();
        (altbc.b, altbc.c, altbc.C, altbc.xMin, altbc.xMax, altbc.V) = (b, c, C, xMin, maxX, V);
    }

    function testLiquidity_PoolWithLPToken_UpdateLPTokenDeposit() public {
        // TokenId 1
        uint256 A = 1e18;
        uint256 B = 1e18;

        _pool.depositLiquidity(2, A, B);
        (packedFloat wj, packedFloat rj) = _pool.lpToken(address(admin), 2);
        uint256 _w = _pool.w();

        assertEq(rj.convertpackedFloatToWAD(), 10000000);
        // At this point, admin owns the entire pool
        assertEq(uint(wj.convertpackedFloatToWAD()), _w);
    }

    function testLiquidity_PoolWithLPToken_MultipleLPs() public {
        // TokenId 2
        uint256 A = 1e18;
        uint256 B = 1e18;
        uint256 _w0 = _pool.w();

        // Give some tokens to user 1 to deposit
        _tokenDistributionAndApproveHelper(address(_pool), address(1), A * 2, B * 2);
        vm.startPrank(address(1));
        _pool.depositLiquidity(0, A, B);
        (packedFloat wj, packedFloat rj) = _pool.lpToken(address(1), 3);
        uint256 _w1 = _pool.w();
        // This value is coming from the _calculateRj method: (hn * wj + r_hat * w_hat) / w_hat + wj
        assertEq(uint(rj.convertpackedFloatToWAD()), 10000000);
        assertEq(uint(wj.convertpackedFloatToWAD()), 999999999999999999);
        assertGe(_w1 + 1, _w0 + uint(wj.convertpackedFloatToWAD()));
        assertLe(_w1, _w0 + uint(wj.convertpackedFloatToWAD()) + 1);

        // TokenId 3
        // Give some tokens to user 2 to deposit
        _tokenDistributionAndApproveHelper(address(_pool), address(2), A * 2, B * 2);
        vm.startPrank(address(2));
        _pool.depositLiquidity(0, A * 2, B * 2);
        (wj, rj) = _pool.lpToken(address(2), 4);
        uint256 _w2 = _pool.w();
        // This value is coming from the _calculateRj method: (hn * wj + r_hat * w_hat) / w_hat + wj
        assertEq(uint(rj.convertpackedFloatToWAD()), 10000000);
        assertEq(uint(wj.convertpackedFloatToWAD()), 1999999999999999999);
        assertGe(_w2 + 1, _w1 + uint(wj.convertpackedFloatToWAD()));
        assertLe(_w2, _w1 + uint(wj.convertpackedFloatToWAD()) + 1);

        // TokenId 4
        // Give some tokens to user 3 to deposit
        _tokenDistributionAndApproveHelper(address(_pool), address(3), A * 100, B * 100);
        vm.startPrank(address(3));
        _pool.depositLiquidity(0, A * 100, B * 100);
        (wj, rj) = _pool.lpToken(address(3), 5);
        uint256 _w3 = _pool.w();
        // This value is coming from the _calculateRj method: (hn * wj + r_hat * w_hat) / w_hat + wj
        assertEq(uint(rj.convertpackedFloatToWAD()), 10000000);
        assertEq(uint(wj.convertpackedFloatToWAD()), 99999999999999999999);
        assertGe(_w3 + 1, _w2 + uint(wj.convertpackedFloatToWAD()));
        assertLe(_w3, _w2 + uint(wj.convertpackedFloatToWAD()) + 1);
    }

    function test_LPToken_PoolWithLPToken_PartialWithdrawal() public {
        // TokenId 2
        uint256 A = 1e29;
        uint256 B = 1e30;

        // Give some tokens to user 1 to deposit
        _tokenDistributionAndApproveHelper(address(_pool), address(1), A, B);

        vm.startPrank(address(1));

        // Swap to get some yTokens into the pool so it will allow liquidity deposits of Y
        (uint256 amountOut, , ) = _pool.simSwap(address(yToken), 2e18);
        _pool.swap(address(yToken), 2e18, amountOut);

        _pool.depositLiquidity(0, A, (B - 2e18));
        vm.stopPrank();

        (packedFloat wj, ) = _pool.lpToken(address(admin), 2);
        vm.startPrank(admin);
        _pool.withdrawLiquidity(2, uint(wj.div(int(2).toPackedFloat(0)).convertpackedFloatToWAD()));
        (packedFloat wjUpdated, ) = _pool.lpToken(address(admin), 2);

        // Make sure the liquidity position is updated, and LPToken still in admin owned
        (packedFloat user1Wj, ) = _pool.lpToken(address(1), 3);
        assertEq(uint(wjUpdated.convertpackedFloatToWAD()), _pool.w() - uint(user1Wj.convertpackedFloatToWAD()));
        assertEq(_pool.balanceOf(address(admin)), 1);

        // Make sure the LPToken wasnt burned. This would revert if the token no longer exists
        _pool.tokenURI(2);
    }

    function test_LPToken_PoolWithLPToken_FullWithdrawal() public {
        // TokenId 2
        uint256 A = 1e29;
        uint256 B = 1e30;

        // Give some tokens to user 1 to deposit
        _tokenDistributionAndApproveHelper(address(_pool), address(1), A, B);

        vm.startPrank(address(1));
        // Swap to get some yTokens into the pool so it will allow liquidity deposits of Y
        (uint256 amountOut, , ) = _pool.simSwap(address(yToken), 2e18);
        _pool.swap(address(yToken), 2e18, amountOut);

        _pool.depositLiquidity(0, A, (B - 2e18));
        vm.stopPrank();

        (packedFloat wj, ) = _pool.lpToken(address(admin), 2);
        vm.startPrank(admin);
        _pool.withdrawLiquidity(2, uint(wj.convertpackedFloatToWAD()));
        (packedFloat wjUpdated, ) = _pool.lpToken(address(admin), 2);

        // Make sure the liquidity position is reset, and LPToken representing the position is burned
        assertEq(packedFloat.unwrap(wjUpdated), 0);
        assertEq(_pool.balanceOf(address(admin)), 0);

        // Expect revert when checking the burned token URI
        vm.expectRevert(abi.encodeWithSelector(URIQueryForNonexistentToken.selector));
        _pool.tokenURI(2);
    }

    function test_LPToken_PoolWithLPToken_RevenueClaim() public {
        uint256 A = 1e18;
        uint256 B = 1e18;
        uint256 lps = 10;

        // Get alice in early
        _tokenDistributionAndApproveHelper(address(_pool), alice, A, B);
        vm.startPrank(alice);
        _pool.depositLiquidity(0, A, B);

        // Generate some revenue for alice
        for (uint160 i = 1; i < lps; ++i) {
            _tokenDistributionAndApproveHelper(address(_pool), address(i), A, B);
            vm.startPrank(address(i));
            _pool.depositLiquidity(0, A, B);
        }
        for (uint160 i = 1; i < lps; ++i) {
            _tokenDistributionAndApproveHelper(address(_pool), address(i), A, B);
            (uint expected, , ) = _pool.simSwap(address(yToken), B);
            vm.startPrank(address(i));
            _pool.swap(address(yToken), B, expected);
        }
        uint256 yBalanceBefore = IERC20(address(yToken)).balanceOf(alice);
        console2.log(yBalanceBefore);
        (packedFloat wj, ) = _pool.getLPToken(alice, 3);
        vm.startPrank(alice);
        // Expect revert when Q is too high
        vm.expectRevert("ALTBCPool: Q too high");
        _pool.withdrawRevenue(3, uint(wj.mul(int(2).toPackedFloat(0)).convertpackedFloatToWAD()));

        // TODO Update this test once Ln precision is better to accurately check revenue available
        //uint256 rev = _pool.getRevenueAvailable(alice, 2);
        //_pool.claimRevenue(2, rev);
    }

    function test_LPToken_PoolWithLPToken_Withdawal_RevertCases() public {
        vm.startPrank(admin);
        uint256 w = _pool.w();

        // Expect revert when trying to withdraw 0 amount
        vm.expectRevert(abi.encodeWithSelector(ZeroValueNotAllowed.selector));
        _pool.withdrawLiquidity(2, 0);

        // Expect revert when trying to withdraw more than total w
        vm.expectRevert("LPToken: withdrawal amount exceeds allowance");
        _pool.withdrawLiquidity(2, w + 1);

        // Expect revert when non token owner tries updating a position
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(InvalidToken.selector));
        _pool.withdrawLiquidity(2, w);
    }
}
