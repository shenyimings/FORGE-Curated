// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {BuilderCodes} from "builder-codes/BuilderCodes.sol";
import {Test} from "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";

/// @notice Helper library for easy publisher setup in tests
library PublisherSetupHelper {
    /// @notice Struct to hold publisher configuration
    struct PublisherConfig {
        string refCode;
        address owner;
        address payoutRecipient;
        string metadataUrl;
    }

    /// @notice Creates a default publisher configuration with optional overrides
    function createPublisherConfig(string memory refCode, address owner)
        internal
        pure
        returns (PublisherConfig memory)
    {
        return PublisherConfig({
            refCode: refCode,
            owner: owner,
            payoutRecipient: owner, // Default payout to owner
            metadataUrl: string(abi.encodePacked("https://publisher.com/", refCode))
        });
    }

    /// @notice Creates a publisher configuration with custom payout recipient
    function createPublisherConfig(string memory refCode, address owner, address payoutRecipient)
        internal
        pure
        returns (PublisherConfig memory)
    {
        return PublisherConfig({
            refCode: refCode,
            owner: owner,
            payoutRecipient: payoutRecipient,
            metadataUrl: string(abi.encodePacked("https://publisher.com/", refCode))
        });
    }

    /// @notice Creates a fully custom publisher configuration
    function createPublisherConfig(
        string memory refCode,
        address owner,
        address payoutRecipient,
        string memory metadataUrl
    ) internal pure returns (PublisherConfig memory) {
        return PublisherConfig({
            refCode: refCode, owner: owner, payoutRecipient: payoutRecipient, metadataUrl: metadataUrl
        });
    }
}

/// @notice Test contract with publisher setup utilities
abstract contract PublisherTestSetup is Test {
    using PublisherSetupHelper for *;

    /// @notice Generates a bytes32 code from a uint256 value, left-aligned with right padding
    /// @param value The value to generate a code from
    /// @return code The generated code with value left-aligned and padded with zeros on the right
    function generateCode(uint256 value) public pure returns (string memory code) {
        if (value == 0) return "0";
        vm.assume(value < 10 ** 32);

        bytes memory alphabet = "0123456789";

        uint256 tmp = value;
        uint256 length = 0;
        while (tmp > 0) {
            tmp = tmp / 10;
            length++;
        }

        tmp = value;
        bytes memory codeBytes = new bytes(length);
        for (uint256 i; i < length; i++) {
            uint256 digit = tmp % 10;
            codeBytes[i] = alphabet[digit];
            tmp = tmp / 10;
            if (tmp == 0) break;
        }

        return string(codeBytes);
    }

    /// @notice Sets up a publisher with minimal configuration
    /// @param registry The BuilderCodes to register with
    /// @param refCode The referral code for the publisher
    /// @param owner The owner address for the publisher
    /// @param signer The address that will sign the registration (must have REGISTER_ROLE)
    /// @return config The created publisher configuration
    function setupPublisher(BuilderCodes registry, string memory refCode, address owner, address signer)
        internal
        returns (PublisherSetupHelper.PublisherConfig memory config)
    {
        config = PublisherSetupHelper.createPublisherConfig(refCode, owner);
        _registerPublisher(registry, config, signer);
    }

    /// @notice Sets up a publisher with custom payout recipient
    function setupPublisher(
        BuilderCodes registry,
        string memory refCode,
        address owner,
        address payoutRecipient,
        address signer
    ) internal returns (PublisherSetupHelper.PublisherConfig memory config) {
        config = PublisherSetupHelper.createPublisherConfig(refCode, owner, payoutRecipient);
        _registerPublisher(registry, config, signer);
    }

    /// @notice Sets up a publisher with full custom configuration
    function setupPublisher(BuilderCodes registry, PublisherSetupHelper.PublisherConfig memory config, address signer)
        internal
    {
        _registerPublisher(registry, config, signer);
    }

    /// @notice Batch setup multiple publishers
    function setupPublishers(
        BuilderCodes registry,
        PublisherSetupHelper.PublisherConfig[] memory configs,
        address signer
    ) internal {
        for (uint256 i = 0; i < configs.length; i++) {
            _registerPublisher(registry, configs[i], signer);
        }
    }

    /// @notice Internal function to register a publisher
    function _registerPublisher(
        BuilderCodes registry,
        PublisherSetupHelper.PublisherConfig memory config,
        address signer
    ) private {
        vm.prank(signer);
        registry.register(config.refCode, config.owner, config.payoutRecipient);
    }

    /// @notice Creates test publisher addresses with labels
    function createLabeledPublisher(uint256 index) internal returns (address publisher, address payout) {
        publisher = makeAddr(string(abi.encodePacked("publisher", vm.toString(index))));
        payout = makeAddr(string(abi.encodePacked("payout", vm.toString(index))));
    }

    /// @notice Creates a batch of test publishers
    function createTestPublishers(uint256 count)
        internal
        returns (PublisherSetupHelper.PublisherConfig[] memory configs)
    {
        configs = new PublisherSetupHelper.PublisherConfig[](count);

        for (uint256 i = 0; i < count; i++) {
            (address publisher, address payout) = createLabeledPublisher(i);

            configs[i] = PublisherSetupHelper.createPublisherConfig(
                generateCode(uint16(i)),
                publisher,
                payout,
                string(abi.encodePacked("https://test.com/publisher", vm.toString(i)))
            );
        }
    }
}
