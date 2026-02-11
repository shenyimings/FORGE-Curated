// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../base/LSDIndexAdapter.sol";

/**
 * @title Liquid Staking Derivative Index Adapter Mock
 * @notice Mocks contract for testing
 */
contract LSDIndexAdapterMock is LSDIndexAdapter {
    uint256 public exchangeRate;

    function initialize(
        address _token,
        address _indexPool,
        uint256 _exchangeRate
    ) public initializer {
        __LiquidSDAdapter_init(_token, _indexPool);
        exchangeRate = _exchangeRate;
    }

    /**
     * @notice returns the exchange rate between this adapter's token and the underlying asset
     * @return exchange rate
     */
    function getExchangeRate() public view override returns (uint256) {
        return exchangeRate;
    }

    function setExchangeRate(uint256 _exchangeRate) external {
        exchangeRate = _exchangeRate;
    }
}
