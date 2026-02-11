// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import {LSDIndexAdapter} from "../base/LSDIndexAdapter.sol";
import {ICoinbaseCBETH} from "../interfaces/ICoinbaseCBETH.sol";

/**
 * @title Coinbase cbETH Adapter
 * @notice Adapter for Coinbase's cbETH
 */
contract CoinbaseLSDIndexAdapter is LSDIndexAdapter {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _token, address _indexPool) public initializer {
        __LiquidSDAdapter_init(_token, _indexPool);
    }

    /**
     * @notice returns the exchange rate between the underlying asset and this adapter's token
     * @return exchange rate
     */
    function getExchangeRate() public view override returns (uint256) {
        return ICoinbaseCBETH(address(token)).exchangeRate();
    }
}
