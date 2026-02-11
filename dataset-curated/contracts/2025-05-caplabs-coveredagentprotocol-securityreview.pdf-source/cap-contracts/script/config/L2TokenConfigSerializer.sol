// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { TokenSerializer } from "./TokenSerializer.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

contract L2TokenConfigSerializer is TokenSerializer {
    using stdJson for string;

    function _l2TokensFilePath() private view returns (string memory) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        return string.concat(vm.projectRoot(), "/config/cap-l2tokens-", Strings.toString(block.chainid), ".json");
    }

    function _saveL2TokenAddresses(address token, address stakedToken) internal {
        string memory tokenJson = "l2tokens";
        tokenJson.serialize("bridgedCapToken", _serializeToken(token));
        tokenJson = tokenJson.serialize("bridgedStakedCapToken", _serializeToken(stakedToken));

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        string memory previousJson = vm.readFile(_l2TokensFilePath());
        string memory mergedJson = "merged";
        mergedJson.serialize(previousJson);
        mergedJson = mergedJson.serialize(IERC20Metadata(token).symbol(), tokenJson);
        vm.writeFile(_l2TokensFilePath(), mergedJson);
    }

    function _readL2TokenAddresses(string memory symbol) internal view returns (address token, address stakedToken) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        string memory json = vm.readFile(_l2TokensFilePath());
        string memory tokenJson = json.readString(symbol);

        token = tokenJson.readAddress("token.address");
        stakedToken = tokenJson.readAddress("stakedToken.address");
    }
}
