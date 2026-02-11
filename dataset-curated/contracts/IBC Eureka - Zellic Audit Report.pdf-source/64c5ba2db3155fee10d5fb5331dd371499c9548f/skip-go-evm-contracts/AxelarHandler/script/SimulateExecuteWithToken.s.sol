// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import {Environment} from "test/Environment.sol";
import {MockGateway} from "test/mocks/MockGateway.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AxelarHandler} from "src/AxelarHandler.sol";

contract SimulateExecuteWithToken is Script, Test {
    AxelarHandler public handler;
    Environment public env;
    MockGateway public mockGateway;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        env = new Environment();
        env.setEnv(block.chainid);

        mockGateway = new MockGateway();

        address gateway = address(mockGateway);
        address gasService = env.gasService();
        address swapRouter = env.swapRouter();
        string memory wethSymbol = env.wethSymbol();

        AxelarHandler handlerImpl = new AxelarHandler();
        ERC1967Proxy handlerProxy = new ERC1967Proxy(
            address(handlerImpl),
            abi.encodeWithSignature("initialize(address,address,string)", gateway, gasService, wethSymbol)
        );
        handler = AxelarHandler(payable(address(handlerProxy)));

        handler.setSwapRouter(swapRouter);
    }

    function run() public {
        string memory tokenInputSymbol = "WETH";
        address tokenIn = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address tokenOut = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; //USDC
        address destination = 0x0000000000000000000000000000000000000048;
        uint256 amountIn = 1 ether;
        uint256 amountOutMin = 1_000 * 1e6;
        bool unwrap = false;

        mockGateway.saveTokenAddress(tokenInputSymbol, tokenIn);
        deal(address(tokenIn), address(handler), amountIn);

        bytes memory swapPayload = abi.encode(uint8(0), tokenOut, amountOutMin, abi.encode(uint24(3000), uint160(0)));
        bytes memory payload = abi.encode(uint8(2), abi.encode(destination, unwrap, swapPayload));

        console2.logBytes(payload);

        console2.log("Token Out Destination Balance Before: %s", IERC20(tokenOut).balanceOf(destination));

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, tokenInputSymbol, amountIn
        );

        console2.log("Token Out Destination Balance After: %s", IERC20(tokenOut).balanceOf(destination));
    }

    function run(
        bytes memory payload,
        string memory tokenSymbol,
        address token,
        address tokenOut,
        address destination,
        uint256 amount
    ) public {
        mockGateway.saveTokenAddress(tokenSymbol, token);
        deal(address(token), address(handler), amount);

        console2.log("Token Out Destination Balance Before: %s", IERC20(tokenOut).balanceOf(destination));

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, tokenSymbol, amount
        );

        console2.log("Token Out Destination Balance After: %s", IERC20(tokenOut).balanceOf(destination));
    }
}
