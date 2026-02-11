// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";


/*
Goal: wire up every chain to Solana

NOTE: assumes `nonEvmConfigs` have length of 1 and are Solana
*/

contract SetupSolana is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    function version() public virtual override pure returns (uint256, uint256, uint256) {
        return (1, 1, 0);
    }

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/SetupSolana/txs/");
        string memory name = string.concat(simulateConfig.chainid.toString(), ".json");

        return string.concat(root, name);
    }


    function run() public override {
        // to skip the proxyOfts.length == 6 requirement in _populateConnectedOfts()
        for (uint256 i=0; i<expectedProxyOfts.length; i++) {
            proxyOfts.push(expectedProxyOfts[i]);
        }

        setupSolanaDestinations();
    }

    function setupSolanaDestinations() public {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            setupSolanaDestination({
                _connectedConfig: proxyConfigs[i]
            });
        }
    }

    function setupSolanaDestination(
        L0Config memory _connectedConfig
    ) public simulateAndWriteTxs(_connectedConfig) {
        setSolanaEnforcedOptions({
            _connectedOfts: connectedOfts
        });

        // NOTE: assumes nonEvmConfigs have length of 1 and are Solana
        setNonEvmPeers({
            _connectedOfts: connectedOfts
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: connectedOfts,
            _configs: nonEvmConfigs
        });

        setLibs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: connectedOfts,
            _configs: nonEvmConfigs
        });
    }
}
