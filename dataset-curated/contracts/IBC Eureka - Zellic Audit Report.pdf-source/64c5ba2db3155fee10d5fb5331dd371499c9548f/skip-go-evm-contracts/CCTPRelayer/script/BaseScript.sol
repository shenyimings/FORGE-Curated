pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "./Config.sol";

contract BaseScript is Script {
    address public immutable usdc;
    address public immutable messenger;
    address public immutable transmitter;

    constructor() {
        if (block.chainid == CHAIN_MAINNET) {
            usdc = USDC_MAINNET;
            messenger = MESSENGER_MAINNET;
            transmitter = TRANSMITTER_MAINNET;
        } else if (block.chainid == CHAIN_AVALANCHE) {
            usdc = USDC_AVALANCHE;
            messenger = MESSENGER_AVALANCHE;
            transmitter = TRANSMITTER_AVALANCHE;
        } else if (block.chainid == CHAIN_OP) {
            usdc = USDC_OP;
            messenger = MESSENGER_OP;
            transmitter = TRANSMITTER_OP;
        } else if (block.chainid == CHAIN_ARBITRUM) {
            usdc = USDC_ARBITRUM;
            messenger = MESSENGER_ARBITRUM;
            transmitter = TRANSMITTER_ARBITRUM;
        } else if (block.chainid == CHAIN_BASE) {
            usdc = USDC_BASE;
            messenger = MESSENGER_BASE;
            transmitter = TRANSMITTER_BASE;
        } else if (block.chainid == CHAIN_POLYGON) {
            usdc = USDC_POLYGON;
            messenger = MESSENGER_POLYGON;
            transmitter = TRANSMITTER_POLYGON;
        } else if (block.chainid == CHAIN_SEPOLIA) {
            usdc = USDC_SEPOLIA;
            messenger = MESSENGER_SEPOLIA;
            transmitter = TRANSMITTER_SEPOLIA;
        } else if (block.chainid == CHAIN_AVALANCHE_FUJI) {
            usdc = USDC_AVALANCHE_FUJI;
            messenger = MESSENGER_AVALANCHE_FUJI;
            transmitter = TRANSMITTER_AVALANCHE_FUJI;
        } else if (block.chainid == CHAIN_OP_SEPOLIA) {
            usdc = USDC_OP_SEPOLIA;
            messenger = MESSENGER_OP_SEPOLIA;
            transmitter = TRANSMITTER_OP_SEPOLIA;
        } else if (block.chainid == CHAIN_ARBITRUM_SEPOLIA) {
            usdc = USDC_ARBITRUM_SEPOLIA;
            messenger = MESSENGER_ARBITRUM_SEPOLIA;
            transmitter = TRANSMITTER_ARBITRUM_SEPOLIA;
        } else if (block.chainid == CHAIN_BASE_SEPOLIA) {
            usdc = USDC_BASE_SEPOLIA;
            messenger = MESSENGER_BASE_SEPOLIA;
            transmitter = TRANSMITTER_BASE_SEPOLIA;
        } else if (block.chainid == CHAIN_POLYGON_MUMBAI) {
            usdc = USDC_POLYGON_MUMBAI;
            messenger = MESSENGER_POLYGON_MUMBAI;
            transmitter = TRANSMITTER_POLYGON_MUMBAI;
        } else {
            revert("Chain not supported.");
        }
    }
}
