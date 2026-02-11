// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {GenericERC20} from "lib/liquidity-base/src/example/ERC20/GenericERC20.sol";
import {FactoryCommon} from "lib/liquidity-base/test/factories/FactoryCommon.sol";
import "forge-std/console2.sol";
import {ALTBCFactory} from "src/factory/ALTBCFactory.sol";
import {ALTBCFactoryDeployed} from "src/common/IALTBCEvents.sol";
import {ALTBCInput} from "src/amm/ALTBC.sol";
import {ALTBCTestSetup, PoolBase} from "test/util/ALTBCTestSetup.sol";
import {ALTBCPool, IERC20} from "src/amm/ALTBCPool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {LPToken} from "lib/liquidity-base/src/common/LPToken.sol";

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
        emit ALTBCFactoryDeployed("v1.0.0");
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
                ALTBCInput(10_000, 1e18, 1e18, 1e18),
                X_TOKEN_MAX_SUPPLY,
                0
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
                ALTBCInput(10_000, 1e18, 1e18, 1e18),
                X_TOKEN_MAX_SUPPLY,
                0
            )
        );
    }

    function testLiquidity_PoolFactory_setLPTokenAddress() public {
        _deployAndSetupFactory();
        address oldLPToken = factory.lpTokenAddress();
        address newLPToken = address(new LPToken("New LP Token", "NEW"));
        // expect revert on non-owner call
        vm.startPrank(address(1337));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1337)));
        factory.setLPTokenAddress(address(newLPToken));
        assertEq(factory.lpTokenAddress(), oldLPToken);
        vm.startPrank(admin);

        factory.setLPTokenAddress(address(newLPToken));
        assertEq(factory.lpTokenAddress(), address(newLPToken));
    }

    function testLiquidity_PoolFactory_confirmPoolAddedToAllowList() public startAsAdmin {
        _deployLPToken();
        vm.stopPrank();
        _deployAndSetupFactory();
        _setupAllowLists();
        vm.startPrank(admin);
        IERC20(address(xToken)).approve(address(factory), X_TOKEN_MAX_SUPPLY);
        LPToken newLpToken = new LPToken("New LP Token", "NEW");
        factory.setLPTokenAddress(address(newLpToken));
        vm.expectRevert(abi.encodeWithSignature("NotFactory()"));
        pool = PoolBase(
            ALTBCFactory(address(factory)).createPool(
                address(xToken),
                address(yToken),
                30,
                ALTBCInput(10_000, 1e18, 1e18, 1e18),
                X_TOKEN_MAX_SUPPLY,
                0
            )
        );
        newLpToken.proposeFactoryAddress(address(factory));
        vm.startPrank(address(factory));
        newLpToken.confirmFactoryAddress();
        vm.startPrank(admin);
        pool = PoolBase(
            ALTBCFactory(address(factory)).createPool(
                address(xToken),
                address(yToken),
                30,
                ALTBCInput(10_000, 1e18, 1e18, 1e18),
                X_TOKEN_MAX_SUPPLY,
                0
            )
        );
        vm.expectRevert(abi.encodeWithSignature("NotFactory()"));
        newLpToken.addPoolToAllowList(address(pool));
        vm.startPrank(address(factory));
        vm.expectRevert(abi.encodeWithSignature("PoolAlreadyAllowed()"));
        newLpToken.addPoolToAllowList(address(pool));
        assertTrue(newLpToken.isPoolAllowed(address(pool)));
    }

    function testLiquidity_PoolFactory_acceptLPTokenRole() public {
        vm.startPrank(admin);
        LPToken newLpToken = new LPToken("New LP Token", "NEW");
        vm.stopPrank();
        _deployAndSetupFactory();

        // Make sure it reverts on non-owner call
        vm.startPrank(address(1337));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1337)));
        factory.acceptLPTokenRole();

        vm.startPrank(admin);
        factory.setLPTokenAddress(address(newLpToken));
        newLpToken.proposeFactoryAddress(address(factory));
        factory.acceptLPTokenRole();
        assertEq(newLpToken.factoryAddress(), address(factory));
    }
}
