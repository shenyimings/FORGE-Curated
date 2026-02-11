// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import { IGovernanceOAppSender, TxParams } from "../contracts/GovernanceOAppSender.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

contract SendGovernanceMessageScript is Script {
    using OptionsBuilder for bytes;

    function run(uint32 dstEid, bytes32 dstTarget, bytes memory dstCallData) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        IGovernanceOAppSender governance = IGovernanceOAppSender(vm.envAddress("GOVERNANCE_CONTROLLER_ADDRESS"));

        TxParams memory txParams = TxParams({
            dstEid: dstEid,
            dstTarget: dstTarget,
            dstCallData: dstCallData,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(4000000, 4000000)
        });

        MessagingFee memory fee = governance.quoteTx(txParams, false);

        governance.sendTx{value: fee.nativeFee}(txParams, fee, msg.sender);

        vm.stopBroadcast();
    }
}
