// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;
 
import {Script} from "../lib/forge-std/src/Script.sol";
import {console2} from "../lib/forge-std/src/console2.sol";
import "../src/ZeroBase.sol";
 
contract SetTrustedRemoteScript is Script {
    address constant ETH_CONTRACT = 0xb733E5fF6361770771DcfE58491713661Ac11bb3; // 替换为ETH Sepolia上的合约地址
    address constant BSC_CONTRACT = 0x9c8749892De34dCe62C06eb2E0Fb1D62B8601a49; // 替换为BSC测试网上的合约地址
    
    // LayerZero Chain IDs
    uint32 constant ETH_CHAIN_ID = 40161; // ETH Sepolia
    uint32 constant BSC_CHAIN_ID = 40102; // BSC Testnet

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        // sepolia
        ZEROBASE ethContract = ZEROBASE(ETH_CONTRACT);
        ethContract.setPeer(BSC_CHAIN_ID, bytes32(uint256(uint160(BSC_CONTRACT))));
        console2.log("Set BSC as peer on ETH Sepolia");

        // bnb testnet
        // ZEROBASE bscContract = ZEROBASE(BSC_CONTRACT);
        // bscContract.setPeer(ETH_CHAIN_ID, bytes32(uint256(uint160(ETH_CONTRACT))));
        // console2.log("Set ETH as peer on BSC Testnet");

        vm.stopBroadcast();
    }
}
//forge script script/SetTrustedRemote.s.sol:SetTrustedRemoteScript --rpc-url https://eth-sepolia.api.onfinality.io/public --broadcast
//forge script script/SetTrustedRemote.s.sol:SetTrustedRemoteScript --rpc-url https://bsc-testnet.public.blastapi.io --broadcast