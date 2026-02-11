// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {DeploymentHelpersScript} from "../../helper/DeploymentHelpers.s.sol";
import {AddWasmCacheManagerAction} from "../../../../contracts/child-chain/stylus/AddWasmCacheManagerAction.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

interface ICacheManager {
    function initialize(uint64 initCacheSize, uint64 initDecay) external;
}

/**
 * @title DeployAddWasmCacheManagerActionScript
 * @notice This script deploys CacheManager and then deploys action that's used to add cache manager on a child chain.
 */
contract DeployAddWasmCacheManagerActionScript is DeploymentHelpersScript {
    // https://github.com/OffchainLabs/nitro/releases/tag/consensus-v32
    uint256 public constant TARGET_ARBOS_VERSION = 32;

    function run() public {
        vm.startBroadcast();

        // deploy CacheManger behind proxy
        address cacheManagerLogic = deployBytecodeFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-2.1.0/build/contracts/src/chain/CacheManager.sol/CacheManager.json"
        );
        address cacheManagerProxy = address(
            new TransparentUpgradeableProxy(cacheManagerLogic, vm.envAddress("CACHE_MANAGER_PROXY_ADMIN_ADDRESS"), "")
        );

        ICacheManager cacheManager = ICacheManager(cacheManagerProxy);
        cacheManager.initialize(uint64(vm.envUint("INIT_CACHE_SIZE")), uint64(vm.envUint("INIT_DECAY")));

        // deploy action
        new AddWasmCacheManagerAction({
            _wasmCachemanager: address(cacheManager),
            _targetArbOSVersion: TARGET_ARBOS_VERSION
        });

        vm.stopBroadcast();
    }
}
