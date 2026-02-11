// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Factory} from "src/Factory.sol";
import {StvPool} from "src/StvPool.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {IOssifiableProxy} from "src/interfaces/core/IOssifiableProxy.sol";
import {OssifiableProxy} from "src/proxy/OssifiableProxy.sol";

contract DeployPool is Script {
    struct PoolParams {
        Factory.VaultConfig vaultConfig;
        Factory.CommonPoolConfig commonPoolConfig;
        Factory.AuxiliaryPoolConfig auxiliaryPoolConfig;
        Factory.TimelockConfig timelockConfig;
        address strategyFactory;
        uint256 connectDepositWei;
    }

    function _buildOutputPath() internal view returns (string memory) {
        return string(
            abi.encodePacked(
                "deployments/pool-", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".json"
            )
        );
    }

    function _serializeVaultConfig(Factory.VaultConfig memory _cfg) internal returns (string memory json) {
        json = vm.serializeAddress("_vaultConfig", "nodeOperator", _cfg.nodeOperator);
        json = vm.serializeAddress("_vaultConfig", "nodeOperatorManager", _cfg.nodeOperatorManager);
        json = vm.serializeUint("_vaultConfig", "nodeOperatorFeeBP", _cfg.nodeOperatorFeeBP);
        json = vm.serializeUint("_vaultConfig", "confirmExpiry", _cfg.confirmExpiry);
    }

    function _serializeCommonPoolConfig(Factory.CommonPoolConfig memory _cfg) internal returns (string memory json) {
        json = vm.serializeUint("_commonPoolConfig", "minWithdrawalDelayTime", _cfg.minWithdrawalDelayTime);
        json = vm.serializeString("_commonPoolConfig", "name", _cfg.name);
        json = vm.serializeString("_commonPoolConfig", "symbol", _cfg.symbol);
        json = vm.serializeAddress("_commonPoolConfig", "emergencyCommittee", _cfg.emergencyCommittee);
    }

    function _serializeAuxiliaryPoolConfig(Factory.AuxiliaryPoolConfig memory _cfg)
        internal
        returns (string memory json)
    {
        json = vm.serializeBool("_auxiliaryPoolConfig", "allowListEnabled", _cfg.allowListEnabled);
        json = vm.serializeAddress("_auxiliaryPoolConfig", "allowListManager", _cfg.allowListManager);
        json = vm.serializeBool("_auxiliaryPoolConfig", "mintingEnabled", _cfg.mintingEnabled);
        json = vm.serializeUint("_auxiliaryPoolConfig", "reserveRatioGapBP", _cfg.reserveRatioGapBP);
    }

    function _serializeTimelockConfig(Factory.TimelockConfig memory _cfg) internal returns (string memory json) {
        json = vm.serializeUint("_timelockConfig", "minDelaySeconds", _cfg.minDelaySeconds);
        json = vm.serializeAddress("_timelockConfig", "proposer", _cfg.proposer);
        json = vm.serializeAddress("_timelockConfig", "executor", _cfg.executor);
    }

    function _serializeConfig(PoolParams memory _p) internal returns (string memory json) {
        string memory vaultJson = _serializeVaultConfig(_p.vaultConfig);
        string memory commonJson = _serializeCommonPoolConfig(_p.commonPoolConfig);
        string memory auxiliaryJson = _serializeAuxiliaryPoolConfig(_p.auxiliaryPoolConfig);
        string memory timelockJson = _serializeTimelockConfig(_p.timelockConfig);

        json = vm.serializeString("_deployConfig", "vaultConfig", vaultJson);
        json = vm.serializeString("_deployConfig", "commonPoolConfig", commonJson);
        json = vm.serializeString("_deployConfig", "auxiliaryPoolConfig", auxiliaryJson);
        json = vm.serializeString("_deployConfig", "timelockConfig", timelockJson);
        json = vm.serializeAddress("_deployConfig", "strategyFactory", _p.strategyFactory);
        json = vm.serializeUint("_deployConfig", "connectDepositWei", _p.connectDepositWei);
    }

    function _serializeIntermediate(Factory.PoolIntermediate memory _intermediate)
        internal
        returns (string memory json)
    {
        json = vm.serializeAddress("_intermediate", "dashboard", _intermediate.dashboard);
        json = vm.serializeAddress("_intermediate", "poolProxy", _intermediate.poolProxy);
        json = vm.serializeAddress("_intermediate", "poolImpl", _intermediate.poolImpl);
        json = vm.serializeAddress("_intermediate", "withdrawalQueueProxy", _intermediate.withdrawalQueueProxy);
        json = vm.serializeAddress("_intermediate", "wqImpl", _intermediate.wqImpl);
        json = vm.serializeAddress("_intermediate", "timelock", _intermediate.timelock);
    }

    function _serializeDeployment(Factory.PoolDeployment memory _deployment) internal returns (string memory json) {
        json = vm.serializeAddress("_deployment", "vault", _deployment.vault);
        json = vm.serializeAddress("_deployment", "dashboard", _deployment.dashboard);
        json = vm.serializeAddress("_deployment", "pool", _deployment.pool);
        json = vm.serializeAddress("_deployment", "withdrawalQueue", _deployment.withdrawalQueue);
        json = vm.serializeAddress("_deployment", "distributor", _deployment.distributor);
        json = vm.serializeAddress("_deployment", "timelock", _deployment.timelock);
        json = vm.serializeAddress("_deployment", "strategy", _deployment.strategy);
    }

    function _serializeCtorBytecode(
        Factory _factory,
        Factory.PoolIntermediate memory _intermediate,
        Factory.VaultConfig memory _vaultConfig,
        Factory.CommonPoolConfig memory _commonPoolConfig,
        Factory.AuxiliaryPoolConfig memory _auxiliaryConfig,
        bytes32 _poolType
    ) internal returns (string memory json) {
        StvPool pool = StvPool(payable(_intermediate.poolProxy));
        address dashboard = _intermediate.dashboard;
        address withdrawalQueue = _intermediate.withdrawalQueueProxy;
        address distributor = address(pool.DISTRIBUTOR());

        bytes memory poolCtorBytecode = abi.encodePacked(
            type(OssifiableProxy).creationCode,
            abi.encode(_factory.DUMMY_IMPLEMENTATION(), address(_factory), bytes(""))
        );

        bytes memory poolImplementationCtorBytecode;
        if (_poolType == _factory.STV_POOL_TYPE()) {
            poolImplementationCtorBytecode = abi.encodePacked(
                type(StvPool).creationCode,
                abi.encode(dashboard, _auxiliaryConfig.allowListEnabled, withdrawalQueue, distributor)
            );
        } else {
            poolImplementationCtorBytecode = abi.encodePacked(
                type(StvStETHPool).creationCode,
                abi.encode(
                    dashboard,
                    _auxiliaryConfig.allowListEnabled,
                    _auxiliaryConfig.reserveRatioGapBP,
                    withdrawalQueue,
                    distributor,
                    _poolType
                )
            );
        }

        address withdrawalImpl = IOssifiableProxy(withdrawalQueue).proxy__getImplementation();
        bytes memory withdrawalInitData = abi.encodeCall(
            WithdrawalQueue.initialize,
            (
                _vaultConfig.nodeOperatorManager,
                _vaultConfig.nodeOperator,
                _commonPoolConfig.emergencyCommittee,
                _commonPoolConfig.emergencyCommittee
            )
        );
        bytes memory withdrawalCtorBytecode = abi.encodePacked(
            type(OssifiableProxy).creationCode, abi.encode(withdrawalImpl, _intermediate.timelock, withdrawalInitData)
        );

        json = vm.serializeBytes("_ctorBytecode", "poolProxy", poolCtorBytecode);
        json = vm.serializeBytes("_ctorBytecode", "poolImplementation", poolImplementationCtorBytecode);
        json = vm.serializeBytes("_ctorBytecode", "withdrawalQueueProxy", withdrawalCtorBytecode);
    }

    function _readPoolParams(string memory _path) internal view returns (PoolParams memory p) {
        string memory json = vm.readFile(_path);
        p.vaultConfig = Factory.VaultConfig({
            nodeOperator: vm.parseJsonAddress(json, "$.vaultConfig.nodeOperator"),
            nodeOperatorManager: vm.parseJsonAddress(json, "$.vaultConfig.nodeOperatorManager"),
            nodeOperatorFeeBP: vm.parseJsonUint(json, "$.vaultConfig.nodeOperatorFeeBP"),
            confirmExpiry: vm.parseJsonUint(json, "$.vaultConfig.confirmExpiry")
        });

        p.commonPoolConfig = Factory.CommonPoolConfig({
            minWithdrawalDelayTime: vm.parseJsonUint(json, "$.commonPoolConfig.minWithdrawalDelayTime"),
            name: vm.parseJsonString(json, "$.commonPoolConfig.name"),
            symbol: vm.parseJsonString(json, "$.commonPoolConfig.symbol"),
            emergencyCommittee: vm.parseJsonAddress(json, "$.commonPoolConfig.emergencyCommittee")
        });

        p.auxiliaryPoolConfig = Factory.AuxiliaryPoolConfig({
            allowListEnabled: vm.parseJsonBool(json, "$.auxiliaryPoolConfig.allowListEnabled"),
            allowListManager: vm.parseJsonAddress(json, "$.auxiliaryPoolConfig.allowListManager"),
            mintingEnabled: vm.parseJsonBool(json, "$.auxiliaryPoolConfig.mintingEnabled"),
            reserveRatioGapBP: vm.parseJsonUint(json, "$.auxiliaryPoolConfig.reserveRatioGapBP")
        });

        p.timelockConfig = Factory.TimelockConfig({
            minDelaySeconds: vm.parseJsonUint(json, "$.timelockConfig.minDelaySeconds"),
            proposer: vm.parseJsonAddress(json, "$.timelockConfig.proposer"),
            executor: vm.parseJsonAddress(json, "$.timelockConfig.executor")
        });

        p.connectDepositWei = vm.parseJsonUint(json, "$.connectDepositWei");

        try vm.parseJsonAddress(json, "$.strategyFactory") returns (address addr) {
            p.strategyFactory = addr;
        } catch {}
    }

    function _loadIntermediate(string memory _path) internal view returns (Factory.PoolIntermediate memory) {
        string memory json = vm.readFile(_path);
        return Factory.PoolIntermediate({
            dashboard: vm.parseJsonAddress(json, "$.intermediate.dashboard"),
            poolProxy: vm.parseJsonAddress(json, "$.intermediate.poolProxy"),
            poolImpl: vm.parseJsonAddress(json, "$.intermediate.poolImpl"),
            withdrawalQueueProxy: vm.parseJsonAddress(json, "$.intermediate.withdrawalQueueProxy"),
            wqImpl: vm.parseJsonAddress(json, "$.intermediate.wqImpl"),
            timelock: vm.parseJsonAddress(json, "$.intermediate.timelock")
        });
    }

    function _readIntermediateDeployParams(string memory _path) internal view returns (PoolParams memory) {
        string memory json = vm.readFile(_path);
        return PoolParams({
            vaultConfig: Factory.VaultConfig({
                nodeOperator: vm.parseJsonAddress(json, "$.config.vaultConfig.nodeOperator"),
                nodeOperatorManager: vm.parseJsonAddress(json, "$.config.vaultConfig.nodeOperatorManager"),
                nodeOperatorFeeBP: vm.parseJsonUint(json, "$.config.vaultConfig.nodeOperatorFeeBP"),
                confirmExpiry: vm.parseJsonUint(json, "$.config.vaultConfig.confirmExpiry")
            }),
            commonPoolConfig: Factory.CommonPoolConfig({
                minWithdrawalDelayTime: vm.parseJsonUint(json, "$.config.commonPoolConfig.minWithdrawalDelayTime"),
                name: vm.parseJsonString(json, "$.config.commonPoolConfig.name"),
                symbol: vm.parseJsonString(json, "$.config.commonPoolConfig.symbol"),
                emergencyCommittee: vm.parseJsonAddress(json, "$.config.commonPoolConfig.emergencyCommittee")
            }),
            auxiliaryPoolConfig: Factory.AuxiliaryPoolConfig({
                allowListEnabled: vm.parseJsonBool(json, "$.config.auxiliaryPoolConfig.allowListEnabled"),
                allowListManager: vm.parseJsonAddress(json, "$.config.auxiliaryPoolConfig.allowListManager"),
                mintingEnabled: vm.parseJsonBool(json, "$.config.auxiliaryPoolConfig.mintingEnabled"),
                reserveRatioGapBP: vm.parseJsonUint(json, "$.config.auxiliaryPoolConfig.reserveRatioGapBP")
            }),
            timelockConfig: Factory.TimelockConfig({
                minDelaySeconds: vm.parseJsonUint(json, "$.config.timelockConfig.minDelaySeconds"),
                proposer: vm.parseJsonAddress(json, "$.config.timelockConfig.proposer"),
                executor: vm.parseJsonAddress(json, "$.config.timelockConfig.executor")
            }),
            strategyFactory: vm.parseJsonAddress(json, "$.config.strategyFactory"),
            connectDepositWei: vm.parseJsonUint(json, "$.config.connectDepositWei")
        });
    }

    function run() external {
        string memory factoryAddress = vm.envString("FACTORY_ADDRESS");
        string memory deployMode = vm.envOr("DEPLOY_MODE", string(""));

        require(bytes(factoryAddress).length != 0, "FACTORY_ADDRESS env var must be set and non-empty");
        Factory factory = Factory(vm.parseAddress(factoryAddress));

        string memory intermediateJsonPath = vm.envOr("INTERMEDIATE_JSON", _buildOutputPath());

        if (keccak256(bytes(deployMode)) == keccak256(bytes("start"))) {
            _runStart(factory, intermediateJsonPath);
        } else if (keccak256(bytes(deployMode)) == keccak256(bytes("finish"))) {
            _runFinish(factory, intermediateJsonPath);
        } else {
            _runStart(factory, intermediateJsonPath);
            _runFinish(factory, intermediateJsonPath);
        }
    }

    function _runStart(Factory _factory, string memory _intermediateJsonPath) internal {
        require(
            !vm.isFile(_intermediateJsonPath),
            string(abi.encodePacked("Intermediate JSON file already exists at: ", _intermediateJsonPath))
        );

        string memory paramsJsonPath = vm.envString("POOL_PARAMS_JSON");
        require(bytes(paramsJsonPath).length != 0, "POOL_PARAMS_JSON env var must be set and non-empty");
        if (!vm.isFile(paramsJsonPath)) {
            revert(string(abi.encodePacked("POOL_PARAMS_JSON file does not exist at: ", paramsJsonPath)));
        }

        require(msg.sender.balance > 1 ether, "msg.sender balance must be above 1 ether");

        PoolParams memory p = _readPoolParams(paramsJsonPath);

        require(bytes(p.commonPoolConfig.name).length != 0, "commonPoolConfig.name missing");
        require(bytes(p.commonPoolConfig.symbol).length != 0, "commonPoolConfig.symbol missing");
        require(p.connectDepositWei > 0, "connectDepositWei missing");

        vm.startBroadcast();

        Factory.PoolIntermediate memory intermediate = _factory.createPoolStart(
            p.vaultConfig, p.timelockConfig, p.commonPoolConfig, p.auxiliaryPoolConfig, p.strategyFactory, ""
        );

        vm.stopBroadcast();

        console2.log("Intermediate:");
        console2.log("  dashboard:", intermediate.dashboard);
        console2.log("  poolProxy:", intermediate.poolProxy);
        console2.log("  withdrawalQueueProxy:", intermediate.withdrawalQueueProxy);
        console2.log("  timelock:", intermediate.timelock);

        // Save config and intermediate to output file
        string memory configJson = _serializeConfig(p);
        string memory intermediateJson = _serializeIntermediate(intermediate);

        string memory rootJson = vm.serializeString("_deploy", "config", configJson);
        rootJson = vm.serializeString("_deploy", "intermediate", intermediateJson);

        vm.writeJson(rootJson, _intermediateJsonPath);
        console2.log("\nDeployment intermediate saved to:", _intermediateJsonPath);
    }

    function _runFinish(Factory _factory, string memory _intermediateJsonPath) internal {
        require(bytes(_intermediateJsonPath).length != 0, "INTERMEDIATE_JSON env var must be set and non-empty");
        if (!vm.isFile(_intermediateJsonPath)) {
            revert(string(abi.encodePacked("INTERMEDIATE_JSON file does not exist at: ", _intermediateJsonPath)));
        }

        Factory.PoolIntermediate memory intermediate = _loadIntermediate(_intermediateJsonPath);
        PoolParams memory p = _readIntermediateDeployParams(_intermediateJsonPath);

        vm.startBroadcast();

        _factory.createPoolFinish{value: p.connectDepositWei}(
            p.vaultConfig,
            p.timelockConfig,
            p.commonPoolConfig,
            p.auxiliaryPoolConfig,
            p.strategyFactory,
            "",
            intermediate
        );

        vm.stopBroadcast();

        console2.log("Deploy config:");
        console2.log("  name:", p.commonPoolConfig.name);
        console2.log("  symbol:", p.commonPoolConfig.symbol);
        console2.log("  allowListEnabled:", p.auxiliaryPoolConfig.allowListEnabled);
        console2.log("  mintingEnabled:", p.auxiliaryPoolConfig.mintingEnabled);
        console2.log("  owner:", p.vaultConfig.nodeOperator);
        console2.log("  nodeOperator:", p.vaultConfig.nodeOperator);
        console2.log("  nodeOperatorManager:", p.vaultConfig.nodeOperatorManager);
        console2.log("  nodeOperatorFeeBP:", p.vaultConfig.nodeOperatorFeeBP);
        console2.log("  confirmExpiry:", p.vaultConfig.confirmExpiry);
        console2.log("  minWithdrawalDelayTime:", p.commonPoolConfig.minWithdrawalDelayTime);
        console2.log("  reserveRatioGapBP:", p.auxiliaryPoolConfig.reserveRatioGapBP);
        console2.log("  strategyFactory:", p.strategyFactory);
        console2.log("  connectDepositWei:", p.connectDepositWei);

        // console2.log("\nDeployment addresses:");
        // console2.log("  Vault:", deployment.vault);
        // console2.log("  Dashboard:", deployment.dashboard);
        // console2.log("  Pool:", deployment.pool);
        // console2.log("  WithdrawalQueue:", deployment.withdrawalQueue);
        // console2.log("  Distributor:", deployment.distributor);
        // console2.log("  Timelock:", deployment.timelock);
        // console2.log("  Strategy:", deployment.strategy);

        // // Read existing intermediate file and update with deployment
        // string memory configJson = _serializeConfig(p);
        // string memory intermediateJson = _serializeIntermediate(intermediate);
        // string memory deploymentJson = _serializeDeployment(deployment);
        // string memory ctorJson = _serializeCtorBytecode(_factory, intermediate, p.vaultConfig, p.commonPoolConfig, p.auxiliaryPoolConfig, poolType);

        // string memory rootJson = vm.serializeString("_deploy", "config", configJson);
        // rootJson = vm.serializeString("_deploy", "intermediate", intermediateJson);
        // rootJson = vm.serializeString("_deploy", "deployment", deploymentJson);
        // rootJson = vm.serializeString("_deploy", "ctorBytecode", ctorJson);

        // vm.writeJson(rootJson, _intermediateJsonPath);
        // console2.log("\nDeployment completed and saved to:", _intermediateJsonPath);
    }
}
