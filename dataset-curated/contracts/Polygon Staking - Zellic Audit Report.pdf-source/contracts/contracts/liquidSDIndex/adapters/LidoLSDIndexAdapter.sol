// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../base/LSDIndexAdapter.sol";

/**
 * @title Lido stETH Adapter
 * @notice Adapter for Lido's stETH
 */
contract LidoLSDIndexAdapter is LSDIndexAdapter {
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
        return 1 ether;
    }
}
