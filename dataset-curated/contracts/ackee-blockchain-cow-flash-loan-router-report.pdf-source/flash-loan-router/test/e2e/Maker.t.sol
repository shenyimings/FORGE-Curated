// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {ERC3156Borrower, IERC3156FlashLender} from "src/ERC3156Borrower.sol";
import {FlashLoanRouter, ICowSettlement, Loan} from "src/FlashLoanRouter.sol";

import {CowProtocol} from "./lib//CowProtocol.sol";
import {Constants} from "./lib/Constants.sol";
import {CowProtocolInteraction} from "./lib/CowProtocolInteraction.sol";
import {ForkedRpc} from "./lib/ForkedRpc.sol";
import {TokenBalanceAccumulator} from "./lib/TokenBalanceAccumulator.sol";

library MakerSetup {
    // https://docs.makerdao.com/smart-contract-modules/flash-mint-module
    IERC3156FlashLender internal constant FLASH_LOAN_CONTRACT =
        IERC3156FlashLender(0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA);

    function prepareBorrower(Vm vm, FlashLoanRouter router, address solver)
        internal
        returns (ERC3156Borrower borrower)
    {
        borrower = new ERC3156Borrower(router);

        // Call `approve` from the settlement contract so that DAI can be spent
        // on a settlement interaction on behalf of the borrower. With an
        // unlimited approval, this step only needs to be performed once per
        // loaned token.
        ICowSettlement.Interaction[] memory onlyApprove = new ICowSettlement.Interaction[](1);
        onlyApprove[0] = CowProtocolInteraction.borrowerApprove(
            borrower, Constants.DAI, address(Constants.SETTLEMENT_CONTRACT), type(uint256).max
        );
        vm.prank(solver);
        CowProtocol.emptySettleWithInteractions(onlyApprove);
    }
}

/// @dev Documentation for the ERC-3156-compatible flash loans by Maker can be
/// found at:
/// <https://docs.makerdao.com/smart-contract-modules/flash-mint-module>
contract E2eMaker is Test {
    using ForkedRpc for Vm;

    uint256 private constant MAINNET_FORK_BLOCK = 21765553;
    address private solver = makeAddr("E2eMaker: solver");

    ERC3156Borrower private borrower;
    TokenBalanceAccumulator private tokenBalanceAccumulator;
    FlashLoanRouter private router;

    function setUp() external {
        vm.forkEthereumMainnetAtBlock(MAINNET_FORK_BLOCK);
        tokenBalanceAccumulator = new TokenBalanceAccumulator();
        router = new FlashLoanRouter(Constants.SETTLEMENT_CONTRACT);

        vm.prank(Constants.AUTHENTICATOR_MANAGER);
        Constants.SOLVER_AUTHENTICATOR.addSolver(solver);
        vm.prank(Constants.AUTHENTICATOR_MANAGER);
        Constants.SOLVER_AUTHENTICATOR.addSolver(address(router));

        borrower = MakerSetup.prepareBorrower(vm, router, solver);
    }

    function test_settleWithFlashLoan() external {
        uint256 loanedAmount = 10_000 ether; // $10,000

        uint256 flashFee = MakerSetup.FLASH_LOAN_CONTRACT.flashFee(address(Constants.DAI), loanedAmount);
        // Flash loan fees are always zero in the Maker contract. We just need
        // to repay the borrowed collateral at the end.
        // <https://etherscan.io/address/0x07df2ad9878F8797B4055230bbAE5C808b8259b3#code#F1#L31>
        assertEq(flashFee, 0);

        uint256 settlementInitialDaiBalance = Constants.DAI.balanceOf(address(Constants.SETTLEMENT_CONTRACT));
        TokenBalanceAccumulator.Balance[] memory expectedBalances = new TokenBalanceAccumulator.Balance[](3);

        // Start preparing the settlement interactions.
        ICowSettlement.Interaction[] memory interactionsWithFlashLoan = new ICowSettlement.Interaction[](6);
        // First, we confirm that, at the point in time of the settlement, the
        // flash loan proceeds are indeed stored in the borrower.
        interactionsWithFlashLoan[0] =
            CowProtocolInteraction.pushBalanceToAccumulator(tokenBalanceAccumulator, Constants.DAI, address(borrower));
        expectedBalances[0] = TokenBalanceAccumulator.Balance(Constants.DAI, address(borrower), loanedAmount);
        // Second, we double check that the settlement balance hasn't changed.
        interactionsWithFlashLoan[1] = CowProtocolInteraction.pushBalanceToAccumulator(
            tokenBalanceAccumulator, Constants.DAI, address(Constants.SETTLEMENT_CONTRACT)
        );
        expectedBalances[1] = TokenBalanceAccumulator.Balance(
            Constants.DAI, address(Constants.SETTLEMENT_CONTRACT), settlementInitialDaiBalance
        );
        // Third, we make sure we can transfer these tokens. We do that by
        // trying a transfer into the settlement contract. The expectation is
        // that the borrower has already approved the settlement contract to
        // transfer its tokens out of it. In practice, the target of the
        // transfer is expected to be the user rather than the settlement
        // contract for gas efficiency.
        interactionsWithFlashLoan[2] = CowProtocolInteraction.transferFrom(
            Constants.DAI, address(borrower), address(Constants.SETTLEMENT_CONTRACT), loanedAmount
        );
        // Fourth, we check that the balance has indeed changed.
        interactionsWithFlashLoan[3] = CowProtocolInteraction.pushBalanceToAccumulator(
            tokenBalanceAccumulator, Constants.DAI, address(Constants.SETTLEMENT_CONTRACT)
        );
        expectedBalances[2] = TokenBalanceAccumulator.Balance(
            Constants.DAI, address(Constants.SETTLEMENT_CONTRACT), settlementInitialDaiBalance + loanedAmount
        );
        // Fifth, prepare the flash-loan repayment. Maker makes you repay the
        // loan by calling `transferFrom` under the assumption that the flash
        // loan borrower holds the funds and has approved its contract for
        // withdrawing funds.
        interactionsWithFlashLoan[4] = CowProtocolInteraction.borrowerApprove(
            borrower, Constants.DAI, address(MakerSetup.FLASH_LOAN_CONTRACT), loanedAmount
        );
        // Sixth and finally, send the funds to the borrower for repayment of
        // the loan.
        interactionsWithFlashLoan[5] = CowProtocolInteraction.transfer(Constants.DAI, address(borrower), loanedAmount);

        bytes memory settleCallData = CowProtocol.encodeEmptySettleWithInteractions(interactionsWithFlashLoan);

        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({
            amount: loanedAmount,
            borrower: borrower,
            lender: address(MakerSetup.FLASH_LOAN_CONTRACT),
            token: Constants.DAI
        });

        vm.prank(solver);
        router.flashLoanAndSettle(loans, settleCallData);

        tokenBalanceAccumulator.assertAccumulatorEq(vm, expectedBalances);
        assertEq(Constants.DAI.balanceOf(address(Constants.SETTLEMENT_CONTRACT)), settlementInitialDaiBalance);
    }
}
