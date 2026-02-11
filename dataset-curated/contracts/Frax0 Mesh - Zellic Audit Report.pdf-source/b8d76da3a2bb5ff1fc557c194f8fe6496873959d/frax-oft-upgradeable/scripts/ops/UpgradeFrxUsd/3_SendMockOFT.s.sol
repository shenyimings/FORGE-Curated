// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/*
forge script scripts/UpgradeFrax/3_SendMockOFT.s.sol \ 
--rpc-url https://rpc.frax.com --verifier-url $FRAXSCAN_API_URL --etherscan-api-key $FRAXSCAN_API_KEY
*/
contract SendMockOFT is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    address public mFraxOft = 0x474Aab3444c63D628F916C7941Eb35B32a8e9B70;
    address public mSFraxOft = 0xB9278BD0B54Ee4D39D95fF57Ffc45A8dAffDC438;
    address public ethMsig = 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27;

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/UpgradeFrxUsd/txs/");
        string memory name = string.concat("3_SendMockOFT-", broadcastConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    function run() public override {
        submitSends();
    }

    function submitSends() public simulateAndWriteTxs(broadcastConfig) {
        submitSend(mFraxOft);
        submitSend(mSFraxOft);
    }

    function submitSend(address _oft) public {
        uint256 amount = IERC20(_oft).balanceOf(broadcastConfig.delegate);

        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
                dstEid: uint32(30101), // Ethereum
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
                sendParam, fee, broadcastConfig.delegate
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