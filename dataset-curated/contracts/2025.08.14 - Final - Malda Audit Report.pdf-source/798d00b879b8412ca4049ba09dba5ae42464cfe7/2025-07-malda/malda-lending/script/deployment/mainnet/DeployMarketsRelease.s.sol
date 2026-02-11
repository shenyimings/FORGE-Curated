// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {Operator} from "src/Operator/Operator.sol";
import {mErc20Host} from "src/mToken/host/mErc20Host.sol";
import {Roles} from "src/Roles.sol";
import {IPauser} from "src/interfaces/IPauser.sol";
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
import {DeployHostMarket} from "../markets/host/DeployHostMarket.s.sol";
import {DeployExtensionMarket} from "../markets/extension/DeployExtensionMarket.s.sol";
import {DeployJumpRateModelV4} from "../interest/DeployJumpRateModelV4.s.sol";
import {UpdateAllowedChains} from "../../configuration/UpdateAllowedChains.s.sol";
import {SetGasHelper} from "../../configuration/SetGasHelper.s.sol";

contract DeployMarketsRelease is DeployBaseRelease {
    using stdJson for string;

    error UnsupportedOracleType();

    address marketAddress;
    address[] marketAddresses;
    address[] extensionMarketAddresses;
    address owner;

    mapping(string => MarketRelease) public fullConfigs;

    address rolesContract;
    address zkVerifier;
    address operator;
    address oracle;
    address pauser;
    address gasHelper;

    Deployer deployer;

    DeployJumpRateModelV4 deployInterest;
    DeployHostMarket deployHost;
    DeployExtensionMarket deployExt;
    UpdateAllowedChains updateAllowedChains;
    SetGasHelper setGasHelper;

    function setUp() public override {
        configPath = "deployment-config-release.json";
        super.setUp();

        // full configs
        fullConfigs["mUSDC"] = MarketRelease({
            borrowCap: 0,
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: 0,
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
            reserveFactor: 0,
            liquidationBonus: 0
        });

        fullConfigs["mWETH"] = MarketRelease({
            borrowCap: 0,
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: 0,
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
            reserveFactor: 0,
            liquidationBonus: 0
        });

        fullConfigs["mUSDT"] = MarketRelease({
            borrowCap: 0,
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: 0,
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
            reserveFactor: 0,
            liquidationBonus: 0
        });

        fullConfigs["mWBTC"] = MarketRelease({
            borrowCap: 0,
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: 0,
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
            reserveFactor: 0,
            liquidationBonus: 0
        });

        fullConfigs["mwstETH"] = MarketRelease({
            borrowCap: 0,
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: 0,
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
            reserveFactor: 0,
            liquidationBonus: 0
        });

        fullConfigs["mezETH"] = MarketRelease({
            borrowCap: 0,
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: 0,
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
            reserveFactor: 0,
            liquidationBonus: 0
        });

        fullConfigs["mweETH"] = MarketRelease({
            borrowCap: 0,
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: 0,
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
            reserveFactor: 0,
            liquidationBonus: 0
        });

        fullConfigs["mwrsETH"] = MarketRelease({
            borrowCap: 0,
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: 0,
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
            reserveFactor: 0,
            liquidationBonus: 0
        });
    }

    function run() public {
        string memory corePath = "script/deployment/mainnet/output/release-deployed-core-addresses.json";
        string memory jsonContent = vm.readFile(corePath);
        console.logString(jsonContent);

        rolesContract = vm.parseJsonAddress(jsonContent, ".Roles");
        zkVerifier = vm.parseJsonAddress(jsonContent, ".ZkVerifier");
        operator = vm.parseJsonAddress(jsonContent, ".Operator");
        oracle = vm.parseJsonAddress(jsonContent, ".Oracle");
        pauser = vm.parseJsonAddress(jsonContent, ".Pauser");
        gasHelper = vm.parseJsonAddress(jsonContent, ".DefaultGasHelper");
        deployer = Deployer(payable(vm.parseJsonAddress(jsonContent, ".Deployer")));

        delete marketAddresses;
        delete extensionMarketAddresses;

        // Deploy to all networks
        for (uint256 i = 0; i < networks.length; i++) {
            string memory network = networks[i];
            console.log("\n=== Deploying to %s ===", network);

            // Create fork for this network
            forks[network] = vm.createSelectFork(network);

            owner = configs[network].deployer.owner;

            if (configs[network].isHost) {
                deployInterest = new DeployJumpRateModelV4();
                deployHost = new DeployHostMarket();
                updateAllowedChains = new UpdateAllowedChains();
                setGasHelper = new SetGasHelper();

                console.log("Deploying host chain");
                _deployHostChain(network);
            } else {
                deployExt = new DeployExtensionMarket();
                console.log("Deploying extension chain");
                _deployExtensionChain(network);
            }

            console.log("-------------------- DONE");
        }

        marketAddresses.push(address(0x1));
        marketAddresses.push(address(0x2));
        marketAddresses.push(address(0x3));
        string memory outputPath = "script/deployment/mainnet/output/release-deployed-market-addresses.json";
        string memory json = "[";
        for (uint256 i; i < marketAddresses.length; ++i) {
            address addr = marketAddresses[i];

            // Check if it's in extensionMarketAddresses
            bool isExtension = false;
            for (uint256 j; j < extensionMarketAddresses.length; ++j) {
                if (addr == extensionMarketAddresses[j]) {
                    isExtension = true;
                    break;
                }
            }

            string memory obj;
            if (isExtension) {
                obj = string(abi.encodePacked('{"address":"', vm.toString(addr), '","isExtension":true}'));
            } else {
                obj = string(abi.encodePacked('{"address":"', vm.toString(addr), '"}'));
            }

            json = string(abi.encodePacked(json, obj));
            if (i < marketAddresses.length - 1) {
                json = string(abi.encodePacked(json, ","));
            }
        }
        json = string(abi.encodePacked(json, "]"));
        vm.writeFile(outputPath, json);
    }

    function _deployHostChain(string memory network) internal {
        uint256 marketsLength = configs[network].markets.length;
        for (uint256 i; i < marketsLength;) {
            _deployAndConfigureMarket(true, configs[network].markets[i], network);
            unchecked {
                ++i;
            }
        }
    }

    function _deployExtensionChain(string memory network) internal {
        uint256 marketsLength = configs[network].markets.length;
        for (uint256 i; i < marketsLength;) {
            _deployAndConfigureMarket(false, configs[network].markets[i], network);
            unchecked {
                ++i;
            }
        }

        //
    }

    function _deployAndConfigureMarket(bool isHost, MarketRelease memory market, string memory network) internal {
        address interestModel;

        // Deploy interest model only for host chain
        if (isHost) {
            market = fullConfigs[market.name];
            interestModel = _deployInterestModel(market.interestModel);
        }
        uint256 key = vm.envUint("PRIVATE_KEY");

        // Deploy proxy for market
        if (isHost) {
            marketAddress = _deployHostMarket(deployer, market, interestModel);

            _setDefaultGasHelper(marketAddress);

            marketAddresses.push(marketAddress);

            console.log(" -- adding HOST market to pausable contract");
            vm.startBroadcast(key);
            Pauser(pauser).addPausableMarket(marketAddress, IPauser.PausableType.Host);
            vm.stopBroadcast();
        } else {
            marketAddress = _deployExtensionMarket(deployer, market);
            marketAddresses.push(marketAddress);
            extensionMarketAddresses.push(marketAddress);

            console.log(" -- adding EXTENSION market to pausable contract");
            vm.startBroadcast(key);
            Pauser(pauser).addPausableMarket(marketAddress, IPauser.PausableType.Extension);
            vm.stopBroadcast();
        }

        // Configure market if host chain
        if (isHost) {
            // Setup allowed chains on host market
            _updateAllowedChains(marketAddress, network);
        }
    }

    function _deployInterestModel(InterestConfig memory modelConfig) internal returns (address) {
        return deployInterest.run(
            deployer,
            DeployJumpRateModelV4.InterestData({
                kink: modelConfig.kink,
                name: modelConfig.name,
                blocksPerYear: modelConfig.blocksPerYear,
                baseRatePerYear: modelConfig.baseRate,
                multiplierPerYear: modelConfig.multiplier,
                jumpMultiplierPerYear: modelConfig.jumpMultiplier
            }),
            owner
        );
    }

    function _deployHostMarket(Deployer _deployer, MarketRelease memory market, address interestModel)
        internal
        returns (address)
    {
        return deployHost.run(
            _deployer,
            DeployHostMarket.MarketData({
                underlyingToken: market.underlying,
                operator: operator,
                interestModel: interestModel,
                exchangeRateMantissa: uint256(2e16),
                name: market.name,
                symbol: market.symbol,
                decimals: market.decimals,
                owner: owner,
                zkVerifier: zkVerifier,
                roles: rolesContract
            })
        );
    }

    function _deployExtensionMarket(Deployer _deployer, MarketRelease memory market) internal returns (address) {
        return deployExt.run(_deployer, market.underlying, market.name, owner, zkVerifier, rolesContract);
    }

    function _updateAllowedChains(address market, string memory network) internal {
        // Allow chains in host market
        for (uint256 i = 0; i < configs[network].allowedChains.length; i++) {
            vm.startBroadcast(key);
            mErc20Host(market).updateAllowedChain(configs[network].allowedChains[i], true);
            vm.stopBroadcast();
        }
    }

    function _setDefaultGasHelper(address market) internal {
        setGasHelper.run(market, gasHelper);
    }
}
