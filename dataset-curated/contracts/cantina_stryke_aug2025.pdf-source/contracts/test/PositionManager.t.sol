// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockHandler} from "./mocks/MockHandler.sol";

contract PositionManagerTest is Test {
    PositionManager public positionManager;
    MockERC20 public token0;
    MockERC20 public token1;
    MockHandler public handler;
    address public owner;
    address public feeReceiver;
    address public user; // New user address

    function setUp() public {
        owner = address(this);
        feeReceiver = address(0xF33);
        user = address(0x1234); // Initialize user address
        positionManager = new PositionManager(owner);
        token0 = new MockERC20("Token0", "TKN0", 18);
        token1 = new MockERC20("Token1", "TKN1", 18);
        handler = new MockHandler(address(token0), address(token1), address(positionManager), feeReceiver);

        // Whitelist the handler
        positionManager.updateWhitelistHandler(address(handler), true);

        // Whitelist the handler with this contract as the app
        positionManager.updateWhitelistHandlerWithApp(address(handler), address(this), true);
    }

    function testMintPosition() public {
        uint256 amount0 = 1e18;
        uint256 amount1 = 1e18;
        token0.mint(user, amount0); // Mint to user address
        token1.mint(user, amount1); // Mint to user address

        vm.startPrank(user); // Start using user address for the following operations
        token0.approve(address(positionManager), amount0);
        token1.approve(address(positionManager), amount0);

        uint256 initialBalance0 = token0.balanceOf(user);
        uint256 initialBalance1 = token1.balanceOf(user);

        bytes memory mintPositionData = abi.encode(amount0, amount1);
        uint256 sharesMinted = positionManager.mintPosition(handler, mintPositionData);
        vm.stopPrank(); // Stop using user address

        assertGt(sharesMinted, 0);
        assertEq(token0.balanceOf(user), initialBalance0 - amount0);
        assertEq(token1.balanceOf(user), initialBalance1 - amount1);
    }

    function testBurnPosition() public {
        // First mint a position
        testMintPosition();

        uint256 amount0 = 1e18;
        uint256 amount1 = 1e18;
        bytes memory burnPositionData = abi.encode(amount0, amount1); // Pass amount0 and amount1

        vm.startPrank(user); // Start using user address for the following operations
        uint256 initialBalance0 = token0.balanceOf(user);
        uint256 initialBalance1 = token1.balanceOf(user);

        uint256 sharesBurned = positionManager.burnPosition(handler, burnPositionData);
        vm.stopPrank(); // Stop using user address

        assertGt(sharesBurned, 0);
        assertEq(token0.balanceOf(user), initialBalance0 + amount0);
        assertEq(token1.balanceOf(user), initialBalance1 + amount1);
    }

    function testUsePosition() public {
        // First mint a position
        testMintPosition();

        // Record initial balances of positionManager
        uint256 initialBalance0 = token0.balanceOf(address(address(this)));
        uint256 initialBalance1 = token1.balanceOf(address(address(this)));

        bytes memory usePositionData = abi.encode(1e17); // Use 10% of the position
        (address[] memory tokens, uint256[] memory amounts, uint256 liquidityUsed) =
            positionManager.usePosition(handler, usePositionData);

        // Record final balances of positionManager
        uint256 finalBalance0 = token0.balanceOf(address(address(this)));
        uint256 finalBalance1 = token1.balanceOf(address(address(this)));

        // Check that the token balances at positionManager have increased
        assertEq(tokens.length, 2);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);
        assertGt(liquidityUsed, 0);
        assertGt(finalBalance0, initialBalance0);
        assertGt(finalBalance1, initialBalance1);
    }

    function testUnusePosition() public {
        // First mint a position and use it
        testUsePosition();

        // Approve tokens for unuse operation
        uint256 approvalAmount = 1e18; // Approve more than needed to ensure sufficient allowance
        token0.approve(address(positionManager), approvalAmount);
        token1.approve(address(positionManager), approvalAmount);

        uint256 initialBalance0 = token0.balanceOf(address(handler));
        uint256 initialBalance1 = token1.balanceOf(address(handler));

        bytes memory unusePositionData = abi.encode(1e17); // Unuse 10% of the position
        (uint256[] memory amounts, uint256 liquidity) = positionManager.unusePosition(handler, unusePositionData);

        uint256 finalBalance0 = token0.balanceOf(address(handler));
        uint256 finalBalance1 = token1.balanceOf(address(handler));

        assertEq(amounts.length, 2);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);
        assertGt(liquidity, 0);
        assertEq(finalBalance0, initialBalance0 + amounts[0]);
        assertEq(finalBalance1, initialBalance1 + amounts[1]);
    }

    function testDonateToPosition() public {
        // First mint a position
        testMintPosition();

        uint256 donationAmount = 1e17;
        token0.mint(address(this), donationAmount);
        token1.mint(address(this), donationAmount);
        token0.approve(address(positionManager), donationAmount);
        token1.approve(address(positionManager), donationAmount);

        uint256 initialBalance0 = token0.balanceOf(address(this));
        uint256 initialBalance1 = token1.balanceOf(address(this));

        uint256 initialFeeReceiverBalance0 = token0.balanceOf(feeReceiver);
        uint256 initialFeeReceiverBalance1 = token1.balanceOf(feeReceiver);

        bytes memory donatePositionData = abi.encode(donationAmount, donationAmount);
        (uint256[] memory amounts, uint256 liquidity) = positionManager.donateToPosition(handler, donatePositionData);

        assertEq(amounts.length, 2);
        assertEq(amounts[0], donationAmount);
        assertEq(amounts[1], donationAmount);
        assertGt(liquidity, 0);
        assertEq(token0.balanceOf(address(this)), initialBalance0 - donationAmount);
        assertEq(token1.balanceOf(address(this)), initialBalance1 - donationAmount);
        assertEq(token0.balanceOf(feeReceiver), initialFeeReceiverBalance0 + donationAmount);
        assertEq(token1.balanceOf(feeReceiver), initialFeeReceiverBalance1 + donationAmount);
    }

    function testWildcard() public {
        bytes memory wildcardData = abi.encode("Some wildcard data");
        bytes memory result = positionManager.wildcard(handler, wildcardData);

        assertGt(result.length, 0);
    }

    function testUpdateWhitelistHandlerWithApp() public {
        address newHandler = address(0x123);
        address app = address(0x456);

        positionManager.updateWhitelistHandlerWithApp(newHandler, app, true);

        bytes32 key = keccak256(abi.encode(newHandler, app));
        assertTrue(positionManager.whitelistedHandlersWithApp(key));
    }

    function testUpdateWhitelistHandler() public {
        address newHandler = address(0x789);

        positionManager.updateWhitelistHandler(newHandler, true);

        assertTrue(positionManager.whitelistedHandlers(newHandler));
    }
}
