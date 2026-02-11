// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

import "../src/interfaces/INttManager.sol";
import "../src/interfaces/IManagerBase.sol";

import {NttManager} from "../src/NttManager/NttManager.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract NttManagerHealthCheckScript {
    address public constant NTT_MANAGER_ADDRESS = 0x7d4958454a3f520bDA8be764d06591B054B0bf33;

    address private constant VM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    Vm public constant vm = Vm(VM_ADDRESS);

    function run() public view {
        NttManager nttManager = NttManager(NTT_MANAGER_ADDRESS);

        console2.log("NttManager address: ", address(nttManager));

        bool isPaused = nttManager.isPaused();
        console2.log("Is NttManager paused: ", isPaused);

        INttManager.NttManagerPeer memory peer = nttManager.getPeer(1);
        console2.log("Solana peer: ", vm.toString(peer.peerAddress));

        uint256 tokenBalance = IERC20(nttManager.token()).balanceOf(address(nttManager));
        console2.log("Token balance locked in the contract: ", tokenBalance);
    }
}
