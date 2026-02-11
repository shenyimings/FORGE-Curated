// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseL0Script.sol";

contract SubmitSendsFromFraxtal is BaseL0Script {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    uint256[] chainIds;

    constructor() {
        chainIds = [
        //     1, // ethereum,
        //     10, // optimism
        //     56, // bsc
        //     137, // polygon
        //     146, // sonic
        //     196, // xlayer
        //     252, // fraxtal
        //     324, // zksync : skip
        //     1101, // polygon zkevm
        //     1329, // sei
        //     2741, // abstract :skip
        //     8453, // base
        //     34443, // mode
        //     42161, // arbitrum
        //     43114, // avalanche
        //     57073, // ink
        //     59144, // linea
        //     80094, // berachain
        //     81457, // blast
        //     480, // worldchain
        //     130 // unichain
            98866 // plume
        ];
    }

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
        simulateConfig = broadcastConfig;
        _populateConnectedOfts();

        submitSends();
    }

    function submitSends() public {
        submitSends(connectedOfts);
    }

    function submitSends(
        address[] memory _connectedOfts
    ) public broadcastAs(senderDeployerPK) {
        for (uint256 c=0; c<allConfigs.length; c++) {
            // skip if the config is the broadcastConfig
            if (allConfigs[c].chainid == broadcastConfig.chainid) {
                continue;
            }

            for (uint256 i=0; i<chainIds.length; i++) {
                // skip if the chain id is not the active config
                if (allConfigs[c].chainid != chainIds[i]) {
                    continue;
                }

                for (uint256 o=0; o<_connectedOfts.length; o++) {
                    submitSend(
                        allConfigs[c].eid,
                        _connectedOfts[o]
                    );
                }
            }
        }
    }

    /// Similar methods: https://github.com/angg-lz/my-lz-oft/blob/main/tasks/index.ts
    /// https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/OFT.t.sol#L111
    function submitSend(
        uint256 _dstEid,
        address _connectedOft
    ) public {
        uint256 amount = 1e14;
        address oftToken = IOFT(_connectedOft).token();
    
        require(
            IERC20(oftToken).balanceOf(vm.addr(senderDeployerPK)) > amount * chainIds.length,
            "Not enough token balance"
        );

        uint256 allowance = IERC20(oftToken).allowance(vm.addr(senderDeployerPK), _connectedOft);
        if (allowance < amount) {
            IERC20(oftToken).approve(_connectedOft, type(uint256).max);
        }

        // bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300_000, 0);
        bytes memory options = OptionsBuilder.newOptions();
        bytes32 to = _dstEid == 30324 || _dstEid == 30165 
            ? addressToBytes32(address(0)) 
            : addressToBytes32(vm.addr(senderDeployerPK));
        
        SendParam memory sendParam = SendParam({
                dstEid: uint32(_dstEid),
                to: to,
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