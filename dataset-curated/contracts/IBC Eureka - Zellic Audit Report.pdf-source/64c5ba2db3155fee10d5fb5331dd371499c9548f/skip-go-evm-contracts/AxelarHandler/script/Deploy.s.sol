// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GoFastHandler} from "../src/GoFastHandler.sol";

contract GoFastHandlerDeploy is Script {
    address public constant SWAP_ROUTER_ABRITRUM = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address public constant FAST_TRANSFER_GATEWAY_ABRITRUM = 0x23Cb6147E5600C23d1fb5543916D3D5457c9B54C;

    address public constant SWAP_ROUTER_OPTIMISM = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address public constant FAST_TRANSFER_GATEWAY_OPTIMISM = 0x0F479de4fD3144642f1Af88e3797B1821724f703;

    address public constant SWAP_ROUTER_POLYGON = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address public constant FAST_TRANSFER_GATEWAY_POLYGON = 0x3Ffaf8D0D33226302E3a0AE48367cF1Dd2023B1f;

    address public constant SWAP_ROUTER_BASE = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address public constant FAST_TRANSFER_GATEWAY_BASE = 0x43d090025aAA6C8693B71952B910AC55CcB56bBb;

    address public constant SWAP_ROUTER_AVALANCHE = 0xbb00FF08d01D300023C629E8fFfFcb65A5a578cE;
    address public constant FAST_TRANSFER_GATEWAY_AVALANCHE = 0xD415B02A7E91dBAf92EAa4721F9289CFB7f4E1cF;

    address public constant SWAP_ROUTER_ETHEREUM = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address public constant FAST_TRANSFER_GATEWAY_ETHEREUM = 0xE7935104c9670015b21c6300E5b95d2F75474CDA;

    GoFastHandler public handler;

    function run() external {
        (address swapRouter, address fastTransferGateway) = _getInitValues(block.chainid);

        vm.startBroadcast();

        GoFastHandler handlerImpl = new GoFastHandler();

        ERC1967Proxy handlerProxy = new ERC1967Proxy(
            address(handlerImpl),
            abi.encodeWithSignature("initialize(address,address)", swapRouter, fastTransferGateway)
        );

        handler = GoFastHandler(payable(address(handlerProxy)));

        vm.stopBroadcast();

        console.log("GoFastHandler deployed at: ", address(handler));
    }

    function _getInitValues(uint256 chainID) internal pure returns (address, address) {
        if (chainID == 42161) {
            return (SWAP_ROUTER_ABRITRUM, FAST_TRANSFER_GATEWAY_ABRITRUM);
        }

        if (chainID == 10) {
            return (SWAP_ROUTER_OPTIMISM, FAST_TRANSFER_GATEWAY_OPTIMISM);
        }

        if (chainID == 137) {
            return (SWAP_ROUTER_POLYGON, FAST_TRANSFER_GATEWAY_POLYGON);
        }

        if (chainID == 8453) {
            return (SWAP_ROUTER_BASE, FAST_TRANSFER_GATEWAY_BASE);
        }

        if (chainID == 43114) {
            return (SWAP_ROUTER_AVALANCHE, FAST_TRANSFER_GATEWAY_AVALANCHE);
        }

        if (chainID == 1) {
            return (SWAP_ROUTER_ETHEREUM, FAST_TRANSFER_GATEWAY_ETHEREUM);
        }

        revert("Unsupported chain");
    }
}
