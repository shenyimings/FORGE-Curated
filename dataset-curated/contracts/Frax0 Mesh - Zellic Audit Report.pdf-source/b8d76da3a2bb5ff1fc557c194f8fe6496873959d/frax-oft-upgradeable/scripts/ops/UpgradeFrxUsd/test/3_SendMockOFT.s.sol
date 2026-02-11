// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// forge script scripts/upgradeFrax/test/3_SendMockOFT.s.sol --rpc-url https://rpc.frax.com
contract SendMockOFT is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    address public mCacOft = 0x8d8F779e1548B0eF538f5Dfe76AbFA232d705C8b; // fraxtal mock CAC
    address public ethMsig = 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27;

    function run() public override {
        submitSends();
    }

    function submitSends() public broadcastAs(configDeployerPK) {
        submitSend(mCacOft);
    }

    function submitSend(address _oft) public {
        uint256 amount = IERC20(_oft).balanceOf(vm.addr(configDeployerPK));

        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
                dstEid: uint32(30184), // base
                to: addressToBytes32(ethMsig),
                amountLD: amount,
                minAmountLD: amount,
                extraOptions: options,
                composeMsg: '',
                oftCmd: ''
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        bytes memory data = abi.encodeCall(
            IOFT.send,
            (
                sendParam, fee, vm.addr(configDeployerPK)
            )
        );
        (bool success, ) = _oft.call{value: fee.nativeFee}(data);
        require(success, "Failed send");
        serializedTxs.push(
            SerializedTx({
                name: "sendMockOFT",
                to: _oft,
                value: fee.nativeFee,
                data: data
            })
        );
    }
}