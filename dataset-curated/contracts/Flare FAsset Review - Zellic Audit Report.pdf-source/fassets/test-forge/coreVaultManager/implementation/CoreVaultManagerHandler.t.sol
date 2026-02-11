// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {CoreVaultManager} from "../../../contracts/coreVaultManager/implementation/CoreVaultManager.sol";
import {IPayment} from "@flarenetwork/flare-periphery-contracts/flare/IFdcVerification.sol";
import {IPaymentVerification} from "@flarenetwork/flare-periphery-contracts/flare/IPaymentVerification.sol";

contract CoreVaultManagerHandler is Test {
    CoreVaultManager public coreVaultManager;
    address public fdcVerificationMock;
    address public governance;
    address public assetManager;
    bytes32 public chainId;
    string public coreVaultAddress;
    bytes32 public coreVaultAddressHash;
    string[] public allowedDestinations;
    uint128 public availableFunds; // ghost variable to available funds
    bytes32[] private preimageHashes;
    uint128 public setEscrowsFinishedAmount;

    constructor(
        CoreVaultManager _coreVaultManager,
        address _fdcVerificationMock,
        address _governance,
        address _assetManager,
        bytes32 _chainId,
        string memory _coreVaultAddress
    ) {
        coreVaultManager = _coreVaultManager;
        fdcVerificationMock = _fdcVerificationMock;
        governance = _governance;
        assetManager = _assetManager;
        chainId = _chainId;
        coreVaultAddress = _coreVaultAddress;
        coreVaultAddressHash = keccak256(bytes(_coreVaultAddress));

        allowedDestinations.push("destination1");
        vm.prank(governance);
        coreVaultManager.addAllowedDestinationAddresses(allowedDestinations);

        address[] memory triggeringAccounts = new address[](1);
        triggeringAccounts[0] = address(this);
        vm.prank(governance);
        coreVaultManager.addTriggeringAccounts(triggeringAccounts);

        for (uint256 i = 0; i < 100; i++) {
            preimageHashes.push(keccak256(abi.encodePacked("preimage", i)));
        }
        vm.prank(governance);
        coreVaultManager.addPreimageHashes(preimageHashes);
    }

    function confirmPayment(uint64 _receivedAmount, bytes32 _transactionId) public {

        // Construct a valid IPayment.Proof
        IPayment.Proof memory proof;
        proof.data.responseBody.status = 0;
        proof.data.sourceId = chainId;
        proof.data.responseBody.receivingAddressHash = coreVaultAddressHash;
        proof.data.responseBody.receivedAmount = int256(uint256(_receivedAmount));
        proof.data.requestBody.transactionId = _transactionId;

        vm.mockCall(
            fdcVerificationMock,
            abi.encodeWithSelector(IPaymentVerification.verifyPayment.selector, proof),
            abi.encode(true)
        );

        uint128 availableBefore = coreVaultManager.availableFunds();
        uint128 increaseAmount = coreVaultManager.confirmedPayments(_transactionId) ? 0 : _receivedAmount;
        if (!coreVaultManager.confirmedPayments(_transactionId)) {
            availableFunds += _receivedAmount;
        }
        coreVaultManager.confirmPayment(proof);
        assertEq(availableBefore + increaseAmount, coreVaultManager.availableFunds());
    }

    function requestTransferFromCoreVault(
        uint256 _destIndex,
        bytes32 _paymentReference,
        uint64 _amount,
        bool _cancelable
    ) public {
        _destIndex = bound(_destIndex, 0, allowedDestinations.length - 1);
        _amount = uint64(bound(_amount, 1, type(uint64).max / 2));
        string memory destination = allowedDestinations[_destIndex];

        (, , , uint128 fee) = coreVaultManager.getSettings();
        uint256 totalRequestAmount = coreVaultManager.totalRequestAmountWithFee() + _amount + fee;
        if (totalRequestAmount * 2 > type(uint64).max) return;
        if (totalRequestAmount > coreVaultManager.availableFunds() + coreVaultManager.escrowedFunds()) {
            vm.warp(block.timestamp + 1);
            confirmPayment(uint64(totalRequestAmount * 2), keccak256(abi.encodePacked(block.timestamp)));
        }

        vm.prank(assetManager);
        coreVaultManager.requestTransferFromCoreVault(destination, _paymentReference, _amount, _cancelable);
    }

    function triggerInstructions() public {
        if (
            coreVaultManager.getCancelableTransferRequests().length == 0 &&
            coreVaultManager.getNonCancelableTransferRequests().length == 0
        ) {
            vm.warp(block.timestamp + 1);
            requestTransferFromCoreVault(0, keccak256(abi.encodePacked(block.timestamp)), 1000, true);
        }

        if (coreVaultManager.getUnusedPreimageHashes().length == 0) {
            uint256 len = preimageHashes.length;
            bytes32[] memory newHashes = new bytes32[](100);
            for (uint256 i = len; i < len + 100; i++) {
                bytes32 preimageHash = keccak256(abi.encodePacked("preimage", i));
                preimageHashes.push(preimageHash);
                newHashes[i - len] = preimageHash;
            }
            vm.prank(governance);
            coreVaultManager.addPreimageHashes(newHashes);
        }

        uint128 preAvailable = coreVaultManager.availableFunds();

        vm.prank(address(this));
        coreVaultManager.triggerInstructions();

        uint128 postAvailable = coreVaultManager.availableFunds();
        uint128 fundsMoved = preAvailable - postAvailable;
        availableFunds -= fundsMoved;
    }

    function setEscrowsFinished(uint64 _escrowIndex) public {
        uint256 numOfEscrows = coreVaultManager.getEscrowsCount();
        if (numOfEscrows == 0) {
            triggerInstructions();
            numOfEscrows = coreVaultManager.getEscrowsCount();
        }
        if (numOfEscrows == 0) return; // no escrows to finish
        _escrowIndex = uint64(bound(_escrowIndex, 0, numOfEscrows - 1));

        CoreVaultManager.Escrow memory escrow = coreVaultManager.getEscrowByIndex(_escrowIndex);

        if (block.timestamp < escrow.expiryTs) {
            vm.warp(escrow.expiryTs + 1);
        }
        if (escrow.finished) return;

        uint128 preAvailable = coreVaultManager.availableFunds();
        uint128 preEscrowFunds = coreVaultManager.escrowedFunds();
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = escrow.preimageHash;
        vm.prank(governance);
        coreVaultManager.setEscrowsFinished(hashes);

        uint128 postAvailable = coreVaultManager.availableFunds();
        uint128 postEscrowFunds = coreVaultManager.escrowedFunds();
        uint128 fundsAvailableDiff = preAvailable - postAvailable;
        uint128 fundsEscrowedDiff = preEscrowFunds - postEscrowFunds;
        // successful setEscrowsFinished call
        if (fundsAvailableDiff > 0) {
            setEscrowsFinishedAmount += fundsAvailableDiff;
            availableFunds -= fundsAvailableDiff;
        } else if (fundsEscrowedDiff > 0) {
            setEscrowsFinishedAmount += fundsEscrowedDiff;
        }
    }

    function getAvailableFunds() external view returns (uint128) {
        return availableFunds;
    }
}