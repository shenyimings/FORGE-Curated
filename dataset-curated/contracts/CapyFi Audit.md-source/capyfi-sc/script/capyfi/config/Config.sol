// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

abstract contract Config {
    struct DeployedProtocolContracts {
        address unitroller;
        address comptroller;
        address priceOracle;
    }

    struct DeployedInterestRateModels {
        address iRM_UXD_Updateable;
        address iRM_WETH_Updateable;
        address iRM_LAC_Updateable;
        address iRM_WBTC_Updateable;
        address iRM_USDT_Updateable;
        address iRM_USDC_Updateable;
        address iRM_MockCToken_Updateable;
    }

    struct DeployedUnderlyingTokens {
        address uxd;
        address weth;
        address wbtc;
        address usdt;
        address usdc;
        address mockUnderlying;
        address lac;
    }

    struct DeployedCTokens {
        address caUXD;
        address caWETH;
        address caLAC;
        address caWBTC;
        address caUSDT;
        address caUSDC;
        address caMOCK;
    }

    enum InterestRateModelType {
        WhitePaperInterestRateModel,
        JumpRateModelV2,
        LegacyJumpRateModelV2
    }

    struct InterestRateModelArgs {
        uint256 baseRatePerYear;
        uint256 multiplierPerYear;
        uint256 jumpMultiplierPerYear;
        uint256 kink;
        address owner;
    }

    struct CInterestRateModel {
        string name;
        InterestRateModelType modelType;
        InterestRateModelArgs args;
    }

    enum CTokenType {
        CErc20Delegator,
        CErc20,
        CLAC,
        CTokenMock,
        CEther
    }

    struct CTokenArgs {
        address underlying;
        address unitroller;
        address interestRateModel;
        uint256 initialExchangeRateMantissa;
        string name;
        string symbol;
        uint8 decimals;
        address admin;
        address implementation;
    }

    struct CTokenInfo {
        CTokenType cTokenType;
        CTokenArgs args;
        CtokenConfig config;
    }

    struct ERC20Args {
        address initialOwner;
        string name;
        string symbol;
        uint256 initialSupply;
        uint8 decimals;
    }

    struct chainlinkOracleConfig {
        uint8 underlyingAssetDecimals;
        address priceFeed;
        uint256 fixedPrice;
    }

    struct CtokenConfig {
        uint256 collateralFactor;
        uint256 underlyingPrice;
        uint256 reserveFactor;
        chainlinkOracleConfig chainlinkOracleConfig;
    }

    struct CapyfiAggregatorConfig {
        string symbol;
        string description;
        uint8 decimals;
        uint256 version;
        int256 initialPrice;
    }

    function getInterestRateModels() public virtual returns (CInterestRateModel[] memory);

    function getCTokens() public virtual returns (CTokenInfo[] memory);

    function getERC20s() public virtual returns (ERC20Args[] memory);

    function getCapyfiAggregators() public virtual returns (CapyfiAggregatorConfig[] memory);
}