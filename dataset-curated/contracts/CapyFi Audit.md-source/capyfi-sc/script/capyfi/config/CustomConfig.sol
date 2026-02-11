// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Config } from "./Config.sol";

contract CustomConfig is Config {
    function getInterestRateModels() public pure override returns (CInterestRateModel[] memory models) {
        models = new CInterestRateModel[](5);

        models[0] = (
            CInterestRateModel({
                name: "IRM_UXD_Updateable",
                modelType: InterestRateModelType.JumpRateModelV2,
                args: InterestRateModelArgs({
                    baseRatePerYear: 0,
                    multiplierPerYear: 0.04e18,
                    jumpMultiplierPerYear: 1.09e18,
                    kink: 0.8e18,
                    owner: 0x0000000000000000000000000000000000000000
                })
            })
        );

        models[1] = (
            CInterestRateModel({
                name: "IRM_WETH_Updateable",
                modelType: InterestRateModelType.JumpRateModelV2,
                args: InterestRateModelArgs({
                    baseRatePerYear: 0.02e18,
                    multiplierPerYear: 0.18e18,
                    jumpMultiplierPerYear: 6e18,
                    kink: 0.8e18,
                    owner: 0x0000000000000000000000000000000000000000
                })
            })
        );

        models[2] = (
            CInterestRateModel({
                name: "IRM_LAC_Updateable",
                modelType: InterestRateModelType.JumpRateModelV2,
                args: InterestRateModelArgs({
                    baseRatePerYear: 0.02e18,
                    multiplierPerYear: 0.28e18,
                    jumpMultiplierPerYear: 6e18,
                    kink: 0.8e18,
                    owner: 0x0000000000000000000000000000000000000000
                })
            })
        );

        models[3] = (
            CInterestRateModel({
                name: "IRM_WBTC_Updateable",
                modelType: InterestRateModelType.JumpRateModelV2,
                args: InterestRateModelArgs({
                    baseRatePerYear: 0,
                    multiplierPerYear: 0.015e18,
                    jumpMultiplierPerYear: 1e18,
                    kink: 0.8e18,
                    owner: 0x0000000000000000000000000000000000000000
                })
            })
        );

        models[4] = (
            CInterestRateModel({
                name: "IRM_MockCToken_Updateable",
                modelType: InterestRateModelType.JumpRateModelV2,
                args: InterestRateModelArgs({
                    baseRatePerYear: 0,
                    multiplierPerYear: 0.1e18,
                    jumpMultiplierPerYear: 1.09e18,
                    kink: 0.8e18,
                    owner: 0x0000000000000000000000000000000000000000
                })
            })
        );

        return models;
    }

    function getCTokens() public pure override returns (CTokenInfo[] memory cTokens) {
        cTokens = new CTokenInfo[](5);
        cTokens[0] = (
            CTokenInfo({
                cTokenType: CTokenType.CErc20Delegator,
                args: CTokenArgs({
                    underlying: 0x0000000000000000000000000000000000000000,
                    unitroller: 0x0000000000000000000000000000000000000000,
                    interestRateModel: 0x0000000000000000000000000000000000000000,
                    initialExchangeRateMantissa: 200_000_000_000_000_000_000_000_000,
                    name: "Capyfi Criptodolar UXD",
                    symbol: "caUXD",
                    decimals: 8,
                    admin: 0x0000000000000000000000000000000000000000,
                    implementation: 0x0000000000000000000000000000000000000000
                }),
                config: CtokenConfig({
                    collateralFactor: 0,
                    underlyingPrice: 1_000_000_000_000_000_000,
                    reserveFactor: 0.075e18,
                    chainlinkOracleConfig: chainlinkOracleConfig({
                        underlyingAssetDecimals: 0,
                        priceFeed: 0x0000000000000000000000000000000000000000,
                        fixedPrice: 0
                    })
                })
            })
        );

        cTokens[1] = (
            CTokenInfo({
                cTokenType: CTokenType.CLAC,
                args: CTokenArgs({
                    underlying: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
                    unitroller: 0x0000000000000000000000000000000000000000,
                    interestRateModel: 0x0000000000000000000000000000000000000000,
                    initialExchangeRateMantissa: 200_000_000_000_000_000_000_000_000,
                    name: "Capyfi La Coin",
                    symbol: "caLAC",
                    decimals: 8,
                    admin: 0x0000000000000000000000000000000000000000,
                    implementation: 0x0000000000000000000000000000000000000000
                }),
                config: CtokenConfig({
                    collateralFactor: 0.75e18,
                    underlyingPrice: 12_548_500_000_000_000,
                    reserveFactor: 0.5e18,
                    chainlinkOracleConfig: chainlinkOracleConfig({
                        underlyingAssetDecimals: 0,
                        priceFeed: 0x0000000000000000000000000000000000000000,
                        fixedPrice: 0
                    })
                })
            })
        );

        cTokens[2] = (
            CTokenInfo({
                cTokenType: CTokenType.CErc20Delegator,
                args: CTokenArgs({
                    underlying: 0x0000000000000000000000000000000000000000,
                    unitroller: 0x0000000000000000000000000000000000000000,
                    interestRateModel: 0x0000000000000000000000000000000000000000,
                    initialExchangeRateMantissa: 200_000_000_000_000_000_000_000_000,
                    name: "Capyfi Wrapped Ether",
                    symbol: "caWETH",
                    decimals: 8,
                    admin: 0x0000000000000000000000000000000000000000,
                    implementation: 0x0000000000000000000000000000000000000000
                }),
                config: CtokenConfig({
                    collateralFactor: 0.825e18,
                    underlyingPrice: 2_504_640_000_000_000_000_000,
                    reserveFactor: 0.2e18,
                    chainlinkOracleConfig: chainlinkOracleConfig({
                        underlyingAssetDecimals: 0,
                        priceFeed: 0x0000000000000000000000000000000000000000,
                        fixedPrice: 0
                    })
                })
            })
        );

        cTokens[3] = (
            CTokenInfo({
                cTokenType: CTokenType.CErc20Delegator,
                args: CTokenArgs({
                    underlying: 0x0000000000000000000000000000000000000000,
                    unitroller: 0x0000000000000000000000000000000000000000,
                    interestRateModel: 0x0000000000000000000000000000000000000000,
                    initialExchangeRateMantissa: 20_000_000_000_000_000,
                    name: "Capyfi Wrapped Bitcoin",
                    symbol: "caWBTC",
                    decimals: 8,
                    admin: 0x0000000000000000000000000000000000000000,
                    implementation: 0x0000000000000000000000000000000000000000
                }),
                config: CtokenConfig({
                    collateralFactor: 0.7e18,
                    underlyingPrice: 589_166_300_000_000_000_000_000_000_000_000,
                    reserveFactor: 0.2e18,
                    chainlinkOracleConfig: chainlinkOracleConfig({
                        underlyingAssetDecimals: 8,
                        priceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                        fixedPrice: 0
                    })
                })
            })
        );

        cTokens[4] = (
            CTokenInfo({
                cTokenType: CTokenType.CTokenMock,
                args: CTokenArgs({
                    underlying: 0x0000000000000000000000000000000000000000,
                    unitroller: 0x0000000000000000000000000000000000000000,
                    interestRateModel: 0x0000000000000000000000000000000000000000,
                    initialExchangeRateMantissa: 200_000_000_000_000_000_000_000_000,
                    name: "Mock CToken",
                    symbol: "caMOCK",
                    decimals: 8,
                    admin: 0x0000000000000000000000000000000000000000,
                    implementation: 0x0000000000000000000000000000000000000000
                }),
                config: CtokenConfig({
                    collateralFactor: 0,
                    underlyingPrice: 1_000_000_000_000_000_000,
                    reserveFactor: 0.075e18,
                    chainlinkOracleConfig: chainlinkOracleConfig({
                        underlyingAssetDecimals: 0,
                        priceFeed: 0x0000000000000000000000000000000000000000,
                        fixedPrice: 0
                    })
                })
            })
        );

        return cTokens;
    }

    function getERC20s() public pure override returns (ERC20Args[] memory erc20s) {
        erc20s = new ERC20Args[](4);
        erc20s[0] = (
            ERC20Args({
                initialOwner: 0x0000000000000000000000000000000000000000,
                name: "Criptodolar UXD",
                symbol: "UXD",
                initialSupply: 1_000_000e18,
                decimals: 18
            })
        );

        erc20s[1] = (
            ERC20Args({
                initialOwner: 0x0000000000000000000000000000000000000000,
                name: "Wrapped Ether",
                symbol: "WETH",
                initialSupply: 1_000_000e18,
                decimals: 18
            })
        );

        erc20s[2] = (
            ERC20Args({
                initialOwner: 0x0000000000000000000000000000000000000000,
                name: "Wrapped Bitcoin",
                symbol: "WBTC",
                initialSupply: 1_000_000e8,
                decimals: 8
            })
        );

        erc20s[3] = (
            ERC20Args({
                initialOwner: 0x0000000000000000000000000000000000000000,
                name: "Mock Token",
                symbol: "MOCK",
                initialSupply: 1_000_000e18,
                decimals: 18
            })
        );

        return erc20s;
    }

    function getCapyfiAggregators() public pure override returns (CapyfiAggregatorConfig[] memory) {
        CapyfiAggregatorConfig[] memory aggregators = new CapyfiAggregatorConfig[](2);
        
        // UXD Aggregator Configuration
        aggregators[0] = CapyfiAggregatorConfig({
            symbol: "UXD",
            description: "UXD/USD Price Feed (Test)",
            decimals: 8,
            version: 1,
            initialPrice: 1e8  
        });
        
        // LAC Aggregator Configuration  
        aggregators[1] = CapyfiAggregatorConfig({
            symbol: "LAC",
            description: "LAC/USD Price Feed (Test)",
            decimals: 8,
            version: 1,
            initialPrice: 11e5 
        });
        
        return aggregators;
    }
}