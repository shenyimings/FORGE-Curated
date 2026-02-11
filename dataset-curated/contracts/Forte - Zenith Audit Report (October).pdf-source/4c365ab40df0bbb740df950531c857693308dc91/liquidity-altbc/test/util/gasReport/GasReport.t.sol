// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {ALTBCFactory} from "src/factory/ALTBCFactory.sol";
import {ALTBCPool} from "src/amm/ALTBCPool.sol";
import {ALTBCInput} from "src/amm/ALTBC.sol";
import {TestCommonSetup} from "liquidity-base/test/util/TestCommonSetup.sol";
import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";
import {GasHelpers} from "lib/liquidity-base/test/util/gasReport/GasHelpers.sol";
import {packedFloat} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {LPToken} from "lib/liquidity-base/src/common/LPToken.sol";

contract ALTBCGasReport is TestCommonSetup, ALTBCTestSetup, GasHelpers {
    LPToken _lpToken;
    ALTBCPool _pool;
    ALTBCFactory _factory;

    function setUp() public {
        path = "test/util/gasReport/GasReport.json";

        _setupPool(false);

        (packedFloat b, packedFloat c, packedFloat C, , packedFloat maxX, packedFloat V, ) = ALTBCPool(address(pool)).tbc();
        (altbc.xMax, altbc.b, altbc.c, altbc.C, altbc.V) = (maxX, b, c, C, V);

        vm.startPrank(admin);

        // Swap to get some xTokens into alice and admin account for subsequent operations
        (uint256 amountOut, , ) = pool.simSwap(address(yToken), 2e18);
        pool.swap(address(yToken), 2e18, amountOut, admin, getValidExpiration());
        _approvePool(pool, false);

        (amountOut, , ) = pool.simSwap(address(yToken), 2e18);
        vm.startPrank(alice);
        pool.swap(address(yToken), 2e18, amountOut, alice, getValidExpiration());
    }

    function testApproveAndDepositLiquidityGasUsed() public {
        _resetGasUsed();

        vm.startPrank(admin);
        startMeasuringGas("Approval and liquidity position update");
        xToken.approve(address(pool), xToken.balanceOf(admin));
        yToken.approve(address(pool), yToken.balanceOf(admin));

        // A, B and W here are not set as a variable to more accurately represent an external call
        ALTBCPool(address(pool)).depositLiquidity(2, 1e18, 1e18, 0, 0, getValidExpiration());
        gasUsed = stopMeasuringGas();
        _writeJson(".Deposit.approvalAndDeposit");
        _resetGasUsed();
    }

    function testUpdateLiquidityPositionGasUsed() public {
        _resetGasUsed();

        vm.startPrank(admin);
        startMeasuringGas("Liquidity position update");
        // A, B, and W here are not set as a variable to more accurately represent an external call
        ALTBCPool(address(pool)).depositLiquidity(2, 1e18, 1e18, 0, 0, getValidExpiration());
        gasUsed = stopMeasuringGas();
        _writeJson(".Deposit.updateLiquidityPosition");
        _resetGasUsed();
    }

    function testApprovalAndNewLiquidityPositionGasUsed() public {
        _resetGasUsed();

        vm.startPrank(alice);

        startMeasuringGas("Approval and new liquidity position");
        xToken.approve(address(pool), xToken.balanceOf(alice));
        yToken.approve(address(pool), yToken.balanceOf(alice));
        // A, B, and W here are not set as a variable to more accurately represent an external call
        ALTBCPool(address(pool)).depositLiquidity(0, 1e18, 1e18, 0, 0, getValidExpiration());
        gasUsed = stopMeasuringGas();
        _writeJson(".Deposit.approvalAndNewLiquidityPosition");
        _resetGasUsed();
    }

    function testNewLiquidityPositionGasUsed() public {
        _resetGasUsed();

        vm.startPrank(alice);

        startMeasuringGas("New liquidity position - both token types deposited");
        xToken.approve(address(pool), xToken.balanceOf(alice));
        yToken.approve(address(pool), yToken.balanceOf(alice));
        // A, B, and W here are not set as a variable to more accurately represent an external call
        ALTBCPool(address(pool)).depositLiquidity(0, 1e18, 1e18, 0, 0, getValidExpiration());
        gasUsed = stopMeasuringGas();
        _writeJson(".Deposit.newLiquidityPosition");
        _resetGasUsed();
    }

    function testNewLiquidityPositionOnlyOneTokenGasUsed() public {
        _resetGasUsed();

        vm.startPrank(alice);

        startMeasuringGas("New liquidity position - one token type deposited");
        // A, B, and W here are not set as a variable to more accurately represent an external call
        // This is sending only the xToken value, the yToken adjusted value is 0.
        ALTBCPool(address(pool)).depositLiquidity(0, 1, 1, 0, 0, getValidExpiration());
        gasUsed = stopMeasuringGas();
        _writeJson(".Deposit.newLiquidityPositionOnlyOneToken");
        _resetGasUsed();
    }

    function testSwapGasUsed() public {
        _resetGasUsed();

        vm.startPrank(alice);
        (uint256 amountOut, , ) = ALTBCPool(address(pool)).simSwap(address(yToken), 1e18);
        startMeasuringGas("Swap");
        ALTBCPool(address(pool)).swap(address(yToken), 1e18, amountOut, msg.sender, getValidExpiration());
        gasUsed = stopMeasuringGas();
        _writeJson(".Swap.swapToken");
        _resetGasUsed();
    }

    function testDeployFactoryGasUsed() public {
        _resetGasUsed();

        startMeasuringGas("Factory Deployment");
        _factory = new ALTBCFactory(type(ALTBCPool).creationCode);
        gasUsed = stopMeasuringGas();
        _writeJson(".Deployment.factory");
        _resetGasUsed();
    }

    function testDeployPoolGasUsed() public {
        _resetGasUsed();

        startMeasuringGas("Pool Deployment");
        vm.startPrank(admin);
        altbcFactory.createPool(address(xToken), address(yToken), 30, altbcInput, X_TOKEN_MAX_SUPPLY, 1e17);
        gasUsed = stopMeasuringGas();
        _writeJson(".Deployment.pool");
        _resetGasUsed();
    }
}
