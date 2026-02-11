// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {FtsoV2PriceStore, IPricePublisher} from "../../../contracts/ftso/implementation/FtsoV2PriceStore.sol";
import {FtsoV2PriceStoreProxy} from "../../../contracts/ftso/implementation/FtsoV2PriceStoreProxy.sol";
import {IGovernanceSettings} from "@flarenetwork/flare-periphery-contracts/flare/IGovernanceSettings.sol";
import {IRelay} from "@flarenetwork/flare-periphery-contracts/flare/IRelay.sol";

// solhint-disable func-name-mixedcase
contract FtsoV2PriceStoreTest is Test {

    FtsoV2PriceStore private ftsoV2PriceStoreImpl;
    FtsoV2PriceStore private ftsoV2PriceStore;
    FtsoV2PriceStoreProxy private ftsoV2PriceStoreProxy;

    address private relayMock;

    address private governance;
    address private addressUpdater;

    bytes32[] private contractNameHashes;
    address[] private contractAddresses;

    uint64 private firstVotingRoundStartTs;
    uint8 private votingEpochDurationSeconds;
    uint8 private ftsoProtocolId;

    bytes21[] private feedIds;
    string[] private symbols;
    int8[] private trustedDecimals;

    bytes32[] private leaves = new bytes21[](4);

    mapping(string => uint256) private previousTimestamps;
    mapping(string => uint256) private previousTrustedTimestamps;

    function setUp() public {
        relayMock = makeAddr("relayMock");
        governance = makeAddr("governance");
        addressUpdater = makeAddr("addressUpdater");

        firstVotingRoundStartTs = 12345;
        votingEpochDurationSeconds = 90;
        ftsoProtocolId = 30;
        vm.warp(firstVotingRoundStartTs + votingEpochDurationSeconds + 1);

        ftsoV2PriceStoreImpl = new FtsoV2PriceStore();
        ftsoV2PriceStoreProxy = new FtsoV2PriceStoreProxy(
            address(ftsoV2PriceStoreImpl),
            IGovernanceSettings(makeAddr("governanceSettings")),
            governance,
            addressUpdater,
            firstVotingRoundStartTs,
            votingEpochDurationSeconds,
            ftsoProtocolId
        );
        ftsoV2PriceStore = FtsoV2PriceStore(address(ftsoV2PriceStoreProxy));

        contractNameHashes = new bytes32[](2);
        contractAddresses = new address[](2);
        contractNameHashes[0] = keccak256(abi.encode("Relay"));
        contractAddresses[0] = address(relayMock);
        contractNameHashes[1] = keccak256(abi.encode("AddressUpdater"));
        contractAddresses[1] = addressUpdater;
        vm.prank(addressUpdater);
        ftsoV2PriceStore.updateContractAddresses(contractNameHashes, contractAddresses);
    }

    function testFuzz_publishPrices(
        uint32[4] memory valueSeeds,
        int8[4] memory decimalSeeds,
        bytes21[4] memory feedIdSeeds,
        uint256[4] memory trustedValueSeeds,
        uint256 ts
    )
        public
    {
        uint8 numFeeds = 4;
        _setFeeds(numFeeds, decimalSeeds, feedIdSeeds);

        vm.warp(bound(ts, firstVotingRoundStartTs + 1000, type(uint32).max));
        uint32 votingRoundId = _getPreviousVotingEpochId();
        uint256 startTimestamp = _getEndTimestamp(votingRoundId);
        vm.warp(startTimestamp + 1);

        IPricePublisher.TrustedProviderFeed[] memory trustedFeeds =
            new IPricePublisher.TrustedProviderFeed[](numFeeds);
        for (uint256 i = 0; i < numFeeds; i++) {
            trustedFeeds[i] = IPricePublisher.TrustedProviderFeed({
                id: feedIds[i],
                value: uint32(bound(trustedValueSeeds[i], 0, type(uint32).max) / 2),
                decimals: trustedDecimals[i]
            });
        }
        address[] memory trustedProviders = new address[](1);
        trustedProviders[0] = makeAddr("trustedProvider");
        vm.prank(governance);
        ftsoV2PriceStore.setTrustedProviders(trustedProviders, 1);
        vm.prank(makeAddr("trustedProvider"));
        ftsoV2PriceStore.submitTrustedPrices(votingRoundId, trustedFeeds);

        votingRoundId = uint32(bound(votingRoundId, ftsoV2PriceStore.lastPublishedVotingRoundId() + 1,
            type(uint32).max));

        uint256 endTimestamp = _getEndTimestamp(votingRoundId);
        vm.warp(endTimestamp + ftsoV2PriceStore.submitTrustedPricesWindowSeconds() + 1);

        uint32[] memory values = new uint32[](numFeeds);
        int8[] memory decimals = new int8[](numFeeds);

        IPricePublisher.FeedWithProof[] memory proofs = new IPricePublisher.FeedWithProof[](numFeeds);
        for (uint256 i = 0; i < numFeeds; i++) {
            values[i] = uint32(bound(valueSeeds[i], 0, type(uint32).max/2));
            decimals[i] = int8(bound(decimalSeeds[i], -18, 18)); // common decimal range

            IPricePublisher.Feed memory feed = IPricePublisher.Feed({
                id: feedIds[i],
                votingRoundId: votingRoundId,
                value: int32(values[i]),
                decimals: decimals[i],
                turnoutBIPS: 1000
            });

            proofs[i].body = feed;
            leaves[i] = keccak256(abi.encode(feed));
        }

        for (uint256 i = 0; i < numFeeds; i++) {
            proofs[i].proof = _getProof(i);
        }

        vm.mockCall(
            relayMock,
            abi.encodeWithSelector(IRelay.merkleRoots.selector, ftsoProtocolId, votingRoundId),
            abi.encode(_calculateRoot(leaves))
        );

        // Call function
        ftsoV2PriceStore.publishPrices(proofs);

        // Verify state
        for (uint256 i = 0; i < feedIds.length; i++) {
            (uint256 price, uint256 timestamp, uint256 priceDecimals) = ftsoV2PriceStore.getPrice(symbols[i]);
            int256 decimal = decimals[i];
            uint256 uintDecimals;
            uint256 value = values[i];
            if (decimal < 0) {
                uintDecimals = 0;
                value *= 10 ** uint256(-decimal);
            } else {
                uintDecimals = uint256(decimal);
            }
            assertEq(price, value);
            assertEq(priceDecimals, uintDecimals);
            assertEq(timestamp, endTimestamp);

            (uint256 trustedPrice, , uint256 trustedDecimal, uint8 numOfSubmits) =
                ftsoV2PriceStore.getPriceFromTrustedProvidersWithQuality(symbols[i]);
            decimal = trustedDecimals[i];
            value = trustedFeeds[i].value;
            if (decimal < 0) {
                uintDecimals = 0;
                value *= 10 ** uint256(-decimal);
            } else {
                uintDecimals = uint256(decimal);
            }
            assertEq(numOfSubmits, 1);
            assertEq(trustedDecimal, uintDecimals);
            assertEq(trustedPrice, value);
        }
    }

    function _getEndTimestamp(uint256 _votingEpochId) internal view returns(uint256) {
        return firstVotingRoundStartTs + (_votingEpochId + 1) * votingEpochDurationSeconds;
    }

    function _setFeeds(
        uint8 _numFeeds,
        int8[4] memory decimalSeeds,
        bytes21[4] memory feedIdSeeds
    )
        internal
    {
        // generate dynamic feedIds, symbols, and trustedDecimals
        feedIds = new bytes21[](_numFeeds);
        symbols = new string[](_numFeeds);
        trustedDecimals = new int8[](_numFeeds);
        for (uint256 i = 0; i < _numFeeds; i++) {
            feedIds[i] = bytes21(keccak256(abi.encode(feedIdSeeds[i], i)));
            symbols[i] =  string.concat("symbol", vm.toString(i));
            trustedDecimals[i] = int8(bound(decimalSeeds[i], -18, 18)); // Common decimal range
        }
        vm.prank(governance);
        ftsoV2PriceStore.updateSettings(feedIds, symbols, trustedDecimals, 500);
    }


    function _calculateRoot(bytes32[] memory _treeLeaves) public returns (bytes32) {
        bytes32 h12 = _hashPair(_treeLeaves[0], _treeLeaves[1]);
        bytes32 h34 = _hashPair(_treeLeaves[2], _treeLeaves[3]);
        return _hashPair(h12, h34);
    }

    function _getProof(uint256 _index) internal returns (bytes32[] memory proof) {
        require(_index < 4, "Index out of bounds");
        proof = new bytes32[](2);

        if (_index == 0) {
            proof[0] = leaves[1];
            proof[1] = _hashPair(leaves[2], leaves[3]);
        } else if (_index == 1) {
            proof[0] = leaves[0];
            proof[1] = _hashPair(leaves[2], leaves[3]);
        } else if (_index == 2) {
            proof[0] = leaves[3];
            proof[1] = _hashPair(leaves[0], leaves[1]);
        } else {
            proof[0] = leaves[2];
            proof[1] = _hashPair(leaves[0], leaves[1]);
        }
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _getPreviousVotingEpochId() internal view returns(uint32) {
        return uint32((block.timestamp - firstVotingRoundStartTs) / votingEpochDurationSeconds) - 1;
    }
}
