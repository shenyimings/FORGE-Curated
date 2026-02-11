// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21;

import {Test, console2} from "forge-std/Test.sol";
import {LevelReserveLensChainlinkOracle} from "../../../src/lens/LevelReserveLensChainlinkOracle.sol";
import {LevelReserveLens} from "../../../src/lens/LevelReserveLens.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {MockLevelReserveLens} from "../../mocks/MockLevelReserveLens.sol";
import {MockToken} from "../../mocks/MockToken.sol";

contract LevelReserveLensChainlinkOracleTest is Test {
    LevelReserveLensChainlinkOracle public oracle;
    MockLevelReserveLens public lens;
    MockToken public lvlUSD;

    address public admin = address(1);
    address public pauser = address(2);

    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        lvlUSD = new MockToken("Level USD", "lvlUSD", 18, address(admin));
        lens = new MockLevelReserveLens();

        oracle = new LevelReserveLensChainlinkOracle(admin, pauser, address(lens));
    }

    function test_constructor() public {
        assertEq(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(oracle.hasRole(oracle.PAUSER_ROLE(), pauser), true);
        assertEq(address(oracle.lens()), address(lens));
    }

    function test_constructor_zeroAddressAdmin() public {
        vm.expectRevert("Address cannot be zero");
        new LevelReserveLensChainlinkOracle(address(0), pauser, address(lens));
    }

    function test_constructor_zeroAddressLens() public {
        vm.expectRevert("Address cannot be zero");
        new LevelReserveLensChainlinkOracle(admin, pauser, address(0));
    }

    function test_decimals() public {
        assertEq(oracle.decimals(), 8);
    }

    function test_description() public {
        assertEq(oracle.description(), "Chainlink interface compliant oracle for Level USD");
    }

    function test_version() public {
        assertEq(oracle.version(), 0);
    }

    function test_latestRoundData() public {
        uint256 mockPrice = 0.9e18;
        lens.setMockPrice(mockPrice);

        uint256 expectedPrice = 0.9e8;

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();

        assertEq(roundId, 0);
        assertEq(answer, int256(expectedPrice));
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_latestRoundData_WhenPaused() public {
        vm.prank(pauser);
        oracle.setPaused(true);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();

        assertEq(roundId, 0);
        assertEq(answer, 1e8); // Default $1 price
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_latestRoundData_whenLensReverts() public {
        lens.setShouldRevert(true);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();

        assertEq(roundId, 0);
        assertEq(answer, 1e8); // Default $1 price
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_latestRoundData_whenDecimalsReverts() public {
        lens.setShouldDecimalsRevert(true);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();

        assertEq(roundId, 0);
        assertEq(answer, 1e8); // Default $1 price
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_getRoundData() public {
        uint256 mockPrice = 0.9e18;
        lens.setMockPrice(mockPrice);

        uint256 expectedPrice = 0.9e8;

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.getRoundData(0);

        assertEq(roundId, 0);
        assertEq(answer, int256(expectedPrice));
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_setPaused() public {
        vm.prank(pauser);
        oracle.setPaused(true);

        assertTrue(oracle.paused());

        vm.prank(pauser);
        oracle.setPaused(false);

        assertFalse(oracle.paused());
    }

    function test_setPaused_OnlyPauser() public {
        vm.startPrank(address(0xdead));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(0xdead), oracle.PAUSER_ROLE()
            )
        );
        oracle.setPaused(true);
    }

    function test_defaultRoundData() public {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.defaultRoundData();

        assertEq(roundId, 0);
        assertEq(answer, 1e8); // $1 with 18 decimals
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }
}
