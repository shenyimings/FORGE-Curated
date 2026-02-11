// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";

import { LzAddressbook, LzUtils } from "../contracts/deploy/utils/LzUtils.sol";
import { WalletUtils } from "../contracts/deploy/utils/WalletUtils.sol";
import { PreMainnetVault } from "../contracts/testnetCampaign/PreMainnetVault.sol";
import { L2Token } from "../contracts/token/L2Token.sol";

contract DeployPreMainnetVault is Script, LzUtils, WalletUtils {
    using stdJson for string;

    string constant SOURCE_RPC_URL = "mainnet";
    uint256 constant SOURCE_CHAIN_ID = 1;

    string constant TARGET_RPC_URL = "megaeth-testnet";
    uint256 constant TARGET_CHAIN_ID = 6342;

    // Max campaign length (1 week)
    uint48 constant CAMPAIGN_TIMESTAMP_END = 1754006400;

    uint256 mainnetForkId;
    uint256 megaethTestnetForkId;

    // Deployment addresses
    address public usdc;
    address public l2TokenAddress;

    // Deployed contracts
    PreMainnetVault public vault;
    L2Token public l2Token;

    // LayerZero configs
    LzAddressbook public mainnetConfig;
    LzAddressbook public megaethTestnetConfig;

    function run() external {
        // address deployer = getWalletAddress();
        mainnetForkId = vm.createFork(SOURCE_RPC_URL);
        // megaethTestnetForkId = vm.createFork(TARGET_RPC_URL);

        // Get deployment configuration
        usdc = vm.envAddress("USDC_ADDRESS");
        l2TokenAddress = vm.envAddress("L2TOKEN_ADDRESS");

        // Get LayerZero configuration for both chains
        mainnetConfig = _getLzAddressbook(SOURCE_CHAIN_ID);
        megaethTestnetConfig = _getLzAddressbook(TARGET_CHAIN_ID);

        // compute time left in campaign
        console.log("current timestamp:", block.timestamp);
        console.log("campaign timestamp end:", CAMPAIGN_TIMESTAMP_END);
        uint48 timeLeft = uint48(CAMPAIGN_TIMESTAMP_END - block.timestamp);
        console.log("time left:", timeLeft);

        // Deploy PreMainnetVault on Sepolia
        vm.selectFork(mainnetForkId);
        vm.startBroadcast();
        vault = new PreMainnetVault(usdc, address(mainnetConfig.endpointV2), megaethTestnetConfig.eid, timeLeft);
        console.log("PreMainnetVault deployed on Sepolia at:", address(vault));
        vm.stopBroadcast();

        l2Token = L2Token(l2TokenAddress);

        // Link the contracts
        bytes32 l2TokenPeer = addressToBytes32(address(l2Token));

        // Set PreMainnetVault's peer to L2Token
        vm.selectFork(mainnetForkId);
        vm.startBroadcast();
        vault.setPeer(megaethTestnetConfig.eid, l2TokenPeer);
        console.log("Set PreMainnetVault's peer to L2Token");
        vm.stopBroadcast();
    }
}
