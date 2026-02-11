// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../../Base.sol";
import { AddressGaugeVoter as GaugeVoter } from "@voting/AddressGaugeVoter.sol";
import { IAddressGaugeVote as IGaugeVoter } from "@voting/IAddressGaugeVoter.sol";

contract AutoCompoundBase is Base {
    address[] internal tokens;
    uint256[] internal amounts;

    address internal gaugeA = vm.createWallet("gaugeA").addr;
    address internal gaugeB = vm.createWallet("gaugeB").addr;

    function setUp() public override {
        super.setUp();

        tokens.push(tokenA);
        tokens.push(tokenB);

        amounts.push(50e18);
        amounts.push(15e18);

        vm.startPrank(address(dao));
        voter.createGauge(gaugeA, "metadata1");
        voter.createGauge(gaugeB, "metadata2");
        vm.stopPrank();
    }

    // Helper to create gauge votes
    function _createGaugeVotes() internal view returns (GaugeVoter.GaugeVote[] memory) {
        GaugeVoter.GaugeVote[] memory votes = new IGaugeVoter.GaugeVote[](2);
        votes[0] = IGaugeVoter.GaugeVote(50, gaugeA);
        votes[1] = IGaugeVoter.GaugeVote(40, gaugeB);
        return votes;
    }
}
