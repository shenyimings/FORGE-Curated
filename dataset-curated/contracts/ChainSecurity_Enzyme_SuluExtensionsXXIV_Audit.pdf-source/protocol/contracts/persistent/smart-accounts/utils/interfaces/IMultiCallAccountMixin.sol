// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

/// @title IMultiCallAccountMixin Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IMultiCallAccountMixin {
    struct Call {
        address target;
        bytes data;
    }

    function executeCalls(Call[] calldata _calls) external;
}
