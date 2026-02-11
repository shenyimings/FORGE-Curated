// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BaseTest} from "../BaseTest.sol";
import {Whitelist} from "../../contracts/libs/Whitelist.sol";

contract TestWhitelist is Whitelist {
    constructor(bytes32[] memory addresses) Whitelist(addresses) {}

    function checkWhitelist(bytes32 addr) external view {
        validateWhitelisted(addr);
    }
}

contract WhitelistTest is BaseTest {
    TestWhitelist internal testWhitelist;
    TestWhitelist internal emptyWhitelist;

    bytes32[] internal whitelist;
    bytes32[] internal emptyList;

    function setUp() public override {
        super.setUp();

        // Setup whitelist
        whitelist.push(bytes32(uint256(uint160(creator))));
        whitelist.push(bytes32(uint256(uint160(claimant))));

        vm.startPrank(deployer);
        testWhitelist = new TestWhitelist(whitelist);
        emptyWhitelist = new TestWhitelist(emptyList);
        vm.stopPrank();
    }

    function testWhitelistBasicFunctionality() public view {
        bytes32 addr1 = bytes32(uint256(uint160(creator)));
        bytes32 addr2 = bytes32(uint256(uint160(claimant)));
        bytes32 addr3 = bytes32(uint256(uint160(otherPerson)));

        assertTrue(testWhitelist.isWhitelisted(addr1));
        assertTrue(testWhitelist.isWhitelisted(addr2));
        assertFalse(testWhitelist.isWhitelisted(addr3));
    }

    function testWhitelistSize() public view {
        assertEq(testWhitelist.getWhitelistSize(), 2);
        assertEq(emptyWhitelist.getWhitelistSize(), 0);
    }

    function testWhitelistGetWhitelist() public view {
        bytes32[] memory retrieved = testWhitelist.getWhitelist();
        assertEq(retrieved.length, 2);
        assertEq(retrieved[0], bytes32(uint256(uint160(creator))));
        assertEq(retrieved[1], bytes32(uint256(uint160(claimant))));
    }

    function testWhitelistValidation() public {
        bytes32 validAddr = bytes32(uint256(uint160(creator)));
        bytes32 invalidAddr = bytes32(uint256(uint160(otherPerson)));

        // Should not revert for valid address
        testWhitelist.checkWhitelist(validAddr);

        // Should revert for invalid address
        vm.expectRevert(
            abi.encodeWithSelector(
                Whitelist.AddressNotWhitelisted.selector,
                invalidAddr
            )
        );
        testWhitelist.checkWhitelist(invalidAddr);
    }

    function testWhitelistEmptyList() public {
        bytes32 anyAddr = bytes32(uint256(uint160(creator)));
        assertFalse(emptyWhitelist.isWhitelisted(anyAddr));

        vm.expectRevert(
            abi.encodeWithSelector(
                Whitelist.AddressNotWhitelisted.selector,
                anyAddr
            )
        );
        emptyWhitelist.checkWhitelist(anyAddr);
    }

    function testWhitelistGasConsumption() public view {
        bytes32 addr = bytes32(uint256(uint160(creator)));

        uint256 gasBefore = gasleft();
        testWhitelist.isWhitelisted(addr);
        uint256 gasUsed = gasBefore - gasleft();

        // Should be efficient
        assertTrue(gasUsed < 10000);
    }

    function testWhitelistZeroAddress() public view {
        assertFalse(testWhitelist.isWhitelisted(bytes32(0)));
        assertFalse(emptyWhitelist.isWhitelisted(bytes32(0)));
    }

    function testWhitelistMaxSize() public {
        bytes32[] memory maxAddresses = new bytes32[](20);
        for (uint256 i = 0; i < 20; i++) {
            maxAddresses[i] = keccak256(abi.encodePacked("addr", i));
        }

        TestWhitelist maxWhitelist = new TestWhitelist(maxAddresses);
        assertEq(maxWhitelist.getWhitelistSize(), 20);

        // Test all addresses are whitelisted
        for (uint256 i = 0; i < 20; i++) {
            assertTrue(maxWhitelist.isWhitelisted(maxAddresses[i]));
        }
    }

    function testWhitelistTooManyAddresses() public {
        bytes32[] memory tooManyAddresses = new bytes32[](21);
        for (uint256 i = 0; i < 21; i++) {
            tooManyAddresses[i] = keccak256(abi.encodePacked("addr", i));
        }

        vm.expectRevert();
        new TestWhitelist(tooManyAddresses);
    }
}
