pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

import { ERC1967Utils } from "@openzeppelin-5/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { FrxUSDOFTUpgradeable } from "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";
import { SFrxUSDOFTUpgradeable } from "contracts/frxUsd/SFrxUSDOFTUpgradeable.sol";
import { WFRAXTokenOFTUpgradeable } from "contracts/WFRAXTokenOFTUpgradeable.sol";


abstract contract UpgradeV110Destinations is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    address public oftImplementation;
    address public frxUsdImplementation;
    address public sfrxUsdImplementation;
    address public wfraxImplementation;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/V110/destinations/txs/");
        string memory name = string.concat("UpgradeV110Destination-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    function upgradeToV110(L0Config memory _config) public {
        
        // Setup environment
        vm.createSelectFork(_config.RPC);
        simulateConfig = _config;
        _populateConnectedOfts();
        delete serializedTxs;

        if (_config.chainid == 1) {
            // For ethereum, only upgrade WFRAX
            vm.startBroadcast(configDeployerPK);
            deployWFraxImplementation(_config.endpoint);
            vm.stopBroadcast();
            
            address[] memory implementations = new address[](1);
            implementations[0] = wfraxImplementation;

            connectedOfts = new address[](1);
            connectedOfts[0] = ethFraxOft;
            
            submitUpgrades(implementations);
        } else {
            // For all other chains, upgrade all OFTs
            vm.startBroadcast(configDeployerPK);
            deployImplementations(_config.endpoint);
            vm.stopBroadcast();

            // align implementations to the order of connectedOfts array
            address[] memory implementations = new address[](6);
            implementations[0] = wfraxImplementation; // WFRAX
            implementations[1] = sfrxUsdImplementation; // sfrxUSD
            implementations[2] = oftImplementation; // sfrxETH
            implementations[3] = frxUsdImplementation; // frxUSD
            implementations[4] = oftImplementation; // frxETH
            implementations[5] = oftImplementation; // FPI

            submitUpgrades(implementations);
        }
    }

    function deployImplementations(address _endpoint) public {
        deployOftImplementation(_endpoint);
        deployFrxUsdImplementation(_endpoint);
        deploySFrxUsdImplementation(_endpoint);
        deployWFraxImplementation(_endpoint);
    }

    function deployOftImplementation(address _endpoint) public {
        oftImplementation = address(new FraxOFTUpgradeable(_endpoint));
    }

    function deployFrxUsdImplementation(address _endpoint) public {
        frxUsdImplementation = address(new FrxUSDOFTUpgradeable(_endpoint));
    }

    function deploySFrxUsdImplementation(address _endpoint) public {
        sfrxUsdImplementation = address(new SFrxUSDOFTUpgradeable(_endpoint));
    }

    function deployWFraxImplementation(address _endpoint) public {
        wfraxImplementation = address(new WFRAXTokenOFTUpgradeable(_endpoint));
    }

    function submitUpgrades(address[] memory _implementations) public {        
        
        // get address of proxyAdmin - will be the same across all connected OFTs
        bytes32 adminSlot = vm.load(connectedOfts[0], ERC1967Utils.ADMIN_SLOT);
        proxyAdmin = address(uint160(uint256(adminSlot)));

        // Simulate calls from the delegate, who also has upgrade rights through the proxyAdmin
        vm.startPrank(simulateConfig.delegate);
        
        for (uint256 i=0; i<_implementations.length; i++) {
            address oft = connectedOfts[i];
            address implementation = _implementations[i];

            // cache the symbol to ensure we're upgrading to the right implementation
            string memory symbolBefore = FraxOFTUpgradeable(oft).symbol();

            // Generate the msig slot
            bytes memory initData = abi.encodeWithSignature("initializeV110()");
            bytes memory upgradeData = abi.encodeCall(
                ProxyAdmin.upgradeAndCall,
                (TransparentUpgradeableProxy(payable(oft)), implementation, initData)
            );
            (bool success, ) = proxyAdmin.call(upgradeData);
            require(success, "Upgrade failed: Unable to upgrade proxy");

            serializedTxs.push(
                SerializedTx({
                    name: "upgrade",
                    to: proxyAdmin,
                    value: 0,
                    data: upgradeData
                })
            );

            // post-upgrade validations
            require(
                isStringEqual(symbolBefore, FraxOFTUpgradeable(oft).symbol()),
                "Upgrade failed: Symbol changed unexpectedly"
            );

            require(
                isStringEqual(FraxOFTUpgradeable(oft).version(), "1.1.0"),
                "Upgrade failed: version mismatch"
            );
        }

        vm.stopPrank();

        if (serializedTxs.length > 0) {
            new SafeTxUtil().writeTxs(serializedTxs, filename());
        }
    }
}