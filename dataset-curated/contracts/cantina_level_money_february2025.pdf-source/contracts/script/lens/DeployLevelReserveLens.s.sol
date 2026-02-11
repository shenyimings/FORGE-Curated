// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "../DeploymentUtils.s.sol";
import "forge-std/Script.sol";

import {LevelReserveLens} from "../../src/lens/LevelReserveLens.sol";

import {Upgrades} from "@openzeppelin-upgrades/src/Upgrades.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

contract DeployLevelReserveLens is Script, DeploymentUtils {
    struct Contracts {
        LevelReserveLens lens;
    }

    address public admin = 0x343ACce723339D5A417411D8Ff57fde8886E91dc;

    IERC20Metadata usdc = IERC20Metadata(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20Metadata usdt = IERC20Metadata(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    function run() public virtual {
        uint256 deployerPrivateKey = vm.envUint("MAINNET_PRIVATE_KEY");

        upgrade(deployerPrivateKey);
    }

    function deployment(uint256 deployerPrivateKey) public returns (Contracts memory) {
        address deployerAddress = vm.addr(deployerPrivateKey);
        Contracts memory contracts;

        vm.startBroadcast(deployerPrivateKey);
        console.log("Deploying LevelReserveLens from address %s", deployerAddress);

        address proxy =
            Upgrades.deployUUPSProxy("LevelReserveLens.sol", abi.encodeCall(LevelReserveLens.initialize, (admin)));

        contracts.lens = LevelReserveLens(proxy);
        console.log("LevelReserveLens Deployed");

        console.log("Owner", contracts.lens.owner());
        console.log("USDC Reserves", contracts.lens.getReserves(address(usdc)));
        console.log("USDT Reserves", contracts.lens.getReserves(address(usdt)));
        console.log("USDC Mint Price", contracts.lens.getMintPrice(usdc));
        console.log("USDT Mint Price", contracts.lens.getMintPrice(usdt));
        console.log("USDC Redeem Price", contracts.lens.getRedeemPrice(usdc));
        console.log("USDT Redeem Price", contracts.lens.getRedeemPrice(usdt));

        vm.stopBroadcast();

        // Logs
        console.log("=====> Level lens contracts deployed ....");
        console.log(
            "LevelReserveLens Proxy                   : https://etherscan.io/address/%s", address(contracts.lens)
        );

        return contracts;
    }

    function upgrade(uint256 deployerPrivateKey) public {
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        console.log("Deploying LevelReserveLens from address %s", deployerAddress);

        LevelReserveLens impl = new LevelReserveLens();

        vm.stopBroadcast();

        // Logs
        console.log("=====> Level lens implementation deployed ....");
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
