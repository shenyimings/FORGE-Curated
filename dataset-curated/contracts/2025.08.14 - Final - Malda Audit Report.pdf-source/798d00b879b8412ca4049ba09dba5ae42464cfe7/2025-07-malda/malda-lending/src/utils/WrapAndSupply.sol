// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This file contains code derived from or inspired by Compound V2,
// originally licensed under the BSD 3-Clause License. See LICENSE-COMPOUND-V2
// for original license terms and attributions.

// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ImErc20} from "src/interfaces/ImErc20.sol";
import {ImTokenMinimal} from "src/interfaces/ImToken.sol";
import {ImTokenGateway} from "src/interfaces/ImTokenGateway.sol";

interface IWrappedNative {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
}

contract WrapAndSupply {
    IWrappedNative public immutable wrappedNative;

    // ----------- ERRORS ------------
    error WrapAndSupply_AddressNotValid();
    error WrapAndSupply_AmountNotValid();

    // ----------- EVENTS ------------
    event WrappedAndSupplied(address indexed sender, address indexed receiver, address indexed market, uint256 amount);

    constructor(address _wrappedNative) {
        require(_wrappedNative != address(0), WrapAndSupply_AddressNotValid());
        wrappedNative = IWrappedNative(_wrappedNative);
    }

    // ----------- PUBLIC ------------
    /**
     * @notice Wraps a native coin into its wrapped version and supplies on a host market
     * @param mToken The market address
     * @param receiver The mToken receiver
     */
    function wrapAndSupplyOnHostMarket(address mToken, address receiver, uint256 minAmount) external payable {
        address underlying = ImTokenMinimal(mToken).underlying();
        require(underlying == address(wrappedNative), WrapAndSupply_AddressNotValid());

        uint256 amount = _wrap();

        IERC20(underlying).approve(mToken, 0);
        IERC20(underlying).approve(mToken, amount);
        ImErc20(mToken).mint(amount, receiver, minAmount);

        emit WrappedAndSupplied(msg.sender, receiver, mToken, amount);
    }

    /**
     * @notice Wraps a native coin into its wrapped version and supplies on an extension market
     * @param mTokenGateway The market address
     * @param receiver The receiver
     * @param selector The host chain function selector
     */
    function wrapAndSupplyOnExtensionMarket(address mTokenGateway, address receiver, bytes4 selector)
        external
        payable
    {
        address underlying = ImTokenGateway(mTokenGateway).underlying();
        require(underlying == address(wrappedNative), WrapAndSupply_AddressNotValid());

        uint256 amount = _wrap();

        IERC20(underlying).approve(mTokenGateway, 0);
        IERC20(underlying).approve(mTokenGateway, amount);
        ImTokenGateway(mTokenGateway).supplyOnHost(amount, receiver, selector);
    }

    // ----------- PRIVATE ------------
    function _wrap() private returns (uint256) {
        uint256 amount = msg.value;
        require(amount > 0, WrapAndSupply_AmountNotValid());

        wrappedNative.deposit{value: amount}();
        return amount;
    }
}
