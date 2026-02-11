// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {IPool} from "src/amm/base/IPool.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Script} from "forge-std/Script.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {console} from "forge-std/console.sol";

contract TestSwap is Script, StdAssertions {
    uint validExpiration = 4102473600; // January 1, 2100
    function run() external {
        IPool pool = IPool(vm.envAddress("POOL_CONTRACT"));
        address tokenX = vm.envAddress("XTOKEN_ADDRESS");
        address tokenY = vm.envAddress("YTOKEN_ADDRESS");
        uint256 amountY = 10000000;
        vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));
        console2.log("xToken", tokenX);
        console2.log("yToken", tokenY);
        console2.log("deployment owner", vm.envUint("DEPLOYMENT_OWNER_KEY"));
        console2.log("pool", address(pool));
        console2.log("amountY", amountY);
        console2.log("poolXtoken", pool.xToken());
        IERC20(tokenY).approve(address(pool), amountY);
        (uint256 expectedAmountX, , ) = pool.simSwap(tokenY, amountY);
        pool.swap(tokenY, amountY, expectedAmountX, address(vm.envAddress("DEPLOYMENT_OWNER")), validExpiration);
        assertGe(IERC20(tokenX).balanceOf(address(vm.envAddress("DEPLOYMENT_OWNER"))), expectedAmountX);
        (uint256 expectedAmountY, , ) = pool.simSwap(tokenX, expectedAmountX);
        IERC20(tokenX).approve(address(pool), expectedAmountX);
        pool.swap(tokenX, expectedAmountX, expectedAmountY, address(vm.envAddress("DEPLOYMENT_OWNER")), validExpiration);
        assertGe(IERC20(tokenY).balanceOf(address(vm.envAddress("DEPLOYMENT_OWNER"))), expectedAmountY);
        vm.stopBroadcast();
    }
}
