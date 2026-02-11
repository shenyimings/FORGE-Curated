// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {FrxUSDOFTUpgradeable} from "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";
import {SFrxUSDOFTUpgradeable} from "contracts/frxUsd/SFrxUSDOFTUpgradeable.sol";


/// @dev craft tx to upgrade the FRAX / sFRAX OFT with the new name & symbol
/// @dev forge script scripts/ops/UpgradeFrxUsd/5b_UpgradeOFTMetadata.s.sol --rpc-url https://xlayerrpc.okx.com
/// @dev forge script scripts/ops/UpgradeFrxUsd/5b_UpgradeOFTMetadata.s.sol --rpc-url https://mainnet.mode.network
/// @dev forge script scripts/ops/UpgradeFrxUsd/5b_UpgradeOFTMetadata.s.sol --rpc-url https://twilight-crimson-grass.sei-pacific.quiknode.pro/1fe7cb5c6950df0f3ebceead37f8eefdf41ddbe9
contract UpgradeOFTMetadata is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    /// @dev these change per chain
    address public frxUsdImplementation;
    address public sfrxUsdImplementation;

    constructor() {
        /// @dev declared in BaseL0Script.sol, already deployed
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;

        if (block.chainid == 34443) {
            // mode
            frxUsdImplementation = 0xEEdd3A0DDDF977462A97C1F0eBb89C3fbe8D084B;
            sfrxUsdImplementation = 0x5aDdD7c2e5D7526fdcbd887bE09F0D6cB14bea2F;
        } else if (block.chainid == 1329) {
            // sei
            frxUsdImplementation = 0x8c65aa3215bd20DBe20374BB5d9AaE891973D0d6;
            sfrxUsdImplementation = 0x8f6F4359090BbF65938392874Cac44dcE165A285;
        } else {
            // xlayer
            frxUsdImplementation = 0xcB73b257b4d3b7e984abC7f49eEe2980A22E0585;
            sfrxUsdImplementation = 0x47c9756489Cf57F2dfD2f134c59d7683E25CfeBa;
        }
    }

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/UpgradeFrxUsd/txs/");
        string memory name = string.concat("5b_UpgradeOFTMetadata-", broadcastConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    function run() public override {
        upgradeOfts();
    }

    function upgradeOfts() public simulateAndWriteTxs(broadcastConfig) {
        upgradeOft({
            _oft: proxyFrxUsdOft,
            _implementation: frxUsdImplementation,
            _name: "Frax USD",
            _symbol: "frxUSD"
        });
        upgradeOft({
            _oft: proxySFrxUsdOft,
            _implementation: sfrxUsdImplementation,
            _name: "Staked Frax USD",
            _symbol: "sfrxUSD"
        });
    }

    function upgradeOft(
        address _oft,
        address _implementation,
        string memory _name,
        string memory _symbol
    ) public {
        uint256 supplyBefore = IERC20(_oft).totalSupply();
        require(supplyBefore > 0, "Supply before == 0");

        bytes memory upgrade = abi.encodeCall(
            ProxyAdmin.upgrade,
            (
                TransparentUpgradeableProxy(payable(_oft)),
                _implementation
            )
        );
        (bool success, ) = proxyAdmin.call(upgrade);
        require(success, "Unable to upgrade proxy");

        // state checks
        require(supplyBefore == IERC20(_oft).totalSupply(), "total supply changed");
        require(isStringEqual(_name, IERC20Metadata(_oft).name()), "name not changed");
        require(isStringEqual(_symbol, IERC20Metadata(_oft).symbol()), "symbol not changed");

        // make sure contract cannot be re-initialized
        bytes memory initialize = abi.encodeCall(
            FraxOFTUpgradeable.initialize,
            (
                "Mock name", "mName", address(1)
            )
        );
        (success, ) = _oft.call(initialize);
        require(!success, "should not be able to initialize");

        serializedTxs.push(
            SerializedTx({
                name: "upgrade",
                to: proxyAdmin,
                value: 0,
                data: upgrade
            })
        );
    }
}