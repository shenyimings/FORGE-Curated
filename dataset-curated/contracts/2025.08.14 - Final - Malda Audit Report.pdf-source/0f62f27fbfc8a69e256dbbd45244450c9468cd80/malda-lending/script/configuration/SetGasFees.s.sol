// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {mErc20Host} from "src/mToken/host/mErc20Host.sol";
import {mTokenGateway} from "src/mToken/extension/mTokenGateway.sol";

contract SetGasFees is Script {
    function run() public virtual {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        bool isHost = false;

        address[] memory markets = new address[](8);
        markets[0] = 0x269C36A173D881720544Fb303E681370158FF1FD;
        markets[1] = 0xC7Bc6bD45Eb84D594f51cED3c5497E6812C7732f;
        markets[2] = 0xDF0635c1eCfdF08146150691a97e2Ff6a8Aa1a90;
        markets[3] = 0x2B588F7f4832561e46924F3Ea54C244569724915;
        markets[4] = 0x1D8e8cEFEb085f3211Ab6a443Ad9051b54D1cd1a;
        markets[5] = 0x0B3c6645F4F2442AD4bbee2e2273A250461cA6f8;
        markets[6] = 0x8BaD0c523516262a439197736fFf982F5E0987cC;
        markets[7] = 0x4DF3DD62DB219C47F6a7CB1bE02C511AFceAdf5E;

        uint32[] memory routes = new uint32[](3);
        routes[0] = 8453;
        routes[1] = 59144;
        routes[2] = 1;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 83338358600000;
        amounts[1] = 108904397956204;
        amounts[2] = 3497531544510113;

        if (isHost) {
            console.log("Set gas destination fees on HOST");
            vm.startBroadcast(key);
            for (uint256 i; i < markets.length; i++) {
                for (uint256 j; j < routes.length; j++) {
                    mErc20Host(markets[i]).setGasFee(routes[j], amounts[j]);
                }
            }
            vm.stopBroadcast();
            console.log("Gas fees set");
        } else {
            console.log("Set gas destination fees on EXTENSION");
            vm.startBroadcast(key);
            for (uint256 i; i < markets.length; i++) {
                if (i != 5) { //ezEth available only on Linea
                    mTokenGateway(markets[i]).setGasFee(amounts[1]);
                }
            }
            vm.stopBroadcast();
            console.log("Gas fees set");
        }
    }
}
