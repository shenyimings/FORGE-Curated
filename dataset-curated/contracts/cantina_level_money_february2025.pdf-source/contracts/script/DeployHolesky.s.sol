// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "./DeploymentUtils.s.sol";
import "forge-std/Script.sol";
import "./ContractAddresses.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20 as IERC20Old} from "@openzeppelin-4.9.0/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IlvlUSD} from "../src/interfaces/IlvlUSD.sol";
import {IStakedlvlUSD} from "../src/interfaces/IStakedlvlUSD.sol";
import {WrappedRebasingERC20} from "../src/WrappedRebasingERC20.sol";
import {LevelMinting} from "../src/LevelMinting.sol";
import {EigenlayerReserveManager} from "../src/reserve/LevelEigenlayerReserveManager.sol";
import {KarakReserveManager} from "../src/reserve/LevelKarakReserveManager.sol";
import {SymbioticReserveManager} from "../src/reserve/LevelSymbioticReserveManager.sol";
import {LevelBaseReserveManager} from "../src/reserve/LevelBaseReserveManager.sol";

import {AaveV3YieldManager} from "../src/yield/AaveV3YieldManager.sol";
import {WrappedRebasingERC20} from "../src/WrappedRebasingERC20.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {StakedlvlUSD} from "../src/StakedlvlUSD.sol";
// Deployment interfaces
import {IStrategy} from "../src/interfaces/eigenlayer/IStrategy.sol";
import {IStrategyFactory} from "../src/interfaces/eigenlayer/IStrategyFactory.sol";
import {IStrategyManager} from "../src/interfaces/eigenlayer/IStrategyManager.sol";

contract DeployHolesky is Script, DeploymentUtils, ContractAddresses {
    uint256 public chainId;

    constructor() {
        chainId = vm.envUint("CHAIN_ID");
        _initializeAddresses(chainId);
    }

    function run() public virtual {
        uint256 deployerPrivateKey = _getPrivateKey(chainId);
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deploying contracts with deployer address: %s", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // _deployStakedLvlUsd();

        // EigenlayerReserveManager eigenlayerReserveManager = _deployEigenlayerReserveManager(
        //         "operator 1"
        //     );

        // SymbioticReserveManager symbioticReserveManager = _deploySymbioticReserveManager();

        // WrappedRebasingERC20 waUsdt = _deployWrappedUsdt();
        // WrappedRebasingERC20 waUsdc = _deployWrappedUsdc();

        // AaveV3YieldManager aaveV3YieldManager = _deployAaveV3YieldManager();

        // _setupYieldManager();

        _setupReserveManager();

        console.log("=====> Contracts deployed ....");
        // _printDeployedContracts(
        //     chainId,
        //     "StakedlvlUSD",
        //     levelContracts.slvlUSD
        // );
        // _printDeployedContracts(chainId, "KarakReserveManager", levelContracts.karakReserveManager);
        _printDeployedContracts(chainId, "SymbioticReserveManager", levelContracts.symbioticReserveManager);
        // _printDeployedContracts(
        //     chainId,
        //     "EigenlayerReserveManager",
        //     levelContracts.eigenlayerReserveManager
        // );
        // _printDeployedContracts(
        //     chainId,
        //     "AaveV3YieldManager",
        //     levelContracts.aaveV3YieldManager
        // );

        // _printDeployedContracts(
        //     chainId,
        //     "Wrapped aUSDT",
        //     address(tokenContracts.waUsdt)
        // );
        // _printDeployedContracts(
        //     chainId,
        //     "Wrapped aUSDC",
        //     address(tokenContracts.waUsdc)
        // );
    }

    function _deployAaveV3YieldManager() public returns (AaveV3YieldManager) {
        if (levelContracts.aaveV3YieldManager != address(0)) {
            return AaveV3YieldManager(levelContracts.aaveV3YieldManager);
        }

        AaveV3YieldManager aaveV3YieldManager =
            new AaveV3YieldManager(IPool(aaveContracts.aavePoolProxy), levelContracts.levelAdmin);

        levelContracts.aaveV3YieldManager = address(aaveV3YieldManager);
        return aaveV3YieldManager;
    }

    function _deployEigenlayerReserveManager(string memory name) public returns (EigenlayerReserveManager) {
        if (levelContracts.eigenlayerReserveManager != address(0)) {
            return EigenlayerReserveManager(payable(levelContracts.eigenlayerReserveManager));
        }

        EigenlayerReserveManager eigenlayerReserveManager = new EigenlayerReserveManager(
            IlvlUSD(levelContracts.lvlUSD),
            eigenlayerContracts.eigenlayerDelegationManager,
            eigenlayerContracts.eigenlayerStrategyManager,
            eigenlayerContracts.eigenlayerRewardsCoordinator,
            StakedlvlUSD(address(0)),
            levelContracts.levelAdmin,
            levelContracts.levelOperator,
            name
        );
        levelContracts.eigenlayerReserveManager = address(eigenlayerReserveManager);
        return eigenlayerReserveManager;
    }

    function _deployKarakReserveManager() public returns (KarakReserveManager) {
        if (levelContracts.karakReserveManager != address(0)) {
            return KarakReserveManager(payable(levelContracts.karakReserveManager));
        }

        KarakReserveManager karakReserveManager = new KarakReserveManager(
            IlvlUSD(levelContracts.lvlUSD),
            StakedlvlUSD(levelContracts.slvlUSD),
            levelContracts.levelAdmin,
            levelContracts.levelOperator
        );

        levelContracts.karakReserveManager = address(karakReserveManager);
        return karakReserveManager;
    }

    function _deploySymbioticReserveManager() public returns (SymbioticReserveManager) {
        if (levelContracts.symbioticReserveManager != address(0)) {
            return SymbioticReserveManager(payable(levelContracts.symbioticReserveManager));
        }

        SymbioticReserveManager symbioticReserveManager = new SymbioticReserveManager(
            IlvlUSD(levelContracts.lvlUSD),
            StakedlvlUSD(levelContracts.slvlUSD),
            levelContracts.levelDeployer,
            levelContracts.levelDeployer
        );

        levelContracts.symbioticReserveManager = address(symbioticReserveManager);
        return symbioticReserveManager;
    }

    function _setupYieldManager() internal {
        AaveV3YieldManager aaveV3YieldManager = AaveV3YieldManager(levelContracts.aaveV3YieldManager);

        aaveV3YieldManager.setWrapperForToken(aaveContracts.aaveUsdt, tokenContracts.waUsdt);
        aaveV3YieldManager.setWrapperForToken(aaveContracts.aaveUsdc, tokenContracts.waUsdc);
    }

    function _setupReserveManager() internal {
        LevelBaseReserveManager lrm = LevelBaseReserveManager(payable(levelContracts.symbioticReserveManager));

        // Initiate transfer to new admin
        lrm.transferAdmin(levelContracts.levelAdmin);

        // Init yield manager
        lrm.setYieldManager(tokenContracts.usdc, levelContracts.aaveV3YieldManager);
        lrm.setYieldManager(tokenContracts.usdt, levelContracts.aaveV3YieldManager);

        lrm.approveSpender(tokenContracts.waUsdc, levelContracts.aaveV3YieldManager, 100_000_000_000 * 1e6);
        lrm.approveSpender(tokenContracts.waUsdt, levelContracts.aaveV3YieldManager, 100_000_000_000 * 1e6);

        // Allowlist other reserve managers
        lrm.setAllowlist(levelContracts.eigenlayerReserveManager, true);
        lrm.setAllowlist(levelContracts.karakReserveManager, true);

        // Set roles
        lrm.grantRole(keccak256("MANAGER_AGENT_ROLE"), levelContracts.levelOperator);
        lrm.grantRole(keccak256("PAUSER_ROLE"), levelContracts.levelAdmin);
        lrm.grantRole(keccak256("PAUSER_ROLE"), levelContracts.levelOperator);
        lrm.grantRole(keccak256("PAUSER_ROLE"), levelContracts.levelPauser);
        lrm.grantRole(keccak256("PAUSER_ROLE"), MAINNET_HEXAGATE_GATEKEEPER_1);
        lrm.grantRole(keccak256("PAUSER_ROLE"), MAINNET_HEXAGATE_GATEKEEPER_2);

        // Remove ALLOWLIST role from deployer
        lrm.revokeRole(keccak256("ALLOWLIST_ROLE"), levelContracts.levelDeployer);
        lrm.grantRole(keccak256("ALLOWLIST_ROLE"), levelContracts.levelAdmin);

        lrm.setTreasury(levelContracts.levelTreasuryReceiver);
    }

    // function _deployLevelMinting() public returns (LevelMinting) {
    //     if (levelContracts.levelMinting != address(0)) {
    //         return LevelMinting(levelContracts.levelMinting);
    //     }

    //     address mockOracle = 0xB92Fd4c5125Ec4927819e8C5dbC58ED26BB5345E;

    //     address[] memory assets = new address[](2);
    //     assets[0] = tokenContracts.usdc;
    //     assets[1] = tokenContracts.usdt;

    //     address[] memory oracles = new address[](2);
    //     oracles[0] = mockOracle;
    //     oracles[1] = mockOracle;

    //     address[] memory reserves = new address[](1);
    //     reserves[0] = 0x9C18db0640dC08C246CF9a4Ab361ae7e7358Bfa4;

    //     uint256[] memory ratios = new uint256[](1);
    //     ratios[0] = 10000;

    //     LevelMinting levelMinting = new LevelMinting(
    //         IlvlUSD(levelContracts.lvlUSD),
    //         assets,
    //         oracles,
    //         reserves,
    //         ratios,
    //         address(levelContracts.levelAdmin),
    //         // 100k lvlUSD
    //         100_000 ether,
    //         100_000 ether
    //     );
    //     levelContracts.levelMinting = address(levelMinting);
    //     return levelMinting;
    // }

    function _deployStakedLvlUsd() public returns (StakedlvlUSD) {
        if (levelContracts.slvlUSD != address(0)) {
            return StakedlvlUSD(levelContracts.slvlUSD);
        }
        StakedlvlUSD slvlUSDToken =
            new StakedlvlUSD(IERC20Old(levelContracts.lvlUSD), levelContracts.levelAdmin, levelContracts.levelAdmin);
        levelContracts.slvlUSD = address(slvlUSDToken);
        return slvlUSDToken;
    }

    function _deployWrappedUsdt() public returns (WrappedRebasingERC20) {
        if (tokenContracts.waUsdt != address(0)) {
            return WrappedRebasingERC20(tokenContracts.waUsdt);
        }

        WrappedRebasingERC20 waUsdt = _deployWrappedErc20(aaveContracts.aaveUsdt, "Level Wrapped aUSDT", "lvlwaUSDT");
        tokenContracts.waUsdt = address(waUsdt);

        _getOrCreateStrategy(tokenContracts.waUsdt);
        return waUsdt;
    }

    function _deployWrappedUsdc() public returns (WrappedRebasingERC20) {
        if (tokenContracts.waUsdc != address(0)) {
            return WrappedRebasingERC20(tokenContracts.waUsdc);
        }

        WrappedRebasingERC20 waUsdc = _deployWrappedErc20(aaveContracts.aaveUsdc, "Level Wrapped aUSDC", "lvlwaUSDC");
        tokenContracts.waUsdc = address(waUsdc);
        _getOrCreateStrategy(tokenContracts.waUsdc);
        return waUsdc;
    }

    function _deployWrappedErc20(address tokenAddress, string memory name, string memory symbol)
        public
        returns (WrappedRebasingERC20)
    {
        WrappedRebasingERC20 wrappedToken = new WrappedRebasingERC20(ERC20(tokenAddress), name, symbol);

        return wrappedToken;
    }

    function _getOrCreateStrategy(address tokenAddress) public returns (IStrategy) {
        IStrategyFactory strategyFactory = IStrategyFactory(eigenlayerContracts.eigenlayerStrategyFactory);

        IStrategy strategy = strategyFactory.deployedStrategies(IERC20(tokenAddress));
        if (address(strategy) == address(0)) {
            strategy = strategyFactory.deployNewStrategy(IERC20(tokenAddress));
        }
        return strategy;
    }
}
