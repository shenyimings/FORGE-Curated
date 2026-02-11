// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "./Environment.sol";
import {MockGateway} from "./mocks/MockGateway.sol";
import {MockRouter} from "./mocks/MockRouter.sol";

import {AxelarHandler} from "src/AxelarHandler.sol";
import {IAxelarExecutable} from "lib/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarExecutable.sol";

import {IAxelarGateway} from "lib/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ISwapRouter02} from "src/interfaces/ISwapRouter02.sol";

contract AxelarHandlerTest is Test {
    string public constant FORK_CHAIN = "mainnet";

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public immutable ALICE = makeAddr("ALICE");
    address public immutable BOB = makeAddr("BOB");

    bool public isForked;

    AxelarHandler public handler;
    IAxelarGateway public gateway;
    ISwapRouter02 public router;

    modifier forked() {
        isForked = true;
        Environment env = new Environment();
        env.setEnv(1);

        vm.makePersistent(address(env));
        vm.createSelectFork(vm.rpcUrl(FORK_CHAIN), 20581168);

        gateway = IAxelarGateway(env.gateway());
        address gasService = env.gasService();
        router = ISwapRouter02(env.swapRouter());

        string memory wethSymbol = "WETH";

        AxelarHandler handlerImpl = new AxelarHandler();
        ERC1967Proxy handlerProxy = new ERC1967Proxy(
            address(handlerImpl),
            abi.encodeWithSignature("initialize(address,address,string)", address(gateway), gasService, wethSymbol)
        );
        handler = AxelarHandler(payable(address(handlerProxy)));

        handler.setSwapRouter(address(router));

        vm.label(address(handler), "HANDLER");
        vm.label(address(gateway), "GATEWAY");
        vm.label(gasService, "GAS SERVICE");
        vm.label(gateway.tokenAddresses(wethSymbol), "WETH");

        _;

        isForked = false;
    }

    modifier local() {
        gateway = IAxelarGateway(address(new MockGateway()));
        address gasService = makeAddr("GAS SERVICE");

        router = ISwapRouter02(address(new MockRouter()));

        string memory wethSymbol = "WETH";

        AxelarHandler handlerImpl = new AxelarHandler();
        ERC1967Proxy handlerProxy = new ERC1967Proxy(
            address(handlerImpl),
            abi.encodeWithSignature("initialize(address,address,string)", address(gateway), gasService, wethSymbol)
        );
        handler = AxelarHandler(payable(address(handlerProxy)));

        handler.setSwapRouter(address(router));

        vm.label(address(handler), "HANDLER");
        vm.label(address(gateway), "GATEWAY");
        vm.label(gateway.tokenAddresses(wethSymbol), "WETH");

        _;
    }

    function test_forked_sendNativeToken() public forked {
        vm.deal(ALICE, 10 ether);
        assertEq(ALICE.balance, 10 ether, "Native balance before sending.");

        vm.startPrank(ALICE);
        handler.sendNativeToken{value: 10 ether}("arbitrum", vm.toString(BOB));
        vm.stopPrank();

        assertEq(ALICE.balance, 0, "Native balance after sending.");
        assertEq(address(handler).balance, 0, "Ether left in the contract.");
    }

    function test_forked_sendNativeToken_NoAmount() public forked {
        vm.deal(ALICE, 10 ether);
        assertEq(ALICE.balance, 10 ether, "Native balance before sending.");

        vm.startPrank(ALICE);
        vm.expectRevert(AxelarHandler.ZeroNativeSent.selector);
        handler.sendNativeToken{value: 0}("arbitrum", vm.toString(BOB));
        vm.stopPrank();
    }

    function test_forked_sendERC20Token() public forked {
        string memory symbol = "WETH";
        IERC20Upgradeable token = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses(symbol));

        deal(address(token), BOB, 100 ether);

        vm.prank(BOB);
        token.approve(address(handler), type(uint256).max);

        vm.prank(BOB);
        handler.sendERC20Token("arbitrum", vm.toString(ALICE), symbol, 20 ether);

        assertEq(token.balanceOf(BOB), 80 ether, "User balance after sending.");
        assertEq(token.balanceOf(address(handler)), 0, "Tokens left in the contract.");
    }

    function test_forked_sendERC20Token_WrongSymbol() public forked {
        string memory symbol = "WBTCx";
        vm.startPrank(ALICE);
        vm.expectRevert(AxelarHandler.TokenNotSupported.selector);
        handler.sendERC20Token("arbitrum", vm.toString(BOB), symbol, 50 ether);
        vm.stopPrank();
    }

    function test_forked_sendERC20Token_NoAllowance() public forked {
        string memory symbol = "WBTC";
        IERC20Upgradeable token = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses(symbol));

        deal(address(token), ALICE, 100 ether);
        assertEq(token.balanceOf(ALICE), 100 ether, "Balance before sending.");

        vm.startPrank(ALICE);

        token.approve(address(handler), 49 ether);
        vm.expectRevert();
        handler.sendERC20Token("arbitrum", vm.toString(BOB), symbol, 50 ether);
        vm.stopPrank();
    }

    function test_forked_gmpTransferNativeToken() public forked {
        vm.deal(ALICE, 100 ether);
        assertEq(ALICE.balance, 100 ether, "Native balance before sending.");

        vm.startPrank(ALICE);
        handler.gmpTransferNativeToken{value: 50.5 ether}(
            "arbitrum", vm.toString(address(this)), abi.encodePacked(address(BOB)), 50 ether, 0.5 ether
        );
        vm.stopPrank();

        assertEq(ALICE.balance, 49.5 ether, "Native balance after sending.");
        assertEq(address(handler).balance, 0, "Ether left in the contract.");
    }

    function test_forked_gmpTransferNativeToken_ZeroGas() public forked {
        vm.deal(ALICE, 100 ether);
        assertEq(ALICE.balance, 100 ether, "Native balance before sending.");

        vm.startPrank(ALICE);
        vm.expectRevert(AxelarHandler.ZeroGasAmount.selector);
        handler.gmpTransferNativeToken{value: 50 ether}(
            "arbitrum", vm.toString(address(this)), abi.encodePacked(address(BOB)), 50 ether, 0 ether
        );
        vm.stopPrank();
    }

    function test_forked_gmpTransferNativeToken_ZeroAmount() public forked {
        vm.deal(ALICE, 100 ether);
        assertEq(ALICE.balance, 100 ether, "Native balance before sending.");

        vm.startPrank(ALICE);
        vm.expectRevert(AxelarHandler.ZeroAmount.selector);
        handler.gmpTransferNativeToken{value: 0.5 ether}(
            "arbitrum", vm.toString(address(this)), abi.encodePacked(address(BOB)), 0, 0.5 ether
        );
        vm.stopPrank();
    }

    function test_forked_gmpTransferNativeToken_AmountMismatch() public forked {
        vm.deal(ALICE, 100 ether);
        assertEq(ALICE.balance, 100 ether, "Native balance before sending.");

        vm.startPrank(ALICE);
        vm.expectRevert(AxelarHandler.NativeSentDoesNotMatchAmounts.selector);
        handler.gmpTransferNativeToken{value: 50 ether}(
            "arbitrum", vm.toString(address(this)), abi.encodePacked(address(BOB)), 50 ether, 0.5 ether
        );
        vm.stopPrank();
    }

    function test_forked_gmpTransferERC20Token() public forked {
        vm.deal(ALICE, 25 ether);
        assertEq(ALICE.balance, 25 ether, "Native balance before sending.");

        string memory symbol = "WBTC";
        IERC20Upgradeable token = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses(symbol));

        deal(address(token), ALICE, 5000 ether);
        assertEq(token.balanceOf(ALICE), 5000 ether);

        vm.startPrank(ALICE);
        token.approve(address(handler), 5000 ether);
        handler.gmpTransferERC20Token{value: 25 ether}(
            "arbitrum", vm.toString(address(this)), abi.encodePacked(address(BOB)), symbol, 4900 ether, 25 ether
        );
        vm.stopPrank();

        assertEq(ALICE.balance, 0, "Native balance after sending.");
        assertEq(token.balanceOf(ALICE), 100 ether, "Token balance after sending.");
        assertEq(address(handler).balance, 0, "Ether left in the contract.");
        assertEq(token.balanceOf(address(handler)), 0, "Tokens left in the contract.");
    }

    function test_forked_gmpTransferERC20Token_GasMismatch() public forked {
        vm.deal(ALICE, 0.5 ether);
        assertEq(ALICE.balance, 0.5 ether, "Native balance before sending.");

        string memory symbol = "WBTC";
        IERC20Upgradeable token = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses(symbol));

        deal(address(token), ALICE, 100 ether);
        assertEq(token.balanceOf(ALICE), 100 ether);

        vm.startPrank(ALICE);
        token.approve(address(handler), 100 ether);
        vm.expectRevert(AxelarHandler.NativeSentDoesNotMatchAmounts.selector);
        handler.gmpTransferERC20Token{value: 0.25 ether}(
            "arbitrum", vm.toString(address(this)), abi.encodePacked(address(BOB)), symbol, 50 ether, 0.5 ether
        );
        vm.stopPrank();
    }

    function test_forked_gmpTransferERC20Token_ZeroGas() public forked {
        vm.deal(ALICE, 0.5 ether);
        assertEq(ALICE.balance, 0.5 ether, "Native balance before sending.");

        string memory symbol = "WBTC";
        IERC20Upgradeable token = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses(symbol));

        deal(address(token), ALICE, 100 ether);
        assertEq(token.balanceOf(ALICE), 100 ether);

        vm.startPrank(ALICE);
        token.approve(address(handler), 100 ether);
        vm.expectRevert(AxelarHandler.ZeroGasAmount.selector);
        handler.gmpTransferERC20Token(
            "arbitrum", vm.toString(address(this)), abi.encodePacked(address(BOB)), symbol, 50 ether, 0
        );
        vm.stopPrank();
    }

    function test_forked_gmpTransferERC20TokenGasTokenPayment() public forked {
        string memory symbol = "WBTC";
        IERC20Upgradeable token = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses(symbol));
        vm.label(address(token), "WBTC");

        deal(address(token), ALICE, 100 ether);
        assertEq(token.balanceOf(ALICE), 100 ether);

        vm.startPrank(ALICE);
        token.approve(address(handler), 100 ether);
        handler.gmpTransferERC20TokenGasTokenPayment(
            "arbitrum", vm.toString(address(this)), abi.encodePacked(address(BOB)), symbol, 75 ether, 25 ether
        );
        vm.stopPrank();

        assertEq(token.balanceOf(ALICE), 0, "Token balance after sending.");
        assertEq(token.balanceOf(address(handler)), 0, "Tokens left in the contract.");
    }

    function test_forked_executeWithToken_nonunwrap_nonWETH() public forked {
        string memory symbol = "WBTC";
        IERC20Upgradeable token = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses(symbol));
        vm.label(address(token), "WBTC");

        deal(address(token), address(this), 100 ether);
        token.transfer(address(handler), 100 ether);

        assertEq(token.balanceOf(address(handler)), 100 ether, "Handler balance before");

        assertEq(token.balanceOf(ALICE), 0, "Alice balance before");

        deployCodeTo("MockGateway.sol", address(gateway));
        MockGateway mockGateway = MockGateway(address(gateway));
        mockGateway.saveTokenAddress(symbol, address(token));

        bytes memory payload = abi.encode(uint8(0), abi.encode(ALICE));

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbol, 100 ether
        );

        assertEq(token.balanceOf(address(handler)), 0, "Handler balance after");

        assertEq(token.balanceOf(ALICE), 100 ether, "Alice balance after");
    }

    function test_forked_executeWithToken_unwrap_nonWETH() public forked {
        string memory symbol = "WBTC";
        IERC20Upgradeable token = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses(symbol));
        vm.label(address(token), "WBTC");

        deal(address(token), address(this), 100 ether);
        token.transfer(address(handler), 100 ether);

        assertEq(token.balanceOf(address(handler)), 100 ether, "Handler balance before");

        assertEq(token.balanceOf(ALICE), 0, "Alice balance before");

        deployCodeTo("MockGateway.sol", address(gateway));
        MockGateway mockGateway = MockGateway(address(gateway));
        mockGateway.saveTokenAddress(symbol, address(token));

        bytes memory payload = abi.encode(uint8(1), abi.encode(ALICE));

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbol, 100 ether
        );

        assertEq(token.balanceOf(address(handler)), 0, "Handler balance after");

        assertEq(token.balanceOf(ALICE), 100 ether, "Alice balance after");
    }

    function test_forked_executeWithToken_unwrap_WETH() public forked {
        string memory symbol = "WETH";
        IERC20Upgradeable token = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses(symbol));
        vm.label(address(token), "WETH");

        deal(address(token), address(this), 100 ether);
        token.transfer(address(handler), 100 ether);

        assertEq(token.balanceOf(address(handler)), 100 ether, "Handler balance before");

        assertEq(token.balanceOf(ALICE), 0, "Alice token balance before");
        assertEq(ALICE.balance, 0, "Alice native balance before");

        deployCodeTo("MockGateway.sol", address(gateway));
        MockGateway mockGateway = MockGateway(address(gateway));
        mockGateway.saveTokenAddress(symbol, address(token));

        bytes memory payload = abi.encode(uint8(1), abi.encode(ALICE));

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbol, 100 ether
        );

        assertEq(token.balanceOf(address(handler)), 0, "Handler balance after");
        assertEq(token.balanceOf(ALICE), 0, "Alice token balance after");
        assertEq(ALICE.balance, 100 ether, "Alice native balance after");
    }

    function test_forked_executeWithToken_exactInputSingleSwap() public forked {
        uint256 amountIn = 1 ether; // 1 WETH
        uint256 amountOutMin = 1_000 * 1e6; // 1,000 USDC
        address destination = ALICE;
        bool unwrap = false;

        string memory symbolIn = "WETH";
        address tokenIn = IAxelarGateway(gateway).tokenAddresses(symbolIn);
        vm.label(address(tokenIn), symbolIn);

        string memory symbolOut = "USDC";
        address tokenOut = IAxelarGateway(gateway).tokenAddresses(symbolOut);
        vm.label(address(tokenOut), symbolOut);

        _execute_exactInputSingleSwap(symbolIn, tokenIn, tokenOut, amountIn, amountOutMin, destination, unwrap);
    }

    function test_forked_executeWithToken_exactInputSingleSwap_unwrap() public forked {
        uint256 amountIn = 5_000 ether; // 5,000 USDT
        uint256 amountOutMin = 1.5 ether; // 1.5 ETH
        address destination = ALICE;
        bool unwrap = true;

        string memory symbolIn = "USDT";
        address tokenIn = IAxelarGateway(gateway).tokenAddresses(symbolIn);
        vm.label(address(tokenIn), symbolIn);

        string memory symbolOut = "WETH";
        address tokenOut = IAxelarGateway(gateway).tokenAddresses(symbolOut);
        vm.label(address(tokenOut), symbolOut);

        _execute_exactInputSingleSwap(symbolIn, tokenIn, tokenOut, amountIn, amountOutMin, destination, unwrap);
    }

    function test_forked_executeWithToken_exactInputSingleSwap_unwrap_noWETH() public forked {
        uint256 amountIn = 1 ether; // 0.1 WBTC
        uint256 amountOutMin = 1_000 * 1e6; // 1,000 USDCs
        address destination = ALICE;
        bool unwrap = true;

        string memory symbolIn = "WETH";
        address tokenIn = IAxelarGateway(gateway).tokenAddresses(symbolIn);
        vm.label(address(tokenIn), symbolIn);

        string memory symbolOut = "USDC";
        address tokenOut = IAxelarGateway(gateway).tokenAddresses(symbolOut);
        vm.label(address(tokenOut), symbolOut);

        _mockGateway(symbolIn, tokenIn, amountIn);

        IERC20 inputToken = IERC20(tokenIn);
        IERC20 outputToken = IERC20(tokenOut);

        _assertPreSwap(inputToken, outputToken, amountIn, destination);

        bytes memory payload;
        {
            bytes memory swapPayload = _build_exactInputSingle(tokenOut, amountOutMin, 3000);
            payload = _build_executeWithToken(destination, unwrap, swapPayload);
        }
        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbolIn, amountIn
        );

        _assertPostSwapExactInput(inputToken, outputToken, amountOutMin, destination, false);
    }

    function test_forked_executeWithToken_exactInputSwap() public forked {
        uint256 amountIn = 1 ether; // 1 WETH
        uint256 amountOutMin = 1_000 * 1e6; // 1,000 USDC
        address destination = ALICE;
        bool unwrap = false;

        string memory symbolIn = "WETH";
        address tokenIn = IAxelarGateway(gateway).tokenAddresses(symbolIn);
        vm.label(address(tokenIn), symbolIn);

        string memory symbolOut = "USDC";
        address tokenOut = IAxelarGateway(gateway).tokenAddresses(symbolOut);
        vm.label(address(tokenOut), symbolOut);

        bytes memory path = abi.encodePacked(tokenIn, uint24(500), tokenOut);
        _execute_exactInputSwap(symbolIn, tokenIn, tokenOut, amountIn, amountOutMin, destination, unwrap, path);
    }

    function test_forked_executeWithToken_exactInputSwap_insufficientOutput() public forked {
        uint256 amountIn = 1 ether; // 1 WETH
        uint256 amountOutMin = 4_000 * 1e6; // 1,000 USDC
        address destination = ALICE;
        bool unwrap = false;

        string memory symbolIn = "WETH";

        IERC20 inputToken;
        IERC20 outputToken;
        bytes memory path;
        {
            address tokenIn = IAxelarGateway(gateway).tokenAddresses(symbolIn);
            vm.label(address(tokenIn), symbolIn);
            inputToken = IERC20(tokenIn);

            string memory symbolOut = "USDC";
            address tokenOut = IAxelarGateway(gateway).tokenAddresses(symbolOut);
            vm.label(address(tokenOut), symbolOut);
            outputToken = IERC20(tokenOut);

            _mockGateway(symbolIn, tokenIn, amountIn);

            path = abi.encodePacked(tokenIn, uint24(500), tokenOut);
        }

        _assertPreSwap(inputToken, outputToken, amountIn, destination);

        bytes memory swapPayload = _build_exactInput(address(outputToken), amountOutMin, path);
        bytes memory payload = _build_executeWithToken(destination, unwrap, swapPayload);

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbolIn, amountIn
        );

        _assertNoDust(inputToken);
        _assertNoDust(outputToken);
        _assertNoAllowance(inputToken);

        assertEq(inputToken.balanceOf(destination), amountIn, "Input not refunded upon failed swap");
        assertEq(outputToken.balanceOf(destination), 0, "Existing output after failed swap");
    }

    function test_forked_executeWithToken_exactTokensForTokensSwap() public forked {
        uint256 amountIn = 1 ether; // 1 WETH
        uint256 amountOutMin = 1_000 * 1e6; // 1,000 USDC
        address destination = ALICE;
        bool unwrap = false;

        string memory symbolIn = "WETH";
        address tokenIn = IAxelarGateway(gateway).tokenAddresses(symbolIn);
        vm.label(address(tokenIn), symbolIn);

        string memory symbolOut = "USDC";
        address tokenOut = IAxelarGateway(gateway).tokenAddresses(symbolOut);
        vm.label(address(tokenOut), symbolOut);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        _execute_exactTokensForTokens(symbolIn, tokenIn, tokenOut, amountIn, amountOutMin, destination, unwrap, path);
    }

    function test_forked_executeWithToken_exactOutputSingleSwap() public forked {
        uint256 amountIn = 1 ether; // 1 WETH
        uint256 amountOut = 1_000 * 1e6; // 1,000 USDC
        address destination = ALICE;
        bool unwrap = false;

        string memory symbolIn = "WETH";
        address tokenIn = IAxelarGateway(gateway).tokenAddresses(symbolIn);
        vm.label(address(tokenIn), symbolIn);

        string memory symbolOut = "USDC";
        address tokenOut = IAxelarGateway(gateway).tokenAddresses(symbolOut);
        vm.label(address(tokenOut), symbolOut);

        _execute_exactOutputSingleSwap(symbolIn, tokenIn, tokenOut, amountIn, amountOut, destination, unwrap);
    }

    function test_forked_executeWithToken_exactOutputSwap() public forked {
        uint256 amountIn = 1 ether; // 1 WETH
        uint256 amountOut = 1_000 * 1e6; // 1,000 USDC
        address destination = ALICE;
        bool unwrap = false;

        string memory symbolIn = "WETH";
        address tokenIn = IAxelarGateway(gateway).tokenAddresses(symbolIn);
        vm.label(address(tokenIn), symbolIn);

        string memory symbolOut = "USDC";
        address tokenOut = IAxelarGateway(gateway).tokenAddresses(symbolOut);
        vm.label(address(tokenOut), symbolOut);

        bytes memory path = abi.encodePacked(tokenOut, uint24(500), tokenIn);
        _execute_exactOutputSwap(symbolIn, tokenIn, tokenOut, amountIn, amountOut, destination, unwrap, path);
    }

    function test_forked_executeWithToken_tokensForExactTokensSwap() public forked {
        uint256 amountIn = 1 ether; // 1 WETH
        uint256 amountOut = 1_000 * 1e6; // 1,000 USDC
        address destination = ALICE;
        bool unwrap = false;

        string memory symbolIn = "WETH";
        address tokenIn = IAxelarGateway(gateway).tokenAddresses(symbolIn);
        vm.label(address(tokenIn), symbolIn);

        string memory symbolOut = "USDC";
        address tokenOut = IAxelarGateway(gateway).tokenAddresses(symbolOut);
        vm.label(address(tokenOut), symbolOut);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        _execute_tokensForExactTokens(symbolIn, tokenIn, tokenOut, amountIn, amountOut, destination, unwrap, path);
    }

    function test_forked_executeWithToken_multiSwap() public forked {
        uint256 amountIn = 1 ether; // 1 WETH
        uint256 amountOut = 2_000 * 1e6; // 2,000 USDT
        address destination = ALICE;
        bool unwrap = false;

        string memory symbolIn = "WETH";
        address tokenIn = IAxelarGateway(gateway).tokenAddresses(symbolIn);
        vm.label(address(tokenIn), symbolIn);

        address tokenOut = IAxelarGateway(gateway).tokenAddresses("USDT");

        IERC20 inputToken = IERC20(tokenIn);
        IERC20 outputToken = IERC20(tokenOut);

        bytes memory payload;
        {
            bytes[] memory swaps = new bytes[](2);
            swaps[0] = _build_exactInputSingle(USDC, 2_000 * 1e6, 500);
            swaps[1] = _build_exactOutputSingle(tokenOut, amountOut, 500);

            payload = _build_executeWithToken_multiswap(destination, unwrap, swaps);
        }

        _mockGateway(symbolIn, tokenIn, amountIn);

        _assertPreSwap(inputToken, outputToken, amountIn, destination);

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbolIn, amountIn
        );

        {
            IERC20[] memory tokens = new IERC20[](3);
            tokens[0] = inputToken;
            tokens[1] = IERC20(USDC);
            tokens[2] = outputToken;

            _assertNoDust(tokens);
            _assertNoAllowance(tokens);
        }

        assertEq(outputToken.balanceOf(destination), amountOut, "Output token below minimum");
        assertEq(inputToken.balanceOf(destination), 0, "Input token refunded");
        assertNotEq(IERC20(USDC).balanceOf(destination), 0);

        console2.log("Intermediate refund: ", IERC20(USDC).balanceOf(destination));
    }

    function test_forked_executeWithToken_custom() public forked {
        uint256 inputAmount = 5 ether;
        string memory symbol = "WETH";
        IERC20Upgradeable inputToken = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses(symbol));

        deployCodeTo("MockGateway.sol", address(gateway));
        MockGateway mockGateway = MockGateway(address(gateway));
        mockGateway.saveTokenAddress(symbol, address(inputToken));

        deal(address(inputToken), address(this), inputAmount);
        inputToken.transfer(address(handler), inputAmount);

        bytes memory payload =
            hex"000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000ef211076b8d8b46797e09c9a374fb4cdc1df09160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000004000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000003b9aca000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000002ba0b86991c6218b36c1d19d4a2e9eb0ce3606eb480001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000";

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbol, inputAmount
        );
    }

    function _mockGateway(string memory symbol, address tokenIn, uint256 amountIn) internal {
        deal(tokenIn, address(handler), amountIn);

        if (isForked) {
            deployCodeTo("MockGateway.sol", address(gateway));
        }

        MockGateway mockGateway = MockGateway(address(gateway));
        mockGateway.saveTokenAddress(symbol, tokenIn);
        mockGateway.saveTokenAddress("WETH", WETH);
    }

    function _build_exactInputSingle(address tokenOut, uint256 amountOutMin, uint24 fee)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(uint8(0), tokenOut, amountOutMin, abi.encode(uint24(fee), uint160(0)));
    }

    function _build_exactInput(address tokenOut, uint256 amountOutMin, bytes memory path)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(uint8(1), tokenOut, amountOutMin, path);
    }

    function _build_exactTokensForTokens(address tokenOut, uint256 amountOut, address[] memory path)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(uint8(2), tokenOut, amountOut, abi.encode(path));
    }

    function _build_exactOutputSingle(address tokenOut, uint256 amountOut, uint24 fee)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(uint8(3), tokenOut, amountOut, abi.encode(uint24(fee), uint160(0)));
    }

    function _build_exactOutput(address tokenOut, uint256 amountOut, bytes memory path)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(uint8(4), tokenOut, amountOut, path);
    }

    function _build_tokensForExactTokens(address tokenOut, uint256 amountOut, address[] memory path)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(uint8(5), tokenOut, amountOut, abi.encode(path));
    }

    function _build_executeWithToken(address destination, bool unwrap, bytes memory swapPayload)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(uint8(2), abi.encode(destination, unwrap, swapPayload));
    }

    function _build_executeWithToken_multiswap(address destination, bool unwrap, bytes[] memory swapsPayloads)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(uint8(3), abi.encode(destination, unwrap, swapsPayloads));
    }

    function _execute_exactInputSingleSwap(
        string memory symbol,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address destination,
        bool unwrap
    ) internal {
        _mockGateway(symbol, tokenIn, amountIn);

        IERC20 inputToken = IERC20(tokenIn);
        IERC20 outputToken = IERC20(tokenOut);

        _assertPreSwap(inputToken, outputToken, amountIn, destination);

        bytes memory swapPayload = _build_exactInputSingle(tokenOut, amountOutMin, 3000);
        bytes memory payload = _build_executeWithToken(destination, unwrap, swapPayload);

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbol, amountIn
        );

        _assertPostSwapExactInput(inputToken, outputToken, amountOutMin, destination, unwrap);
    }

    function _execute_exactInputSwap(
        string memory symbol,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address destination,
        bool unwrap,
        bytes memory path
    ) internal {
        _mockGateway(symbol, tokenIn, amountIn);

        IERC20 inputToken = IERC20(tokenIn);
        IERC20 outputToken = IERC20(tokenOut);

        _assertPreSwap(inputToken, outputToken, amountIn, destination);

        bytes memory swapPayload = _build_exactInput(tokenOut, amountOutMin, path);
        bytes memory payload = _build_executeWithToken(destination, unwrap, swapPayload);

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbol, amountIn
        );

        _assertPostSwapExactInput(inputToken, outputToken, amountOutMin, destination, unwrap);
    }

    function _execute_exactTokensForTokens(
        string memory symbol,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address destination,
        bool unwrap,
        address[] memory path
    ) internal {
        _mockGateway(symbol, tokenIn, amountIn);

        IERC20 inputToken = IERC20(tokenIn);
        IERC20 outputToken = IERC20(tokenOut);

        _assertPreSwap(inputToken, outputToken, amountIn, destination);

        bytes memory swapPayload = _build_exactTokensForTokens(tokenOut, amountOutMin, path);
        bytes memory payload = _build_executeWithToken(destination, unwrap, swapPayload);

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbol, amountIn
        );

        _assertPostSwapExactInput(inputToken, outputToken, amountOutMin, destination, unwrap);
    }

    function _execute_exactOutputSingleSwap(
        string memory symbol,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address destination,
        bool unwrap
    ) internal {
        _mockGateway(symbol, tokenIn, amountIn);

        IERC20 inputToken = IERC20(tokenIn);
        IERC20 outputToken = IERC20(tokenOut);

        _assertPreSwap(inputToken, outputToken, amountIn, destination);

        bytes memory swapPayload = _build_exactOutputSingle(tokenOut, amountOut, 3000);
        bytes memory payload = _build_executeWithToken(destination, unwrap, swapPayload);

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbol, amountIn
        );

        _assertPostSwapExactOutput(inputToken, outputToken, amountOut, destination, unwrap);
    }

    function _execute_exactOutputSwap(
        string memory symbol,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address destination,
        bool unwrap,
        bytes memory path
    ) internal {
        _mockGateway(symbol, tokenIn, amountIn);

        IERC20 inputToken = IERC20(tokenIn);
        IERC20 outputToken = IERC20(tokenOut);

        _assertPreSwap(inputToken, outputToken, amountIn, destination);

        bytes memory swapPayload = _build_exactOutput(tokenOut, amountOut, path);
        bytes memory payload = _build_executeWithToken(destination, unwrap, swapPayload);

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbol, amountIn
        );

        _assertPostSwapExactOutput(inputToken, outputToken, amountOut, destination, unwrap);
    }

    function _execute_tokensForExactTokens(
        string memory symbol,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address destination,
        bool unwrap,
        address[] memory path
    ) internal {
        _mockGateway(symbol, tokenIn, amountIn);

        IERC20 inputToken = IERC20(tokenIn);
        IERC20 outputToken = IERC20(tokenOut);

        _assertPreSwap(inputToken, outputToken, amountIn, destination);

        bytes memory swapPayload = _build_tokensForExactTokens(tokenOut, amountOut, path);
        bytes memory payload = _build_executeWithToken(destination, unwrap, swapPayload);

        handler.executeWithToken(
            keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbol, amountIn
        );

        _assertPostSwapExactOutput(inputToken, outputToken, amountOut, destination, unwrap);
    }

    function _assertPreSwap(IERC20 inputToken, IERC20 outputToken, uint256 amountIn, address destination) internal {
        assertEq(inputToken.balanceOf(address(handler)), amountIn, "Handler input token balance before");
        assertEq(outputToken.balanceOf(address(handler)), 0, "Handler output token balance before");

        assertEq(destination.balance, 0, "Destination eth balance before");
        assertEq(inputToken.balanceOf(destination), 0, "Destination input token balance before");
        assertEq(outputToken.balanceOf(destination), 0, "Destination output token balance before");
    }

    function _assertPostSwapExactInput(
        IERC20 inputToken,
        IERC20 outputToken,
        uint256 amountOutMin,
        address destination,
        bool unwrap
    ) internal {
        assertEq(inputToken.balanceOf(destination), 0, "Destination input token balance after");
        if (unwrap) {
            assertTrue(destination.balance >= amountOutMin, "Destination output native balance after");
            _assertNoDust();
        } else {
            assertTrue(outputToken.balanceOf(destination) >= amountOutMin, "Destination output token balance after");
        }

        _assertNoDust(inputToken);
        _assertNoDust(outputToken);
        _assertNoAllowance(inputToken);
    }

    function _assertPostSwapExactOutput(
        IERC20 inputToken,
        IERC20 outputToken,
        uint256 amountOut,
        address destination,
        bool unwrap
    ) internal {
        assertGt(inputToken.balanceOf(destination), 0, "Destination input token balance after");
        console2.log("Input refund: ", inputToken.balanceOf(destination));

        if (unwrap) {
            assertEq(destination.balance, amountOut, "Destination output native balance after");
            _assertNoDust();
        } else {
            assertEq(outputToken.balanceOf(destination), amountOut, "Destination output token balance after");
        }

        _assertNoDust(inputToken);
        _assertNoDust(outputToken);
        _assertNoAllowance(inputToken);
    }

    function _assertNoDust(IERC20[] memory tokens) internal {
        uint256 length = tokens.length;
        for (uint256 i; i < length; ++i) {
            _assertNoDust(tokens[i]);
        }
    }

    function _assertNoDust(IERC20 token) internal {
        assertEq(token.balanceOf(address(handler)), 0, "Dust left in handler");
    }

    function _assertNoDust() internal {
        assertEq(address(handler).balance, 0, "Handler native token balance after");
    }

    function _assertNoAllowance(IERC20[] memory tokens) internal {
        uint256 length = tokens.length;
        for (uint256 i; i < length; ++i) {
            _assertNoAllowance(tokens[i]);
        }
    }

    function _assertNoAllowance(IERC20 token) internal {
        assertEq(token.allowance(address(handler), address(router)), 0, "Allowance left in handler");
    }

    // function test_forked_executeWithToken_swap_refundDust() public {
    //     uint256 inputAmount = 4.95 ether;
    //     uint256 dust = 0.05 ether;
    //     uint256 minOutput = 10_000 * 1e6;

    //     string memory symbol = "WETH";
    //     IERC20Upgradeable inputToken = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses(symbol));
    //     vm.label(address(inputToken), "WETH");

    //     IERC20Upgradeable outputToken = IERC20Upgradeable(USDC);
    //     vm.label(address(inputToken), "USDC");

    //     deal(address(inputToken), address(this), inputAmount);
    //     inputToken.transfer(address(handler), inputAmount);

    //     assertEq(inputToken.balanceOf(address(handler)), inputAmount, "Handler input token balance before");
    //     assertEq(outputToken.balanceOf(address(handler)), 0, "Handler output token balance before");

    //     assertEq(inputToken.balanceOf(ALICE), 0, "Alice input token balance before");
    //     assertEq(outputToken.balanceOf(ALICE), 0, "Alice output token balance before");

    //     deployCodeTo("MockGateway.sol", address(gateway));
    //     MockGateway mockGateway = MockGateway(address(gateway));
    //     mockGateway.saveTokenAddress(symbol, address(inputToken));

    //     address[] memory path = new address[](2);
    //     path[0] = address(inputToken);
    //     path[1] = address(outputToken);
    //     bytes memory swapCalldata =
    //         abi.encodeWithSelector(bytes4(0x472b43f3), inputAmount - dust, minOutput, path, address(handler));
    //     bytes memory payload = abi.encode(uint8(1), abi.encode(ALICE, address(outputToken), swapCalldata));

    //     handler.executeWithToken(
    //         keccak256(abi.encodePacked("COMMAND_ID")), "osmosis-7", "mock_address", payload, symbol, inputAmount
    //     );

    //     assertEq(inputToken.balanceOf(ALICE), dust, "User didn't got dust refunded");
    //     assertGt(outputToken.balanceOf(ALICE), minOutput, "User balance didn't increase");
    //     assertEq(inputToken.balanceOf(address(handler)), 0, "Dust leftover in the contract.");
    //     assertEq(outputToken.balanceOf(address(handler)), 0, "Funds leftover in contract");
    //     assertEq(inputToken.allowance(address(handler), address(router)), 0, "Router Allowance Remaining After Payment");
    // }

    function test_forked_swapAndGmpTransferERC20Token_ETH() public forked {
        uint256 amount = 2 ether;
        uint256 gasAmount = 0.5 ether;
        IERC20Upgradeable token = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses("WBTC"));

        assertEq(ALICE.balance, 0, "Pre-swap user balance");
        assertEq(address(handler).balance, 0, "Pre-swap contract balance");

        vm.deal(ALICE, amount + gasAmount);
        uint256 minAmount = 0.05 * 1e8;
        address[] memory path = new address[](2);
        path[0] = gateway.tokenAddresses("WETH");
        path[1] = address(token);
        bytes memory swapCalldata =
            abi.encodeWithSelector(bytes4(0x472b43f3), amount, minAmount, path, address(handler));

        vm.startPrank(ALICE);
        handler.swapAndGmpTransferERC20Token{value: amount + gasAmount}(
            address(0),
            amount,
            swapCalldata,
            "arbitrum",
            vm.toString(address(this)),
            abi.encodePacked(address(BOB)),
            "WBTC",
            gasAmount
        );
        vm.stopPrank();

        assertEq(ALICE.balance, 0, "User balance increased");
        assertEq(address(handler).balance, 0, "Funds leftover in contract");
        assertEq(token.allowance(address(handler), address(router)), 0, "Router Allowance Remaining After Payment");
        assertEq(token.balanceOf(address(handler)), 0, "Balance Remaining After Payment");
        assertEq(address(handler).balance, 0, "Native balance after sending.");
    }

    function test_forked_swapAndGmpTransferERC20Token_Token() public forked {
        uint256 amount = 2 ether;
        uint256 gasAmount = 0.5 ether;
        IERC20Upgradeable inputToken = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses("WETH"));
        IERC20Upgradeable token = IERC20Upgradeable(IAxelarGateway(gateway).tokenAddresses("WBTC"));

        assertEq(inputToken.balanceOf(ALICE), 0, "Pre-swap user balance");
        assertEq(inputToken.balanceOf(address(handler)), 0, "Pre-swap contract balance");
        assertEq(address(handler).balance, 0, "Pre-swap contract eth balance");

        vm.deal(ALICE, gasAmount);
        deal(address(inputToken), ALICE, amount);

        uint256 minAmount = 0.05 * 1e8;
        address[] memory path = new address[](2);
        path[0] = address(inputToken);
        path[1] = address(token);
        bytes memory swapCalldata =
            abi.encodeWithSelector(bytes4(0x472b43f3), amount, minAmount, path, address(handler));

        vm.startPrank(ALICE);
        IERC20Upgradeable(path[0]).approve(address(handler), amount);
        handler.swapAndGmpTransferERC20Token{value: gasAmount}(
            path[0],
            amount,
            swapCalldata,
            "arbitrum",
            vm.toString(address(this)),
            abi.encodePacked(address(BOB)),
            "WBTC",
            gasAmount
        );
        vm.stopPrank();

        assertEq(IERC20Upgradeable(path[0]).balanceOf(ALICE), 0, "Handler balance increased");
        assertEq(IERC20Upgradeable(path[1]).balanceOf(ALICE), 0, "Handler balance increased");
        assertEq(address(handler).balance, 0, "Funds leftover in contract");
        assertEq(token.allowance(address(handler), address(router)), 0, "Router Allowance Remaining After Payment");
        assertEq(token.balanceOf(address(handler)), 0, "Balance Remaining After Payment");
        assertEq(address(handler).balance, 0, "Native balance after sending.");
    }
}
