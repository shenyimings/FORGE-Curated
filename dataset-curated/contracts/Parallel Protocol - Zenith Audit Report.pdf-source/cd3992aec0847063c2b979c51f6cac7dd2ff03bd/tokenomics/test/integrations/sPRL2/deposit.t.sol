// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract SPRL2_Deposits_Integrations_Test is Integrations_Test {
    uint256 exactBptAmount = 1e18;

    function setUp() public override {
        super.setUp();
        sigUtils = new SigUtils(prl.DOMAIN_SEPARATOR());

        vm.startPrank(users.alice.addr);
        weth.approve(address(sprl2), type(uint256).max);
    }

    function test_sPRL2_DepositBPT() external {
        deal(address(bpt), address(users.alice.addr), INITIAL_BALANCE);
        bpt.approve(address(sprl2), INITIAL_BALANCE);
        vm.expectEmit(address(sprl2));
        emit TimeLockPenaltyERC20.Deposited(users.alice.addr, INITIAL_BALANCE);
        sprl2.depositBPT(INITIAL_BALANCE);

        assertEq(bpt.balanceOf(address(users.alice.addr)), 0);
        assertEq(sprl2.balanceOf(address(users.alice.addr)), INITIAL_BALANCE);
    }

    function test_sPRL2_DepositPRLAndWeth(uint256 maxPrlAmount, uint256 maxWethAmount) external {
        maxPrlAmount = bound(maxPrlAmount, 1, prl.balanceOf(users.alice.addr));
        maxWethAmount = bound(maxWethAmount, 1, weth.balanceOf(users.alice.addr));

        uint256 alicePrlBalanceBefore = prl.balanceOf(users.alice.addr);
        uint256 aliceWethBalanceBefore = weth.balanceOf(users.alice.addr);

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            _signPermitData(users.alice.privateKey, address(sprl2), maxPrlAmount, address(prl));

        vm.expectEmit(address(sprl2));
        emit TimeLockPenaltyERC20.Deposited(users.alice.addr, exactBptAmount);
        sprl2.depositPRLAndWeth(maxPrlAmount, maxWethAmount, exactBptAmount, deadline, v, r, s);

        assertEq(prl.balanceOf(users.alice.addr), alicePrlBalanceBefore - maxPrlAmount);
        assertEq(weth.balanceOf(users.alice.addr), aliceWethBalanceBefore - maxWethAmount);
        assertEq(sprl2.balanceOf(users.alice.addr), exactBptAmount);
    }

    function test_sPRL2_DepositPRLAndWeth_WithEth(uint256 maxPrlAmount, uint256 maxEthAmount) external {
        maxPrlAmount = bound(maxPrlAmount, 1, prl.balanceOf(users.alice.addr));
        maxEthAmount = bound(maxEthAmount, 1, (users.alice.addr).balance);

        uint256 alicePrlBalanceBefore = prl.balanceOf(users.alice.addr);
        uint256 aliceEthBalanceBefore = (users.alice.addr).balance;

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            _signPermitData(users.alice.privateKey, address(sprl2), maxPrlAmount, address(prl));

        vm.expectEmit(address(sprl2));
        emit TimeLockPenaltyERC20.Deposited(users.alice.addr, exactBptAmount);
        sprl2.depositPRLAndEth{ value: maxEthAmount }(maxPrlAmount, exactBptAmount, deadline, v, r, s);
        assertEq(prl.balanceOf(users.alice.addr), alicePrlBalanceBefore - maxPrlAmount);
        assertEq((users.alice.addr).balance, aliceEthBalanceBefore - maxEthAmount);
        assertEq(sprl2.balanceOf(users.alice.addr), exactBptAmount);
    }

    function test_sPRL2_Deposit_RevertWhen_AuraDepositFailed(uint256 maxPrlAmount, uint256 maxEthAmount) external {
        maxPrlAmount = bound(maxPrlAmount, 1, prl.balanceOf(users.alice.addr));
        maxEthAmount = bound(maxEthAmount, 1, (users.alice.addr).balance);

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            _signPermitData(users.alice.privateKey, address(sprl2), maxPrlAmount, address(prl));
        vm.mockCall(
            address(auraBoosterLiteMock),
            abi.encodeWithSelector(IAuraBoosterLite.deposit.selector, sprl2.AURA_POOL_PID(), exactBptAmount, true),
            abi.encode(false)
        );
        vm.expectRevert(sPRL2.AuraDepositFailed.selector);
        sprl2.depositPRLAndEth{ value: maxEthAmount }(maxPrlAmount, exactBptAmount, deadline, v, r, s);
    }

    function test_sPRL2_Deposit_ReturnRemainingTokens_ETH(uint256 maxPrlAmount, uint256 maxEthAmount) external {
        maxPrlAmount = bound(maxPrlAmount, 1, prl.balanceOf(users.alice.addr));
        maxEthAmount = bound(maxEthAmount, 1, (users.alice.addr).balance);

        uint256 alicePrlBalanceBefore = prl.balanceOf(users.alice.addr);
        uint256 aliceEthBalanceBefore = (users.alice.addr).balance;

        /// @dev add extra tokens to the contract
        prl.mint(address(sprl2), maxPrlAmount);
        weth.mint(address(sprl2), maxEthAmount);

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            _signPermitData(users.alice.privateKey, address(sprl2), maxPrlAmount, address(prl));

        sprl2.depositPRLAndEth{ value: maxEthAmount }(maxPrlAmount, exactBptAmount, deadline, v, r, s);
        assertEq(prl.balanceOf(users.alice.addr), alicePrlBalanceBefore);
        assertEq((users.alice.addr).balance, aliceEthBalanceBefore);
        assertEq(sprl2.balanceOf(users.alice.addr), exactBptAmount);
        assertEq(prl.balanceOf(address(sprl2)), 0);
        assertEq(weth.balanceOf(address(sprl2)), 0);
    }

    function test_sPRL2_Deposit_ReturnRemainingTokens_WETH(uint256 maxPrlAmount, uint256 maxWethAmount) external {
        maxPrlAmount = bound(maxPrlAmount, 1, prl.balanceOf(users.alice.addr));
        maxWethAmount = bound(maxWethAmount, 1, weth.balanceOf(users.alice.addr));

        uint256 alicePrlBalanceBefore = prl.balanceOf(users.alice.addr);
        uint256 aliceWethBalanceBefore = weth.balanceOf(users.alice.addr);

        /// @dev add extra tokens to the contract
        prl.mint(address(sprl2), maxPrlAmount);
        weth.mint(address(sprl2), maxWethAmount);

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            _signPermitData(users.alice.privateKey, address(sprl2), maxPrlAmount, address(prl));

        sprl2.depositPRLAndWeth(maxPrlAmount, maxWethAmount, exactBptAmount, deadline, v, r, s);
        assertEq(prl.balanceOf(users.alice.addr), alicePrlBalanceBefore);
        assertEq(weth.balanceOf(users.alice.addr), aliceWethBalanceBefore);
        assertEq(sprl2.balanceOf(users.alice.addr), exactBptAmount);
        assertEq(prl.balanceOf(address(sprl2)), 0);
        assertEq(weth.balanceOf(address(sprl2)), 0);
    }
}
