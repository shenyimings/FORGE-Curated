// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/BaseL0Script.sol";

// forge script scripts/ops/dvn/test/6_SendMintableTestOFT.s.sol --rpc-url https://ethereum-sepolia-rpc.publicnode.com --broadcast
contract SendMintableTestOFT is BaseL0Script {
    using OptionsBuilder for bytes;

    address sepoliaOFT = 0x29a5134D3B22F47AD52e0A22A63247363e9F35c2;
    address arbSepoliaOFT = 0x0768C16445B41137F98Ab68CA545C0afD65A7513;
    uint32 arbSepoliaPeerId = 40231;

    uint256 amount = 1e18;
    uint32 public dstEid = arbSepoliaPeerId;

    function run() public broadcastAs(configDeployerPK) {
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: addressToBytes32(vm.addr(configDeployerPK)),
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = IOFT(sepoliaOFT).quoteSend(sendParam, false);
        IOFT(sepoliaOFT).send{ value: fee.nativeFee }(sendParam, fee, payable(vm.addr(configDeployerPK)));
    }
}
