// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {mErc20Host} from "../../src/mToken/host/mErc20Host.sol";
import {Script, console} from "forge-std/Script.sol";

interface IEnable {
    function enableWhitelist() external;
    function disableWhitelist() external;
}

contract SetWhitelistDisabled is Script {
    function run() public virtual {
        uint256 key = vm.envUint("PRIVATE_KEY");

        address[] memory markets = new address[](7);
        markets[0] = 0x269C36A173D881720544Fb303E681370158FF1FD;
        markets[1] = 0xC7Bc6bD45Eb84D594f51cED3c5497E6812C7732f;
        markets[2] = 0xDF0635c1eCfdF08146150691a97e2Ff6a8Aa1a90;
        markets[3] = 0x2B588F7f4832561e46924F3Ea54C244569724915;
        markets[4] = 0x1D8e8cEFEb085f3211Ab6a443Ad9051b54D1cd1a;
        markets[5] = 0x8BaD0c523516262a439197736fFf982F5E0987cC;
        markets[6] = 0x4DF3DD62DB219C47F6a7CB1bE02C511AFceAdf5E;

        for (uint256 i; i < markets.length; i++) {
            address market = markets[i];
            vm.startBroadcast(key);
            IEnable(market).disableWhitelist();
            vm.stopBroadcast();
        }
    }
}
