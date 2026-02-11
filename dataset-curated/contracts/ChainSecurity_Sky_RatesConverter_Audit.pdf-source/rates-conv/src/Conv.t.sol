// SPDX-FileCopyrightText: 2025 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./Conv.sol";
import "./mock/RatesMapping.sol";

abstract contract StorageAddition {
    uint256 a;
}

contract ModifiedConv is StorageAddition, Conv {}

contract ConvTest is Test {
    Conv public conv;
    RatesMapping public ratesMapping;
    uint256 public maxBps;
    uint256 public constant RAY = 10 ** 27;

    function setUp() public {
        conv = new Conv();
        ratesMapping = new RatesMapping();
        maxBps = conv.MAX_BPS_IN();
    }

    function testBtor() public view {
        for (uint256 bps = 0; bps <= maxBps; bps++) {
            uint256 mappingRate = ratesMapping.rates(bps);
            uint256 convRate = conv.btor(bps);

            assertEq(convRate, mappingRate, string.concat("Rate mismatch at bps=", vm.toString(bps)));
        }
    }

    function testBtorRatesInDifferentStorageSlot() public {
        ModifiedConv modifiedConv = new ModifiedConv();
        for (uint256 bps = 0; bps <= maxBps; bps++) {
            uint256 mappingRate = ratesMapping.rates(bps);
            uint256 convRate = modifiedConv.btor(bps);

            assertEq(
                convRate,
                mappingRate,
                string.concat("Rate mismatch with modified RATES storage position at bps=", vm.toString(bps))
            );
        }
    }

    function testRevert_Btor_WhenInvalidBps() public {
        vm.expectRevert("Conv/bps-too-high");
        conv.btor(maxBps + 1);
    }

    function testFuzz_Btor_InvalidBps(uint256 bps) public {
        bps = bound(bps, maxBps + 1, type(uint256).max);
        vm.expectRevert("Conv/bps-too-high");
        conv.btor(bps);
    }

    function testRtob() public view {
        for (uint256 bps = 0; bps <= 10000; bps++) {
            uint256 mappingRate = ratesMapping.rates(bps);
            uint256 bpsResult = conv.rtob(mappingRate);

            assertEq(bpsResult, bps, "rtob result must match bps");
        }
    }

    function testRevert_Rtob_RayTooLow() public {
        vm.expectRevert("Conv/ray-too-low");
        conv.rtob(0);
    }

    function testFuzz_Rtob_InvalidRay(uint256 ray) public {
        ray = bound(ray, 0, RAY - 1);
        vm.expectRevert("Conv/ray-too-low");
        conv.rtob(ray);
    }

    function testInvariants() public view {
        for (uint256 bps = 0; bps <= maxBps; bps++) {
            uint256 mappingRate = ratesMapping.rates(bps);

            // rtob(btor(bps)) == bps and btor(rtob(ray)) == ray
            assertEq(conv.rtob(conv.btor(bps)), bps, "rtob(btor(bps)) must equal bps");
            assertEq(conv.btor(conv.rtob(mappingRate)), mappingRate, "btor(rtob(ray)) must equal ray");
        }
    }
}
