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

contract V31Install is Script, GlobalSetup, AnvilHelper, LegacyHelper {
    using LibString for string;

    bool realDeploy = vm.envOr("REAL_DEPLOY", false);

    // VmSafe.Wallet[] internal initialSigners;
    address internal instanceOwner;
    VmSafe.Wallet internal auditor;
    VmSafe.Wallet internal author;

    address[] sponsoredAddresses;

    address internal admin;
    address internal emergencyAdmin;

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
            initialSigners.push(vm.createWallet(vm.envUint("INITIAL_SIGNER_PRIVATE_KEY")));
            instanceOwner = vm.addr(vm.envUint("INSTANCE_OWNER_PRIVATE_KEY"));
            auditor = vm.createWallet(vm.envUint("AUDITOR_PRIVATE_KEY"));
            author = vm.createWallet(vm.envUint("AUTHOR_PRIVATE_KEY"));
            dao = vm.rememberKey(vm.envUint("DAO_PRIVATE_KEY"));
            admin = vm.addr(vm.envUint("ADMIN_PRIVATE_KEY"));
            emergencyAdmin = vm.addr(vm.envUint("EMERGENCY_ADMIN_PRIVATE_KEY"));
        }

        uint256 len = initialSigners.length;
        for (uint256 i; i < len; ++i) {
            vm.rememberKey(initialSigners[i].privateKey);
        }

        sponsoredAddresses.push(initialSigners[len - 1].addr);
        sponsoredAddresses.push(author.addr);
        sponsoredAddresses.push(dao);

        vm.rememberKey(auditor.privateKey);
        vm.rememberKey(author.privateKey);
    }

    function _fundActors() internal {
        address[] memory actors = new address[](sponsoredAddresses.length);
        for (uint256 i; i < sponsoredAddresses.length; ++i) {
            actors[i] = sponsoredAddresses[i];
        }

        _fundActors(actors, 200_000_000 gwei);
    }

    function run() public {
        if (block.chainid != 1) return;

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        _fundActors();
        _deployGlobalContracts(initialSigners, author, auditor, "Initial Auditor", uint8(initialSigners.length), dao);
        _setUpPeripheryContracts();

        ChainInfo[] memory chains = _getChains();

        CrossChainCall[] memory setRouterCalls = new CrossChainCall[](chains.length);
        for (uint256 i; i < chains.length; ++i) {
            setRouterCalls[i] = CrossChainCall({
                chainId: chains[i].chainId,
                target: address(instanceManager),
                callData: abi.encodeCall(instanceManager.setGlobalAddress, ("GLOBAL::ROUTER", chains[i].router, true))
            });
        }
        _submitBatchAndSign("Set routers", setRouterCalls);

        for (uint256 i; i < chains.length; ++i) {
            if (chains[i].usdt == address(0)) continue;
            CrossChainCall[] memory setUSDTPostfixCalls = new CrossChainCall[](1);

            setUSDTPostfixCalls[0] = CrossChainCall({
                chainId: chains[i].chainId,
                target: address(instanceManager),
                callData: abi.encodeCall(
                    instanceManager.configureGlobal,
                    (
                        address(bytecodeRepository),
                        abi.encodeCall(IBytecodeRepository.setTokenSpecificPostfix, (chains[i].usdt, "USDT"))
                    )
                )
            });
            _submitBatchAndSign(string.concat("Set USDT postfix on ", chains[i].name), setUSDTPostfixCalls);
        }
        // activate instances
        for (uint256 i; i < chains.length; ++i) {
            CrossChainCall[] memory activateCalls =
                _getActivateInstanceCalls(address(instanceManager), instanceOwner, chains[i]);
            _submitBatchAndSign(string.concat("Activate instance on ", chains[i].name), activateCalls);
        }

        // connect legacy market configurators
        address addressProvider = instanceManager.addressProvider();
        address factory =
            IAddressProvider(addressProvider).getAddressOrRevert(AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL);

        bool connectChaosLabs = vm.envOr("CONNECT_CHAOS_LABS", true);
        bool connectNexo = vm.envOr("CONNECT_NEXO", false);
        CuratorInfo[] memory curators = _getCurators(admin, emergencyAdmin);
        for (uint256 i; i < curators.length; ++i) {
            if (curators[i].name.eq("Chaos Labs") && !connectChaosLabs) continue;
            if (curators[i].name.eq("Nexo") && !connectNexo) continue;

            if (curators[i].chainId == 1) _deployLegacyMarketConfigurator(addressProvider, curators[i]);

            CrossChainCall[] memory addCalls =
                _getAddLegacyMarketConfiguratorCalls(addressProvider, factory, curators[i]);
            _submitBatchAndSign(
                string.concat("Add legacy market configurator for ", curators[i].name, " on ", curators[i].chainName),
                addCalls
            );
        }

        vm.stopBroadcast();

        _saveAddresses(vm.envOr("OUT_DIR", string(".")));
    }

    function deployLegacyMarketConfigurators() public {
        if (block.chainid == 1) return;

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        uint256 len = initialSigners.length;
        address[] memory initialSignerAddresses = new address[](len);
        for (uint256 i; i < len; ++i) {
            initialSignerAddresses[i] = initialSigners[i].addr;
        }

        _attachGlobalContracts(initialSignerAddresses, uint8(len), dao);

        address addressProvider = instanceManager.addressProvider();
        bool connectChaosLabs = vm.envOr("CONNECT_CHAOS_LABS", true);
        bool connectNexo = vm.envOr("CONNECT_NEXO", false);
        CuratorInfo[] memory curators = _getCurators(admin, emergencyAdmin);
        for (uint256 i; i < curators.length; ++i) {
            if (curators[i].name.eq("Chaos Labs") && !connectChaosLabs) continue;
            if (curators[i].name.eq("Nexo") && !connectNexo) continue;

            if (curators[i].chainId == block.chainid) _deployLegacyMarketConfigurator(addressProvider, curators[i]);
        }

        vm.stopBroadcast();
    }

    function _setUpPeripheryContracts() internal {
        address addressProvider = instanceManager.addressProvider();

        CrossChainCall[] memory calls = new CrossChainCall[](8);
        calls[0] = _getSetGlobalAddressCall(
            AP_CREDIT_ACCOUNT_COMPRESSOR, address(new CreditAccountCompressor{salt: bytes32(0)}(addressProvider)), true
        );
        calls[1] = _getSetGlobalAddressCall(
            AP_CREDIT_SUITE_COMPRESSOR, address(new CreditSuiteCompressor{salt: bytes32(0)}(addressProvider)), true
        );
        calls[2] = _getSetGlobalAddressCall(
            AP_GAUGE_COMPRESSOR, address(new GaugeCompressor{salt: bytes32(0)}(addressProvider)), true
        );
        calls[3] = _getSetGlobalAddressCall(
            AP_MARKET_COMPRESSOR, address(new MarketCompressor{salt: bytes32(0)}(addressProvider)), true
        );
        calls[4] = _getSetGlobalAddressCall(
            AP_PERIPHERY_COMPRESSOR, address(new PeripheryCompressor{salt: bytes32(0)}(addressProvider)), true
        );
        calls[5] = _getSetGlobalAddressCall(
            AP_PRICE_FEED_COMPRESSOR, address(new PriceFeedCompressor{salt: bytes32(0)}(addressProvider)), true
        );
        calls[6] = _getSetGlobalAddressCall(
            AP_REWARDS_COMPRESSOR, address(new RewardsCompressor{salt: bytes32(0)}(addressProvider)), true
        );
        calls[7] = _getSetGlobalAddressCall(
            AP_TOKEN_COMPRESSOR, address(new TokenCompressor{salt: bytes32(0)}(addressProvider)), true
        );

        _submitBatchAndSign("Save compressors", calls);
    }

    function _getSetGlobalAddressCall(bytes32 key, address addr, bool saveVersion)
        internal
        view
        returns (CrossChainCall memory)
    {
        return CrossChainCall({
            chainId: 0,
            target: address(instanceManager),
            callData: abi.encodeCall(instanceManager.setGlobalAddress, (key, addr, saveVersion))
        });
    }

    function _saveAddresses(string memory path) internal {
        address addressProvider = instanceManager.addressProvider();

        string memory json = vm.serializeAddress("addresses", "instanceManager", address(instanceManager));
        json = vm.serializeAddress("addresses", "bytecodeRepository", address(bytecodeRepository));
        json = vm.serializeAddress("addresses", "multisig", address(multisig));
        json = vm.serializeAddress("addresses", "addressProvider", addressProvider);

        address marketConfiguratorFactory =
            IAddressProvider(addressProvider).getAddressOrRevert(AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL);
        address[] memory marketConfigurators =
            IMarketConfiguratorFactory(marketConfiguratorFactory).getMarketConfigurators();
        for (uint256 i; i < marketConfigurators.length; ++i) {
            json = vm.serializeAddress(
                "addresses",
                string.concat(
                    "market-configurator-",
                    vm.replace(vm.toLowercase(IMarketConfigurator(marketConfigurators[i]).curatorName()), " ", "-")
                ),
                marketConfigurators[i]
            );
        }

        vm.writeJson(json, string.concat(path, "/addresses.json"));
    }
}
