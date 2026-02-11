// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {IMorphoLendingAdapter} from "src/interfaces/IMorphoLendingAdapter.sol";
import {IMorphoLendingAdapterFactory} from "src/interfaces/IMorphoLendingAdapterFactory.sol";
import {MorphoLendingAdapterFactoryTest} from "./MorphoLendingAdapterFactory.t.sol";

contract MorphoLendingAdapterFactoryComputeAddressTest is MorphoLendingAdapterFactoryTest {
    function testFuzz_computeAddress_MatchesDeployAddress(address sender, address authorizedCreator, bytes32 baseSalt)
        public
    {
        address computedAddress = factory.computeAddress(sender, baseSalt);

        vm.prank(sender);
        IMorphoLendingAdapter lendingAdapter = factory.deployAdapter(defaultMarketId, authorizedCreator, baseSalt);

        assertEq(address(lendingAdapter), computedAddress);
    }

    function test_computeAddress_SameSaltDifferentSender(address senderA, address senderB, bytes32 baseSalt)
        public
        view
    {
        vm.assume(senderA != senderB);

        address computedAddressA = factory.computeAddress(senderA, baseSalt);
        address computedAddressB = factory.computeAddress(senderB, baseSalt);
        assertNotEq(computedAddressA, computedAddressB);
    }

    function test_computeAddress_SameSenderDifferentSalt(address sender, bytes32 baseSaltA, bytes32 baseSaltB)
        public
        view
    {
        vm.assume(baseSaltA != baseSaltB);

        address computedAddressA = factory.computeAddress(sender, baseSaltA);
        address computedAddressB = factory.computeAddress(sender, baseSaltB);
        assertNotEq(computedAddressA, computedAddressB);
    }
}
