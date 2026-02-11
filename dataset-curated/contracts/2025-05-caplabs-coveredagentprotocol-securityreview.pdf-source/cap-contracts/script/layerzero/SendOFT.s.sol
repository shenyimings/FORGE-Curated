// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { LzAddressbook, LzUtils } from "../../contracts/deploy/utils/LzUtils.sol";
import { WalletUtils } from "../../contracts/deploy/utils/WalletUtils.sol";

import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { IOFT } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTReceipt, SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Script, console } from "forge-std/Script.sol";

/**
 * Send an OFT token to a target chain
 */
contract SendOFT is Script, WalletUtils, LzUtils {
    using OptionsBuilder for bytes;

    function run() public {
        // Fetching environment variables
        address oftAddress = vm.envAddress("OFT_ADDRESS");
        uint toChainId = vm.envUint("TO_CHAIN_ID");
        LzAddressbook memory toConfig = _getLzAddressbook(toChainId);
        uint256 _amount = vm.envUint("AMOUNT");

        vm.startBroadcast();

        address toAddress = getWalletAddress();
        console.log("Sending to address: ", toAddress);

        IOFT sourceOFT = IOFT(oftAddress);
        IERC20 token = IERC20(sourceOFT.token());

        bytes memory _extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(65000, 0);
        SendParam memory sendParam = SendParam(
            toConfig.eid, // You can also make this dynamic if needed
            addressToBytes32(toAddress),
            _amount,
            _amount * 9 / 10,
            _extraOptions,
            "",
            ""
        );

        MessagingFee memory fee = sourceOFT.quoteSend(sendParam, false);

        console.log("Fee amount: ", fee.nativeFee);

        // allow the OFT to send the tokens
        token.approve(address(sourceOFT), _amount);
        sourceOFT.send{ value: fee.nativeFee }(sendParam, fee, getWalletAddress());

        // Stop broadcasting
        vm.stopBroadcast();
    }
}
