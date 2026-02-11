// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract MainFeeDistributor_SwapLzToken_Integrations_Test is Integrations_Test {
    address internal receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        bridgeableTokenMock.mint(address(mainFeeDistributor), INITIAL_BALANCE);
    }

    function test_MainFeeDistributor_SwapLzToken_AllLzBalance() external {
        bridgeableTokenMock.setMaxMintableAmount(INITIAL_BALANCE);

        mainFeeDistributor.swapLzToken();
        assertEq(bridgeableTokenMock.balanceOf(address(mainFeeDistributor)), 0);
        assertEq(par.balanceOf(address(mainFeeDistributor)), INITIAL_BALANCE);
    }

    function test_MainFeeDistributor_SwapLzToken_NotAllBalance(uint256 maxMintableAmount) external {
        maxMintableAmount = _bound(maxMintableAmount, 1, INITIAL_BALANCE - 1);
        bridgeableTokenMock.setMaxMintableAmount(maxMintableAmount);

        mainFeeDistributor.swapLzToken();
        assertEq(bridgeableTokenMock.balanceOf(address(mainFeeDistributor)), INITIAL_BALANCE - maxMintableAmount);
        assertEq(par.balanceOf(address(mainFeeDistributor)), maxMintableAmount);
    }

    function test_MainFeeDistributor_SwapLzToken_RevertWhen_LzBalanceIsZero() external {
        bridgeableTokenMock.burn(address(mainFeeDistributor), INITIAL_BALANCE);
        vm.expectRevert(abi.encodeWithSelector(MainFeeDistributor.NothingToSwap.selector));
        mainFeeDistributor.swapLzToken();
    }

    function test_MainFeeDistributor_SwapLzToken_RevertWhen_MaxSwappableAmountIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(MainFeeDistributor.MaxSwappableAmountIsZero.selector));
        mainFeeDistributor.swapLzToken();
    }
}
