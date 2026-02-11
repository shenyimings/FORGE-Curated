// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/BaseL0Script.sol";
import "contracts/FraxOFTMintableUpgradeable.sol";

// forge script scripts/ops/FraxDVNTest/mainnet/4_MintMockFrax.s.sol --rpc-url https://rpc.frax.com --broadcast
contract MintMockFrax is BaseL0Script {
    address fraxtalOFT = 0x57558Cb8d6005DE0BAe8a2789d5EfaaE52dba5a8;
    address fraxtalOFTWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;

    uint256 amount = 1000e18;

    function run() public broadcastAs(configDeployerPK) {
        FraxOFTMintableUpgradeable(fraxtalOFT).mint(fraxtalOFTWallet, amount);
    }
}
