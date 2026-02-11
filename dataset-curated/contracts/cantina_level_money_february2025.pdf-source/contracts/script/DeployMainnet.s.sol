// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "./DeploymentUtils.s.sol";
import "forge-std/Script.sol";
import {lvlUSD} from "../src/lvlUSD.sol";
import {IlvlUSD} from "../src/interfaces/IlvlUSD.sol";
import "../src/interfaces/ILevelMinting.sol";
import {LevelMinting} from "../src/LevelMinting.sol";

contract DeployMainnet is Script, DeploymentUtils {
    struct Contracts {
        // E-tokens
        lvlUSD levelUSDToken;
        // E-contracts
        LevelMinting levelMintingContract;
    }

    struct Configuration {
        // Roles
        bytes32 LevelMinterRole;
    }

    address public constant ZERO_ADDRESS = address(0);
    uint256 public constant MAX_LVLUSD_MINT_PER_BLOCK = 500_000e18;
    uint256 public constant MAX_LVLUSD_REDEEM_PER_BLOCK = 500_000e18;

    address public constant SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address public constant MAINNET_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address public constant BNB_USDT = 0x55d398326f99059fF775485246999027B3197955;
    address public constant BNB_USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;

    address public constant BNB_USDT_CHAINLINK_ORACLE = 0xB97Ad0E74fa7d920791E90258A6E2085088b4320;
    address public constant BNB_USDC_CHAINLINK_ORACLE = 0x51597f405303C4377E36123cBc172b13269EA163;

    address public constant SEPOLIA_CUSTODIAN = 0xe9AF0428143E4509df4379Bd10C4850b223F2EcB;

    address public constant ADMIN_MULTISIG = 0x343ACce723339D5A417411D8Ff57fde8886E91dc;
    address public constant OPERATOR_MULTISIG = 0xcEa14C3e9Afc5822d44ADe8d006fCFBAb60f7a21;

    address public constant HEXAGATE_GATEKEEPER_1 = 0xA7367eCE6AeA6EA5D775867Aa9B56F5f35B202Fe;
    address public constant HEXAGATE_GATEKEEPER_2 = 0x1557C8a68110D17cf19Bd7451972ea954B689ed6;

    function run() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployment(deployerPrivateKey);
    }

    function deployment(uint256 deployerPrivateKey) public returns (Contracts memory) {
        address deployerAddress = vm.addr(deployerPrivateKey);
        Contracts memory contracts;

        vm.startBroadcast(deployerPrivateKey);

        contracts.levelUSDToken = new lvlUSD(deployerAddress);
        IlvlUSD ilvlUSD = IlvlUSD(address(contracts.levelUSDToken));

        // Level Minting
        address[] memory assets = new address[](1);
        // assets[0] = address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        // assets[1] = address(0xae78736Cd615f374D3085123A210448E74Fc6393);
        assets[0] = address(MAINNET_USDT);
        // assets[3] = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        // assets[4] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        // assets[5] = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

        address[] memory oracles = new address[](1);
        oracles[0] = address(0);

        address[] memory reserves = new address[](1);
        // reserve address
        reserves[0] = address(deployerAddress);

        uint256[] memory _ratios = new uint256[](1);
        _ratios[0] = uint256(10000);

        contracts.levelMintingContract = new LevelMinting(
            ilvlUSD,
            assets,
            oracles,
            reserves,
            _ratios,
            deployerAddress,
            MAX_LVLUSD_MINT_PER_BLOCK,
            MAX_LVLUSD_REDEEM_PER_BLOCK
        );

        // Set minter role
        contracts.levelUSDToken.setMinter(address(contracts.levelMintingContract));

        //------- Setup LevelMinting ---------------
        // Allowlist redemptions and set operator, admin, and hot wallet as redeemers
        contracts.levelMintingContract.setCheckRedeemerRole(true);
        contracts.levelMintingContract.grantRole(keccak256("REDEEMER_ROLE"), ADMIN_MULTISIG);
        contracts.levelMintingContract.grantRole(keccak256("REDEEMER_ROLE"), OPERATOR_MULTISIG);
        contracts.levelMintingContract.grantRole(keccak256("REDEEMER_ROLE"), 0xEcc67F2c1A182908acbf655B3b3ABA85a177B825);

        // Give gatekeeper role to operator, admin, and Hexagate addresses
        contracts.levelMintingContract.grantRole(keccak256("GATEKEEPER_ROLE"), ADMIN_MULTISIG);
        contracts.levelMintingContract.grantRole(keccak256("GATEKEEPER_ROLE"), OPERATOR_MULTISIG);
        contracts.levelMintingContract.grantRole(keccak256("GATEKEEPER_ROLE"), HEXAGATE_GATEKEEPER_1);
        contracts.levelMintingContract.grantRole(keccak256("GATEKEEPER_ROLE"), HEXAGATE_GATEKEEPER_2);

        // Set self as the only reserve address
        contracts.levelMintingContract.removeReserveAddress(deployerAddress);
        contracts.levelMintingContract.addReserveAddress(address(contracts.levelMintingContract));
        address[] memory newReserves = new address[](1);
        newReserves[0] = address(contracts.levelMintingContract);
        contracts.levelMintingContract.setRoute(newReserves, _ratios);

        // Enable instant redemptions
        contracts.levelMintingContract.setCooldownDuration(0);

        //------- Finish LevelMinting setup ---------------

        // Transfer admin
        contracts.levelMintingContract.transferAdmin(ADMIN_MULTISIG);
        contracts.levelUSDToken.transferAdmin(ADMIN_MULTISIG);

        console.log("Level Deployed");
        vm.stopBroadcast();

        // Logs
        console.log("=====> Minting Level contracts deployed ....");
        console.log(
            "levelUSD                          : https://etherscan.io/address/%s", address(contracts.levelUSDToken)
        );
        console.log(
            "Level Minting                  : https://etherscan.io/address/%s", address(contracts.levelMintingContract)
        );
        return contracts;
    }
}
