// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { CustomConfig } from "./config/CustomConfig.sol";
import { CErc20Delegator } from "../../src/contracts/CErc20Delegator.sol";
import { CErc20Delegate } from "../../src/contracts/CErc20Delegate.sol";
import { Comptroller } from "../../src/contracts/Comptroller.sol";
import { SimplePriceOracle } from "../../src/contracts/SimplePriceOracle.sol";
import { InterestRateModel } from "../../src/contracts/InterestRateModel.sol";
import { CLac } from "../../src/contracts/CLac.sol";
import { CToken } from "../../src/contracts/CToken.sol";
import { CTokenMock } from "../../test/mocks/CtokenMock.sol";
import { Config } from "./config/Config.sol";
import { console } from "forge-std/console.sol";

contract DeployCTokens is CustomConfig, Script {
    mapping(string => address) public cTokenAddresses;

    function run(
        address account,
        Config.DeployedProtocolContracts memory protocolContracts,
        Config.DeployedInterestRateModels memory interestRateModels,
        Config.DeployedUnderlyingTokens memory mockTokens
    ) external returns (Config.DeployedCTokens memory) {
        console.log("Deploying CTokens with account:", account);

        CTokenInfo[] memory configCtokens = getCTokens();

        vm.startBroadcast(account);

        for (uint256 i = 0; i < configCtokens.length; i++) {
            CTokenInfo memory c = configCtokens[i];

            if (keccak256(abi.encodePacked(c.args.symbol)) == keccak256(abi.encodePacked("caUXD"))) {
                c.args.underlying = mockTokens.uxd;
                c.args.interestRateModel = interestRateModels.iRM_UXD_Updateable;
            } else if (keccak256(abi.encodePacked(c.args.symbol)) == keccak256(abi.encodePacked("caWETH"))) {
                c.args.underlying = mockTokens.weth;
                c.args.interestRateModel = interestRateModels.iRM_WETH_Updateable;
            } else if (keccak256(abi.encodePacked(c.args.symbol)) == keccak256(abi.encodePacked("caLAC"))) {
                c.args.underlying = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
                c.args.interestRateModel = interestRateModels.iRM_LAC_Updateable;
            } else if (keccak256(abi.encodePacked(c.args.symbol)) == keccak256(abi.encodePacked("caWBTC"))) {
                c.args.underlying = mockTokens.wbtc;
                c.args.interestRateModel = interestRateModels.iRM_WBTC_Updateable;
            } else if (keccak256(abi.encodePacked(c.args.symbol)) == keccak256(abi.encodePacked("caUSDT"))) {
                c.args.underlying = mockTokens.usdt;
                c.args.interestRateModel = interestRateModels.iRM_USDT_Updateable;
            } else if (keccak256(abi.encodePacked(c.args.symbol)) == keccak256(abi.encodePacked("caUSDC"))) {
                c.args.underlying = mockTokens.usdc;
                c.args.interestRateModel = interestRateModels.iRM_USDC_Updateable;
            } else if (keccak256(abi.encodePacked(c.args.symbol)) == keccak256(abi.encodePacked("caMOCK"))) {
                c.args.underlying = mockTokens.mockUnderlying;
                c.args.interestRateModel = interestRateModels.iRM_MockCToken_Updateable;
            }
            c.args.unitroller = protocolContracts.unitroller;
            c.args.admin = account;

            // Deploy CTokens
            if (c.cTokenType == CTokenType.CErc20Delegator) {
                address implementation = address(new CErc20Delegate());
                CErc20Delegator cErc20Delegator = new CErc20Delegator(
                    c.args.underlying,
                    Comptroller(c.args.unitroller),
                    InterestRateModel(c.args.interestRateModel),
                    c.args.initialExchangeRateMantissa,
                    c.args.name,
                    c.args.symbol,
                    c.args.decimals,
                    payable(c.args.admin),
                    implementation,
                    ""
                );
                cTokenAddresses[c.args.symbol] = address(cErc20Delegator);
                setCtokenConfig(c, address(cErc20Delegator));
            } else if (c.cTokenType == CTokenType.CLAC) {
                CLac cLac = new CLac(
                    Comptroller(c.args.unitroller),
                    InterestRateModel(c.args.interestRateModel),
                    c.args.initialExchangeRateMantissa,
                    c.args.name,
                    c.args.symbol,
                    c.args.decimals,
                    payable(c.args.admin)
                );
                cTokenAddresses[c.args.symbol] = address(cLac);
                setCtokenConfig(c, address(cLac));
            } else if (c.cTokenType == CTokenType.CTokenMock) {
                address implementation = address(new CTokenMock());
                CErc20Delegator cTokenMock = new CErc20Delegator(
                    c.args.underlying,
                    Comptroller(c.args.unitroller),
                    InterestRateModel(c.args.interestRateModel),
                    c.args.initialExchangeRateMantissa,
                    c.args.name,
                    c.args.symbol,
                    c.args.decimals,
                    payable(c.args.admin),
                    implementation,
                    ""
                );
                cTokenAddresses[c.args.symbol] = address(cTokenMock);
            }
        }

        vm.stopBroadcast();

        return Config.DeployedCTokens({
            caUXD: cTokenAddresses["caUXD"],
            caWETH: cTokenAddresses["caWETH"],
            caLAC: cTokenAddresses["caLAC"],
            caWBTC: cTokenAddresses["caWBTC"],
            caUSDT: cTokenAddresses["caUSDT"],
            caUSDC: cTokenAddresses["caUSDC"],
            caMOCK: cTokenAddresses["caMOCK"]
        });
    }

    function setCtokenConfig(CTokenInfo memory _cToken, address _cTokenAddress) public {
        // Support market
        Comptroller comptroller = Comptroller(_cToken.args.unitroller);
        comptroller._supportMarket(CToken(_cTokenAddress));

        SimplePriceOracle priceOracle = SimplePriceOracle(address(comptroller.oracle()));

        // Set price oracle
        if (_cToken.cTokenType == CTokenType.CLAC) {
            priceOracle.setDirectPrice(_cToken.args.underlying, _cToken.config.underlyingPrice);
        } else {
            priceOracle.setUnderlyingPrice(CToken(_cTokenAddress), _cToken.config.underlyingPrice);
        }

        // Set collateral factor
        if (_cToken.config.collateralFactor > 0) {
            comptroller._setCollateralFactor(CToken(_cTokenAddress), _cToken.config.collateralFactor);
        }
    }
}
