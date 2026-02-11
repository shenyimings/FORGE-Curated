// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0Script.sol";

// forge script scripts/SubmitSends/SubmitSend.s.sol --rpc-url https://rpc-gel.inkonchain.com
contract SubmitSend is BaseL0Script {
    using OptionsBuilder for bytes;

    uint256 amount = 1e18;
    address public oft = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361; // sfrxUSD
    uint32 public dstEid = 30339; // ink
    address to = /* vm.addr(senderDeployerPK) */ 0x17e06ce6914E3969f7BD37D8b2a563890cA1c96e; // sam

    function run() public broadcastAs(senderDeployerPK) {
        address token = IOFT(oft).token();

        uint256 allowance = IERC20(token).allowance(vm.addr(senderDeployerPK), oft);
        if (allowance < amount) {
            IERC20(token).approve(oft, type(uint256).max);
        }

        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
                dstEid: dstEid,
                to: addressToBytes32(vm.addr(senderDeployerPK)),
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