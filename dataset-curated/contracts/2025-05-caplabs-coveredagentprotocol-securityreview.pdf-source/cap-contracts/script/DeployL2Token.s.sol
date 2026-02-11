// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { VaultConfig } from "../../contracts/deploy/interfaces/DeployConfigs.sol";
import { LzAddressbook, LzUtils } from "../contracts/deploy/utils/LzUtils.sol";
import { WalletUtils } from "../contracts/deploy/utils/WalletUtils.sol";
import { L2Token } from "../contracts/token/L2Token.sol";
import { L2TokenConfigSerializer } from "./config/L2TokenConfigSerializer.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

/**
 * Deploy an L2 token contract
 */
contract DeployL2Token is Script, WalletUtils, LzUtils, L2TokenConfigSerializer {
    function run() public {
        LzAddressbook memory config = _getLzAddressbook(block.chainid);

        string memory cTokenSymbol = "cETH";
        string memory cTokenName = "Cap ETH";
        string memory stcTokenSymbol = "stcETH";
        string memory stcTokenName = "Staked Cap ETH";

        address owner = getWalletAddress();
        console.log("owner", owner);

        vm.startBroadcast();

        L2Token l2cToken = new L2Token(cTokenName, cTokenSymbol, address(config.endpointV2), owner);
        L2Token l2stcToken = new L2Token(stcTokenName, stcTokenSymbol, address(config.endpointV2), owner);

        vm.stopBroadcast();

        // Save the L2 token addresses
        _saveL2TokenAddresses(address(l2cToken), address(l2stcToken));
    }
}
