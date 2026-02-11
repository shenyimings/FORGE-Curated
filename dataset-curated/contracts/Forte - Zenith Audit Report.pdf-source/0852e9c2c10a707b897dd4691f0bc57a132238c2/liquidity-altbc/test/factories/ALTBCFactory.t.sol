/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GenericERC20} from "lib/liquidity-base/src/example/ERC20/GenericERC20.sol";
import {FactoryCommon} from "lib/liquidity-base/test/factories/FactoryCommon.sol";
import "forge-std/console2.sol";
import {ALTBCFactory} from "src/factory/ALTBCFactory.sol";
import {ALTBCFactoryDeployed} from "src/common/IALTBCEvents.sol";
import {ALTBCInput} from "src/amm/ALTBC.sol";
import {ALTBCTestSetup, PoolBase} from "test/util/ALTBCTestSetup.sol";
import {ALTBCPool, IERC20} from "src/amm/ALTBCPool.sol";

/**
 * @title Test ALTBCFactory contract
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55
 */
contract ALTBCFactoryTest is FactoryCommon, ALTBCTestSetup {
    function setUp() public {
        super._setUp();
    }

    function testLiquidity_PoolFactory_deploymentEvent() public startAsAdmin {
        vm.expectEmit(true, true, true, true);
        emit ALTBCFactoryDeployed("v0.2.0");
        new ALTBCFactory(type(ALTBCPool).creationCode);
    }

    function testLiquidity_PoolFactory_deployALTBCPool_NotAllowedDeployer() public endWithStopPrank {
        _deployAndSetupFactory();
        vm.startPrank(alice);
        IERC20(address(xToken)).approve(address(factory), X_TOKEN_MAX_SUPPLY);
        vm.expectRevert(abi.encodeWithSignature("NotAnAllowedDeployer()"));
        pool = PoolBase(
            ALTBCFactory(address(factory)).createPool(
                address(xToken),
                address(yToken),
                30,
                ALTBCInput(10_000, 0, 1e18, 1e18, 1e18),
                X_TOKEN_MAX_SUPPLY,
                "Name",
                "SYMBOL"
            )
        );
    }

    function testLiquidity_PoolFactory_deployALTBCPool_NotAllowedCollateralToken() public endWithStopPrank {
        _deployAndSetupFactory();
        _setupAllowLists();
        vm.startPrank(admin);
        IERC20(address(xToken)).approve(address(factory), X_TOKEN_MAX_SUPPLY);
        GenericERC20 invalidCollateralToken = new GenericERC20("Invalid Collateral", "INVALID");
        vm.expectRevert(abi.encodeWithSignature("YTokenNotAllowed()"));
        pool = PoolBase(
            ALTBCFactory(address(factory)).createPool(
                address(xToken),
                address(invalidCollateralToken),
                30,
                ALTBCInput(10_000, 0, 1e18, 1e18, 1e18),
                X_TOKEN_MAX_SUPPLY,
                "Name",
                "SYMBOL"
            )
        );
    }
}
