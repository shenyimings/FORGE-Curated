// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Rebalancer} from "src/rebalancer/Rebalancer.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {Roles} from "src/Roles.sol";
import {ImToken} from "src/interfaces/ImToken.sol";

/**
 * forge script DeployRebalancer  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --sig "run(address)" 0x0 \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract RedeployRebalancer is Script {
    function run() public returns (address) {
        address roles = 0x1211d07F0EBeA8994F23EC26e1e512929FC8Ab08;
        address saveAddress = 0xB819A871d20913839c37f316Dc914b0570bfc0eE;
        Deployer deployer = Deployer(payable(0xc781BaD08968E324D1B91Be3cca30fAd86E7BF98));

        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");
        bytes32 salt = getSalt("RebalancerV1.0.0");

        address created = deployer.precompute(salt);
        // Deploy only if not already deployed
        if (created.code.length == 0) {
            vm.startBroadcast(key);
            created = deployer.create(salt, abi.encodePacked(type(Rebalancer).creationCode, abi.encode(roles, saveAddress)));
            vm.stopBroadcast();
            console.log("Rebalancer deployed at:", created);
        } else {
            console.log("Using existing Rebalancer at: %s", created);
        }


        // assign roles
        vm.startBroadcast(key);
        Roles(roles).allowFor(created, keccak256(abi.encodePacked("REBALANCER")), true);
        vm.stopBroadcast();

        // allow markets
        address[] memory markets = new address[](8);
        markets[0] = 0x269C36A173D881720544Fb303E681370158FF1FD;
        markets[1] = 0xC7Bc6bD45Eb84D594f51cED3c5497E6812C7732f;
        markets[2] = 0xDF0635c1eCfdF08146150691a97e2Ff6a8Aa1a90;
        markets[3] = 0xcb4d153604a6F21Ff7625e5044E89C3b903599Bc;
        markets[4] = 0x1D8e8cEFEb085f3211Ab6a443Ad9051b54D1cd1a;
        markets[5] = 0x0B3c6645F4F2442AD4bbee2e2273A250461cA6f8;
        markets[6] = 0x8BaD0c523516262a439197736fFf982F5E0987cC;
        markets[7] = 0x4DF3DD62DB219C47F6a7CB1bE02C511AFceAdf5E;
        vm.startBroadcast(key);
        Rebalancer(created).setAllowList(markets, true);
        vm.stopBroadcast();

        // add bridges
        address[] memory bridges = new address[](4);
        bridges[0] = 0x1Fab79E6130C93a2AF11B2a5934589E003107c7c;
        bridges[1] = 0x0be4Ad33E1B8835599857f5a8f110c3537D268A8;
        bridges[2] = 0x9A4Ac70da21a3057Ee8f314C5640913578C7F2a7;
        bridges[3] = 0xF6697bfc708e202c4cF1694deDf1952e7B169b79;

        for (uint256 i; i < bridges.length; i++) {
            vm.startBroadcast(key);
            Rebalancer(created).setWhitelistedBridgeStatus(bridges[i], true);
            vm.stopBroadcast();
        }

        // destinations
        uint32[] memory destinations = new uint32[](3);
        destinations[0] = 1;
        destinations[1] = 8453;
        destinations[2] = 59144;
        for (uint32 i; i < destinations.length; i++) {
            vm.startBroadcast(key);
            Rebalancer(created).setWhitelistedDestination(destinations[i], true);
            vm.stopBroadcast();
        }

        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
