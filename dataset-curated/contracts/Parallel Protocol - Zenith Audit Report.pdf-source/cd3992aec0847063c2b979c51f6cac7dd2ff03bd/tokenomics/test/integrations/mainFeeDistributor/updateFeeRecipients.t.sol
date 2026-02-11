// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract MainFeeDistributor_UpdateFeeReceivers_Integrations_Test is Integrations_Test {
    address[] receivers;
    uint256[] shares;

    function setUp() public override {
        super.setUp();

        receivers.push(users.daoTreasury.addr);
        receivers.push(users.insuranceFundMultisig.addr);

        shares.push(1);
        shares.push(2);
    }

    function test_MainFeeDistributor_UpdateFeeReceivers() external {
        vm.startPrank(users.admin.addr);

        mainFeeDistributor.updateFeeReceivers(receivers, shares);

        assertEq(mainFeeDistributor.totalShares(), 3);
        assertEq(mainFeeDistributor.shares(users.daoTreasury.addr), 1);
        assertEq(mainFeeDistributor.shares(users.insuranceFundMultisig.addr), 2);

        address[] memory _feeReceivers = mainFeeDistributor.getFeeReceivers();
        assertEq(_feeReceivers.length, 2);
        assertEq(_feeReceivers[0], receivers[0]);
        assertEq(_feeReceivers[1], receivers[1]);
    }

    function test_MainFeeDistributor_UpdateFeeReceivers_ReplaceCorrectlyCurrentFeeReceivers() external {
        vm.startPrank(users.admin.addr);
        /// @notice Default fee receivers are `daoTreasury` and `insuranceFundMultisig`.
        mainFeeDistributor.updateFeeReceivers(receivers, shares);

        address[] memory newReceivers = new address[](3);
        newReceivers[0] = makeAddr("newReceiver 1");
        newReceivers[1] = makeAddr("newReceiver 2");
        newReceivers[2] = makeAddr("newReceiver 3");
        uint256[] memory newShares = new uint256[](3);
        newShares[0] = 10;
        newShares[1] = 20;
        newShares[2] = 30;

        mainFeeDistributor.updateFeeReceivers(newReceivers, newShares);
        assertEq(mainFeeDistributor.totalShares(), 60);
        assertEq(mainFeeDistributor.shares(newReceivers[0]), 10);
        assertEq(mainFeeDistributor.shares(newReceivers[1]), 20);
        assertEq(mainFeeDistributor.shares(newReceivers[2]), 30);

        address[] memory _feeReceivers = mainFeeDistributor.getFeeReceivers();
        assertEq(_feeReceivers.length, 3);
        assertEq(_feeReceivers[0], newReceivers[0]);
        assertEq(_feeReceivers[1], newReceivers[1]);
        assertEq(_feeReceivers[2], newReceivers[2]);
    }

    function test_MainFeeDistributor_UpdateFeeReceivers_RevertWhen_WhenArrayEmpty() external {
        vm.startPrank(users.admin.addr);
        address[] memory emptyArray = new address[](0);

        vm.expectRevert(abi.encodeWithSelector(MainFeeDistributor.NoFeeReceivers.selector));
        mainFeeDistributor.updateFeeReceivers(emptyArray, shares);
    }

    function test_MainFeeDistributor_UpdateFeeReceivers_RevertWhen_WhenArrayLengthMisMatch() external {
        vm.startPrank(users.admin.addr);
        address[] memory wrongLengthReceivers = new address[](1);
        wrongLengthReceivers[0] = users.daoTreasury.addr;
        vm.expectRevert(abi.encodeWithSelector(MainFeeDistributor.ArrayLengthMismatch.selector));
        mainFeeDistributor.updateFeeReceivers(wrongLengthReceivers, shares);
    }

    function test_MainFeeDistributor_UpdateFeeReceivers_RevertWhen_WhenReceiverIsAddressZero() external {
        vm.startPrank(users.admin.addr);
        address[] memory wrongReceivers = new address[](2);
        wrongReceivers[0] = users.daoTreasury.addr;
        wrongReceivers[1] = address(0);
        vm.expectRevert(abi.encodeWithSelector(MainFeeDistributor.FeeReceiverZeroAddress.selector));
        mainFeeDistributor.updateFeeReceivers(wrongReceivers, shares);
    }

    function test_MainFeeDistributor_UpdateFeeReceivers_RevertWhen_WhenReceiverSharesIsZero() external {
        vm.startPrank(users.admin.addr);
        uint256[] memory wrongShares = new uint256[](2);
        wrongShares[0] = 1;
        wrongShares[1] = 0;
        vm.expectRevert(abi.encodeWithSelector(MainFeeDistributor.SharesIsZero.selector));
        mainFeeDistributor.updateFeeReceivers(receivers, wrongShares);
    }

    function test_MainFeeDistributor_UpdateFeeReceivers_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        mainFeeDistributor.updateFeeReceivers(receivers, shares);
    }
}
