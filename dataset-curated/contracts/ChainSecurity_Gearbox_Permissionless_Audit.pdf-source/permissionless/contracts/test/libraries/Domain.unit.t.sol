// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Domain} from "../../libraries/Domain.sol";

contract DomainUnitTest is Test {
    /// @notice Test extracting domain from string with domain separator
    function test_Domain_01_extracts_domain_with_separator() public pure {
        string memory input = "test::name";
        string memory domain = Domain.extractDomain(input);
        assertEq(domain, "test");
    }

    /// @notice Test extracting domain from string without domain separator
    function test_Domain_02_extracts_full_domain_without_separator() public pure {
        string memory input = "test";
        string memory domain = Domain.extractDomain(input);
        assertEq(domain, "test");
    }

    /// @notice Test extracting domain from empty string
    function test_Domain_03_extracts_empty_domain_from_empty_string() public pure {
        string memory input = "";
        string memory domain = Domain.extractDomain(input);
        assertEq(domain, "");
    }

    /// @notice Test extracting domain with multiple separators
    function test_Domain_04_extracts_first_domain_with_multiple_separators() public pure {
        string memory input = "test::sub::name";
        string memory domain = Domain.extractDomain(input);
        assertEq(domain, "test");
    }
}
