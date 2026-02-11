// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {FlashLoanRouter, Loan} from "src/FlashLoanRouter.sol";
import {IBorrower, ICowSettlement} from "src/interface/IBorrower.sol";

import {AaveSetup} from "./Aave.t.sol";
import {MakerSetup} from "./Maker.t.sol";
import {Constants} from "./lib/Constants.sol";
import {CowProtocol} from "./lib/CowProtocol.sol";
import {CowProtocolInteraction} from "./lib/CowProtocolInteraction.sol";
import {ForkedRpc} from "./lib/ForkedRpc.sol";
import {TokenBalanceAccumulator} from "./lib/TokenBalanceAccumulator.sol";

contract E2eAaveThenMaker is Test {
    using ForkedRpc for Vm;

    // This is the block immediately before a mainnet fee withdrawal:
    // <https://etherscan.io/tx/0x2ac75cbf67d74ae3ad736314acb9dba170922849d411cc7ccbe81e4e0cff157e>
    // It guarantees that there are some WETH available in the buffers to pay
    // for the flash loan.
    uint256 private constant MAINNET_FORK_BLOCK = 21883877;

    address private solver = makeAddr("E2eAaveThenMaker: solver");

    IBorrower private aaveBorrower;
    IBorrower private makerBorrower;
    TokenBalanceAccumulator private tokenBalanceAccumulator;
    FlashLoanRouter private router;

    function setUp() external {
        vm.forkEthereumMainnetAtBlock(MAINNET_FORK_BLOCK);
        tokenBalanceAccumulator = new TokenBalanceAccumulator();
        router = new FlashLoanRouter(Constants.SETTLEMENT_CONTRACT);
        CowProtocol.addSolver(vm, solver);
        CowProtocol.addSolver(vm, address(router));
        aaveBorrower = AaveSetup.prepareBorrower(vm, router, solver);
        makerBorrower = MakerSetup.prepareBorrower(vm, router, solver);
    }

    function test_settleWithFlashLoans() external {
        uint256 aaveLoanedAmount = 500 ether; // 500 WETH
        uint256 makerLoanedAmount = 10_000 ether; // $10,000

        uint256 makerAmountWithFee = makerLoanedAmount; // no fee
        // We cover the balance of the flash fee with the tokens that are
        // currently present in the settlement contract.
        uint256 relativeFlashFee = AaveSetup.WETH_POOL.FLASHLOAN_PREMIUM_TOTAL();
        uint256 aaveAmountWithFee = aaveLoanedAmount + aaveLoanedAmount * relativeFlashFee / 1000;

        uint256 settlementInitialWethBalance = Constants.WETH.balanceOf(address(Constants.SETTLEMENT_CONTRACT));
        uint256 settlementInitialDaiBalance = Constants.DAI.balanceOf(address(Constants.SETTLEMENT_CONTRACT));

        Loan.Data[] memory loans = new Loan.Data[](2);
        loans[0] = Loan.Data({
            amount: aaveLoanedAmount,
            borrower: aaveBorrower,
            lender: address(AaveSetup.WETH_POOL),
            token: Constants.WETH
        });
        loans[1] = Loan.Data({
            amount: makerLoanedAmount,
            borrower: makerBorrower,
            lender: address(MakerSetup.FLASH_LOAN_CONTRACT),
            token: Constants.DAI
        });

        // Start preparing the settlement interactions.
        ICowSettlement.Interaction[] memory interactionsWithFlashLoan = new ICowSettlement.Interaction[](10);
        TokenBalanceAccumulator.Balance[] memory expectedBalances = new TokenBalanceAccumulator.Balance[](4);

        // At the time of the settlement, each borrower holds the respective
        // token.
        interactionsWithFlashLoan[0] = CowProtocolInteraction.pushBalanceToAccumulator(
            tokenBalanceAccumulator, Constants.WETH, address(aaveBorrower)
        );
        interactionsWithFlashLoan[1] = CowProtocolInteraction.pushBalanceToAccumulator(
            tokenBalanceAccumulator, Constants.DAI, address(makerBorrower)
        );
        expectedBalances[0] = TokenBalanceAccumulator.Balance(Constants.WETH, address(aaveBorrower), aaveLoanedAmount);
        expectedBalances[1] = TokenBalanceAccumulator.Balance(Constants.DAI, address(makerBorrower), makerLoanedAmount);

        // Make sure we can transfer these tokens. We do that by trying a
        // transfer into the settlement contract. The expectation is
        // that the borrower has already approved the settlement contract to
        // transfer its tokens out of it.
        interactionsWithFlashLoan[2] = CowProtocolInteraction.transferFrom(
            Constants.WETH, address(aaveBorrower), address(Constants.SETTLEMENT_CONTRACT), aaveLoanedAmount
        );
        interactionsWithFlashLoan[3] = CowProtocolInteraction.transferFrom(
            Constants.DAI, address(makerBorrower), address(Constants.SETTLEMENT_CONTRACT), makerLoanedAmount
        );

        // Fourth, we check that the balance has indeed changed.
        interactionsWithFlashLoan[4] = CowProtocolInteraction.pushBalanceToAccumulator(
            tokenBalanceAccumulator, Constants.WETH, address(Constants.SETTLEMENT_CONTRACT)
        );
        interactionsWithFlashLoan[5] = CowProtocolInteraction.pushBalanceToAccumulator(
            tokenBalanceAccumulator, Constants.DAI, address(Constants.SETTLEMENT_CONTRACT)
        );
        expectedBalances[2] = TokenBalanceAccumulator.Balance(
            Constants.WETH, address(Constants.SETTLEMENT_CONTRACT), settlementInitialWethBalance + aaveLoanedAmount
        );
        expectedBalances[3] = TokenBalanceAccumulator.Balance(
            Constants.DAI, address(Constants.SETTLEMENT_CONTRACT), settlementInitialDaiBalance + makerLoanedAmount
        );

        // Prepare the borrowers for enabling repayment of the loan.
        interactionsWithFlashLoan[6] = CowProtocolInteraction.borrowerApprove(
            aaveBorrower, Constants.WETH, address(AaveSetup.WETH_POOL), aaveAmountWithFee
        );
        interactionsWithFlashLoan[7] = CowProtocolInteraction.borrowerApprove(
            makerBorrower, Constants.DAI, address(MakerSetup.FLASH_LOAN_CONTRACT), makerAmountWithFee
        );

        // Send back the funds to the solver borrower for repaying the loan.
        interactionsWithFlashLoan[8] =
            CowProtocolInteraction.transfer(Constants.WETH, address(aaveBorrower), aaveAmountWithFee);
        interactionsWithFlashLoan[9] =
            CowProtocolInteraction.transfer(Constants.DAI, address(makerBorrower), makerAmountWithFee);

        bytes memory settleCallData = CowProtocol.encodeEmptySettleWithInteractions(interactionsWithFlashLoan);

        vm.prank(solver);
        router.flashLoanAndSettle(loans, settleCallData);

        tokenBalanceAccumulator.assertAccumulatorEq(vm, expectedBalances);
    }
}
