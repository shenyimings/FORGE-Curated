// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { stdJson } from "forge-std/StdJson.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

struct ZapAddressbook {
    address zapRouter;
    address tokenManager;
}

contract ZapUtils {
    using stdJson for string;

    string public constant ZAP_CONFIG_PATH_FROM_PROJECT_ROOT = "config/zap.json";

    function _getZapAddressbook() internal view returns (ZapAddressbook memory ab) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        string memory configJson = vm.readFile(ZAP_CONFIG_PATH_FROM_PROJECT_ROOT);
        string memory selectorPrefix = string.concat("$['", vm.toString(block.chainid), "']");

        console.log("block.chainid", block.chainid);

        // ethereum sepolia
        ab.zapRouter = configJson.readAddress(string.concat(selectorPrefix, ".zapRouter"));
        ab.tokenManager = configJson.readAddress(string.concat(selectorPrefix, ".tokenManager"));
    }
}
