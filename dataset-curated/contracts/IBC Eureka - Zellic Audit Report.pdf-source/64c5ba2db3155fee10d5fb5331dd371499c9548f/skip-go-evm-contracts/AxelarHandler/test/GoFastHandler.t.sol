// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GoFastHandler} from "../src/GoFastHandler.sol";
import {IFastTransferGateway} from "../src/interfaces/IFastTransferGateway.sol";

contract GoFastHandlerTest is Test {
    uint256 arbitrumFork;

    address fastTransferGateway;
    address uniswapRouter;
    address usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    GoFastHandler handler;

    address alice;

    function setUp() public {
        arbitrumFork = vm.createFork(vm.envString("RPC_URL"));

        vm.selectFork(arbitrumFork);
        vm.rollFork(242534997);

        fastTransferGateway = address(0xC);
        uniswapRouter = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

        GoFastHandler handlerImpl = new GoFastHandler();
        ERC1967Proxy handlerProxy = new ERC1967Proxy(
            address(handlerImpl),
            abi.encodeWithSignature("initialize(address,address)", uniswapRouter, fastTransferGateway)
        );
        handler = GoFastHandler(payable(address(handlerProxy)));

        alice = makeAddr("alice");
    }

    function testSwapAndSubmitOrderERC20() public {
        address tokenIn = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        uint256 amountIn = 1 ether;
        uint256 fastTransferFee = 1_000_000; // 1 USDC
        uint256 solverFeeBPS = 10; // 0.1%
        uint32 destinationDomain = 10;
        uint64 timeoutTimestamp = uint64(block.timestamp + 100);
        bytes32 sender = keccak256("sender");
        bytes32 recipient = keccak256("recipient");

        bytes memory swapCalldata = _encodeSwapExactInputCalldata(tokenIn, usdc, 500, address(handler), amountIn, 0, 0);

        deal(tokenIn, alice, amountIn);

        vm.mockCall(fastTransferGateway, abi.encodeWithSelector(IFastTransferGateway.token.selector), abi.encode(usdc));

        vm.mockCall(
            fastTransferGateway,
            abi.encodeWithSelector(
                IFastTransferGateway.submitOrder.selector,
                sender,
                recipient,
                2702776834,
                2699074058,
                destinationDomain,
                timeoutTimestamp,
                ""
            ),
            abi.encode(keccak256("orderId"))
        );

        vm.startPrank(alice);
        IERC20(tokenIn).approve(address(handler), amountIn);

        bytes32 orderId = handler.swapAndSubmitOrder(
            tokenIn,
            amountIn,
            swapCalldata,
            fastTransferFee,
            solverFeeBPS,
            sender,
            recipient,
            destinationDomain,
            timeoutTimestamp,
            ""
        );
        vm.stopPrank();

        assertEq(orderId, keccak256("orderId"));
    }

    function testSwapAndSubmitOrderUSDT() public {
        address tokenIn = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT
        uint256 amountIn = 100_000_000;
        uint256 fastTransferFee = 1_000_000; // 1 USDC
        uint256 solverFeeBPS = 10; // 0.1%
        uint32 destinationDomain = 10;
        uint64 timeoutTimestamp = uint64(block.timestamp + 100);
        bytes32 sender = keccak256("sender");
        bytes32 recipient = keccak256("recipient");

        bytes memory swapCalldata = _encodeSwapExactInputCalldata(tokenIn, usdc, 500, address(handler), amountIn, 0, 0);

        deal(tokenIn, alice, amountIn);

        vm.mockCall(fastTransferGateway, abi.encodeWithSelector(IFastTransferGateway.token.selector), abi.encode(usdc));

        vm.mockCall(
            fastTransferGateway,
            abi.encodeWithSelector(
                IFastTransferGateway.submitOrder.selector,
                sender,
                recipient,
                99963678,
                98863715,
                destinationDomain,
                timeoutTimestamp,
                ""
            ),
            abi.encode(keccak256("orderId"))
        );

        vm.startPrank(alice);
        IERC20(tokenIn).approve(address(handler), amountIn);

        bytes32 orderId = handler.swapAndSubmitOrder(
            tokenIn,
            amountIn,
            swapCalldata,
            fastTransferFee,
            solverFeeBPS,
            sender,
            recipient,
            destinationDomain,
            timeoutTimestamp,
            ""
        );
        vm.stopPrank();

        assertEq(orderId, keccak256("orderId"));
    }

    function testSwapAndSubmitOrderNative() public {
        address tokenIn = address(0); // ETH
        uint256 amountIn = 1 ether;
        uint256 fastTransferFee = 1_000_000; // 1 USDC
        uint256 solverFeeBPS = 10; // 0.1%
        uint32 destinationDomain = 10;
        uint64 timeoutTimestamp = uint64(block.timestamp + 100);
        bytes32 sender = keccak256("sender");
        bytes32 recipient = keccak256("recipient");

        bytes memory swapCalldata = _encodeSwapExactInputCalldata(
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, usdc, 500, address(handler), amountIn, 0, 0
        );

        deal(alice, amountIn);

        vm.mockCall(fastTransferGateway, abi.encodeWithSelector(IFastTransferGateway.token.selector), abi.encode(usdc));

        vm.mockCall(
            fastTransferGateway,
            abi.encodeWithSelector(
                IFastTransferGateway.submitOrder.selector,
                sender,
                recipient,
                2702776834,
                2699074058,
                destinationDomain,
                timeoutTimestamp,
                ""
            ),
            abi.encode(keccak256("orderId"))
        );

        vm.startPrank(alice);
        bytes32 orderId = handler.swapAndSubmitOrder{value: amountIn}(
            tokenIn,
            amountIn,
            swapCalldata,
            fastTransferFee,
            solverFeeBPS,
            sender,
            recipient,
            destinationDomain,
            timeoutTimestamp,
            ""
        );
        vm.stopPrank();

        assertEq(orderId, keccak256("orderId"));
    }

    function testSwapAndSubmitOrderRevertsIfSwapFails() public {
        address tokenIn = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        uint256 amountIn = 1 ether;
        uint256 amountOutMinimum = 1_000_000_000_000; // 1,000,000 USDC
        uint256 fastTransferFee = 1_000_000; // 1 USDC
        uint256 solverFeeBPS = 10; // 0.1%
        uint32 destinationDomain = 10;
        uint64 timeoutTimestamp = uint64(block.timestamp + 100);
        bytes32 sender = keccak256("sender");
        bytes32 recipient = keccak256("recipient");

        bytes memory swapCalldata =
            _encodeSwapExactInputCalldata(tokenIn, usdc, 500, address(handler), amountIn, amountOutMinimum, 0);

        deal(tokenIn, alice, amountIn);

        vm.mockCall(fastTransferGateway, abi.encodeWithSelector(IFastTransferGateway.token.selector), abi.encode(usdc));

        vm.startPrank(alice);
        IERC20(tokenIn).approve(address(handler), amountIn);

        vm.expectRevert("Too little received");
        handler.swapAndSubmitOrder(
            tokenIn,
            amountIn,
            swapCalldata,
            fastTransferFee,
            solverFeeBPS,
            sender,
            recipient,
            destinationDomain,
            timeoutTimestamp,
            ""
        );
        vm.stopPrank();
    }

    function testSwapAndSubmitOrderRevertsIfSwapAmountOutIsLessThanFastTransferFee() public {
        address tokenIn = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        uint256 amountIn = 1 ether;
        uint256 fastTransferFee = 3000_000_000; // 3000 USDC
        uint256 solverFeeBPS = 10; // 0.1%
        uint32 destinationDomain = 10;
        uint64 timeoutTimestamp = uint64(block.timestamp + 100);
        bytes32 sender = keccak256("sender");
        bytes32 recipient = keccak256("recipient");

        bytes memory swapCalldata = _encodeSwapExactInputCalldata(tokenIn, usdc, 500, address(handler), amountIn, 0, 0);

        deal(tokenIn, alice, amountIn);

        vm.mockCall(fastTransferGateway, abi.encodeWithSelector(IFastTransferGateway.token.selector), abi.encode(usdc));

        vm.startPrank(alice);
        IERC20(tokenIn).approve(address(handler), amountIn);

        vm.expectRevert("amount received from swap is less than fee");
        handler.swapAndSubmitOrder(
            tokenIn,
            amountIn,
            swapCalldata,
            fastTransferFee,
            solverFeeBPS,
            sender,
            recipient,
            destinationDomain,
            timeoutTimestamp,
            ""
        );
        vm.stopPrank();
    }

    function testSwapAndSubmitOrderRevertsIfSolverFeeIsZero() public {
        address tokenIn = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        uint256 amountIn = 1 ether;
        uint256 fastTransferFee = 1_000_000; // 1 USDC
        uint256 solverFeeBPS = 0;
        uint32 destinationDomain = 10;
        uint64 timeoutTimestamp = uint64(block.timestamp + 100);
        bytes32 sender = keccak256("sender");
        bytes32 recipient = keccak256("recipient");

        bytes memory swapCalldata = _encodeSwapExactInputCalldata(tokenIn, usdc, 500, address(handler), amountIn, 0, 0);

        deal(tokenIn, alice, amountIn);

        vm.mockCall(fastTransferGateway, abi.encodeWithSelector(IFastTransferGateway.token.selector), abi.encode(usdc));

        vm.startPrank(alice);
        IERC20(tokenIn).approve(address(handler), amountIn);

        vm.expectRevert("solver fee cannot be zero");
        handler.swapAndSubmitOrder(
            tokenIn,
            amountIn,
            swapCalldata,
            fastTransferFee,
            solverFeeBPS,
            sender,
            recipient,
            destinationDomain,
            timeoutTimestamp,
            ""
        );
        vm.stopPrank();
    }

    function _encodeSwapExactInputCalldata(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            bytes4(0x04e45aaf), tokenIn, tokenOut, fee, recipient, amountIn, amountOutMinimum, sqrtPriceLimitX96
        );
    }
}
