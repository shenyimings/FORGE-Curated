// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

contract TokenSerializer {
    using stdJson for string;

    function _serializeToken(address token) internal returns (string memory) {
        string memory symbol = IERC20Metadata(token).symbol();
        string memory name = IERC20Metadata(token).name();
        uint256 decimals = IERC20Metadata(token).decimals();
        string memory json = string.concat("token_", symbol);
        json.serialize("symbol", symbol);
        json.serialize("name", name);
        json.serialize("decimals", decimals);
        json = json.serialize("address", token);
        console.log(json);
        return json;
    }
}
