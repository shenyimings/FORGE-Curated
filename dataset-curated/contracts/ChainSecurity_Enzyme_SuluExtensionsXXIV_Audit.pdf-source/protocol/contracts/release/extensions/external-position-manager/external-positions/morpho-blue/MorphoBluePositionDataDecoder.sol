// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.
    (c) Enzyme Foundation <security@enzyme.finance>
    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.19;

/// @title MorphoBluePositionDataDecoder Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Abstract contract containing data decodings for IMorphoBluePosition payloads
abstract contract MorphoBluePositionDataDecoder {
    /// @dev Helper to decode args used during the AddCollateral action
    function __decodeAddCollateralActionArgs(bytes memory _actionArgs)
        internal
        pure
        returns (bytes32 marketId_, uint256 collateralAmount_)
    {
        return abi.decode(_actionArgs, (bytes32, uint256));
    }

    /// @dev Helper to decode args used during the Borrow action
    function __decodeBorrowActionArgs(bytes memory _actionArgs)
        internal
        pure
        returns (bytes32 marketId_, uint256 borrowAmount_)
    {
        return abi.decode(_actionArgs, (bytes32, uint256));
    }

    /// @dev Helper to decode args used during the Lend action
    function __decodeLendActionArgs(bytes memory _actionArgs)
        internal
        pure
        returns (bytes32 marketId_, uint256 lendAmount_)
    {
        return abi.decode(_actionArgs, (bytes32, uint256));
    }

    /// @dev Helper to decode args used during the Redeem action
    function __decodeRedeemActionArgs(bytes memory _actionArgs)
        internal
        pure
        returns (bytes32 marketId_, uint256 sharesAmount_)
    {
        return abi.decode(_actionArgs, (bytes32, uint256));
    }

    /// @dev Helper to decode args used during the RemoveCollateral action
    function __decodeRemoveCollateralActionArgs(bytes memory _actionArgs)
        internal
        pure
        returns (bytes32 marketId_, uint256 collateralAmount_)
    {
        return abi.decode(_actionArgs, (bytes32, uint256));
    }

    /// @dev Helper to decode args used during the Repay action
    function __decodeRepayActionArgs(bytes memory _actionArgs)
        internal
        pure
        returns (bytes32 marketId_, uint256 repayAmount_)
    {
        return abi.decode(_actionArgs, (bytes32, uint256));
    }
}
