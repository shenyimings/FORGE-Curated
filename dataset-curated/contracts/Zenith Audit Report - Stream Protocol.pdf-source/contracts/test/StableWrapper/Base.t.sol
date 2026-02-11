// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {StableWrapper} from "../../src/StableWrapper.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract Base is TestHelperOz5 {
    // contract
    StableWrapper stableWrapper;

    // assets
    MockERC20 usdc;

    // depositors
    address depositor1;
    address depositor2;
    address depositor3;
    address depositor4;
    address depositor5;
    address depositor6;
    address depositor7;
    address depositor8;
    address depositor9;
    address depositor10;
    address[] depositors;

    // admin
    address keeper;
    address keeper2;
    address owner;

    // layerzero
    uint32 private aEid = 1;
    uint32 private bEid = 2;
    address lzDelegate;

    // helper
    uint8 decimals = 6;
    uint256 startingBal = 10000 * (10 ** 6);

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);
        depositor1 = vm.addr(1);
        depositor2 = vm.addr(2);
        depositor3 = vm.addr(3);
        depositor4 = vm.addr(4);
        depositor5 = vm.addr(5);
        depositor6 = vm.addr(6);
        depositor7 = vm.addr(7);
        depositor8 = vm.addr(8);
        depositor9 = vm.addr(9);
        depositor10 = vm.addr(10);

        depositors = [
            depositor1,
            depositor2,
            depositor3,
            depositor4,
            depositor5,
            depositor6,
            depositor7,
            depositor8,
            depositor9,
            depositor10
        ];

        keeper = vm.addr(11);
        keeper2 = vm.addr(12);
        owner = vm.addr(13);

        // lzEndpoint = vm.addr(14);
        lzDelegate = vm.addr(15);

        usdc = new MockERC20("USD Coin", "USDC");

        vm.startPrank(owner);
        stableWrapper = new StableWrapper(
            address(usdc),
            "Wrapped USD Coin",
            "wUSDC",
            decimals,
            keeper,
            address(endpoints[aEid]),
            lzDelegate
        );
        vm.stopPrank();

        // fund deposirs with 10_000 USDC and 100 ETH each and approve vault
        for (uint256 i = 0; i < depositors.length; i++) {
            vm.startPrank(depositors[i]);
            usdc.mint(depositors[i], startingBal);
            usdc.approve(address(stableWrapper), startingBal);
            vm.deal(depositors[i], 10 * (10 ** 18));
            vm.stopPrank();
        }
    }

    function assertEpoch(uint32 expectedEpoch) public {
        uint32 currentEpoch = stableWrapper.currentEpoch();
        assertEq(currentEpoch, expectedEpoch, "current epoch");
    }

    function assertWithdrawalReceipt(address user, uint224 amount) public {
        (uint224 receiptAmount, uint32 receiptEpoch) = stableWrapper
            .withdrawalReceipts(user);
        assertEq(receiptAmount, amount, "withdrawal receipt amount");
        assertEq(
            receiptEpoch,
            stableWrapper.currentEpoch(),
            "withdrawal receipt epoch"
        );
    }

    function assertWrapperBalance(uint256 expectedBalance) public {
        _assertBalance(address(stableWrapper), expectedBalance);
    }

    function assertUserBalance(address user, uint256 expectedBalance) public {
        _assertBalance(user, expectedBalance);
    }

    function _assertBalance(address account, uint256 expectedBalance) public {
        assertEq(usdc.balanceOf(account), expectedBalance, "balance");
    }

    /************************************************
     *  WITHDRAW HELPERS
     ***********************************************/
    function depositFromAddyAndRollEpoch(
        address _depositor,
        uint256 _amount
    ) public {
        vm.prank(keeper);
        stableWrapper.depositToVault(_depositor, _amount);
        vm.prank(owner);
        stableWrapper.processWithdrawals();
    }

    function assertNoStateChangeAfterRevert_Vault(
        address _depositor,
        uint256 _amount
    ) public {
        vm.assertEq(usdc.balanceOf(_depositor), startingBal - _amount);
        vm.assertEq(stableWrapper.totalSupply(), _amount);
        vm.assertEq(stableWrapper.balanceOf(keeper), _amount);
        vm.assertEq(usdc.balanceOf(address(stableWrapper)), 0);
    }
}
