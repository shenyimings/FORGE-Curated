// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {LikwidVault} from "../src/LikwidVault.sol";
import {LikwidPairPosition} from "../src/LikwidPairPosition.sol";
import {IPairPositionManager} from "../src/interfaces/IPairPositionManager.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {StateLibrary} from "../src/libraries/StateLibrary.sol";
import {PairPosition} from "../src/libraries/PairPosition.sol";
import {Reserves} from "../src/types/Reserves.sol";
import {MarginState} from "../src/types/MarginState.sol";

contract LikwidPairPositionTest is Test {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    LikwidVault vault;
    LikwidPairPosition pairPositionManager;
    PoolKey key;
    PoolKey keyNative;
    MockERC20 token0;
    MockERC20 token1;
    Currency currency0;
    Currency currency1;

    function setUp() public {
        skip(1); // Ensure block.timestamp is not zero

        // Deploy Vault and Position Manager
        vault = new LikwidVault(address(this));
        pairPositionManager = new LikwidPairPosition(address(this), vault);

        // Deploy mock tokens
        address tokenA = address(new MockERC20("TokenA", "TKNA", 18));
        address tokenB = address(new MockERC20("TokenB", "TKNB", 18));

        // Ensure currency order
        if (tokenA < tokenB) {
            token0 = MockERC20(tokenA);
            token1 = MockERC20(tokenB);
        } else {
            token0 = MockERC20(tokenB);
            token1 = MockERC20(tokenA);
        }

        // Wrap tokens into Currency type
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        // The test contract is the vault's controller to settle balances
        vault.setMarginController(address(this));

        // Disable liquidity locking for tests
        MarginState currentMarginState = vault.marginState();
        vault.setMarginState(currentMarginState.setStageDuration(0));

        // Approve the vault to pull funds from this test contract
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
        token0.approve(address(pairPositionManager), type(uint256).max);
        token1.approve(address(pairPositionManager), type(uint256).max);
        uint24 fee = 3000; // 0.3%
        key = PoolKey({currency0: currency0, currency1: currency1, fee: fee});
        vault.initialize(key);
        keyNative = PoolKey({currency0: CurrencyLibrary.ADDRESS_ZERO, currency1: currency1, fee: fee});
        vault.initialize(keyNative);
    }

    function testAddLiquidityCreatesPositionAndAddsLiquidity() public {
        // 1. Arrange
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 20e18;
        PoolId id = key.toId();

        // Mint tokens to this test contract
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);

        assertEq(token0.balanceOf(address(this)), amount0ToAdd, "Initial user balance of token0 should be correct");
        assertEq(token1.balanceOf(address(this)), amount1ToAdd, "Initial user balance of token1 should be correct");

        // 2. Act
        (uint256 tokenId, uint128 liquidity) = pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        // 3. Assert
        // Check NFT ownership and position data
        assertEq(tokenId, 1, "First token minted should have ID 1");
        assertEq(pairPositionManager.ownerOf(tokenId), address(this), "Owner of new token should be the caller");
        (Currency c0, Currency c1, uint24 storedFee) =
            pairPositionManager.poolKeys(pairPositionManager.poolIds(tokenId));
        PoolKey memory storedKey = PoolKey(c0, c1, storedFee);
        assertEq(PoolId.unwrap(storedKey.toId()), PoolId.unwrap(id), "Stored PoolKey should be correct");
        assertTrue(liquidity > 0, "Liquidity should be greater than zero");

        // Check user's token balances (should be zero)
        assertEq(token0.balanceOf(address(this)), 0, "User should have spent all token0");
        assertEq(token1.balanceOf(address(this)), 0, "User should have spent all token1");

        // Check vault's token balances
        assertEq(token0.balanceOf(address(vault)), amount0ToAdd, "Vault should have received token0");
        assertEq(token1.balanceOf(address(vault)), amount1ToAdd, "Vault should have received token1");

        // Check vault's internal reserves for the pool
        Reserves reserves = StateLibrary.getPairReserves(vault, id);
        assertEq(reserves.reserve0(), amount0ToAdd, "Vault internal reserve0 should match");
        assertEq(reserves.reserve1(), amount1ToAdd, "Vault internal reserve1 should match");

        PairPosition.State memory _positionState = pairPositionManager.getPositionState(tokenId);
        assertEq(_positionState.liquidity, liquidity, "positionState.liquidity == liquidity");
        uint256 prev = _positionState.totalInvestment;
        int128 prevAmount0;
        int128 prevAmount1;
        assembly ("memory-safe") {
            // Unpack prev into two 128-bit values
            prevAmount0 := shr(128, prev)
            prevAmount1 := and(prev, 0xffffffffffffffffffffffffffffffff)
        }
        assertEq(amount0ToAdd, uint256(-int256(prevAmount0)), "amount0ToAdd == -prevAmount0");
        assertEq(amount1ToAdd, uint256(-int256(prevAmount1)), "amount1ToAdd == -prevAmount1");
    }

    function testAddLiquidityCreatesPositionAndAddsLiquidityNative() public {
        // 1. Arrange
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 20e18;
        PoolId id = keyNative.toId();

        // Mint tokens to this test contract
        token1.mint(address(this), amount1ToAdd);

        assertEq(token1.balanceOf(address(this)), amount1ToAdd, "Initial user balance of token1 should be correct");

        // 2. Act
        (uint256 tokenId, uint128 liquidity) =
            pairPositionManager.addLiquidity{value: amount0ToAdd}(keyNative, amount0ToAdd, amount1ToAdd, 0, 0);

        // 3. Assert
        // Check NFT ownership and position data
        assertEq(tokenId, 1, "First token minted should have ID 1");
        assertEq(pairPositionManager.ownerOf(tokenId), address(this), "Owner of new token should be the caller");
        (Currency c0, Currency c1, uint24 storedFee) =
            pairPositionManager.poolKeys(pairPositionManager.poolIds(tokenId));
        PoolKey memory storedKey = PoolKey(c0, c1, storedFee);
        assertEq(PoolId.unwrap(storedKey.toId()), PoolId.unwrap(id), "Stored PoolKey should be correct");
        assertTrue(liquidity > 0, "Liquidity should be greater than zero");

        // Check user's token balances (should be zero)
        assertEq(token1.balanceOf(address(this)), 0, "User should have spent all token1");

        // Check vault's token balances
        assertEq(token1.balanceOf(address(vault)), amount1ToAdd, "Vault should have received token1");

        // Check vault's internal reserves for the pool
        Reserves reserves = StateLibrary.getPairReserves(vault, id);
        assertEq(reserves.reserve0(), amount0ToAdd, "Vault internal reserve0 should match");
        assertEq(reserves.reserve1(), amount1ToAdd, "Vault internal reserve1 should match");

        PairPosition.State memory _positionState = pairPositionManager.getPositionState(tokenId);
        assertEq(_positionState.liquidity, liquidity, "positionState.liquidity == liquidity");
        uint256 prev = _positionState.totalInvestment;
        int128 prevAmount0;
        int128 prevAmount1;
        assembly ("memory-safe") {
            // Unpack prev into two 128-bit values
            prevAmount0 := shr(128, prev)
            prevAmount1 := and(prev, 0xffffffffffffffffffffffffffffffff)
        }
        assertEq(amount0ToAdd, uint256(-int256(prevAmount0)), "amount0ToAdd == -prevAmount0");
        assertEq(amount1ToAdd, uint256(-int256(prevAmount1)), "amount1ToAdd == -prevAmount1");
    }

    function testRemoveLiquidity() public {
        // 1. Arrange: Add liquidity first to create a position
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 10e18; // Use 1:1 ratio for simplicity

        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);

        (uint256 tokenId, uint128 liquidityAdded) =
            pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        assertEq(token0.balanceOf(address(this)), 0, "User token0 balance should be 0 after adding liquidity");
        assertEq(token1.balanceOf(address(this)), 0, "User token1 balance should be 0 after adding liquidity");

        // 2. Act: Remove the entire liquidity
        uint128 liquidityRemoved = liquidityAdded / 6;
        (uint256 amount0Removed, uint256 amount1Removed) =
            pairPositionManager.removeLiquidity(tokenId, liquidityRemoved, 0, 0);

        // 3. Assert
        // Check amounts returned
        assertEq(amount0Removed, amount0ToAdd / 6, "Amount of token0 removed should equal 1/6 amount added");
        assertEq(amount1Removed, amount1ToAdd / 6, "Amount of token1 removed should equal 1/6 amount added");

        // Check user's final token balances
        assertEq(token0.balanceOf(address(this)), amount0Removed, "User should have received back 1/6 token0");
        assertEq(token1.balanceOf(address(this)), amount1Removed, "User should have received back 1/6 token1");

        // Check vault's final token balances (should be zero)
        assertEq(token0.balanceOf(address(vault)), amount0ToAdd - amount0Removed, "Vault should have sent 1/6 token0");
        assertEq(token1.balanceOf(address(vault)), amount1ToAdd - amount1Removed, "Vault should have sent 1/6 token1");

        // Check vault's internal reserves (should be zero)
        Reserves reserves = StateLibrary.getPairReserves(vault, key.toId());
        assertEq(
            reserves.reserve0(),
            amount0ToAdd - amount0Removed,
            "Vault internal reserve0 should be amount0ToAdd - amount0Removed"
        );
        assertEq(
            reserves.reserve1(),
            amount1ToAdd - amount1Removed,
            "Vault internal reserve1 should be amount1ToAdd-amount1Removed"
        );
    }

    function testExactInputSwap() public {
        // 1. Arrange: Add liquidity
        uint256 amount0ToAdd = 100e18;
        uint256 amount1ToAdd = 100e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        // 2. Arrange: Prepare for swap
        uint256 amountIn = 10e18;
        token0.mint(address(this), amountIn); // Mint token0 to swap for token1
        PoolId poolId = key.toId();
        bool zeroForOne = true; // Swapping token0 for token1

        IPairPositionManager.SwapInputParams memory params = IPairPositionManager.SwapInputParams({
            poolId: poolId,
            zeroForOne: zeroForOne,
            to: address(this),
            amountIn: amountIn,
            amountOutMin: 0,
            deadline: block.timestamp + 1
        });

        // 3. Act
        (,, uint256 amountOut) = pairPositionManager.exactInput(params);

        // 4. Assert
        assertTrue(amountOut > 0, "Amount out should be greater than 0");

        // Check balances
        assertEq(token0.balanceOf(address(this)), 0, "User should have spent all token0 for swap");
        assertEq(token1.balanceOf(address(this)), amountOut, "User should have received token1");

        // Check vault reserves
        Reserves reserves = StateLibrary.getPairReserves(vault, poolId);
        assertEq(reserves.reserve0(), amount0ToAdd + amountIn, "Vault reserve0 should have increased by amountIn");
        assertEq(reserves.reserve1(), amount1ToAdd - amountOut, "Vault reserve1 should have decreased by amountOut");
    }

    function testExactInputSwapNative() public {
        // 1. Arrange: Add liquidity
        uint256 amount0ToAdd = 100e18;
        uint256 amount1ToAdd = 100e18;
        token1.mint(address(this), amount1ToAdd);
        pairPositionManager.addLiquidity{value: amount0ToAdd}(keyNative, amount0ToAdd, amount1ToAdd, 0, 0);

        // 2. Arrange: Prepare for swap
        uint256 amountIn = 10e18;
        token0.mint(address(this), amountIn); // Mint token0 to swap for token1
        PoolId poolId = keyNative.toId();
        bool zeroForOne = true; // Swapping token0 for token1

        IPairPositionManager.SwapInputParams memory params = IPairPositionManager.SwapInputParams({
            poolId: poolId,
            zeroForOne: zeroForOne,
            to: address(this),
            amountIn: amountIn,
            amountOutMin: 0,
            deadline: block.timestamp + 1
        });

        // 3. Act
        (,, uint256 amountOut) = pairPositionManager.exactInput{value: amountIn}(params);

        // 4. Assert
        assertTrue(amountOut > 0, "Amount out should be greater than 0");

        // Check balances
        assertEq(token1.balanceOf(address(this)), amountOut, "User should have received token1");

        // Check vault reserves
        Reserves reserves = StateLibrary.getPairReserves(vault, poolId);
        assertEq(reserves.reserve0(), amount0ToAdd + amountIn, "Vault reserve0 should have increased by amountIn");
        assertEq(reserves.reserve1(), amount1ToAdd - amountOut, "Vault reserve1 should have decreased by amountOut");
    }

    function testExactOutputSwap() public {
        // 1. Arrange: Add liquidity
        uint256 amount0ToAdd = 100e18;
        uint256 amount1ToAdd = 100e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        // 2. Arrange: Prepare for swap
        uint256 amountOut = 10e18;
        token0.mint(address(this), 20e18); // Mint extra token0 to cover input
        PoolId poolId = key.toId();
        bool zeroForOne = true; // Swapping token0 for token1

        IPairPositionManager.SwapOutputParams memory params = IPairPositionManager.SwapOutputParams({
            poolId: poolId,
            zeroForOne: zeroForOne,
            to: address(this),
            amountInMax: 20e18,
            amountOut: amountOut,
            deadline: block.timestamp + 1
        });

        // 3. Act
        (,, uint256 amountIn) = pairPositionManager.exactOutput(params);

        // 4. Assert
        assertTrue(amountIn > 0, "Amount in should be greater than 0");
        assertTrue(amountIn < 20e18, "Amount in should be less than max");

        // Check balances
        assertEq(token0.balanceOf(address(this)), 20e18 - amountIn, "User should have spent amountIn of token0");
        assertEq(token1.balanceOf(address(this)), amountOut, "User should have received amountOut of token1");

        // Check vault reserves
        Reserves reserves = StateLibrary.getPairReserves(vault, poolId);
        assertEq(reserves.reserve0(), amount0ToAdd + amountIn, "Vault reserve0 should have increased by amountIn");
        assertEq(reserves.reserve1(), amount1ToAdd - amountOut, "Vault reserve1 should have decreased by amountOut");
    }

    function test_RevertIf_RemoveLiquidityNotOwner() public {
        // 1. Arrange: Add liquidity to create a position
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 10e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        (uint256 tokenId, uint128 liquidityAdded) =
            pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        // 2. Act & Assert: Expect revert when another user tries to remove liquidity
        vm.prank(address(0xDEADBEEF));
        vm.expectRevert(bytes("NotOwner()"));
        pairPositionManager.removeLiquidity(tokenId, liquidityAdded, 0, 0);
    }

    function test_RevertIf_IncreaseLiquidityNotOwner() public {
        // 1. Arrange: Add liquidity to create a position
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 10e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        (uint256 tokenId,) = pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        // 2. Act & Assert: Expect revert when another user tries to increase liquidity
        vm.prank(address(0xDEADBEEF));
        vm.expectRevert(bytes("NotOwner()"));
        pairPositionManager.increaseLiquidity(tokenId, 1e18, 1e18, 0, 0);
    }

    function testRemoveAllLiquidity() public {
        // 1. Arrange: Add liquidity first to create a position
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 10e18; // Use 1:1 ratio for simplicity

        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);

        (uint256 tokenId, uint128 liquidityAdded) =
            pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        assertEq(token0.balanceOf(address(this)), 0, "User token0 balance should be 0 after adding liquidity");
        assertEq(token1.balanceOf(address(this)), 0, "User token1 balance should be 0 after adding liquidity");

        // 2. Act: Remove the entire liquidity
        (uint256 amount0Removed, uint256 amount1Removed) =
            pairPositionManager.removeLiquidity(tokenId, liquidityAdded, 0, 0);

        // 3. Assert
        // Check amounts returned. Due to rounding, it might not be exactly the same, but should be very close.
        assertApproxEqAbs(amount0Removed, amount0ToAdd, 1, "Amount of token0 removed should be close to amount added");
        assertApproxEqAbs(amount1Removed, amount1ToAdd, 1, "Amount of token1 removed should be close to amount added");

        // Check user's final token balances
        assertEq(token0.balanceOf(address(this)), amount0Removed, "User should have received back all token0");
        assertEq(token1.balanceOf(address(this)), amount1Removed, "User should have received back all token1");

        // Check vault's final token balances (should be close to zero)
        assertApproxEqAbs(token0.balanceOf(address(vault)), 0, 1, "Vault should have sent all token0");
        assertApproxEqAbs(token1.balanceOf(address(vault)), 0, 1, "Vault should have sent all token1");

        // Check position liquidity is now zero
        PairPosition.State memory positionState = pairPositionManager.getPositionState(tokenId);
        assertEq(positionState.liquidity, 0, "Position liquidity should be zero after full withdrawal");
    }

    function test_RevertIf_SwapWithExpiredDeadline() public {
        // 1. Arrange: Add liquidity and prepare for swap
        uint256 amount0ToAdd = 100e18;
        uint256 amount1ToAdd = 100e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        uint256 amountIn = 10e18;
        token0.mint(address(this), amountIn);
        PoolId poolId = key.toId();

        IPairPositionManager.SwapInputParams memory params = IPairPositionManager.SwapInputParams({
            poolId: poolId,
            zeroForOne: true,
            to: address(this),
            amountIn: amountIn,
            amountOutMin: 0,
            deadline: block.timestamp - 1 // Expired deadline
        });

        // 2. Act & Assert
        vm.expectRevert("EXPIRED");
        pairPositionManager.exactInput(params);
    }

    function testIncreaseLiquidity() public {
        // 1. Arrange: Add initial liquidity
        uint256 initialAmount0 = 10e18;
        uint256 initialAmount1 = 10e18;
        token0.mint(address(this), initialAmount0);
        token1.mint(address(this), initialAmount1);
        (uint256 tokenId, uint128 initialLiquidity) =
            pairPositionManager.addLiquidity(key, initialAmount0, initialAmount1, 0, 0);

        // 2. Arrange: Prepare for increasing liquidity
        uint256 increaseAmount0 = 5e18;
        uint256 increaseAmount1 = 5e18;
        token0.mint(address(this), increaseAmount0);
        token1.mint(address(this), increaseAmount1);

        // 3. Act
        uint128 addedLiquidity = pairPositionManager.increaseLiquidity(tokenId, increaseAmount0, increaseAmount1, 0, 0);

        // 4. Assert
        assertTrue(addedLiquidity > 0, "Added liquidity should be positive");

        // Check position state
        PairPosition.State memory positionState = pairPositionManager.getPositionState(tokenId);
        assertEq(positionState.liquidity, initialLiquidity + addedLiquidity, "Total liquidity should have increased");

        // Check vault reserves
        Reserves reserves = StateLibrary.getPairReserves(vault, key.toId());
        assertEq(reserves.reserve0(), initialAmount0 + increaseAmount0, "Vault reserve0 should be updated");
        assertEq(reserves.reserve1(), initialAmount1 + increaseAmount1, "Vault reserve1 should be updated");

        // Check user balances
        assertEq(token0.balanceOf(address(this)), 0, "User should have spent all token0");
        assertEq(token1.balanceOf(address(this)), 0, "User should have spent all token1");
    }

    function testRevert_When_Invalid_Action() public {
        // 1. Arrange: Prepare invalid callback data
        uint8 invalidAction = 99; // An action that doesn't exist in the Actions enum
        bytes memory params = abi.encode("invalid params");
        bytes memory data = abi.encode(invalidAction, params);

        // 2. Act & Assert
        vm.expectRevert();
        pairPositionManager.unlockCallback(data);
    }

    function test_RevertIf_RemoveLiquidityWithInvalidTokenId() public {
        // 1. Arrange: Add liquidity to create a position
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 10e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        (, uint128 liquidityAdded) = pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        // 2. Act & Assert: Expect revert when removing liquidity with an invalid tokenId
        uint256 invalidTokenId = 999;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, invalidTokenId));
        pairPositionManager.removeLiquidity(invalidTokenId, liquidityAdded, 0, 0);
    }

    function test_RevertIf_IncreaseLiquidityWithInvalidTokenId() public {
        // 1. Arrange: Add liquidity to create a position
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 10e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        // 2. Act & Assert: Expect revert when increasing liquidity with an invalid tokenId
        uint256 invalidTokenId = 999;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, invalidTokenId));
        pairPositionManager.increaseLiquidity(invalidTokenId, 1e18, 1e18, 0, 0);
    }

    function test_RevertIf_ExactInputWithTooHighAmountOutMin() public {
        // 1. Arrange: Add liquidity
        uint256 amount0ToAdd = 100e18;
        uint256 amount1ToAdd = 100e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        // 2. Arrange: Prepare for swap
        uint256 amountIn = 10e18;
        token0.mint(address(this), amountIn);
        PoolId poolId = key.toId();

        IPairPositionManager.SwapInputParams memory params = IPairPositionManager.SwapInputParams({
            poolId: poolId,
            zeroForOne: true,
            to: address(this),
            amountIn: amountIn,
            amountOutMin: 100e18, // Unrealistic minimum output
            deadline: block.timestamp + 1
        });

        // 3. Act & Assert
        vm.expectRevert(bytes4(keccak256("PriceSlippageTooHigh()")));
        pairPositionManager.exactInput(params);
    }

    function test_RevertIf_ExactOutputWithTooLowAmountInMax() public {
        // 1. Arrange: Add liquidity
        uint256 amount0ToAdd = 100e18;
        uint256 amount1ToAdd = 100e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        // 2. Arrange: Prepare for swap
        uint256 amountOut = 10e18;
        token0.mint(address(this), 5e18); // Mint insufficient token0
        PoolId poolId = key.toId();

        IPairPositionManager.SwapOutputParams memory params = IPairPositionManager.SwapOutputParams({
            poolId: poolId,
            zeroForOne: true,
            to: address(this),
            amountInMax: 5e18, // Insufficient max input
            amountOut: amountOut,
            deadline: block.timestamp + 1
        });

        // 3. Act & Assert
        vm.expectRevert(bytes4(keccak256("PriceSlippageTooHigh()")));
        pairPositionManager.exactOutput(params);
    }

    function test_RevertIf_AddLiquidityWithTooHighAmountMin() public {
        // 1. Arrange
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 10e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);

        // 2. Act & Assert
        vm.expectRevert(bytes4(keccak256("PriceSlippageTooHigh()")));
        pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, amount0ToAdd + 1, 0);
    }

    function test_RevertIf_RemoveLiquidityWithTooHighAmountMin() public {
        // 1. Arrange: Add liquidity
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 10e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        (uint256 tokenId, uint128 liquidity) = pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        // 2. Act & Assert
        vm.expectRevert(bytes4(keccak256("PriceSlippageTooHigh()")));
        pairPositionManager.removeLiquidity(tokenId, liquidity, amount0ToAdd + 1, 0);
    }

    function test_RevertIf_IncreaseLiquidityWithTooHighAmountMin() public {
        // 1. Arrange: Add liquidity
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 10e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        (uint256 tokenId,) = pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        // 2. Arrange: Prepare for increasing liquidity
        uint256 increaseAmount0 = 5e18;
        uint256 increaseAmount1 = 5e18;
        token0.mint(address(this), increaseAmount0);
        token1.mint(address(this), increaseAmount1);

        // 3. Act & Assert
        vm.expectRevert(bytes4(keccak256("PriceSlippageTooHigh()")));
        pairPositionManager.increaseLiquidity(tokenId, increaseAmount0, increaseAmount1, increaseAmount0 + 1, 0);
    }
}
