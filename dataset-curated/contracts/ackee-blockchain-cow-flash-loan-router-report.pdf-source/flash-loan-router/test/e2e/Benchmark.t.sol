// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {FlashLoanRouter, Loan} from "src/FlashLoanRouter.sol";
import {IBorrower, ICowSettlement, IERC20} from "src/interface/IBorrower.sol";

import {AaveSetup} from "./Aave.t.sol";
import {MakerSetup} from "./Maker.t.sol";
import {Constants} from "./lib/Constants.sol";
import {CowProtocol} from "./lib/CowProtocol.sol";
import {CowProtocolInteraction} from "./lib/CowProtocolInteraction.sol";
import {ForkedRpc} from "./lib/ForkedRpc.sol";

uint256 constant MAINNET_FORK_BLOCK = 21765553;

// These values were computed based on the actual mainnet on-chain settlement
// transaction size on 2025-02-21.
uint256 constant SETTLEMENT_24H_MIN_SIZE = 1802;
uint256 constant SETTLEMENT_24H_MAX_SIZE = 45146;
uint256 constant SETTLEMENT_24H_AVERAGE_SIZE = 7598;
uint256 constant SETTLEMENT_24H_MEDIAN_SIZE = 4442;

abstract contract BenchmarkFixture is Test {
    using ForkedRpc for Vm;

    struct BenchLoan {
        IBorrower borrower;
        address lender;
        IERC20 token;
    }

    address internal solver = makeAddr("BenchmarkFixture: solver");
    FlashLoanRouter internal router;
    BenchLoan[] internal loans;
    string private benchGroup;

    constructor(string memory _benchGroup) {
        vm.forkEthereumMainnetAtBlock(MAINNET_FORK_BLOCK);
        router = new FlashLoanRouter(Constants.SETTLEMENT_CONTRACT);
        CowProtocol.addSolver(vm, solver);
        benchGroup = _benchGroup;
        populateLoanPlan();
    }

    /// @dev Each benchmark can execute its own setup in this call.
    /// It needs to build the array of loans that will be executed for the
    /// benchmark.
    function populateLoanPlan() internal virtual;

    function setUp() external {
        CowProtocol.addSolver(vm, solver);
        CowProtocol.addSolver(vm, address(router));
    }

    /// @param extraDataSize The size of the padding data that will be included
    /// in an interaction to pad the settlement. This can be approximately be
    /// the calldata size of a `settle` interaction without flash loans.
    /// @param name An identifier that will be used to give a name to the
    /// snapshot for this run.
    function flashLoanSettleWithExtraData(uint256 extraDataSize, string memory name) private {
        // Start preparing the settlement interactions.
        // The interaction plan is, for each loan:
        // - Transfer all tokens from the borrower to the settlement contract.
        //   In practice, the funds may be sent to a different address, but for
        //   the purpose of the test this should have an equivalent cost of
        //   modifying a fresh storage slot.
        // - Approve repayment. Under some minor trust assumptions on the
        //   lender, this could be done once per (token, lender) instead.
        // - Send back funds to the borrower, including fees, for loan
        //   repayment.
        // And finally, a call to the zero address with padding data. It does
        // nothing but increase the cost of executing the settlement in a way
        // that is compatible with the execution of other interactions with
        // on-chain liquidity to settle an order.
        // In practice, the gas cost of these extra interactions will be
        // different, but that's not something that should change with the flash
        // loans or without them.
        // As a first approximation, using the actual calldata size of a normal
        // call to `settle` seems reasonable, though it slightly overestimates
        // the actual cost (some of the calldata used in a settlement is due to
        // the ABI encoding of the transaction in a format compatible with a
        // `settle()` call, which has to be done regardless). However, we
        // consider the impact of this extra data overall small.

        ICowSettlement.Interaction[] memory interactionsWithFlashLoan =
            new ICowSettlement.Interaction[](3 * loans.length + 1);

        // We always loan just 1 wei so that we don't need to transfer funds
        // around.
        uint256 loanedAmount = 1;
        // We assume that the fees aren't larger than the traded amount.
        uint256 fees = loanedAmount;

        // Sanity check: we can pay back the loan with interests from the
        // buffers.
        for (uint256 i = 0; i < loans.length; i++) {
            uint256 settlementBalance = loans[i].token.balanceOf(address(Constants.SETTLEMENT_CONTRACT));
            assertGt(settlementBalance, fees, "Test sanity check failed: cannot repay loan from buffers");
        }

        // Keep track of the number of interactions populated so far.
        uint256 head = 0;

        for (uint256 i = 0; i < loans.length; i++) {
            interactionsWithFlashLoan[head++] = CowProtocolInteraction.transferFrom(
                loans[i].token, address(loans[i].borrower), address(Constants.SETTLEMENT_CONTRACT), loanedAmount
            );
        }

        for (uint256 i = 0; i < loans.length; i++) {
            interactionsWithFlashLoan[head++] = CowProtocolInteraction.borrowerApprove(
                loans[i].borrower, loans[i].token, loans[i].lender, loanedAmount + fees
            );
        }

        for (uint256 i = 0; i < loans.length; i++) {
            interactionsWithFlashLoan[head++] =
                CowProtocolInteraction.transfer(loans[i].token, address(loans[i].borrower), loanedAmount + fees);
        }

        interactionsWithFlashLoan[head++] =
            ICowSettlement.Interaction({target: address(0), value: 0, callData: new bytes(extraDataSize)});

        require(
            head == interactionsWithFlashLoan.length,
            "Test sanity check failed: the number of included interactions doesn't match the hardcoded interaction length"
        );

        bytes memory settleCallData = CowProtocol.encodeEmptySettleWithInteractions(interactionsWithFlashLoan);
        Loan.Data[] memory encodedLoans = encodeLoans(loanedAmount);

        vm.prank(solver);
        vm.startSnapshotGas(string.concat("E2eBenchmark", benchGroup), name);
        router.flashLoanAndSettle(encodedLoans, settleCallData);
        vm.stopSnapshotGas();
    }

    function encodeLoans(uint256 amount) private view returns (Loan.Data[] memory encodedLoans) {
        encodedLoans = new Loan.Data[](loans.length);
        for (uint256 i = 0; i < loans.length; i++) {
            encodedLoans[i] =
                Loan.Data({amount: amount, borrower: loans[i].borrower, lender: loans[i].lender, token: loans[i].token});
        }
    }

    function test_settleMin() external {
        flashLoanSettleWithExtraData(SETTLEMENT_24H_MIN_SIZE, "Min");
    }

    function test_settleMax() external {
        flashLoanSettleWithExtraData(SETTLEMENT_24H_MAX_SIZE, "Max");
    }

    function test_settleAverage() external {
        flashLoanSettleWithExtraData(SETTLEMENT_24H_AVERAGE_SIZE, "Average");
    }

    function test_settleMedian() external {
        flashLoanSettleWithExtraData(SETTLEMENT_24H_MEDIAN_SIZE, "Median");
    }
}

contract E2eBenchmarkNoFlashLoan is Test {
    using ForkedRpc for Vm;

    address private solver = makeAddr("E2eBenchmarkNoFlashLoan: solver");

    function setUp() external {
        vm.forkEthereumMainnetAtBlock(MAINNET_FORK_BLOCK);
        CowProtocol.addSolver(vm, solver);
    }

    function settleWithExtraData(uint256 extraDataSize, string memory name) private {
        ICowSettlement.Interaction[] memory intraInteractions = new ICowSettlement.Interaction[](1);
        intraInteractions[0] =
            ICowSettlement.Interaction({target: address(0), value: 0, callData: new bytes(extraDataSize)});

        (
            address[] memory noTokens,
            uint256[] memory noPrices,
            ICowSettlement.Trade[] memory noTrades,
            ICowSettlement.Interaction[][3] memory interactions
        ) = CowProtocol.emptySettleInputWithInteractions(intraInteractions);

        vm.prank(solver);
        vm.startSnapshotGas("E2eBenchmarkNoFlashLoans", name);
        Constants.SETTLEMENT_CONTRACT.settle(noTokens, noPrices, noTrades, interactions);
        vm.stopSnapshotGas();
    }

    function test_settleMin() external {
        settleWithExtraData(SETTLEMENT_24H_MIN_SIZE, "Min");
    }

    function test_settleMax() external {
        settleWithExtraData(SETTLEMENT_24H_MAX_SIZE, "Max");
    }

    function test_settleAverage() external {
        settleWithExtraData(SETTLEMENT_24H_AVERAGE_SIZE, "Average");
    }

    function test_settleMedian() external {
        settleWithExtraData(SETTLEMENT_24H_MEDIAN_SIZE, "Median");
    }
}

contract E2eBenchmarkMaker is BenchmarkFixture {
    constructor() BenchmarkFixture("Maker") {}

    function populateLoanPlan() internal override {
        loans.push(
            BenchLoan({
                borrower: MakerSetup.prepareBorrower(vm, router, solver),
                lender: address(MakerSetup.FLASH_LOAN_CONTRACT),
                token: Constants.DAI
            })
        );
    }
}

contract E2eBenchmarkAave is BenchmarkFixture {
    constructor() BenchmarkFixture("Aave") {}

    function populateLoanPlan() internal override {
        loans.push(
            BenchLoan({
                borrower: AaveSetup.prepareBorrower(vm, router, solver),
                lender: address(AaveSetup.WETH_POOL),
                token: Constants.WETH
            })
        );
    }
}

contract E2eBenchmarkAaveThenMaker is BenchmarkFixture {
    constructor() BenchmarkFixture("AaveThenMaker") {}

    function populateLoanPlan() internal override {
        loans.push(
            BenchLoan({
                borrower: AaveSetup.prepareBorrower(vm, router, solver),
                lender: address(AaveSetup.WETH_POOL),
                token: Constants.WETH
            })
        );
        loans.push(
            BenchLoan({
                borrower: MakerSetup.prepareBorrower(vm, router, solver),
                lender: address(MakerSetup.FLASH_LOAN_CONTRACT),
                token: Constants.DAI
            })
        );
    }
}
