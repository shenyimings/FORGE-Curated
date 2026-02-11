// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Base.t.sol";

contract SideChainFeeCollector_Constructor_Integrations_Test is Base_Test {
    function setUp() public override {
        super.setUp();
        sideChainFeeCollector = new SideChainFeeCollector(
            address(accessManager), mainEid, address(bridgeableTokenMock), address(mainFeeDistributor), address(par)
        );
    }

    function test_SideChainFeeCollector_Constructor() external view {
        assertEq(sideChainFeeCollector.authority(), address(accessManager));
        assertEq(sideChainFeeCollector.destinationReceiver(), address(mainFeeDistributor));
        assertEq(address(sideChainFeeCollector.bridgeableToken()), address(bridgeableTokenMock));
        assertEq(sideChainFeeCollector.lzEidReceiver(), mainEid);
        assertEq(sideChainFeeCollector.feeToken(), par);
    }
}
