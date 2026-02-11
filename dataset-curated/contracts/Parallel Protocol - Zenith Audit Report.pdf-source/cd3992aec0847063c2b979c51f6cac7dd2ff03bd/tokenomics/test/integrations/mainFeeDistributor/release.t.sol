// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract MainFeeDistributor_Release_Integrations_Test is Integrations_Test {
    using OptionsBuilder for bytes;

    function test_MainFeeDistributor_Release1(uint256 feeAmount, uint256[] memory shares) external {
        feeAmount = _bound(feeAmount, 1e18, 1e27);
        address[] memory receivers;
        (receivers, shares) = _boundReceiversAndShares(shares);
        vm.startPrank(users.admin.addr);
        mainFeeDistributor.updateFeeReceivers(receivers, shares);
        par.mint(address(mainFeeDistributor), feeAmount);
        uint256 totalShares = mainFeeDistributor.totalShares();

        mainFeeDistributor.release();

        assertAlmostEqual(par.balanceOf(address(mainFeeDistributor)), 0, 10);
        for (uint256 i = 0; i < receivers.length; i++) {
            assertEq(par.balanceOf(receivers[i]), feeAmount * shares[i] / totalShares);
        }
    }

    function test_MainFeeDistributor_Release_RevertWhen_BalanceIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(FeeCollectorCore.NothingToRelease.selector));
        mainFeeDistributor.release();
    }

    function test_MainFeeDistributor_Release_RevertWhen_NoFeeReceivers() external {
        par.mint(address(mainFeeDistributor), INITIAL_BALANCE);
        vm.expectRevert(abi.encodeWithSelector(MainFeeDistributor.NoFeeReceivers.selector));
        mainFeeDistributor.release();
    }

    //-------------------------------------------
    // Helpers functions
    //-------------------------------------------

    function _boundReceiversAndShares(uint256[] memory shares)
        internal
        pure
        returns (address[] memory, uint256[] memory)
    {
        vm.assume(shares.length > 0 && shares.length <= 10);
        address[] memory _receivers = new address[](shares.length);
        uint256[] memory _shares = new uint256[](shares.length);

        for (uint256 i = 0; i < shares.length; i++) {
            _receivers[i] = address(uint160(uint256(keccak256(abi.encode("receiver", i)))));
            _shares[i] = _bound(shares[i], 1, 10_000);
        }
        return (_receivers, _shares);
    }
}
