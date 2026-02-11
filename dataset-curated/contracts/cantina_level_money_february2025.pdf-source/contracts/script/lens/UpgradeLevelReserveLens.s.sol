// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "../DeploymentUtils.s.sol";
import "forge-std/Script.sol";

import {LevelReserveLens} from "../../src/lens/LevelReserveLens.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

import {Upgrades} from "@openzeppelin-upgrades/src/Upgrades.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

contract UpgradeLevelReserveLens is Script, DeploymentUtils, ContractAddresses {
    address public admin = 0x343ACce723339D5A417411D8Ff57fde8886E91dc;

    IERC20Metadata usdc = IERC20Metadata(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20Metadata usdt = IERC20Metadata(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    // constructor() {
    // uint256 chainId = vm.envUint("CHAIN_ID");
    // _initializeAddresses(chainId);
    // }

    function run() public virtual {
        console.log("Begin");
        uint256 deployerPrivateKey = vm.envUint("MAINNET_PRIVATE_KEY");
        // upgrade(deployerPrivateKey);
    }

    function upgrade(uint256 deployerPrivateKey) public {
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        console.log("Deploying LevelReserveLens from address %s", deployerAddress);

        LevelReserveLens impl = LevelReserveLens(0x4664a1802e7dE6Ff829d23f1D82cC49311E921dc);

        // lens.upgradeToAndCall(address(impl), "");

        vm.stopBroadcast();

        // Logs
        console.log("=====> Level lens contracts deployed ....");
        console.log(
            "LevelReserveLens Implementation                   : https://etherscan.io/address/%s", address(impl)
        );

        verify(impl);
    }

    function verify(LevelReserveLens lens) public view {
        console.log("Owner", lens.owner());
        console.log("USDC Reserves", lens.getReserves(address(usdc)));
        console.log("USDT Reserves", lens.getReserves(address(usdt)));
        console.log("USDC Mint Price", lens.getMintPrice(usdc));
        console.log("USDT Mint Price", lens.getMintPrice(usdt));
        console.log("USDC Redeem Price", lens.getRedeemPrice(usdc));
        console.log("USDT Redeem Price", lens.getRedeemPrice(usdt));
    }
}
