// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { MockERC20 } from "../../test/mocks/MockERC20.sol";
import { CustomConfig } from "./config/CustomConfig.sol";
import { console } from "forge-std/console.sol";

contract DeployMockTokens is CustomConfig, Script {
    ERC20Args[] public erc20Args;
    mapping(string => address) public tokens;

    function run(address account) external returns (DeployedUnderlyingTokens memory) {
        console.log("Deploying Mock Tokens with account:", account);

        ERC20Args[] memory erc20Configs = getERC20s();

        vm.startBroadcast(account);

        for (uint256 i = 0; i < erc20Configs.length; i++) {
            address token = address(
                new MockERC20(
                    account, 
                    erc20Configs[i].name, 
                    erc20Configs[i].symbol, 
                    erc20Configs[i].initialSupply, 
                    erc20Configs[i].decimals
                )
            );
            tokens[erc20Configs[i].symbol] = token;
        }

        vm.stopBroadcast();

        return DeployedUnderlyingTokens({
            uxd: tokens["UXD"],
            weth: tokens["WETH"],
            wbtc: tokens["WBTC"],
            usdt: tokens["USDT"],
            usdc: tokens["USDC"],
            mockUnderlying: tokens["MOCK"],
            lac: tokens["LAC"]
        });
    }
}
