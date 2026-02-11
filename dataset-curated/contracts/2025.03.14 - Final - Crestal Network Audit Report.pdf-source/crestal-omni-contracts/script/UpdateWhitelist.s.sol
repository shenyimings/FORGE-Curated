// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BlueprintV4} from "../src/BlueprintV4.sol";

contract UpdateWhitelistScript is Script {
    address[] public whitelistUsers;

    function setUp() public {}

    function stringToAddress(string memory s) internal pure returns (address) {
        bytes memory b = bytes(s);
        require(b.length == 42, "Invalid address length");

        uint160 result = 0;
        for (uint256 i = 2; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            uint8 digit;
            if (c >= 48 && c <= 57) {
                digit = c - 48;
            } else if (c >= 65 && c <= 70) {
                digit = c - 55;
            } else if (c >= 97 && c <= 102) {
                digit = c - 87;
            } else {
                revert("Invalid hex character");
            }
            result = result * 16 + uint160(digit);
        }
        return address(result);
    }

    function run() public {
        vm.startBroadcast();

        address proxyAddr = vm.envAddress("PROXY_ADDRESS");
        string memory whitelistFile = vm.envString("WHITELIST_FILE");
        while (true) {
            string memory line = vm.readLine(whitelistFile);
            if (bytes(line).length == 0) {
                break;
            }
            address addr = stringToAddress(line);
            whitelistUsers.push(addr);
        }

        BlueprintV4 proxy = BlueprintV4(proxyAddr);
        proxy.setWhitelistAddresses(whitelistUsers);

        vm.stopBroadcast();
    }
}
