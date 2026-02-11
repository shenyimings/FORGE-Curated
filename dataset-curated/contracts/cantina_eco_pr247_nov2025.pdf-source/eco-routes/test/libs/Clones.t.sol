// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../BaseTest.sol";
import {Clones} from "../../contracts/vault/Clones.sol";
import {Proxy} from "../../contracts/vault/Proxy.sol";
import {Vault} from "../../contracts/vault/Vault.sol";
import {TestERC20} from "../../contracts/test/TestERC20.sol";

/**
 * @title ClonesTest
 * @notice Comprehensive test suite for the Clones library
 * @dev Tests cover:
 *      - CREATE2 proxy deployment functionality
 *      - Address prediction accuracy and determinism
 *      - Proxy delegation behavior and storage isolation
 *      - Cross-platform prefix support (standard vs TRON)
 *      - Integration with various implementation contracts
 *      - Edge cases, gas usage, and security scenarios
 */

contract MockImplementation {
    uint256 public value;
    address public caller;

    function setValue(uint256 _value) external {
        value = _value;
        caller = msg.sender;
    }

    function getValue() external view returns (uint256) {
        return value;
    }

    function getCaller() external view returns (address) {
        return caller;
    }

    function revertWithMessage() external pure {
        revert("MockImplementation: test revert");
    }
}

contract ClonesTest is BaseTest {
    using Clones for address;

    MockImplementation public implementation;
    bytes32 public constant TEST_SALT = keccak256("test");
    bytes32 public constant DIFFERENT_SALT = keccak256("different");
    bytes1 public constant CREATE2_PREFIX = hex"ff";

    function setUp() public override {
        super.setUp();
        implementation = new MockImplementation();
    }

    function testCloneCreatesProxyWithCorrectImplementation() public {
        address clone = address(implementation).clone(TEST_SALT);

        // Verify proxy delegates calls correctly
        MockImplementation(clone).setValue(42);
        assertEq(MockImplementation(clone).getValue(), 42);
        assertEq(MockImplementation(clone).getCaller(), address(this));

        // Verify storage isolation between proxy and implementation
        assertEq(implementation.getValue(), 0);
    }

    function testCloneCreatesDifferentAddressesWithDifferentSalts() public {
        address clone1 = address(implementation).clone(TEST_SALT);
        address clone2 = address(implementation).clone(DIFFERENT_SALT);

        assertNotEq(clone1, clone2);
        assertNotEq(clone1, address(0));
        assertNotEq(clone2, address(0));
    }

    function testCloneWithSameSaltCreatesSameAddress() public {
        address clone1 = Clones.clone(address(implementation), TEST_SALT);

        // Second deployment with same salt should revert due to CREATE2 collision
        vm.expectRevert();
        Clones.clone(address(implementation), TEST_SALT);

        // But the first clone should still be valid
        assertNotEq(clone1, address(0));
        MockImplementation(clone1).setValue(123);
        assertEq(MockImplementation(clone1).getValue(), 123);
    }

    function testPredictCalculatesCorrectAddress() public {
        address predicted = Clones.predict(
            address(implementation),
            TEST_SALT,
            CREATE2_PREFIX
        );
        address actual = Clones.clone(address(implementation), TEST_SALT);

        assertEq(predicted, actual);
    }

    function testPredictWithDifferentPrefixes() public {
        bytes1 tronPrefix = hex"41";
        bytes1 customPrefix = hex"77";

        address predictedStandard = Clones.predict(
            address(implementation),
            TEST_SALT,
            CREATE2_PREFIX
        );
        address predictedTron = Clones.predict(
            address(implementation),
            TEST_SALT,
            tronPrefix
        );
        address predictedCustom = Clones.predict(
            address(implementation),
            TEST_SALT,
            customPrefix
        );

        // Different prefixes should produce different addresses
        assertNotEq(predictedStandard, predictedTron);
        assertNotEq(predictedStandard, predictedCustom);
        assertNotEq(predictedTron, predictedCustom);

        // Standard prefix should match actual deployment
        address actual = Clones.clone(address(implementation), TEST_SALT);
        assertEq(predictedStandard, actual);

        // None of the predictions should be zero address
        assertNotEq(predictedStandard, address(0));
        assertNotEq(predictedTron, address(0));
        assertNotEq(predictedCustom, address(0));
    }

    function testPredictWithDifferentImplementations() public {
        MockImplementation implementation2 = new MockImplementation();

        address predicted1 = Clones.predict(
            address(implementation),
            TEST_SALT,
            CREATE2_PREFIX
        );
        address predicted2 = Clones.predict(
            address(implementation2),
            TEST_SALT,
            CREATE2_PREFIX
        );

        // Different implementations should produce different addresses for same salt
        assertNotEq(predicted1, predicted2);
    }

    function testCloneWithVaultImplementation() public {
        Vault vaultImpl = new Vault();

        address clone = Clones.clone(address(vaultImpl), TEST_SALT);
        address predicted = Clones.predict(
            address(vaultImpl),
            TEST_SALT,
            CREATE2_PREFIX
        );

        assertEq(clone, predicted);
    }

    function testProxyDelegateCallBehavior() public {
        address clone = Clones.clone(address(implementation), TEST_SALT);

        // Set value through proxy
        MockImplementation(clone).setValue(999);

        // Value should be stored in proxy's storage, not implementation's
        assertEq(MockImplementation(clone).getValue(), 999);
        assertEq(implementation.getValue(), 0); // Implementation unchanged

        // Caller should be recorded as this contract
        assertEq(MockImplementation(clone).getCaller(), address(this));
    }

    function testProxyHandlesRevertCorrectly() public {
        address clone = Clones.clone(address(implementation), TEST_SALT);

        vm.expectRevert("MockImplementation: test revert");
        MockImplementation(clone).revertWithMessage();
    }

    function testProxyReceiveEther() public {
        address clone = Clones.clone(address(implementation), TEST_SALT);

        uint256 sendAmount = 1 ether;

        // Send ether to proxy using call (triggers receive function)
        (bool success, ) = clone.call{value: sendAmount}("");
        assertTrue(success);

        // Verify proxy received the ether
        assertEq(clone.balance, sendAmount);
    }

    function testProxyFallbackWithCalldata() public {
        address clone = Clones.clone(address(implementation), TEST_SALT);

        // Encode function call
        bytes memory data = abi.encodeWithSelector(
            MockImplementation.setValue.selector,
            777
        );

        // Call through fallback
        (bool success, bytes memory returnData) = clone.call(data);
        assertTrue(success);
        assertEq(returnData.length, 0); // setValue returns void

        // Verify the call worked
        assertEq(MockImplementation(clone).getValue(), 777);
    }

    function testMultipleProxiesIndependentStorage() public {
        address clone1 = Clones.clone(address(implementation), TEST_SALT);
        address clone2 = Clones.clone(address(implementation), DIFFERENT_SALT);

        // Set different values in each proxy
        MockImplementation(clone1).setValue(100);
        MockImplementation(clone2).setValue(200);

        // Each proxy should have its own storage
        assertEq(MockImplementation(clone1).getValue(), 100);
        assertEq(MockImplementation(clone2).getValue(), 200);

        // Implementation should be unchanged
        assertEq(implementation.getValue(), 0);
    }

    function testPredictWithZeroSalt() public {
        bytes32 zeroSalt = bytes32(0);

        address predicted = Clones.predict(
            address(implementation),
            zeroSalt,
            CREATE2_PREFIX
        );
        address actual = Clones.clone(address(implementation), zeroSalt);

        assertEq(predicted, actual);
        assertNotEq(actual, address(0));
    }

    function testPredictWithMaxSalt() public {
        bytes32 maxSalt = bytes32(type(uint256).max);

        address predicted = Clones.predict(
            address(implementation),
            maxSalt,
            CREATE2_PREFIX
        );
        address actual = Clones.clone(address(implementation), maxSalt);

        assertEq(predicted, actual);
        assertNotEq(actual, address(0));
    }

    function testCloneGasUsage() public {
        uint256 gasBefore = gasleft();
        Clones.clone(address(implementation), TEST_SALT);
        uint256 gasUsed = gasBefore - gasleft();

        // Should be reasonably efficient (CREATE2 + proxy deployment)
        // Exact gas usage may vary but should be under reasonable limits
        assertLt(gasUsed, 200000);
    }

    function testPredictGasUsage() public view {
        uint256 gasBefore = gasleft();
        Clones.predict(address(implementation), TEST_SALT, CREATE2_PREFIX);
        uint256 gasUsed = gasBefore - gasleft();

        // Prediction should be very cheap (just computation)
        assertLt(gasUsed, 10000);
    }

    function testPredictDeterministicAcrossBlocks() public {
        address predicted1 = Clones.predict(
            address(implementation),
            TEST_SALT,
            CREATE2_PREFIX
        );

        // Move to next block
        vm.roll(block.number + 1);

        address predicted2 = Clones.predict(
            address(implementation),
            TEST_SALT,
            CREATE2_PREFIX
        );

        // Prediction should be the same regardless of block
        assertEq(predicted1, predicted2);
    }

    function testPredictDeterministicAcrossTime() public {
        address predicted1 = Clones.predict(
            address(implementation),
            TEST_SALT,
            CREATE2_PREFIX
        );

        // Move time forward
        vm.warp(block.timestamp + 3600);

        address predicted2 = Clones.predict(
            address(implementation),
            TEST_SALT,
            CREATE2_PREFIX
        );

        // Prediction should be the same regardless of timestamp
        assertEq(predicted1, predicted2);
    }

    function testCloneWithRandomSalts() public {
        bytes32[] memory salts = new bytes32[](10);
        address[] memory clones = new address[](10);

        // Generate random salts and create clones
        for (uint i = 0; i < 10; i++) {
            salts[i] = keccak256(abi.encode(i, block.timestamp));
            clones[i] = Clones.clone(address(implementation), salts[i]);

            // Each clone should be unique
            assertNotEq(clones[i], address(0));

            // Verify prediction matches
            assertEq(
                clones[i],
                Clones.predict(
                    address(implementation),
                    salts[i],
                    CREATE2_PREFIX
                )
            );
        }

        // All clones should be different
        for (uint i = 0; i < 10; i++) {
            for (uint j = i + 1; j < 10; j++) {
                assertNotEq(clones[i], clones[j]);
            }
        }
    }

    function testProxyReceiveViaTransfer() public {
        address clone = Clones.clone(address(implementation), TEST_SALT);

        uint256 sendAmount = 0.5 ether;

        // Send ether using transfer (also triggers receive function)
        payable(clone).transfer(sendAmount);
        assertEq(clone.balance, sendAmount);
    }
}
