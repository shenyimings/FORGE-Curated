// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { MultiSig } from "../../contracts/MultiSig.sol";

contract MultiSigTest is MultiSig, Test {
    constructor() MultiSig(_getSigners(), 2) {}

    function _getSigners() internal pure returns (address[] memory) {
        address[] memory signers = new address[](2);
        signers[0] = vm.addr(2);
        signers[1] = vm.addr(3);
        return signers;
    }

    function test_getSigners() public view {
        address[] memory signers = this.getSigners();
        assertEq(signers[0], vm.addr(2));
        assertEq(signers[1], vm.addr(3));
        assertEq(signers.length, 2);
    }

    function test_isSigner() public view {
        assertEq(isSigner(vm.addr(2)), true);
        assertEq(isSigner(vm.addr(3)), true);
        assertEq(isSigner(vm.addr(4)), false);
    }

    function test_setSigner() public {
        // only two signers
        assertEq(totalSigners(), 2);

        // add a new signer
        address newSigner = vm.addr(4);
        this.exposeAddSigner(newSigner);
        assertEq(isSigner(vm.addr(4)), true);
        assertEq(totalSigners(), 3);

        // can't add address(0) as a signer
        vm.expectRevert(abi.encodeWithSelector(InvalidSigner.selector));
        this.exposeAddSigner(address(0));
        assertEq(totalSigners(), 3);

        // can't add a signer twice
        vm.expectRevert(abi.encodeWithSelector(SignerAlreadyAdded.selector, newSigner));
        this.exposeAddSigner(newSigner);
        assertEq(totalSigners(), 3);

        // remove a signer
        this.exposeRemoveSigner(newSigner);
        assertEq(totalSigners(), 2);

        // can't remove a signer that is not in the committee
        vm.expectRevert(abi.encodeWithSelector(SignerNotFound.selector, newSigner));
        this.exposeRemoveSigner(newSigner);
        assertEq(totalSigners(), 2);

        // signer size must be >= threshold after removing a signer
        vm.expectRevert(abi.encodeWithSelector(TotalSignersLessThanThreshold.selector, uint64(1), uint64(2)));
        this.exposeRemoveSigner(vm.addr(3));

        // add the signer back
        vm.expectEmit();
        emit SignerSet(newSigner, true);
        this.setSigner(newSigner, true);
        assertEq(isSigner(newSigner), true);

        // remove the new signer
        vm.expectEmit();
        emit SignerSet(newSigner, false);
        this.setSigner(newSigner, false);

        // fail to set by non-self
        vm.expectRevert(abi.encodeWithSelector(OnlySelfCall.selector));
        vm.prank(address(1));
        this.setSigner(newSigner, true);
    }

    function test_setThreshold() public {
        assertEq(threshold, 2);

        // cant set threshold to 0
        vm.expectRevert(ZeroThreshold.selector);
        this.exposeSetThreshold(0);

        // cant set threshold to more than signer size
        vm.expectRevert(abi.encodeWithSelector(TotalSignersLessThanThreshold.selector, uint64(2), uint64(3)));
        this.exposeSetThreshold(3);

        // set threshold to 1
        this.exposeSetThreshold(1);
        assertEq(threshold, 1);

        // set threshold to 2
        this.exposeSetThreshold(2);
        assertEq(threshold, 2);

        // set threshold to 1 again
        uint256 newThreshold = 1;
        vm.expectEmit();
        emit ThresholdSet(newThreshold);
        this.setThreshold(newThreshold);
        assertEq(threshold, newThreshold);

        // fail to set by non-self
        vm.expectRevert();
        vm.prank(address(1));
        this.setThreshold(newThreshold);
    }

    function test_verifySignatures() public {
        bytes32 hash = keccak256(bytes("message"));

        bytes memory sig1 = _generateSignature(2, hash); // sign with private key 2
        bytes memory sig2 = _generateSignature(3, hash); // sign with private key 3
        bytes memory invalidSig = _generateSignature(4, hash); // sign with private key 4

        // if only one signature is provided, it should fail for invalid size
        vm.expectRevert(abi.encodeWithSelector(SignatureError.selector));
        this.verifySignatures(hash, sig1);

        // if duplicate/unsorted signatures are provided, it should fail
        vm.expectRevert(abi.encodeWithSelector(UnsortedSigners.selector));
        bytes memory duplicateSignatures = bytes.concat(sig1, sig1);
        this.verifySignatures(hash, duplicateSignatures);

        // if signatures are not from signers, it should fail
        vm.expectRevert(abi.encodeWithSelector(SignerNotFound.selector, vm.addr(4)));
        bytes memory signaturesNotFromSigners = bytes.concat(invalidSig, sig1);
        this.verifySignatures(hash, signaturesNotFromSigners);

        // passes
        bytes memory signatures = bytes.concat(sig1, sig2);
        this.verifySignatures(hash, signatures);
    }

    function _generateSignature(uint256 _privateKey, bytes32 _digest) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, _digest);
        signature = abi.encodePacked(r, s, v);
    }

    // --- expose internal functions for testing ---

    function exposeAddSigner(address _signer) public {
        _addSigner(_signer);
    }

    function exposeRemoveSigner(address _signer) public {
        _removeSigner(_signer);
    }

    function exposeSetThreshold(uint256 _threshold) public {
        _setThreshold(_threshold);
    }
}
