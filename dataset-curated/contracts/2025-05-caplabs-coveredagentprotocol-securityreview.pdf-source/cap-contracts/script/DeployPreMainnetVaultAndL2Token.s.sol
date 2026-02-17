// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";

import { LzAddressbook, LzUtils } from "../contracts/deploy/utils/LzUtils.sol";
import { WalletUtils } from "../contracts/deploy/utils/WalletUtils.sol";
import { PreMainnetVault } from "../contracts/testnetCampaign/PreMainnetVault.sol";
import { L2Token } from "../contracts/token/L2Token.sol";

contract DeployPreMainnetVaultAndL2Token is Script, LzUtils, WalletUtils {
    using stdJson for string;

    // Chain IDs
    string constant SOURCE_RPC_URL = "ethereum-sepolia";
    uint256 constant SOURCE_CHAIN_ID = 11155111;

    string constant TARGET_RPC_URL = "arbitrum-sepolia";
    uint256 constant TARGET_CHAIN_ID = 421614;

    // Max campaign length (1 week)
    uint48 constant MAX_CAMPAIGN_LENGTH = 7 days;

    uint256 sepoliaForkId;
    uint256 arbitrumSepoliaForkId;

    // Deployment addresses
    address public usdc;

    // Deployed contracts
    PreMainnetVault public vault;
    L2Token public l2Token;

    // LayerZero configs
    LzAddressbook public sepoliaConfig;
    LzAddressbook public arbSepoliaConfig;

    function run() external {
        address deployer = getWalletAddress();
        sepoliaForkId = vm.createFork(SOURCE_RPC_URL);
        arbitrumSepoliaForkId = vm.createFork(TARGET_RPC_URL);

        // Get deployment configuration
        usdc = vm.envAddress("USDC_ADDRESS");

        // Get LayerZero configuration for both chains
        sepoliaConfig = _getLzAddressbook(SOURCE_CHAIN_ID);
        arbSepoliaConfig = _getLzAddressbook(TARGET_CHAIN_ID);

        // Deploy PreMainnetVault on Sepolia
        vm.selectFork(sepoliaForkId);
        vm.startBroadcast();
        vault = new PreMainnetVault(usdc, address(sepoliaConfig.endpointV2), arbSepoliaConfig.eid, MAX_CAMPAIGN_LENGTH);
        console.log("PreMainnetVault deployed on Sepolia at:", address(vault));
        vm.stopBroadcast();

        // Deploy L2Token on Arbitrum Sepolia
        vm.selectFork(arbitrumSepoliaForkId);
        vm.startBroadcast();
        l2Token = new L2Token("Boosted cUSD", "bcUSD", address(arbSepoliaConfig.endpointV2), deployer);
        console.log("L2Token deployed on Arbitrum Sepolia at:", address(l2Token));
        vm.stopBroadcast();

        // Link the contracts
        bytes32 l2TokenPeer = addressToBytes32(address(l2Token));
        bytes32 vaultPeer = addressToBytes32(address(vault));

        // Set PreMainnetVault's peer to L2Token
        vm.selectFork(sepoliaForkId);
        vm.startBroadcast();
        vault.setPeer(arbSepoliaConfig.eid, l2TokenPeer);
        console.log("Set PreMainnetVault's peer to L2Token");
        vm.stopBroadcast();

        // Set L2Token's peer to PreMainnetVault
        vm.selectFork(arbitrumSepoliaForkId);
        vm.startBroadcast();
        l2Token.setPeer(sepoliaConfig.eid, vaultPeer);
        console.log("Set L2Token's peer to PreMainnetVault");
        vm.stopBroadcast();
    }
}
