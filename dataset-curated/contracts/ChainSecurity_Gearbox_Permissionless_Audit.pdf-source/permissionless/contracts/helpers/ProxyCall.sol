// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ImmutableOwnableTrait} from "../traits/ImmutableOwnableTrait.sol";

/// @title ProxyCall
/// @notice Contract that allows an immutable owner to make calls on its behalf
contract ProxyCall is ImmutableOwnableTrait {
    using Address for address;

    /// @notice Emitted when a call is made through the proxy
    event ProxyCallExecuted(address target, bytes data);

    constructor() ImmutableOwnableTrait(msg.sender) {}

    /// @notice Makes a call to target contract with provided data
    /// @param target Address of contract to call
    /// @param data Call data to execute
    /// @return result The raw return data from the call
    function proxyCall(address target, bytes calldata data) external onlyOwner returns (bytes memory result) {
        // Make the call using OpenZeppelin's Address library
        return target.functionCall(data);
    }
}
