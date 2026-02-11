// SPDX-License-Identifier: MIT
// solhint-disable gas-custom-errors

pragma solidity ^0.8.27;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {FtsoV2PriceStore} from "../implementation/FtsoV2PriceStore.sol";


contract FtsoV2PriceStoreMock is FtsoV2PriceStore {
    using SafeCast for uint256;

    function addFeed(bytes21 _feedId, string memory _symbol) external {
        symbolToFeedId[_symbol] = _feedId;
        feedIdToSymbol[_feedId] = _symbol;
    }

    function setDecimals(string memory _symbol, int8 _decimals) external {
        PriceStore storage feed = _getFeed(_symbol);
        feed.decimals = _decimals;
        feed.trustedDecimals = _decimals;
    }

    function setCurrentPrice(string memory _symbol, uint256 _price, uint256 _ageSeconds) external {
        PriceStore storage feed = _getFeed(_symbol);
        feed.value = _price.toUint32();
        feed.votingRoundId = _timestampToVotingRound(block.timestamp - _ageSeconds);
        feed.decimals = feed.trustedDecimals;
    }

    function setCurrentPriceFromTrustedProviders(string memory _symbol, uint256 _price, uint256 _ageSeconds) external {
        PriceStore storage feed = _getFeed(_symbol);
        feed.trustedValue = _price.toUint32();
        feed.trustedVotingRoundId = _timestampToVotingRound(block.timestamp - _ageSeconds);
    }

    function finalizePrices() external {
        emit PricesPublished(0);
    }

    function _getFeed(string memory _symbol) private view returns (PriceStore storage) {
        bytes21 feedId = symbolToFeedId[_symbol];
        require(feedId != bytes21(0), SymbolNotSupported());
        return latestPrices[feedId];
    }

    function _timestampToVotingRound(uint256 _timestamp) private view returns (uint32) {
        uint256 roundId = (_timestamp - firstVotingRoundStartTs) / votingEpochDurationSeconds;
        return roundId.toUint32();
    }
}
