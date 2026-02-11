// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {mTokenGateway} from "src/mToken/extension/mTokenGateway.sol";
import {Script, console} from "forge-std/Script.sol";

contract SetWhitelistedUsersOnGateway is Script {
    function run() public virtual {
        uint256 key = vm.envUint("PRIVATE_KEY");

        mTokenGateway market = mTokenGateway(0xcb4d153604a6F21Ff7625e5044E89C3b903599Bc);

        address[] memory users = new address[](25);
        users[0] = 0xf20a8950c368Ec48323092D6e4acF90aADf2BdC6;
        users[1] = 0x8E72a24221517E51502f20f387415a06b27A5b51;
        users[2] = 0x50d8Deadd2b3140B151CaB2C4FB76F1f59b236F8;
        users[3] = 0x574582C44e3f1EF2cB29a7131B057FebBCC8244E;
        users[4] = 0x281567fe62b587EC1755f6F33b80160F544Dc5d0;
        users[5] = 0x2705f6A8F01bd4A805D9FC73151DBe37BB8d1edE;
        users[6] = 0xc9C9693b6A445D05Add0043662fad9Ac600Ad088;
        users[7] = 0x7EfE40B2E6dA8b28AaB6Bd2D622B9Cd7f5fE077c;
        users[8] = 0xa22DCB8F0A2848289124086F35ae9dB2a0006962;
        users[9] = 0xB819A871d20913839c37f316Dc914b0570bfc0eE;
        users[10] = 0x40282d3Cf4890D9806BC1853e97a59C93D813653;
        users[11] = 0xB5b901F1BB86421301138b5c45C1D3Fe96663161;
        users[12] = 0xBAec8904499dcdee770c60df15b0C37EAC84Fb62;
        users[13] = 0xfC4A23271b60887FC246B060B6931a08E2BC434c;
        users[14] = 0x65b142550aE82f4BB3792E1eEfb2FC35541A3837;
        users[15] = 0x75149feEBb20E1fE5Ddb89302a6d4bACE70c14Ce;
        users[16] = 0x65B6D4770DAdcFba6d363dE86aA4D9c76283cea0;
        users[17] = 0xa6A9fdDC94BB4FE7520A2eA1CC2c433e18683342;
        users[18] = 0x18D04F05f80ADE5373849385a1c24E1E0a6d1744;
        users[19] = 0xBD9C90D6774CB5320B54Bb7998b6Bcc5e4A9071f;
        users[20] = 0x8f2eABa31B1b613ca78F2795bA05400F0583c5A4;
        users[21] = 0x8f2eABa31B1b613ca78F2795bA05400F0583c5A4;
        users[22] = 0x50d8Deadd2b3140B151CaB2C4FB76F1f59b236F8;
        users[23] = 0x574582C44e3f1EF2cB29a7131B057FebBCC8244E;
        users[24] = 0xBd0Ce952bA069A1e15f3bf3916d4B07bBBdBC8B3;

        for (uint256 i; i < users.length; ++i) {
            console.log("Setting whitelisted user:", users[i]);
            vm.startBroadcast(key);
            market.setWhitelistedUser(users[i], true);
            vm.stopBroadcast();

            console.log("Set", i);
        }
    }
}
