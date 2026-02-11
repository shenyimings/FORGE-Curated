// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {LeverageManagerTest} from "./LeverageManager.t.sol";
import {MockLendingAdapter} from "test/unit/mock/MockLendingAdapter.sol";

contract TransferTokensTest is LeverageManagerTest {
    function test_transferTokens_FromLeverageManager() public {
        ERC20Mock token1 = new ERC20Mock();

        uint256 token1BalanceBefore = 100 ether;

        token1.mint(address(leverageManager), token1BalanceBefore);

        uint256 token1TransferAmount = 50 ether;

        leverageManager.exposed_transferTokens(
            IERC20(address(token1)), address(leverageManager), address(this), token1TransferAmount
        );

        assertEq(token1.balanceOf(address(this)), token1TransferAmount);
        assertEq(token1.balanceOf(address(leverageManager)), token1BalanceBefore - token1TransferAmount);
    }

    function test_transferTokens_ToLeverageManager() public {
        ERC20Mock token1 = new ERC20Mock();

        uint256 token1BalanceBefore = 100 ether;

        token1.mint(address(this), token1BalanceBefore);

        uint256 token1TransferAmount = 50 ether;

        token1.approve(address(leverageManager), token1TransferAmount);

        leverageManager.exposed_transferTokens(
            IERC20(address(token1)), address(this), address(leverageManager), token1TransferAmount
        );

        assertEq(token1.balanceOf(address(leverageManager)), token1TransferAmount);
        assertEq(token1.balanceOf(address(this)), token1BalanceBefore - token1TransferAmount);
    }

    function test_transferTokens_ZeroAddress() public {
        // No-op, does not revert
        leverageManager.exposed_transferTokens(IERC20(address(0)), address(this), address(this), 100 ether);
    }
}
