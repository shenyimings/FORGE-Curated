// SPDX-License-Identifier: Apache 2

import "forge-std/Test.sol";
import "../src/interfaces/IRateLimiterEvents.sol";
import "../src/interfaces/IManagerBase.sol";
import "../src/NttManager/NttManager.sol";
import "./mocks/DummyTransceiver.sol";
import "../src/mocks/DummyToken.sol";
import "./mocks/MockNttManager.sol";
import "wormhole-solidity-sdk/testing/helpers/WormholeSimulator.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./libraries/TransceiverHelpers.sol";
import "./libraries/NttManagerHelpers.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

pragma solidity >=0.8.8 <0.9.0;

contract TestRateLimit is Test, IRateLimiterEvents {
    MockNttManagerContract nttManager;

    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;
    using BytesParsing for bytes;

    uint16 constant chainId = 7;
    uint16 constant chainId2 = 8;

    uint256 constant DEVNET_GUARDIAN_PK =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
    WormholeSimulator guardian;
    uint256 initialBlockTimestamp;

    function setUp() public {
        string memory url = "https://ethereum-sepolia-rpc.publicnode.com";
        IWormhole wormhole = IWormhole(0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78);
        vm.createSelectFork(url);
        initialBlockTimestamp = vm.getBlockTimestamp();

        guardian = new WormholeSimulator(address(wormhole), DEVNET_GUARDIAN_PK);

        DummyToken t = new DummyToken();
        NttManager implementation = new MockNttManagerContract(
            address(t), IManagerBase.Mode.LOCKING, chainId, 1 days, false
        );

        nttManager = MockNttManagerContract(address(new ERC1967Proxy(address(implementation), "")));
        nttManager.initialize();

        nttManager.setPeer(chainId2, toWormholeFormat(address(0x1)), 9, type(uint64).max);

        DummyTransceiver e = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e));
    }

    function test_outboundRateLimit_setLimitSimple() public {
        DummyToken token = DummyToken(nttManager.token());
        uint8 decimals = token.decimals();

        uint256 limit = 1 * 10 ** 6;
        nttManager.setOutboundLimit(limit);

        IRateLimiter.RateLimitParams memory outboundLimitParams =
            nttManager.getOutboundLimitParams();

        assertEq(outboundLimitParams.limit.getAmount(), limit.trim(decimals, decimals).getAmount());
        assertEq(
            outboundLimitParams.currentCapacity.getAmount(),
            limit.trim(decimals, decimals).getAmount()
        );
        assertEq(outboundLimitParams.lastTxTimestamp, initialBlockTimestamp);
    }

    function test_inboundRateLimit_simple() public {
        address user_B = address(0x456);

        (DummyTransceiver e1, DummyTransceiver e2) =
            TransceiverHelpersLib.setup_transceivers(nttManager);

        DummyToken token = DummyToken(nttManager.token());

        ITransceiverReceiver[] memory transceivers = new ITransceiverReceiver[](2);
        transceivers[0] = e1;
        transceivers[1] = e2;

        TrimmedAmount transferAmount = packTrimmedAmount(50, 8);
        TrimmedAmount limitAmount = packTrimmedAmount(100, 8);
        TransceiverHelpersLib.attestTransceiversHelper(
            user_B, 0, chainId, nttManager, nttManager, transferAmount, limitAmount, transceivers
        );

        // assert that the user received tokens
        assertEq(token.balanceOf(address(user_B)), transferAmount.untrim(token.decimals()));

        // assert that the inbound limits updated
        IRateLimiter.RateLimitParams memory inboundLimitParams =
            nttManager.getInboundLimitParams(TransceiverHelpersLib.SENDING_CHAIN_ID);
        assertEq(
            inboundLimitParams.currentCapacity.getAmount(),
            (limitAmount - (transferAmount)).getAmount()
        );
        assertEq(inboundLimitParams.lastTxTimestamp, initialBlockTimestamp);

        // assert that the outbound limit is still at the max
        // backflow should not go over the max limit
        IRateLimiter.RateLimitParams memory outboundLimitParams =
            nttManager.getOutboundLimitParams();
        assertEq(
            outboundLimitParams.currentCapacity.getAmount(), outboundLimitParams.limit.getAmount()
        );
        assertEq(outboundLimitParams.lastTxTimestamp, initialBlockTimestamp);
    }

    function test_inboundRateLimit_queue() public {
        address user_B = address(0x456);

        (DummyTransceiver e1, DummyTransceiver e2) =
            TransceiverHelpersLib.setup_transceivers(nttManager);

        DummyToken token = DummyToken(nttManager.token());

        ITransceiverReceiver[] memory transceivers = new ITransceiverReceiver[](1);
        transceivers[0] = e1;

        TransceiverStructs.NttManagerMessage memory m;
        bytes memory encodedEm;
        {
            TransceiverStructs.TransceiverMessage memory em;
            (m, em) = TransceiverHelpersLib.attestTransceiversHelper(
                user_B,
                0,
                chainId,
                nttManager,
                nttManager,
                packTrimmedAmount(50, 8),
                uint256(5).trim(token.decimals(), token.decimals()),
                transceivers
            );
            encodedEm = TransceiverStructs.encodeTransceiverMessage(
                TransceiverHelpersLib.TEST_TRANSCEIVER_PAYLOAD_PREFIX, em
            );
        }

        bytes32 digest =
            TransceiverStructs.nttManagerMessageDigest(TransceiverHelpersLib.SENDING_CHAIN_ID, m);

        // no quorum yet
        assertEq(token.balanceOf(address(user_B)), 0);

        vm.expectEmit(address(nttManager));
        emit InboundTransferQueued(digest);
        e2.receiveMessage(encodedEm);

        {
            // now we have quorum but it'll hit limit
            IRateLimiter.InboundQueuedTransfer memory qt =
                nttManager.getInboundQueuedTransfer(digest);
            assertEq(qt.amount.getAmount(), 50);
            assertEq(qt.txTimestamp, initialBlockTimestamp);
            assertEq(qt.recipient, user_B);
        }

        // assert that the user doesn't have funds yet
        assertEq(token.balanceOf(address(user_B)), 0);

        // change block time to (duration - 1) seconds later
        uint256 durationElapsedTime = initialBlockTimestamp + nttManager.rateLimitDuration();
        vm.warp(durationElapsedTime - 1);

        {
            // assert that transfer still can't be completed
            vm.expectRevert(
                abi.encodeWithSelector(
                    IRateLimiter.InboundQueuedTransferStillQueued.selector,
                    digest,
                    initialBlockTimestamp
                )
            );
            nttManager.completeInboundQueuedTransfer(digest);
        }

        // now complete transfer
        vm.warp(durationElapsedTime);
        nttManager.completeInboundQueuedTransfer(digest);

        {
            // assert transfer no longer in queue
            vm.expectRevert(
                abi.encodeWithSelector(IRateLimiter.InboundQueuedTransferNotFound.selector, digest)
            );
            nttManager.completeInboundQueuedTransfer(digest);
        }

        // assert user now has funds
        assertEq(token.balanceOf(address(user_B)), 50 * 10 ** (token.decimals() - 8));

        // replay protection on executeMsg
        vm.recordLogs();
        nttManager.executeMsg(
            TransceiverHelpersLib.SENDING_CHAIN_ID, toWormholeFormat(address(nttManager)), m
        );

        {
            Vm.Log[] memory entries = vm.getRecordedLogs();
            assertEq(entries.length, 1);
            assertEq(entries[0].topics.length, 3);
            assertEq(entries[0].topics[0], keccak256("MessageAlreadyExecuted(bytes32,bytes32)"));
            assertEq(entries[0].topics[1], toWormholeFormat(address(nttManager)));
            assertEq(
                entries[0].topics[2],
                TransceiverStructs.nttManagerMessageDigest(
                    TransceiverHelpersLib.SENDING_CHAIN_ID, m
                )
            );
        }
    }

    // helper functions
    function setupToken() public returns (address, address, DummyToken, uint8) {
        address user_A = address(0x123);
        address user_B = address(0x456);

        DummyToken token = DummyToken(nttManager.token());

        uint8 decimals = token.decimals();
        assertEq(decimals, 18);

        return (user_A, user_B, token, decimals);
    }

    function initializeTransceivers() public returns (ITransceiverReceiver[] memory) {
        (DummyTransceiver e1, DummyTransceiver e2) =
            TransceiverHelpersLib.setup_transceivers(nttManager);

        ITransceiverReceiver[] memory transceivers = new ITransceiverReceiver[](2);
        transceivers[0] = e1;
        transceivers[1] = e2;

        return transceivers;
    }

    function expectRevert(
        address contractAddress,
        bytes memory encodedSignature,
        string memory expectedRevert
    ) internal {
        (bool success, bytes memory result) = contractAddress.call(encodedSignature);
        require(!success, "call did not revert");

        console.log("result: %s", result.length);
        // // compare revert strings
        bytes32 expectedRevertHash = keccak256(abi.encode(expectedRevert));
        (bytes memory res,) = result.slice(4, result.length - 4);
        bytes32 actualRevertHash = keccak256(abi.encodePacked(res));
        require(expectedRevertHash == actualRevertHash, "call did not revert as expected");
    }

    function testFuzz_inboundRateLimitShouldQueue(uint256 inboundLimitAmt, uint256 amount) public {
        amount = bound(amount, 1, type(uint64).max);
        inboundLimitAmt = bound(amount, 0, amount - 1);

        address user_B = address(0x456);

        (DummyTransceiver e1, DummyTransceiver e2) =
            TransceiverHelpersLib.setup_transceivers(nttManager);

        DummyToken token = DummyToken(nttManager.token());

        ITransceiverReceiver[] memory transceivers = new ITransceiverReceiver[](1);
        transceivers[0] = e1;

        TransceiverStructs.NttManagerMessage memory m;
        bytes memory encodedEm;
        uint256 inboundLimit = inboundLimitAmt;
        TrimmedAmount trimmedAmount = packTrimmedAmount(uint64(amount), 8);
        {
            TransceiverStructs.TransceiverMessage memory em;
            (m, em) = TransceiverHelpersLib.attestTransceiversHelper(
                user_B,
                0,
                chainId,
                nttManager,
                nttManager,
                trimmedAmount,
                inboundLimit.trim(token.decimals(), token.decimals()),
                transceivers
            );
            encodedEm = TransceiverStructs.encodeTransceiverMessage(
                TransceiverHelpersLib.TEST_TRANSCEIVER_PAYLOAD_PREFIX, em
            );
        }

        bytes32 digest =
            TransceiverStructs.nttManagerMessageDigest(TransceiverHelpersLib.SENDING_CHAIN_ID, m);

        // no quorum yet
        assertEq(token.balanceOf(address(user_B)), 0);

        vm.expectEmit(address(nttManager));
        emit InboundTransferQueued(digest);
        e2.receiveMessage(encodedEm);

        {
            // now we have quorum but it'll hit limit
            IRateLimiter.InboundQueuedTransfer memory qt =
                nttManager.getInboundQueuedTransfer(digest);
            assertEq(qt.amount.getAmount(), trimmedAmount.getAmount());
            assertEq(qt.txTimestamp, initialBlockTimestamp);
            assertEq(qt.recipient, user_B);
        }

        // assert that the user doesn't have funds yet
        assertEq(token.balanceOf(address(user_B)), 0);

        // change block time to (duration - 1) seconds later
        uint256 durationElapsedTime = initialBlockTimestamp + nttManager.rateLimitDuration();
        vm.warp(durationElapsedTime - 1);

        {
            // assert that transfer still can't be completed
            vm.expectRevert(
                abi.encodeWithSelector(
                    IRateLimiter.InboundQueuedTransferStillQueued.selector,
                    digest,
                    initialBlockTimestamp
                )
            );
            nttManager.completeInboundQueuedTransfer(digest);
        }

        // now complete transfer
        vm.warp(durationElapsedTime);
        nttManager.completeInboundQueuedTransfer(digest);

        {
            // assert transfer no longer in queue
            vm.expectRevert(
                abi.encodeWithSelector(IRateLimiter.InboundQueuedTransferNotFound.selector, digest)
            );
            nttManager.completeInboundQueuedTransfer(digest);
        }

        // assert user now has funds
        assertEq(
            token.balanceOf(address(user_B)),
            trimmedAmount.getAmount() * 10 ** (token.decimals() - 8)
        );

        // replay protection on executeMsg
        vm.recordLogs();
        nttManager.executeMsg(
            TransceiverHelpersLib.SENDING_CHAIN_ID, toWormholeFormat(address(nttManager)), m
        );

        {
            Vm.Log[] memory entries = vm.getRecordedLogs();
            assertEq(entries.length, 1);
            assertEq(entries[0].topics.length, 3);
            assertEq(entries[0].topics[0], keccak256("MessageAlreadyExecuted(bytes32,bytes32)"));
            assertEq(entries[0].topics[1], toWormholeFormat(address(nttManager)));
            assertEq(
                entries[0].topics[2],
                TransceiverStructs.nttManagerMessageDigest(
                    TransceiverHelpersLib.SENDING_CHAIN_ID, m
                )
            );
        }
    }
}
