// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Config } from "./Config.sol";


contract ProdConfig is Config {
    address constant MULTISIG_ADDRESS = 0x6C15e4Bc44CC5674b1d7956D0e9596d2E509eD24;

    function getInterestRateModels() public pure override returns (CInterestRateModel[] memory models) {
        models = new CInterestRateModel[](6);

        models[0] = (
            CInterestRateModel({
                name: "IRM_UXD_Updateable",
                modelType: InterestRateModelType.JumpRateModelV2,
                args: InterestRateModelArgs({
                    baseRatePerYear: 0,
                    multiplierPerYear: 0.15e18,
                    jumpMultiplierPerYear: 1.09e18,
                    kink: 0.8e18,
                    owner: MULTISIG_ADDRESS
                })
            })
        );

        models[1] = (
            CInterestRateModel({
                name: "IRM_WETH_Updateable",
                modelType: InterestRateModelType.JumpRateModelV2,
                args: InterestRateModelArgs({
                    baseRatePerYear: 0,
                    multiplierPerYear: 0.05e18,
                    jumpMultiplierPerYear: 6e18,
                    kink: 0.8e18,
                    owner: MULTISIG_ADDRESS
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
                    owner: MULTISIG_ADDRESS
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
                    owner: MULTISIG_ADDRESS
                })
            })
        );

        models[4] = (
            CInterestRateModel({
                name: "IRM_USDT_Updateable",
                modelType: InterestRateModelType.JumpRateModelV2,
                args: InterestRateModelArgs({
                    baseRatePerYear: 0,
                    multiplierPerYear: 0.08e18,
                    jumpMultiplierPerYear: 1.09e18,
                    kink: 0.8e18,
                    owner: MULTISIG_ADDRESS
                })
            })
        );

        models[5] = (
            CInterestRateModel({
                name: "IRM_USDC_Updateable",
                modelType: InterestRateModelType.JumpRateModelV2,
                args: InterestRateModelArgs({
                    baseRatePerYear: 0,
                    multiplierPerYear: 0.08e18,
                    jumpMultiplierPerYear: 1.09e18,
                    kink: 0.8e18,
                    owner: MULTISIG_ADDRESS
                })
            })
        );

        return models;
    }

    function getCTokens() public pure override returns (CTokenInfo[] memory cTokens) {
        cTokens = new CTokenInfo[](6);
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
                        underlyingAssetDecimals: 18,
                        priceFeed: 0x0000000000000000000000000000000000000000,
                        fixedPrice: 1000000000000000000
                    })
                })
            })
        );

        cTokens[1] = (
            CTokenInfo({
                cTokenType: CTokenType.CErc20Delegator,
                args: CTokenArgs({
                    underlying: 0x0000000000000000000000000000000000000000,
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
                    collateralFactor: 0.5e18,
                    underlyingPrice: 11_548_500_000_000_000,
                    reserveFactor: 0.5e18,
                    chainlinkOracleConfig: chainlinkOracleConfig({
                        underlyingAssetDecimals: 18,
                        priceFeed: 0x0000000000000000000000000000000000000000,
                        fixedPrice: 11620000000000000
                    })
                })
            })
        );

        cTokens[2] = (
            CTokenInfo({
                cTokenType: CTokenType.CEther,
                args: CTokenArgs({
                    underlying: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
                    unitroller: 0x0000000000000000000000000000000000000000,
                    interestRateModel: 0x0000000000000000000000000000000000000000,
                    initialExchangeRateMantissa: 200_000_000_000_000_000_000_000_000,
                    name: "Capyfi Ether",
                    symbol: "caWETH",
                    decimals: 8,
                    admin: 0x0000000000000000000000000000000000000000,
                    implementation: 0x0000000000000000000000000000000000000000
                }),
                config: CtokenConfig({
                    collateralFactor: 0.8e18,
                    underlyingPrice: 2_654_640_000_000_000_000_000,
                    reserveFactor: 0.1e18,
                    chainlinkOracleConfig: chainlinkOracleConfig({
                        underlyingAssetDecimals: 18,
                        priceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
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
                    collateralFactor: 0.8e18,
                    underlyingPrice: 969_166_300_000_000_000_000_000_000_000_000,
                    reserveFactor: 0.1e18,
                    chainlinkOracleConfig: chainlinkOracleConfig({
                        underlyingAssetDecimals: 8,
                        priceFeed: 0x45939657d1CA34A8FA39A924B71D28Fe8431e581,
                        fixedPrice: 0
                    })
                })
            })
        );

        cTokens[4] = (
            CTokenInfo({
                cTokenType: CTokenType.CErc20Delegator,
                args: CTokenArgs({
                    underlying: 0x0000000000000000000000000000000000000000,
                    unitroller: 0x0000000000000000000000000000000000000000,
                    interestRateModel: 0x0000000000000000000000000000000000000000,
                    initialExchangeRateMantissa: 200000000000000,
                    name: "Capyfi USDT",
                    symbol: "caUSDT",
                    decimals: 8,
                    admin: 0x0000000000000000000000000000000000000000,
                    implementation: 0x0000000000000000000000000000000000000000
                }),
                config: CtokenConfig({
                    collateralFactor: 0,
                    underlyingPrice: 1000000000000000000000000000000,
                    reserveFactor: 0.15e18,
                    chainlinkOracleConfig: chainlinkOracleConfig({
                        underlyingAssetDecimals: 6,
                        priceFeed: 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D,
                        fixedPrice: 0
                    })
                })
            })
        );

        cTokens[5] = (
            CTokenInfo({
                cTokenType: CTokenType.CErc20Delegator,
                args: CTokenArgs({
                    underlying: 0x0000000000000000000000000000000000000000,
                    unitroller: 0x0000000000000000000000000000000000000000,
                    interestRateModel: 0x0000000000000000000000000000000000000000,
                    initialExchangeRateMantissa: 200000000000000,
                    name: "Capyfi USDC",
                    symbol: "caUSDC",
                    decimals: 8,
                    admin: 0x0000000000000000000000000000000000000000,
                    implementation: 0x0000000000000000000000000000000000000000
                }),
                config: CtokenConfig({
                    collateralFactor: 0,
                    underlyingPrice: 1000000000000000000000000000000,
                    reserveFactor: 0.15e18,
                    chainlinkOracleConfig: chainlinkOracleConfig({
                        underlyingAssetDecimals: 6,
                        priceFeed: 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6,
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
            description: "UXD/USD Price Feed",
            decimals: 8,
            version: 1,
            initialPrice: 99962650  
        });
        
        // LAC Aggregator Configuration  
        aggregators[1] = CapyfiAggregatorConfig({
            symbol: "LAC",
            description: "LAC/USD Price Feed",
            decimals: 8,
            version: 1,
            initialPrice: 1002300 
        });
        
        return aggregators;
    }
}