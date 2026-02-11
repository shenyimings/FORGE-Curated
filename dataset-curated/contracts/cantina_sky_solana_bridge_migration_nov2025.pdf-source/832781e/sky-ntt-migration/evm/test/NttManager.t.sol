// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/NttManager/NttManager.sol";
import "../src/interfaces/INttManager.sol";
import "../src/interfaces/IRateLimiter.sol";
import "../src/interfaces/IManagerBase.sol";
import "../src/interfaces/IRateLimiterEvents.sol";
import "../src/NttManager/TransceiverRegistry.sol";
import "../src/libraries/PausableUpgradeable.sol";
import "../src/libraries/TransceiverHelpers.sol";
import {Utils} from "./libraries/Utils.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/testing/helpers/WormholeSimulator.sol";
import "wormhole-solidity-sdk/Utils.sol";
import "./libraries/TransceiverHelpers.sol";
import "./libraries/NttManagerHelpers.sol";
import "./interfaces/ITransceiverReceiver.sol";
import "./mocks/DummyTransceiver.sol";
import "../src/mocks/DummyToken.sol";
import "./mocks/MockNttManager.sol";

// TODO: set this up so the common functionality tests can be run against both
contract TestNttManager is Test, IRateLimiterEvents {
    MockNttManagerContract nttManager;
    MockNttManagerContract nttManagerOther;
    MockNttManagerContract nttManagerZeroRateLimiter;

    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    // 0x99'E''T''T'
    uint16 constant chainId = 7;
    uint16 constant chainId2 = 8;
    uint256 constant DEVNET_GUARDIAN_PK =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
    WormholeSimulator guardian;
    uint256 initialBlockTimestamp;
    DummyTransceiver dummyTransceiver;

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

        NttManager otherImplementation = new MockNttManagerContract(
            address(t), IManagerBase.Mode.LOCKING, chainId, 1 days, false
        );

        nttManager = MockNttManagerContract(address(new ERC1967Proxy(address(implementation), "")));
        nttManager.initialize();

        nttManagerOther =
            MockNttManagerContract(address(new ERC1967Proxy(address(otherImplementation), "")));
        nttManagerOther.initialize();

        dummyTransceiver = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(dummyTransceiver));
    }

    // === pure unit tests

    // naive implementation of countSetBits to test against
    function simpleCount(
        uint64 n
    ) public pure returns (uint8) {
        uint8 count;

        while (n > 0) {
            count += uint8(n & 1);
            n >>= 1;
        }

        return count;
    }

    function testFuzz_countSetBits(
        uint64 n
    ) public {
        assertEq(simpleCount(n), countSetBits(n));
    }

    // === ownership

    function test_owner() public {
        // TODO: implement separate governance contract
        assertEq(nttManager.owner(), address(this));
    }

    function test_transferOwnership() public {
        address newOwner = address(0x123);
        nttManager.transferOwnership(newOwner);
        assertEq(nttManager.owner(), newOwner);
    }

    function test_onlyOwnerCanTransferOwnership() public {
        address notOwner = address(0x123);
        vm.startPrank(notOwner);

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner)
        );
        nttManager.transferOwnership(address(0x456));
    }

    function test_pauseUnpause() public {
        assertEq(nttManager.isPaused(), false);
        nttManager.pause();
        assertEq(nttManager.isPaused(), true);

        // When the NttManager is paused, initiating transfers, completing queued transfers on both source and destination chains,
        // executing transfers and attesting to transfers should all revert
        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.RequireContractIsNotPaused.selector)
        );
        nttManager.completeOutboundQueuedTransfer(0);

        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.RequireContractIsNotPaused.selector)
        );
        nttManager.completeInboundQueuedTransfer(bytes32(0));

        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.RequireContractIsNotPaused.selector)
        );
        TransceiverStructs.NttManagerMessage memory message;
        nttManager.executeMsg(0, bytes32(0), message);

        bytes memory transceiverMessage;
        (, transceiverMessage) = TransceiverHelpersLib.buildTransceiverMessageWithNttManagerPayload(
            0,
            bytes32(0),
            toWormholeFormat(address(nttManagerOther)),
            toWormholeFormat(address(nttManager)),
            abi.encode("payload")
        );
        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.RequireContractIsNotPaused.selector)
        );
        dummyTransceiver.receiveMessage(transceiverMessage);

        nttManager.unpause();
        assertEq(nttManager.isPaused(), false);
    }

    function test_pausePauserUnpauseOnlyOwner() public {
        // transfer pauser to another address
        address pauser = address(0x123);
        nttManager.transferPauserCapability(pauser);

        // execute from pauser context
        vm.startPrank(pauser);
        assertEq(nttManager.isPaused(), false);
        nttManager.pause();
        assertEq(nttManager.isPaused(), true);

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, pauser)
        );
        nttManager.unpause();

        // execute from owner context
        // ensures that owner can still unpause
        vm.startPrank(address(this));
        nttManager.unpause();
        assertEq(nttManager.isPaused(), false);
    }

    // === transceiver registration

    function test_registerTransceiver() public {
        DummyTransceiver e = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e));
    }

    function test_onlyOwnerCanModifyTransceivers() public {
        DummyTransceiver e = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e));

        address notOwner = address(0x123);
        vm.startPrank(notOwner);

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner)
        );
        nttManager.setTransceiver(address(e));

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner)
        );
        nttManager.removeTransceiver(address(e));
    }

    function test_cantEnableTransceiverTwice() public {
        DummyTransceiver e = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e));

        vm.expectRevert(
            abi.encodeWithSelector(
                TransceiverRegistry.TransceiverAlreadyEnabled.selector, address(e)
            )
        );
        nttManager.setTransceiver(address(e));
    }

    function test_disableReenableTransceiver() public {
        DummyTransceiver e = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e));
        nttManager.removeTransceiver(address(e));
        nttManager.setTransceiver(address(e));
    }

    function test_disableAllTransceiversFails() public {
        vm.expectRevert(abi.encodeWithSelector(IManagerBase.ZeroThreshold.selector));
        nttManager.removeTransceiver(address(dummyTransceiver));
    }

    function test_multipleTransceivers() public {
        DummyTransceiver e1 = new DummyTransceiver(address(nttManager));
        DummyTransceiver e2 = new DummyTransceiver(address(nttManager));

        nttManager.setTransceiver(address(e1));
        nttManager.setTransceiver(address(e2));
    }

    function test_transceiverIncompatibleNttManager() public {
        // Transceiver instantiation reverts if the nttManager doesn't have the proper token method
        vm.expectRevert(bytes(""));
        new DummyTransceiver(address(0xBEEF));
    }

    function test_transceiverWrongNttManager() public {
        // TODO: this is accepted currently. should we include a check to ensure
        // only transceivers whose nttManager is us can be registered? (this would be
        // a convenience check, not a security one)
        DummyToken t = new DummyToken();
        NttManager altNttManager = new MockNttManagerContract(
            address(t), IManagerBase.Mode.LOCKING, chainId, 1 days, false
        );
        DummyTransceiver e = new DummyTransceiver(address(altNttManager));
        nttManager.setTransceiver(address(e));
    }

    function test_notTransceiver() public {
        // TODO: this is accepted currently. should we include a check to ensure
        // only transceivers can be registered? (this would be a convenience check, not a security one)
        nttManager.setTransceiver(address(0x123));
    }

    function test_maxOutTransceivers() public {
        // Let's register a transceiver and then disable it. We now have 2 registered managers
        // since we register 1 in the setup
        DummyTransceiver e = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e));
        nttManager.removeTransceiver(address(e));

        // We should be able to register 64 transceivers total
        for (uint256 i = 0; i < 62; ++i) {
            DummyTransceiver d = new DummyTransceiver(address(nttManager));
            nttManager.setTransceiver(address(d));
        }

        // Registering a new transceiver should fail as we've hit the cap
        DummyTransceiver c = new DummyTransceiver(address(nttManager));
        vm.expectRevert(TransceiverRegistry.TooManyTransceivers.selector);
        nttManager.setTransceiver(address(c));

        // We should be able to renable an already registered transceiver at the cap
        nttManager.setTransceiver(address(e));
    }

    // == threshold

    function test_cantSetThresholdTooHigh() public {
        // 1 transceiver set, so can't set threshold to 2
        vm.expectRevert(abi.encodeWithSelector(IManagerBase.ThresholdTooHigh.selector, 2, 1));
        nttManager.setThreshold(2);
    }

    function test_canSetThreshold() public {
        DummyTransceiver e1 = new DummyTransceiver(address(nttManager));
        DummyTransceiver e2 = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e1));
        nttManager.setTransceiver(address(e2));

        nttManager.setThreshold(1);
        nttManager.setThreshold(2);
        nttManager.setThreshold(1);
    }

    function test_cantSetThresholdToZero() public {
        DummyTransceiver e = new DummyTransceiver(address(nttManager));
        nttManager.setTransceiver(address(e));

        vm.expectRevert(abi.encodeWithSelector(IManagerBase.ZeroThreshold.selector));
        nttManager.setThreshold(0);
    }

    function test_onlyOwnerCanSetThreshold() public {
        address notOwner = address(0x123);
        vm.startPrank(notOwner);

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner)
        );
        nttManager.setThreshold(1);
    }

    // == threshold

    function test_peerRegistrationLimitsCanBeUpdated() public {
        bytes32 peer = toWormholeFormat(address(nttManager));
        nttManager.setPeer(TransceiverHelpersLib.SENDING_CHAIN_ID, peer, 9, 0);

        IRateLimiter.RateLimitParams memory params =
            nttManager.getInboundLimitParams(TransceiverHelpersLib.SENDING_CHAIN_ID);
        assertEq(params.limit.getAmount(), 0);
        assertEq(params.limit.getDecimals(), 8);

        nttManager.setInboundLimit(type(uint64).max, TransceiverHelpersLib.SENDING_CHAIN_ID);
        params = nttManager.getInboundLimitParams(TransceiverHelpersLib.SENDING_CHAIN_ID);
        assertEq(params.limit.getAmount(), type(uint64).max / 10 ** (18 - 8));
        assertEq(params.limit.getDecimals(), 8);
    }

    // === attestation

    function test_onlyEnabledTransceiversCanAttest() public {
        (DummyTransceiver e1,) = TransceiverHelpersLib.setup_transceivers(nttManagerOther);
        nttManagerOther.removeTransceiver(address(e1));
        bytes32 peer = toWormholeFormat(address(nttManager));
        nttManagerOther.setPeer(TransceiverHelpersLib.SENDING_CHAIN_ID, peer, 9, type(uint64).max);

        bytes memory transceiverMessage;
        (, transceiverMessage) = TransceiverHelpersLib.buildTransceiverMessageWithNttManagerPayload(
            0, bytes32(0), peer, toWormholeFormat(address(nttManagerOther)), abi.encode("payload")
        );

        vm.expectRevert(
            abi.encodeWithSelector(TransceiverRegistry.CallerNotTransceiver.selector, address(e1))
        );
        e1.receiveMessage(transceiverMessage);
    }

    function test_onlyPeerNttManagerCanAttest() public {
        (DummyTransceiver e1,) = TransceiverHelpersLib.setup_transceivers(nttManagerOther);
        nttManagerOther.setThreshold(2);

        bytes32 peer = toWormholeFormat(address(nttManager));

        TransceiverStructs.NttManagerMessage memory nttManagerMessage;
        bytes memory transceiverMessage;
        (nttManagerMessage, transceiverMessage) = TransceiverHelpersLib
            .buildTransceiverMessageWithNttManagerPayload(
            0, bytes32(0), peer, toWormholeFormat(address(nttManagerOther)), abi.encode("payload")
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                INttManager.InvalidPeer.selector, TransceiverHelpersLib.SENDING_CHAIN_ID, peer
            )
        );
        e1.receiveMessage(transceiverMessage);
    }

    function test_attestSimple() public {
        (DummyTransceiver e1,) = TransceiverHelpersLib.setup_transceivers(nttManagerOther);
        nttManagerOther.setThreshold(2);

        // register nttManager peer
        bytes32 peer = toWormholeFormat(address(nttManager));
        nttManagerOther.setPeer(TransceiverHelpersLib.SENDING_CHAIN_ID, peer, 9, type(uint64).max);

        TransceiverStructs.NttManagerMessage memory nttManagerMessage;
        bytes memory transceiverMessage;
        (nttManagerMessage, transceiverMessage) = TransceiverHelpersLib
            .buildTransceiverMessageWithNttManagerPayload(
            0, bytes32(0), peer, toWormholeFormat(address(nttManagerOther)), abi.encode("payload")
        );

        e1.receiveMessage(transceiverMessage);

        bytes32 hash = TransceiverStructs.nttManagerMessageDigest(
            TransceiverHelpersLib.SENDING_CHAIN_ID, nttManagerMessage
        );
        assertEq(nttManagerOther.messageAttestations(hash), 1);
    }

    function test_attestTwice() public {
        (DummyTransceiver e1,) = TransceiverHelpersLib.setup_transceivers(nttManagerOther);
        nttManagerOther.setThreshold(2);

        // register nttManager peer
        bytes32 peer = toWormholeFormat(address(nttManager));
        nttManagerOther.setPeer(TransceiverHelpersLib.SENDING_CHAIN_ID, peer, 9, type(uint64).max);

        TransceiverStructs.NttManagerMessage memory nttManagerMessage;
        bytes memory transceiverMessage;
        (nttManagerMessage, transceiverMessage) = TransceiverHelpersLib
            .buildTransceiverMessageWithNttManagerPayload(
            0, bytes32(0), peer, toWormholeFormat(address(nttManagerOther)), abi.encode("payload")
        );

        bytes32 hash = TransceiverStructs.nttManagerMessageDigest(
            TransceiverHelpersLib.SENDING_CHAIN_ID, nttManagerMessage
        );

        e1.receiveMessage(transceiverMessage);
        vm.expectRevert(
            abi.encodeWithSelector(IManagerBase.TransceiverAlreadyAttestedToMessage.selector, hash)
        );
        e1.receiveMessage(transceiverMessage);

        // can't double vote
        assertEq(nttManagerOther.messageAttestations(hash), 1);
    }

    function test_attestDisabled() public {
        (DummyTransceiver e1,) = TransceiverHelpersLib.setup_transceivers(nttManagerOther);
        nttManagerOther.setThreshold(2);

        bytes32 peer = toWormholeFormat(address(nttManager));
        nttManagerOther.setPeer(TransceiverHelpersLib.SENDING_CHAIN_ID, peer, 9, type(uint64).max);

        ITransceiverReceiver[] memory transceivers = new ITransceiverReceiver[](1);
        transceivers[0] = e1;

        TransceiverStructs.NttManagerMessage memory m;
        (m,) = TransceiverHelpersLib.attestTransceiversHelper(
            address(0x456),
            0,
            chainId,
            nttManager,
            nttManagerOther,
            packTrimmedAmount(50, 8),
            packTrimmedAmount(type(uint64).max, 8),
            transceivers
        );

        nttManagerOther.removeTransceiver(address(e1));

        bytes32 hash =
            TransceiverStructs.nttManagerMessageDigest(TransceiverHelpersLib.SENDING_CHAIN_ID, m);
        // a disabled transceiver's vote no longer counts
        assertEq(nttManagerOther.messageAttestations(hash), 0);

        nttManagerOther.setTransceiver(address(e1));
        // it counts again when reenabled
        assertEq(nttManagerOther.messageAttestations(hash), 1);
    }

    function test_attestationQuorum() public {
        address user_B = address(0x456);

        (DummyTransceiver e1, DummyTransceiver e2) =
            TransceiverHelpersLib.setup_transceivers(nttManagerOther);

        TrimmedAmount transferAmount = packTrimmedAmount(50, 8);

        TransceiverStructs.NttManagerMessage memory m;
        bytes memory encodedEm;
        {
            ITransceiverReceiver[] memory transceivers = new ITransceiverReceiver[](2);
            transceivers[0] = e1;
            transceivers[1] = e2;

            TransceiverStructs.TransceiverMessage memory em;
            (m, em) = TransceiverHelpersLib.attestTransceiversHelper(
                user_B,
                0,
                chainId,
                nttManager,
                nttManagerOther,
                transferAmount,
                packTrimmedAmount(type(uint64).max, 8),
                transceivers
            );
            encodedEm = TransceiverStructs.encodeTransceiverMessage(
                TransceiverHelpersLib.TEST_TRANSCEIVER_PAYLOAD_PREFIX, em
            );
        }

        {
            DummyToken token = DummyToken(nttManager.token());
            assertEq(token.balanceOf(address(user_B)), transferAmount.untrim(token.decimals()));
        }

        // replay protection for transceiver
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IManagerBase.TransceiverAlreadyAttestedToMessage.selector,
                TransceiverStructs.nttManagerMessageDigest(
                    TransceiverHelpersLib.SENDING_CHAIN_ID, m
                )
            )
        );
        e2.receiveMessage(encodedEm);
    }

    // TODO:
    // currently there is no way to test the threshold logic and the duplicate
    // protection logic without setting up the business logic as well.
    //
    // we should separate the business logic out from the transceiver handling.
    // that way the functionality could be tested separately (and the contracts
    // would also be more reusable)

    // === storage

    function test_noAutomaticSlot() public {
        DummyToken t = new DummyToken();
        MockNttManagerContract c =
            new MockNttManagerContract(address(t), IManagerBase.Mode.LOCKING, 1, 1 days, false);
        assertEq(c.lastSlot(), 0x0);
    }

    function test_constructor() public {
        DummyToken t = new DummyToken();

        vm.startStateDiffRecording();

        new MockNttManagerContract(address(t), IManagerBase.Mode.LOCKING, 1, 1 days, false);

        Utils.assertSafeUpgradeableConstructor(vm.stopAndReturnStateDiff());
    }

    // === upgradeability
    function expectRevert(
        address contractAddress,
        bytes memory encodedSignature,
        bytes memory expectedRevert
    ) internal {
        (bool success, bytes memory result) = contractAddress.call(encodedSignature);
        require(!success, "call did not revert");

        require(keccak256(result) == keccak256(expectedRevert), "call did not revert as expected");
    }

    function test_upgradeNttManager() public {
        // The testing strategy here is as follows:
        // Step 1: Deploy the nttManager contract with two transceivers and
        //         receive a message through it.
        // Step 2: Upgrade it to a new nttManager contract an use the same transceivers to receive
        //         a new message through it.
        // Step 3: Upgrade back to the standalone contract (with two
        //           transceivers) and receive a message through it.
        // This ensures that the storage slots don't get clobbered through the upgrades.

        address user_B = address(0x456);
        DummyToken token = DummyToken(nttManager.token());
        TrimmedAmount transferAmount = packTrimmedAmount(50, 8);
        (ITransceiverReceiver e1, ITransceiverReceiver e2) =
            TransceiverHelpersLib.setup_transceivers(nttManagerOther);

        // Step 1 (contract is deployed by setUp())
        ITransceiverReceiver[] memory transceivers = new ITransceiverReceiver[](2);
        transceivers[0] = e1;
        transceivers[1] = e2;

        TransceiverStructs.NttManagerMessage memory m;
        bytes memory encodedEm;
        {
            TransceiverStructs.TransceiverMessage memory em;
            (m, em) = TransceiverHelpersLib.attestTransceiversHelper(
                user_B,
                0,
                chainId,
                nttManager,
                nttManagerOther,
                transferAmount,
                packTrimmedAmount(type(uint64).max, 8),
                transceivers
            );
            encodedEm = TransceiverStructs.encodeTransceiverMessage(
                TransceiverHelpersLib.TEST_TRANSCEIVER_PAYLOAD_PREFIX, em
            );
        }

        assertEq(token.balanceOf(address(user_B)), transferAmount.untrim(token.decimals()));

        // Step 2 (upgrade to a new nttManager)
        MockNttManagerContract newNttManager = new MockNttManagerContract(
            nttManager.token(), IManagerBase.Mode.LOCKING, chainId, 1 days, false
        );
        nttManagerOther.upgrade(address(newNttManager));

        TransceiverHelpersLib.attestTransceiversHelper(
            user_B,
            bytes32(uint256(1)),
            chainId,
            nttManager, // this is the proxy
            nttManagerOther, // this is the proxy
            transferAmount,
            packTrimmedAmount(type(uint64).max, 8),
            transceivers
        );

        assertEq(token.balanceOf(address(user_B)), transferAmount.untrim(token.decimals()) * 2);
    }

    function test_migrateLockedTokens() public {
        DummyToken token = DummyToken(nttManager.token());

        address tokenReceiver = makeAddr("tokenReceiver");

        uint8 decimals = token.decimals();

        token.mintDummy(address(nttManager), 5 * 10 ** decimals);

        vm.startPrank(address(0x123));
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(0x123)
            )
        );
        nttManager.migrateLockedTokens(tokenReceiver);
        vm.stopPrank();

        vm.startPrank(nttManager.owner());
        nttManager.migrateLockedTokens(tokenReceiver);
        vm.stopPrank();

        assertEq(token.balanceOf(address(nttManager)), 0);
        assertEq(token.balanceOf(tokenReceiver), 5 * 10 ** decimals);
    }
}
