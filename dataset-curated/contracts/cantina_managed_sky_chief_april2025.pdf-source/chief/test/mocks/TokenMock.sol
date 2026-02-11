// SPDX-License-Identifier: GPL-3.0-or-later

// TokenMock.sol

// Copyright (C) 2023 Dai Foundation

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

contract TokenMock {
    mapping (address => uint256)                      public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;

    function transfer(address to, uint256 value) external returns (bool) {
        require(to != address(0) && to != address(this), "TokenMock/invalid-address");
        uint256 balance = balanceOf[msg.sender];
        require(balance >= value, "TokenMock/insufficient-balance");

        balanceOf[msg.sender] = balance - value;
        balanceOf[to] += value;

        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(to != address(0) && to != address(this), "TokenMock/invalid-address");
        uint256 balance = balanceOf[from];
        require(balance >= value, "TokenMock/insufficient-balance");

        if (from != msg.sender) {
            uint256 allowed = allowance[from][msg.sender];
            if (allowed != type(uint256).max) {
                require(allowed >= value, "TokenMock/insufficient-allowance");

                allowance[from][msg.sender] = allowed - value;
            }
        }

        balanceOf[from] = balance - value;
        balanceOf[to] += value;

        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;

        return true;
    }
}
