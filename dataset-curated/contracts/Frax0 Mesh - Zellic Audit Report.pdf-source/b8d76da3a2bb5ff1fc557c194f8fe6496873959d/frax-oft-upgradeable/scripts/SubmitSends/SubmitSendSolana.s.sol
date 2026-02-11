// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0Script.sol";

// forge script scripts/SubmitSends/SubmitSend.s.sol --rpc-url https://rpc.frax.com
// NOTE: environment `PK_SENDER_DEPLOYER` must be set to the proper private key
contract SubmitSendSolana is BaseL0Script {
    using OptionsBuilder for bytes;

    uint256 amount = 1e18; // 1.00 frxUSD
    address public oft = 0x0ebFC51719acF4e2D0d4869C04b69F5FD26C27E5; // frxUsd testing lockbox
    uint32 public dstEid = 30168;
    // npx ts-node script/solanaConverter.ts
    bytes32 to = 0x402e86d1cfd2cde4fac63aa8d9892eca6d3c0e08e8335622124332a95df6c10c;

    function run() public broadcastAs(senderDeployerPK) {
        address token = IOFT(oft).token();

        uint256 allowance = IERC20(token).allowance(vm.addr(senderDeployerPK), oft);
        if (allowance < amount) {
            IERC20(token).approve(oft, type(uint256).max);
        }

        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
                dstEid: dstEid,
                to: to,
                amountLD: amount,
                minAmountLD: amount,
                extraOptions: options,
                composeMsg: '',
                oftCmd: ''
        });
        MessagingFee memory fee = IOFT(oft).quoteSend(sendParam, false);
        IOFT(oft).send{value: fee.nativeFee}(
            sendParam,
            fee,
            payable(vm.addr(senderDeployerPK))
        );
    }
}