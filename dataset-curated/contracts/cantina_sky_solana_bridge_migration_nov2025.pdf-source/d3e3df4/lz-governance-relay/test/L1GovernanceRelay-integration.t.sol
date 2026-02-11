// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2025 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.22;

import "dss-test/DssTest.sol";

import { L1GovernanceRelay, MessagingFee, TxParams } from "src/L1GovernanceRelay.sol";
import { GovernanceRelayDeploy } from "deploy/GovernanceRelayDeploy.sol";
import { GovernanceRelayInit } from "deploy/GovernanceRelayInit.sol";
import { GovernanceOAppSender } from "lib/sky-oapp-oft/contracts/GovernanceOAppSender.sol";
import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { SetConfigParam, IMessageLibManager } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import { ExecutorConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface GemLike {
    function approve(address spender, uint256 amount) external;
    function transfer(address recipient, uint256 amount) external;
}

// The purpose of this test is to see things go smooth also when interacting with the real endpoint
contract L1GovernanceRelayIntegrationTest is DssTest {
    using OptionsBuilder for bytes;

    DssInstance dss;
    L1GovernanceRelay relay;
    address pauseProxy;

    address constant ETH_LZ_ENDPOINT          = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant LZ_MAINNET_EXECUTOR      = 0x173272739Bd7Aa6e4e214714048a9fE699453059;
    address constant LZ_LABS_DVN              = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
    address constant SEND_ULN_302_MESSAGE_LIB = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;

    uint32  constant AVAX_EID = 30106;

    event PacketSent(bytes, bytes, address);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        dss = MCD.loadFromChainlog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
        pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");

        relay = L1GovernanceRelay(GovernanceRelayDeploy.deployL1(address(this), pauseProxy));
        GovernanceOAppSender l1Oapp = new GovernanceOAppSender(ETH_LZ_ENDPOINT, pauseProxy);

        vm.startPrank(pauseProxy);

        GovernanceRelayInit.init(dss, address(relay), address(l1Oapp));
        l1Oapp.setCanCallTarget(address(relay), AVAX_EID, bytes32(uint256(uint160(address(0x111)))), true);
        IOAppCore(address(l1Oapp)).setPeer(AVAX_EID, bytes32("peer"));

        ExecutorConfig memory execCfg = ExecutorConfig({
            maxMessageSize: 1_000_000,
            executor:       LZ_MAINNET_EXECUTOR
        });
        UlnConfig memory ulnCfg = UlnConfig({
            confirmations:        15,
            requiredDVNCount:     1,
            optionalDVNCount:     type(uint8).max,
            optionalDVNThreshold: 0,
            requiredDVNs:         new address[](1),
            optionalDVNs:         new address[](0)
        });
        ulnCfg.requiredDVNs[0] = LZ_LABS_DVN;

        SetConfigParam[] memory cfgParams = new SetConfigParam[](2);
        cfgParams[0] = SetConfigParam(AVAX_EID, 1, abi.encode(execCfg));
        cfgParams[1] = SetConfigParam(AVAX_EID, 2, abi.encode(ulnCfg));

        IMessageLibManager(ETH_LZ_ENDPOINT).setConfig(address(l1Oapp), SEND_ULN_302_MESSAGE_LIB, cfgParams);

        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam(AVAX_EID, 1, OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000));
        IOAppOptionsType3(address(l1Oapp)).setEnforcedOptions(opts);

        vm.stopPrank();
    }

    function testRelayEvmWithSentEth() public {
        vm.deal(address(relay), 1 ether);

        vm.expectEmit(false, false, false, false); // Just make sure the packet was sent
        emit PacketSent("", "", address(0));
        vm.prank(pauseProxy);
        relay.relayEVM({
            dstEid            : AVAX_EID,
            l2GovernanceRelay : address(0x111),
            target            : address(0x333),
            targetData        : "",
            extraOptions      : "",
            fee : MessagingFee({
                nativeFee  : 1 ether,
                lzTokenFee : 0
            }),
            refundAddress     : address(0x222)
        });
    }

    function testRelayRawWithSentEth() public {
        vm.deal(address(relay), 1 ether);

        vm.expectEmit(false, false, false, false); // Just make sure the packet was sent
        emit PacketSent("", "", address(0));
        vm.prank(pauseProxy);
        relay.relayRaw({
            txParams : TxParams({
                dstEid       : AVAX_EID,
                dstTarget    : bytes32(uint256(uint160(address(0x111)))),
                dstCallData  : abi.encodeWithSelector(bytes4(0), address(0x333), ""),
                extraOptions : ""
            }),
            fee : MessagingFee({
                nativeFee  : 1 ether,
                lzTokenFee : 0
            }),
            refundAddress : address(0x222)
        });
    }
}
