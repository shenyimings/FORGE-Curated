// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {FtsoV2PriceStore, IPricePublisher} from "../../../contracts/ftso/implementation/FtsoV2PriceStore.sol";
import {IRelay} from "@flarenetwork/flare-periphery-contracts/flare/IRelay.sol";

contract FtsoV2PriceStoreHandler is Test {
    FtsoV2PriceStore public ftsoV2PriceStore;
    address public governance;
    address public relayMock;
    uint64 public firstVotingRoundStartTs;
    uint8 public votingEpochDurationSeconds;
    uint8 public ftsoProtocolId;

    bytes21[] public feedIds;
    string[] public symbols;
    int8[] public fixedTrustedDecimals;
    bytes21[] public fixedFeedIds;
    string[] public fixedSymbols;

    constructor(
        FtsoV2PriceStore _ftsoV2PriceStore,
        address _governance,
        address _relayMock,
        uint64 _firstVotingRoundStartTs,
        uint8 _votingEpochDurationSeconds,
        uint8 _ftsoProtocolId
    ) {
        ftsoV2PriceStore = _ftsoV2PriceStore;
        governance = _governance;
        relayMock = _relayMock;
        firstVotingRoundStartTs = _firstVotingRoundStartTs;
        votingEpochDurationSeconds = _votingEpochDurationSeconds;
        ftsoProtocolId = _ftsoProtocolId;

        // initialize fixed feeds for testing
        fixedFeedIds = new bytes21[](4);
        fixedSymbols = new string[](4);
        fixedTrustedDecimals = new int8[](4);
        for (uint256 i = 0; i < 4; i++) {
            fixedFeedIds[i] = bytes21(keccak256(abi.encode("fixedFeedId", i)));
            fixedSymbols[i] = string.concat("fixedSymbol", vm.toString(i));
        }
        fixedTrustedDecimals[0] = 8;
        fixedTrustedDecimals[1] = 6;
        fixedTrustedDecimals[2] = 4;
        fixedTrustedDecimals[3] = -12;

        // initialize feeds
        vm.prank(governance);
        ftsoV2PriceStore.updateSettings(fixedFeedIds, fixedSymbols, fixedTrustedDecimals, 1000);
    }

    function submitTrustedPrices(
        uint32[4] memory values
    ) public {
        uint8 numFeeds = 4;
        uint32 votingRoundId = _getPreviousVotingEpochId();
        uint256 startTimestamp = _getEndTimestamp(votingRoundId);
        vm.warp(startTimestamp + 1);

        IPricePublisher.TrustedProviderFeed[] memory trustedFeeds =
            new IPricePublisher.TrustedProviderFeed[](numFeeds);
        for (uint256 i = 0; i < numFeeds; i++) {
            trustedFeeds[i] = IPricePublisher.TrustedProviderFeed({
                id: fixedFeedIds[i],
                value: values[i],
                decimals: fixedTrustedDecimals[i]
            });
        }

        vm.prank(address(this));
        ftsoV2PriceStore.submitTrustedPrices(votingRoundId, trustedFeeds);
        vm.warp(block.timestamp + 10);
    }

    function publishPrices(
        uint32[4] memory values,
        int8[4] memory decimals
    ) public {
        uint8 numFeeds = 4;
        uint32 votingRoundId = ftsoV2PriceStore.lastPublishedVotingRoundId() + 1;

        // Advance time to after submission window
        uint256 endTimestamp = _getEndTimestamp(votingRoundId);
        vm.warp(endTimestamp + ftsoV2PriceStore.submitTrustedPricesWindowSeconds() + 1);

        // Prepare proofs
        IPricePublisher.FeedWithProof[] memory proofs = new IPricePublisher.FeedWithProof[](numFeeds);
        bytes32[] memory leaves = new bytes32[](numFeeds);

        for (uint256 i = 0; i < numFeeds; i++) {
            values[i] = uint32(bound(values[i], 0, type(uint32).max/2));
            decimals[i] = int8(bound(decimals[i], -18, 18)); // common decimal range
            IPricePublisher.Feed memory feed = IPricePublisher.Feed({
                id: fixedFeedIds[i],
                votingRoundId: votingRoundId,
                value: int32(uint32(values[i])),
                decimals: decimals[i],
                turnoutBIPS: 1000
            });
            proofs[i].body = feed;
            leaves[i] = keccak256(abi.encode(feed));
        }

        for (uint256 i = 0; i < numFeeds; i++) {
            proofs[i].proof = _getProof(i, leaves);
        }

        // Mock relay root
        bytes32 root = _calculateRoot(leaves);
        vm.mockCall(
            relayMock,
            abi.encodeWithSelector(IRelay.merkleRoots.selector, ftsoProtocolId, votingRoundId),
            abi.encode(root)
        );

        ftsoV2PriceStore.publishPrices(proofs);
    }

    // --- Helpers ---

    function _calculateRoot(bytes32[] memory _leaves) internal pure returns (bytes32) {
        require(_leaves.length == 4, "Only 4 leaves supported");
        bytes32 h12 = _hashPair(_leaves[0], _leaves[1]);
        bytes32 h34 = _hashPair(_leaves[2], _leaves[3]);
        return _hashPair(h12, h34);
    }

    function _getProof(uint256 _index, bytes32[] memory leaves) internal pure returns (bytes32[] memory proof) {
        require(leaves.length == 4, "Only 4 leaves supported");
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

    function _getEndTimestamp(uint256 _votingEpochId) internal view returns(uint256) {
        return firstVotingRoundStartTs + (_votingEpochId + 1) * votingEpochDurationSeconds;
    }
}