// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { DeployMUSDBase } from "../../script/deploy/DeployMUSDBase.sol";

import { MUSDUpgrade } from "../utils/Mocks.sol";

contract DeployTests is DeployMUSDBase, Test {
    uint256 public mainnetFork;
    uint256 public lineaFork;

    address public constant DEPLOYER = 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB; // M0 deployer address

    address public yieldRecipient = makeAddr("yieldRecipient");
    address public admin = makeAddr("admin");
    address public freezeManager = makeAddr("freezeManager");
    address public yieldRecipientManager = makeAddr("yieldRecipientManager");
    address public pauser = makeAddr("pauser");
    address public forcedTransferManager = makeAddr("forcedTransferManager");

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        lineaFork = vm.createFork(vm.envString("LINEA_RPC_URL"));
    }

    /* ============ Deploy ============ */

    function testFork_deployEthereumMainnet() external {
        vm.selectFork(mainnetFork);

        vm.deal(DEPLOYER, 100 ether);

        vm.startPrank(DEPLOYER);

        (, address proxy, ) = _deployMUSD(
            DEPLOYER,
            M_TOKEN,
            SWAP_FACILITY,
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser,
            forcedTransferManager
        );

        vm.stopPrank();

        assertEq(proxy, _getCreate3Address(DEPLOYER, _computeSalt(DEPLOYER, "MUSD")));
    }

    function testFork_deployLineaMainnet() external {
        vm.selectFork(lineaFork);

        vm.deal(DEPLOYER, 100 ether);

        vm.startPrank(DEPLOYER);

        (, address proxy, ) = _deployMUSD(
            DEPLOYER,
            M_TOKEN,
            SWAP_FACILITY,
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser,
            forcedTransferManager
        );

        vm.stopPrank();

        assertEq(proxy, _getCreate3Address(DEPLOYER, _computeSalt(DEPLOYER, "MUSD")));
    }

    /* ============ Upgrade ============ */

    function testFork_upgradeEthereumMainnet() external {
        vm.selectFork(mainnetFork);

        vm.deal(DEPLOYER, 100 ether);

        (, address proxy, ) = _deployMUSD(
            DEPLOYER,
            M_TOKEN,
            SWAP_FACILITY,
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser,
            forcedTransferManager
        );

        UnsafeUpgrades.upgradeProxy(proxy, address(new MUSDUpgrade()), "", admin);

        assertEq(MUSDUpgrade(proxy).bar(), 1);
    }

    function testFork_upgradeLineaMainnet() external {
        vm.selectFork(lineaFork);

        vm.deal(DEPLOYER, 100 ether);

        (, address proxy, ) = _deployMUSD(
            DEPLOYER,
            M_TOKEN,
            SWAP_FACILITY,
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser,
            forcedTransferManager
        );

        UnsafeUpgrades.upgradeProxy(proxy, address(new MUSDUpgrade()), "", admin);

        assertEq(MUSDUpgrade(proxy).bar(), 1);
    }
}
