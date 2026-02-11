// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ScriptUtils} from "script/utils/ScriptUtils.sol";
import {LGEMigrationV1} from "src/L1/LGEMigrationV1.sol";

contract LGEMigrationDeploy is ScriptUtils {
    address public hexTrust = makeAddr("HEX_TRUST");
    LGEMigrationV1 public lgeMigration;
    address public l1StandardBridge;
    address public l1LidoTokensBridge;
    address public usdxBridge;
    address public lgeStaking;
    address public usdc;
    address public wstETH;
    address[] public l1Addresses;
    address[] public l2Addresses;

    /// @dev Used in testing environment, unnecessary for mainnet deployment
    function setUp(
        address _hexTrust,
        address _l1StandardBridge,
        address _l1LidoTokensBridge,
        address _usdxBridge,
        address _lgeStaking,
        address _usdc,
        address _wstETH,
        address[] memory _l1Addresses,
        address[] memory _l2Addresses
    ) external {
        hexTrust = _hexTrust;
        l1StandardBridge = _l1StandardBridge;
        l1LidoTokensBridge = _l1LidoTokensBridge;
        usdxBridge = _usdxBridge;
        lgeStaking = _lgeStaking;
        usdc = _usdc;
        wstETH = _wstETH;
        l1Addresses = _l1Addresses;
        l2Addresses = _l2Addresses;
    }

    function run() external broadcast {
        lgeMigration = new LGEMigrationV1(
            hexTrust,
            l1StandardBridge,
            l1LidoTokensBridge,
            usdxBridge,
            lgeStaking,
            usdc,
            wstETH,
            l1Addresses,
            l2Addresses
        );
    }
}
