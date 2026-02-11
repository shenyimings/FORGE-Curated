// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AlphaProVault, VaultParams} from "../contracts/AlphaProVault.sol";
import {AlphaProVaultFactory} from "../contracts/AlphaProVaultFactory.sol";
import {AlphaProPeriphery} from "../contracts/AlphaProPeriphery.sol";

import {ManagerStore} from "../contracts/ManagerStore.sol";
import {Constants} from "./Constants.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

abstract contract VaultTestUtils is Test {
    AlphaProVaultFactory vaultFactory;
    AlphaProVault vault;
    AlphaProPeriphery alphaProPeriphery;
    ManagerStore managerStore;

    uint24 constant PROTOCOL_FEE = 30000;

    address constant UNISWAP_V3_FACTORY = address(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address constant UNISWAP_V3_ROUTER = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    uint24 constant POOL_FEE = 3000;

    address owner = makeAddr("owner");
    address other = makeAddr("other");
    address initialDepositor = makeAddr("initialDepositor");

    function deployManagerStore() internal {
        vm.prank(owner);
        managerStore = new ManagerStore();
    }

    function deployPeriphery() internal {
        vm.prank(owner);
        alphaProPeriphery = new AlphaProPeriphery();
    }

    function swapForwardAndBack(bool reverse) internal {
        (address tokenIn, address tokenOut) = reverse ? (USDC, WETH) : (WETH, USDC);

        uint256 amountInStart = reverse ? 105000 * 1e6 : 50 ether;

        // Get intermediate token balance before swap
        uint256 intermediateTokenBalanceBefore = IERC20(tokenOut).balanceOf(owner);

        // First swap
        swapToken(tokenIn, tokenOut, amountInStart, owner);

        // Calculate the delta from the first swap
        uint256 intermediateAmountAfterSwap = IERC20(tokenOut).balanceOf(owner);
        uint256 intermediateAmountDelta = intermediateAmountAfterSwap - intermediateTokenBalanceBefore;

        // Second swap with adjusted amount (multiplied by 10000/9985)
        uint256 adjustedAmount = (intermediateAmountDelta * 10000) / 9985;
        swapToken(tokenOut, tokenIn, adjustedAmount, owner);
    }

    function swapToken(address tokenIn, address tokenOut, uint256 amountIn, address from_)
        internal
        returns (uint256 amountOut)
    {
        deal(tokenIn, from_, amountIn);
        vm.startPrank(from_);
        IERC20(tokenIn).approve(UNISWAP_V3_ROUTER, type(uint256).max);
        amountOut = ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(
            ISwapRouter.ExactInputSingleParams(tokenIn, tokenOut, POOL_FEE, from_, type(uint256).max, amountIn, 0, 0)
        );
        vm.stopPrank();
    }

    function deployFactory() internal {
        AlphaProVault templateVault = new AlphaProVault();
        vaultFactory = new AlphaProVaultFactory(address(templateVault), owner, PROTOCOL_FEE);

        address pool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(WETH, USDC, POOL_FEE);

        VaultParams memory vaultParams = VaultParams(
            pool,
            owner,
            0,
            type(uint128).max - 1,
            0,
            72000,
            1200,
            600,
            0,
            Constants.MIN_TICK_MOVE,
            Constants.MAX_TWAP_DEVIATION,
            Constants.TWAP_DURATION,
            "AV_TEST",
            "AV_TEST"
        );

        vm.startPrank(owner);
        vaultFactory.setAllowedFactory(UNISWAP_V3_FACTORY, true);
        address vaultAddress = vaultFactory.createVault(vaultParams);
        vault = AlphaProVault(vaultAddress);
        vault.setDepositDelegate(address(0));
        vault.setRebalanceDelegate(address(0));

        IERC20(USDC).approve(vaultAddress, type(uint256).max);
        IERC20(WETH).approve(vaultAddress, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(other);
        IERC20(USDC).approve(vaultAddress, type(uint256).max);
        IERC20(WETH).approve(vaultAddress, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(initialDepositor);
        IERC20(USDC).approve(vaultAddress, type(uint256).max);
        IERC20(WETH).approve(vaultAddress, type(uint256).max);
        vm.stopPrank();
    }

    function depositInFactory() internal {
        uint256 usdcAmount = 21000 * 1e6;
        uint256 wethAmount = 10 ether;

        depositAndRebalance(initialDepositor, usdcAmount, wethAmount);
    }

    function depositAndRebalance(address _address, uint256 usdcAmount, uint256 wethAmount)
        internal
        returns (uint256 shares)
    {
        deal(USDC, _address, usdcAmount);
        deal(WETH, _address, wethAmount);

        vm.prank(_address);
        (shares,,) = vault.deposit(usdcAmount, wethAmount, 0, 0, _address);
        vault.rebalance();
    }

    function prepareTokens() internal {
        deal(USDC, owner, type(uint256).max / 2);
        deal(WETH, owner, type(uint256).max / 2);
        deal(USDC, other, type(uint256).max / 2);
        deal(WETH, other, type(uint256).max / 2);
    }
}
