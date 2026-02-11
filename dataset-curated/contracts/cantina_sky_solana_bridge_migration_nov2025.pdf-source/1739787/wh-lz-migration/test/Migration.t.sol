// SPDX-FileCopyrightText: © 2025 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
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

import { DssTest } from "dss-test/DssTest.sol";

import { MigrationDeploy } from "deploy/MigrationDeploy.sol";
import { MigrationInit } from "deploy/MigrationInit.sol";
import { NttManager } from "lib/sky-ntt-migration/evm/src/NttManager/NttManager.sol";
import { SkyOFTAdapter } from "lib/sky-oapp-oft/contracts/SkyOFTAdapter.sol";
import { ISkyRateLimiter } from "lib/sky-oapp-oft/contracts/interfaces/ISkyRateLimiter.sol";
import { GovernanceOAppSender } from "lib/sky-oapp-oft/contracts/GovernanceOAppSender.sol";

import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { SetConfigParam, IMessageLibManager } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import { ExecutorConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface TokenLike {
    function approve(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
}

interface WormholeLike {
    function messageFee() external view returns (uint256);
    function nextSequence(address) external view returns (uint64);
}

contract MigrationTest is DssTest {
    using OptionsBuilder for bytes;

    ChainlogLike public chainlog = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
    NttManager   public nttManager = NttManager(0x7d4958454a3f520bDA8be764d06591B054B0bf33);
    WormholeLike public wormhole = WormholeLike(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B);

    event LogMessagePublished(address indexed sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel);

    address public pauseProxy;
    address public usds;
    address public susds;
    address public nttImpV2;

    bytes32 public oftPeer = bytes32(uint256(0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f));
    bytes32 public govPeer = bytes32(uint256(0xb055b055b055b055b055b055b055b055b055b055b055b055b055b055b055b055));

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        pauseProxy = chainlog.getAddress("MCD_PAUSE_PROXY");
        usds       = chainlog.getAddress("USDS");
        susds      = chainlog.getAddress("SUSDS");

        nttImpV2 = MigrationDeploy.deployMigration();
    }

    function initMigrationStep0(
        address nttManagerImpV2,
        uint256 maxFee,
        bytes memory payload
    ) external {
        vm.startPrank(pauseProxy);
        MigrationInit.initMigrationStep0(nttManagerImpV2, maxFee, payload);
        vm.stopPrank();
    }

    function initMigrationStep1(
        address oftAdapter,
        bytes32 oftPeer_,
        address govOapp,
        bytes32 govPeer_,
        MigrationInit.RateLimitsParams memory rl,
        uint256 maxFee,
        bytes memory transferMintAuthPayload,
        bytes memory transferFreezeAuthPayload,
        bytes memory transferMetadataUpdateAuthPayload
    ) external {
        vm.startPrank(pauseProxy);
        MigrationInit.initMigrationStep1(
            oftAdapter,
            oftPeer_,
            govOapp,
            govPeer_,
            rl,
            maxFee,
            transferMintAuthPayload,
            transferFreezeAuthPayload,
            transferMetadataUpdateAuthPayload
        );
        vm.stopPrank();
    }

    function testMigrationStep0() public {
        vm.expectRevert(bytes(""));
        vm.prank(pauseProxy); nttManager.migrateLockedTokens(address(this));

        vm.mockCall(address(wormhole), abi.encodeWithSelector(WormholeLike.messageFee.selector), abi.encode(1));
        vm.expectRevert("MigrationInit/exceeds-max-fee");
        this.initMigrationStep0(nttImpV2, 0, "123");
        vm.clearMockedCalls();

        vm.expectEmit(true, true, true, true, address(wormhole));
        emit LogMessagePublished(pauseProxy, wormhole.nextSequence(pauseProxy), 0, "123", 202);
        this.initMigrationStep0(nttImpV2, 0, "123");

        vm.prank(pauseProxy); nttManager.migrateLockedTokens(address(this));
    }

    function _initOapp(address oapp, bytes32 peer) internal {
        IOAppCore(oapp).setPeer(MigrationInit.SOL_EID, peer);

        ExecutorConfig memory execCfg = ExecutorConfig({
            maxMessageSize: 1_000_000,
            executor:       0x173272739Bd7Aa6e4e214714048a9fE699453059 // LZ Executor
        });
        UlnConfig memory ulnCfg = UlnConfig({
            confirmations:        15,
            requiredDVNCount:     1,
            optionalDVNCount:     type(uint8).max,
            optionalDVNThreshold: 0,
            requiredDVNs:         new address[](1),
            optionalDVNs:         new address[](0)
        });
        ulnCfg.requiredDVNs[0] = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b; // LayerZero Labs DVN

        SetConfigParam[] memory cfgParams = new SetConfigParam[](2);
        cfgParams[0] = SetConfigParam(MigrationInit.SOL_EID, 1, abi.encode(execCfg));
        cfgParams[1] = SetConfigParam(MigrationInit.SOL_EID, 2, abi.encode(ulnCfg));

        IMessageLibManager(MigrationInit.ETH_LZ_ENDPOINT).setConfig(
            oapp,
            0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1, // SendUln302 message lib
            cfgParams
        );

        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam(MigrationInit.SOL_EID, 1, OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 2_500_000));
        IOAppOptionsType3(oapp).setEnforcedOptions(opts);
    }

    function testMigrationStep1() public {
        SkyOFTAdapter oftAdapter = new SkyOFTAdapter(usds, MigrationInit.ETH_LZ_ENDPOINT, pauseProxy);
        GovernanceOAppSender govOapp = new GovernanceOAppSender({
            _endpoint: MigrationInit.ETH_LZ_ENDPOINT,
            _owner: pauseProxy
        });
        this.initMigrationStep0(nttImpV2, 0, "");
        vm.startPrank(pauseProxy);
        _initOapp(address(govOapp), govPeer);
        _initOapp(address(oftAdapter), oftPeer);
        vm.stopPrank();

        uint256 escrowed = TokenLike(usds).balanceOf(address(nttManager));
        assertGt(escrowed, 0);
        {
        (,uint48 outWindow,,uint256 outLimit) = oftAdapter.outboundRateLimits(MigrationInit.SOL_EID);
        (,uint48  inWindow,,uint256  inLimit) = oftAdapter.inboundRateLimits(MigrationInit.SOL_EID);
        assertEq(outWindow, 0);
        assertEq(outLimit, 0);
        assertEq(inWindow, 0);
        assertEq(inLimit, 0);
        }
        SendParam memory sendParams = SendParam({
            dstEid: MigrationInit.SOL_EID,
            to: bytes32(uint256(0xdede)),
            amountLD: 1 ether,
            minAmountLD: 1 ether,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });
        MessagingFee memory msgFee = oftAdapter.quoteSend(sendParams, false);
        deal(usds, address(this), 1 ether, true);
        TokenLike(usds).approve(address(oftAdapter), 1 ether);
        vm.expectRevert(ISkyRateLimiter.RateLimitExceeded.selector);
        oftAdapter.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));

        MigrationInit.RateLimitsParams memory rl = MigrationInit.RateLimitsParams({
            // using different values for inbound and outbound only for the sake of a more rigorous test, not expecting such values to be used in practice
            outboundWindow:   1.01 days,
            outboundLimit:    1_000_001 ether,
            inboundWindow:    1.02 days,
            inboundLimit:     1_000_002 ether,
            rlAccountingType: 0
        });

        vm.mockCall(address(wormhole), abi.encodeWithSelector(WormholeLike.messageFee.selector), abi.encode(1));
        vm.expectRevert("MigrationInit/exceeds-max-fee");
        this.initMigrationStep1({
            oftAdapter: address(oftAdapter),
            oftPeer_: oftPeer,
            govOapp: address(govOapp),
            govPeer_: govPeer,
            rl: rl,
            maxFee: 0,
            transferMintAuthPayload: "456",
            transferFreezeAuthPayload: "789",
            transferMetadataUpdateAuthPayload: "123"
        });
        vm.clearMockedCalls();

        vm.expectEmit(true, true, true, true, address(wormhole));
        emit LogMessagePublished(pauseProxy, wormhole.nextSequence(pauseProxy), 0, "456", 202);
        vm.expectEmit(true, true, true, true, address(wormhole));
        emit LogMessagePublished(pauseProxy, wormhole.nextSequence(pauseProxy) + 1, 0, "789", 202);
        vm.expectEmit(true, true, true, true, address(wormhole));
        emit LogMessagePublished(pauseProxy, wormhole.nextSequence(pauseProxy) + 2, 0, "123", 202);
        this.initMigrationStep1({
            oftAdapter: address(oftAdapter),
            oftPeer_: oftPeer,
            govOapp: address(govOapp),
            govPeer_: govPeer,
            rl: rl,
            maxFee: 0,
            transferMintAuthPayload: "456",
            transferFreezeAuthPayload: "789",
            transferMetadataUpdateAuthPayload: "123"
        });

        assertEq(TokenLike(usds).balanceOf(address(nttManager)), 0);
        assertEq(TokenLike(usds).balanceOf(address(oftAdapter)), escrowed);
        (,uint48 outWindow2,,uint256 outLimit2) = oftAdapter.outboundRateLimits(MigrationInit.SOL_EID);
        (,uint48  inWindow2,,uint256  inLimit2) = oftAdapter.inboundRateLimits(MigrationInit.SOL_EID);
        assertEq(outWindow2, 1.01 days);
        assertEq(outLimit2, 1_000_001 ether);
        assertEq(inWindow2, 1.02 days);
        assertEq(inLimit2, 1_000_002 ether);
        oftAdapter.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));
    }

    function testInitSusdsBridge() public {
        SkyOFTAdapter oftAdapter = new SkyOFTAdapter(susds, MigrationInit.ETH_LZ_ENDPOINT, pauseProxy);
        vm.startPrank(pauseProxy);
        _initOapp(address(oftAdapter), oftPeer);
        vm.stopPrank();

        (,uint48 outWindow,,uint256 outLimit) = oftAdapter.outboundRateLimits(MigrationInit.SOL_EID);
        (,uint48  inWindow,,uint256  inLimit) = oftAdapter.inboundRateLimits(MigrationInit.SOL_EID);
        assertEq(outWindow, 0);
        assertEq(outLimit, 0);
        assertEq(inWindow, 0);
        assertEq(inLimit, 0);
        SendParam memory sendParams = SendParam({
            dstEid: MigrationInit.SOL_EID,
            to: bytes32(uint256(0xdede)),
            amountLD: 1 ether,
            minAmountLD: 1 ether,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });
        MessagingFee memory msgFee = oftAdapter.quoteSend(sendParams, false);
        deal(susds, address(this), 1 ether, true);
        TokenLike(susds).approve(address(oftAdapter), 1 ether);
        vm.expectRevert(ISkyRateLimiter.RateLimitExceeded.selector);
        oftAdapter.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));

        MigrationInit.RateLimitsParams memory rl = MigrationInit.RateLimitsParams({
            // using different values for inbound and outbound only for the sake of a more rigorous test, not expecting such values to be used in practice
            outboundWindow:   1.01 days,
            outboundLimit:    1_000_001 ether,
            inboundWindow:    1.02 days,
            inboundLimit:     1_000_002 ether,
            rlAccountingType: 0
        });

        vm.startPrank(pauseProxy);
        MigrationInit.initSusdsBridge(address(oftAdapter), oftPeer, rl);
        vm.stopPrank();

        (,uint48 outWindow2,,uint256 outLimit2) = oftAdapter.outboundRateLimits(MigrationInit.SOL_EID);
        (,uint48  inWindow2,,uint256  inLimit2) = oftAdapter.inboundRateLimits(MigrationInit.SOL_EID);
        assertEq(outWindow2, 1.01 days);
        assertEq(outLimit2, 1_000_001 ether);
        assertEq(inWindow2, 1.02 days);
        assertEq(inLimit2, 1_000_002 ether);
        oftAdapter.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));
    }
}
