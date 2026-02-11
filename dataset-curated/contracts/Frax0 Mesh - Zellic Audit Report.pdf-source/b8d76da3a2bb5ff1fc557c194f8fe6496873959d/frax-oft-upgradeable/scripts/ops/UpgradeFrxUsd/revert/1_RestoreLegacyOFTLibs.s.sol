// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev Resume bridging across legacy chains
// forge script scripts/ops/UpgradeFrxUsd/revert/1_RestoreLegacyOFTLibs.s.sol --rpc-url https://rpc.frax.com
contract RestoreLegacyOFTLibs is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/UpgradeFrxUsd/revert/txs/");
        string memory name = string.concat("1_RestoreLegacyOFTLibs-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    /// @dev setup all (s)frxUSD configs across all chains
    function run() public override {
        delete legacyOfts;
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX
        legacyOfts.push(0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E); // sFRAX

        // deploySource();
        // setupSource();
        setupDestinations();
    }

    function setupDestinations() public override {
        setupLegacyDestinations();
        // setupProxyDestinations();
    }

    function setupLegacyDestinations() public override {
        for (uint256 c=0; c<legacyConfigs.length; c++) {
            setupLegacyDestination({
                _connectedConfig: legacyConfigs[c],
                _connectedOfts: legacyOfts
            });
        }
    }

    // unblock legacy libs
    function setupLegacyDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public simulateAndWriteTxs(_connectedConfig) {
        // unlock sending through legacy network
        setLibs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: legacyConfigs
        });
    }


}