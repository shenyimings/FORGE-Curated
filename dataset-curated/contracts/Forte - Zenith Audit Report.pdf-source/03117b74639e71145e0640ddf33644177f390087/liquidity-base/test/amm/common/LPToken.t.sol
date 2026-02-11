/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {LPToken} from "src/common/LPToken.sol";
import "forge-std/console2.sol";
import {TestCommon} from "test/util/TestCommon.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Errors} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/*contract LPTokenTests is TestCommon {
    address _pool = address(0x9001); // We use this _pool instead of pool because pool is currently address(0), which cant be set to owner
    uint256 wj_input = 1_000; // Arbitrary value for qWn, used to update amount of liquidity of a position
    uint256 rj_input = 100; // Arbitrary value for last_revenue_claim, used to update last_revenue_claim of a position
    uint256 w0 = 10_000_000; // Arbitrary value for initial liquidity deposit by pool deployer

    function setUp() public {
        vm.startPrank(address(_pool));
        lpToken = new LPToken("LP Token", "LPT");
    }

    function test_LPToken_SetGlobalWInConstructor() public view {
        assertEq(lpToken.w(), w0);
    }

    function test_LPToken_ConstructorAssignsNameAndSymbolCorrectly() public view {
        assertEq(lpToken.name(), "LP Token");
        assertEq(lpToken.symbol(), "LPT");
    }

    function test_LPToken_ConstructorAssignsPoolAddressAsOwner() public view {
        assertEq(lpToken.owner(), address(_pool));
    }

    function test_LPToken_ConstructorMintsLPTokenToAdmin() public view {
        assertEq(lpToken.balanceOf(admin), 1);
    }

    function test_LPToken_ConstructorBaseURISetCorrectly() public view {
        assertEq(lpToken.tokenURI(1), "Example.uri/1");
    }

    function test_LPToken_AssignVariablesOnMint() public view {
        (uint256 rj, uint256 wj) = lpToken.lpToken(admin, 1);
        assertEq(rj, 0);
        assertEq(wj, w0);
    }

    function test_LPToken_MultipleLPs() public {
        // One token minted already. Next token minted will be tokenId 2, and so on.
        vm.startPrank(address(_pool));

        // TokenId 2
        wj_input = 100;
        uint256 _w = lpToken.w();
        lpToken.mint(ADDRESSES[0], wj_input, rj_input);
        (uint256 rj, uint256 wj) = lpToken.lpToken(ADDRESSES[0], 2);
        assertEq(rj, rj_input);
        assertEq(wj, _w + wj_input);

        // TokenId 3
        wj_input = 500;
        _w = lpToken.w();
        lpToken.mint(ADDRESSES[1], wj_input, rj_input);
        (rj, wj) = lpToken.lpToken(ADDRESSES[1], 3);
        assertEq(rj, rj_input);
        assertEq(wj, _w + wj_input);

        // TokenId 4
        wj_input = 1000;
        _w = lpToken.w();
        lpToken.mint(ADDRESSES[2], wj_input, rj_input);
        (rj, wj) = lpToken.lpToken(ADDRESSES[2], 4);
        assertEq(rj, rj_input);
        assertEq(wj, _w + wj_input);
    }

    function test_LPToken_UpdateLPTokenVarsWithNewLiqDeposit_ZeroRjValue() public {
        (uint256 rj, uint256 wj) = lpToken.lpToken(address(admin), 1);
        assertEq(rj, 0);
        assertEq(wj, w0);

        wj_input = 1_000_000;

        vm.startPrank(address(_pool));
        lpToken.updateLPTokenDeposit(address(admin), 1, wj_input, rj_input);
        (uint256 rjUpdated, uint256 wjUpdated) = lpToken.lpToken(address(admin), 1);

        // The value 9 is coming from the _calculateRj method: (hn * wj + r_hat * w_hat) / w_hat + wj
        assertEq(rjUpdated, 9);
        assertEq(wjUpdated, wj + wj_input);
    }

    function test_LPToken_UpdateLPTokenVarsWithNewLiqDeposit_NonZeroRjValue() public {
        vm.startPrank(address(_pool));
        lpToken.updateLPTokenDeposit(address(admin), 1, wj_input, rj_input);
        (, uint256 wj) = lpToken.lpToken(address(admin), 1);

        wj_input = 1_000_000;
        lpToken.updateLPTokenDeposit(address(admin), 1, wj_input, rj_input);
        (uint256 rjUpdated, uint256 wjUpdated) = lpToken.lpToken(address(admin), 1);

        // The value 9 is coming from the _calculateRj method: (hn * wj + r_hat * w_hat) / w_hat + wj
        assertEq(rjUpdated, 9);
        assertEq(wjUpdated, wj + wj_input);
    }

    function test_LPToken_UpdateLPTokenVarsWithWithdrawal_Partial() public {
        (uint256 rj, uint256 wj) = lpToken.lpToken(address(admin), 1);
        assertEq(rj, 0);
        assertEq(wj, w0);

        vm.startPrank(address(_pool));
        lpToken.updateLPTokenWithdrawal(address(admin), 1, w0 / 2);
        (, uint256 wjUpdated) = lpToken.lpToken(address(admin), 1);
        assertEq(wjUpdated, w0 / 2);
    }

    function test_LPToken_UpdateLPTokenVarsWithWithdrawal_Full() public {
        (uint256 rj, uint256 wj) = lpToken.lpToken(address(admin), 1);
        assertEq(rj, 0);
        assertEq(wj, w0);
        assertEq(lpToken.balanceOf(address(admin)), 1);

        vm.startPrank(address(_pool));
        vm.expectEmit(true, true, true, true, address(lpToken));
        emit IERC721.Transfer(address(admin), address(0), 1);

        lpToken.updateLPTokenWithdrawal(address(admin), 1, w0);
        (, uint256 wjUpdated) = lpToken.lpToken(address(admin), 1);

        // Make sure the liquidity position is reset, and LPToken representing the position is burned
        assertEq(wjUpdated, 0);
        assertEq(lpToken.balanceOf(address(admin)), 0);

        // Expect revert when checking the burned token URI
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        lpToken.tokenURI(1);
    }

    function test_LPToken_RevertOnNonOwnerCalling_updateLPTokenDeposit() public {
        // Set caller to non-owner
        vm.startPrank(ADDRESSES[0]);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ADDRESSES[0]));
        lpToken.updateLPTokenDeposit(address(admin), 1, wj_input, rj_input);
    }

    function test_LPToken_RevertOnNonOwnerCalling_updateLPTokenWithdrawal() public {
        // Set caller to non-owner
        vm.startPrank(ADDRESSES[0]);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ADDRESSES[0]));
        lpToken.updateLPTokenWithdrawal(address(admin), 1, w0);
    }

    function test_LPToken_RevertOnNonOwnerCalling_mint() public {
        // Set caller to non-owner
        vm.startPrank(ADDRESSES[0]);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ADDRESSES[0]));
        lpToken.mint(ADDRESSES[0], wj_input, rj_input);
    }
}*/
