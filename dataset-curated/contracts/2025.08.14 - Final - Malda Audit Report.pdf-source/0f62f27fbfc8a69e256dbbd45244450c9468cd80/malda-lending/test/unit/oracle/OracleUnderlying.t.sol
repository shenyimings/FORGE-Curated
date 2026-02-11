// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {MixedPriceOracleV3} from "src/oracles/MixedPriceOracleV3.sol";
import {IDefaultAdapter} from "src/interfaces/IDefaultAdapter.sol";
import {ImToken} from "src/interfaces/ImToken.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Base_Unit_Test} from "test/Base_Unit_Test.t.sol";
import {Operator} from "src/Operator/Operator.sol";

contract MockChainlinkOracle {
    uint256 public decimals;
    uint256 price;

    constructor(uint256 _price, uint256 _decimals) {
        price = _price;
        decimals = _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 1;
        answer = int256(price);
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = 1;
    }
}

contract DummyToken {
    string public symbol;
    uint256 public decimals;
    constructor(string memory _symbol, uint256 _decimals) {
        symbol = _symbol;
        decimals = _decimals;
    }
}

contract DummyMToken {
    address public underlying;
    constructor(address _underlying) {
        underlying = _underlying;
    }
}


contract MixedPriceOracleV3_Test is Operator, Test {
    MixedPriceOracleV3 mixedPriceOracle;

    DummyToken BTC;
    DummyMToken mBTC;
    uint256 usdPerBitcoin = 70_000;
    uint256 bitcoinDecimals = 8;

    DummyToken ETH;
    DummyMToken mETH;
    uint256 usdPerEth = 2_500;
    uint256 ethDecimals = 18;

    DummyToken USDC;
    DummyMToken mUSDC;
    uint256 usdPerUsdc = 1;
    uint256 usdcDecimals = 6;

    DummyToken LargeDecimalsToken;
    DummyMToken mLargeDecimalsToken;
    uint256 usdPerLargeToken = 1;
    uint256 largeTokenDecimals = 30;
    

    uint256 feedDecimals = 8; //chainlink returns answers in 8 decimals
    function newUSDOracle(uint256 usdPerToken) public returns (MockChainlinkOracle) {
        uint256 decimals = feedDecimals;
        uint256 price = 10**decimals * usdPerToken;
        return new MockChainlinkOracle(price, decimals);
    }

    function newOracleInBase(uint256 usdPerQuotedToken, uint256 usdPerBaseToken) public returns (MockChainlinkOracle) {
        uint256 decimals = feedDecimals;
        uint256 price = 10**decimals * usdPerQuotedToken / usdPerBaseToken;
        return new MockChainlinkOracle(price, decimals);
    }

    function setUp() public {
        BTC = new DummyToken("BTC", bitcoinDecimals);
        ETH = new DummyToken("ETH", ethDecimals);
        USDC = new DummyToken("USDC", usdcDecimals);
        LargeDecimalsToken = new DummyToken("Large", largeTokenDecimals);

        mBTC = new DummyMToken(address(BTC));
        mETH = new DummyMToken(address(ETH));
        mUSDC = new DummyMToken(address(USDC));
        mLargeDecimalsToken = new DummyMToken(address(LargeDecimalsToken));

        MockChainlinkOracle usdPerUSDCOracle = newUSDOracle(usdPerUsdc);
        MockChainlinkOracle usdcPerEthOracle = newOracleInBase(usdPerEth, usdPerUsdc);
        MockChainlinkOracle ethPerBTCOracle = newOracleInBase(usdPerBitcoin, usdPerEth);

        uint256 numOracles = 3;
        string[] memory symbols = new string[](numOracles);
        IDefaultAdapter.PriceConfig[] memory configs = new IDefaultAdapter.PriceConfig[](numOracles);

        symbols[0] = "USDC";
        configs[0] = IDefaultAdapter.PriceConfig({
            defaultFeed: address(usdPerUSDCOracle),
            toSymbol: "USD",
            underlyingDecimals: usdcDecimals
        });

        symbols[1] = "ETH";
        configs[1] = IDefaultAdapter.PriceConfig({
            defaultFeed: address(usdcPerEthOracle),
            toSymbol: "USDC",
            underlyingDecimals: ethDecimals
        });

        symbols[2] = "BTC";
        configs[2] = IDefaultAdapter.PriceConfig({
            defaultFeed: address(ethPerBTCOracle),
            toSymbol: "ETH",
            underlyingDecimals: bitcoinDecimals
        });

        address roles = address(0);
        uint256 stalenessPeriod = 100;

        mixedPriceOracle = new MixedPriceOracleV3(symbols, configs, roles, stalenessPeriod);
        // Set the oracleOperator to our mocked oracle
        oracleOperator = address(mixedPriceOracle);
    }

    function test_getPriceUSD() public view {
        uint256 btcPrice = mixedPriceOracle.getUnderlyingPrice(address(mBTC));
        uint256 ethPrice = mixedPriceOracle.getUnderlyingPrice(address(mETH));
        uint256 usdcPrice = mixedPriceOracle.getUnderlyingPrice(address(mUSDC));

        console.log("btcPrice", btcPrice);
        console.log("ethPrice", ethPrice);
        console.log("usdcPrice", usdcPrice);
        assertEq(btcPrice, 10**(36-bitcoinDecimals) * usdPerBitcoin);
        assertEq(ethPrice, 10**(36 - ethDecimals) * usdPerEth);
        assertEq(usdcPrice, 10**(36 - usdcDecimals) * usdPerUsdc);

        assertEq(usdPerBitcoin *1e8, _convertMarketAmountToUSDValue(1e8, address(mBTC)), "A");
        assertEq(usdPerEth *1e8, _convertMarketAmountToUSDValue(1e18, address(mETH)), "B");
        assertEq(usdPerUsdc *1e8, _convertMarketAmountToUSDValue(1e6, address(mUSDC)), "C");
    }
}
