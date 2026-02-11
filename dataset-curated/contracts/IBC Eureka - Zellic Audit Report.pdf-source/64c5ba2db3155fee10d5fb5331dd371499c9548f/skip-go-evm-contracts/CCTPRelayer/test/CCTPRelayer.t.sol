pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "script/Config.sol";

import {CCTPRelayer} from "src/CCTPRelayer.sol";
import {ITokenMessenger} from "src/interfaces/ITokenMessenger.sol";
import {IMessageTransmitter} from "src/interfaces/IMessageTransmitter.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CCTPRelayerTest is Test {
    using stdStorage for StdStorage;
    using stdJson for string;

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    address public ACTOR_1 = makeAddr("ACTOR 1");

    uint256[] public forks;

    // Contracts from the selected fork
    CCTPRelayer public relayer;
    IERC20 public usdc;
    IERC20 public wETH;
    ITokenMessenger messenger;
    IMessageTransmitter transmitter;
    address public router;

    // Fork ID -> Contract
    mapping(uint256 => CCTPRelayer) public relayers;
    mapping(uint256 => IERC20) public usdcs;
    mapping(uint256 => ITokenMessenger) public messengers;
    mapping(uint256 => IMessageTransmitter) public transmitters;
    mapping(uint256 => address) public routers;
    mapping(uint256 => IERC20) public wETHs;

    function setUp() public {
        string memory rpcsJson = vm.envString("RPC_ENDPOINTS");

        uint256 id = vm.createSelectFork(rpcsJson.readString(".ethereum-mainnet"));
        usdcs[id] = IERC20(USDC_MAINNET);
        wETHs[id] = IERC20(WETH_MAINNET);
        messengers[id] = ITokenMessenger(MESSENGER_MAINNET);
        transmitters[id] = IMessageTransmitter(TRANSMITTER_MAINNET);
        routers[id] = ROUTER_MAINNET;
        _deploy(id);
        forks.push(id);

        id = vm.createSelectFork(rpcsJson.readString(".avalanche-mainnet"));
        usdcs[id] = IERC20(USDC_AVALANCHE);
        wETHs[id] = IERC20(WETH_AVALANCHE);
        messengers[id] = ITokenMessenger(MESSENGER_AVALANCHE);
        transmitters[id] = IMessageTransmitter(TRANSMITTER_AVALANCHE);
        routers[id] = ROUTER_AVALANCHE;
        _deploy(id);
        forks.push(id);

        id = vm.createSelectFork(rpcsJson.readString(".op-mainnet"));
        usdcs[id] = IERC20(USDC_OP);
        wETHs[id] = IERC20(WETH_OP);
        messengers[id] = ITokenMessenger(MESSENGER_OP);
        transmitters[id] = IMessageTransmitter(TRANSMITTER_OP);
        routers[id] = ROUTER_OP;
        _deploy(id);
        forks.push(id);

        id = vm.createSelectFork(rpcsJson.readString(".arbitrum-mainnet"));
        usdcs[id] = IERC20(USDC_ARBITRUM);
        wETHs[id] = IERC20(WETH_ARBITRUM);
        messengers[id] = ITokenMessenger(MESSENGER_ARBITRUM);
        transmitters[id] = IMessageTransmitter(TRANSMITTER_ARBITRUM);
        routers[id] = ROUTER_ARBITRUM;
        _deploy(id);
        forks.push(id);

        id = vm.createSelectFork(rpcsJson.readString(".base-mainnet"));
        usdcs[id] = IERC20(USDC_BASE);
        wETHs[id] = IERC20(WETH_BASE);
        messengers[id] = ITokenMessenger(MESSENGER_BASE);
        transmitters[id] = IMessageTransmitter(TRANSMITTER_BASE);
        routers[id] = ROUTER_BASE;
        _deploy(id);
        forks.push(id);

        id = vm.createSelectFork(rpcsJson.readString(".polygon-mainnet"));
        usdcs[id] = IERC20(USDC_POLYGON);
        wETHs[id] = IERC20(WETH_POLYGON);
        messengers[id] = ITokenMessenger(MESSENGER_POLYGON);
        transmitters[id] = IMessageTransmitter(TRANSMITTER_POLYGON);
        routers[id] = ROUTER_POLYGON;
        _deploy(id);
        forks.push(id);

        // id = vm.createSelectFork(rpcsJson.readString(".ethereum-testnet"));
        // usdcs[id] = IERC20(USDC_SEPOLIA);
        // messengers[id] = ITokenMessenger(MESSENGER_SEPOLIA);
        // transmitters[id] = IMessageTransmitter(TRANSMITTER_SEPOLIA);
        // _deploy(id);
        // forks.push(id);

        // id = vm.createSelectFork(rpcsJson.readString(".avalanche-testnet"));
        // usdcs[id] = IERC20(USDC_AVALANCHE_FUJI);
        // messengers[id] = ITokenMessenger(MESSENGER_AVALANCHE_FUJI);
        // transmitters[id] = IMessageTransmitter(TRANSMITTER_AVALANCHE_FUJI);
        // _deploy(id);
        // forks.push(id);

        // id = vm.createSelectFork(rpcsJson.readString(".op-testnet"));
        // usdcs[id] = IERC20(USDC_OP_SEPOLIA);
        // messengers[id] = ITokenMessenger(MESSENGER_OP_SEPOLIA);
        // transmitters[id] = IMessageTransmitter(TRANSMITTER_OP_SEPOLIA);
        // _deploy(id);
        // forks.push(id);

        // id = vm.createSelectFork(rpcsJson.readString(".arbitrum-testnet"));
        // usdcs[id] = IERC20(USDC_ARBITRUM_SEPOLIA);
        // messengers[id] = ITokenMessenger(MESSENGER_ARBITRUM_SEPOLIA);
        // transmitters[id] = IMessageTransmitter(TRANSMITTER_ARBITRUM_SEPOLIA);
        // _deploy(id);
        // forks.push(id);

        // id = vm.createSelectFork(rpcsJson.readString(".base-testnet"));
        // usdcs[id] = IERC20(USDC_BASE_SEPOLIA);
        // messengers[id] = ITokenMessenger(MESSENGER_BASE_SEPOLIA);
        // transmitters[id] = IMessageTransmitter(TRANSMITTER_BASE_SEPOLIA);
        // _deploy(id);
        // forks.push(id);

        // id = vm.createSelectFork(rpcsJson.readString(".polygon-testnet"));
        // usdcs[id] = IERC20(USDC_POLYGON_MUMBAI);
        // messengers[id] = ITokenMessenger(MESSENGER_POLYGON_MUMBAI);
        // transmitters[id] = IMessageTransmitter(TRANSMITTER_POLYGON_MUMBAI);
        // _deploy(id);
        // forks.push(id);
    }

    function test_Fuzz_makePaymentForRelay(uint64 nonce, uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        uint256 length = forks.length;

        for (uint256 i; i < length; ++i) {
            _switchFork(forks[i]);
            _paymentForRelay(nonce, amount);
        }
    }

    function test_requestCCTPTransfer() public {
        uint256 length = forks.length;

        uint32[6] memory domains = [uint32(7), 6, 3, 2, 1, 0];

        for (uint256 i; i < length; ++i) {
            uint32 domain;
            if (i < 6) {
                domain = domains[i];
            } else {
                domain = domains[i - 6];
            }
            _switchFork(forks[i]);
            _requestCCTPTransfer(domain);
        }
    }

    function test_requestCCTPTransferWithCaller() public {
        uint256 length = forks.length;

        uint32[6] memory domains = [uint32(7), 6, 3, 2, 1, 0];

        for (uint256 i; i < length; ++i) {
            uint32 domain;
            if (i < 6) {
                domain = domains[i];
            } else {
                domain = domains[i - 6];
            }
            _switchFork(forks[i]);
            _requestCCTPTransferWithCaller(domain);
        }
    }

    function test_swapAndRequestCCTPTransfer_ETH() public {
        uint32 domain = uint32(7);
        _switchFork(forks[0]);

        uint256 minAmount = 2_000 * 1e6;
        address[] memory path = new address[](2);
        path[0] = address(wETH);
        path[1] = address(usdc);
        bytes memory swapCalldata =
            abi.encodeWithSelector(bytes4(0x472b43f3), 1 ether, minAmount, path, address(relayer));

        _swapAndRequestCCTPTransfer(domain, address(0), 1 ether, swapCalldata);
    }

    function test_swapAndRequestCCTPTransfer_ETH_refund() public {
        uint32 domain = uint32(7);
        _switchFork(forks[0]);

        uint256 minAmount = 2_000 * 1e6;
        address[] memory path = new address[](2);
        path[0] = address(wETH);
        path[1] = address(usdc);
        bytes memory swapCalldata =
            abi.encodeWithSelector(bytes4(0x472b43f3), 1 ether, minAmount, path, address(relayer));

        _swapAndRequestCCTPTransfer(domain, address(0), 1 ether, swapCalldata);
    }

    function test_swapAndRequestCCTPTransfer_Token() public {
        uint32 domain = 7;
        _switchFork(forks[0]);

        uint256 minAmount = 2_000 * 1e6;
        address[] memory path = new address[](2);
        path[0] = address(wETH);
        path[1] = address(usdc);
        bytes memory swapCalldata =
            abi.encodeWithSelector(bytes4(0x472b43f3), 1 ether, minAmount, path, address(relayer));

        _swapAndRequestCCTPTransfer(domain, address(wETH), 1 ether, swapCalldata);
    }

    function test_swapAndRequestCCTPTransferWithCaller_ETH() public {
        uint32 domain = 7;
        _switchFork(forks[0]);

        uint256 minAmount = 2_000 * 1e6;
        address[] memory path = new address[](2);
        path[0] = address(wETH);
        path[1] = address(usdc);
        bytes memory swapCalldata =
            abi.encodeWithSelector(bytes4(0x472b43f3), 1 ether, minAmount, path, address(relayer));

        _swapAndRequestCCTPTransferWithCaller(domain, address(0), 1 ether, swapCalldata);
    }

    function test_swapAndRequestCCTPTransferWithCaller_Token() public {
        uint32 domain = 7;
        _switchFork(forks[0]);

        uint256 minAmount = 2_000 * 1e6;
        address[] memory path = new address[](2);
        path[0] = address(wETH);
        path[1] = address(usdc);
        bytes memory swapCalldata =
            abi.encodeWithSelector(bytes4(0x472b43f3), 1 ether, minAmount, path, address(relayer));

        _swapAndRequestCCTPTransferWithCaller(domain, address(wETH), 1 ether, swapCalldata);
    }

    function _swapAndRequestCCTPTransfer(
        uint32 domain,
        address inputToken,
        uint256 inputAmount,
        bytes memory swapCalldata
    ) internal {
        uint256 feeAmount = 10 * 1e6;

        bytes32 mintRecipent = bytes32(abi.encodePacked(ACTOR_1));

        if (inputToken == address(0)) {
            vm.deal(ACTOR_1, inputAmount);
            uint256 preSwapUserBalance = ACTOR_1.balance;
            uint256 preSwapContractBalance = address(relayer).balance;

            vm.startPrank(ACTOR_1);
            relayer.swapAndRequestCCTPTransfer{value: inputAmount}(
                inputToken, inputAmount, swapCalldata, domain, mintRecipent, address(usdc), feeAmount
            );
            vm.stopPrank();

            assertTrue(ACTOR_1.balance < preSwapUserBalance, "User balance increased");
            assertEq(address(relayer).balance, preSwapContractBalance, "Funds leftover in contract");
        } else {
            deal(inputToken, ACTOR_1, inputAmount);

            uint256 preSwapUserBalance = IERC20(inputToken).balanceOf(ACTOR_1);
            uint256 preSwapContractBalance = IERC20(inputToken).balanceOf(address(relayer));

            vm.startPrank(ACTOR_1);
            IERC20(inputToken).approve(address(relayer), inputAmount);
            relayer.swapAndRequestCCTPTransfer(
                inputToken, inputAmount, swapCalldata, domain, mintRecipent, address(usdc), feeAmount
            );
            vm.stopPrank();

            assertEq(IERC20(inputToken).allowance(address(relayer), relayer.swapRouter()), 0, "Left-over allowance");
            assertTrue(IERC20(inputToken).balanceOf(ACTOR_1) < preSwapUserBalance, "User balance increased");
            assertEq(
                IERC20(inputToken).balanceOf(address(relayer)), preSwapContractBalance, "Funds leftover in contract"
            );
        }

        assertEq(usdc.allowance(address(relayer), address(messenger)), 0, "Messenger Allowance Remaining After Payment");
        assertEq(usdc.allowance(ACTOR_1, address(relayer)), 0, "Relayer Allowance Remaining After Payment");
        assertEq(usdc.balanceOf(ACTOR_1), 0, "Balance Remaining After Payment");
    }

    function _swapAndRequestCCTPTransferWithCaller(
        uint32 domain,
        address inputToken,
        uint256 inputAmount,
        bytes memory swapCalldata
    ) internal {
        uint256 feeAmount = 10 * 1e6;

        bytes32 mintRecipent = bytes32(abi.encodePacked(ACTOR_1));

        if (inputToken == address(0)) {
            vm.deal(ACTOR_1, inputAmount);
            uint256 preSwapUserBalance = ACTOR_1.balance;
            uint256 preSwapContractBalance = address(relayer).balance;

            vm.startPrank(ACTOR_1);
            relayer.swapAndRequestCCTPTransferWithCaller{value: inputAmount}(
                inputToken,
                inputAmount,
                swapCalldata,
                domain,
                mintRecipent,
                address(usdc),
                feeAmount,
                keccak256(abi.encodePacked("random caller"))
            );
            vm.stopPrank();

            assertTrue(ACTOR_1.balance < preSwapUserBalance, "User balance increased");
            assertEq(address(relayer).balance, preSwapContractBalance, "Funds leftover in contract");
        } else {
            deal(inputToken, ACTOR_1, inputAmount);

            uint256 preSwapUserBalance = IERC20(inputToken).balanceOf(ACTOR_1);
            uint256 preSwapContractBalance = IERC20(inputToken).balanceOf(address(relayer));

            vm.startPrank(ACTOR_1);
            IERC20(inputToken).approve(address(relayer), inputAmount);
            relayer.swapAndRequestCCTPTransferWithCaller(
                inputToken,
                inputAmount,
                swapCalldata,
                domain,
                mintRecipent,
                address(usdc),
                feeAmount,
                keccak256(abi.encodePacked("random caller"))
            );
            vm.stopPrank();

            assertEq(IERC20(inputToken).allowance(address(relayer), relayer.swapRouter()), 0, "Left-over allowance");
            assertTrue(IERC20(inputToken).balanceOf(ACTOR_1) < preSwapUserBalance, "User balance increased");
            assertEq(
                IERC20(inputToken).balanceOf(address(relayer)), preSwapContractBalance, "Funds leftover in contract"
            );
        }

        assertEq(usdc.allowance(address(relayer), address(messenger)), 0, "Messenger Allowance Remaining After Payment");
        assertEq(usdc.allowance(ACTOR_1, address(relayer)), 0, "Relayer Allowance Remaining After Payment");
        assertEq(usdc.balanceOf(ACTOR_1), 0, "Balance Remaining After Payment");
    }

    function test_withdraw() public {
        uint256 length = forks.length;

        address receiver = makeAddr("RECEIVER");

        for (uint256 i; i < length; ++i) {
            uint256 amount = 10 * (i + 1) * 1e6;
            _switchFork(forks[i]);
            _paymentForRelay(uint64(i), amount);

            relayer.withdraw(receiver, amount);
            assertEq(usdc.balanceOf(receiver), amount, "Withdrawal not transferred");
        }
    }

    function _requestCCTPTransfer(uint32 domain) internal {
        uint256 transferAmount = 1_000 * 1e6;
        uint256 feeAmount = 10 * 1e6;
        uint256 amount = transferAmount + feeAmount;

        _dealUSDC(ACTOR_1, amount);
        assertEq(usdc.balanceOf(ACTOR_1), amount, "Balance Before Payment is Wrong");

        bytes32 mintRecipent = bytes32(abi.encodePacked(ACTOR_1));

        vm.startPrank(ACTOR_1);
        usdc.approve(address(relayer), amount);
        relayer.requestCCTPTransfer(transferAmount, domain, mintRecipent, address(usdc), feeAmount);
        vm.stopPrank();

        assertEq(usdc.allowance(address(relayer), address(messenger)), 0, "Messenger Allowance Remaining After Payment");
        assertEq(usdc.allowance(ACTOR_1, address(relayer)), 0, "Relayer Allowance Remaining After Payment");
        assertEq(usdc.balanceOf(ACTOR_1), 0, "Balance Remaining After Payment");
    }

    function _requestCCTPTransferWithCaller(uint32 domain) internal {
        uint256 transferAmount = 1_000 * 1e6;
        uint256 feeAmount = 10 * 1e6;
        uint256 amount = transferAmount + feeAmount;

        _dealUSDC(ACTOR_1, amount);
        assertEq(usdc.balanceOf(ACTOR_1), amount, "Balance Before Payment is Wrong");

        bytes32 mintRecipent = bytes32(abi.encodePacked(ACTOR_1));

        vm.startPrank(ACTOR_1);
        usdc.approve(address(relayer), amount);
        relayer.requestCCTPTransferWithCaller(
            transferAmount, domain, mintRecipent, address(usdc), feeAmount, keccak256(abi.encodePacked("random caller"))
        );
        vm.stopPrank();

        assertEq(usdc.allowance(address(relayer), address(messenger)), 0, "Messenger Allowance Remaining After Payment");
        assertEq(usdc.allowance(ACTOR_1, address(relayer)), 0, "Relayer Allowance Remaining After Payment");
        assertEq(usdc.balanceOf(ACTOR_1), 0, "Balance Remaining After Payment");
    }

    function _switchFork(uint256 id) internal {
        vm.selectFork(id);

        relayer = relayers[id];
        usdc = usdcs[id];
        wETH = wETHs[id];
        messenger = messengers[id];
        transmitter = transmitters[id];
        router = routers[id];
    }

    function _deploy(uint256 id) internal {
        CCTPRelayer relayerImpl = new CCTPRelayer();
        ERC1967Proxy relayerProxy = new ERC1967Proxy(
            address(relayerImpl),
            abi.encodeWithSignature(
                "initialize(address,address,address)",
                address(usdcs[id]),
                address(messengers[id]),
                address(transmitters[id])
            )
        );

        relayers[id] = CCTPRelayer(payable(address(relayerProxy)));
        relayer = CCTPRelayer(payable(address(relayerProxy)));

        relayer.setSwapRouter(routers[id]);
    }

    function _dealUSDC(address account, uint256 amount) internal {
        vm.store(address(usdc), keccak256(abi.encode(account, uint256(9))), bytes32(amount));
    }

    function _paymentForRelay(uint64 nonce, uint256 amount) internal {
        _dealUSDC(ACTOR_1, amount);
        assertEq(usdc.balanceOf(ACTOR_1), amount, "Balance Before Payment is Wrong");

        vm.startPrank(ACTOR_1);
        usdc.approve(address(relayer), amount);
        relayer.makePaymentForRelay(nonce, amount);
        vm.stopPrank();

        assertEq(usdc.allowance(ACTOR_1, address(relayer)), 0, "Allowance Remaining After Payment");
        assertEq(usdc.balanceOf(ACTOR_1), 0, "Balance Remaining After Payment");
    }

    fallback() external payable {}

    receive() external payable {}
}
