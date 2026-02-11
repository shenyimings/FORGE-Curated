// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

/* solhint-disable func-name-mixedcase  */
import "../minting/MintingBaseSetup.sol";
import "../../utils/WadRayMath.sol";

contract LevelYieldManagerTest is MintingBaseSetup {
    function setUp() public override {
        vm.startPrank(owner);
        super.setUp();
        vm.stopPrank();
    }

    // This test demonstrates the conversion USDC -> aUSDC -> waUSDC via aaveYieldManager
    function testDepositForYieldAndWithdraw() public {
        vm.startPrank(owner);
        uint amount = 10000000000000;
        USDCToken.mint(amount);
        USDCToken.approve(address(aaveYieldManager), amount);
        aaveYieldManager.depositForYield(address(USDCToken), 10);
        assertEq(
            waUSDC.balanceOf(address(owner)),
            10,
            "Incorrect waUSDC balance."
        );
        waUSDC.approve(address(aaveYieldManager), amount);
        aaveYieldManager.withdraw(address(USDCToken), 10);
        assertEq(
            waUSDC.balanceOf(address(owner)),
            0,
            "Incorrect waUSDC balance."
        );
        assertEq(
            USDCToken.balanceOf(address(owner)),
            amount,
            "Incorrect USDC balance."
        );
    }

    // test deposit and withdraw for token with 18 decimals
    function testDepositForYieldAndWithdrawMoreDecimals() public {
        vm.startPrank(owner);
        uint amount = 10000000000000;
        DAIToken.mint(amount);
        DAIToken.approve(address(aaveYieldManager), amount);
        aaveYieldManager.depositForYield(address(DAIToken), 10);
        assertEq(
            waDAIToken.balanceOf(address(owner)),
            10,
            "Incorrect waDAIToken balance."
        );
        waDAIToken.approve(address(aaveYieldManager), amount);
        aaveYieldManager.withdraw(address(DAIToken), 10);
        assertEq(
            waDAIToken.balanceOf(address(owner)),
            0,
            "Incorrect waDAIToken balance."
        );
        assertEq(
            DAIToken.balanceOf(address(owner)),
            amount,
            "Incorrect DAIToken balance."
        );
    }

    // test reserve manager deposit for yield and withdraw functions, which call
    // the corresponding functions in yield managers
    function testReserveManagerDepositForYield() public {
        vm.startPrank(owner);
        uint amount = 10000000000000;
        uint transferAmount = 99999999;
        USDCToken.mint(amount);
        USDCToken.transfer(address(eigenlayerReserveManager), transferAmount);
        eigenlayerReserveManager.approveSpender(
            address(waUSDC),
            address(aaveYieldManager),
            amount
        );

        vm.stopPrank();
        vm.startPrank(managerAgent);
        eigenlayerReserveManager.depositForYield(address(USDCToken), 10);
        assertEq(
            waUSDC.balanceOf(address(eigenlayerReserveManager)),
            10,
            "Incorrect waUSDC balance."
        );
        eigenlayerReserveManager.withdrawFromYieldManager(
            address(USDCToken),
            10
        );
        assertEq(
            waUSDC.balanceOf(address(eigenlayerReserveManager)),
            0,
            "Incorrect waUSDC balance."
        );
        assertEq(
            USDCToken.balanceOf(address(eigenlayerReserveManager)),
            transferAmount,
            "Incorrect USDC balance."
        );
    }

    // test that aave yield is accrued to ERC20Wrapper (in this case waUSDC)
    // test recover mechanism that allows someone with RECOVERER_ROLE to collect accrued interest
    function testAaveAccrueInterest(
        uint depositAmount,
        uint increaseAmountPercent
    ) public {
        vm.assume(100000 < depositAmount);
        vm.assume(depositAmount < 99999999);
        vm.assume(1 < increaseAmountPercent);
        vm.assume(increaseAmountPercent < 100);
        vm.startPrank(owner);
        uint amount = 10000000000000;
        uint transferAmount = 99999999;
        USDCToken.mint(amount);
        USDCToken.transfer(address(eigenlayerReserveManager), transferAmount);
        vm.stopPrank();

        vm.startPrank(managerAgent);
        eigenlayerReserveManager.depositForYield(
            address(USDCToken),
            depositAmount
        );
        vm.stopPrank();
        assertEq(
            waUSDC.balanceOf(address(eigenlayerReserveManager)),
            depositAmount,
            "Incorrect waUSDC balance."
        );
        assertApproxEqRel(
            aUSDC.balanceOf(address(waUSDC)),
            depositAmount,
            1e15
        );

        vm.startPrank(owner);

        // test rebase / accrue interest
        aUSDC.accrueInterest(increaseAmountPercent * 100);
        // here, we are basically doing depositAmount * (1e4 + increaseAmountPercent * 100) / 1e4,
        // except we pre-multiply by WadRayMath.RAY to ensure a high level of precision
        // rayMul does a multiplication and divides by 1 RAY to get us back to the expected result
        uint newTotalAmountQuotedInUnderlying = WadRayMath.rayMul(
            (depositAmount *
                WadRayMath.RAY *
                (1e4 + increaseAmountPercent * 100)) / 1e4,
            1
        );

        // Note: aToken balanceOf returns the balance quoted in the underlying asset, and not the aToken
        assertApproxEqRel(
            aUSDC.balanceOf(address(waUSDC)),
            newTotalAmountQuotedInUnderlying,
            1e15
        );
        waUSDC.grantRole(waUSDC.RECOVERER_ROLE(), bob);
        vm.stopPrank();
        vm.startPrank(bob);

        // recover accrued interest in the form of the underlying asset
        uint value = waUSDC.recoverUnderlying();
        assertEq(address(waUSDC.underlying()), address(aUSDC));

        // check using approx eq because aUSDC balanceOf does decimal arithmetic under the hood
        assertApproxEqRel(
            aUSDC.balanceOf(address(waUSDC)),
            depositAmount,
            1e16, // 1% = 1e16 because 100% = 1e18
            "Incorrect aUSDC balance."
        );
        // check using approx eq because aUSDC balanceOf does decimal arithmetic under the hood
        assertApproxEqRel(
            aUSDC.balanceOf(bob),
            newTotalAmountQuotedInUnderlying - aUSDC.balanceOf(address(waUSDC)),
            1e16, // 1% = 1e16 because 100% = 1e18
            "End Incorrect aUSDC balance."
        );
    }
}
