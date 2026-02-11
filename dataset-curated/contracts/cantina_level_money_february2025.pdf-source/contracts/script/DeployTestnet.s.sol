// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "./DeploymentUtils.s.sol";
import "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20 as IERC20v4} from "@openzeppelin-4.9.0/contracts/token/ERC20/IERC20.sol";

import {lvlUSD} from "../src/lvlUSD.sol";
import {IlvlUSD} from "../src/interfaces/IlvlUSD.sol";
import "../src/interfaces/ILevelMinting.sol";
import "../src/interfaces/IStakedlvlUSD.sol";

import {LevelMinting} from "../src/LevelMinting.sol";
import {EigenlayerReserveManager} from "../src/reserve/LevelEigenlayerReserveManager.sol";
import {StakedlvlUSD} from "../src/StakedlvlUSD.sol";

contract DeployTestnet is Script, DeploymentUtils {
    struct Contracts {
        lvlUSD levelUSDToken;
        LevelMinting levelMinting;
        StakedlvlUSD stakedlvlUSD;
        EigenlayerReserveManager levelBaseReserveManager;
    }

    struct Configuration {
        // Roles
        bytes32 LevelMinterRole;
        bytes32 LevelRedeemerRole;
    }

    address public constant ZERO_ADDRESS = address(0);
    uint256 public constant MAX_LVLUSD_MINT_PER_BLOCK = 100_000e18;
    uint256 public constant MAX_LVLUSD_REDEEM_PER_BLOCK = 100_000e18;

    address public constant SEPOLIA_AAVE_USDT =
        0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;

    address public constant SEPOLIA_USDC =
        0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    address public constant SEPOLIA_ADMIN =
        0x74C3dC2F48b9cc5f167B0C8AE09FbbDc6315f519;

    address public constant SEPOLIA_CUSTODIAN =
        0x74C3dC2F48b9cc5f167B0C8AE09FbbDc6315f519;

    address public constant SEPOLIA_AAVE_POOL_PROXY =
        0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;

    function run() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployment(deployerPrivateKey);
    }

    function deployment(
        uint256 deployerPrivateKey
    ) public returns (Contracts memory) {
        address deployerAddress = vm.addr(deployerPrivateKey);
        Contracts memory contracts;

        vm.startBroadcast(deployerPrivateKey);

        contracts.levelUSDToken = new lvlUSD(deployerAddress);
        IlvlUSD _lvlUSD = IlvlUSD(address(contracts.levelUSDToken));
        // stakedlvlUSD
        contracts.stakedlvlUSD = new StakedlvlUSD(
            IERC20v4(address(contracts.levelUSDToken)),
            SEPOLIA_ADMIN,
            SEPOLIA_ADMIN
        );

        // LevelReserveManager
        contracts.levelBaseReserveManager = new EigenlayerReserveManager(
            IlvlUSD(address(contracts.levelUSDToken)),
            SEPOLIA_ADMIN,
            SEPOLIA_ADMIN,
            SEPOLIA_ADMIN,
            contracts.stakedlvlUSD,
            SEPOLIA_ADMIN,
            SEPOLIA_ADMIN,
            "operator1"
        );

        // Level Minting
        address[] memory assets = new address[](2);
        assets[0] = address(SEPOLIA_AAVE_USDT);
        assets[1] = address(SEPOLIA_USDC);

        address[] memory oracles = new address[](2);
        // https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
        oracles[0] = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
        oracles[1] = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;

        address[] memory reserves = new address[](1);
        reserves[0] = address(contracts.levelBaseReserveManager);

        uint256[] memory _ratios = new uint256[](1);
        _ratios[0] = uint256(10000);

        contracts.levelMinting = new LevelMinting(
            _lvlUSD,
            assets,
            oracles,
            reserves,
            _ratios,
            deployerAddress,
            MAX_LVLUSD_MINT_PER_BLOCK,
            MAX_LVLUSD_REDEEM_PER_BLOCK
        );

        // Set minter role
        contracts.levelUSDToken.setMinter(address(contracts.levelMinting));

        // StakedlvlUSD
        contracts.stakedlvlUSD = new StakedlvlUSD(
            contracts.levelUSDToken,
            SEPOLIA_ADMIN,
            SEPOLIA_ADMIN
        );

        // LevelReserveManager
        contracts.levelBaseReserveManager = new EigenlayerReserveManager(
            IlvlUSD(address(contracts.levelUSDToken)),
            SEPOLIA_ADMIN,
            SEPOLIA_ADMIN,
            SEPOLIA_ADMIN,
            IStakedlvlUSD(address(contracts.stakedlvlUSD)),
            SEPOLIA_ADMIN,
            SEPOLIA_ADMIN,
            "operator1"
        );

        console.log("Level Deployed");
        vm.stopBroadcast();

        // Logs
        console.log("=====> Minting Level contracts deployed ....");
        console.log(
            "levelUSD                          : https://sepolia.etherscan.io/address/%s",
            address(contracts.levelUSDToken)
        );
        console.log(
            "Level Minting                  : https://sepolia.etherscan.io/address/%s",
            address(contracts.levelMinting)
        );
        // console.log(
        //     "StakedlvlUSD                  : https://sepolia.etherscan.io/address/%s",
        //     address(contracts.stakedlvlUSD)
        // );
        console.log(
            "LevelReserveManager                  : https://sepolia.etherscan.io/address/%s",
            address(contracts.levelBaseReserveManager)
        );
        return contracts;
    }
}
