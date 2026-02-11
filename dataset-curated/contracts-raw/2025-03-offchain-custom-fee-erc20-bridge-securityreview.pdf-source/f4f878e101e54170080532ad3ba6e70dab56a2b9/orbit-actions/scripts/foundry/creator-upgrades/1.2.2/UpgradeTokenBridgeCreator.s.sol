// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {DeploymentHelpersScript} from "../../helper/DeploymentHelpers.s.sol";
import {MockArbSys} from "../../helper/MockArbSys.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

interface IL1AtomicTokenBridgeCreator {
    function retryableSender() external view returns (address);
}

/**
 * @title DeployScript
 * @notice This script will deploy new token bridge creator logic contracts and do the upgrade ot prepare the payload for multisig.
 */
contract UpgradeTokenBridgeCreatorScript is DeploymentHelpersScript {
    bool public isArbitrum;

    function run() public {
        vm.startBroadcast();

        /// deploy logic contract
        address newL1AtomicTokenBridgeCreatorLogic = deployBytecodeFromJSON(
            "/node_modules/@arbitrum/token-bridge-1.2.2/build/contracts/contracts/tokenbridge/ethereum/L1AtomicTokenBridgeCreator.sol/L1AtomicTokenBridgeCreator.json"
        );
        address newL1TokenBridgeRetryableSenderLogic = deployBytecodeFromJSON(
            "/node_modules/@arbitrum/token-bridge-1.2.2/build/contracts/contracts/tokenbridge/ethereum/L1TokenBridgeRetryableSender.sol/L1TokenBridgeRetryableSender.json"
        );

        /// load params
        ProxyAdmin proxyAdmin = ProxyAdmin(vm.envAddress("PROXY_ADMIN_ADDRESS"));
        address tokenBridgeCreator = vm.envAddress("TOKEN_BRIDGE_CREATOR_ADDRESS");
        bool creatorOwnerIsMultisig = vm.envBool("CREATOR_OWNER_IS_MULTISIG");

        TransparentUpgradeableProxy tokenBridgeCreatorProxy = TransparentUpgradeableProxy(payable(tokenBridgeCreator));
        TransparentUpgradeableProxy retryableSenderProxy =
            TransparentUpgradeableProxy(payable(IL1AtomicTokenBridgeCreator(tokenBridgeCreator).retryableSender()));

        /// prepare upgrade calldata (not a proper gnosis safe format, used just for a reference)
        if (creatorOwnerIsMultisig) {
            bytes memory creatorCalldata =
                abi.encodeCall(ProxyAdmin.upgrade, (tokenBridgeCreatorProxy, newL1AtomicTokenBridgeCreatorLogic));
            bytes memory retryableSenderCalldata =
                abi.encodeCall(ProxyAdmin.upgrade, (retryableSenderProxy, newL1TokenBridgeRetryableSenderLogic));

            string memory rootObj = "root";
            vm.serializeString(rootObj, "chainId", vm.toString(block.chainid));
            vm.serializeString(rootObj, "to", vm.toString(address(proxyAdmin)));
            vm.serializeString(rootObj, "creatorCalldata", vm.toString(creatorCalldata));
            string memory finalJson =
                vm.serializeString(rootObj, "retryableSenderCalldata", vm.toString(retryableSenderCalldata));
            vm.writeJson(
                finalJson,
                string(
                    abi.encodePacked(
                        vm.projectRoot(),
                        "/scripts/foundry/creator-upgrades/1.2.2/output/",
                        vm.toString(block.chainid),
                        ".json"
                    )
                )
            );
        } else {
            /// do the upgrade
            proxyAdmin.upgrade(tokenBridgeCreatorProxy, newL1AtomicTokenBridgeCreatorLogic);
            proxyAdmin.upgrade(retryableSenderProxy, newL1TokenBridgeRetryableSenderLogic);

            /// verify
            require(
                proxyAdmin.getProxyImplementation(tokenBridgeCreatorProxy) == newL1AtomicTokenBridgeCreatorLogic,
                "Token bridge creator upgrade failed"
            );
            require(
                proxyAdmin.getProxyImplementation(retryableSenderProxy) == newL1TokenBridgeRetryableSenderLogic,
                "Retryable sender upgrade failed"
            );
        }

        vm.stopBroadcast();
    }
}
