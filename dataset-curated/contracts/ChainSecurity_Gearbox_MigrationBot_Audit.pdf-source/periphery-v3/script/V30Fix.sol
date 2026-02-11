// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {ICreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditConfiguratorV3.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {IContractsRegister} from "@gearbox-protocol/permissionless/contracts/interfaces/IContractsRegister.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {LibString} from "@solady/utils/LibString.sol";

import {AnvilHelper} from "./AnvilHelper.sol";

interface ICreditConfiguratorLegacy {
    function makeTokenQuoted(address token) external;
}

contract V30Fix is Script, AnvilHelper {
    using LibString for address;
    using LibString for uint256;

    address constant ACL = 0x523dA3a8961E4dD4f6206DBf7E6c749f51796bb3;
    address constant CONTRACTS_REGISTER = 0xA50d4E7D8946a7c90652339CDBd262c375d54D99;

    function run() public {
        // Get all credit managers from contracts register
        address[] memory creditManagers = IContractsRegister(CONTRACTS_REGISTER).getCreditManagers();

        address aclOwner = Ownable(ACL).owner();
        _setBalance(aclOwner, 10 ether);

        _autoImpersonate(true);
        _impersonate(aclOwner);
        vm.startBroadcast(aclOwner);

        uint256 len = creditManagers.length;

        for (uint256 i = 0; i < len; i++) {
            address cm = creditManagers[i];
            uint256 version = IVersion(cm).version();
            if (version < 300 || version >= 3_10) continue;

            ICreditManagerV3 creditManager = ICreditManagerV3(cm);
            address configurator = creditManager.creditConfigurator();

            uint256 tokensCount = creditManager.collateralTokensCount();
            uint256 quotedTokensMask = creditManager.quotedTokensMask();

            for (uint256 j = 1; j < tokensCount; j++) {
                uint256 tokenMask = 1 << j;
                if (quotedTokensMask & tokenMask != 0) continue;
                address token = creditManager.getTokenByMask(tokenMask);

                console.log("Making token quoted:", token);

                ICreditConfiguratorLegacy(configurator).makeTokenQuoted(token);
            }
        }

        vm.stopBroadcast();
        _stopImpersonate(aclOwner);
        // _autoImpersonate(false);
    }
}
