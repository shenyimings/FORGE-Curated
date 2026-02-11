// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {CrossChainMultisig, CrossChainCall} from "../../global/CrossChainMultisig.sol";
import {InstanceManager} from "../../instance/InstanceManager.sol";
import {PriceFeedStore} from "../../instance/PriceFeedStore.sol";
import {IBytecodeRepository} from "../../interfaces/IBytecodeRepository.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {IInstanceManager} from "../../interfaces/IInstanceManager.sol";
import {IConfigureActions} from "../../factories/CreditFactory.sol";

import {IWETH} from "@gearbox-protocol/core-v3/contracts/interfaces/external/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {
    AP_PRICE_FEED_STORE,
    AP_INSTANCE_MANAGER_PROXY,
    AP_INTEREST_RATE_MODEL_FACTORY,
    AP_CREDIT_FACTORY,
    AP_POOL_FACTORY,
    AP_PRICE_ORACLE_FACTORY,
    AP_RATE_KEEPER_FACTORY,
    AP_MARKET_CONFIGURATOR_FACTORY,
    AP_LOSS_POLICY_FACTORY,
    AP_GOVERNOR,
    AP_POOL,
    AP_POOL_QUOTA_KEEPER,
    AP_PRICE_ORACLE,
    AP_MARKET_CONFIGURATOR,
    AP_ACL,
    AP_CONTRACTS_REGISTER,
    AP_INTEREST_RATE_MODEL_LINEAR,
    AP_RATE_KEEPER_TUMBLER,
    AP_RATE_KEEPER_GAUGE,
    AP_LOSS_POLICY_DEFAULT,
    AP_CREDIT_MANAGER,
    AP_CREDIT_FACADE,
    AP_CREDIT_CONFIGURATOR,
    NO_VERSION_CONTROL
} from "../../libraries/ContractLiterals.sol";
import {SignedProposal, Bytecode} from "../../interfaces/Types.sol";

import {CreditFactory} from "../../factories/CreditFactory.sol";
import {InterestRateModelFactory} from "../../factories/InterestRateModelFactory.sol";
import {LossPolicyFactory} from "../../factories/LossPolicyFactory.sol";
import {PoolFactory} from "../../factories/PoolFactory.sol";
import {PriceOracleFactory} from "../../factories/PriceOracleFactory.sol";
import {RateKeeperFactory} from "../../factories/RateKeeperFactory.sol";

import {MarketConfigurator} from "../../market/MarketConfigurator.sol";
import {MarketConfiguratorFactory} from "../../instance/MarketConfiguratorFactory.sol";
import {ACL} from "../../market/ACL.sol";
import {ContractsRegister} from "../../market/ContractsRegister.sol";
import {Governor} from "../../market/Governor.sol";

import {PoolV3} from "@gearbox-protocol/core-v3/contracts/pool/PoolV3.sol";
import {PoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/pool/PoolQuotaKeeperV3.sol";
import {PriceOracleV3} from "@gearbox-protocol/core-v3/contracts/core/PriceOracleV3.sol";
import {LinearInterestRateModelV3} from "@gearbox-protocol/core-v3/contracts/pool/LinearInterestRateModelV3.sol";
import {TumblerV3} from "@gearbox-protocol/core-v3/contracts/pool/TumblerV3.sol";
import {GaugeV3} from "@gearbox-protocol/core-v3/contracts/pool/GaugeV3.sol";
import {DefaultLossPolicy} from "../../helpers/DefaultLossPolicy.sol";
import {CreditManagerV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditManagerV3.sol";
import {CreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditFacadeV3.sol";
import {CreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditConfiguratorV3.sol";

import {DeployParams} from "../../interfaces/Types.sol";
import {CreditFacadeParams, CreditManagerParams} from "../../factories/CreditFactory.sol";

import {GlobalSetup} from "../../test/helpers/GlobalSetup.sol";

contract NewChainDeploySuite is Test, GlobalSetup {
    address internal riskCurator;

    address constant TREASURY = 0x3E965117A51186e41c2BB58b729A1e518A715e5F;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant GEAR = 0xBa3335588D9403515223F109EdC4eB7269a9Ab5D;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant CHAINLINK_USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    string constant name = "Test Market ETH";
    string constant symbol = "dETH";

    function setUp() public {
        // simulate chainId 1
        if (block.chainid != 1) {
            vm.chainId(1);
        }

        _setUpGlobalContracts();

        // activate instance
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = _generateActivateCall(1, instanceOwner, TREASURY, WETH, GEAR);
        _submitProposalAndSign("Activate instance", calls);

        // Configure instance
        _setupPriceFeedStore();
        riskCurator = vm.addr(_generatePrivateKey("RISK_CURATOR"));
    }

    function _setupPriceFeedStore() internal {
        _addPriceFeed(CHAINLINK_ETH_USD, 1 days);
        _addPriceFeed(CHAINLINK_USDC_USD, 1 days);

        _allowPriceFeed(WETH, CHAINLINK_ETH_USD);
        _allowPriceFeed(USDC, CHAINLINK_USDC_USD);
    }

    function test_NCD_01_createMarket() public {
        address ap = instanceManager.addressProvider();

        address mcf = IAddressProvider(ap).getAddressOrRevert(AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL);

        address poolFactory = IAddressProvider(ap).getAddressOrRevert(AP_POOL_FACTORY, 3_10);

        IWETH(WETH).deposit{value: 1e18}();
        IERC20(WETH).transfer(poolFactory, 1e18);

        uint256 gasBefore = gasleft();

        vm.startPrank(riskCurator);
        address mc = MarketConfiguratorFactory(mcf).createMarketConfigurator(
            riskCurator, riskCurator, riskCurator, "Test Risk Curator", false
        );

        uint256 gasAfter = gasleft();
        uint256 used = gasBefore - gasAfter;
        console.log("createMarketConfigurator gasUsed", used);

        address pool = MarketConfigurator(mc).previewCreateMarket(3_10, WETH, name, symbol);

        DeployParams memory interestRateModelParams = DeployParams({
            postfix: "LINEAR",
            salt: 0,
            constructorParams: abi.encode(100, 200, 100, 100, 200, 300, false)
        });
        DeployParams memory rateKeeperParams =
            DeployParams({postfix: "TUMBLER", salt: 0, constructorParams: abi.encode(pool, 7 days)});
        DeployParams memory lossPolicyParams =
            DeployParams({postfix: "DEFAULT", salt: 0, constructorParams: abi.encode(pool, ap)});

        gasBefore = gasleft();

        address poolFromMarket = MarketConfigurator(mc).createMarket({
            minorVersion: 3_10,
            underlying: WETH,
            name: name,
            symbol: symbol,
            interestRateModelParams: interestRateModelParams,
            rateKeeperParams: rateKeeperParams,
            lossPolicyParams: lossPolicyParams,
            underlyingPriceFeed: CHAINLINK_ETH_USD
        });

        gasAfter = gasleft();
        used = gasBefore - gasAfter;
        console.log("createMarket gasUsed", used);

        assertEq(pool, poolFromMarket);

        DeployParams memory accountFactoryParams =
            DeployParams({postfix: "DEFAULT", salt: 0, constructorParams: abi.encode(ap)});
        CreditManagerParams memory creditManagerParams = CreditManagerParams({
            maxEnabledTokens: 4,
            feeInterest: 10_00,
            feeLiquidation: 1_50,
            liquidationPremium: 1_50,
            feeLiquidationExpired: 1_50,
            liquidationPremiumExpired: 1_50,
            minDebt: 1e18,
            maxDebt: 20e18,
            name: "Credit Manager ETH",
            accountFactoryParams: accountFactoryParams
        });

        CreditFacadeParams memory facadeParams =
            CreditFacadeParams({degenNFT: address(0), expirable: false, migrateBotList: false});

        bytes memory creditSuiteParams = abi.encode(creditManagerParams, facadeParams);

        address cm = MarketConfigurator(mc).createCreditSuite(3_10, pool, creditSuiteParams);

        address balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

        MarketConfigurator(mc).configureCreditSuite(
            cm,
            abi.encodeCall(
                IConfigureActions.allowAdapter, (DeployParams("BALANCER_VAULT", 0, abi.encode(cm, balancerVault)))
            )
        );

        vm.stopPrank();
    }
}
