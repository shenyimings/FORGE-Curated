// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {LibString} from "@solady/utils/LibString.sol";

import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IBytecodeRepository} from "../interfaces/IBytecodeRepository.sol";
import {IDeployerTrait} from "../interfaces/base/IDeployerTrait.sol";

import {AP_BYTECODE_REPOSITORY, NO_VERSION_CONTROL} from "../libraries/ContractLiterals.sol";

abstract contract DeployerTrait is IDeployerTrait {
    using LibString for string;
    using LibString for bytes32;

    /// @notice Address of the address provider
    address public immutable override addressProvider;

    /// @notice Address of the bytecode repository
    address public immutable override bytecodeRepository;

    constructor(address addressProvider_) {
        addressProvider = addressProvider_;
        bytecodeRepository = _getAddressOrRevert(AP_BYTECODE_REPOSITORY, NO_VERSION_CONTROL);
    }

    function _getAddressOrRevert(bytes32 key, uint256 version) internal view returns (address) {
        return IAddressProvider(addressProvider).getAddressOrRevert(key, version);
    }

    function _tryGetAddress(bytes32 key, uint256 version) internal view returns (address) {
        try IAddressProvider(addressProvider).getAddressOrRevert(key, version) returns (address result) {
            return result;
        } catch {
            return address(0);
        }
    }

    function _getContractType(bytes32 domain, bytes32 postfix) internal pure returns (bytes32) {
        if (postfix == 0) return domain;
        return string.concat(domain.fromSmallString(), "::", postfix.fromSmallString()).toSmallString();
    }

    function _deploy(bytes32 contractType, uint256 version, bytes memory constructorParams, bytes32 salt)
        internal
        returns (address)
    {
        return IBytecodeRepository(bytecodeRepository).deploy(contractType, version, constructorParams, salt);
    }

    function _computeAddress(
        bytes32 contractType,
        uint256 version,
        bytes memory constructorParams,
        bytes32 salt,
        address deployer
    ) internal view returns (address) {
        return IBytecodeRepository(bytecodeRepository).computeAddress(
            contractType, version, constructorParams, salt, deployer
        );
    }

    function _deployLatestPatch(
        bytes32 contractType,
        uint256 minorVersion,
        bytes memory constructorParams,
        bytes32 salt
    ) internal returns (address) {
        // NOTE: it's best to add a check that deployed contract's version matches the expected one in the governor
        return _deploy(contractType, _getLatestPatchVersion(contractType, minorVersion), constructorParams, salt);
    }

    function _computeAddressLatestPatch(
        bytes32 contractType,
        uint256 minorVersion,
        bytes memory constructorParams,
        bytes32 salt,
        address deployer
    ) internal view returns (address) {
        return _computeAddress(
            contractType, _getLatestPatchVersion(contractType, minorVersion), constructorParams, salt, deployer
        );
    }

    function _getLatestPatchVersion(bytes32 contractType, uint256 minorVersion) internal view returns (uint256) {
        return IBytecodeRepository(bytecodeRepository).getLatestPatchVersion(contractType, minorVersion);
    }

    function _getTokenSpecificPostfix(address token) internal view returns (bytes32) {
        return IBytecodeRepository(bytecodeRepository).getTokenSpecificPostfix(token);
    }
}
