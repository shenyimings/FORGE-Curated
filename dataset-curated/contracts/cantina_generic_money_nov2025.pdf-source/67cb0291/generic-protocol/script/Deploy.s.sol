// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { Controller } from "../src/controller/Controller.sol";
import { BaseController, IChainlinkAggregatorLike } from "../src/controller/BaseController.sol";
import { GenericUSD } from "../src/GenericUSD.sol";
import { GenericUnit } from "../src/unit/GenericUnit.sol";
import { GenericVault } from "../src/vault/GenericVault.sol";
import { IYieldDistributor } from "../src/interfaces/IYieldDistributor.sol";
import { OneInchSwapper, IOneInchAggregationRouterLike } from "../src/periphery/swapper/OneInchSwapper.sol";

import { BaseScript } from "./Base.s.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * forge script script/Deploy.s.sol:Deploy --broadcast --verify
 */

contract Deploy is BaseScript {
    struct ControllerRoles {
        address admin;
        address configManager;
        address emergencyManager;
        address priceFeedManager;
        address vaultManager;
        address peripheryManager;
        address rebalancingManager;
        address yieldManager;
        address rewardsManager;
    }

    struct ControllerEntities {
        address yieldDistributor;
        address rewardsCollector;
    }

    struct ControllerOperators {
        address proxyAdmin;
        address swapperOwner;
        address vaultOwner;
    }

    struct GenericUsdOperators {
        address proxyAdmin;
    }

    struct ExternalAddresses {
        address usdc;
        address usdt;
        address usdcStrategy;
        address usdtStrategy;
        address usdcPriceFeed;
        address usdtPriceFeed;
        address oneInchRouter;
    }

    struct Deployment {
        Controller controllerImpl;
        Controller controller;
        GenericUnit gunit;
        GenericUSD gusdImpl;
        GenericUSD gusd;
        OneInchSwapper swapper;
        GenericVault usdcVault;
        GenericVault usdtVault;
    }

    function run() public broadcast {
        ControllerRoles memory controllerRoles = _controllerRoles();
        ControllerEntities memory controllerEntities = _controllerEntities();
        ControllerOperators memory controllerOperators = _controllerOperators();
        GenericUsdOperators memory gusdOperators = _gusdOperators();
        ExternalAddresses memory externalAddresses = _externalAddresses();
        Deployment memory deployment = Deployment({
            controllerImpl: Controller(address(0)),
            controller: Controller(address(0)),
            gunit: GenericUnit(address(0)),
            gusdImpl: GenericUSD(address(0)),
            gusd: GenericUSD(address(0)),
            swapper: OneInchSwapper(address(0)),
            usdcVault: GenericVault(address(0)),
            usdtVault: GenericVault(address(0))
        });

        address deployer = broadcaster;
        address finalAdmin = controllerRoles.admin;
        require(finalAdmin != address(0), "Deploy: admin is zero");

        console2.log("Active chain id:", block.chainid);

        // Deploy
        deployment.controllerImpl = new Controller();
        deployment.controller = Controller(
            address(
                new TransparentUpgradeableProxy(address(deployment.controllerImpl), controllerOperators.proxyAdmin, "")
            )
        );
        deployment.gunit = new GenericUnit(address(deployment.controller), "Generic Unit USD", "GU_USD");

        deployment.swapper = new OneInchSwapper(
            controllerOperators.swapperOwner, IOneInchAggregationRouterLike(externalAddresses.oneInchRouter)
        );

        deployment.controller
            .initialize(
                deployer,
                deployment.gunit,
                controllerEntities.rewardsCollector,
                deployment.swapper,
                IYieldDistributor(controllerEntities.yieldDistributor)
            );

        deployment.gusdImpl = new GenericUSD();
        deployment.gusd = GenericUSD(
            address(
                new TransparentUpgradeableProxy(
                    address(deployment.gusdImpl),
                    gusdOperators.proxyAdmin,
                    abi.encodeCall(GenericUSD.initialize, (deployment.gunit))
                )
            )
        );

        // Allow the broadcaster to execute setup actions gated by role checks.
        deployment.controller.grantRole(deployment.controller.PRICE_FEED_MANAGER_ROLE(), deployer);
        deployment.controller.grantRole(deployment.controller.VAULT_MANAGER_ROLE(), deployer);

        deployment.controller
            .setPriceFeed(
                externalAddresses.usdc, IChainlinkAggregatorLike(externalAddresses.usdcPriceFeed), 86_400 seconds
            );
        deployment.controller
            .setPriceFeed(
                externalAddresses.usdt, IChainlinkAggregatorLike(externalAddresses.usdtPriceFeed), 86_400 seconds
            );

        deployment.usdcVault = new GenericVault(
            IERC20(externalAddresses.usdc),
            deployment.controller,
            IERC4626(externalAddresses.usdcStrategy),
            controllerOperators.vaultOwner
        );
        deployment.usdtVault = new GenericVault(
            IERC20(externalAddresses.usdt),
            deployment.controller,
            IERC4626(externalAddresses.usdtStrategy),
            controllerOperators.vaultOwner
        );

        deployment.controller
            .addVault(address(deployment.usdcVault), BaseController.VaultSettings(1_000_000e18, 0, 10_000), true);
        deployment.controller
            .addVault(address(deployment.usdtVault), BaseController.VaultSettings(1_000_000e18, 0, 10_000), true);

        // Setup
        // // Controller
        deployment.controller.grantRole(deployment.controller.CONFIG_MANAGER_ROLE(), controllerRoles.configManager);
        deployment.controller
            .grantRole(deployment.controller.EMERGENCY_MANAGER_ROLE(), controllerRoles.emergencyManager);
        deployment.controller
            .grantRole(deployment.controller.PRICE_FEED_MANAGER_ROLE(), controllerRoles.priceFeedManager);
        deployment.controller.grantRole(deployment.controller.VAULT_MANAGER_ROLE(), controllerRoles.vaultManager);
        deployment.controller
            .grantRole(deployment.controller.PERIPHERY_MANAGER_ROLE(), controllerRoles.peripheryManager);
        deployment.controller
            .grantRole(deployment.controller.REBALANCING_MANAGER_ROLE(), controllerRoles.rebalancingManager);
        deployment.controller.grantRole(deployment.controller.YIELD_MANAGER_ROLE(), controllerRoles.yieldManager);
        deployment.controller.grantRole(deployment.controller.REWARDS_MANAGER_ROLE(), controllerRoles.rewardsManager);

        if (controllerRoles.priceFeedManager != deployer) {
            deployment.controller.revokeRole(deployment.controller.PRICE_FEED_MANAGER_ROLE(), deployer);
        }

        if (controllerRoles.vaultManager != deployer) {
            deployment.controller.revokeRole(deployment.controller.VAULT_MANAGER_ROLE(), deployer);
        }

        if (finalAdmin != deployer) {
            deployment.controller.grantRole(deployment.controller.DEFAULT_ADMIN_ROLE(), finalAdmin);
            deployment.controller.revokeRole(deployment.controller.DEFAULT_ADMIN_ROLE(), deployer);
        }

        console2.log("=== Deployment Summary ===");

        console2.log("-- Controller Components --");
        console2.log("Controller impl:", address(deployment.controllerImpl));
        console2.log("Controller proxy:", address(deployment.controller));
        console2.log("Generic Unit token:", address(deployment.gunit));
        console2.log("GUSD token impl:", address(deployment.gusdImpl));
        console2.log("GUSD token:", address(deployment.gusd));
        console2.log("OneInch swapper:", address(deployment.swapper));

        console2.log("-- Vaults --");
        console2.log("USDC vault:", address(deployment.usdcVault));
        console2.log("USDT vault:", address(deployment.usdtVault));

        console2.log("-- External Addresses --");
        console2.log("USDC token:", externalAddresses.usdc);
        console2.log("USDT token:", externalAddresses.usdt);
        console2.log("USDC strategy:", externalAddresses.usdcStrategy);
        console2.log("USDT strategy:", externalAddresses.usdtStrategy);
        console2.log("USDC price feed:", externalAddresses.usdcPriceFeed);
        console2.log("USDT price feed:", externalAddresses.usdtPriceFeed);
        console2.log("1inch router:", externalAddresses.oneInchRouter);

        console2.log("-- Controller Operators --");
        console2.log("Proxy admin:", controllerOperators.proxyAdmin);
        console2.log("Swapper owner:", controllerOperators.swapperOwner);
        console2.log("Vault owner:", controllerOperators.vaultOwner);

        console2.log("-- Controller Entities --");
        console2.log("Rewards collector:", controllerEntities.rewardsCollector);
        console2.log("Yield distributor:", controllerEntities.yieldDistributor);

        console2.log("-- Controller Roles --");
        console2.log("Admin:", controllerRoles.admin);
        console2.log("Config manager:", controllerRoles.configManager);
        console2.log("Emergency manager:", controllerRoles.emergencyManager);
        console2.log("Price feed manager:", controllerRoles.priceFeedManager);
        console2.log("Vault manager:", controllerRoles.vaultManager);
        console2.log("Periphery manager:", controllerRoles.peripheryManager);
        console2.log("Rebalancing manager:", controllerRoles.rebalancingManager);
        console2.log("Yield manager:", controllerRoles.yieldManager);
        console2.log("Rewards manager:", controllerRoles.rewardsManager);
    }

    function _controllerRoles() internal view returns (ControllerRoles memory roles) {
        roles = ControllerRoles({
            admin: vm.envAddress("CONTROLLER_ADMIN"),
            configManager: vm.envAddress("CONTROLLER_CONFIG_MANAGER"),
            emergencyManager: vm.envAddress("CONTROLLER_EMERGENCY_MANAGER"),
            priceFeedManager: vm.envAddress("CONTROLLER_PRICE_FEED_MANAGER"),
            vaultManager: vm.envAddress("CONTROLLER_VAULT_MANAGER"),
            peripheryManager: vm.envAddress("CONTROLLER_PERIPHERY_MANAGER"),
            rebalancingManager: vm.envAddress("CONTROLLER_REBALANCING_MANAGER"),
            yieldManager: vm.envAddress("CONTROLLER_YIELD_MANAGER"),
            rewardsManager: vm.envAddress("CONTROLLER_REWARDS_MANAGER")
        });
    }

    function _controllerEntities() internal view returns (ControllerEntities memory entities) {
        entities = ControllerEntities({
            yieldDistributor: vm.envAddress("CONTROLLER_YIELD_DISTRIBUTOR"),
            rewardsCollector: vm.envAddress("CONTROLLER_REWARDS_COLLECTOR")
        });
    }

    function _controllerOperators() internal view returns (ControllerOperators memory operators) {
        operators = ControllerOperators({
            proxyAdmin: vm.envAddress("CONTROLLER_PROXY_ADMIN"),
            swapperOwner: vm.envAddress("CONTROLLER_SWAPPER_OWNER"),
            vaultOwner: vm.envAddress("CONTROLLER_VAULT_OWNER")
        });
    }

    function _gusdOperators() internal view returns (GenericUsdOperators memory operators) {
        operators = GenericUsdOperators({ proxyAdmin: vm.envAddress("GUSD_PROXY_ADMIN") });
    }

    function _externalAddresses() internal view returns (ExternalAddresses memory addresses) {
        addresses = ExternalAddresses({
            usdc: vm.envAddress("USDC_TOKEN"),
            usdt: vm.envAddress("USDT_TOKEN"),
            usdcStrategy: vm.envAddress("USDC_STRATEGY"),
            usdtStrategy: vm.envAddress("USDT_STRATEGY"),
            usdcPriceFeed: vm.envAddress("USDC_PRICE_FEED"),
            usdtPriceFeed: vm.envAddress("USDT_PRICE_FEED"),
            oneInchRouter: vm.envAddress("ONE_INCH_ROUTER")
        });
    }
}
