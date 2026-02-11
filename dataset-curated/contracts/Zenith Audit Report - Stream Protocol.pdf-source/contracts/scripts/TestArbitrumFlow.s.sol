// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {TestToken} from "../src/TestToken.sol";
import {StreamVault} from "../src/StreamVault.sol";
import {StableWrapper} from "../src/StableWrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestArbitrumFlowScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Contracts
        TestToken token = TestToken(0xbd9f45ced9209E0c8d45eF0621fB5b72335546C6);
        StreamVault vault = StreamVault(0x58107a168E54802A7D35ebDBE6e9f82447d5Fb8d);
        StableWrapper wrapper = StableWrapper(0xc380Fc06B25242DbeD574132a0C0e7ED77e8eD28);

        // Log initial balances
        console2.log("Initial token balance:", token.balanceOf(deployer));
        console2.log("Initial vault shares:", vault.balanceOf(deployer));

        vm.startBroadcast(deployerPrivateKey);

        // 2. Approve wapper
        token.approve(address(wrapper), 2000e6);

        // 3. Deposit and stake
        vault.depositAndStake(200e6, deployer);  // Let's start with 200 USDC
        console2.log("After deposit token balance:", token.balanceOf(deployer));
        console2.log("After deposit vault shares:", vault.balanceOf(deployer));

        // 4. Roll to next round with 0 yield
        vault.rollToNextRound(0, true);

        // 5. Max redeem
        vault.maxRedeem();
        console2.log("Final token balance:", token.balanceOf(deployer));
        console2.log("Final vault shares:", vault.balanceOf(deployer));

        vm.stopBroadcast();
    }
} 