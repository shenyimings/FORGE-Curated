// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 [Byzantine Finance]
// The implementation of this contract was inspired by Morpho Vault V2, developed by the Morpho Association in 2025.
pragma solidity >= 0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";

interface IERC4626MerklAdapter is IAdapter {
    /* STRUCTS */

    struct MerklParams {
        address[] users;
        address[] tokens;
        uint256[] amounts;
        bytes32[][] proofs;
    }

    struct SwapParams {
        address swapper;
        bytes swapData;
    }

    struct ClaimParams {
        MerklParams merklParams;
        SwapParams[] swapParams;
    }

    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event SetClaimer(address indexed newClaimer);
    event Skim(address indexed token, uint256 assets);
    event ClaimRewards(address indexed token, uint256 amount);
    event SwapRewards(address indexed swapper, address indexed token, uint256 amount, bytes swapData);

    /* ERRORS */

    error AssetMismatch();
    error CannotSkimERC4626Shares();
    error InvalidData();
    error NotAuthorized();
    error SwapperCannotBeUnderlyingVault();
    error SwapReverted();
    error RewardsNotReceived();

    /* FUNCTIONS */

    function factory() external view returns (address);
    function parentVault() external view returns (address);
    function erc4626Vault() external view returns (address);
    function adapterId() external view returns (bytes32);
    function skimRecipient() external view returns (address);
    function claimer() external view returns (address);
    function allocation() external view returns (uint256);
    function ids() external view returns (bytes32[] memory);
    function setSkimRecipient(address newSkimRecipient) external;
    function setClaimer(address newClaimer) external;
    function skim(address token) external;
    function claim(bytes calldata data) external;
}
