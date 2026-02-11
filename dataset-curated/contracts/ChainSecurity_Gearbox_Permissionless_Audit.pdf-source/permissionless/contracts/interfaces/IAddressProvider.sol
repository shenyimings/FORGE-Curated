// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IAddressProvider as IAddressProviderBase} from
    "@gearbox-protocol/core-v3/contracts/interfaces/base/IAddressProvider.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {IImmutableOwnableTrait} from "./base/IImmutableOwnableTrait.sol";

struct ContractValue {
    string key;
    address value;
    uint256 version;
}

/// @title Address provider interface
interface IAddressProvider is IAddressProviderBase, IVersion, IImmutableOwnableTrait {
    event SetAddress(string indexed key, uint256 indexed version, address indexed value);

    function addresses(string memory key, uint256 _version) external view returns (address);

    function getAddressOrRevert(string memory key, uint256 _version) external view returns (address);

    function getAllSavedContracts() external view returns (ContractValue[] memory);

    function getLatestVersion(string memory key) external view returns (uint256);

    function getLatestMinorVersion(string memory key, uint256 majorVersion) external view returns (uint256);

    function getLatestPatchVersion(string memory key, uint256 minorVersion) external view returns (uint256);

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function setAddress(string memory key, address addr, bool saveVersion) external;

    function setAddress(bytes32 key, address value, bool saveVersion) external;

    function setAddress(address addr, bool saveVersion) external;
}
