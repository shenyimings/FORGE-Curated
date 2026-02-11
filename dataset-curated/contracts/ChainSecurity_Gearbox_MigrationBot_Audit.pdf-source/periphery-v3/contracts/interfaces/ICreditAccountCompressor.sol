// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {CreditAccountData, TokenInfo} from "../types/CreditAccountState.sol";
import {CreditAccountFilter, CreditManagerFilter} from "../types/Filters.sol";

/// @title  Credit account compressor
/// @notice Allows to fetch data on all credit accounts matching certain criteria in an efficient manner
/// @dev    The contract is not gas optimized and is thus not recommended for on-chain use
/// @dev    Querying functions try to process as many accounts as possible and stop when they get close to gas limit
interface ICreditAccountCompressor is IVersion {
    /// @notice Returns data for a particular `creditAccount`
    function getCreditAccountData(address creditAccount) external view returns (CreditAccountData memory);

    /// @notice Returns data for credit accounts that match `caFilter` in credit managers matching `cmFilter`
    /// @dev    The non-zero value of `nextOffset` return variable indicates that gas supplied with a call was
    ///         insufficient to process all the accounts and next iteration starting from this value is needed
    function getCreditAccounts(CreditManagerFilter memory cmFilter, CreditAccountFilter memory caFilter, uint256 offset)
        external
        view
        returns (CreditAccountData[] memory data, uint256 nextOffset);

    /// @dev Same as above but with `limit` parameter that specifies the number of accounts to process
    function getCreditAccounts(
        CreditManagerFilter memory cmFilter,
        CreditAccountFilter memory caFilter,
        uint256 offset,
        uint256 limit
    ) external view returns (CreditAccountData[] memory data, uint256 nextOffset);

    /// @notice Returns data for credit accounts that match `caFilter` in a given `creditManager`
    /// @dev    The non-zero value of `nextOffset` return variable indicates that gas supplied with a call was
    ///         insufficient to process all the accounts and next iteration starting from this value is needed
    function getCreditAccounts(address creditManager, CreditAccountFilter memory caFilter, uint256 offset)
        external
        view
        returns (CreditAccountData[] memory data, uint256 nextOffset);

    /// @dev Same as above but with `limit` parameter that specifies the number of accounts to process
    function getCreditAccounts(
        address creditManager,
        CreditAccountFilter memory caFilter,
        uint256 offset,
        uint256 limit
    ) external view returns (CreditAccountData[] memory data, uint256 nextOffset);

    /// @notice Counts credit accounts that match `caFilter` in credit managers matching `cmFilter`
    function countCreditAccounts(CreditManagerFilter memory cmFilter, CreditAccountFilter memory caFilter)
        external
        view
        returns (uint256);

    /// @notice Counts credit accounts that match `caFilter` in a given `creditManager`
    function countCreditAccounts(address creditManager, CreditAccountFilter memory caFilter)
        external
        view
        returns (uint256);
}
