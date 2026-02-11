// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ReferralSigning} from "src/referral/ReferralSigning.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ReferralSigningTest is Test {
    ReferralSigning referral;

    address referrer;
    address referred;
    uint256 referrerKey;
    uint256 referredKey;

    function setUp() public {
        (referrer, referrerKey) = makeAddrAndKey("referrer");
        (referred, referredKey) = makeAddrAndKey("referred");

        referral = new ReferralSigning();
    }

    function sign(uint256 privKey, address user, address referrerAddr, uint256 nonce) internal pure returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(user, referrerAddr, nonce));
        bytes32 ethSigned = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, ethSigned);
        return abi.encodePacked(r, s, v);
    }

    function test_ClaimReferral_Works() public {
        uint256 nonce = referral.nonces(referred);
        bytes memory sig = sign(referredKey, referred, referrer, nonce);

        vm.prank(referred);
        referral.claimReferral(sig, referrer);

        assertEq(referral.referralsForUserRegistry(referred), referrer);
        assertTrue(referral.referredByRegistry(referrer, referred));
        assertTrue(referral.isUserReferred(referred));
        assertEq(referral.totalReferred(referrer), 1);
        assertEq(referral.nonces(referred), nonce + 1);
    }

    function test_ClaimReferral_RejectsSelfReferral() public {
        uint256 nonce = referral.nonces(referrer);
        bytes memory sig = sign(referrerKey, referrer, referrer, nonce);

        vm.prank(referrer);
        vm.expectRevert(abi.encodeWithSelector(ReferralSigning.ReferralSigning_SameUser.selector));
        referral.claimReferral(sig, referrer);
    }

    function test_ClaimReferral_RejectsDoubleClaim() public {
        uint256 nonce = referral.nonces(referred);
        bytes memory sig = sign(referredKey, referred, referrer, nonce);

        vm.prank(referred);
        referral.claimReferral(sig, referrer);

        vm.prank(referred);
        vm.expectRevert(abi.encodeWithSelector(ReferralSigning.ReferralSigning_UserAlreadyReferred.selector));
        referral.claimReferral(sig, referrer);
    }

    function test_ClaimReferral_InvalidSignature() public {
        uint256 nonce = referral.nonces(referred);
        // Signed by referrer instead of referred
        bytes memory sig = sign(referrerKey, referred, referrer, nonce);

        vm.prank(referred);
        vm.expectRevert(abi.encodeWithSelector(ReferralSigning.ReferralSigning_InvalidSignature.selector));
        referral.claimReferral(sig, referrer);
    }

    function test_ClaimReferral_RejectsContractReferrer() public {
        address contractReferrer = address(new DummyReferrer());
        uint256 nonce = referral.nonces(referred);
        bytes memory sig = sign(referredKey, referred, contractReferrer, nonce);

        vm.prank(referred);
        vm.expectRevert(abi.encodeWithSelector(ReferralSigning.ReferralSigning_ContractReferrerNotAllowed.selector));
        referral.claimReferral(sig, contractReferrer);
    }
}

contract DummyReferrer {
    // Just a dummy contract used to simulate contract referrer
}
