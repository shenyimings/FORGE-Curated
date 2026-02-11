// SPDX-License-Identifier: MIT
// solhint-disable gas-custom-errors

pragma solidity ^0.8.27;

import {Governed} from "../../governance/implementation/Governed.sol";
import {IGovernanceSettings} from "@flarenetwork/flare-periphery-contracts/flare/IGovernanceSettings.sol";
import {IIAddressUpdater}
    from "@flarenetwork/flare-periphery-contracts/flare/addressUpdater/interfaces/IIAddressUpdater.sol";
import {IIAddressUpdatable}
    from "@flarenetwork/flare-periphery-contracts/flare/addressUpdater/interfaces/IIAddressUpdatable.sol";


contract AddressUpdaterMock is IIAddressUpdater, Governed {

    string internal constant ERR_ARRAY_LENGTHS = "array lengths do not match";
    string internal constant ERR_ADDRESS_ZERO = "address zero";

    string[] internal contractNames;
    mapping(bytes32 => address) internal contractAddresses;

    constructor(IGovernanceSettings _governanceSettings, address _initialGovernance)
        Governed(_governanceSettings, _initialGovernance) {}

    /**
     * @notice set/update contract names/addresses and then apply changes to other contracts
     * @param _contractNames                contracts names
     * @param _contractAddresses            addresses of corresponding contracts names
     * @param _contractsToUpdate            contracts to be updated
     */
    function update(
        string[] memory _contractNames,
        address[] memory _contractAddresses,
        IIAddressUpdatable[] memory _contractsToUpdate
    )
        external onlyGovernance
    {
        _addOrUpdateContractNamesAndAddresses(_contractNames, _contractAddresses);
        _updateContractAddresses(_contractsToUpdate);
    }

    /**
     * @notice Updates contract addresses on all contracts implementing IIAddressUpdatable interface
     * @param _contractsToUpdate            contracts to be updated
     */
    function updateContractAddresses(IIAddressUpdatable[] memory _contractsToUpdate)
        external
        onlyImmediateGovernance
    {
        _updateContractAddresses(_contractsToUpdate);
    }

    /**
     * @notice Add or update contract names and addresses that are later used in updateContractAddresses calls
     * @param _contractNames                contracts names
     * @param _contractAddresses            addresses of corresponding contracts names
     */
    function addOrUpdateContractNamesAndAddresses(
        string[] memory _contractNames,
        address[] memory _contractAddresses
    )
        external onlyGovernance
    {
        _addOrUpdateContractNamesAndAddresses(_contractNames, _contractAddresses);
    }

    /**
     * @notice Remove contracts with given names
     * @param _contractNames                contracts names
     */
    function removeContracts(string[] memory _contractNames) external onlyGovernance {
        for (uint256 i = 0; i < _contractNames.length; i++) {
            string memory contractName = _contractNames[i];
            bytes32 nameHash = _keccak256AbiEncode(contractName);
            require(contractAddresses[nameHash] != address(0), ERR_ADDRESS_ZERO);
            delete contractAddresses[nameHash];
            uint256 index = contractNames.length;
            while (index > 0) {
                index--;
                if (nameHash == _keccak256AbiEncode(contractNames[index])) {
                    break;
                }
            }
            contractNames[index] = contractNames[contractNames.length - 1];
            contractNames.pop();
        }
    }

    /**
     * @notice Returns all contract names and corresponding addresses
     */
    function getContractNamesAndAddresses() external view override returns(
        string[] memory _contractNames,
        address[] memory _contractAddresses
    ) {
        _contractNames = contractNames;
        uint256 len = _contractNames.length;
        _contractAddresses = new address[](len);
        while (len > 0) {
            len--;
            _contractAddresses[len] = contractAddresses[_keccak256AbiEncode(_contractNames[len])];
        }
    }

    /**
     * @notice Returns contract address for the given name - might be address(0)
     * @param _name             name of the contract
     */
    function getContractAddress(string calldata _name) external view override returns(address) {
        return contractAddresses[_keccak256AbiEncode(_name)];
    }

    /**
     * @notice Returns contract address for the given name hash - might be address(0)
     * @param _nameHash         hash of the contract name (keccak256(abi.encode(name))
     */
    function getContractAddressByHash(bytes32 _nameHash) external view override returns(address) {
        return contractAddresses[_nameHash];
    }

    /**
     * @notice Returns contract addresses for the given names - might be address(0)
     * @param _names            names of the contracts
     */
    function getContractAddresses(string[] calldata _names) external view override returns(address[] memory) {
        address[] memory addresses = new address[](_names.length);
        for (uint256 i = 0; i < _names.length; i++) {
            addresses[i] = contractAddresses[_keccak256AbiEncode(_names[i])];
        }
        return addresses;
    }

    /**
     * @notice Returns contract addresses for the given name hashes - might be address(0)
     * @param _nameHashes       hashes of the contract names (keccak256(abi.encode(name))
     */
    function getContractAddressesByHash(
        bytes32[] calldata _nameHashes
    )
        external view override returns(address[] memory)
    {
        address[] memory addresses = new address[](_nameHashes.length);
        for (uint256 i = 0; i < _nameHashes.length; i++) {
            addresses[i] = contractAddresses[_nameHashes[i]];
        }
        return addresses;
    }

    /**
     * @notice Add or update contract names and addresses that are later used in updateContractAddresses calls
     * @param _contractNames                contracts names
     * @param _contractAddresses            addresses of corresponding contracts names
     */
    function _addOrUpdateContractNamesAndAddresses(
        string[] memory _contractNames,
        address[] memory _contractAddresses
    )
        internal
    {
        uint256 len = _contractNames.length;
        require(len == _contractAddresses.length, ERR_ARRAY_LENGTHS);

        for (uint256 i = 0; i < len; i++) {
            require(_contractAddresses[i] != address(0), ERR_ADDRESS_ZERO);
            bytes32 nameHash = _keccak256AbiEncode(_contractNames[i]);
            // add new contract name if address is not known yet
            if (contractAddresses[nameHash] == address(0)) {
                contractNames.push(_contractNames[i]);
            }
            // set or update contract address
            contractAddresses[nameHash] = _contractAddresses[i];
        }
    }

    /**
     * @notice Updates contract addresses on all contracts implementing IIAddressUpdatable interface
     * @param _contractsToUpdate            contracts to be updated
     */
    function _updateContractAddresses(IIAddressUpdatable[] memory _contractsToUpdate) internal {
        uint256 len = contractNames.length;
        bytes32[] memory nameHashes = new bytes32[](len);
        address[] memory addresses = new address[](len);
        while (len > 0) {
            len--;
            nameHashes[len] = _keccak256AbiEncode(contractNames[len]);
            addresses[len] = contractAddresses[nameHashes[len]];
        }

        for (uint256 i = 0; i < _contractsToUpdate.length; i++) {
            _contractsToUpdate[i].updateContractAddresses(nameHashes, addresses);
        }
    }

    /**
     * @notice Returns hash from string value
     */
    function _keccak256AbiEncode(string memory _value) internal pure returns(bytes32) {
        return keccak256(abi.encode(_value));
    }
}
