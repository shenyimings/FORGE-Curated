// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { SafeOFTLzComposer } from "../../contracts/zap/SafeOFTLzComposer.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

import { MockOFT } from "../mocks/MockOFT.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

struct TestMessage {
    bool shouldRevert;
    bool consumeAllGas;
    uint256 amountToSend;
    address sendTo;
}

// The implementation of SafeOFTLzComposer used for testing
contract SafeOFTLzComposer_TestImplementation is SafeOFTLzComposer {
    using SafeERC20 for IERC20;

    event GasConsumer(bytes1 a, bytes1 b, bytes1 c, bytes1 d, bytes1 e, bytes1 f, bytes1 g, bytes1 h);

    constructor(address _oApp, address _endpoint) SafeOFTLzComposer(_oApp, _endpoint) { }

    function _lzCompose(address _oApp, bytes32, bytes calldata _message, address, bytes calldata) internal override {
        bytes memory payload = OFTComposeMsgCodec.composeMsg(_message);
        TestMessage memory testMessage = abi.decode(payload, (TestMessage));
        console.log("consumeAllGas", testMessage.consumeAllGas);
        if (testMessage.shouldRevert) {
            revert("revert");
        }
        if (testMessage.consumeAllGas) {
            for (uint256 i = 0; i < 100_000_000; i++) {
                // make sure to trigger a random sstore each loop
                emit GasConsumer(
                    bytes1(uint8(i)),
                    bytes1(uint8(i + 1)),
                    bytes1(uint8(i + 2)),
                    bytes1(uint8(i + 3)),
                    bytes1(uint8(i + 4)),
                    bytes1(uint8(i + 5)),
                    bytes1(uint8(i + 6)),
                    bytes1(uint8(i + 7))
                );
            }
        }

        address token = MockOFT(_oApp).token();
        IERC20(token).safeTransfer(testMessage.sendTo, testMessage.amountToSend);
    }
}

contract SafeOFTLzComposerTest is Test {
    SafeOFTLzComposer_TestImplementation public composer;
    MockOFT public oft;
    address public endpoint;
    address public user;

    function setUp() public {
        user = makeAddr("user");
        endpoint = makeAddr("endpoint");
        oft = new MockOFT();
        composer = new SafeOFTLzComposer_TestImplementation(address(oft), endpoint);

        // mint some tokens to the composer to simulate parallel execution
        oft.mint(address(composer), 3333333333333333333);
    }

    function test_lzCompose_Success() public {
        uint256 amountLd = 100e18;
        oft.mint(address(composer), amountLd);
        uint256 initialUserBalance = oft.balanceOf(user);
        uint256 initialComposerBalance = oft.balanceOf(address(composer));

        bytes memory message = _encodeComposeMessage(user, amountLd, false, false, user, 42);

        vm.prank(endpoint);
        composer.lzCompose(address(oft), bytes32(0), message, address(0), bytes(""));
        vm.stopPrank();

        uint256 finalComposerBalance = oft.balanceOf(address(composer));
        uint256 finalUserBalance = oft.balanceOf(user);
        assertEq(finalComposerBalance, initialComposerBalance - 42);
        assertEq(finalUserBalance, initialUserBalance + 42);
    }

    function test_lzCompose_FailAndRefund() public {
        uint256 amountLd = 100e18;
        oft.mint(address(composer), amountLd);
        uint256 initialComposerBalance = oft.balanceOf(address(composer));
        uint256 initialUserBalance = user.balance;

        bytes memory message = _encodeComposeMessage(user, amountLd, false, true, user, 42);

        vm.prank(endpoint);
        composer.lzCompose(address(oft), bytes32(0), message, address(0), bytes(""));
        vm.stopPrank();

        uint256 finalUserBalance = oft.balanceOf(user);
        uint256 finalComposerBalance = oft.balanceOf(address(composer));
        assertEq(finalUserBalance, initialUserBalance + amountLd);
        assertEq(finalComposerBalance, initialComposerBalance - amountLd);
    }

    function test_lzCompose_FailAndRefund_HandlerExceedsGasLimit() public {
        uint256 amountLd = 100e18;
        oft.mint(address(composer), amountLd);
        uint256 initialComposerBalance = oft.balanceOf(address(composer));
        uint256 initialUserBalance = user.balance;

        bytes memory message = _encodeComposeMessage(user, amountLd, false, true, user, 42);

        vm.prank(endpoint);
        composer.lzCompose{ gas: 100_000 }(address(oft), bytes32(0), message, address(0), bytes(""));
        vm.stopPrank();

        uint256 finalUserBalance = oft.balanceOf(user);
        uint256 finalComposerBalance = oft.balanceOf(address(composer));
        assertEq(finalUserBalance, initialUserBalance + amountLd);
        assertEq(finalComposerBalance, initialComposerBalance - amountLd);
    }

    function test_RevertWhen_CallerNotEndpoint() public {
        bytes memory message = _encodeComposeMessage(user, 1e18, false, false, user, 42);

        vm.expectRevert(SafeOFTLzComposer.SafeOFTLzComposer_InvalidEndpoint.selector);
        composer.lzCompose(address(oft), bytes32(0), message, address(0), bytes(""));
    }

    function test_RevertWhen_InvalidOApp() public {
        bytes memory message = _encodeComposeMessage(user, 1e18, false, false, user, 42);

        vm.prank(endpoint);
        vm.expectRevert(SafeOFTLzComposer.SafeOFTLzComposer_InvalidOApp.selector);
        composer.lzCompose(address(0), bytes32(0), message, address(0), bytes(""));
    }

    function test_RevertWhen_CallingFromNonThis() public {
        bytes memory message = _encodeComposeMessage(user, 1e18, false, false, user, 42);

        vm.expectRevert(SafeOFTLzComposer.SafeOFTLzComposer_Unauthorized.selector);
        composer.safeLzCompose(address(oft), bytes32(0), message, address(0), bytes(""));
    }

    function _encodeComposeMessage(
        address srcChainSender,
        uint256 amountLd,
        bool shouldRevert,
        bool consumeAllGas,
        address sendTo,
        uint256 amountToSend
    ) internal pure returns (bytes memory) {
        uint64 _nonce = 0;
        uint32 _srcEid = 0;
        TestMessage memory message = TestMessage({
            shouldRevert: shouldRevert,
            consumeAllGas: consumeAllGas,
            sendTo: sendTo,
            amountToSend: amountToSend
        });
        bytes memory payload =
            abi.encodePacked(OFTComposeMsgCodec.addressToBytes32(srcChainSender), abi.encode(message));
        return OFTComposeMsgCodec.encode(_nonce, _srcEid, amountLd, payload);
    }
}
