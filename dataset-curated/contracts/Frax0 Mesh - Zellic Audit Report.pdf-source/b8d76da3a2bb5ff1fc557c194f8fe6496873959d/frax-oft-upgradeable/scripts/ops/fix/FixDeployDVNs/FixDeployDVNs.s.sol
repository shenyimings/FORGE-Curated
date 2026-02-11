// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev creates 34443 files with set DVNs for all chains- 

/*
Goal: change _configs from broadcastConfigArray to all configs as setupSource uses configs.
ie: through non-removal of old arrays (https://github.com/FraxFinance/frax-oft-upgradeable/pull/11),
  the prior DVN configurations were overwritten in setupSource() with invalid broadcastConfigArray DVN addrs.
*/

contract FixDeployDVNs is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    function version() public virtual override pure returns (uint256, uint256, uint256) {
        return (1, 0, 2);
    }

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/DeployFraxOFTProtocol/txs/FixDeployDVNs/");
        string memory name = string.concat(simulateConfig.chainid.toString(), "-fixed.json");

        return string.concat(root, name);
    }

    function setUp() public override {
        super.setUp();
    }

    function run() public override {
        // deploySource();
        // setupSource();
        proxyOfts.push(0x64445f0aecC51E94aD52d8AC56b7190e764E561a);
        proxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0);
        proxyOfts.push(0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45);
        proxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df);
        setupDestinations();
    }

    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public simulateAndWriteTxs(_connectedConfig) {
        // setEnforcedOptions({
        //     _connectedOfts: _connectedOfts,
        //     _configs: broadcastConfigArray
        // });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: evmConfigs
        });

        // setPeers({
        //     _connectedOfts: _connectedOfts,
        //     _peerOfts: proxyOfts,
        //     _configs: configs
        // });
    }
}
