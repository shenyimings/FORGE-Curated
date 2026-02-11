// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ShortString, ShortStrings} from "@openzeppelin/contracts/utils/ShortStrings.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {StvPoolFactory} from "src/factories/StvPoolFactory.sol";
import {StvStETHPoolFactory} from "src/factories/StvStETHPoolFactory.sol";

interface ICoreFactory {
    function VAULT_HUB() external view returns (address);
    function STETH() external view returns (address);
    function WSTETH() external view returns (address);
}

contract DashboardStub {
    address public immutable VAULT_HUB;
    address public immutable STETH;
    address public immutable WSTETH;
    address public immutable STAKING_VAULT;

    constructor(address _vaultHub, address _steth, address _wsteth, address _stakingVault) {
        VAULT_HUB = _vaultHub;
        STETH = _steth;
        WSTETH = _wsteth;
        STAKING_VAULT = _stakingVault;
    }

    function stakingVault() external view returns (address) {
        return STAKING_VAULT;
    }
}

contract DeployPoolsVerifySources is Script {
    struct PoolParams {
        bool allowListEnabled;
        bool mintingEnabled;
        uint256 reserveRatioGapBP;
        address strategyFactory;
    }

    struct DeploymentRefs {
        address dashboard;
        address withdrawalQueue;
        address distributor;
    }

    function _readFactoryAddress(string memory _path, string memory jsonPath) internal view returns (address addr) {
        require(vm.isFile(_path), string(abi.encodePacked("FACTORY_DEPLOYMENT_JSON file does not exist at: ", _path)));
        string memory json = vm.readFile(_path);
        addr = vm.parseJsonAddress(json, jsonPath);
        require(addr != address(0), "factory address missing");
    }

    function _readPoolParams(string memory _path) internal view returns (PoolParams memory p) {
        require(vm.isFile(_path), string(abi.encodePacked("POOL_PARAMS_JSON missing at: ", _path)));
        string memory json = vm.readFile(_path);
        p.allowListEnabled = vm.parseJsonBool(json, "$.auxiliaryPoolConfig.allowListEnabled");
        p.mintingEnabled = vm.parseJsonBool(json, "$.auxiliaryPoolConfig.mintingEnabled");
        p.reserveRatioGapBP = vm.parseJsonUint(json, "$.auxiliaryPoolConfig.reserveRatioGapBP");
        try vm.parseJsonAddress(json, "$.strategyFactory") returns (address addr) {
            p.strategyFactory = addr;
        } catch {
            p.strategyFactory = address(0);
        }
    }

    function _readDeploymentRefs(address _dashboard, address _withdrawalQueue, address _distributor)
        internal
        pure
        returns (DeploymentRefs memory p)
    {
        p.dashboard = _dashboard;
        p.withdrawalQueue = _withdrawalQueue;
        p.distributor = _distributor;
    }

    function _stvPoolType() internal pure returns (bytes32) {
        return ShortString.unwrap(ShortStrings.toShortString("StvPool"));
    }

    function _stvStethPoolType() internal pure returns (bytes32) {
        return ShortString.unwrap(ShortStrings.toShortString("StvStETHPool"));
    }

    function _strategyPoolType() internal pure returns (bytes32) {
        return ShortString.unwrap(ShortStrings.toShortString("StvStrategyPool"));
    }

    function _deployStvPool(
        StvPoolFactory _factory,
        PoolParams memory params,
        DeploymentRefs memory refs,
        string memory tag
    ) internal returns (address impl) {
        bytes32 poolType = params.strategyFactory == address(0) ? _stvPoolType() : _strategyPoolType();

        vm.startBroadcast();
        impl =
            _factory.deploy(refs.dashboard, params.allowListEnabled, refs.withdrawalQueue, refs.distributor, poolType);
        vm.stopBroadcast();

        console2.log("Deployed", tag);
        console2.log("  impl:", impl);
    }

    function _deployStvStethPool(
        StvStETHPoolFactory _factory,
        PoolParams memory params,
        DeploymentRefs memory refs,
        string memory tag
    ) internal returns (address impl) {
        bytes32 poolType = params.strategyFactory == address(0) ? _stvStethPoolType() : _strategyPoolType();

        vm.startBroadcast();
        impl = _factory.deploy(
            refs.dashboard,
            params.allowListEnabled,
            params.reserveRatioGapBP,
            refs.withdrawalQueue,
            refs.distributor,
            poolType
        );
        vm.stopBroadcast();

        console2.log("Deployed", tag);
        console2.log("  impl:", impl);
    }

    function run() external {
        string memory factoryDeploymentJson = vm.envString("FACTORY_DEPLOYMENT_JSON");
        string memory stvParamsJson = vm.envString("STV_POOL_PARAMS_JSON");
        string memory stvStethParamsJson = vm.envString("STV_STETH_POOL_PARAMS_JSON");

        address stvPoolFactoryAddr = _readFactoryAddress(factoryDeploymentJson, "$.factories.stvPoolFactory");
        address stvStethPoolFactoryAddr = _readFactoryAddress(factoryDeploymentJson, "$.factories.stvStETHPoolFactory");
        address factoryAddr = _readFactoryAddress(factoryDeploymentJson, "$.deployment.factory");
        ICoreFactory coreFactory = ICoreFactory(factoryAddr);
        address vaultHub = coreFactory.VAULT_HUB();
        address steth = coreFactory.STETH();
        address wsteth = coreFactory.WSTETH();

        PoolParams memory stvParams = _readPoolParams(stvParamsJson);
        PoolParams memory stvStethParams = _readPoolParams(stvStethParamsJson);
        require(stvParams.strategyFactory == address(0), "stv strategyFactory must be zero");
        require(stvStethParams.strategyFactory == address(0), "stv-steth strategyFactory must be zero");
        require(!stvParams.mintingEnabled, "stv mintingEnabled must be false");
        require(stvStethParams.mintingEnabled, "stv-steth mintingEnabled must be true");

        vm.startBroadcast();
        DashboardStub dashboard = new DashboardStub(vaultHub, steth, wsteth, vaultHub);
        vm.stopBroadcast();

        DeploymentRefs memory stvRefs = _readDeploymentRefs(address(dashboard), vaultHub, vaultHub);
        DeploymentRefs memory stvStethRefs = _readDeploymentRefs(address(dashboard), vaultHub, vaultHub);

        _deployStvPool(StvPoolFactory(stvPoolFactoryAddr), stvParams, stvRefs, "stv-impl");
        _deployStvStethPool(
            StvStETHPoolFactory(stvStethPoolFactoryAddr), stvStethParams, stvStethRefs, "stv-steth-impl"
        );
    }
}
