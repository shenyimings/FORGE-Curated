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
import { L2GovernanceRelay } from "src/L2GovernanceRelay.sol";
import { OappSenderMock } from "test/mocks/OappSenderMock.sol";
import { GemMock } from "test/mocks/GemMock.sol";

// Fake callee on L1 for OappMock to call, in practice the call would be on L2 but this checks relayEVM's message.calldata encoding
contract Callee {
    event Relay(address target, bytes targetData);

    // Same signature as L2GovernanceRelay.relay
    function relay(address target, bytes calldata targetData) external {
        emit Relay(target, targetData);
    }
}

contract L1GovernanceRelayTest is DssTest {
    DssInstance dss;
    address pauseProxy;
    L1GovernanceRelay relay;
    address l2GovRelay = address(0x111);
    address l1Oapp;
    GemMock lzToken;
    Callee callee;

    event SentMessageEVM(
        uint32 dstEid,
        bytes32 dstTarget,
        bytes dstCallData,
        bytes extraOptions,
        uint256 nativeFee,
        uint256 lzTokenFee,
        address refundAddress
    );

    event Relay(address target, bytes targetData);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        dss = MCD.loadFromChainlog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
        pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");

        relay = L1GovernanceRelay(GovernanceRelayDeploy.deployL1(address(this), pauseProxy));
        lzToken = new GemMock(100 ether);
        l1Oapp = address(new OappSenderMock(address(lzToken)));
        callee = new Callee();

        vm.startPrank(pauseProxy);
        GovernanceRelayInit.init(dss, address(relay), address(l1Oapp));
        relay.file("lzToken", address(lzToken));
        vm.stopPrank();

        assertEq(dss.chainlog.getAddress("LZ_GOV_RELAY"), address(relay));
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        L1GovernanceRelay r = new L1GovernanceRelay();

        assertEq(r.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(relay), "L1GovernanceRelay");
    }

    function testFile() public {
        checkFileAddress(address(relay), "L1GovernanceRelay", ["lzToken", "l1Oapp"]);
    }

    function testAuthModifiers() public virtual {
        vm.startPrank(address(0xBEEF));
        checkModifier(address(relay), string(abi.encodePacked("L1GovernanceRelay", "/not-authorized")), [
            relay.reclaim.selector,
            relay.reclaimLzToken.selector,
            relay.relayEVM.selector,
            relay.relayRaw.selector
        ]);
        vm.stopPrank();
    }

    function testReceive() public {
        uint256 relayBalanceBefore = address(relay).balance;
        vm.deal(address(this), 1 ether);
        (bool sent, ) = address(relay).call{value: 1 ether}("");
        assertEq(sent, true);
        assertEq(address(relay).balance, relayBalanceBefore + 1 ether);
    }

    function testReclaim() public {
        uint256 initialReceiverBalance = address(0x123).balance;
        vm.deal(address(relay), 1 ether);

        vm.prank(pauseProxy); relay.reclaim(address(0x123), 1 ether);

        assertEq(address(0x123).balance, initialReceiverBalance + 1 ether);
        assertEq(address(relay).balance, 0);
    }

    function testReclaimFailedToSendEther() public {
        vm.deal(address(relay), 1 ether);
        vm.expectRevert("L1GovernanceRelay/failed-to-send-ether");
        vm.prank(pauseProxy); relay.reclaim(address(0x123), 2 ether);
    }

    function testReclaimLzToken() public {
        uint256 initialReceiverBalance = lzToken.balanceOf(address(0x123));
        lzToken.transfer(address(relay), 1 ether);

        vm.prank(pauseProxy); relay.reclaimLzToken(address(0x123), 1 ether);

        assertEq(lzToken.balanceOf(address(0x123)), initialReceiverBalance + 1 ether);
        assertEq(lzToken.balanceOf(address(relay)), 0);
    }

    function _checkRelay(bool isRelayEvm, uint256 sendValue, uint256 nativeFee, uint256 lzTokenFee, bool expectSuccess) internal {
        if (expectSuccess) {
            vm.expectEmit(true, true, true, true);
            emit SentMessageEVM(
                /* dstEid */        5,
                /* dstTarget */     bytes32(uint256(uint160(address(callee)))),
                /* dstCallData */   abi.encodeCall(L2GovernanceRelay.relay, (address(0x333), "789")),
                /* extraOptions */  "1234",
                /* nativeFee */     nativeFee,
                /* lzTokenFee */    lzTokenFee,
                /* refundAddress */ address(0x222)
            );
            vm.expectEmit(true, true, true, true);
            emit Relay(address(0x333), "789");
        }
        vm.prank(pauseProxy);
        if (isRelayEvm) {
            relay.relayEVM{value: sendValue}({
                dstEid            : 5,
                l2GovernanceRelay : address(callee),
                target            : address(0x333),
                targetData        : "789",
                extraOptions      : "1234",
                fee : MessagingFee({
                    nativeFee  : nativeFee,
                    lzTokenFee : lzTokenFee
                }),
                refundAddress     : address(0x222)
            });
        } else {
            relay.relayRaw{value: sendValue}({
                txParams : TxParams({
                    dstEid            : 5,
                    dstTarget         : bytes32(uint256(uint160(address(callee)))),
                    dstCallData       : abi.encodeCall(Callee.relay, (address(0x333), "789")),
                    extraOptions      : "1234"
                }),
                fee : MessagingFee({
                    nativeFee  : nativeFee,
                    lzTokenFee : lzTokenFee
                }),
                refundAddress : address(0x222)
            });
        }
    }

    function testRelayEvmWithSentEth() public {
        vm.deal(address(pauseProxy), 1 ether);
        _checkRelay({ isRelayEvm: true, sendValue: 1 ether, nativeFee: 1 ether, lzTokenFee: 0, expectSuccess: true });
    }

    function testRelayRawWithSentEth() public {
        vm.deal(address(pauseProxy), 1 ether);
        _checkRelay({ isRelayEvm: false, sendValue: 1 ether, nativeFee: 1 ether, lzTokenFee: 0, expectSuccess: true });
    }

    function testRelayEvmWithExistingEth() public {
        vm.deal(address(relay), 1 ether);
        _checkRelay({ isRelayEvm: true, sendValue: 0, nativeFee: 1 ether, lzTokenFee: 0, expectSuccess: true });
    }

    function testRelayRawWithExistingEth() public {
        vm.deal(address(relay), 1 ether);
        _checkRelay({ isRelayEvm: false, sendValue: 0, nativeFee: 1 ether, lzTokenFee: 0, expectSuccess: true });
    }
    
    function testRelayEvmNotEnoughEth() public {
        vm.deal(address(relay), 1 ether / 2);
        vm.expectRevert();
        _checkRelay({ isRelayEvm: true, sendValue: 0, nativeFee: 1 ether, lzTokenFee: 0, expectSuccess: false });
    }

    function testRelayRawNotEnoughEth() public {
        vm.deal(address(relay), 1 ether / 2);
        vm.expectRevert();
        _checkRelay({ isRelayEvm: false, sendValue: 0, nativeFee: 1 ether, lzTokenFee: 0, expectSuccess: false });
    }
    
    function testRelayEvmWithLzToken() public {
        deal(address(lzToken), address(relay), 2 ether);
        _checkRelay({ isRelayEvm: true, sendValue: 0, nativeFee: 0, lzTokenFee: 2 ether, expectSuccess: true });
    }

    function testRelayRawWithLzToken() public {
        deal(address(lzToken), address(relay), 2 ether);
        _checkRelay({ isRelayEvm: false, sendValue: 0, nativeFee: 0, lzTokenFee: 2 ether, expectSuccess: true });
    }

    function testRelayEvmWithNotEnoughToken() public {
        deal(address(lzToken), address(relay), 1 ether);
        vm.expectRevert("Gem/insufficient-balance");
        _checkRelay({ isRelayEvm: true, sendValue: 0, nativeFee: 0, lzTokenFee: 2 ether, expectSuccess: false });
    }

    function testRelayRawWithNotEnoughToken() public {
        deal(address(lzToken), address(relay), 1 ether);
        vm.expectRevert("Gem/insufficient-balance");
        _checkRelay({ isRelayEvm: false, sendValue: 0, nativeFee: 0, lzTokenFee: 2 ether, expectSuccess: false });
    }
    
    function testRelayEvmBothFees() public {
        vm.deal(address(pauseProxy), 1 ether);
        deal(address(lzToken), address(relay), 1 ether);
        _checkRelay({ isRelayEvm: true, sendValue: 1 ether, nativeFee: 1 ether, lzTokenFee: 1 ether, expectSuccess: true });
    }

    function testRelayRawBothFees() public {
        vm.deal(address(pauseProxy), 1 ether);
        deal(address(lzToken), address(relay), 1 ether);
        _checkRelay({ isRelayEvm: false, sendValue: 1 ether, nativeFee: 1 ether, lzTokenFee: 1 ether, expectSuccess: true });
    }
}
