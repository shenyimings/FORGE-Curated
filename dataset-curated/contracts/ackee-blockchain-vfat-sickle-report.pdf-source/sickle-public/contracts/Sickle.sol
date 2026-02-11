// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SickleStorage } from "contracts/base/SickleStorage.sol";
import { Multicall } from "contracts/base/Multicall.sol";
import { SickleRegistry } from "contracts/SickleRegistry.sol";

/// @title Sickle contract
/// @author vfat.tools
/// @notice Sickle facilitates farming and interactions with Masterchef
/// contracts
/// @dev Base contract inheriting from all the other "manager" contracts
contract Sickle is SickleStorage, Multicall {
    /// @notice Function to receive ETH
    receive() external payable { }

    /// @param sickleRegistry_ Address of the SickleRegistry contract
    constructor(
        SickleRegistry sickleRegistry_
    ) initializer Multicall(sickleRegistry_) {
        _Sickle_initialize(address(0), address(0));
    }

    /// @param sickleOwner_ Address of the Sickle owner
    function initialize(
        address sickleOwner_,
        address approved_
    ) external initializer {
        _Sickle_initialize(sickleOwner_, approved_);
    }

    /// INTERNALS ///

    function _Sickle_initialize(
        address sickleOwner_,
        address approved_
    ) internal {
        SickleStorage._SickleStorage_initialize(sickleOwner_, approved_);
    }

    function onERC721Received(
        address, // operator
        address, // from
        uint256, // tokenId
        bytes calldata // data
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address, // operator
        address, // from
        uint256, // id
        uint256, // value
        bytes calldata // data
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address, // operator
        address, // from
        uint256[] calldata, // ids
        uint256[] calldata, // values
        bytes calldata // data
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
