// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Base.t.sol";

contract MainFeeDistributor_Constructor_Integrations_Test is Base_Test {
    function setUp() public override {
        super.setUp();
        mainFeeDistributor = new MainFeeDistributor(address(accessManager), address(bridgeableTokenMock), address(par));
    }

    function test_MainFeeDistributor_Constructor() external view {
        assertEq(mainFeeDistributor.authority(), address(accessManager));
        assertEq(address(mainFeeDistributor.bridgeableToken()), address(bridgeableTokenMock));
        assertEq(mainFeeDistributor.feeToken(), par);
    }
}
