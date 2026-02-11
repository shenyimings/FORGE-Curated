// SPDX-License-Identifier: BUSL-1.1
// Copyright 2023 LayerZero Labs Ltd.
// You may obtain a copy of the License at
// https://github.com/LayerZero-Labs/license/blob/main/LICENSE-LZBL-1.1

pragma solidity ^0.7.6;

library RateLimiter {
    struct Info {
        // capacity of the token bucket. This is the maximum number of tokens that the bucket can hold at any given time
        uint64 capacity;
        // current number of tokens in the bucket
        uint64 tokens;
        // number of tokens refilled per second
        uint64 rate;
        // timestamp of last refill
        uint64 lastRefillTime;
    }

    function setCapacity(Info storage _self, uint64 _capacity) internal {
        _self.capacity = _capacity;
        _self.tokens = _capacity;
        _self.lastRefillTime = uint64(block.timestamp);
    }

    function setRate(Info storage _self, uint64 _rate) internal {
        refill(_self, 0);
        _self.rate = _rate;
    }

    function tryConsume(Info storage _self, uint64 _amount) internal returns (uint64) {
        refill(_self, 0);

        uint64 tokens = _self.tokens;
        require(tokens >= _amount, "RelayerV2: out of counters - try again later!");

        uint64 newTokens = tokens - _amount;
        _self.tokens = newTokens;
        return newTokens;
    }

    function refill(Info storage _self, uint64 _extraTokens) internal {
        uint newTokens = _extraTokens;

        uint64 currentTime = uint64(block.timestamp);
        if (currentTime > _self.lastRefillTime) {
            uint timeElapsedInSeconds = currentTime - _self.lastRefillTime;
            newTokens += timeElapsedInSeconds * _self.rate;
        }

        if (newTokens > 0) {
            newTokens += _self.tokens;
            _self.tokens = newTokens > _self.capacity ? _self.capacity : uint64(newTokens);
        }

        _self.lastRefillTime = currentTime;
    }
}
