// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Operator} from "src/Operator/Operator.sol";
import {Roles} from "src/Roles.sol";
import {Pauser} from "src/pauser/Pauser.sol";

import {
    DeployConfig,
    MarketRelease,
    Role,
    InterestConfig,
    OracleConfigRelease,
    OracleFeed
} from "../../deployers/Types.sol";

import {DeployBaseRelease} from "../../deployers/DeployBaseRelease.sol";
import {SetRole} from "../../configuration/SetRole.s.sol";
import {SetCollateralFactor} from "../../configuration/SetCollateralFactor.s.sol";
import {SetReserveFactor} from "../../configuration/SetReserveFactor.s.sol";
import {SetLiquidationBonus} from "../../configuration/SetLiquidationBonus.s.sol";
import {SupportMarket} from "../../configuration/SupportMarket.s.sol";
import {SetBorrowRateMaxMantissa} from "../../configuration/SetBorrowRateMaxMantissa.s.sol";
import {SetBorrowCap} from "../../configuration/SetBorrowCap.s.sol";
import {SetSupplyCap} from "../../configuration/SetSupplyCap.s.sol";
import {SetPriceFeedOnOracleV4} from "../../configuration/SetPriceFeedOnOracleV4.s.sol";

contract ConfigureRelease is DeployBaseRelease {
    using stdJson for string;

    address[] marketList;

    mapping(string => uint256) public collateralFactors;
    mapping(string => uint256) public reserveFactors;
    mapping(string => uint256) public liquidationBonuses;
    mapping(string => uint256) public borrowCaps;
    mapping(string => MarketRelease) public fullConfigs;

    address oracle;
    address operator;
    address rolesContract;
    SetRole setRole;
    SupportMarket supportMarket;
    SetCollateralFactor setCollateralFactor;
    SetReserveFactor setReserveFactor;
    SetLiquidationBonus setLiquidationBonus;
    SetBorrowRateMaxMantissa setBorrowRateMaxMantissa;
    SetBorrowCap setBorrowCap;
    SetSupplyCap setSupplyCap;
    SetPriceFeedOnOracleV4 setFeed;

    function setUp() public override {
        configPath = "deployment-config-release.json";
        super.setUp();

        // borrow caps
        borrowCaps["mUSDC"] = 0;
        borrowCaps["mWETH"] = 0;
        borrowCaps["mUSDT"] = 0;
        borrowCaps["mDAI"] = 0;
        borrowCaps["mWBTC"] = 0;
        borrowCaps["mwstETH"] = 0;
        borrowCaps["mezETH"] = 0;
        borrowCaps["mweETH"] = 0;
        borrowCaps["mwrsETH"] = 0;

        // collateral factors
        collateralFactors["mUSDC"] = 900000000000000000;
        collateralFactors["mWETH"] = 830000000000000000;
        collateralFactors["mUSDT"] = 900000000000000000;
        collateralFactors["mDAI"] = 900000000000000000;
        collateralFactors["mWBTC"] = 780000000000000000;
        collateralFactors["mwstETH"] = 810000000000000000;
        collateralFactors["mezETH"] = 750000000000000000;
        collateralFactors["mweETH"] = 800000000000000000;
        collateralFactors["mwrsETH"] = 750000000000000000;

        // reserve factors
        reserveFactors["mUSDC"] = 100000000000000000;
        reserveFactors["mWETH"] = 150000000000000000;
        reserveFactors["mUSDT"] = 100000000000000000;
        reserveFactors["mDAI"] = 100000000000000000;
        reserveFactors["mWBTC"] = 500000000000000000;
        reserveFactors["mwstETH"] = 50000000000000000;
        reserveFactors["mezETH"] = 450000000000000000;
        reserveFactors["mweETH"] = 450000000000000000;
        reserveFactors["mwrsETH"] = 450000000000000000;

        // liquidation bonuses
        liquidationBonuses["mUSDC"] = 1050000000000000000;
        liquidationBonuses["mWETH"] = 1050000000000000000;
        liquidationBonuses["mUSDT"] = 1050000000000000000;
        liquidationBonuses["mDAI"] = 1050000000000000000;
        liquidationBonuses["mWBTC"] = 1050000000000000000;
        liquidationBonuses["mwstETH"] = 1060000000000000000;
        liquidationBonuses["mezETH"] = 1070000000000000000;
        liquidationBonuses["mweETH"] = 1070000000000000000;
        liquidationBonuses["mwrsETH"] = 1070000000000000000;

        // full configs
        fullConfigs["mUSDC"] = MarketRelease({
            borrowCap: borrowCaps["mUSDC"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mUSDC"],
            decimals: 6,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 3499999999994448000,
                kink: 920000000000000000,
                multiplier: 50605736204435511,
                name: "mUSDC Interest Model"
            }),
            name: "mUSDC",
            supplyCap: 0,
            symbol: "mUSDC",
            underlying: 0x176211869cA2b568f2A7D4EE941E073a821EE1ff,
            reserveFactor: reserveFactors["mUSDC"],
            liquidationBonus: liquidationBonuses["mUSDC"]
        });

        fullConfigs["mWETH"] = MarketRelease({
            borrowCap: borrowCaps["mWETH"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mWETH"],
            decimals: 18,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 4999999999974048000,
                kink: 900000000000000000,
                multiplier: 22498715810630400,
                name: "mWETH Interest Model"
            }),
            name: "mWETH",
            supplyCap: 0,
            symbol: "mWETH",
            underlying: 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f,
            reserveFactor: reserveFactors["mWETH"],
            liquidationBonus: liquidationBonuses["mWETH"]
        });

        fullConfigs["mUSDT"] = MarketRelease({
            borrowCap: borrowCaps["mUSDT"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mUSDT"],
            decimals: 6,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 3499999999994448000,
                kink: 920000000000000000,
                multiplier: 55194998244975695,
                name: "mUSDT Interest Model"
            }),
            name: "mUSDT",
            supplyCap: 0,
            symbol: "mUSDT",
            underlying: 0xA219439258ca9da29E9Cc4cE5596924745e12B93,
            reserveFactor: reserveFactors["mUSDT"],
            liquidationBonus: liquidationBonuses["mUSDT"]
        });

        fullConfigs["mWBTC"] = MarketRelease({
            borrowCap: borrowCaps["mWBTC"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mWBTC"],
            decimals: 8,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 11999999999995568000,
                kink: 800000000000000000,
                multiplier: 36005582570424320,
                name: "mWBTC Interest Model"
            }),
            name: "mWBTC",
            supplyCap: 0,
            symbol: "mWBTC",
            underlying: 0x3aAB2285ddcDdaD8edf438C1bAB47e1a9D05a9b4,
            reserveFactor: reserveFactors["mWBTC"],
            liquidationBonus: liquidationBonuses["mWBTC"]
        });

        fullConfigs["mwstETH"] = MarketRelease({
            borrowCap: borrowCaps["mwstETH"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mwstETH"],
            decimals: 18,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 8499924722164496000,
                kink: 800000000000000000,
                multiplier: 12799993755404800,
                name: "mwstETH Interest Model"
            }),
            name: "mwstETH",
            supplyCap: 0,
            symbol: "mwstETH",
            underlying: 0xB5beDd42000b71FddE22D3eE8a79Bd49A568fC8F,
            reserveFactor: reserveFactors["mwstETH"],
            liquidationBonus: liquidationBonuses["mwstETH"]
        });

        fullConfigs["mezETH"] = MarketRelease({
            borrowCap: borrowCaps["mezETH"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mezETH"],
            decimals: 18,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 3000002316638736000,
                kink: 400000000000000000,
                multiplier: 27999732233587200,
                name: "mezETH Interest Model"
            }),
            name: "mezETH",
            supplyCap: 0,
            symbol: "mezETH",
            underlying: 0x2416092f143378750bb29b79eD961ab195CcEea5,
            reserveFactor: reserveFactors["mezETH"],
            liquidationBonus: liquidationBonuses["mezETH"]
        });

        fullConfigs["mweETH"] = MarketRelease({
            borrowCap: borrowCaps["mweETH"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mweETH"],
            decimals: 18,
            interestModel: InterestConfig({
                baseRate: 317091247,
                blocksPerYear: 31536000,
                jumpMultiplier: 3000002316638736000,
                kink: 400000000000000000,
                multiplier: 27999732233587200,
                name: "mweETH Interest Model"
            }),
            name: "mweETH",
            supplyCap: 0,
            symbol: "mweETH",
            underlying: 0x1Bf74C010E6320bab11e2e5A532b5AC15e0b8aA6,
            reserveFactor: reserveFactors["mweETH"],
            liquidationBonus: liquidationBonuses["mweETH"]
        });

        fullConfigs["mwrsETH"] = MarketRelease({
            borrowCap: borrowCaps["mwrsETH"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mwrsETH"],
            decimals: 18,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 3000002316638736000,
                kink: 400000000000000000,
                multiplier: 27999732233587200,
                name: "mwrsETH Interest Model"
            }),
            name: "mwrsETH",
            supplyCap: 0,
            symbol: "mwrsETH",
            underlying: 0xD2671165570f41BBB3B0097893300b6EB6101E6C,
            reserveFactor: reserveFactors["mwrsETH"],
            liquidationBonus: liquidationBonuses["mwrsETH"]
        });

        string memory marketsOutputPath = "script/deployment/mainnet/output/release-deployed-market-addresses.json";
        string memory rawMarketJson = vm.readFile(marketsOutputPath);
        uint256 length = 8;
        marketList = new address[](length);
        for (uint256 i; i < length; ++i) {
            string memory base = string.concat("[", vm.toString(i), "]");

            address marketAddr = vm.parseJsonAddress(rawMarketJson, string.concat(base, ".address"));
            marketList.push(marketAddr);
        }

        string memory corePath = "script/deployment/mainnet/output/release-deployed-core-addresses.json";
        string memory jsonContent = vm.readFile(corePath);
        console.logString(jsonContent);
        oracle = vm.parseJsonAddress(jsonContent, ".Oracle");
        operator = vm.parseJsonAddress(jsonContent, ".Operator");
        rolesContract = vm.parseJsonAddress(jsonContent, ".Roles");
    }

    function run() public {
        // Deploy to all networks
        for (uint256 i = 0; i < networks.length; i++) {
            string memory network = networks[i];
            console.log("\n=== Configuring %s ===", network);

            // Create fork for this network
            forks[network] = vm.createSelectFork(network);

            setRole = new SetRole();
            _setRoles(network);

            if (configs[network].isHost) {
                supportMarket = new SupportMarket();
                setCollateralFactor = new SetCollateralFactor();
                setBorrowRateMaxMantissa = new SetBorrowRateMaxMantissa();
                setBorrowCap = new SetBorrowCap();
                setSupplyCap = new SetSupplyCap();
                setReserveFactor = new SetReserveFactor();
                setFeed = new SetPriceFeedOnOracleV4();
                setLiquidationBonus = new SetLiquidationBonus();
                _configure(network);
            }

            console.log("-------------------- DONE");
        }
    }

    function _configure(string memory network) internal {
        uint256 feedsLength = feeds.length;
        for (uint256 i; i < feedsLength; ++i) {
            setFeed.run(oracle);
        }

        uint256 marketsLength = marketList.length;
        for (uint256 i; i < marketsLength; ++i) {
            MarketRelease storage mktRelease = fullConfigs[configs[network].markets[i].name];
            _configureMarket(marketList[i], mktRelease);
        }
    }

    function _configureMarket(address marketAddress, MarketRelease storage market) internal {
        // Configure market on host chain
        console.log("Configuring market", marketAddress);
        _configureMarket(
            marketAddress,
            market.liquidationBonus,
            market.reserveFactor,
            market.collateralFactor,
            market.borrowCap,
            market.supplyCap,
            market.borrowRateMaxMantissa
        );
        console.log("Market configured");
    }

    function _configureMarket(
        address market,
        uint256 liquidationBonus,
        uint256 reserveFactor,
        uint256 collateralFactor,
        uint256 borrowCap,
        uint256 supplyCap,
        uint256 borrowRateMaxMantissa
    ) internal {
        // Support market
        _supportMarket(market);

        // Set collateral factor
        _setCollateralFactor(market, collateralFactor);

        // Set borrow cap
        _setBorrowCap(market, borrowCap);

        // Set supply cap
        _setSupplyCap(market, supplyCap);

        // Set liquidation incentives
        _setLiquidationIncentive(market, liquidationBonus);

        // Set reserve factor
        _setReserveFactor(market, reserveFactor);

        // Set borrow rate max mantissa
        _setBorrowRateMaxMantissa(market, borrowRateMaxMantissa);
    }

    function _setRoles(string memory network) internal {
        uint256 rolesLength = configs[network].roles.length;
        for (uint256 i = 0; i < rolesLength; i++) {
            Role memory role = configs[network].roles[i];
            for (uint256 j = 0; j < role.accounts.length; j++) {
                setRole.run(rolesContract, role.accounts[j], keccak256(abi.encodePacked(role.roleName)), true);
            }
        }
    }

    function _supportMarket(address market) internal {
        supportMarket.run(operator, market);
    }

    function _setCollateralFactor(address market, uint256 collateralFactor) internal {
        setCollateralFactor.run(operator, market, collateralFactor);
    }

    function _setReserveFactor(address market, uint256 reserveFactor) internal {
        setReserveFactor.run(market, reserveFactor);
    }

    function _setLiquidationIncentive(address market, uint256 liquidationBonus) internal {
        setLiquidationBonus.run(operator, market, liquidationBonus);
    }

    function _setBorrowRateMaxMantissa(address market, uint256 borrowRateMaxMantissa) internal {
        setBorrowRateMaxMantissa.run(market, borrowRateMaxMantissa);
    }

    function _setBorrowCap(address market, uint256 borrowCap) internal {
        setBorrowCap.run(operator, market, borrowCap);
    }

    function _setSupplyCap(address market, uint256 supplyCap) internal {
        setSupplyCap.run(operator, market, supplyCap);
    }
}
