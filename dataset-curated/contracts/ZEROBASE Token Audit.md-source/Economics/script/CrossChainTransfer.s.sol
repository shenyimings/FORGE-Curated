// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;
 
import {Script} from "../lib/forge-std/src/Script.sol";
import {console2} from "../lib/forge-std/src/console2.sol";
import "../src/ZeroBase.sol";
import {SendParam, MessagingFee, OFTReceipt} from "../node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {MessagingReceipt} from "../node_modules/@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { OptionsBuilder } from "../node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
 
contract CrossChainTransferScript is Script {
    using OptionsBuilder for bytes;
    address constant ETH_CONTRACT = 0xb733E5fF6361770771DcfE58491713661Ac11bb3; // ETH Sepolia上的合约地址
    
    // LayerZero Chain IDs
    uint32 constant BSC_CHAIN_ID = 40102; // BSC Testnet
    
    address constant TARGET_ADDRESS = 0x2b2E23ceC9921288f63F60A839E2B28235bc22ad;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        ZEROBASE ethContract = ZEROBASE(ETH_CONTRACT);
        
        uint256 amount = 100 * 1e18; // 100 ZB

        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        SendParam memory sendParam = SendParam({
            dstEid: BSC_CHAIN_ID,
            to: bytes32(uint256(uint160(TARGET_ADDRESS))),
            amountLD: amount,
            minAmountLD: amount * 95 / 100,
            extraOptions: extraOptions,
            composeMsg: "",
            oftCmd: ""
        });
        
        MessagingFee memory estimatedFee = ethContract.quoteSend(sendParam, false);
        console2.log("Estimated native fee:", estimatedFee.nativeFee);
        console2.log("Estimated lzToken fee:", estimatedFee.lzTokenFee);
        
        
        ethContract.send{value: estimatedFee.nativeFee}(
            sendParam,
            estimatedFee,
            payable(vm.addr(privateKey)) // refund address
        );
        
        console2.log("Cross-chain transfer initiated!");

        vm.stopBroadcast();
    }
}
//forge script script/CrossChainTransfer.s.sol:CrossChainTransferScript --rpc-url https://eth-sepolia.api.onfinality.io/public --broadcast