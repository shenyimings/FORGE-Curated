// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev Make proxy network fully operable, re-open legacy network to run independently
// forge script scripts/ops/UpgradeFrxUsd/7_SetOFTLibs.s.sol --rpc-url https://rpc.frax.com
contract SetOFTLibs is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;


    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/UpgradeFrxUsd/txs/");
        string memory name = string.concat("7_SetOFTLibs-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    /// @dev setup all (s)frxUSD configs across all chains
    function run() public override {
        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        
        delete proxyOfts;
        proxyOfts.push(frxUsdOft);
        proxyOfts.push(sfrxUsdOft);

        delete legacyOfts;
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX
        legacyOfts.push(0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E); // sFRAX

        delete fraxtalLockboxes;
        fraxtalLockboxes.push(0x96A394058E2b84A89bac9667B19661Ed003cF5D4); // frxUSD
        fraxtalLockboxes.push(0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361); // sfrxUSD

        // deploySource();
        // setupSource();
        setupDestinations();
    }

    function setupDestinations() public override {
        setupLegacyDestinations();
        setupProxyDestinations();
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

    // (Fraxtal, proxy OFTs): set legacy peer to 0
    // (Fraxtal): Connect to (Mode, Sei, Xlayer
    // (Mode, Sei, XLayer): connect to new OFT peer, fraxtal lockbox
    function setupProxyDestinations() public override {
        for (uint256 c=0; c<proxyConfigs.length; c++) {

            // All Proxy
            if (proxyConfigs[c].chainid != 252) {
                setupProxyDestination({
                    _connectedConfig: proxyConfigs[c],
                    _connectedOfts: proxyOfts
                });
            } else if (proxyConfigs[c].chainid == 252) {
                setupProxyDestination({
                    _connectedConfig: proxyConfigs[c],
                    _connectedOfts: fraxtalLockboxes
                });
            }
        }
    }

    // Set up all config for (s)frxUSD across all proxy setups
    // change _configs from broadcastConfigArray to proxyConfigs
    function setupProxyDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public simulateAndWriteTxs(_connectedConfig) {
        setLibs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: proxyConfigs
        });
    }

}