// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/BaseL0Script.sol";
import "contracts/FraxOFTMintableUpgradeable.sol";

// forge script scripts/ops/dvn/test/5_MintTestOFT.s.sol --rpc-url https://ethereum-sepolia-rpc.publicnode.com --broadcast
contract Send is BaseL0Script {
    address sepoliaOFT = 0x29a5134D3B22F47AD52e0A22A63247363e9F35c2;

    uint256 amount = 10e18;

    function run() public broadcastAs(configDeployerPK) {
        address token = IOFT(sepoliaOFT).token();

        FraxOFTMintableUpgradeable(token).mint(vm.addr(configDeployerPK), amount);
    }
}
