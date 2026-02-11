// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {mErc20Host} from "src/mToken/host/mErc20Host.sol";
import {mTokenGateway} from "src/mToken/extension/mTokenGateway.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

contract UpgradeMarket is Script {
    // Market type enum to determine which implementation to deploy
    enum MarketType {
        HOST,
        GATEWAY
    }

    // Admin slot from ERC1967
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function run() public {
        // Setup

        address proxy = 0xDF0635c1eCfdF08146150691a97e2Ff6a8Aa1a90;
        MarketType marketType = MarketType.GATEWAY;
        string memory salt = "DeployerV1.0.1";
        address create3Deployer = 0xc781BaD08968E324D1B91Be3cca30fAd86E7BF98;

        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");
        Deployer deployer = Deployer(payable(create3Deployer));
        // Get ProxyAdmin address from proxy
        address proxyAdmin = address(uint160(uint256(vm.load(proxy, ADMIN_SLOT))));
        console.log("ProxyAdmin address:", proxyAdmin);

        // Deploy new implementation
        address newImpl;
        if (marketType == MarketType.HOST) {
            newImpl = _deployHostImplementation(deployer, salt);
        } else {
            newImpl = _deployGatewayImplementation(deployer, salt);
        }

        // Upgrade proxy through ProxyAdmin
        vm.startBroadcast(key);
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(payable(proxy)), newImpl, "");
        vm.stopBroadcast();

        console.log("Upgraded market %s to implementation %s", proxy, newImpl);
    }

    function _deployHostImplementation(Deployer deployer, string memory salt) internal returns (address) {
        bytes32 implSalt = keccak256(abi.encodePacked("mErc20HostImplementation", salt));
        vm.startBroadcast(vm.envUint("OWNER_PRIVATE_KEY"));
        address implementation = deployer.create(implSalt, type(mErc20Host).creationCode);
        vm.stopBroadcast();

        console.log("New mErc20Host implementation deployed at:", implementation);
        return implementation;
    }

    function _deployGatewayImplementation(Deployer deployer, string memory salt) internal returns (address) {
        bytes32 implSalt = keccak256(abi.encodePacked("mTokenGatewayImplementationV1.0.1", salt));
        vm.startBroadcast(vm.envUint("OWNER_PRIVATE_KEY"));
        address implementation = deployer.create(implSalt, type(mTokenGateway).creationCode);
        vm.stopBroadcast();

        console.log("New mTokenGateway implementation deployed at:", implementation);
        return implementation;
    }
}
