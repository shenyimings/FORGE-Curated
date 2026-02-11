// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.19;

import {IERC20} from "../../../../../external-interfaces/IERC20.sol";
import {IStaderOracle} from "../../../../../external-interfaces/IStaderOracle.sol";
import {IDerivativePriceFeed} from "../IDerivativePriceFeed.sol";

/// @title StaderSDPriceFeed Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Price feed for Stader SD Token
/// @dev This price feed utilizes the Stader Oracle to determine pricing.
/// Note that the Stader Oracle provides a 24-hour average price, not a real-time market price.
/// Vault owners should be aware of the potential risks associated with discrepancies between the price feed and the current market price of the asset.
contract StaderSDPriceFeed is IDerivativePriceFeed {
    IStaderOracle private immutable STADER_ORACLE;
    address private immutable SD_TOKEN_ADDRESS;
    uint256 immutable SD_TOKEN_UNIT;
    address private immutable WETH_ADDRESS;

    constructor(address _sdTokenAddress, address _staderOracleAddress, address _wethAddress) {
        SD_TOKEN_ADDRESS = _sdTokenAddress;
        SD_TOKEN_UNIT = 10 ** uint256(IERC20(_sdTokenAddress).decimals());
        STADER_ORACLE = IStaderOracle(_staderOracleAddress);
        WETH_ADDRESS = _wethAddress;
    }

    /// @notice Converts a given amount of a derivative to its underlying asset values
    /// @param _derivativeAmount The amount of the derivative to convert
    /// @return underlyings_ The underlying assets for the derivative
    /// @return underlyingAmounts_ The amount of each underlying asset for the equivalent derivative amount
    function calcUnderlyingValues(address, uint256 _derivativeAmount)
        external
        view
        override
        returns (address[] memory underlyings_, uint256[] memory underlyingAmounts_)
    {
        underlyings_ = new address[](1);
        underlyings_[0] = WETH_ADDRESS;

        underlyingAmounts_ = new uint256[](1);
        underlyingAmounts_[0] = STADER_ORACLE.getSDPriceInETH() * _derivativeAmount / SD_TOKEN_UNIT;

        return (underlyings_, underlyingAmounts_);
    }

    /// @notice Checks if an asset is supported by the price feed
    /// @param _asset The asset to check
    /// @return isSupported_ True if the asset is supported
    function isSupportedAsset(address _asset) public view override returns (bool isSupported_) {
        return _asset == SD_TOKEN_ADDRESS;
    }
}
