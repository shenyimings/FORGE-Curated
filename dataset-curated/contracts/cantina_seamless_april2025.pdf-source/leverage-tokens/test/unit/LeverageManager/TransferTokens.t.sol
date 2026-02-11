// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {LeverageManagerTest} from "./LeverageManager.t.sol";
import {MockLendingAdapter} from "test/unit/mock/MockLendingAdapter.sol";
import {TokenTransfer} from "src/types/DataTypes.sol";

contract TransferTokensTest is LeverageManagerTest {
    function test_transferTokens_FromLeverageManager() public {
        ERC20Mock token1 = new ERC20Mock();
        ERC20Mock token2 = new ERC20Mock();
        ERC20Mock token3 = new ERC20Mock();

        uint256 token1BalanceBefore = 100 ether;
        uint256 token2BalanceBefore = 80 ether;
        uint256 token3BalanceBefore = 90 ether;

        token1.mint(address(leverageManager), token1BalanceBefore);
        token2.mint(address(leverageManager), token2BalanceBefore);
        token3.mint(address(leverageManager), token3BalanceBefore);

        uint256 token1TransferAmount = 50 ether;
        uint256 token2TransferAmount = 30 ether;
        uint256 token3TransferAmount = 70 ether;

        TokenTransfer[] memory transfers = new TokenTransfer[](3);
        transfers[0] = TokenTransfer({token: address(token1), amount: token1TransferAmount});
        transfers[1] = TokenTransfer({token: address(token2), amount: token2TransferAmount});
        transfers[2] = TokenTransfer({token: address(token3), amount: token3TransferAmount});

        leverageManager.exposed_transferTokens(transfers, address(leverageManager), address(this));

        assertEq(token1.balanceOf(address(this)), token1TransferAmount);
        assertEq(token2.balanceOf(address(this)), token2TransferAmount);
        assertEq(token3.balanceOf(address(this)), token3TransferAmount);
        assertEq(token1.balanceOf(address(leverageManager)), token1BalanceBefore - token1TransferAmount);
        assertEq(token2.balanceOf(address(leverageManager)), token2BalanceBefore - token2TransferAmount);
        assertEq(token3.balanceOf(address(leverageManager)), token3BalanceBefore - token3TransferAmount);
    }

    function test_transferTokens_ToLeverageManager() public {
        ERC20Mock token1 = new ERC20Mock();
        ERC20Mock token2 = new ERC20Mock();
        ERC20Mock token3 = new ERC20Mock();

        uint256 token1BalanceBefore = 100 ether;
        uint256 token2BalanceBefore = 80 ether;
        uint256 token3BalanceBefore = 90 ether;

        token1.mint(address(this), token1BalanceBefore);
        token2.mint(address(this), token2BalanceBefore);
        token3.mint(address(this), token3BalanceBefore);

        uint256 token1TransferAmount = 50 ether;
        uint256 token2TransferAmount = 30 ether;
        uint256 token3TransferAmount = 70 ether;

        TokenTransfer[] memory transfers = new TokenTransfer[](3);
        transfers[0] = TokenTransfer({token: address(token1), amount: token1TransferAmount});
        transfers[1] = TokenTransfer({token: address(token2), amount: token2TransferAmount});
        transfers[2] = TokenTransfer({token: address(token3), amount: token3TransferAmount});

        token1.approve(address(leverageManager), token1TransferAmount);
        token2.approve(address(leverageManager), token2TransferAmount);
        token3.approve(address(leverageManager), token3TransferAmount);

        leverageManager.exposed_transferTokens(transfers, address(this), address(leverageManager));

        assertEq(token1.balanceOf(address(leverageManager)), token1TransferAmount);
        assertEq(token2.balanceOf(address(leverageManager)), token2TransferAmount);
        assertEq(token3.balanceOf(address(leverageManager)), token3TransferAmount);
        assertEq(token1.balanceOf(address(this)), token1BalanceBefore - token1TransferAmount);
        assertEq(token2.balanceOf(address(this)), token2BalanceBefore - token2TransferAmount);
        assertEq(token3.balanceOf(address(this)), token3BalanceBefore - token3TransferAmount);
    }
}
