// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Mock imports
import { ERC20Mock } from "@layerzerolabs/oft-evm/test/mocks/ERC20Mock.sol";
import { OFTComposerMock } from "@layerzerolabs/oft-evm/test/mocks/OFTComposerMock.sol";
import { MintBurnERC20Mock } from "@layerzerolabs/oft-evm/test/mocks/MintBurnERC20Mock.sol";

// OApp imports
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

// OFT imports
import { SkyOFTAdapter } from "../../../contracts/SkyOFTAdapter.sol";
import { SkyRateLimiter, RateLimitConfig, RateLimitDirection, RateLimitAccountingType } from "../../../contracts/SkyRateLimiter.sol";
import { ISkyRateLimiter } from "../../../contracts/interfaces/ISkyRateLimiter.sol";
import { IOFT, SendParam, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt, Origin, OFTLimit, OFTFeeDetail } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { OFTMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { DoubleEndedQueue } from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import { SkyOFTCore } from "../../../contracts/SkyOFTCore.sol";
import { ISkyOFT } from "../../../contracts/interfaces/ISkyOFT.sol";

// OZ imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

// DevTools imports
import { TestHelperOz5WithRevertAssertions } from "../helpers/TestHelperOz5WithRevertAssertions.sol";

contract SkyOFTAdapterTest is TestHelperOz5WithRevertAssertions {
    using OptionsBuilder for bytes;
    using PacketV1Codec for bytes;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    uint32 aEid = 1;
    uint32 bEid = 2;
    uint32 cEid = 3;

    IERC20 aToken;
    IERC20 bToken;
    IERC20 cToken;

    SkyOFTAdapter aOFT;
    SkyOFTAdapter bOFT;
    SkyOFTAdapter cOFT;

    address public userA = address(0x1);
    address public userB = address(0x2);
    address public userC = address(0x3);
    uint256 public initialBalance = 100 ether;

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);
        vm.deal(userC, 1000 ether);
        
        // The outbound (send) rate limits for OFT A.
        RateLimitConfig[] memory aOutboundConfigs = new RateLimitConfig[](1);
        aOutboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 10 ether, window: 60 seconds});

        // The inbound (receive) rate limits for OFT A.
        RateLimitConfig[] memory aInboundConfigs = new RateLimitConfig[](1);
        aInboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 10 ether, window: 60 seconds});

        // The outbound (send) rate limits for OFT B.
        RateLimitConfig[] memory bOutboundConfigs = new RateLimitConfig[](1);
        bOutboundConfigs[0] = RateLimitConfig({eid: aEid, limit: 10 ether, window: 60 seconds});

        // The inbound (receive) rate limits for OFT B.
        RateLimitConfig[] memory bInboundConfigs = new RateLimitConfig[](1);
        bInboundConfigs[0] = RateLimitConfig({eid: aEid, limit: 10 ether, window: 60 seconds});

        // The outbound (send) rate limits for OFT C (only limits to A).
        RateLimitConfig[] memory cOutboundConfigs = new RateLimitConfig[](1);
        cOutboundConfigs[0] = RateLimitConfig({eid: aEid, limit: 10 ether, window: 60 seconds});
        
        // The inbound (receive) rate limits for OFT C (only limits from A).
        RateLimitConfig[] memory cInboundConfigs = new RateLimitConfig[](1);
        cInboundConfigs[0] = RateLimitConfig({eid: aEid, limit: 10 ether, window: 60 seconds});

        super.setUp();
        setUpEndpoints(3, LibraryType.UltraLightNode);
        setUpTokens();
        
        aOFT = SkyOFTAdapter(
            _deployOApp(type(SkyOFTAdapter).creationCode, abi.encode(address(aToken), address(endpoints[aEid]), address(this)))
        );
        aOFT.setRateLimits(aInboundConfigs, aOutboundConfigs);

        bOFT = SkyOFTAdapter(
            _deployOApp(type(SkyOFTAdapter).creationCode, abi.encode(address(bToken), address(endpoints[bEid]), address(this)))
        );
        bOFT.setRateLimits(bInboundConfigs, bOutboundConfigs);

        cOFT = SkyOFTAdapter(
            _deployOApp(type(SkyOFTAdapter).creationCode, abi.encode(address(cToken), address(endpoints[cEid]), address(this)))
        );
        cOFT.setRateLimits(cInboundConfigs, cOutboundConfigs);

        // config and wire the ofts
        address[] memory ofts = new address[](3);
        ofts[0] = address(aOFT);
        ofts[1] = address(bOFT);
        ofts[2] = address(cOFT);
        this.wireOApps(ofts);

        // mint tokens
        deal(address(aToken), userA, initialBalance);
        deal(address(bToken), userB, initialBalance);
        deal(address(cToken), userC, initialBalance);

        // mint tokens to the B and C adapter lockboxes
        // this is not needed in production, only for testing
        // because there is more than one lockbox in the testing mesh
        deal(address(bToken), address(bOFT), initialBalance);
        deal(address(cToken), address(cOFT), initialBalance);
    }

    function setUpTokens() public virtual {
        aToken = new MintBurnERC20Mock("aToken", "aToken");
        bToken = new MintBurnERC20Mock("bToken", "bToken");
        cToken = new MintBurnERC20Mock("cToken", "cToken");
    }

    function test_constructor() public view {
        assertEq(aOFT.owner(), address(this));
        assertEq(bOFT.owner(), address(this));
        assertEq(cOFT.owner(), address(this));

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);
        assertEq(cToken.balanceOf(userC), initialBalance);

        assertEq(aOFT.token(), address(aToken));
        assertEq(bOFT.token(), address(bToken));
        assertEq(cOFT.token(), address(cToken));
    }

    function test_set_rates() public {
        // The outbound (send) rate limits for OFT A.
        RateLimitConfig[] memory aNewOutboundConfigs = new RateLimitConfig[](1);
        aNewOutboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 1.9 ether, window: 59 seconds});
        RateLimitConfig[] memory aEmptyInboundConfigs = new RateLimitConfig[](0);
        aOFT.setRateLimits(aEmptyInboundConfigs, aNewOutboundConfigs);

        uint256 tokensToSend = 2 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // User A call send two times within the allowed outbound window.
        vm.startPrank(userA);
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    }

    function test_set_rates_only_apply_per_direction() public {
        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(cToken.balanceOf(userC), initialBalance);
        
        // The outbound (send) rate limits for OFT A only allows to send 2.5 tokens every 60 seconds.
        RateLimitConfig[] memory aNewOutboundConfigs = new RateLimitConfig[](1);
        aNewOutboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 2.5 ether, window: 60 seconds});
        RateLimitConfig[] memory aEmptyInboundConfigs = new RateLimitConfig[](0);
        aOFT.setRateLimits(aEmptyInboundConfigs, aNewOutboundConfigs);

        // The inbound (receive) rate limits for OFT B allows for 5 tokens to be received every 60 seconds..
        RateLimitConfig[] memory bNewInboundConfigs = new RateLimitConfig[](1);
        bNewInboundConfigs[0] = RateLimitConfig({eid: aEid, limit: 5 ether, window: 60 seconds});
        RateLimitConfig[] memory bEmptyOutboundConfigs = new RateLimitConfig[](0);
        bOFT.setRateLimits(bNewInboundConfigs, bEmptyOutboundConfigs);

        uint256 tokensToSend = 2.5 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory _sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(_sendParam, false);

        // User A calls send twice which loads two packets with a total of 5 tokens inside.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(_sendParam, fee, payable(address(this)));
        skip(60 seconds);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(_sendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Verify and execute those packets all at once to test if the inbound rate limit applies.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend * 2);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend * 2);
    }

    function test_set_rates_only_apply_per_pathway() public {
        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(cToken.balanceOf(userC), initialBalance);

        // The outbound (send) rate limits for OFT A.
        RateLimitConfig[] memory aNewOutboundConfigs = new RateLimitConfig[](2);
        aNewOutboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 1.9 ether, window: 59 seconds});
        aNewOutboundConfigs[1] = RateLimitConfig({eid: cEid, limit: 2 ether, window: 60 seconds});
        RateLimitConfig[] memory aEmptyInboundConfigs = new RateLimitConfig[](0);
        aOFT.setRateLimits(aEmptyInboundConfigs, aNewOutboundConfigs);

        uint256 tokensToSend = 2 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParamToEndpointC = SendParam(
            cEid,
            addressToBytes32(userC),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory feeC = aOFT.quoteSend(sendParamToEndpointC, false);

        // User A call send within the allowed outbound window and limit.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: feeC.nativeFee }(sendParamToEndpointC, feeC, payable(address(this)));
        vm.stopPrank();

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);

        SendParam memory sendParamToEndpointB = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory feeB = aOFT.quoteSend(sendParamToEndpointB, false);

        // User A call send within the allowed outbound window and limit.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        aOFT.send{ value: feeB.nativeFee }(sendParamToEndpointB, feeB, payable(address(this)));
        vm.stopPrank();
    }

    function test_only_owner_can_set_rates() public {
        assertEq(aOFT.owner(), address(this));
        assertEq(bOFT.owner(), address(this));

        // The outbound (send) rate limits for OFT A.
        RateLimitConfig[] memory aNewOutboundConfigs = new RateLimitConfig[](1);
        aNewOutboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 1.9 ether, window: 59 seconds});
        RateLimitConfig[] memory aEmptyInboundConfigs = new RateLimitConfig[](0);

        vm.prank(userB);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userB)
        );
        aOFT.setRateLimits(aEmptyInboundConfigs, aNewOutboundConfigs);
    }

    function test_send_oft() public {
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend);
    }

    function test_send_oft_fails_outside_outbound_limit() public {
        uint256 tokensToSend = 10 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();
    }

    function test_send_oft_succeeds_after_waiting_limit() public {
        uint256 tokensToSend = 10 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // User A call send first time
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend);

        uint256 tokensToSendAfter = 1 ether;
        SendParam memory nextSendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSendAfter,
            tokensToSendAfter,
            options,
            "",
            ""
        );
        MessagingFee memory nextFee = aOFT.quoteSend(nextSendParam, false);

        // User A waits 61 seconds and calls send a second time
        skip(61 seconds);
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSendAfter);
        aOFT.send{ value: nextFee.nativeFee }(nextSendParam, nextFee, payable(address(this)));
        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend - tokensToSendAfter);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend + tokensToSendAfter);
    }

    function test_receive_oft_fails_outside_inbound_limit() public {
        uint256 tokensToSend = 10 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // User A call send two times within the allowed outbound window.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        skip(61 seconds);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Packet 1 is executed.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));

        // Packet 2 fails and must wait at least 60 seconds.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0), abi.encodePacked(ISkyRateLimiter.RateLimitExceeded.selector), "");
    }

    function test_receive_oft_succeeds_after_waiting_limit() public {

        uint256 tokensToSend = 10 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );

        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // User A calls send twice.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        skip(61 seconds);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Packet 1 is executed.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));

        // Packet 2 waits at least 60 seconds and is executed.
        skip(61 seconds);
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend * 2);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend * 2);
    }

    function test_receive_oft_succeeds_with_amount_allowed_after_decay() public {
        uint256 tokensToSend = 10 ether;
        uint256 tokensToSendAfterDecay = 5 ether;

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );

        SendParam memory sendParamAfterDecay = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSendAfterDecay,
            tokensToSendAfterDecay,
            options,
            "",
            ""
        );

        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);
        MessagingFee memory feeAfterDecay = aOFT.quoteSend(sendParamAfterDecay, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // User A calls send twice.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        skip(61 seconds);
        aToken.approve(address(aOFT), tokensToSendAfterDecay);
        aOFT.send{ value: fee.nativeFee }(sendParamAfterDecay, feeAfterDecay, payable(address(this)));
        vm.stopPrank();

        // Packet 1 is executed.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));

        // Packet 2 waits at least 30 seconds.
        // Because the decay is 60 seconds, with a limit of 10 tokens, 5 tokens should be free to send after 30 seconds of decay.
        skip(30 seconds);
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend - tokensToSendAfterDecay);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend + tokensToSendAfterDecay);
    }

    function test_receive_oft_fails_with_amount_greater_than_decay() public {
        uint256 tokensToSend = 10 ether;
        uint256 tokensToSendAfterDecay = 5.1 ether;

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );

        SendParam memory sendParamAfterDecay = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSendAfterDecay,
            tokensToSendAfterDecay,
            options,
            "",
            ""
        );

        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);
        MessagingFee memory feeAfterDecay = aOFT.quoteSend(sendParamAfterDecay, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // User A calls send twice.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        skip(61 seconds);
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));
        aToken.approve(address(aOFT), tokensToSendAfterDecay);
        aOFT.send{ value: fee.nativeFee }(sendParamAfterDecay, feeAfterDecay, payable(address(this)));
        vm.stopPrank();
        // Packet 2 waits at least 30 seconds.
        // Because the decay is 60 seconds, with a limit of 10 tokens, only 5 tokens should be free to send after 30 seconds of decay.
        skip(30 seconds);
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0), abi.encodePacked(ISkyRateLimiter.RateLimitExceeded.selector), "");

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend - tokensToSendAfterDecay);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend);
    }

    function test_send_oft_compose_msg() public {
        uint256 tokensToSend = 1 ether;

        OFTComposerMock composer = new OFTComposerMock();

        bytes memory options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 500000, 0);
        bytes memory composeMsg = hex"1234";
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(address(composer)),
            tokensToSend,
            tokensToSend,
            options,
            composeMsg,
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(address(composer)), 0);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) = aOFT.send{ value: fee.nativeFee }(
            sendParam,
            fee,
            payable(address(this))
        );
        vm.stopPrank();

        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)));

        // lzCompose params
        uint32 dstEid_ = bEid;
        address from_ = address(bOFT);
        bytes memory options_ = options;
        bytes32 guid_ = msgReceipt.guid;
        address to_ = address(composer);
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce,
            aEid,
            oftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(userA), composeMsg)
        );
        this.lzCompose(dstEid_, from_, options_, guid_, to_, composerMsg_);

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bToken.balanceOf(address(composer)), tokensToSend);

        assertEq(composer.from(), from_);
        assertEq(composer.guid(), guid_);
        assertEq(composer.message(), composerMsg_);
        assertEq(composer.executor(), address(this));
        assertEq(composer.extraData(), composerMsg_); // default to setting the extraData to the message as well to test
    }

    function _createSendParam(uint256 _tokensToSend, uint32 _dstEid, address _to) internal pure returns (SendParam memory) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        return SendParam(
            _dstEid,
            addressToBytes32(_to),
            _tokensToSend,
            _tokensToSend * 9_000 / 10_000,
            options,
            "",
            ""
        );
    }

    function test_net_rate_limiting() public {
        // 1. Set the ORL on aEid to bEid to 20 eth/min.  The inbound rate limit on bEid from
        // aEid remains the same (10 eth/min).
        RateLimitConfig[] memory aOutboundConfigs = new RateLimitConfig[](1);
        aOutboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 20 ether, window: 60 seconds});
        RateLimitConfig[] memory aInboundConfigs = new RateLimitConfig[](1);
        aInboundConfigs[0] = RateLimitConfig({eid: bEid, limit: 20 ether, window: 60 seconds});
        aOFT.setRateLimits(aInboundConfigs, aOutboundConfigs);
        
        uint256 amountCanBeSent;
        uint256 amountCanBeReceived;

        // 2. tokensToSend is meant to exhaust bEid's IRL from aEid.
        uint256 tokensToSend = 10 ether;
        SendParam memory aToBSendParam = _createSendParam(tokensToSend, bEid, userB);
        MessagingFee memory fee = aOFT.quoteSend(aToBSendParam, false);

        // 3. userA exhausts the IRL of bEid from aEid.
        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 20 ether);
        (, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(amountCanBeReceived, 10 ether);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(aToBSendParam, fee, payable(address(this)));
        vm.stopPrank();

        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0));

        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 10 ether);
        (, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(amountCanBeReceived, 0);

        // 4. Assert bEid IRL from aEID is exhausted.
        (uint128 lastUpdated, uint48 window, uint256 amountInFlight, uint256 limit) = bOFT.inboundRateLimits(aEid);

        assertEq(amountInFlight, tokensToSend);
        assertEq(lastUpdated, block.timestamp);
        assertEq(limit, 10 ether);
        assertEq(window, 60 seconds);

        // 5. Send 10 ether from aEid to bEid again.  This should not fail because ORL of aEID to bEid is 20 ether.
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(aToBSendParam, fee, payable(address(this)));
        vm.stopPrank();

        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 0);
        (, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(amountCanBeReceived, 0); // should not have changed

        // 6. Expect the packet delivery to revert, as the IRL is exhausted.  This packet is now in flight until the IRL
        // allows another 10 ether to be received.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)), 1, address(0), abi.encodePacked(ISkyRateLimiter.RateLimitExceeded.selector), "");

        // 7. userB sends back the 10 ether to userA on aEid, resetting the amountCanBeReceived on bEid from aEID to 10
        // ether.  The packet from #6 can now be delivered without violating the IRL.
        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 10 ether);
        SendParam memory bToASendParam = _createSendParam(tokensToSend, aEid, userA);

        vm.startPrank(userB);
        bToken.approve(address(bOFT), tokensToSend);
        bOFT.send{ value: fee.nativeFee }(bToASendParam, fee, payable(address(this)));
        vm.stopPrank();

        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 0);
        (, amountCanBeReceived) = aOFT.getAmountCanBeReceived(bEid);
        assertEq(amountCanBeReceived, 20 ether);
        verifyAndExecutePackets(aEid, addressToBytes32(address(aOFT)), 1, address(0));
        (, amountCanBeReceived) = aOFT.getAmountCanBeReceived(bEid);
        assertEq(amountCanBeReceived, 10 ether);
        (lastUpdated, window, amountInFlight, limit) = bOFT.inboundRateLimits(aEid);
        assertEq(amountInFlight, 0);
        assertEq(lastUpdated, block.timestamp);
        assertEq(limit, 10 ether);
        assertEq(window, 60 seconds);

        // 8. try to send 10 ether from bEid to aEid again, violating the ORL.
        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 0);
        (, amountCanBeReceived) = aOFT.getAmountCanBeReceived(bEid);
        assertEq(amountCanBeReceived, 10 ether);

        vm.startPrank(userB);
        bToken.approve(address(bOFT), tokensToSend);
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        bOFT.send{ value: fee.nativeFee }(bToASendParam, fee, payable(address(this)));
        vm.stopPrank();

        // 9. The packet from #6 can be delivered through a permission-less retry without violating the IRL.
        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 0);
        (, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(amountCanBeReceived, 10 ether);
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)));
        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 10 ether);
        (, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(amountCanBeReceived, 0);

        // 10. Similar to #8, send 10 ether from bEid to aEid again, but this time successfully as the ORL has reset.
        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 10 ether);

        vm.startPrank(userB);
        bToken.approve(address(bOFT), tokensToSend);
        bOFT.send{ value: fee.nativeFee }(bToASendParam, fee, payable(address(this)));
        vm.stopPrank();

        (, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(amountCanBeSent, 0);
    }

    function test_reset_rate_limits_and_apply_new_limits() public {
        // Initial setup - send tokens to hit the rate limit
        uint256 tokensToSend = 10 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        // Send tokens to hit the rate limit
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Verify we've hit the rate limit
        (uint256 amountInFlight, uint256 amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountInFlight, tokensToSend);
        assertEq(amountCanBeSent, 0);

        // Reset the rate limits
        uint32[] memory eids = new uint32[](1);
        eids[0] = bEid;
        aOFT.resetRateLimits(new uint32[](0), eids);

        (amountInFlight, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountInFlight, 0 ether);
        assertEq(amountCanBeSent, 10 ether);

        // Verify the rate limits are reset
        RateLimitConfig[] memory newOutboundConfigs = new RateLimitConfig[](1);
        newOutboundConfigs[0] = RateLimitConfig({
            eid: bEid,
            limit: 20 ether,  // Double the previous limit
            window: 30 seconds // Half the previous window
        });
        aOFT.setRateLimits(new RateLimitConfig[](0), newOutboundConfigs);

        // Verify the new limits are in effect
        (amountInFlight, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountInFlight, 0 ether);
        assertEq(amountCanBeSent, 20 ether);

        // Test we can send with the new higher limit
        uint256 newTokensToSend = 15 ether;
        SendParam memory newSendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            newTokensToSend,
            newTokensToSend,
            options,
            "",
            ""
        );
        fee = aOFT.quoteSend(newSendParam, false);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), newTokensToSend);
        aOFT.send{ value: fee.nativeFee }(newSendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Verify the new amount that can be sent
        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 5 ether); // 20 ether limit - 15 ether sent = 5 ether remaining

        // Test the shorter window
        skip(31 seconds); // Just over the new 30 second window
        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 20 ether); // Should be fully reset after the window
    }

    function test_reset_rate_limits_and_change_to_gross_accounting() public {
        // override B rate limits
        RateLimitConfig[] memory newBOutboundConfigs = new RateLimitConfig[](1);
        newBOutboundConfigs[0] = RateLimitConfig({
            eid: aEid,
            limit: 30 ether,
            window: 60 seconds
        });
        RateLimitConfig[] memory newBInboundConfigs = new RateLimitConfig[](1);
        newBInboundConfigs[0] = RateLimitConfig({
            eid: aEid,
            limit: 60 ether,
            window: 60 seconds
        });
        bOFT.setRateLimits(newBInboundConfigs, newBOutboundConfigs);

        // Initial setup - send tokens to hit the rate limit
        uint256 tokensToSend = 10 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        // Send tokens to hit the rate limit
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Verify we've hit the rate limit
        (uint256 amountInFlight, uint256 amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountInFlight, tokensToSend);
        assertEq(amountCanBeSent, 0);

        // Change accounting type
        aOFT.setRateLimitAccountingType(RateLimitAccountingType.Gross);

        // Reset the rate limits
        uint32[] memory eids = new uint32[](1);
        eids[0] = bEid;
        aOFT.resetRateLimits(new uint32[](0), eids);

        // Set new rate limits with Gross accounting
        RateLimitConfig[] memory newOutboundConfigs = new RateLimitConfig[](1);
        newOutboundConfigs[0] = RateLimitConfig({
            eid: bEid,
            limit: 20 ether,  // Double the previous limit
            window: 30 seconds // Half the previous window
        });
        aOFT.setRateLimits(new RateLimitConfig[](0), newOutboundConfigs);

        // Send tokens in one direction
        uint256 firstSend = 15 ether;
        SendParam memory firstSendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            firstSend,
            firstSend,
            options,
            "",
            ""
        );
        fee = aOFT.quoteSend(firstSendParam, false);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), firstSend);
        aOFT.send{ value: fee.nativeFee }(firstSendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Verify first send amount
        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 5 ether); // 20 ether limit - 15 ether sent = 5 ether remaining

        // Execute the packet
        verifyAndExecutePackets(bEid, addressToBytes32(address(bOFT)));

        // Get amount can be received from bEid to aEid
        (, uint256 amountCanBeReceived) = aOFT.getAmountCanBeReceived(bEid);
        assertEq(amountCanBeReceived, 10 ether);

        // Now send tokens back from B to A - with Gross accounting, this should not affect the rate limit
        vm.startPrank(userB);
        bToken.approve(address(bOFT), firstSend);
        SendParam memory returnSendParam = SendParam(
            aEid,
            addressToBytes32(userA),
            5 ether,
            5 ether,
            options,
            "",
            ""
        );
        fee = bOFT.quoteSend(returnSendParam, false);
        bOFT.send{ value: fee.nativeFee }(returnSendParam, fee, payable(address(this)));
        vm.stopPrank();

        // Execute the return packet
        verifyAndExecutePackets(aEid, addressToBytes32(address(aOFT)));

        // Verify that sending tokens back did not affect the outbound rate limit
        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 5 ether); // Should still be 5 ether, unchanged by the return transfer

        // Wait for window to expire and verify reset
        skip(31 seconds);
        (, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(amountCanBeSent, 20 ether); // Should be fully reset after the window
    }

    function test_send_with_fee() public {
        uint16 feeBps = 100;
        aOFT.setDefaultFeeBps(feeBps);

        uint256 tokensToSend = 1 ether;
        uint256 tokenFee = tokensToSend * feeBps / 10000;
        uint256 minAmountToCreditLD = tokensToSend - tokenFee;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            minAmountToCreditLD,
            options,
            "",
            ""
        );
        MessagingFee memory protocolFee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(address(aOFT)), 0);
        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: protocolFee.nativeFee }(sendParam, protocolFee, payable(address(this)));
        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(aToken.balanceOf(address(aOFT)), tokensToSend);
        assertEq(bToken.balanceOf(userB), initialBalance + minAmountToCreditLD);
        assertEq(bToken.balanceOf(address(bOFT)), initialBalance - minAmountToCreditLD);
        assertEq(aOFT.feeBalance(), tokenFee);
        assertEq(bOFT.feeBalance(), 0);
    }

    function test_migrate_locked_tokens() public {
        vm.prank(userA);
        aToken.transfer(address(aOFT), initialBalance);

        assertEq(aToken.balanceOf(address(this)), 0);
        assertEq(aToken.balanceOf(address(aOFT)), initialBalance);

        // not owner
        vm.prank(userB);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userB));
        aOFT.migrateLockedTokens(address(this));

        // migrate locked tokens
        aOFT.migrateLockedTokens(address(this));

        assertEq(aToken.balanceOf(address(this)), initialBalance);
        assertEq(aToken.balanceOf(address(aOFT)), 0);
    }

    function test_setPauser() public {
        assertFalse(aOFT.pausers(userA));
        
        vm.prank(userB);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userB));
        aOFT.setPauser(userA, true);
        
        aOFT.setPauser(userA, true);
        assertTrue(aOFT.pausers(userA));
        
        aOFT.setPauser(userA, false);
        assertFalse(aOFT.pausers(userA));
        
        vm.expectEmit(true, true, true, true);
        emit ISkyOFT.PauserSet(userA, true);
        aOFT.setPauser(userA, true);
    }

    function test_pause() public {
        vm.prank(userB);
        vm.expectRevert(abi.encodeWithSelector(ISkyOFT.OnlyPauser.selector, userB));
        aOFT.pause();
        
        aOFT.setPauser(userA, true);
        
        vm.prank(userA);
        aOFT.pause();
        
        // Verify contract is paused by attempting a transfer
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        uint256 dummyNativeFee = 1 ether;
        MessagingFee memory fee = MessagingFee({
            nativeFee: dummyNativeFee,
            lzTokenFee: 0
        });
        
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        aOFT.send{ value: dummyNativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();
    }

    function test_unpause() public {
        aOFT.setPauser(userA, true);
        vm.prank(userA);
        aOFT.pause();
        
        vm.prank(userB);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userB));
        aOFT.unpause();
        
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userA));
        aOFT.unpause();
        
        // Owner can unpause
        aOFT.unpause();
        
        // Verify contract is unpaused by performing a transfer
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);
        
        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();
        
        // Verify the transfer was successful
        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
    }

    function test_multiple_pausers() public {
        aOFT.setPauser(userA, true);
        aOFT.setPauser(userB, true);
        
        assertTrue(aOFT.pausers(userA));
        assertTrue(aOFT.pausers(userB));
        
        vm.prank(userB);
        aOFT.pause();
        
        aOFT.unpause();
        
        vm.prank(userA);
        aOFT.pause();
        
        aOFT.setPauser(userA, false);
        aOFT.setPauser(userB, false);
        
        assertFalse(aOFT.pausers(userA));
        assertFalse(aOFT.pausers(userB));
    }

    function test_send_oft_to_null_address() public {
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(address(0)),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(address(0xdead)), 0);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bToken.balanceOf(address(0xdead)), tokensToSend);
    }

    function test_send_oft_to_inner_token_address() public {
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(address(bToken)),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(address(0xdead)), 0);

        vm.startPrank(userA);
        aToken.approve(address(aOFT), tokensToSend);
        aOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bToken.balanceOf(address(0xdead)), tokensToSend);
    }

    function test_rate_limit_send_with_fee() public {
        uint16 feeBps = 100;
        aOFT.setDefaultFeeBps(feeBps);

        uint256 tokensToSend = 1 ether;
        uint256 tokenFee = tokensToSend * feeBps / 10000;
        uint256 minAmountToCreditLD = tokensToSend - tokenFee;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            minAmountToCreditLD,
            options,
            "",
            ""
        );
        MessagingFee memory protocolFee = aOFT.quoteSend(sendParam, false);

        (uint256 currentSendAmountInFlight, uint256 amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(currentSendAmountInFlight, 0);
        assertEq(amountCanBeSent, 10 ether);

        (uint256 currentReceiveAmountInFlight, uint256 amountCanBeReceived) = aOFT.getAmountCanBeReceived(bEid);
        assertEq(currentReceiveAmountInFlight, 0);
        assertEq(amountCanBeReceived, 10 ether);

        (currentSendAmountInFlight, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(currentSendAmountInFlight, 0);
        assertEq(amountCanBeSent, 10 ether);

        (currentReceiveAmountInFlight, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(currentReceiveAmountInFlight, 0);
        assertEq(amountCanBeReceived, 10 ether);

        vm.startPrank(userA);

        aToken.approve(address(aOFT), tokensToSend);

        aOFT.send{ value: protocolFee.nativeFee }(sendParam, protocolFee, payable(address(this)));

        vm.stopPrank();

        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        (currentSendAmountInFlight, amountCanBeSent) = aOFT.getAmountCanBeSent(bEid);
        assertEq(currentSendAmountInFlight, minAmountToCreditLD);
        assertEq(amountCanBeSent, 10 ether - minAmountToCreditLD);

        (currentReceiveAmountInFlight, amountCanBeReceived) = aOFT.getAmountCanBeReceived(bEid);
        assertEq(currentReceiveAmountInFlight, 0);
        assertEq(amountCanBeReceived, 10 ether);

        (currentSendAmountInFlight, amountCanBeSent) = bOFT.getAmountCanBeSent(aEid);
        assertEq(currentSendAmountInFlight, 0);
        assertEq(amountCanBeSent, 10 ether);

        (currentReceiveAmountInFlight, amountCanBeReceived) = bOFT.getAmountCanBeReceived(aEid);
        assertEq(currentReceiveAmountInFlight, minAmountToCreditLD);
        assertEq(amountCanBeReceived, 10 ether - minAmountToCreditLD);
    }

    function test_quoteOFT_no_fee_returns_empty_array() public view {
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );

        // Test with no fee set (default is 0)
        (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt) = aOFT.quoteOFT(sendParam);
        
        // Should return empty fee details array when no fee is charged
        assertEq(oftFeeDetails.length, 0, "Fee details array should be empty when no fee is charged");
        
        // Verify other return values
        assertEq(oftLimit.minAmountLD, 0, "Min amount should be 0");
        assertEq(oftReceipt.amountSentLD, tokensToSend, "Amount sent should equal tokens to send");
        assertEq(oftReceipt.amountReceivedLD, tokensToSend, "Amount received should equal tokens to send when no fee");
    }

    function test_quoteOFT_with_fee_returns_populated_array() public {
        // Set a fee
        uint16 feeBps = 100; // 1%
        aOFT.setDefaultFeeBps(feeBps);

        uint256 tokensToSend = 1 ether;
        uint256 expectedFee = tokensToSend * feeBps / 10000;
        uint256 expectedAmountReceived = tokensToSend - expectedFee;
        
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            expectedAmountReceived, // min amount after fee
            options,
            "",
            ""
        );

        (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt) = aOFT.quoteOFT(sendParam);
        
        // Should return populated fee details array when fee is charged
        assertEq(oftFeeDetails.length, 1, "Fee details array should have 1 element when fee is charged");
        assertEq(oftFeeDetails[0].feeAmountLD, int256(expectedFee), "Fee amount should match expected fee");
        assertEq(oftFeeDetails[0].description, "SkyOFT: cross-chain transfer fee", "Fee description should match");
        
        // Verify other return values
        assertEq(oftLimit.minAmountLD, 0, "Min amount should be 0");
        assertEq(oftReceipt.amountSentLD, tokensToSend, "Amount sent should equal tokens to send");
        assertEq(oftReceipt.amountReceivedLD, expectedAmountReceived, "Amount received should be after fee deduction");
    }

    function test_quoteOFT_with_dust_removal_and_fee() public {
        // Set a fee
        uint16 feeBps = 50; // 0.5%
        aOFT.setDefaultFeeBps(feeBps);

        // Use an amount that will result in dust after fee calculation
        uint256 tokensToSend = 1000001; // This should create some dust after fee and dust removal
        
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            0, // min amount (we'll accept any amount for this test)
            options,
            "",
            ""
        );

        (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt) = aOFT.quoteOFT(sendParam);
        
        // The dust removal happens in _removeDust, which should remove any remainder
        // If there's a difference between sent and received, should have fee details
        if (oftReceipt.amountSentLD != oftReceipt.amountReceivedLD) {
            assertEq(oftFeeDetails.length, 1, "Fee details array should have 1 element when fee is charged");
            assertEq(oftFeeDetails[0].feeAmountLD, int256(oftReceipt.amountSentLD) - int256(oftReceipt.amountReceivedLD), "Fee amount should match difference");
            assertEq(oftFeeDetails[0].description, "SkyOFT: cross-chain transfer fee", "Fee description should match");
        } else {
            assertEq(oftFeeDetails.length, 0, "Fee details array should be empty when no effective fee");
        }
        
        // Verify other return values
        assertEq(oftLimit.minAmountLD, 0, "Min amount should be 0");
        assertEq(oftReceipt.amountSentLD, tokensToSend, "Amount sent should equal tokens to send");
    }

    function test_quoteOFT_zero_fee_edge_case() public {
        // Explicitly set fee to 0
        aOFT.setDefaultFeeBps(0);

        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );

        (, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt) = aOFT.quoteOFT(sendParam);
        
        // Should return empty fee details array when fee is explicitly 0
        assertEq(oftFeeDetails.length, 0, "Fee details array should be empty when fee is 0");
        
        // Verify amounts are equal
        assertEq(oftReceipt.amountSentLD, oftReceipt.amountReceivedLD, "Sent and received amounts should be equal with 0 fee");
        assertEq(oftReceipt.amountSentLD, tokensToSend, "Amount sent should equal tokens to send");
    }

    function test_quoteOFT_rate_limit_integration() public view {
        uint256 tokensToSend = 5 ether; // Within rate limit
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(userB),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );

        (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt) = aOFT.quoteOFT(sendParam);
        
        // Verify rate limit is properly reflected
        assertEq(oftLimit.minAmountLD, 0, "Min amount should be 0");
        assertGt(oftLimit.maxAmountLD, tokensToSend, "Max amount should be greater than tokens to send");
        
        // Should work without fee
        assertEq(oftFeeDetails.length, 0, "Fee details array should be empty when no fee is charged");
        assertEq(oftReceipt.amountSentLD, tokensToSend, "Amount sent should equal tokens to send");
        assertEq(oftReceipt.amountReceivedLD, tokensToSend, "Amount received should equal tokens to send");
    }
}