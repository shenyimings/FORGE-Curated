// SPDX-License-Identifier: GPL-3.0-or-later

// Chief.sol - select an authority by consensus

// Copyright (C) 2017 DappHub, LLC
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

interface DSAuthority {
    function canCall(address src, address dst, bytes4 sig) external view returns (bool);
}

interface GemLike {
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

contract Chief is DSAuthority {
    uint256                                  public live;
    address                                  public hat;
    mapping(bytes32 slate => address[] yays) public slates;
    mapping(address usr   => bytes32 slate)  public votes;
    mapping(address yay   => uint256 amt)    public approvals;
    mapping(address usr   => uint256 amt)    public deposits;
    uint256                                  public last;

    GemLike public immutable gov;
    uint256 public immutable maxYays;
    uint256 public immutable launchThreshold;
    uint256 public immutable liftCooldown;

    bytes32 public constant EMPTY_SLATE   = keccak256(abi.encodePacked(new address[](0)));

    event Launch();
    event Lock(address indexed usr, uint256 wad);
    event Free(address indexed usr, uint256 wad);
    event Etch(bytes32 indexed slate, address[] yays);
    event Vote(address indexed usr, bytes32 indexed slate);
    event Lift(address indexed whom);

    constructor(address gov_, uint256 maxYays_, uint256 launchThreshold_, uint256 liftCooldown_) {
        gov = GemLike(gov_);
        maxYays = maxYays_;
        launchThreshold = launchThreshold_;
        liftCooldown = liftCooldown_;
    }

    function _addWeight(uint256 weight, bytes32 slate) internal {
        address[] memory yays = slates[slate];
        for (uint256 i = 0; i < yays.length;) {
            approvals[yays[i]] += weight;
            unchecked { ++i; } // bounded by max array length
        }
    }

    function _subWeight(uint256 weight, bytes32 slate) internal {
        address[] memory yays = slates[slate];
        for (uint256 i = 0; i < yays.length;) {
            approvals[yays[i]] -= weight;
            unchecked { ++i; } // bounded by max array length
        }
    }

    function length(bytes32 slate) external view returns (uint256) {
        return slates[slate].length;
    }

    function canCall(address caller, address, bytes4) external view returns (bool ok) {
        ok = live == 1 && caller == hat;
    }

    function launch() external {
        require(live == 0, "Chief/already-live");
        require(hat == address(0), "Chief/not-address-zero");
        require(approvals[address(0)] >= launchThreshold, "Chief/less-than-threshold");
        live = 1;
        last = block.number;
        emit Launch();
    }

    function lock(uint256 wad) external {
        gov.transferFrom(msg.sender, address(this), wad);
        deposits[msg.sender] += wad;
        _addWeight(wad, votes[msg.sender]);
        emit Lock(msg.sender, wad);
    }

    function free(uint256 wad) external {
        require(block.number > last, "Chief/cant-free-same-block");
        deposits[msg.sender] -= wad;
        _subWeight(wad, votes[msg.sender]);
        gov.transfer(msg.sender, wad);
        emit Free(msg.sender, wad);
    }

    function etch(address[] calldata yays) public returns (bytes32 slate) {
        require(yays.length <= maxYays, "Chief/greater-max-yays");
        if (yays.length > 1) {
            unchecked { // bounded by min and max array length
                for (uint256 i = 0; i < yays.length - 1;) {
                    // strict inequality ensures both ordering and uniqueness
                    require(yays[i] < yays[i + 1], "Chief/yays-not-ordered");
                    ++i;
                }
            }
        }
        slate = keccak256(abi.encodePacked(yays));
        slates[slate] = yays;
        emit Etch(slate, yays);
    }

    function vote(address[] calldata yays) external returns (bytes32 slate) {
        slate = etch(yays);
        vote(slate);
    }

    function vote(bytes32 slate) public {
        require(slates[slate].length > 0 || slate == EMPTY_SLATE, "Chief/invalid-slate");
        uint256 weight = deposits[msg.sender];
        _subWeight(weight, votes[msg.sender]);
        votes[msg.sender] = slate;
        _addWeight(weight, slate);
        emit Vote(msg.sender, slate);
    }

    function lift(address whom) external {
        require(block.number == last || block.number > last + liftCooldown, "Chief/cant-lift-again-yet");
        require(approvals[whom] > approvals[hat], "Chief/not-higher-current-hat");
        hat = whom;
        last = block.number;
        emit Lift(whom);
    }

    // Compatibility with old getters

    function GOV() external view returns (address) {
        return address(gov);
    }

    function MAX_YAYS() external view returns (uint256) {
        return maxYays;
    }
}
