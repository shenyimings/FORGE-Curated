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

import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { GovernanceOAppSender, TxParams, MessagingFee } from "lib/sky-oapp-oft/contracts/GovernanceOAppSender.sol";
import { GovernanceOAppReceiver } from "lib/sky-oapp-oft/contracts/GovernanceOAppReceiver.sol";
import { MockControlledContract } from "lib/sky-oapp-oft/test/mocks/MockControlledContract.sol";
import { MockSpell } from "lib/sky-oapp-oft/test/mocks/MockSpell.sol";
import { TestHelperOz5WithRevertAssertions } from "lib/sky-oapp-oft/test/foundry/helpers/TestHelperOz5WithRevertAssertions.sol";
import { L1GovernanceRelay } from "src/L1GovernanceRelay.sol";
import { L2GovernanceRelay } from "src/L2GovernanceRelay.sol";
import { GovernanceRelayDeploy } from "deploy/GovernanceRelayDeploy.sol";
import { GovernanceRelayInit } from "deploy/GovernanceRelayInit.sol";

contract FileSpell {
    function cast() public {
        FileLike(address(this)).file("l2Oapp", address(0x11));
        FileLike(address(this)).file("l1GovernanceRelay", address(0x22));
    }
}

contract GovernanceTest is TestHelperOz5WithRevertAssertions, DssTest {
    using OptionsBuilder for bytes;

    DssInstance dss;

    uint32 aEid = 1;
    uint32 bEid = 2;

    address                pauseProxy;
    GovernanceOAppSender   aGov;
    GovernanceOAppReceiver bGov;
    L1GovernanceRelay      aRelay;
    L2GovernanceRelay      bRelay;

    MockControlledContract bControlledContract;

    /// @notice Calls setUp from TestHelper and initializes contract instances for testing.
    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        super.setUp();

        dss = MCD.loadFromChainlog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
        pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");

        // Setup function to initialize 2 Mock Endpoints with Mock MessageLib.
        setUpEndpoints(2, LibraryType.UltraLightNode);

        aGov = new GovernanceOAppSender({
            _endpoint : endpoints[aEid],
            _owner    : address(this)
        });

        bGov = new GovernanceOAppReceiver({
            _governanceOAppSenderEid     : aEid,
            _governanceOAppSenderAddress : addressToBytes32(address(aGov)),
            _endpoint                    : endpoints[bEid],
            _owner                       : address(this)
        });

        aGov.setPeer(bEid, addressToBytes32(address(bGov)));
        bGov.setPeer(aEid, addressToBytes32(address(aGov)));

        aRelay = L1GovernanceRelay(GovernanceRelayDeploy.deployL1(address(this), pauseProxy));
        vm.startPrank(pauseProxy);
        GovernanceRelayInit.init(dss, address(aRelay), address(aGov));
        vm.stopPrank();

        bRelay = L2GovernanceRelay(GovernanceRelayDeploy.deployL2(aEid, address(bGov), address(aRelay)));

        bControlledContract = new MockControlledContract(address(bRelay));

        aGov.setCanCallTarget(address(aRelay), bEid, addressToBytes32(address(bRelay)), true);
    }

    function testRelayEvm() public {
        string memory dataBefore = bControlledContract.data();

        // Generates 1 lzReceive execution option via the OptionsBuilder library.
        // Estimating message gas fees via the quote function.
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        TxParams memory txParams = TxParams({
            dstEid       : bEid,
            dstTarget    : addressToBytes32(address(bRelay)),
            dstCallData  : abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector)),
            extraOptions : options
        });
        MessagingFee memory fee = aGov.quoteTx(txParams, false);

        vm.deal(address(aRelay), fee.nativeFee);

        vm.prank(pauseProxy); aRelay.relayEVM({
            dstEid            : bEid,
            l2GovernanceRelay : address(bRelay),
            target            : address(spell),
            targetData        : abi.encodeWithSelector(spell.cast.selector),
            extraOptions      : options,
            fee               : fee,
            refundAddress     : address(this)
        });

        // Asserting that the receiving OApps have NOT had data manipulated.
        assertEq(bControlledContract.data(), dataBefore, "shouldn't be changed until lzReceive packet is verified");
        assertNotEq(bControlledContract.data(), "test message", "shouldn't be equal to expected result");

        // Deliver packet to bGov manually.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));

        // Asserting that the data variable has updated in the receiving OApp.
        assertEq(bControlledContract.data(), "test message", "lzReceive data assertion failure");
    }

    function testFileSpell() public {
        assertNotEq(address(bRelay.l2Oapp()), address(0x11));
        assertNotEq(bRelay.l1GovernanceRelay(), address(0x22));

        // Generates 1 lzReceive execution option via the OptionsBuilder library.
        // Estimating message gas fees via the quote function.
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        FileSpell spell = new FileSpell();

        TxParams memory txParams = TxParams({
            dstEid       : bEid,
            dstTarget    : addressToBytes32(address(bRelay)),
            dstCallData  : abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector)),
            extraOptions : OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0)
        });
        MessagingFee memory fee = aGov.quoteTx(txParams, false);

        vm.deal(address(aRelay), fee.nativeFee);

        vm.prank(pauseProxy); aRelay.relayEVM({
            dstEid            : bEid,
            l2GovernanceRelay : address(bRelay),
            target            : address(spell),
            targetData        : abi.encodeWithSelector(spell.cast.selector),
            extraOptions      : options,
            fee               : fee,
            refundAddress     : address(this)
        });

        // Deliver packet to bGov manually.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));

        assertEq(address(bRelay.l2Oapp()), address(0x11));
        assertEq(bRelay.l1GovernanceRelay(), address(0x22));
    }
}
