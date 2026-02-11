// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {Script} from "forge-std/Script.sol";
import {IEverclearSpoke} from "src/interfaces/external/everclear/IEverclearSpoke.sol";

contract CreateEverclearIntent is Script {
    function run() public virtual {
        uint256 key = vm.envUint("PRIVATE_KEY");

        address everclearSpoke = 0xf9A4d8cED1b8c53B39429BB9a8A391b74E85aE5C; //op sep
        bytes memory data = "";

        address market = 0x8Ef9d2057Fed09Fd18cbF393D789C6507CD3E875; //destination
        address outputAsset = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9; //weth on eth sep
        uint256 amount = 1e16;
        address token = 0x4200000000000000000000000000000000000006; //weth on op sep

        uint32[] memory destinations = new uint32[](1);
        destinations[0] = uint32(11155111); //eth sep

        vm.startBroadcast(key);
        IERC20(token).approve(everclearSpoke, amount);
        IEverclearSpoke(everclearSpoke).newIntent(destinations, market, token, outputAsset, amount, 0, 0, data);
        vm.stopBroadcast();
    }
}
