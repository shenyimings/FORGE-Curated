// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {BatchSubmitter_Unit_Shared} from "../shared/BatchSubmitter_Unit_Shared.t.sol";
import {BatchSubmitter} from "src/mToken/BatchSubmitter.sol";
import {ImTokenGateway} from "src/interfaces/ImTokenGateway.sol";
import {ImErc20Host} from "src/interfaces/ImErc20Host.sol";

contract BatchSubmitter_methods is BatchSubmitter_Unit_Shared {
    bytes[] internal journals;
    uint256[] internal amounts;
    address[] internal mTokens;
    bytes4[] internal selectors;
    address[] internal receivers;
    bytes32[] internal initHashes;

    // Define selectors from interfaces
    bytes4 internal constant OUT_HERE_SELECTOR = ImTokenGateway.outHere.selector;
    bytes4 internal constant MINT_SELECTOR = ImErc20Host.mintExternal.selector;
    bytes4 internal constant REPAY_SELECTOR = ImErc20Host.repayExternal.selector;

    modifier whenMarketIsListed(address mToken) {
        operator.supportMarket(mToken);
        _;
    }

    function setUp() public virtual override {
        super.setUp();

        address[] memory senders = new address[](2);
        senders[0] = address(this);
        senders[1] = address(this);

        address[] memory markets = new address[](2);
        markets[0] = address(mWethExtension);
        markets[1] = address(mUsdcExtension);

        amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        mTokens = markets;

        selectors = new bytes4[](2);
        selectors[0] = OUT_HERE_SELECTOR;
        selectors[1] = OUT_HERE_SELECTOR;

        bytes memory encodedJournals = _createBatchJournals(
            senders,
            markets,
            amounts,
            TEST_SOURCE_CHAIN_ID,
            uint32(block.chainid),
            true // Set L1inclusion to true for tests
        );
        journals = abi.decode(encodedJournals, (bytes[]));

        // Initialize new state variables
        receivers = new address[](2);
        receivers[0] = address(this);
        receivers[1] = address(this);

        initHashes = new bytes32[](2);
        initHashes[0] = keccak256(journals[0]);
        initHashes[1] = keccak256(journals[1]);
    }

    modifier givenSenderDoesNotHaveProofForwarderRole() {
        _;
    }

    function test_RevertWhen_CallerIsNotProofForwarder() external givenSenderDoesNotHaveProofForwarderRole {
        bytes memory encodedJournals = abi.encode(journals);
        vm.expectRevert(BatchSubmitter.BatchSubmitter_CallerNotAllowed.selector);
        batchSubmitter.batchProcess(
            BatchSubmitter.BatchProcessMsg(
                receivers, encodedJournals, "", mTokens, amounts, amounts, selectors, initHashes, 0
            )
        );
    }

    modifier givenSenderHasProofForwarderRole() {
        roles.allowFor(address(this), roles.PROOF_FORWARDER(), true);
        _;
    }

    modifier givenJournalDataIsEmpty() {
        _;
    }

    function test_RevertWhen_JournalDataIsEmpty() external givenSenderHasProofForwarderRole givenJournalDataIsEmpty {
        vm.expectRevert(BatchSubmitter.BatchSubmitter_JournalNotValid.selector);

        receivers = new address[](1);
        receivers[0] = address(this);

        initHashes = new bytes32[](1);
        initHashes[0] = bytes32(0);

        batchSubmitter.batchProcess(
            BatchSubmitter.BatchProcessMsg(receivers, "", "", mTokens, amounts, amounts, selectors, initHashes, 0)
        );
    }

    function test_RevertWhen_InvalidSelector() external givenSenderHasProofForwarderRole {
        bytes4[] memory invalidSelectors = new bytes4[](1);
        invalidSelectors[0] = bytes4(0x12345678); // Invalid selector

        // Reset storage arrays to length 1
        mTokens = new address[](1);
        mTokens[0] = address(mWethExtension);

        amounts = new uint256[](1);
        amounts[0] = 1 ether;

        receivers = new address[](1);
        receivers[0] = address(this);

        bytes memory encodedJournals =
            _createBatchJournals(new address[](1), mTokens, amounts, TEST_SOURCE_CHAIN_ID, uint32(block.chainid), true);
        journals = abi.decode(encodedJournals, (bytes[]));

        initHashes = new bytes32[](1);
        initHashes[0] = keccak256(journals[0]);

        vm.expectRevert(BatchSubmitter.BatchSubmitter_InvalidSelector.selector);
        batchSubmitter.batchProcess(
            BatchSubmitter.BatchProcessMsg(
                receivers, encodedJournals, "", mTokens, amounts, amounts, invalidSelectors, initHashes, 0
            )
        );
    }

    modifier givenJournalDataIsValid() {
        _;
    }

    function test_WhenOutHereSucceeds(uint256 amount)
        external
        givenSenderHasProofForwarderRole
        givenJournalDataIsValid
        inRange(amount, SMALL, LARGE)
    {
        // Reset storage arrays to length 1
        mTokens = new address[](1);
        mTokens[0] = address(mWethExtension);

        amounts = new uint256[](1);
        amounts[0] = amount;

        selectors = new bytes4[](1);
        selectors[0] = OUT_HERE_SELECTOR;

        receivers = new address[](1);
        receivers[0] = address(this);

        bytes memory encodedJournals =
            _createBatchJournals(receivers, mTokens, amounts, TEST_SOURCE_CHAIN_ID, uint32(block.chainid), true);
        journals = abi.decode(encodedJournals, (bytes[]));

        initHashes = new bytes32[](1);
        initHashes[0] = keccak256(journals[0]);

        // Fund the gateway
        _getTokens(weth, address(mWethExtension), amount);

        // Record balances before
        uint256 balanceBefore = weth.balanceOf(address(this));
        uint256 gatewayBalanceBefore = weth.balanceOf(address(mWethExtension));

        batchSubmitter.batchProcess(
            BatchSubmitter.BatchProcessMsg(
                receivers, encodedJournals, "0x123", mTokens, amounts, amounts, selectors, initHashes, 0
            )
        );

        // Check balances after
        uint256 balanceAfter = weth.balanceOf(address(this));
        uint256 gatewayBalanceAfter = weth.balanceOf(address(mWethExtension));

        // Verify balances changed correctly
        assertEq(balanceAfter - balanceBefore, amount);
        assertEq(gatewayBalanceBefore - gatewayBalanceAfter, amount);
    }

    function test_WhenOutHereFails() external givenSenderHasProofForwarderRole givenJournalDataIsValid {
        // Reset storage arrays to length 1
        mTokens = new address[](1);
        mTokens[0] = address(mWethExtension);

        amounts = new uint256[](1);
        amounts[0] = 1 ether;

        selectors = new bytes4[](1);
        selectors[0] = OUT_HERE_SELECTOR;

        receivers = new address[](1);
        receivers[0] = address(this);

        address[] memory senders = new address[](1);
        senders[0] = address(this);

        address[] memory markets = new address[](1);
        markets[0] = address(0); // Invalid market address

        bytes memory encodedJournals =
            _createBatchJournals(senders, markets, amounts, TEST_SOURCE_CHAIN_ID, uint32(block.chainid), true);
        journals = abi.decode(encodedJournals, (bytes[]));

        initHashes = new bytes32[](1);
        initHashes[0] = keccak256(journals[0]);

        vm.expectEmit(true, true, true, true);
        emit BatchSubmitter.BatchProcessFailed(
            initHashes[0],
            receivers[0],
            mTokens[0],
            amounts[0],
            amounts[0],
            selectors[0],
            abi.encodePacked(ImTokenGateway.mTokenGateway_AddressNotValid.selector)
        );

        batchSubmitter.batchProcess(
            BatchSubmitter.BatchProcessMsg(
                receivers, encodedJournals, "", mTokens, amounts, amounts, selectors, initHashes, 0
            )
        );
    }

    function test_WhenMintSucceeds(uint256 amount)
        external
        givenSenderHasProofForwarderRole
        givenJournalDataIsValid
        inRange(amount, SMALL, LARGE)
    {
        // Reset storage arrays to length 1
        mTokens = new address[](1);
        mTokens[0] = address(mWethHost);

        amounts = new uint256[](1);
        amounts[0] = amount;

        selectors = new bytes4[](1);
        selectors[0] = MINT_SELECTOR;

        receivers = new address[](1);
        receivers[0] = address(this);

        address[] memory senders = new address[](1);
        senders[0] = address(this);

        bytes memory encodedJournals =
            _createBatchJournals(senders, mTokens, amounts, TEST_SOURCE_CHAIN_ID, uint32(block.chainid), true);
        journals = abi.decode(encodedJournals, (bytes[]));

        initHashes = new bytes32[](1);
        initHashes[0] = keccak256(journals[0]);

        // Record balances before
        uint256 balanceBefore = mWethHost.balanceOf(address(this));
        uint256 totalSupplyBefore = mWethHost.totalSupply();

        batchSubmitter.batchProcess(
            BatchSubmitter.BatchProcessMsg(
                receivers, encodedJournals, "0x123", mTokens, amounts, amounts, selectors, initHashes, 0
            )
        );

        // Check balances after
        uint256 balanceAfter = mWethHost.balanceOf(address(this));
        uint256 totalSupplyAfter = mWethHost.totalSupply();

        // Verify balances changed correctly
        assertGt(balanceAfter, balanceBefore);
        assertGt(totalSupplyAfter, totalSupplyBefore);
        assertEq(totalSupplyAfter - amount, totalSupplyBefore);
    }

    function test_WhenMintFails() external givenSenderHasProofForwarderRole givenJournalDataIsValid {
        // Reset storage arrays to length 1
        mTokens = new address[](1);
        mTokens[0] = address(mWethHost);

        amounts = new uint256[](1);
        amounts[0] = 1 ether;

        selectors = new bytes4[](1);
        selectors[0] = MINT_SELECTOR;

        receivers = new address[](1);
        receivers[0] = address(this);

        address[] memory senders = new address[](1);
        senders[0] = address(this);

        address[] memory markets = new address[](1);
        markets[0] = address(0); // Invalid market address

        bytes memory encodedJournals =
            _createBatchJournals(senders, markets, amounts, TEST_SOURCE_CHAIN_ID, uint32(block.chainid), true);
        journals = abi.decode(encodedJournals, (bytes[]));

        initHashes = new bytes32[](1);
        initHashes[0] = keccak256(journals[0]);

        vm.expectEmit(true, true, true, true);
        emit BatchSubmitter.BatchProcessFailed(
            initHashes[0],
            receivers[0],
            mTokens[0],
            amounts[0],
            amounts[0],
            selectors[0],
            abi.encodePacked(ImErc20Host.mErc20Host_AddressNotValid.selector)
        );

        batchSubmitter.batchProcess(
            BatchSubmitter.BatchProcessMsg(
                receivers, encodedJournals, "", mTokens, amounts, amounts, selectors, initHashes, 0
            )
        );
    }

    function test_WhenRepayFails() external givenSenderHasProofForwarderRole givenJournalDataIsValid {
        // Reset storage arrays to length 1
        mTokens = new address[](1);
        mTokens[0] = address(mWethHost);

        amounts = new uint256[](1);
        amounts[0] = 1 ether;

        selectors = new bytes4[](1);
        selectors[0] = REPAY_SELECTOR;

        receivers = new address[](1);
        receivers[0] = address(this);

        address[] memory senders = new address[](1);
        senders[0] = address(this);

        address[] memory markets = new address[](1);
        markets[0] = address(0); // Invalid market address

        bytes memory encodedJournals =
            _createBatchJournals(senders, markets, amounts, TEST_SOURCE_CHAIN_ID, uint32(block.chainid), true);
        journals = abi.decode(encodedJournals, (bytes[]));

        initHashes = new bytes32[](1);
        initHashes[0] = keccak256(journals[0]);

        vm.expectEmit(true, true, true, true);
        emit BatchSubmitter.BatchProcessFailed(
            initHashes[0],
            receivers[0],
            mTokens[0],
            amounts[0],
            amounts[0],
            selectors[0],
            abi.encodePacked(ImErc20Host.mErc20Host_AddressNotValid.selector)
        );

        batchSubmitter.batchProcess(
            BatchSubmitter.BatchProcessMsg(
                receivers, encodedJournals, "", mTokens, amounts, amounts, selectors, initHashes, 0
            )
        );
    }
}
