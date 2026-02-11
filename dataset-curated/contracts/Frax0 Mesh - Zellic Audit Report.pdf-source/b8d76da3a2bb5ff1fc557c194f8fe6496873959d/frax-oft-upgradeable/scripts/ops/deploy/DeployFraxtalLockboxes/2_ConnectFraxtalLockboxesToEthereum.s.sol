// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// forge script scripts/ops/deploy/DeployFraxtalLockboxes/2_ConnectFraxtalLockboxesToEthereum.s.sol --rpc-url https://rpc.frax.com
contract ConnectFraxtalLockboxesToEthereum is DeployFraxOFTProtocol {
    using Strings for uint256;

    L0Config[] public ethConfigArray;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, '/scripts/ops/deploy/DeployFraxtalLockboxes/txs/');

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    function run() public override {
        // Align two lockboxes to [frxETH, sfrxETH, FXS, FPI]
        delete fraxtalLockboxes;
        fraxtalLockboxes.push(fraxtalFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalSFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalFraxLockbox);
        fraxtalLockboxes.push(fraxtalFpiLockbox);

        delete ethLockboxes;
        ethLockboxes.push(ethFrxEthLockbox);
        ethLockboxes.push(ethSFrxEthLockbox);
        ethLockboxes.push(ethFraxLockbox);
        ethLockboxes.push(ethFpiLockbox);

        // populate ethConfigArray with length 1 of eth config
        for (uint256 c=0; c<legacyConfigs.length; c++) {
            if (legacyConfigs[c].chainid == 1) {
                ethConfigArray.push(legacyConfigs[c]);
            }
        }
        require(ethConfigArray.length == 1, "ethConfigArray.length != 1");

        setupSource();
        setupDestinations();
    }

    function setupSource() public override simulateAndWriteTxs(broadcastConfig) {
        setupEvms();

        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: fraxtalLockboxes,
            _configs: ethConfigArray
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: fraxtalLockboxes,
            _configs: ethConfigArray
        });
    }

    function setupEvms() public override {
        setEvmEnforcedOptions({
            _connectedOfts: fraxtalLockboxes,
            _configs: ethConfigArray
        });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({
            _connectedOfts: fraxtalLockboxes,
            _peerOfts: ethLockboxes,
            _configs: ethConfigArray
        });
    }

    function setupDestinations() public override {
        for (uint256 i=0; i<ethConfigArray.length; i++) {
            setupDestination({
                _connectedConfig: ethConfigArray[i]
            });
        }
    }

    function setupDestination(
        L0Config memory _connectedConfig
    ) public override simulateAndWriteTxs(_connectedConfig) {
        setEvmEnforcedOptions({
            _connectedOfts: ethLockboxes,
            _configs: broadcastConfigArray
        });

        setEvmPeers({
            _connectedOfts: ethLockboxes,
            _peerOfts: fraxtalLockboxes,
            _configs: broadcastConfigArray
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: ethLockboxes,
            _configs: broadcastConfigArray
        });

        setLibs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: ethLockboxes,
            _configs: broadcastConfigArray
        });
    }

    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");

        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address peerOft = _peerOfts[o];

            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {
                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(peerOft)
                });
            }
        }
    }
}