// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { LzAddressbook, LzUtils } from "../../contracts/deploy/utils/LzUtils.sol";
import { WalletUtils } from "../../contracts/deploy/utils/WalletUtils.sol";

import { IZapOFTComposer } from "../../contracts/interfaces/IZapOFTComposer.sol";
import { IZapRouter } from "../../contracts/interfaces/IZapRouter.sol";

import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { IOFT } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTReceipt, SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Script, console } from "forge-std/Script.sol";

/**
 * Send an OFT token to a target chain and compose a Zap message to zap the token out of the vault
 */
contract SendOFTWithZapCompose is Script, WalletUtils, LzUtils {
    using OptionsBuilder for bytes;

    LzAddressbook dstLzAb;
    IZapOFTComposer.ZapMessage zapMessage;

    address srcOftAddress;
    uint256 srcAmount;
    uint256 dstChainId;
    address dstComposerAddress;
    address dstZapRouter;
    address dstStakedCapToken;
    address dstCapToken;

    function run() public {
        // Fetching environment variables
        srcOftAddress = vm.envAddress("SRC_OFT_ADDRESS");
        srcAmount = vm.envUint("SRC_AMOUNT");
        dstChainId = vm.envUint("DST_CHAIN_ID");
        dstComposerAddress = vm.envAddress("DST_COMPOSER_ADDRESS");
        dstZapRouter = vm.envAddress("DST_ZAP_ROUTER");
        dstStakedCapToken = vm.envAddress("DST_STAKED_CAP_TOKEN");
        dstCapToken = vm.envAddress("DST_CAP_TOKEN");
        dstLzAb = _getLzAddressbook(dstChainId);

        vm.startBroadcast();

        address toAddress = getWalletAddress();
        console.log("Sending from address: ", toAddress);
        console.log("From oft balance: ", IERC20(srcOftAddress).balanceOf(toAddress));
        console.log("From native balance: ", address(toAddress).balance);
        console.log("Sending to address: ", toAddress);

        IOFT sourceOFT = IOFT(srcOftAddress);
        IERC20 token = IERC20(sourceOFT.token());

        // ------------------------------- build OFTZapMessage
        {
            IZapRouter.Input[] memory inputs = new IZapRouter.Input[](1);
            inputs[0] = IZapRouter.Input({ token: address(dstStakedCapToken), amount: srcAmount });

            IZapRouter.Output[] memory outputs = new IZapRouter.Output[](1);
            outputs[0] = IZapRouter.Output({ token: address(dstCapToken), minOutputAmount: srcAmount * 999 / 1000 });

            IZapRouter.Order memory order = IZapRouter.Order({
                inputs: inputs,
                outputs: outputs,
                relay: IZapRouter.Relay({ target: address(0), value: 0, data: "" }),
                user: dstComposerAddress,
                recipient: toAddress
            });

            IZapRouter.StepToken[] memory tokens = new IZapRouter.StepToken[](1);
            tokens[0] = IZapRouter.StepToken({ token: address(dstStakedCapToken), index: 4 /* selector size */ });
            IZapRouter.Step[] memory route = new IZapRouter.Step[](1);
            route[0] = IZapRouter.Step({
                target: dstStakedCapToken,
                value: 0,
                data: abi.encodeWithSelector(IERC4626.withdraw.selector, srcAmount, dstZapRouter, dstZapRouter),
                tokens: new IZapRouter.StepToken[](0)
            });

            zapMessage = IZapOFTComposer.ZapMessage({ order: order, route: route });
        }

        uint128 dstZapGasEstimate = 700000;
        uint128 srcZapGasEstimate = dstZapGasEstimate * 3; // src gas is 3x cheaper than dst gas

        // ------------------------------- send a properly formatted zap message
        {
            console.log("Sending correct zap");
            bytes memory _extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(65000, 0)
                .addExecutorLzComposeOption(0, dstZapGasEstimate, 0);
            bytes memory encodedZapMessage = abi.encode(zapMessage);

            SendParam memory sendParam = SendParam(
                dstLzAb.eid,
                addressToBytes32(dstComposerAddress),
                srcAmount,
                srcAmount * 9 / 10,
                _extraOptions,
                encodedZapMessage,
                ""
            );

            MessagingFee memory fee = sourceOFT.quoteSend(sendParam, false);
            fee.nativeFee += srcZapGasEstimate;

            console.log("Fee amount: ", fee.nativeFee);

            token.approve(address(sourceOFT), srcAmount);
            sourceOFT.send{ value: fee.nativeFee }(sendParam, fee, getWalletAddress());
        }

        // ------------------------------- send an incorrect zap
        {
            console.log("Sending incorrect zap");
            // modify the zap message to make the zap fail
            // removing the input will make the token manager empty and the zap will fail
            zapMessage.order.inputs = new IZapRouter.Input[](0);

            bytes memory _extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(65000, 0)
                .addExecutorLzComposeOption(0, dstZapGasEstimate, 0);

            bytes memory encodedZapMessage = abi.encode(zapMessage);

            SendParam memory sendParam = SendParam(
                dstLzAb.eid,
                addressToBytes32(dstComposerAddress),
                srcAmount,
                srcAmount * 9 / 10,
                _extraOptions,
                encodedZapMessage,
                ""
            );

            MessagingFee memory fee = sourceOFT.quoteSend(sendParam, false);
            fee.nativeFee += srcZapGasEstimate;

            console.log("Fee amount: ", fee.nativeFee);

            sourceOFT.send{ value: fee.nativeFee }(sendParam, fee, getWalletAddress());
        }

        // Stop broadcasting
        vm.stopBroadcast();
    }
}
