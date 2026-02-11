// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0Script.sol";

contract SubmitSendsFromFraxtal is BaseL0Script {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    constructor() {}

    function version() public pure override returns (uint256, uint256, uint256) {
        return (1, 2, 0);
    }


    function setUp() public override {
        for (uint256 i=0; i<expectedProxyOfts.length; i++) {
            proxyOfts.push(expectedProxyOfts[i]);
        }

        super.setUp();
    }

    function run() public {
        // for (uint256 c=0; c<proxyConfigs.length; c++) {
        for (uint256 c=0; c<3; c++) {
            // skip zk-chains
            if (proxyConfigs[c].chainid != 324 && proxyConfigs[c].chainid != 2741) continue;

            simulateConfig = proxyConfigs[c];
            _populateConnectedOfts();

            vm.createSelectFork(proxyConfigs[c].RPC);

            submitSends(connectedOfts);
        }
    }

    function submitSends(
        address[] memory _connectedOfts
    ) public broadcastAs(senderDeployerPK) {
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            submitSend(
                _connectedOfts[o]
            );
        }
    }

    /// Similar methods: https://github.com/angg-lz/my-lz-oft/blob/main/tasks/index.ts
    /// https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/OFT.t.sol#L111
    function submitSend(
        address _connectedOft
    ) public {
        uint256 amount = 1e14;
        address oftToken = IOFT(_connectedOft).token();
    
        if (IERC20(oftToken).balanceOf(vm.addr(senderDeployerPK)) < amount) {
            console.log("Chain ID %s", simulateConfig.chainid);
            console.log("Not enough %s", oftToken);
            return;
        }

        uint256 allowance = IERC20(oftToken).allowance(vm.addr(senderDeployerPK), _connectedOft);
        if (allowance < amount) {
            IERC20(oftToken).approve(_connectedOft, type(uint256).max);
        }

        // bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300_000, 0);
        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
                dstEid: uint32(30255), // fraxtal
                to: addressToBytes32(vm.addr(senderDeployerPK)),
                amountLD: amount,
                minAmountLD: amount,
                extraOptions: options,
                composeMsg: '',
                oftCmd: ''
        });
        MessagingFee memory fee = IOFT(_connectedOft).quoteSend(sendParam, false);
        fee.nativeFee *= 2; // double the fee to account for a delay in tx send, and fluctuation in gas prices
        IOFT(_connectedOft).send{value: fee.nativeFee}(
            sendParam,
            fee,
            payable(vm.addr(senderDeployerPK))
        );
    }
}