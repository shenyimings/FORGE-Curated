// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {LibString} from "@solady/utils/LibString.sol";

contract AnvilHelper is Script {
    using LibString for address;
    using LibString for uint256;

    function _setBalance(address account, uint256 balance) internal {
        vm.rpc("anvil_setBalance", string.concat("[\"", account.toHexString(), "\", \"", balance.toHexString(), "\"]"));
    }

    function _autoImpersonate(bool autoImpersonate) internal {
        vm.rpc("anvil_autoImpersonateAccount", string.concat("[", vm.toString(autoImpersonate), "]"));
    }

    function _impersonate(address account) internal {
        vm.rpc("anvil_impersonateAccount", string.concat("[\"", account.toHexString(), "\"]"));
    }

    function _stopImpersonate(address account) internal {
        vm.rpc("anvil_stopImpersonatingAccount", string.concat("[\"", account.toHexString(), "\"]"));
    }
}
