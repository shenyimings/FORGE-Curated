// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";

contract MockMorphoOracle is IOracle {
    uint256 public mockPrice;

    constructor(uint256 initPrice) {
        mockPrice = initPrice;
    }

    /// Corresponds to the price of 10**(collateral token decimals) assets of collateral token quoted in
    /// 10**(loan token decimals) assets of loan token with `36 + loan token decimals - collateral token decimals`
    // decimals of precision.
    /// e.g. Price is 1861323720576765394076355418, collateral token is WETH, debt token is USDC:
    ///     1 WETH in USDC = (1e18 * 1861323720576765394076355418 / 1e36) / 1e6 ~= 1861 USDC
    function price() external view returns (uint256) {
        return mockPrice;
    }

    function setPrice(uint256 newPrice) external {
        mockPrice = newPrice;
    }
}
