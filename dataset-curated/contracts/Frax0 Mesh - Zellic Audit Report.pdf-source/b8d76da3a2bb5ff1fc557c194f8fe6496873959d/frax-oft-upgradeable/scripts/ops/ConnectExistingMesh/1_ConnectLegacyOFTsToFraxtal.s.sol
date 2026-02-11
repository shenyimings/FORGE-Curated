// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev Connect legacy (s)FRAX on Base, Blast, Metis to Fraxtal (s)frxUSD lockboxes
// forge script scripts/ops/ConnectExistingMesh/1_ConnectLegacyOFTsToFraxtal.s.sol --rpc-url https://rpc.frax.com
contract ConnectLegacyOFTsToFraxtal is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/ConnectExistingMesh/txs/");
        string memory name = string.concat("1_ConnectLegacyOFTsToFraxtal-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    /// @dev setup all (s)frxUSD configs across all chains
    function run() public override {
        // to enable passing of setEvmPeers
        frxUsdOft = address(1);
        sfrxUsdOft = address(1);

        delete legacyOfts;
        legacyOfts.push(ethFraxLockboxLegacy); // FRAX legacy OFT / lockbox
        legacyOfts.push(ethSFraxLockboxLegacy); // sFRAX legacy oft / lockbox

        delete fraxtalLockboxes;
        fraxtalLockboxes.push(fraxtalFrxUsdLockbox);
        fraxtalLockboxes.push(fraxtalSFrxUsdLockbox);

        // deploySource();
        setupSource();
        setupDestinations();
    }

    function setupSource() public override simulateAndWriteTxs(broadcastConfig) {
        /// @dev set enforced options / peers separately
        setupEvms();
        // setupNonEvms();

        /// @dev configures legacy configs as well
        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: fraxtalLockboxes,
            _configs: legacyConfigs
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: fraxtalLockboxes,
            _configs: legacyConfigs
        });

        // setPriviledgedRoles();
    }

    function setupEvms() public override {
        setEvmEnforcedOptions({
            _connectedOfts: fraxtalLockboxes,
            _configs: legacyConfigs
        });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({
            _connectedOfts: fraxtalLockboxes,
            _peerOfts: legacyOfts,
            _configs: legacyConfigs
        });
    }

    function setupDestinations() public override {
        for (uint256 c=0; c<legacyConfigs.length; c++) {
            setupLegacyDestination({
                _connectedConfig: legacyConfigs[c]
            });
        }
    }

    function setupLegacyDestination(
        L0Config memory _connectedConfig
    ) public simulateAndWriteTxs(_connectedConfig) {
        setEvmEnforcedOptions({
            _connectedOfts: legacyOfts,
            _configs: broadcastConfigArray
        });

        setEvmPeers({
            _connectedOfts: legacyOfts,
            _peerOfts: fraxtalLockboxes,
            _configs: broadcastConfigArray 
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: legacyOfts,
            _configs: broadcastConfigArray
        });

        setLibs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: legacyOfts,
            _configs: broadcastConfigArray
        });
    }


}