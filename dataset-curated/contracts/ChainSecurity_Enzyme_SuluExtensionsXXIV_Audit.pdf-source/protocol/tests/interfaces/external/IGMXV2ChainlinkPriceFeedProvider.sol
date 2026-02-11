// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

/// @title IGMXV2ChainlinkPriceFeedProvider Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IGMXV2ChainlinkPriceFeedProvider {
    struct ValidatedPrice {
        address token;
        uint256 min;
        uint256 max;
        uint256 timestamp;
        address provider;
    }

    function getOraclePrice(address _token, bytes memory _data)
        external
        view
        returns (ValidatedPrice memory validatedPrice_);
}
