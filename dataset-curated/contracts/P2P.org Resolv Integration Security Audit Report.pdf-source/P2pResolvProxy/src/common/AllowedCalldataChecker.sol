// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../@openzeppelin/contracts-upgradable/proxy/utils/Initializable.sol";
import "./IAllowedCalldataChecker.sol";

/// @dev No extra calls are allowed for now. AllowedCalldataChecker can be upgraded in the future.
error AllowedCalldataChecker__NoAllowedCalldata();

/// @title AllowedCalldataChecker
/// @author P2P Validator <info@p2p.org>
/// @notice Upgradable contract for checking if a calldata is allowed
contract AllowedCalldataChecker is IAllowedCalldataChecker, Initializable {

    function initialize() public initializer {
        // do nothing in this implementation
    }

    /// @inheritdoc IAllowedCalldataChecker
    function checkCalldata(
        address,
        bytes4,
        bytes calldata
    ) public pure {
        revert AllowedCalldataChecker__NoAllowedCalldata();
    }
}
