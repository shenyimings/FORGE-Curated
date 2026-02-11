// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import {LSDIndexAdapter} from "../base/LSDIndexAdapter.sol";
import {ISFRXETH} from "../interfaces/ISFRXETH.sol";

/**
 * @title Frax sfrxETH Adapter
 * @notice Adapter for Frax's sfrxETH
 */
contract FraxLSDIndexAdapter is LSDIndexAdapter {
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
        return ISFRXETH(address(token)).pricePerShare();
    }
}
