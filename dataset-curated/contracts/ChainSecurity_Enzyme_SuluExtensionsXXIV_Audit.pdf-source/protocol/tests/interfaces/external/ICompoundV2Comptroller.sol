// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.
    (c) Enzyme Foundation <security@enzyme.finance>
    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

/// @title ICompoundV2Comptroller Interface
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Minimal interface for interactions with Compound Comptroller
interface ICompoundV2Comptroller {
    function getCompAddress() external view returns (address comp_);

    function _setCompSpeeds(address[] memory _cTokens, uint256[] memory _supplySpeeds, uint256[] memory _borrowSpeeds)
        external;

    function admin() external view returns (address admin_);
}
