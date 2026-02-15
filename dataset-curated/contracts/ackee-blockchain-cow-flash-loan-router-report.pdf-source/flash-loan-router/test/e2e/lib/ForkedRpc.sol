// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

library ForkedRpc {
    function forkEthereumMainnetAtBlock(Vm vm, uint256 blockNumber) internal returns (uint256 forkId) {
        string memory forkUrl;
        try vm.envString("MAINNET_ARCHIVE_NODE_URL") returns (string memory url) {
            forkUrl = url;
        } catch {
            forkUrl = "https://eth.merkle.io";
        }
        forkId = vm.createSelectFork(forkUrl, blockNumber);
    }
}
