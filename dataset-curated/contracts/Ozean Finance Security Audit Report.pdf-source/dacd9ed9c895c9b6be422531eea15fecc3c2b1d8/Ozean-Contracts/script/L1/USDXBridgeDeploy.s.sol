// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ScriptUtils} from "script/utils/ScriptUtils.sol";
import {USDXBridge} from "src/L1/USDXBridge.sol";
import {OptimismPortal} from "optimism/src/L1/OptimismPortal.sol";
import {SystemConfig} from "optimism/src/L1/SystemConfig.sol";

contract USDXBridgeDeploy is ScriptUtils {
    USDXBridge public usdxBridge;

    address public hexTrust;
    address public usdc;
    address public usdt;
    address public dai;
    OptimismPortal public optimismPortal;
    SystemConfig public systemConfig;

    /// @dev Used in testing environment, unnecessary for mainnet deployment
    function setUp(
        address _hexTrust,
        address _usdc,
        address _usdt,
        address _dai,
        OptimismPortal _optimismPortal,
        SystemConfig _systemConfig
    ) external {
        hexTrust = _hexTrust;
        usdc = _usdc;
        usdt = _usdt;
        dai = _dai;
        optimismPortal = _optimismPortal;
        systemConfig = _systemConfig;
    }

    function run() external broadcast {
        address[] memory stablecoins = new address[](3);
        stablecoins[0] = usdc;
        stablecoins[1] = usdt;
        stablecoins[2] = dai;
        uint256[] memory depositCaps = new uint256[](3);
        depositCaps[0] = 1e30;
        depositCaps[1] = 1e30;
        depositCaps[2] = 1e30;
        usdxBridge = new USDXBridge(hexTrust, optimismPortal, systemConfig, stablecoins, depositCaps);
    }
}
