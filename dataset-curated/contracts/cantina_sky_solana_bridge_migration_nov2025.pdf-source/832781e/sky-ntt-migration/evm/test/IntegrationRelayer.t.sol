// SPDX-License-Identifier: Apache 2
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/NttManager/NttManager.sol";
import "../src/Transceiver/Transceiver.sol";
import "../src/interfaces/INttManager.sol";
import "../src/interfaces/IRateLimiter.sol";
import "../src/interfaces/IManagerBase.sol";
import "../src/interfaces/IRateLimiterEvents.sol";
import "../src/interfaces/IWormholeTransceiver.sol";
import "../src/interfaces/IWormholeTransceiverState.sol";
import {Utils} from "./libraries/Utils.sol";
import {DummyToken, DummyTokenMintAndBurn} from "../src/mocks/DummyToken.sol";
import {WormholeTransceiver} from "../src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";
import "../src/libraries/TransceiverStructs.sol";
import "./libraries/TransceiverHelpers.sol";
import "./mocks/MockNttManager.sol";
import "./mocks/MockTransceivers.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/testing/helpers/WormholeSimulator.sol";
import "wormhole-solidity-sdk/Utils.sol";
import {WormholeRelayerBasicTest} from "wormhole-solidity-sdk/testing/WormholeRelayerTest.sol";
import "./libraries/IntegrationHelpers.sol";

contract TestEndToEndRelayer is IntegrationHelpers, IRateLimiterEvents, WormholeRelayerBasicTest {
    NttManager nttManagerChain1;
    NttManager nttManagerChain2;

    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    uint16 constant chainId1 = 4;
    uint16 constant chainId2 = 6;
    uint8 constant FAST_CONSISTENCY_LEVEL = 200;
    uint256 constant GAS_LIMIT = 500000;

    WormholeSimulator guardian;
    uint256 initialBlockTimestamp;

    address userA = address(0x123);
    address userB = address(0x456);
    address userC = address(0x789);
    address userD = address(0xABC);

    constructor() {
        setTestnetForkChains(chainId1, chainId2);
    }

    // https://github.com/wormhole-foundation/hello-wormhole/blob/main/test/HelloWormhole.t.sol#L14C1-L20C6
    // Setup the starting point of the network
    function setUpSource() public override {
        vm.deal(userA, 1 ether);
        DummyToken t1 = new DummyToken();

        NttManager implementation = new MockNttManagerContract(
            address(t1), IManagerBase.Mode.LOCKING, chainId1, 1 days, false
        );

        nttManagerChain1 =
            MockNttManagerContract(address(new ERC1967Proxy(address(implementation), "")));
        nttManagerChain1.initialize();

        wormholeTransceiverChain1 = new MockWormholeTransceiverContract(
            address(nttManagerChain1),
            address(chainInfosTestnet[chainId1].wormhole),
            address(relayerSource),
            address(0x0),
            FAST_CONSISTENCY_LEVEL,
            GAS_LIMIT
        );

        wormholeTransceiverChain1 = MockWormholeTransceiverContract(
            address(new ERC1967Proxy(address(wormholeTransceiverChain1), ""))
        );
        wormholeTransceiverChain1.initialize();
        wormholeTransceiverChain1Other = new MockWormholeTransceiverContract(
            address(nttManagerChain1),
            address(chainInfosTestnet[chainId1].wormhole),
            address(relayerSource),
            address(0x0),
            FAST_CONSISTENCY_LEVEL,
            GAS_LIMIT
        );

        wormholeTransceiverChain1Other = MockWormholeTransceiverContract(
            address(new ERC1967Proxy(address(wormholeTransceiverChain1Other), ""))
        );
        wormholeTransceiverChain1Other.initialize();

        nttManagerChain1.setTransceiver(address(wormholeTransceiverChain1));
        nttManagerChain1.setTransceiver(address(wormholeTransceiverChain1Other));
        nttManagerChain1.setOutboundLimit(type(uint64).max);
        nttManagerChain1.setInboundLimit(type(uint64).max, chainId2);
        nttManagerChain1.setThreshold(1);
    }

    // Setup the chain to relay to of the network
    function setUpTarget() public override {
        vm.deal(userC, 1 ether);

        // Chain 2 setup
        DummyToken t2 = new DummyTokenMintAndBurn();
        NttManager implementationChain2 = new MockNttManagerContract(
            address(t2), IManagerBase.Mode.BURNING, chainId2, 1 days, false
        );

        nttManagerChain2 =
            MockNttManagerContract(address(new ERC1967Proxy(address(implementationChain2), "")));
        nttManagerChain2.initialize();
        wormholeTransceiverChain2 = new MockWormholeTransceiverContract(
            address(nttManagerChain2),
            address(chainInfosTestnet[chainId2].wormhole),
            address(relayerTarget),
            address(0x0),
            FAST_CONSISTENCY_LEVEL,
            GAS_LIMIT
        );

        wormholeTransceiverChain2 = MockWormholeTransceiverContract(
            address(new ERC1967Proxy(address(wormholeTransceiverChain2), ""))
        );
        wormholeTransceiverChain2.initialize();

        wormholeTransceiverChain2Other = new MockWormholeTransceiverContract(
            address(nttManagerChain2),
            address(chainInfosTestnet[chainId2].wormhole),
            address(relayerTarget),
            address(0x0),
            FAST_CONSISTENCY_LEVEL,
            GAS_LIMIT
        );

        wormholeTransceiverChain2Other = MockWormholeTransceiverContract(
            address(new ERC1967Proxy(address(wormholeTransceiverChain2Other), ""))
        );
        wormholeTransceiverChain2Other.initialize();

        nttManagerChain2.setTransceiver(address(wormholeTransceiverChain2));
        nttManagerChain2.setTransceiver(address(wormholeTransceiverChain2Other));
        nttManagerChain2.setOutboundLimit(type(uint64).max);
        nttManagerChain2.setInboundLimit(type(uint64).max, chainId1);

        nttManagerChain2.setThreshold(1);
    }

    function deliverViaRelayer() public {
        vm.selectFork(sourceFork);
        performDelivery();
    }

    function copyBytes(
        bytes memory _bytes
    ) private pure returns (bytes memory) {
        bytes memory copy = new bytes(_bytes.length);
        uint256 max = _bytes.length + 31;
        for (uint256 i = 32; i <= max; i += 32) {
            assembly {
                mstore(add(copy, i), mload(add(_bytes, i)))
            }
        }
        return copy;
    }
}
