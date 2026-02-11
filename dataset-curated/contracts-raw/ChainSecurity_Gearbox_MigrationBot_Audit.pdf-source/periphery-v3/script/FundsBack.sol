// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";

import {LibString} from "@solady/utils/LibString.sol";

import {IAddressProvider} from "@gearbox-protocol/permissionless/contracts/interfaces/IAddressProvider.sol";
import {IBytecodeRepository} from "@gearbox-protocol/permissionless/contracts/interfaces/IBytecodeRepository.sol";
import {IMarketConfigurator} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";
import {IMarketConfiguratorFactory} from
    "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfiguratorFactory.sol";
import {CrossChainCall} from "@gearbox-protocol/permissionless/contracts/interfaces/Types.sol";
import {
    AP_MARKET_CONFIGURATOR_FACTORY,
    NO_VERSION_CONTROL
} from "@gearbox-protocol/permissionless/contracts/libraries/ContractLiterals.sol";
import {
    GlobalSetup,
    UploadableContract,
    DeploySystemContractCall
} from "@gearbox-protocol/permissionless/contracts/test/helpers/GlobalSetup.sol";

import {CreditAccountCompressor} from "../contracts/compressors/CreditAccountCompressor.sol";
import {CreditSuiteCompressor} from "../contracts/compressors/CreditSuiteCompressor.sol";
import {GaugeCompressor} from "../contracts/compressors/GaugeCompressor.sol";
import {MarketCompressor} from "../contracts/compressors/MarketCompressor.sol";
import {PeripheryCompressor} from "../contracts/compressors/PeripheryCompressor.sol";
import {PriceFeedCompressor} from "../contracts/compressors/PriceFeedCompressor.sol";
import {RewardsCompressor} from "../contracts/compressors/RewardsCompressor.sol";
import {TokenCompressor} from "../contracts/compressors/TokenCompressor.sol";

import {
    AP_CREDIT_ACCOUNT_COMPRESSOR,
    AP_CREDIT_SUITE_COMPRESSOR,
    AP_GAUGE_COMPRESSOR,
    AP_MARKET_COMPRESSOR,
    AP_PERIPHERY_COMPRESSOR,
    AP_PRICE_FEED_COMPRESSOR,
    AP_REWARDS_COMPRESSOR,
    AP_TOKEN_COMPRESSOR
} from "../contracts/libraries/Literals.sol";

import {AnvilHelper} from "./AnvilHelper.sol";
import {LegacyHelper} from "./LegacyHelper.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {TestKeys} from "@gearbox-protocol/permissionless/contracts/test/helpers/TestKeys.sol";

contract FundsBack is Script, GlobalSetup, AnvilHelper, LegacyHelper {
    using LibString for string;

    bool realDeploy = vm.envOr("REAL_DEPLOY", false);

    // VmSafe.Wallet[] internal initialSigners;
    address internal instanceOwner;
    VmSafe.Wallet internal auditor;
    VmSafe.Wallet internal author;

    address[] sponsoredAddresses;

    constructor() GlobalSetup() {
        realDeploy = vm.envOr("REAL_DEPLOY", false);

        if (!realDeploy) {
            _autoImpersonate(false);
            TestKeys testKeys = new TestKeys();
            for (uint256 i; i < testKeys.initialSigners().length; ++i) {
                initialSigners.push(testKeys.initialSigners()[i]);
            }

            instanceOwner = testKeys.instanceOwner().addr;
            auditor = testKeys.auditor();
            author = testKeys.bytecodeAuthor();
            dao = vm.rememberKey(testKeys.dao().privateKey);
            testKeys.printKeys();
        } else {
            uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
            initialSigners.push(vm.createWallet(pk));
            vm.rememberKey(pk);

            instanceOwner = 0x000000000000000000000000000000000000dEaD;
            auditor = vm.createWallet(vm.envUint("AUDITOR_PRIVATE_KEY"));
            author = vm.createWallet(vm.envUint("AUTHOR_PRIVATE_KEY"));
            dao = vm.rememberKey(vm.envUint("DAO_PRIVATE_KEY"));
        }

        uint256 len = initialSigners.length;
        sponsoredAddresses.push(initialSigners[len - 1].addr);
        sponsoredAddresses.push(author.addr);
        sponsoredAddresses.push(dao);

        vm.rememberKey(auditor.privateKey);
        vm.rememberKey(author.privateKey);
    }

    function _returnFunds(address[] memory actors, address to) internal {
        for (uint256 i = 0; i < actors.length; ++i) {
            _startPrankOrBroadcast(actors[i]);
            payable(to).transfer(actors[i].balance - 0.0001 ether);
            _stopPrankOrBroadcast();
        }
    }

    function run() public {
        if (block.chainid != 1) return;

        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        _returnFunds(sponsoredAddresses, deployer);

        vm.stopBroadcast();
    }
}
