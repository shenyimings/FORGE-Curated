// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script} from "forge-std/Script.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {mErc20Host} from "src/mToken/host/mErc20Host.sol";
import {Operator} from "src/Operator/Operator.sol";
import {Script, console} from "forge-std/Script.sol";

// 0x7c907cC2D7Dc9f2b8b815d4D0c9271Bcf609240D
contract SimpleInteractionsCheck is Script {
    uint256 amount;
    address USER;

    function run(address _market) public virtual {
        uint256 key = vm.envUint("PRIVATE_KEY");
        USER = vm.envAddress("PUBLIC_KEY");

        vm.startBroadcast(key);

        console.log("Testing for market %s", _market);

        mErc20Host market = mErc20Host(_market);
        address underlying = market.underlying();
        uint8 decimals = market.decimals();
        Operator operator = Operator(market.operator());

        console.log("Market has decimals:  %s", decimals);
        amount = 1 * (10 ** decimals) / 200;
        console.log("Supply amount:  %s", amount);

        uint256 balanceOfUser = IERC20(underlying).balanceOf(USER);

        if (!checkUserBalance(balanceOfUser, amount)) return;

        // ---- Supply
        if (!supplyToMarket(market, underlying, amount)) return;

        // ---- Borrow
        uint256 borrowAmount = amount / 5;
        if (!borrowFromMarket(market, operator, underlying, borrowAmount)) return;

        // ---- Repay
        if (!repayBorrowedAmount(market, underlying, borrowAmount)) return;

        // ---- Redeem
        if (!redeemFromMarket(market)) return;

        vm.stopBroadcast();
    }

    function checkUserBalance(uint256 balanceOfUser, uint256 factoredAmount) private pure returns (bool) {
        if (balanceOfUser < factoredAmount) {
            console.log("User doesn't have enough balance. Needed: %s, Available: %s", factoredAmount, balanceOfUser);
            return false;
        }
        return true;
    }

    function supplyToMarket(mErc20Host market, address underlying, uint256 factoredAmount) private returns (bool) {
        console.log("Approving underlying for supply %s", underlying);
        IERC20(underlying).approve(address(market), factoredAmount);

        console.log("Supplying to market");
        market.mint(factoredAmount, USER, factoredAmount);

        uint256 suppliedAmount = market.balanceOf(USER);
        console.log("Supply amount %s", suppliedAmount);
        // if (suppliedAmount != factoredAmount) {
        //     console.log("Supply operation failed. Expected: %s, Available: %s", factoredAmount, suppliedAmount);
        //     return false;
        // }

        return true;
    }

    function borrowFromMarket(mErc20Host market, Operator operator, address underlying, uint256 borrowAmount)
        private
        returns (bool)
    {
        uint256 borrowCap = operator.borrowCaps(address(market));
        console.log("Borrow cap for the market: %s", borrowCap);

        if (borrowAmount > borrowCap) {
            console.log("Borrow amount exceeds borrow cap. Amount: %s, Cap: %s", borrowAmount, borrowCap);
            return false;
        }

        uint256 cash = market.getCash();
        console.log("Market liquidity (cash): %s", cash);

        if (cash < borrowAmount) {
            console.log("Market does not have enough liquidity for the requested borrow.");
            return false;
        }

        console.log("Borrowing from market, amount: %s", borrowAmount);
        uint256 debtBalanceBefore = IERC20(underlying).balanceOf(USER);
        market.borrow(borrowAmount);
        uint256 debtBalanceAfter = IERC20(underlying).balanceOf(USER);
        uint256 debtBalance = debtBalanceAfter - debtBalanceBefore;

        if (debtBalance < borrowAmount) {
            console.log("Borrow operation failed. Expected: %s, Available: %s", borrowAmount, debtBalance);
            return false;
        }

        return true;
    }

    function repayBorrowedAmount(mErc20Host market, address underlying, uint256 borrowAmount) private returns (bool) {
        console.log("Approving underlying for repayment %s", underlying);
        IERC20(underlying).approve(address(market), borrowAmount);

        console.log("Repaying borrowed amount");
        market.repay(borrowAmount);

        uint256 remainingDebt = market.borrowBalanceCurrent(USER);
        if (remainingDebt != 0) {
            console.log("Repay operation failed. Remaining debt: %s", remainingDebt);
            return false;
        }

        return true;
    }

    function redeemFromMarket(mErc20Host market) private returns (bool) {
        uint256 suppliedAmount = market.balanceOf(USER);
        uint256 redeemAmount = suppliedAmount / 2;

        console.log("Redeeming from market, amount: %s", redeemAmount);
        market.redeem(redeemAmount);

        uint256 remainingSupply = market.balanceOf(USER);
        if (remainingSupply != suppliedAmount - redeemAmount) {
            console.log(
                "Redeem operation failed. Expected remaining supply: %s, Actual: %s",
                suppliedAmount - redeemAmount,
                remainingSupply
            );
            return false;
        }

        return true;
    }
}
