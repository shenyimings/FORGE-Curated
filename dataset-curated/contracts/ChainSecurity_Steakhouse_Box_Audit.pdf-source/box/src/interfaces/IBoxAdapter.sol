// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Steakhouse
pragma solidity >=0.8.0;

import {IAdapter} from "../../lib/vault-v2/src/interfaces/IAdapter.sol";
import {IBox} from "./IBox.sol";

interface IBoxAdapter is IAdapter {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    /* ERRORS */

    error AssetMismatch();
    error CannotSkimBoxShares();
    error InvalidData();
    error NotAuthorized();

    /* FUNCTIONS */

    function factory() external view returns (address);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function parentVault() external view returns (address);
    function box() external view returns (IBox);
    function skimRecipient() external view returns (address);
    function allocation() external view returns (uint256);
    function ids() external view returns (bytes32[] memory);

    // Added for BoxAdapter
    function adapterId() external view returns (bytes32);
    function adapterData() external view returns (bytes memory);
}
