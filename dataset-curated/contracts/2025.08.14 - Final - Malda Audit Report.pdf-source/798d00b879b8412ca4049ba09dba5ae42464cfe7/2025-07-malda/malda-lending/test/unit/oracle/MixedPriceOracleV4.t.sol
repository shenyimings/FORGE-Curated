// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {MixedPriceOracleV4} from "src/oracles/MixedPriceOracleV4.sol";
import {IDefaultAdapter} from "src/interfaces/IDefaultAdapter.sol";
import {ImToken} from "src/interfaces/ImToken.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Base_Unit_Test} from "test/Base_Unit_Test.t.sol";
import {Operator} from "src/Operator/Operator.sol";

contract MockAdapter {
    uint8 public decimals = 8;
    int256 public price = 1e8;
    uint256 public updatedAt = block.timestamp;

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, price, 0, updatedAt, 0);
    }

    function setPrice(int256 _price) external {
        price = _price;
    }

    function setUpdatedAt(uint256 _time) external {
        updatedAt = _time;
    }
}

contract MockRoles {
    mapping(address => bool) public allowed;

    function GUARDIAN_ORACLE() external pure returns (bytes32) {
        return keccak256("GUARDIAN_ORACLE");
    }

    function isAllowedFor(address user, bytes32) external view returns (bool) {
        return allowed[user];
    }

    function allow(address user) external {
        allowed[user] = true;
    }
}

contract MockToken {
    string public symbol_ = "MOCK";
    address public underlying_ = address(this);

    function symbol() external view returns (string memory) {
        return symbol_;
    }

    function underlying() external view returns (address) {
        return underlying_;
    }
}

contract MixedPriceOracleV4Test is Test {
    MixedPriceOracleV4 oracle;
    MockAdapter api3;
    MockAdapter eOracle;
    MockRoles roles;
    MockToken token;

    function setUp() public {
        api3 = new MockAdapter();
        eOracle = new MockAdapter();
        roles = new MockRoles();
        token = new MockToken();

        string[] memory symbols = new string[](1);
        symbols[0] = "MOCK";

        MixedPriceOracleV4.PriceConfig[] memory configs = new MixedPriceOracleV4.PriceConfig[](1);
        configs[0] = MixedPriceOracleV4.PriceConfig({
            api3Feed: address(api3),
            eOracleFeed: address(eOracle),
            toSymbol: "USD",
            underlyingDecimals: 18
        });

        oracle = new MixedPriceOracleV4(symbols, configs, address(roles), 1 days);
        roles.allow(address(this));

        vm.warp(100 days);
    }

    function testSetStaleness() public {
        oracle.setStaleness("MOCK", 1234);
        assertEq(oracle.stalenessPerSymbol("MOCK"), 1234);
    }

    function testSetMaxPriceDelta() public {
        oracle.setMaxPriceDelta(500);
        assertEq(oracle.maxPriceDelta(), 500);
    }

    function testSetSymbolMaxPriceDelta() public {
        oracle.setSymbolMaxPriceDelta(400, "MOCK");
        assertEq(oracle.deltaPerSymbol("MOCK"), 400);
    }

    function testSetConfig() public {
        MixedPriceOracleV4.PriceConfig memory cfg = MixedPriceOracleV4.PriceConfig({
            api3Feed: address(api3),
            eOracleFeed: address(eOracle),
            toSymbol: "USD",
            underlyingDecimals: 18
        });
        oracle.setConfig("MOCK", cfg);
    }

    function testGetPrice() public {
        eOracle.setUpdatedAt(block.timestamp - 10);
        uint256 price = oracle.getPrice(address(token));
        assertEq(price, 1e18); // since price is 1e8 and decimals = 8
    }

    function testGetUnderlyingPrice() public {
        eOracle.setUpdatedAt(block.timestamp - 10);
        uint256 price = oracle.getUnderlyingPrice(address(token));
        assertEq(price, 1e18); // same as getPrice because underlyingDecimals = 18
    }

    function testUseEOracleOnApi3Stale() public {
        api3.setUpdatedAt(block.timestamp - 2 days);
        eOracle.setPrice(2e8);
        eOracle.setUpdatedAt(block.timestamp);

        uint256 price = oracle.getPrice(address(token));
        assertEq(price, 2e18);
    }

    function testRevertIfBothStale() public {
        api3.setUpdatedAt(block.timestamp - 2 days);
        eOracle.setUpdatedAt(block.timestamp - 2 days);

        vm.expectRevert(MixedPriceOracleV4.MixedPriceOracle_eOracleStalePrice.selector);
        oracle.getPrice(address(token));
    }

    function testFallbackToEOracleOnDeltaTooHigh() public {
        // api3 = 1e8, eOracle = 3e8 -> 200% delta
        eOracle.setPrice(3e8);
        eOracle.setUpdatedAt(block.timestamp);

        oracle.setSymbolMaxPriceDelta(1500, "MOCK"); // 1.5% allowed

        uint256 price = oracle.getPrice(address(token));
        assertEq(price, 3e18);
    }

    function test_FailsIfDeltaTooHighAndEOracleStale() public {
        eOracle.setPrice(3e8);
        eOracle.setUpdatedAt(block.timestamp - 2 days);
        oracle.setSymbolMaxPriceDelta(1500, "MOCK");

        vm.expectRevert(MixedPriceOracleV4.MixedPriceOracle_eOracleStalePrice.selector);
        oracle.getPrice(address(token));
    }
}
