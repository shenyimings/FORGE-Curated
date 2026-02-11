// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IOracle } from "../../contracts/interfaces/IOracle.sol";

import { TestDeployer } from "../deploy/TestDeployer.sol";

contract PriceOracleGetPriceTest is TestDeployer {
    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);
    }

    function test_price_oracle_get_price() public view {
        (uint256 usdtPrice,) = IOracle(env.infra.oracle).getPrice(address(usdt));
        assertEq(usdtPrice, 1e8, "USDT price should be $1");
    }
}
