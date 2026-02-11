// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Rebalancer} from "src/rebalancer/Rebalancer.sol";
import {IRebalancer} from "src/interfaces/IRebalancer.sol";
import {Script} from "forge-std/Script.sol";

contract RebalanceWithEverclear is Script {
    function run() public virtual {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");
        vm.startBroadcast(key);

        Rebalancer rebalancer = Rebalancer(0xDB9b98b15960DBfd61e12f0d58E24482B80c06fe);

        address market = 0x8Ef9d2057Fed09Fd18cbF393D789C6507CD3E875;
        address outputAsset = 0x4200000000000000000000000000000000000006;
        uint256 amount = 1e16;
        bytes memory data = "";
        bytes memory btw = abi.encode(market, outputAsset, amount, data);

        rebalancer.sendMsg{value: 0}(
            0xAe84D0E4be93bF996A3aE96fBCA32d4db5748a7a,
            0x8Ef9d2057Fed09Fd18cbF393D789C6507CD3E875,
            1e16,
            IRebalancer.Msg(11155420, 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9, btw, "")
        );
        vm.stopBroadcast();
    }
}
